class_name HUD
extends PanelContainer

@onready var _game_state: GameState = get_node("../../Simulation/GameState") as GameState
@onready var _resource_label: Label = %ResourceLabel
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
	_refresh_resources()
	_refresh_selected_income()
	_refresh_debug_label()
	_refresh_strike_status()


func on_resources_changed(player_id: int, water: int, gold: int) -> void:
	if player_id == _perspective_player_id:
		_resource_label.text = "Запасы: вода %d | золото %d" % [water, gold]


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
	_refresh_selected_income()
	_refresh_strike_status()


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
	if mode == HumanController.InputMode.AIMING_BOMB:
		_mode_label.text = "Режим: выберите цель бомбы (Esc — отмена)"
	elif mode == HumanController.InputMode.AIMING_MISSILE:
		_mode_label.text = "Режим: выберите цель ракеты (Esc — отмена)"
	else:
		_mode_label.text = "Режим: движение | B — бомба | M — ракета"


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
	_debug_label.text = "F1 обзор: %s | F2 сторона: %d" % [
		visibility_text,
		_perspective_player_id,
	]


func _refresh_strike_status() -> void:
	var player: PlayerState = _game_state.get_player_state(_perspective_player_id)
	if player == null:
		return
	var bomb_status: String
	if player.bomb_cooldown_ticks == 0:
		bomb_status = "Бомба: %d воды | готова" % GameState.BOMB_WATER_COST
	else:
		var bomb_seconds: float = (
			player.bomb_cooldown_ticks * GameState.SIMULATION_TICK_SECONDS
		)
		bomb_status = "Бомба: перезарядка %.2f с" % bomb_seconds
	var missile_status: String
	if player.missile_cooldown_ticks == 0:
		missile_status = "Ракета: %d золота | готова" % GameState.MISSILE_GOLD_COST
	else:
		var missile_seconds: float = (
			player.missile_cooldown_ticks * GameState.SIMULATION_TICK_SECONDS
		)
		missile_status = "Ракета: перезарядка %.2f с" % missile_seconds
	_bomb_label.text = "%s\n%s" % [bomb_status, missile_status]
