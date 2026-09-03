class_name WorldPresenter
extends Node

const STRIKE_VIEW_SCENE := preload("res://scenes/combat/strike_view.tscn")
const REVEAL_ZONE_VIEW_SCENE := preload("res://scenes/combat/reveal_zone_view.tscn")
const UNIT_VIEW_SCENE := preload("res://scenes/units/unit_view.tscn")
const TEAM_COLORS: Array[Color] = [Color("#67d5ff"), Color("#ef4f45")]

@export var perspective_player_id := 0

@onready var _game_state: GameState = %GameState
@onready var _unit_views: Node2D = %UnitViews
@onready var _telegraph_views: Node2D = $"../TelegraphViews"
@onready var _reveal_views: Node2D = $"../RevealViews"

var _views_by_unit_id: Dictionary[int, UnitView] = {}
var _strike_views: Dictionary[int, StrikeView] = {}
var _reveal_zone_views: Dictionary[int, RevealZoneView] = {}
var _strike_preview: StrikeView


func _ready() -> void:
	_game_state.unit_spawned.connect(on_unit_spawned)
	_game_state.match_ended.connect(on_match_ended)
	for child: Node in _unit_views.get_children():
		if child is UnitView:
			var view: UnitView = child as UnitView
			_views_by_unit_id[view.unit_id] = view
			view.snap_to_position(_game_state.get_unit_position(view.unit_id))
	_refresh_visibility()
	_refresh_upstream_indicators()


func on_unit_spawned(unit_id: int, owner_id: int, map_position: Vector2) -> void:
	var view: UnitView = UNIT_VIEW_SCENE.instantiate() as UnitView
	view.unit_id = unit_id
	view.map_position = map_position
	view.team_color = TEAM_COLORS[owner_id]
	_unit_views.add_child(view)
	_views_by_unit_id[unit_id] = view
	view.snap_to_position(map_position)
	view.visible = _game_state.is_unit_visible_to(unit_id, perspective_player_id)
	_refresh_upstream_indicators()


func on_match_ended(_winner_player_id: int) -> void:
	if _strike_preview != null:
		_strike_preview.visible = false
	for view: StrikeView in _strike_views.values():
		view.queue_free()
	_strike_views.clear()
	for view: RevealZoneView in _reveal_zone_views.values():
		view.queue_free()
	_reveal_zone_views.clear()


func on_unit_moved(
		unit_id: int,
		_from: Vector2,
		to: Vector2,
		duration_seconds: float
) -> void:
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.move_to_position(to, duration_seconds)
	_refresh_upstream_indicators()


func on_selected_unit_changed(unit_id: int) -> void:
	for current_unit_id: int in _views_by_unit_id:
		var view: UnitView = _views_by_unit_id[current_unit_id]
		view.set_selected(current_unit_id == unit_id)


func on_unit_gathering_changed(unit_id: int, resource_type: int) -> void:
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.set_gathering(resource_type != UnitState.ResourceType.NONE)
	_refresh_upstream_indicators()


func on_unit_visibility_changed(player_id: int, unit_id: int, visible: bool) -> void:
	if player_id != perspective_player_id:
		return
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.visible = visible
	_refresh_reveal_visibility()


func set_perspective(player_id: int) -> void:
	perspective_player_id = player_id
	_refresh_visibility()
	_refresh_reveal_visibility()
	_refresh_upstream_indicators()


func on_strike_scheduled(strike_id: int) -> void:
	var strike: StrikeState = _game_state.get_strike(strike_id)
	if strike == null:
		return
	var view: StrikeView = STRIKE_VIEW_SCENE.instantiate() as StrikeView
	_telegraph_views.add_child(view)
	view.configure(
		strike.id,
		strike.target,
		strike.type,
		strike.damage_radius,
		strike.reveal_radius
	)
	_strike_views[strike.id] = view


func on_strike_detonated(strike_id: int, _position: Vector2) -> void:
	var view: StrikeView = _strike_views.get(strike_id)
	if view != null:
		view.queue_free()
		_strike_views.erase(strike_id)


func on_reveal_zone_created(zone_id: int) -> void:
	var zone: RevealZoneState = _game_state.get_reveal_zone(zone_id)
	if zone == null:
		return
	var view: RevealZoneView = REVEAL_ZONE_VIEW_SCENE.instantiate() as RevealZoneView
	_reveal_views.add_child(view)
	view.configure(zone.id, zone.owner_id, zone.center, zone.radius)
	_reveal_zone_views[zone.id] = view
	_refresh_reveal_visibility()


func on_reveal_zone_removed(zone_id: int) -> void:
	var view: RevealZoneView = _reveal_zone_views.get(zone_id)
	if view != null:
		view.queue_free()
		_reveal_zone_views.erase(zone_id)


func on_unit_destroyed(unit_id: int, _position: Vector2) -> void:
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.set_selected(false)
		view.set_gathering(false)
		view.set_upstream_count(0, false)
		view.visible = false
	_refresh_upstream_indicators()


func on_bomb_target_preview_changed(
		map_position: Vector2,
		strike_type: StrikeState.Type,
		damage_radius: float,
		reveal_radius: float,
		valid: bool,
		visible: bool
) -> void:
	if _strike_preview == null:
		_strike_preview = STRIKE_VIEW_SCENE.instantiate() as StrikeView
		_telegraph_views.add_child(_strike_preview)
	_strike_preview.visible = visible
	if visible:
		_strike_preview.configure(
			-1,
			map_position,
			strike_type,
			damage_radius,
			reveal_radius,
			true,
			valid
		)


func _refresh_visibility() -> void:
	for unit_id: int in _views_by_unit_id:
		var view: UnitView = _views_by_unit_id[unit_id]
		view.visible = _game_state.is_unit_visible_to(unit_id, perspective_player_id)


func _refresh_upstream_indicators() -> void:
	for unit_id: int in _views_by_unit_id:
		var view: UnitView = _views_by_unit_id[unit_id]
		var upstream_count: int = _game_state.get_upstream_gatherer_count_for_unit(
			unit_id,
			perspective_player_id
		)
		view.set_upstream_count(maxi(0, upstream_count), upstream_count >= 0)


func _refresh_reveal_visibility() -> void:
	for zone_id: int in _reveal_zone_views:
		var view: RevealZoneView = _reveal_zone_views[zone_id]
		# The detonation and its affected area are public information. Keeping
		# every active circle visible also prevents perspective switches from
		# hiding an earlier strike while its reveal effect is still active.
		view.visible = true
