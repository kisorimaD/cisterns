class_name HumanController
extends Node

signal selected_unit_changed(unit_id: int)
signal target_preview_changed(
	map_position: Vector2,
	water_income: int,
	gold_income: int,
	valid: bool
)

const PLAYER_ID := 0

@onready var _game_state: GameState = %GameState
@onready var _command_gateway: CommandGateway = %CommandGateway
@onready var _map: Node2D = %Map

var _selected_unit_id := -1
var _next_sequence_number := 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _selected_unit_id != -1:
			_emit_target_preview((event as InputEventMouseMotion).position)
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return

	var map_position: Vector2 = _screen_to_map_position(mouse_event.position)
	if not _game_state.is_position_inside_map(map_position):
		return

	var clicked_unit_id: int = _game_state.get_player_unit_at_position(PLAYER_ID, map_position)
	if clicked_unit_id != -1:
		_select_unit(clicked_unit_id)
		_emit_target_preview(mouse_event.position)
		get_viewport().set_input_as_handled()
		return
	if _selected_unit_id == -1:
		return

	var command: GameCommand = GameCommand.move_unit(
		PLAYER_ID,
		_selected_unit_id,
		map_position,
		_next_sequence_number
	)
	_next_sequence_number += 1
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
