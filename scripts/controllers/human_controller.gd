class_name HumanController
extends Node

signal selected_unit_changed(unit_id: int)
signal input_mode_changed(mode: int)
signal target_preview_changed(
	screen_position: Vector2,
	map_position: Vector2,
	water_income: int,
	gold_income: int,
	valid: bool
)
signal bomb_target_preview_changed(
	map_position: Vector2,
	strike_type: int,
	damage_radius: float,
	reveal_radius: float,
	valid: bool,
	visible: bool
)
signal airstrike_targets_changed(
	targets: PackedVector2Array,
	damage_radius: float,
	visible: bool
)
signal airstrike_target_count_changed(selected_count: int, target_count: int)

enum InputMode {
	NORMAL,
	UNIT_SELECTED,
	AIMING_BOMB,
	AIMING_MISSILE,
	PLACING_REPLACEMENT,
}

@onready var _client_state: ClientMatchState = %ClientMatchState
@onready var _command_gateway: CommandGateway = %CommandGateway
@onready var _network_match: NetworkMatch = %NetworkMatch
@onready var _map: GameMap = %Map
@onready var _network_session: NetworkSessionService = get_node("/root/NetworkSession")

var _selected_unit_id := -1
var _input_mode: InputMode = InputMode.NORMAL
var _airstrike_targets := PackedVector2Array()


func _ready() -> void:
	pass


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion or _client_state.player.is_empty():
		return
	var mouse_position: Vector2 = (event as InputEventMouseMotion).position
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	var over_interactive_ui: bool = (
		hovered_control != null
		and hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE
	)
	_emit_target_preview(mouse_position, not over_interactive_ui)
	if _is_aiming_strike() and not _client_state.match_finished:
		_emit_strike_preview(mouse_position, not over_interactive_ui)


func _unhandled_input(event: InputEvent) -> void:
	if _client_state.player.is_empty():
		return
	if event is InputEventKey:
		_handle_debug_key(event as InputEventKey)
		return
	if _client_state.match_finished:
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	var map_position: Vector2 = _screen_to_map_position(mouse_event.position)
	if not Rect2(Vector2.ZERO, _client_state.rules.map_size).has_point(map_position):
		return
	if _is_aiming_strike():
		var selection_complete: bool = _submit_strike(map_position)
		if selection_complete:
			_emit_strike_preview(mouse_event.position, false)
			_set_input_mode(
				InputMode.UNIT_SELECTED if _selected_unit_id != -1 else InputMode.NORMAL
			)
		get_viewport().set_input_as_handled()
		return
	if _input_mode == InputMode.PLACING_REPLACEMENT:
		_command_gateway.submit(
			GameCommand.buy_replacement(_client_state.local_player_id, map_position)
		)
		_set_input_mode(InputMode.UNIT_SELECTED if _selected_unit_id != -1 else InputMode.NORMAL)
		get_viewport().set_input_as_handled()
		return

	var clicked_unit_id: int = _client_state.get_player_unit_at_position(map_position)
	if clicked_unit_id != -1:
		_select_unit(clicked_unit_id)
		_emit_target_preview(mouse_event.position)
		get_viewport().set_input_as_handled()
		return
	if _selected_unit_id == -1:
		return

	var command: GameCommand = GameCommand.move_unit(
		_client_state.local_player_id,
		_selected_unit_id,
		map_position
	)
	_command_gateway.submit(command)
	_emit_target_preview(mouse_event.position)
	get_viewport().set_input_as_handled()


func _screen_to_map_position(screen_position: Vector2) -> Vector2:
	var world_position: Vector2 = _map.get_canvas_transform().affine_inverse() * screen_position
	return _map.to_local(world_position)


func _select_unit(unit_id: int) -> void:
	if _selected_unit_id == unit_id:
		_cancel_current_mode()
		return
	if _is_aiming_strike():
		_cancel_strike_aiming()
	_clear_airstrike_targets()
	_selected_unit_id = unit_id
	selected_unit_changed.emit(unit_id)
	_set_input_mode(InputMode.UNIT_SELECTED)


func _emit_target_preview(screen_position: Vector2, allow_visible := true) -> void:
	var map_position: Vector2 = _screen_to_map_position(screen_position)
	var valid: bool = (
		allow_visible
		and Rect2(Vector2.ZERO, _client_state.rules.map_size).has_point(map_position)
	)
	var income: ResourceSample = ResourceSample.new()
	if valid:
		income = _map.sample_resources(map_position)
	target_preview_changed.emit(
		screen_position,
		map_position,
		income.water_income,
		income.gold_income,
		valid
	)


func on_unit_removed(unit_id: int) -> void:
	if unit_id != _selected_unit_id:
		return
	_selected_unit_id = -1
	selected_unit_changed.emit(-1)
	_cancel_current_mode()


func on_bomb_requested() -> void:
	_toggle_strike_aiming(InputMode.AIMING_BOMB)


func on_missile_requested() -> void:
	_toggle_strike_aiming(InputMode.AIMING_MISSILE)


