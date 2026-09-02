class_name HUD
extends PanelContainer

@onready var _game_state: GameState = get_node("../../Simulation/GameState") as GameState
@onready var _resource_label: Label = %ResourceLabel
@onready var _selected_label: Label = %SelectedIncomeLabel
@onready var _target_label: Label = %TargetIncomeLabel
@onready var _debug_label: Label = %DebugLabel

var _selected_unit_id := -1
var _perspective_player_id := GameState.PLAYER_ID
var _debug_full_visibility := false


func _ready() -> void:
	_refresh_resources()
	_refresh_selected_income()
	_refresh_debug_label()


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


func on_controlled_player_changed(player_id: int) -> void:
	_perspective_player_id = player_id
	_selected_unit_id = -1
	_refresh_resources()
	_refresh_selected_income()
	_refresh_debug_label()


func on_debug_full_visibility_changed(enabled: bool) -> void:
	_debug_full_visibility = enabled
	_refresh_debug_label()


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
	var visibility_text := "вкл" if _debug_full_visibility else "выкл"
	_debug_label.text = "F1 обзор: %s | F2 сторона: %d" % [
		visibility_text,
		_perspective_player_id,
	]
