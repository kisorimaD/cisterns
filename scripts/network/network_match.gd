class_name NetworkMatch
extends Node

@onready var _game_state: GameState = %GameState
@onready var _client_state: ClientMatchState = %ClientMatchState
@onready var _network_session: NetworkSessionService = get_node("/root/NetworkSession")

var _loaded_peers: Dictionary[int, bool] = {}
var _last_client_sequence: Dictionary[int, int] = {}
var _next_game_sequence: Dictionary[int, int] = {}
var _rate_windows: Dictionary[int, Dictionary] = {}
var _rematch_peers: Dictionary[int, bool] = {}
var _loaded_retry_seconds := 0.0
var _received_first_snapshot := false
var _server_start_queued := false


func _ready() -> void:
	_game_state.tick_advanced.connect(_on_server_tick)
	_game_state.command_rejected.connect(_on_server_command_rejected)
	_game_state.match_ended.connect(_on_server_match_ended)
	_game_state.strike_detonated.connect(_on_server_strike_detonated)
	_game_state.unit_destroyed.connect(_on_server_unit_destroyed)
	_network_session.peer_left.connect(_on_peer_left)
	if _network_session.is_solo_game():
		var bot_controller := BotController.new()
		bot_controller.name = "BotController"
		bot_controller.configure(_game_state, %CommandGateway)
		add_child(bot_controller)
		_game_state.tick_advanced.connect(bot_controller.on_tick_advanced)
	if multiplayer.is_server():
		_mark_peer_loaded(1)
	else:
		peer_loaded.rpc_id(1, _network_session.current_match_id)


func _process(delta: float) -> void:
	if multiplayer.is_server() or _received_first_snapshot:
		return
	_loaded_retry_seconds += delta
	if _loaded_retry_seconds >= 1.0:
		_loaded_retry_seconds = 0.0
		peer_loaded.rpc_id(1, _network_session.current_match_id)


func submit_command(command: GameCommand) -> void:
	var payload: Dictionary = NetworkProtocol.encode_command(command)
	if multiplayer.is_server():
		_receive_command(
			1,
			payload,
			command.player_id if _network_session.is_solo_game() else -1
		)
	else:
		submit_command_remote.rpc_id(1, payload)


func request_rematch() -> void:
	if not _client_state.match_finished:
		return
	_network_session.report_status("Ожидание согласия второго игрока на реванш…")
	if _network_session.is_solo_game():
		_network_session.begin_rematch()
		return
	if multiplayer.is_server():
		_register_rematch_request(1)
	else:
		request_rematch_remote.rpc_id(1, _network_session.current_match_id)


@rpc("any_peer", "call_remote", "reliable", 0)
func submit_command_remote(payload: Dictionary) -> void:
	if multiplayer.is_server():
		_receive_command(multiplayer.get_remote_sender_id(), payload)


