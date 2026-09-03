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
	damage_radius: float,
	reveal_radius: float,
	valid: bool,
	visible: bool
)

enum InputMode {
	NORMAL,
	UNIT_SELECTED,
	AIMING_BOMB,
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
	get_parent().add_child(bot_controller)
	_game_state.tick_advanced.connect(bot_controller.on_tick_advanced)
	controlled_player_changed.connect(bot_controller.on_debug_controlled_player_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_debug_key(event as InputEventKey)
		return
	if event is InputEventMouseMotion:
		var mouse_position: Vector2 = (event as InputEventMouseMotion).position
		if _input_mode == InputMode.AIMING_BOMB:
			_emit_bomb_preview(mouse_position, true)
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
	if _input_mode == InputMode.AIMING_BOMB:
		_submit_bomb(map_position)
		_emit_bomb_preview(mouse_event.position, false)
		_set_input_mode(
			InputMode.UNIT_SELECTED if _selected_unit_id != -1 else InputMode.NORMAL
		)
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
	_set_input_mode(InputMode.NORMAL)


func _handle_debug_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_B:
			if _input_mode == InputMode.AIMING_BOMB:
				_cancel_bomb_aiming()
			else:
				_set_input_mode(InputMode.AIMING_BOMB)
				_emit_bomb_preview(get_viewport().get_mouse_position(), true)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _input_mode == InputMode.AIMING_BOMB:
				_cancel_bomb_aiming()
				get_viewport().set_input_as_handled()
		KEY_F1:
			_debug_full_visibility = not _debug_full_visibility
			debug_full_visibility_changed.emit(_debug_full_visibility)
			get_viewport().set_input_as_handled()
		KEY_F2:
			_controlled_player_id = (_controlled_player_id + 1) % GameState.PLAYER_COUNT
			_selected_unit_id = -1
			selected_unit_changed.emit(-1)
			_cancel_bomb_aiming()
			controlled_player_changed.emit(_controlled_player_id)
			get_viewport().set_input_as_handled()


func _submit_bomb(map_position: Vector2) -> void:
	var command: GameCommand = GameCommand.launch_bomb(
		_controlled_player_id,
		map_position
	)
	_command_gateway.submit(command)


func _cancel_bomb_aiming() -> void:
	bomb_target_preview_changed.emit(Vector2.ZERO, 0.0, 0.0, false, false)
	_set_input_mode(InputMode.UNIT_SELECTED if _selected_unit_id != -1 else InputMode.NORMAL)


func _emit_bomb_preview(screen_position: Vector2, is_visible: bool) -> void:
	var map_position: Vector2 = _screen_to_map_position(screen_position)
	var valid: bool = _game_state.is_position_inside_map(map_position)
	bomb_target_preview_changed.emit(
		map_position,
		GameState.BOMB_DAMAGE_RADIUS,
		GameState.BOMB_REVEAL_RADIUS,
		valid,
		is_visible
	)


func _set_input_mode(mode: InputMode) -> void:
	if _input_mode == mode:
		return
	_input_mode = mode
	input_mode_changed.emit(_input_mode)
