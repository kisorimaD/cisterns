class_name WorldPresenter
extends Node

const STRIKE_VIEW_SCENE := preload("res://scenes/combat/strike_view.tscn")
const REVEAL_ZONE_VIEW_SCENE := preload("res://scenes/combat/reveal_zone_view.tscn")
const UNIT_VIEW_SCENE := preload("res://scenes/units/unit_view.tscn")
const EXPLOSION_VIEW_SCRIPT := preload("res://scripts/presentation/explosion_view.gd")
const TEAM_COLORS: Array[Color] = [Color("#67d5ff"), Color("#ef4f45")]

@onready var _client_state: ClientMatchState = %ClientMatchState
@onready var _unit_views: Node2D = %UnitViews
@onready var _telegraph_views: Node2D = $"../TelegraphViews"
@onready var _reveal_views: Node2D = $"../RevealViews"
@onready var _effects: Node2D = $"../Effects"

var _views_by_unit_id: Dictionary[int, UnitView] = {}
var _strike_views: Dictionary[int, StrikeView] = {}
var _reveal_zone_views: Dictionary[int, RevealZoneView] = {}
var _strike_preview: StrikeView
var _airstrike_target_previews: Array[StrikeView] = []


func _ready() -> void:
	pass


func on_unit_spawned(unit_id: int, owner_id: int, map_position: Vector2) -> void:
	var view: UnitView = UNIT_VIEW_SCENE.instantiate() as UnitView
	view.unit_id = unit_id
	view.map_position = map_position
	view.team_color = TEAM_COLORS[owner_id]
	_unit_views.add_child(view)
	_views_by_unit_id[unit_id] = view
	view.snap_to_position(map_position)
	view.visible = true
	_refresh_upstream_indicators()


func on_match_ended(_winner_player_id: int) -> void:
	if _strike_preview != null:
		_strike_preview.visible = false
	_clear_airstrike_target_previews()
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
	if player_id != _client_state.local_player_id:
		return
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.visible = visible
	_refresh_reveal_visibility()


func on_strike_scheduled(strike_id: int) -> void:
	var strike: Dictionary = _client_state.get_strike(strike_id)
	if strike.is_empty():
		return
	var view: StrikeView = STRIKE_VIEW_SCENE.instantiate() as StrikeView
	_telegraph_views.add_child(view)
	view.configure(
		strike.get("id", strike_id),
		strike.get("target", Vector2.ZERO),
		strike.get("type", StrikeState.Type.BOMB),
		strike.get("damage_radius", 0.0),
		strike.get("reveal_radius", 0.0)
	)
	_strike_views[strike_id] = view


func on_strike_detonated(strike_id: int, _position: Vector2) -> void:
	var view: StrikeView = _strike_views.get(strike_id)
	if view != null:
		view.queue_free()
		_strike_views.erase(strike_id)


func on_strike_impacted(
		strike_id: int,
		map_position: Vector2,
		strike_type: StrikeState.Type,
		damage_radius: float
) -> void:
	on_strike_detonated(strike_id, map_position)
	var effect: StrikeView = STRIKE_VIEW_SCENE.instantiate() as StrikeView
	_effects.add_child(effect)
	effect.configure(strike_id, map_position, strike_type, damage_radius, 0.0)
	effect.scale = Vector2(0.7, 0.7)
	var tween: Tween = effect.create_tween()
	tween.set_parallel(true)
	tween.tween_property(effect, "scale", Vector2(1.25, 1.25), 0.4)
	tween.tween_property(effect, "modulate:a", 0.0, 0.4)
	tween.finished.connect(effect.queue_free)


func on_reveal_zone_created(zone_id: int) -> void:
	var zone: Dictionary = _client_state.get_reveal_zone(zone_id)
	if zone.is_empty():
		return
	var view: RevealZoneView = REVEAL_ZONE_VIEW_SCENE.instantiate() as RevealZoneView
	_reveal_views.add_child(view)
	view.configure(
		zone.get("id", zone_id),
		zone.get("owner_id", -1),
		zone.get("center", Vector2.ZERO),
		zone.get("radius", 0.0)
	)
	_reveal_zone_views[zone_id] = view
	_refresh_reveal_visibility()


func on_reveal_zone_removed(zone_id: int) -> void:
	var view: RevealZoneView = _reveal_zone_views.get(zone_id)
	if view != null:
		view.queue_free()
		_reveal_zone_views.erase(zone_id)


func on_unit_removed(unit_id: int) -> void:
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.queue_free()
		_views_by_unit_id.erase(unit_id)
	_refresh_upstream_indicators()


func on_unit_destroyed(unit_id: int, _owner_id: int, map_position: Vector2) -> void:
	var view: UnitView = _views_by_unit_id.get(unit_id)
	if view != null:
		view.queue_free()
		_views_by_unit_id.erase(unit_id)
	var explosion: Node2D = EXPLOSION_VIEW_SCRIPT.new()
	explosion.position = map_position
	_effects.add_child(explosion)
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


func on_airstrike_targets_changed(
		targets: PackedVector2Array,
		damage_radius: float,
		visible: bool
) -> void:
	_clear_airstrike_target_previews()
	if not visible:
		return
	for target: Vector2 in targets:
		var preview: StrikeView = STRIKE_VIEW_SCENE.instantiate() as StrikeView
		_telegraph_views.add_child(preview)
		preview.configure(
			-1,
			target,
			StrikeState.Type.MISSILE,
			damage_radius,
			0.0,
			true,
			true
		)
		_airstrike_target_previews.append(preview)


func _refresh_upstream_indicators() -> void:
	for unit_id: int in _views_by_unit_id:
		var view: UnitView = _views_by_unit_id[unit_id]
		var upstream_count: int = _client_state.get_upstream_count(unit_id)
		view.set_upstream_count(maxi(0, upstream_count), upstream_count >= 0)
		view.set_danger_state(
			_client_state.is_unit_detected(unit_id),
			_client_state.is_unit_threatened_by_airstrike(unit_id)
		)


func on_tick_advanced(_tick: int) -> void:
	_refresh_upstream_indicators()


func _refresh_reveal_visibility() -> void:
	for zone_id: int in _reveal_zone_views:
		var view: RevealZoneView = _reveal_zone_views[zone_id]
		# The detonation and its affected area are public information. Keeping
		# every active circle visible also prevents perspective switches from
		# hiding an earlier strike while its reveal effect is still active.
		view.visible = true


func _clear_airstrike_target_previews() -> void:
	for preview: StrikeView in _airstrike_target_previews:
		preview.queue_free()
	_airstrike_target_previews.clear()
