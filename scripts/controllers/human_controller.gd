class_name HumanController
extends Node

signal selected_unit_changed(unit_id: int)

const PLAYER_ID := 0

@onready var _game_state: GameState = %GameState
@onready var _command_gateway: CommandGateway = %CommandGateway
@onready var _map: Node2D = %Map

var _selected_unit_id := -1
var _next_sequence_number := 0


func _unhandled_input(event: InputEvent) -> void:
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
	get_viewport().set_input_as_handled()


func _screen_to_map_position(screen_position: Vector2) -> Vector2:
	var world_position: Vector2 = _map.get_canvas_transform().affine_inverse() * screen_position
	return _map.to_local(world_position)


func _select_unit(unit_id: int) -> void:
	if _selected_unit_id == unit_id:
		return
	_selected_unit_id = unit_id
	selected_unit_changed.emit(unit_id)
