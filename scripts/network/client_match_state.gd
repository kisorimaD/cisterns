class_name ClientMatchState
extends Node

signal tick_advanced(tick: int)
signal unit_spawned(unit_id: int, owner_id: int, position: Vector2)
signal unit_moved(unit_id: int, from: Vector2, to: Vector2, duration_seconds: float)
signal unit_removed(unit_id: int)
signal unit_destroyed(unit_id: int, owner_id: int, position: Vector2)
signal unit_gathering_changed(unit_id: int, resource_type: int)
signal resources_changed(player_id: int, water: int, gold: int)
signal strike_scheduled(strike_id: int)
signal strike_detonated(strike_id: int, position: Vector2)
signal strike_impacted(
	strike_id: int,
	position: Vector2,
	strike_type: int,
	damage_radius: float
)
signal reveal_zone_created(zone_id: int)
signal reveal_zone_removed(zone_id: int)
signal command_rejected(player_id: int, command_type: int, reason: StringName)
signal match_ended(winner_player_id: int)

var rules: GameRules = preload("res://resources/default_game_rules.tres")
var local_player_id := -1
var current_tick := 0
var units: Dictionary[int, Dictionary] = {}
var strikes: Dictionary[int, Dictionary] = {}
var reveal_zones: Dictionary[int, Dictionary] = {}
var player: Dictionary = {}
var match_finished := false
var winner_player_id := -1
var metrics: Dictionary = {}
var _destroyed_unit_ids: Dictionary[int, bool] = {}

@onready var _network_session: NetworkSessionService = get_node("/root/NetworkSession")


