class_name GameCommand
extends RefCounted

enum Type {
	MOVE_UNIT,
	LAUNCH_BOMB,
	LAUNCH_MISSILE,
	BUY_REPLACEMENT,
}

var type: Type
var player_id: int
var unit_id := -1
var target := Vector2.ZERO
var sequence_number: int


static func move_unit(
		command_player_id: int,
		command_unit_id: int,
		command_target: Vector2,
		command_sequence_number: int
) -> GameCommand:
	var command := GameCommand.new()
	command.type = Type.MOVE_UNIT
	command.player_id = command_player_id
	command.unit_id = command_unit_id
	command.target = command_target
	command.sequence_number = command_sequence_number
	return command
