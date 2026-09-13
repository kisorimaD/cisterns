class_name NetworkMenu
extends Control

@onready var _address_edit: LineEdit = %AddressEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _public_button: Button = %PublicButton
@onready var _solo_button: Button = %SoloButton
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _disconnect_button: Button = %DisconnectButton
@onready var _status_label: Label = %StatusLabel
@onready var _lobby_label: Label = %LobbyLabel
@onready var _network_session: NetworkSessionService = get_node("/root/NetworkSession")


func _ready() -> void:
	_network_session.status_changed.connect(_on_status_changed)
	_network_session.lobby_changed.connect(_on_lobby_changed)
	_network_session.local_player_assigned.connect(_on_player_assigned)
	_network_session.session_closed.connect(_on_session_closed)
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_public_button.pressed.connect(_on_public_pressed)
	_solo_button.pressed.connect(_network_session.start_solo_game)
	_ready_button.toggled.connect(_network_session.set_local_ready)
	_start_button.pressed.connect(_network_session.begin_match)
	_disconnect_button.pressed.connect(_network_session.leave_to_menu)
	_ready_button.disabled = true
	_start_button.visible = false
	_disconnect_button.visible = not (
		multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	)
	_status_label.text = _network_session.last_status


func _on_host_pressed() -> void:
	if _network_session.host_game() == OK:
		_set_connection_controls_enabled(false)
		_ready_button.disabled = false
		_start_button.visible = true
		_disconnect_button.visible = true


func _on_join_pressed() -> void:
	if _network_session.join_game(_address_edit.text) == OK:
		_set_connection_controls_enabled(false)
		_disconnect_button.visible = true


func _on_public_pressed() -> void:
	if _network_session.join_public_server() == OK:
		_set_connection_controls_enabled(false)
		_disconnect_button.visible = true


func _on_status_changed(message: String) -> void:
	_status_label.text = message


func _on_player_assigned(_player_id: int) -> void:
	_ready_button.disabled = false


func _on_lobby_changed(connected_players: int, ready_players: int, can_start: bool) -> void:
	_lobby_label.text = "Игроки: %d/2 | готовы: %d/2" % [connected_players, ready_players]
	_start_button.disabled = not can_start


func _set_connection_controls_enabled(enabled: bool) -> void:
	_address_edit.editable = enabled
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled
	_public_button.disabled = not enabled
	_solo_button.disabled = not enabled


func _on_session_closed() -> void:
	_set_connection_controls_enabled(true)
	_ready_button.set_pressed_no_signal(false)
	_ready_button.disabled = true
	_start_button.visible = false
	_disconnect_button.visible = false
	_lobby_label.text = "Игроки: 0/2 | готовы: 0/2"
