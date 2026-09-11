class_name HUD
extends PanelContainer

signal bomb_requested
signal missile_requested

@onready var _game_state: GameState = get_node("../../Simulation/GameState") as GameState
@onready var _resource_label: Label = %ResourceLabel
@onready var _water_label: Label = %WaterLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _bomb_button: Button = %BombButton
@onready var _missile_button: Button = %MissileButton
@onready var _selected_label: Label = %SelectedIncomeLabel
@onready var _target_label: Label = %TargetIncomeLabel
@onready var _debug_label: Label = %DebugLabel
@onready var _bomb_label: Label = %BombLabel
@onready var _mode_label: Label = %ModeLabel
@onready var _error_label: Label = %ErrorLabel

var _selected_unit_id := -1
var _perspective_player_id := GameState.PLAYER_ID
var _debug_full_visibility := false


func _ready() -> void:
	_bomb_button.pressed.connect(bomb_requested.emit)
	_missile_button.pressed.connect(missile_requested.emit)
	_refresh_resources()
	_refresh_selected_income()
	_refresh_debug_label()
	_refresh_strike_status()
	_refresh_match_result()


func on_resources_changed(player_id: int, water: int, gold: int) -> void:
	if player_id == _perspective_player_id:
		var player: PlayerState = _game_state.get_player_state(player_id)
		_water_label.text = str(water)
		_gold_label.text = str(gold)
		_resource_label.text = "Юниты: %d/%d" % [
			player.active_unit_ids.size(),
			_game_state.rules.maximum_active_units,
		]


func on_selected_unit_changed(unit_id: int) -> void:
	_selected_unit_id = unit_id
	_refresh_selected_income()


func on_target_preview_changed(
		map_position: Vector2,
		water_income: int,
		gold_income: int,
		valid: bool
) -> void:
	if not valid:
		_target_label.text = "Курсор вне карты"
		return
	_target_label.text = "Точка (%d, %d): вода %d | золото %d" % [
		roundi(map_position.x),
		roundi(map_position.y),
		water_income,
		gold_income,
	]


func on_tick_advanced(_tick: int) -> void:
	_refresh_resources()
	_refresh_selected_income()
	_refresh_strike_status()
	_refresh_debug_label()
	_refresh_match_result()


func on_controlled_player_changed(player_id: int) -> void:
	_perspective_player_id = player_id
	_selected_unit_id = -1
	_refresh_resources()
	_refresh_selected_income()
	_refresh_debug_label()
	_refresh_strike_status()


func on_debug_full_visibility_changed(enabled: bool) -> void:
	_debug_full_visibility = enabled
	_refresh_debug_label()


func on_input_mode_changed(mode: int) -> void:
	_bomb_button.set_pressed_no_signal(mode == HumanController.InputMode.AIMING_BOMB)
	_missile_button.set_pressed_no_signal(mode == HumanController.InputMode.AIMING_MISSILE)
	if mode == HumanController.InputMode.AIMING_BOMB:
		_mode_label.text = "Режим: выберите цель бомбы (Esc — отмена)"
	elif mode == HumanController.InputMode.AIMING_MISSILE:
		_mode_label.text = "Режим: выберите цель ракеты (Esc — отмена)"
	elif mode == HumanController.InputMode.PLACING_REPLACEMENT:
		_mode_label.text = "Режим: выберите точку в своей стартовой области"
	else:
		_mode_label.text = "Режим: выберите юнит | B/M — удары | R — замена"


func on_command_rejected(player_id: int, _command_type: int, reason: StringName) -> void:
	if player_id != _perspective_player_id:
		return
	_error_label.text = "Команда отклонена: %s" % reason


func _refresh_resources() -> void:
	var player: PlayerState = _game_state.get_player_state(_perspective_player_id)
	if player != null:
		on_resources_changed(player.id, player.water, player.gold)


