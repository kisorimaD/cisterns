class_name NetworkSessionService
extends Node

signal status_changed(message: String)
signal lobby_changed(connected_players: int, ready_players: int, can_start: bool)
signal local_player_assigned(player_id: int)
signal peer_left(peer_id: int)
signal session_closed

const MENU_SCENE := "res://scenes/menu/network_menu.tscn"
const GAME_SCENE := "res://scenes/game/game.tscn"
const BOOTSTRAP_SCENE := "res://scenes/bootstrap/bootstrap.tscn"

enum Mode {
	OFFLINE,
	SOLO,
	LISTEN_HOST,
	DEDICATED_SERVER,
	CLIENT,
}

var local_player_id := -1
var current_match_id := 0
var match_active := false
var last_status := "Создайте матч или подключитесь по IP"
var mode: Mode = Mode.OFFLINE
var _peer_to_player: Dictionary[int, int] = {}
var _ready_by_peer: Dictionary[int, bool] = {}
var _rules: GameRules = preload("res://resources/default_game_rules.tres")


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var user_arguments := OS.get_cmdline_user_args()
	if "--dedicated-server" in user_arguments:
		start_dedicated_server()
	elif "--connect-public" in user_arguments:
		join_public_server.call_deferred()


func start_solo_game() -> void:
	_disconnect_peer()
	mode = Mode.SOLO
	local_player_id = 0
	_peer_to_player = {1: 0}
	current_match_id += 1
	match_active = true
	_set_status("Одиночный матч")
	local_player_assigned.emit(local_player_id)
	get_tree().change_scene_to_file(GAME_SCENE)


