class_name GameBootstrap
extends Node


func _ready() -> void:
	var network_session: NetworkSessionService = get_node("/root/NetworkSession")
	if network_session.is_dedicated_server():
		return
	if "--solo" in OS.get_cmdline_user_args():
		network_session.start_solo_game.call_deferred()
		return
	_open_menu.call_deferred()


func _open_menu() -> void:
	get_tree().change_scene_to_file(NetworkSessionService.MENU_SCENE)
