class_name CommandGateway
extends Node

signal command_submitted(command: GameCommand)

var _next_sequence_by_player: Dictionary[int, int] = {}


func submit(command: GameCommand) -> void:
	var sequence_number: int = 0
	if _next_sequence_by_player.has(command.player_id):
		sequence_number = _next_sequence_by_player[command.player_id]
	command.sequence_number = sequence_number
	_next_sequence_by_player[command.player_id] = sequence_number + 1
	command_submitted.emit(command)