@rpc("any_peer", "call_remote", "reliable", 1)
func peer_loaded(match_id: int) -> void:
	if multiplayer.is_server() and match_id == _network_session.current_match_id:
		_mark_peer_loaded(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable", 1)
func request_rematch_remote(match_id: int) -> void:
	if multiplayer.is_server() and match_id == _network_session.current_match_id:
		_register_rematch_request(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func receive_snapshot(snapshot: Dictionary) -> void:
	_received_first_snapshot = true
	_client_state.apply_snapshot(snapshot)


@rpc("authority", "call_remote", "reliable", 1)
func receive_full_snapshot(snapshot: Dictionary) -> void:
	_received_first_snapshot = true
	_client_state.apply_snapshot(snapshot)


@rpc("authority", "call_remote", "reliable", 1)
func receive_command_rejection(command_type: int, reason: StringName) -> void:
	_client_state.reject_local_command(command_type, reason)


@rpc("authority", "call_remote", "reliable", 1)
func receive_strike_impact(record: Dictionary) -> void:
	_client_state.apply_strike_impact(record)


@rpc("authority", "call_remote", "reliable", 1)
func receive_unit_destroyed(record: Dictionary) -> void:
	_client_state.apply_unit_destroyed(record)


func _receive_command(peer_id: int, payload: Dictionary, solo_player_id: int = -1) -> void:
	var player_id: int = (
		solo_player_id
		if _network_session.is_solo_game()
		else _network_session.player_for_peer(peer_id)
	)
	if player_id < 0 or not _game_state.simulation_running:
		_send_rejection(peer_id, payload.get("type", -1), &"match_not_running")
		return
	var command: GameCommand = NetworkProtocol.decode_command(payload, player_id)
	if command == null:
		_send_rejection(peer_id, payload.get("type", -1), &"malformed_command")
		return
	var command_stream_id: int = player_id if _network_session.is_solo_game() else peer_id
	var previous_client_sequence: int = _last_client_sequence.get(command_stream_id, -1)
	if command.sequence_number <= previous_client_sequence:
		_send_rejection(peer_id, int(command.type), &"replayed_command")
		return
	_last_client_sequence[command_stream_id] = command.sequence_number
	if not _consume_rate_limit(command_stream_id):
		_send_rejection(peer_id, int(command.type), &"rate_limited")
		return
	command.sequence_number = _next_game_sequence.get(player_id, 0)
	_next_game_sequence[player_id] = command.sequence_number + 1
	_game_state.queue_command(command)


func _consume_rate_limit(peer_id: int) -> bool:
	var now_msec: int = Time.get_ticks_msec()
	var window: Dictionary = _rate_windows.get(peer_id, {"start": now_msec, "count": 0})
	if now_msec - int(window["start"]) >= 1000:
		window = {"start": now_msec, "count": 0}
	window["count"] = int(window["count"]) + 1
	_rate_windows[peer_id] = window
	return int(window["count"]) <= _game_state.rules.network_max_commands_per_second


func _mark_peer_loaded(peer_id: int) -> void:
	if _network_session.player_for_peer(peer_id) < 0:
		return
	_loaded_peers[peer_id] = true
	_queue_server_start_if_ready()


func _queue_server_start_if_ready() -> void:
	for expected_peer: int in _network_session.connected_peer_ids():
		if not _loaded_peers.has(expected_peer):
			return
	if not _game_state.simulation_running and not _server_start_queued:
		_server_start_queued = true
		_start_server_match.call_deferred()


func _start_server_match() -> void:
	_server_start_queued = false
	for expected_peer: int in _network_session.connected_peer_ids():
		if not _loaded_peers.has(expected_peer):
			return
	if multiplayer.is_server() and not _game_state.simulation_running:
		_game_state.start_match()
		_send_all_snapshots(true)


func _on_server_tick(tick: int) -> void:
	if not multiplayer.is_server():
		return
	var reliable: bool = (
		tick % _game_state.rules.network_full_snapshot_interval_ticks == 0
		or _game_state.match_finished
	)
	_send_all_snapshots(reliable)


func _send_all_snapshots(reliable: bool) -> void:
	for peer_id: int in _network_session.connected_peer_ids():
		var player_id: int = _network_session.player_for_peer(peer_id)
		var snapshot: Dictionary = StateProjector.build_snapshot(
			_game_state,
			player_id,
			_network_session.current_match_id
		)
		assert(not StateProjector.contains_hidden_enemy(snapshot, _game_state, player_id))
		if peer_id == 1:
			_client_state.apply_snapshot(snapshot)
		elif reliable:
			receive_full_snapshot.rpc_id(peer_id, snapshot)
		else:
			receive_snapshot.rpc_id(peer_id, snapshot)


func _on_server_command_rejected(player_id: int, command_type: int, reason: StringName) -> void:
	_send_rejection(_network_session.peer_for_player(player_id), command_type, reason)


func _send_rejection(peer_id: int, command_type: int, reason: StringName) -> void:
	if peer_id == 1:
		_client_state.reject_local_command(command_type, reason)
	elif peer_id > 1:
		receive_command_rejection.rpc_id(peer_id, command_type, reason)


func _on_server_match_ended(_winner_player_id: int) -> void:
	if multiplayer.is_server():
		_send_all_snapshots(true)


func _on_server_strike_detonated(strike_id: int, _position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var strike: StrikeState = _game_state.get_strike(strike_id)
	if strike == null:
		return
	var record := {
		"match_id": _network_session.current_match_id,
		"id": strike.id,
		"type": int(strike.type),
		"target": strike.target,
		"damage_radius": strike.damage_radius,
	}
	for peer_id: int in _network_session.connected_peer_ids():
		if peer_id == 1:
			_client_state.apply_strike_impact(record)
		else:
			receive_strike_impact.rpc_id(peer_id, record)


func _on_server_unit_destroyed(unit_id: int, position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var unit: UnitState = _game_state.units.get(unit_id)
	var record := {
		"match_id": _network_session.current_match_id,
		"id": unit_id,
		"owner_id": unit.owner_id if unit != null else -1,
		"position": position,
	}
	for peer_id: int in _network_session.connected_peer_ids():
		if peer_id == 1:
			_client_state.apply_unit_destroyed(record)
		else:
			receive_unit_destroyed.rpc_id(peer_id, record)


func _on_peer_left(peer_id: int) -> void:
	if multiplayer.is_server() and _game_state.simulation_running:
		var remaining_player_id := -1
		for remaining_peer_id: int in _network_session.connected_peer_ids():
			remaining_player_id = _network_session.player_for_peer(remaining_peer_id)
			break
		_game_state.finish_due_to_disconnect(remaining_player_id)
		_send_all_snapshots(true)


func _register_rematch_request(peer_id: int) -> void:
	if _network_session.connected_peer_ids().size() != GameState.PLAYER_COUNT:
		return
	_rematch_peers[peer_id] = true
	for expected_peer: int in _network_session.connected_peer_ids():
		if not _rematch_peers.has(expected_peer):
			return
	_network_session.begin_rematch()
