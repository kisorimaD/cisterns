class_name CommandGateway
extends Node

@onready var _network_match: NetworkMatch = %NetworkMatch
@onready var _network_session: NetworkSessionService = get_node("/root/NetworkSession")

var _next_sequence_by_player: Dictionary[int, int] = {}


func submit(command: GameCommand) -> void:
	var player_id := _network_session.local_player_id
	if _network_session.is_solo_game():
		player_id = command.player_id
	command.player_id = player_id
	command.sequence_number = _next_sequence_by_player.get(player_id, 0)
	_next_sequence_by_player[player_id] = command.sequence_number + 1
	_network_match.submit_command(command)
