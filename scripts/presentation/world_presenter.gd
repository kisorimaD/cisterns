class_name WorldPresenter
extends Node

@export var perspective_player_id := 0

@onready var _game_state: GameState = %GameState
@onready var _unit_views: Node2D = %UnitViews

var _views_by_unit_id: Dictionary[int, UnitView] = {}


func _ready() -> void:
	for child: Node in _unit_views.get_children():
		if child is UnitView:
			var view: UnitView = child as UnitView
			_views_by_unit_id[view.unit_id] = view
			view.snap_to_position(_game_state.get_unit_position(view.unit_id))
	_refresh_visibility()


func on_unit_moved(
		unit_id: int,
		_from: Vector2,
		to: Vector2,
		duration_seconds: float
) -> void:
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.move_to_position(to, duration_seconds)


func on_selected_unit_changed(unit_id: int) -> void:
	for current_unit_id: int in _views_by_unit_id:
		var view: UnitView = _views_by_unit_id[current_unit_id]
		view.set_selected(current_unit_id == unit_id)


func on_unit_gathering_changed(unit_id: int, resource_type: int) -> void:
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.set_gathering(resource_type != UnitState.ResourceType.NONE)


func on_unit_visibility_changed(player_id: int, unit_id: int, visible: bool) -> void:
	if player_id != perspective_player_id:
		return
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.visible = visible


func set_perspective(player_id: int) -> void:
	perspective_player_id = player_id
	_refresh_visibility()


func _refresh_visibility() -> void:
	for unit_id: int in _views_by_unit_id:
		var view: UnitView = _views_by_unit_id[unit_id]
		view.visible = _game_state.is_unit_visible_to(unit_id, perspective_player_id)