func _refresh_selected_income() -> void:
	if _selected_unit_id == -1:
		_selected_label.text = "Выберите цистерну"
		return
	var income: ResourceSample = _game_state.get_unit_income_preview(_selected_unit_id)
	_selected_label.text = "Юнит %d: вода %d | золото %d" % [
		_selected_unit_id,
		income.water_income,
		income.gold_income,
	]


func _refresh_debug_label() -> void:
	var visibility_text: String = "вкл" if _debug_full_visibility else "выкл"
	var event_text := ""
	for event: String in _game_state.get_recent_events(3):
		if not event_text.is_empty():
			event_text += "\n"
		event_text += event
	_debug_label.text = "F1 обзор: %s | F2 сторона: %d\n%s" % [
		visibility_text,
		_perspective_player_id,
		event_text,
	]


func _refresh_strike_status() -> void:
	var player: PlayerState = _game_state.get_player_state(_perspective_player_id)
	if player == null:
		return
	var bomb_status: String
	if player.bomb_cooldown_ticks == 0:
		bomb_status = "%d воды" % _game_state.rules.bomb_water_cost
		_bomb_button.tooltip_text = "Бомба: %d воды" % _game_state.rules.bomb_water_cost
	else:
		var bomb_seconds: float = (
			player.bomb_cooldown_ticks * _game_state.rules.simulation_tick_seconds
		)
		bomb_status = "%.1f с" % bomb_seconds
		_bomb_button.tooltip_text = "Бомба перезаряжается"
	var missile_status: String
	if player.missile_cooldown_ticks == 0:
		missile_status = "%d золота" % _game_state.rules.missile_gold_cost
		_missile_button.tooltip_text = "Ракета: %d золота" % _game_state.rules.missile_gold_cost
	else:
		var missile_seconds: float = (
			player.missile_cooldown_ticks * _game_state.rules.simulation_tick_seconds
		)
		missile_status = "%.1f с" % missile_seconds
		_missile_button.tooltip_text = "Ракета перезаряжается"
	_bomb_button.text = bomb_status
	_missile_button.text = missile_status
	_bomb_button.disabled = (
		_game_state.match_finished
		or player.active_unit_ids.is_empty()
		or player.water < _game_state.rules.bomb_water_cost
		or player.bomb_cooldown_ticks > 0
	)
	_missile_button.disabled = (
		_game_state.match_finished
		or player.active_unit_ids.is_empty()
		or player.gold < _game_state.rules.missile_gold_cost
		or player.missile_cooldown_ticks > 0
	)
	var replacement_status: String
	var replacement_cost: int = _game_state.get_next_replacement_cost(
		_perspective_player_id
	)
	if player.active_unit_ids.is_empty():
		replacement_status = "Замена: %d золота | недоступна" % replacement_cost
	elif player.active_unit_ids.size() >= _game_state.rules.maximum_active_units:
		replacement_status = "Замена: %d золота | полный состав" % replacement_cost
	else:
		replacement_status = "Замена: %d золота | готова" % replacement_cost
	_bomb_label.text = replacement_status


func _refresh_match_result() -> void:
	if not _game_state.match_finished:
		return
	_mode_label.text = "Матч завершён"
	var metrics: Dictionary = _game_state.get_match_metrics()
	var result_text: String
	if _game_state.winner_player_id == -1:
		result_text = "Ничья"
	elif _game_state.winner_player_id == _perspective_player_id:
		result_text = "Победа!"
	else:
		result_text = "Поражение"
	_error_label.text = (
		"%s Время: %.1f с | команды: %d/%d | удары: %d | потери: %d | замены: %d\n"
		+ "Enter — новый матч"
	) % [
		result_text,
		metrics["elapsed_seconds"],
		metrics["commands_accepted"],
		metrics["commands_received"],
		metrics["strikes_launched"],
		metrics["units_destroyed"],
		metrics["replacements_purchased"],
	]