func on_replacement_requested() -> void:
	if _client_state.match_finished or _client_state.player.is_empty():
		return
	if _input_mode == InputMode.PLACING_REPLACEMENT:
		_cancel_current_mode()
		return
	if _is_aiming_strike():
		_cancel_strike_aiming()
	_set_input_mode(InputMode.PLACING_REPLACEMENT)


func on_leave_requested() -> void:
	_network_session.leave_to_menu()


func _handle_debug_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if _client_state.match_finished:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_network_match.request_rematch()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_network_session.leave_to_menu()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_1:
			_select_unit_by_slot(0)
			get_viewport().set_input_as_handled()
		KEY_2:
			_select_unit_by_slot(1)
			get_viewport().set_input_as_handled()
		KEY_3:
			_select_unit_by_slot(2)
			get_viewport().set_input_as_handled()
		KEY_B:
			_toggle_strike_aiming(InputMode.AIMING_BOMB)
			get_viewport().set_input_as_handled()
		KEY_M:
			_toggle_strike_aiming(InputMode.AIMING_MISSILE)
			get_viewport().set_input_as_handled()
		KEY_R:
			on_replacement_requested()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _is_aiming_strike() or _input_mode == InputMode.PLACING_REPLACEMENT:
				_cancel_current_mode()
				get_viewport().set_input_as_handled()


func _toggle_strike_aiming(mode: InputMode) -> void:
	if _client_state.match_finished or _client_state.player.is_empty():
		return
	if _input_mode == mode:
		_cancel_strike_aiming()
		return
	_clear_airstrike_targets()
	_set_input_mode(mode)
	if mode == InputMode.AIMING_MISSILE:
		airstrike_target_count_changed.emit(0, _client_state.rules.airstrike_target_count)
	_emit_strike_preview(get_viewport().get_mouse_position(), true)


func _submit_strike(map_position: Vector2) -> bool:
	if _input_mode == InputMode.AIMING_MISSILE:
		_airstrike_targets.append(map_position)
		airstrike_targets_changed.emit(
			_airstrike_targets,
			_client_state.rules.missile_damage_radius,
			true
		)
		airstrike_target_count_changed.emit(
			_airstrike_targets.size(),
			_client_state.rules.airstrike_target_count
		)
		if _airstrike_targets.size() < _client_state.rules.airstrike_target_count:
			return false
		_command_gateway.submit(GameCommand.launch_airstrike(
			_client_state.local_player_id,
			_airstrike_targets
		))
		_clear_airstrike_targets()
		return true
	_command_gateway.submit(GameCommand.launch_bomb(
		_client_state.local_player_id,
		map_position
	))
	return true


func _cancel_strike_aiming() -> void:
	_clear_airstrike_targets()
	bomb_target_preview_changed.emit(
		Vector2.ZERO,
		StrikeState.Type.BOMB,
		0.0,
		0.0,
		false,
		false
	)
	_set_input_mode(InputMode.UNIT_SELECTED if _selected_unit_id != -1 else InputMode.NORMAL)


func _cancel_current_mode() -> void:
	if _is_aiming_strike():
		_cancel_strike_aiming()
	else:
		_set_input_mode(InputMode.UNIT_SELECTED if _selected_unit_id != -1 else InputMode.NORMAL)


func _emit_strike_preview(screen_position: Vector2, is_visible: bool) -> void:
	var map_position: Vector2 = _screen_to_map_position(screen_position)
	var valid: bool = Rect2(Vector2.ZERO, _client_state.rules.map_size).has_point(map_position)
	var strike_type: StrikeState.Type = (
		StrikeState.Type.MISSILE
		if _input_mode == InputMode.AIMING_MISSILE
		else StrikeState.Type.BOMB
	)
	var damage_radius: float = (
		_client_state.rules.missile_damage_radius
		if strike_type == StrikeState.Type.MISSILE
		else _client_state.rules.bomb_damage_radius
	)
	var reveal_radius: float = (
		_client_state.rules.missile_reveal_radius
		if strike_type == StrikeState.Type.MISSILE
		else _client_state.rules.bomb_reveal_radius
	)
	bomb_target_preview_changed.emit(
		map_position,
		strike_type,
		damage_radius,
		reveal_radius,
		valid,
		is_visible
	)


func _is_aiming_strike() -> bool:
	return _input_mode == InputMode.AIMING_BOMB or _input_mode == InputMode.AIMING_MISSILE


func _select_unit_by_slot(slot: int) -> void:
	var unit_ids: Array[int] = _client_state.get_player_unit_ids()
	if slot >= 0 and slot < unit_ids.size():
		_select_unit(unit_ids[slot])


func _clear_airstrike_targets() -> void:
	if _airstrike_targets.is_empty():
		return
	_airstrike_targets.clear()
	airstrike_targets_changed.emit(
		PackedVector2Array(),
		_client_state.rules.missile_damage_radius,
		false
	)


func _set_input_mode(mode: InputMode) -> void:
	if _input_mode == mode:
		return
	_input_mode = mode
	input_mode_changed.emit(_input_mode)
