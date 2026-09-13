class_name HUD
extends PanelContainer

signal bomb_requested
signal missile_requested
signal replacement_requested

@onready var _client_state: ClientMatchState = %ClientMatchState
@onready var _water_label: Label = %WaterLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _bomb_button: Button = %BombButton
@onready var _missile_button: Button = %MissileButton
@onready var _repair_button: Button = %RepairButton
@onready var _bomb_price: Label = %BombPrice
@onready var _missile_price: Label = %MissilePrice
@onready var _repair_price: Label = %RepairPrice
@onready var _status_label: Label = %StatusLabel
@onready var _network_session: NetworkSessionService = get_node("/root/NetworkSession")

var _perspective_player_id := -1


func _ready() -> void:
	_perspective_player_id = _network_session.local_player_id
	_bomb_button.pressed.connect(bomb_requested.emit)
	_missile_button.pressed.connect(missile_requested.emit)
	_repair_button.pressed.connect(replacement_requested.emit)
	_network_session.status_changed.connect(on_network_status_changed)
	_status_label.visible = false
	_refresh_resources()
	_refresh_abilities()


func on_resources_changed(player_id: int, water: int, gold: int) -> void:
	if player_id != _perspective_player_id:
		return
	_water_label.text = str(water)
	_gold_label.text = str(gold)
	_refresh_abilities()


func on_selected_unit_changed(_unit_id: int) -> void:
	pass


func on_tick_advanced(_tick: int) -> void:
	_refresh_resources()
	_refresh_abilities()
	_refresh_match_result()


func on_input_mode_changed(mode: int) -> void:
	_bomb_button.set_pressed_no_signal(mode == HumanController.InputMode.AIMING_BOMB)
	_missile_button.set_pressed_no_signal(mode == HumanController.InputMode.AIMING_MISSILE)
	_repair_button.set_pressed_no_signal(mode == HumanController.InputMode.PLACING_REPLACEMENT)
	if mode == HumanController.InputMode.AIMING_BOMB:
		_show_status("Выберите цель бомбы · Esc — отмена")
	elif mode == HumanController.InputMode.AIMING_MISSILE:
		_show_status("Выберите цель авиаудара · Esc — отмена")
	elif mode == HumanController.InputMode.PLACING_REPLACEMENT:
		_show_status("Выберите точку восстановления в стартовой зоне")
	else:
		_show_status("")


func on_airstrike_target_count_changed(selected_count: int, target_count: int) -> void:
	if selected_count >= target_count:
		return
	_show_status("Выберите цель авиаудара %d/%d · Esc — отмена" % [
		selected_count + 1,
		target_count,
	])


func on_command_rejected(player_id: int, _command_type: int, reason: StringName) -> void:
	if player_id == _perspective_player_id:
		_show_status("Команда отклонена: %s" % reason)


func on_network_status_changed(message: String) -> void:
	_show_status(message)


func _refresh_resources() -> void:
	if _client_state.player.is_empty():
		return
	on_resources_changed(
		_perspective_player_id,
		_client_state.player.get("water", 0),
		_client_state.player.get("gold", 0)
	)


func _refresh_abilities() -> void:
	var player: Dictionary = _client_state.player
	var replacement_cost: int = player.get("replacement_cost", 0)
	_bomb_price.text = str(_client_state.rules.bomb_water_cost)
	_missile_price.text = str(_client_state.rules.missile_gold_cost)
	_repair_price.text = str(replacement_cost)
	if player.is_empty():
		_bomb_button.disabled = true
		_missile_button.disabled = true
		_repair_button.disabled = true
		_bomb_price.modulate.a = 0.42
		_missile_price.modulate.a = 0.42
		_repair_price.modulate.a = 0.32
		return
	_bomb_button.disabled = (
		_client_state.match_finished
		or player.get("active_unit_count", 0) == 0
		or player.get("water", 0) < _client_state.rules.bomb_water_cost
		or player.get("bomb_cooldown_ticks", 0) > 0
	)
	_missile_button.disabled = (
		_client_state.match_finished
		or player.get("active_unit_count", 0) == 0
		or player.get("gold", 0) < _client_state.rules.missile_gold_cost
		or player.get("missile_cooldown_ticks", 0) > 0
	)
	_repair_button.disabled = (
		_client_state.match_finished
		or player.get("active_unit_count", 0) == 0
		or player.get("active_unit_count", 0) >= _client_state.rules.maximum_active_units
		or player.get("gold", 0) < replacement_cost
	)
	_bomb_price.modulate.a = 0.42 if _bomb_button.disabled else 1.0
	_missile_price.modulate.a = 0.42 if _missile_button.disabled else 1.0
	_repair_price.modulate.a = 0.32 if _repair_button.disabled else 1.0
	_bomb_button.tooltip_text = _ability_tooltip(
		"Бомба",
		_client_state.rules.bomb_water_cost,
		"воды",
		player.get("bomb_cooldown_ticks", 0)
	)
	_missile_button.tooltip_text = _ability_tooltip(
		"Авиаудар",
		_client_state.rules.missile_gold_cost,
		"золота",
		player.get("missile_cooldown_ticks", 0)
	)
	_repair_button.tooltip_text = "Восстановить цистерну: %d золота" % replacement_cost


func _ability_tooltip(title: String, price: int, resource: String, cooldown_ticks: int) -> String:
	if cooldown_ticks <= 0:
		return "%s: %d %s" % [title, price, resource]
	return "%s: перезарядка %.1f с" % [
		title,
		cooldown_ticks * _client_state.rules.simulation_tick_seconds,
	]


func _refresh_match_result() -> void:
	if not _client_state.match_finished:
		return
	var metrics: Dictionary = _client_state.get_match_metrics()
	var result_text: String
	if _client_state.winner_player_id == -1:
		result_text = "Ничья"
	elif _client_state.winner_player_id == _perspective_player_id:
		result_text = "Победа!"
	else:
		result_text = "Поражение"
	_show_status("%s · %.1f с · Enter — реванш · Esc — меню" % [
		result_text,
		metrics.get("elapsed_seconds", 0.0),
	])


func _show_status(message: String) -> void:
	_status_label.text = message
	_status_label.visible = not message.is_empty()