func start_dedicated_server() -> Error:
	_disconnect_peer()
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(
		_rules.network_port,
		_rules.network_dedicated_max_clients
	)
	if error != OK:
		_set_status("Не удалось запустить выделенный сервер: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	mode = Mode.DEDICATED_SERVER
	_set_status("Выделенный сервер слушает UDP %d" % _rules.network_port)
	return OK


func host_game() -> Error:
	_disconnect_peer()
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(_rules.network_port, _rules.network_max_clients)
	if error != OK:
		_set_status("Не удалось создать сервер: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	mode = Mode.LISTEN_HOST
	local_player_id = 0
	_peer_to_player = {1: 0}
	_ready_by_peer = {1: false}
	match_active = false
	_set_status("Сервер создан. Ожидание второго игрока…")
	local_player_assigned.emit(local_player_id)
	_broadcast_lobby_state()
	return OK


func join_game(address: String) -> Error:
	_disconnect_peer()
	var peer := ENetMultiplayerPeer.new()
	var target_address: String = address.strip_edges()
	if target_address.is_empty():
		target_address = "127.0.0.1"
	var error: Error = peer.create_client(target_address, _rules.network_port)
	if error != OK:
		_set_status("Не удалось подключиться: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	local_player_id = -1
	match_active = false
	_set_status("Подключение к %s…" % target_address)
	return OK


func join_public_server() -> Error:
	return join_game(_rules.network_public_server_address)


func set_local_ready(ready: bool) -> void:
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if multiplayer.is_server():
		_set_peer_ready(1, ready)
	else:
		set_ready.rpc_id(1, ready)


func begin_match() -> void:
	if match_active or not multiplayer.is_server() or not _can_start_match():
		return
	current_match_id += 1
	match_active = true
	_set_status("Матч %d запускается" % current_match_id)
	load_match.rpc(current_match_id, NetworkProtocol.rules_signature(_rules))


func begin_rematch() -> void:
	if not multiplayer.is_server():
		return
	current_match_id += 1
	match_active = true
	_set_status("Реванш %d запускается" % current_match_id)
	if mode == Mode.SOLO:
		get_tree().change_scene_to_file(GAME_SCENE)
		return
	load_match.rpc(current_match_id, NetworkProtocol.rules_signature(_rules))


func is_solo_game() -> bool:
	return mode == Mode.SOLO


func is_dedicated_server() -> bool:
	return mode == Mode.DEDICATED_SERVER


func player_for_peer(peer_id: int) -> int:
	return _peer_to_player.get(peer_id, -1)


func peer_for_player(player_id: int) -> int:
	for peer_id: int in _peer_to_player:
		if _peer_to_player[peer_id] == player_id:
			return peer_id
	return -1


func connected_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_id: int in _peer_to_player:
		result.append(peer_id)
	return result


func leave_to_menu(message: String = "Соединение закрыто") -> void:
	_disconnect_peer()
	_set_status(message)
	session_closed.emit()
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != MENU_SCENE:
		get_tree().change_scene_to_file(MENU_SCENE)


func report_status(message: String) -> void:
	_set_status(message)


@rpc("any_peer", "call_remote", "reliable", 0)
func set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	_set_peer_ready(multiplayer.get_remote_sender_id(), ready)


@rpc("authority", "call_remote", "reliable", 0)
func assign_player(player_id: int, protocol_version: int) -> void:
	if protocol_version != NetworkProtocol.VERSION:
		leave_to_menu("Несовместимая версия сетевого протокола")
		return
	local_player_id = player_id
	local_player_assigned.emit(player_id)
	_set_status("Подключено. Вы играете за сторону %d" % player_id)
	if "--auto-ready" in OS.get_cmdline_user_args():
		set_local_ready.call_deferred(true)


@rpc("authority", "call_local", "reliable", 0)
func receive_lobby_state(connected_players: int, ready_players: int, can_start: bool) -> void:
	lobby_changed.emit(connected_players, ready_players, can_start)


@rpc("authority", "call_local", "reliable", 1)
func load_match(match_id: int, rules_signature: String) -> void:
	if rules_signature != NetworkProtocol.rules_signature(_rules):
		leave_to_menu("Настройки матча отличаются от настроек сервера")
		return
	current_match_id = match_id
	match_active = true
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if match_active:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return
	var maximum_players := (
		GameState.PLAYER_COUNT
		if mode == Mode.DEDICATED_SERVER
		else 1
	)
	if _peer_to_player.size() >= maximum_players:
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return
	var player_id := 1
	if mode == Mode.DEDICATED_SERVER:
		player_id = 0 if not _peer_to_player.values().has(0) else 1
	_peer_to_player[peer_id] = player_id
	_ready_by_peer[peer_id] = false
	assign_player.rpc_id(peer_id, player_id, NetworkProtocol.VERSION)
	_set_status("Игрок %d зарегистрирован" % player_id)
	_broadcast_lobby_state()


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		var was_registered := _peer_to_player.has(peer_id)
		_peer_to_player.erase(peer_id)
		_ready_by_peer.erase(peer_id)
		if was_registered:
			peer_left.emit(peer_id)
		if mode == Mode.DEDICATED_SERVER and match_active and _peer_to_player.is_empty():
			match_active = false
			get_tree().change_scene_to_file(BOOTSTRAP_SCENE)
		if not match_active:
			_set_status("Игрок отключился")
			_broadcast_lobby_state()


func _on_connected_to_server() -> void:
	_set_status("Соединение установлено. Ожидание назначения стороны…")


func _on_connection_failed() -> void:
	leave_to_menu("Не удалось установить соединение")


func _on_server_disconnected() -> void:
	leave_to_menu("Сервер отключился")


func _set_peer_ready(peer_id: int, ready: bool) -> void:
	if not _peer_to_player.has(peer_id):
		return
	_ready_by_peer[peer_id] = ready
	_broadcast_lobby_state()
	if mode == Mode.DEDICATED_SERVER and _can_start_match():
		begin_match.call_deferred()


func _can_start_match() -> bool:
	if _peer_to_player.size() != 2:
		return false
	for peer_id: int in _peer_to_player:
		if not _ready_by_peer.get(peer_id, false):
			return false
	return true


func _broadcast_lobby_state() -> void:
	if not multiplayer.is_server():
		return
	var ready_count := 0
	for peer_id: int in _ready_by_peer:
		if _ready_by_peer[peer_id]:
			ready_count += 1
	receive_lobby_state.rpc(_peer_to_player.size(), ready_count, _can_start_match())


func _set_status(message: String) -> void:
	last_status = message
	print("[Cisterns network] %s" % message)
	status_changed.emit(message)


func _disconnect_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	local_player_id = -1
	match_active = false
	mode = Mode.OFFLINE
	_peer_to_player.clear()
	_ready_by_peer.clear()
