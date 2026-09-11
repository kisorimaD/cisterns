class_name HumanController
extends Node

signal selected_unit_changed(unit_id: int)
signal input_mode_changed(mode: int)
signal target_preview_changed(
	map_position: Vector2,
	water_income: int,
	gold_income: int,
	valid: bool
)
signal controlled_player_changed(player_id: int)
signal debug_full_visibility_changed(enabled: bool)
signal bomb_target_preview_changed(
	map_position: Vector2,
	strike_type: int,
	damage_radius: float,
	reveal_radius: float,
	valid: bool,
	visible: bool
)

enum InputMode {
	NORMAL,
	UNIT_SELECTED,
	AIMING_BOMB,
	AIMING_MISSILE,
	PLACING_REPLACEMENT,
}

@onready var _game_state: GameState = %GameState
@onready var _command_gateway: CommandGateway = %CommandGateway
@onready var _map: Node2D = %Map

var _selected_unit_id := -1
var _controlled_player_id := GameState.PLAYER_ID
var _debug_full_visibility := false
var _input_mode: InputMode = InputMode.NORMAL


func _ready() -> void:
	var bot_controller: BotController = BotController.new()
	bot_controller.name = "BotController"
	bot_controller.configure(_game_state, _command_gateway)
	get_parent().add_child.call_deferred(bot_controller)
	_game_state.tick_advanced.connect(bot_controller.on_tick_advanced)
	controlled_player_changed.connect(bot_controller.on_debug_controlled_player_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_debug_key(event as InputEventKey)
		return
	if _game_state.match_finished:
		return
	if event is InputEventMouseMotion:
		var mouse_position: Vector2 = (event as InputEventMouseMotion).position
		if _is_aiming_strike():
			_emit_strike_preview(mouse_position, true)
		elif _selected_unit_id != -1:
			_emit_target_preview(mouse_position)
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	var map_position: Vector2 = _screen_to_map_position(mouse_event.position)
	if not _game_state.is_position_inside_map(map_position):
		return
	if _is_aiming_strike():
		_submit_strike(map_position)
		_emit_strike_preview(mouse_event.position, false)
		_set_input_mode(
			InputMode.UNIT_SELECTED if _selected_unit_id != -1 else InputMode.NORMAL
		)
		get_viewport().set_input_as_handled()
		return
	if _input_mode == InputMode.PLACING_REPLACEMENT:
		_command_gateway.submit(GameCommand.buy_replacement(_controlled_player_id, map_position))
		_set_input_mode(InputMode.UNIT_SELECTED if _selected_unit_id != -1 else InputMode.NORMAL)
		get_viewport().set_input_as_handled()
		return

	var clicked_unit_id: int = _game_state.get_player_unit_at_position(
		_controlled_player_id,
		map_position
	)
	if clicked_unit_id != -1:
		_select_unit(clicked_unit_id)
		_emit_target_preview(mouse_event.position)
		get_viewport().set_input_as_handled()
		return
	if _selected_unit_id == -1:
		return

	var command: GameCommand = GameCommand.move_unit(
		_controlled_player_id,
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
		return
	_selected_unit_id = unit_id
	selected_unit_changed.emit(unit_id)
	_set_input_mode(InputMode.UNIT_SELECTED)


func _emit_target_preview(screen_position: Vector2) -> void:
	var map_position: Vector2 = _screen_to_map_position(screen_position)
	var valid: bool = _game_state.is_position_inside_map(map_position)
	var income: ResourceSample = ResourceSample.new()
	if valid:
		income = _game_state.get_income_preview_for_unit(_selected_unit_id, map_position)
	target_preview_changed.emit(
		map_position,
		income.water_income,
		income.gold_income,
		valid
	)


func on_unit_destroyed(unit_id: int, _position: Vector2) -> void:
	if unit_id != _selected_unit_id:
		return
	_selected_unit_id = -1
	selected_unit_changed.emit(-1)
	_cancel_current_mode()


func on_bomb_requested() -> void:
	_toggle_strike_aiming(InputMode.AIMING_BOMB)


func on_missile_requested() -> void:
	_toggle_strike_aiming(InputMode.AIMING_MISSILE)


func _handle_debug_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	if _game_state.match_finished:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			get_tree().reload_current_scene()
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_B:
			_toggle_strike_aiming(InputMode.AIMING_BOMB)
			get_viewport().set_input_as_handled()
		KEY_M:
			_toggle_strike_aiming(InputMode.AIMING_MISSILE)
			get_viewport().set_input_as_handled()
		KEY_R:
			if _input_mode == InputMode.PLACING_REPLACEMENT:
				_cancel_current_mode()
			else:
				if _is_aiming_strike():
					_cancel_strike_aiming()
				_set_input_mode(InputMode.PLACING_REPLACEMENT)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _is_aiming_strike() or _input_mode == InputMode.PLACING_REPLACEMENT:
				_cancel_current_mode()
				get_viewport().set_input_as_handled()
		KEY_F1:
			_debug_full_visibility = not _debug_full_visibility
			debug_full_visibility_changed.emit(_debug_full_visibility)
			get_viewport().set_input_as_handled()
		KEY_F2:
			_controlled_player_id = (_controlled_player_id + 1) % GameState.PLAYER_COUNT
			_selected_unit_id = -1
			selected_unit_changed.emit(-1)
			_cancel_current_mode()
			controlled_player_changed.emit(_controlled_player_id)
			get_viewport().set_input_as_handled()


func _toggle_strike_aiming(mode: InputMode) -> void:
	if _game_state.match_finished:
		return
	if _input_mode == mode:
		_cancel_strike_aiming()
		return
	_set_input_mode(mode)
	_emit_strike_preview(get_viewport().get_mouse_position(), true)


func _submit_strike(map_position: Vector2) -> void:
	var command: GameCommand
	if _input_mode == InputMode.AIMING_MISSILE:
		command = GameCommand.launch_missile(_controlled_player_id, map_position)
	else:
		command = GameCommand.launch_bomb(_controlled_player_id, map_position)
	_command_gateway.submit(command)


func _cancel_strike_aiming() -> void:
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
	var valid: bool = _game_state.is_position_inside_map(map_position)
	var strike_type: StrikeState.Type = (
		StrikeState.Type.MISSILE
		if _input_mode == InputMode.AIMING_MISSILE
		else StrikeState.Type.BOMB
	)
	var damage_radius: float = (
		_game_state.rules.missile_damage_radius
		if strike_type == StrikeState.Type.MISSILE
		else _game_state.rules.bomb_damage_radius
	)
	var reveal_radius: float = (
		_game_state.rules.missile_reveal_radius
		if strike_type == StrikeState.Type.MISSILE
		else _game_state.rules.bomb_reveal_radius
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


func _set_input_mode(mode: InputMode) -> void:
	if _input_mode == mode:
		return
	_input_mode = mode
	input_mode_changed.emit(_input_mode)