func apply_snapshot(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or snapshot.get("match_id", -1) != _network_session.current_match_id:
		return
	if snapshot.get("protocol_version", -1) != NetworkProtocol.VERSION:
		_network_session.leave_to_menu("Несовместимый снимок состояния")
		return
	local_player_id = snapshot.get("player_id", -1)
	current_tick = snapshot.get("tick", current_tick)
	_apply_units(snapshot.get("units", []))
	_apply_strikes(snapshot.get("strikes", []))
	_apply_reveal_zones(snapshot.get("reveal_zones", []))
	player = snapshot.get("player", {}).duplicate(true)
	resources_changed.emit(
		local_player_id,
		player.get("water", 0),
		player.get("gold", 0)
	)
	var was_finished := match_finished
	match_finished = snapshot.get("match_finished", false)
	winner_player_id = snapshot.get("winner_player_id", -1)
	metrics = snapshot.get("metrics", {}).duplicate(true)
	tick_advanced.emit(current_tick)
	if match_finished and not was_finished:
		match_ended.emit(winner_player_id)


func reject_local_command(command_type: int, reason: StringName) -> void:
	command_rejected.emit(local_player_id, command_type, reason)


func get_player_unit_at_position(map_position: Vector2) -> int:
	var nearest_id := -1
	var nearest_distance := rules.unit_selection_radius
	for unit_id: int in units:
		var unit: Dictionary = units[unit_id]
		if unit.get("owner_id", -1) != local_player_id:
			continue
		var distance: float = (unit.get("position", Vector2.ZERO) as Vector2).distance_to(map_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_id = unit_id
	return nearest_id


func get_unit_position(unit_id: int) -> Vector2:
	return units.get(unit_id, {}).get("position", Vector2(-1.0, -1.0))


func get_player_unit_ids() -> Array[int]:
	var result: Array[int] = []
	for unit_id: int in units:
		if units[unit_id].get("owner_id", -1) == local_player_id:
			result.append(unit_id)
	result.sort()
	return result


func get_unit_income_preview(unit_id: int) -> ResourceSample:
	var result := ResourceSample.new()
	var unit: Dictionary = units.get(unit_id, {})
	result.water_income = unit.get("water_income", 0)
	result.gold_income = unit.get("gold_income", 0)
	return result


func get_upstream_count(unit_id: int) -> int:
	return units.get(unit_id, {}).get("upstream_count", -1)


func is_unit_detected(unit_id: int) -> bool:
	return units.get(unit_id, {}).get("detected_by_enemy", false)


func is_unit_threatened_by_airstrike(unit_id: int) -> bool:
	return units.get(unit_id, {}).get("airstrike_threatened", false)


func get_strike(strike_id: int) -> Dictionary:
	return strikes.get(strike_id, {})


func get_reveal_zone(zone_id: int) -> Dictionary:
	return reveal_zones.get(zone_id, {})


func get_match_metrics() -> Dictionary:
	return metrics


func apply_strike_impact(record: Dictionary) -> void:
	if record.get("match_id", -1) != _network_session.current_match_id:
		return
	strike_impacted.emit(
		record.get("id", -1),
		record.get("target", Vector2.ZERO),
		record.get("type", StrikeState.Type.BOMB),
		record.get("damage_radius", 0.0)
	)


func apply_unit_destroyed(record: Dictionary) -> void:
	if record.get("match_id", -1) != _network_session.current_match_id:
		return
	var unit_id: int = record.get("id", -1)
	if unit_id < 0 or _destroyed_unit_ids.has(unit_id):
		return
	_destroyed_unit_ids[unit_id] = true
	var was_present := units.has(unit_id)
	units.erase(unit_id)
	unit_destroyed.emit(
		unit_id,
		record.get("owner_id", -1),
		record.get("position", Vector2.ZERO)
	)
	if was_present:
		unit_removed.emit(unit_id)


func _apply_units(records: Array) -> void:
	var next_units: Dictionary[int, Dictionary] = {}
	for value: Variant in records:
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		var unit_id: int = record.get("id", -1)
		if unit_id < 0 or _destroyed_unit_ids.has(unit_id):
			continue
		next_units[unit_id] = record.duplicate(true)
		if not units.has(unit_id):
			units[unit_id] = next_units[unit_id]
			unit_spawned.emit(unit_id, record.get("owner_id", -1), record.get("position", Vector2.ZERO))
			unit_gathering_changed.emit(unit_id, record.get("gathering_type", -1))
			continue
		var previous: Dictionary = units[unit_id]
		var from: Vector2 = previous.get("position", Vector2.ZERO)
		var to: Vector2 = record.get("position", from)
		if not from.is_equal_approx(to):
			unit_moved.emit(unit_id, from, to, rules.simulation_tick_seconds)
		if previous.get("gathering_type", -1) != record.get("gathering_type", -1):
			unit_gathering_changed.emit(unit_id, record.get("gathering_type", -1))
	for unit_id: int in units:
		if not next_units.has(unit_id):
			unit_removed.emit(unit_id)
	units = next_units


func _apply_strikes(records: Array) -> void:
	var next_strikes: Dictionary[int, Dictionary] = {}
	for value: Variant in records:
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		var strike_id: int = record.get("id", -1)
		if strike_id < 0:
			continue
		next_strikes[strike_id] = record.duplicate(true)
		if not strikes.has(strike_id):
			strikes[strike_id] = next_strikes[strike_id]
			strike_scheduled.emit(strike_id)
	for strike_id: int in strikes:
		if not next_strikes.has(strike_id):
			strike_detonated.emit(strike_id, strikes[strike_id].get("target", Vector2.ZERO))
	strikes = next_strikes


func _apply_reveal_zones(records: Array) -> void:
	var next_zones: Dictionary[int, Dictionary] = {}
	for value: Variant in records:
		if not value is Dictionary:
			continue
		var record: Dictionary = value
		var zone_id: int = record.get("id", -1)
		if zone_id < 0:
			continue
		next_zones[zone_id] = record.duplicate(true)
		if not reveal_zones.has(zone_id):
			reveal_zones[zone_id] = next_zones[zone_id]
			reveal_zone_created.emit(zone_id)
	for zone_id: int in reveal_zones:
		if not next_zones.has(zone_id):
			reveal_zone_removed.emit(zone_id)
	reveal_zones = next_zones
