class_name GameState
extends Node

signal tick_advanced(tick: int)
signal unit_moved(
	unit_id: int,
	from: Vector2,
	to: Vector2,
	duration_seconds: float
)
signal unit_destroyed(unit_id: int, position: Vector2)
signal resources_changed(player_id: int, water: int, gold: int)
signal gathering_result(unit_id: int, resource_type: int, amount: int)
signal unit_gathering_changed(unit_id: int, resource_type: int)
signal unit_visibility_changed(player_id: int, unit_id: int, visible: bool)
signal strike_scheduled(strike_id: int)
signal strike_detonated(strike_id: int, position: Vector2)
signal reveal_zone_created(zone_id: int)
signal reveal_zone_removed(zone_id: int)
signal command_rejected(player_id: int, command_type: int, reason: StringName)

const MAP_SIZE := Vector2(960.0, 672.0)
const SIMULATION_TICK_SECONDS := 0.25
const UNIT_MOVE_SPEED := 96.0
const UNIT_SELECTION_RADIUS := 22.0
const GATHERING_INTERVAL_TICKS := 8
const PLAYER_ID := 0
const PLAYER_COUNT := 2
const INITIAL_WATER := 12
const BOMB_WATER_COST := 6
const BOMB_COOLDOWN_TICKS := 20
const BOMB_WARNING_TICKS := 6
const BOMB_DAMAGE_RADIUS := 40.0
const BOMB_REVEAL_RADIUS := 80.0
const BOMB_REVEAL_LEAD_TICKS := 1
const BOMB_REVEAL_DURATION_TICKS := 12

var current_tick := 0
var units: Dictionary[int, UnitState] = {}
var players: Dictionary[int, PlayerState] = {}
var strikes: Dictionary[int, StrikeState] = {}
var reveal_zones: Dictionary[int, RevealZoneState] = {}
var debug_full_visibility := false

@onready var _map: GameMap = %Map

var _tick_accumulator := 0.0
var _pending_commands: Array[GameCommand] = []
var _expected_sequence_by_player: Dictionary[int, int] = {}
var _next_strike_id := 1
var _next_reveal_zone_id := 1
var _visibility_cache: Dictionary[String, bool] = {}


func _ready() -> void:
	for player_id: int in PLAYER_COUNT:
		players[player_id] = PlayerState.new(player_id)
		players[player_id].water = INITIAL_WATER
		_expected_sequence_by_player[player_id] = 0
	_add_unit(1, 0, Vector2(120.0, 120.0))
	_add_unit(2, 0, Vector2(120.0, 336.0))
	_add_unit(3, 0, Vector2(120.0, 552.0))
	_add_unit(101, 1, Vector2(840.0, 120.0))
	_add_unit(102, 1, Vector2(840.0, 336.0))
	_add_unit(103, 1, Vector2(840.0, 552.0))
	_rebuild_visibility_cache()


func _process(delta: float) -> void:
	_tick_accumulator += delta
	while _tick_accumulator >= SIMULATION_TICK_SECONDS:
		_tick_accumulator -= SIMULATION_TICK_SECONDS
		_advance_tick()


func queue_command(command: GameCommand) -> void:
	_pending_commands.append(command)


func get_player_unit_at_position(player_id: int, map_position: Vector2) -> int:
	var nearest_unit_id: int = -1
	var nearest_distance: float = UNIT_SELECTION_RADIUS
	for unit: UnitState in units.values():
		if not unit.alive or unit.owner_id != player_id:
			continue
		var distance: float = unit.position.distance_to(map_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			nearest_unit_id = unit.id
	return nearest_unit_id


func get_unit_position(unit_id: int) -> Vector2:
	var unit: UnitState = units.get(unit_id)
	return unit.position if unit != null else Vector2(-1.0, -1.0)


func get_player_state(player_id: int) -> PlayerState:
	return players.get(player_id)


func get_strike(strike_id: int) -> StrikeState:
	return strikes.get(strike_id)


func get_reveal_zone(zone_id: int) -> RevealZoneState:
	return reveal_zones.get(zone_id)


func is_unit_visible_to(unit_id: int, perspective_player_id: int) -> bool:
	var unit: UnitState = units.get(unit_id)
	if unit == null or not unit.alive or not players.has(perspective_player_id):
		return false
	if unit.owner_id == perspective_player_id or debug_full_visibility:
		return true
	for zone: RevealZoneState in reveal_zones.values():
		if (
			zone.owner_id == perspective_player_id
			and zone.center.distance_to(unit.position) <= zone.radius
		):
			return true
	return false


func set_debug_full_visibility(enabled: bool) -> void:
	if debug_full_visibility == enabled:
		return
	debug_full_visibility = enabled
	_refresh_visibility()


func get_income_preview_for_unit(unit_id: int, map_position: Vector2) -> ResourceSample:
	if not units.has(unit_id):
		return ResourceSample.new()
	var sample: ResourceSample = _map.sample_resources(map_position)
	if sample.water_income > 0:
		sample.water_income = maxi(
			0,
			sample.water_income - _count_upstream_gatherers(sample, unit_id)
		)
	return sample


func get_unit_income_preview(unit_id: int) -> ResourceSample:
	var unit: UnitState = units.get(unit_id)
	if unit == null or not unit.alive or unit.is_moving:
		return ResourceSample.new()
	return get_income_preview_for_unit(unit_id, unit.position)


func is_position_inside_map(map_position: Vector2) -> bool:
	return Rect2(Vector2.ZERO, MAP_SIZE).has_point(map_position)


func _advance_tick() -> void:
	_accept_pending_commands()
	_advance_units()
	_update_gathering_states()
	current_tick += 1
	if current_tick % GATHERING_INTERVAL_TICKS == 0:
		_gather_resources()
	_resolve_due_strikes()
	_expire_reveal_zones()
	_advance_cooldowns()
	_refresh_visibility()
	tick_advanced.emit(current_tick)


func _accept_pending_commands() -> void:
	var commands: Array[GameCommand] = _pending_commands
	_pending_commands = []
	for command: GameCommand in commands:
		_validate_and_apply(command)


func _validate_and_apply(command: GameCommand) -> void:
	if not players.has(command.player_id):
		_reject(command, &"unknown_player")
		return
	var expected_sequence: int = _expected_sequence_by_player[command.player_id]
	if command.sequence_number != expected_sequence:
		_reject(command, &"unexpected_sequence")
		return
	_expected_sequence_by_player[command.player_id] = expected_sequence + 1

	match command.type:
		GameCommand.Type.MOVE_UNIT:
			_apply_move_command(command)
		GameCommand.Type.LAUNCH_BOMB:
			_apply_bomb_command(command)
		_:
			_reject(command, &"unsupported_command")


func _apply_move_command(command: GameCommand) -> void:
	var unit: UnitState = units.get(command.unit_id)
	if unit == null or not unit.alive:
		_reject(command, &"unit_not_found")
		return
	if unit.owner_id != command.player_id:
		_reject(command, &"unit_not_owned")
		return
	if not is_position_inside_map(command.target):
		_reject(command, &"target_outside_map")
		return
	unit.movement_target = command.target
	unit.is_moving = not unit.position.is_equal_approx(command.target)
	if unit.gathering_resource_type != UnitState.ResourceType.NONE:
		unit.gathering_resource_type = UnitState.ResourceType.NONE
		unit_gathering_changed.emit(unit.id, unit.gathering_resource_type)


func _apply_bomb_command(command: GameCommand) -> void:
	var player: PlayerState = players.get(command.player_id)
	if player == null or player.active_unit_ids.is_empty():
		_reject(command, &"no_active_units")
		return
	if not is_position_inside_map(command.target):
		_reject(command, &"target_outside_map")
		return
	if player.water < BOMB_WATER_COST:
		_reject(command, &"not_enough_water")
		return
	if player.bomb_cooldown_ticks > 0:
		_reject(command, &"bomb_on_cooldown")
		return

	player.water -= BOMB_WATER_COST
	player.bomb_cooldown_ticks = BOMB_COOLDOWN_TICKS
	var strike: StrikeState = StrikeState.new(
		_next_strike_id,
		command.player_id,
		StrikeState.Type.BOMB,
		command.target,
		current_tick + BOMB_WARNING_TICKS,
		BOMB_DAMAGE_RADIUS,
		BOMB_REVEAL_RADIUS
	)
	strikes[strike.id] = strike
	_next_strike_id += 1
	resources_changed.emit(player.id, player.water, player.gold)
	strike_scheduled.emit(strike.id)


func _advance_units() -> void:
	for unit: UnitState in units.values():
		if not unit.alive or not unit.is_moving:
			continue

		var from: Vector2 = unit.position
		var maximum_distance: float = UNIT_MOVE_SPEED * SIMULATION_TICK_SECONDS
		unit.position = unit.position.move_toward(unit.movement_target, maximum_distance)
		if unit.position.is_equal_approx(unit.movement_target):
			unit.position = unit.movement_target
			unit.is_moving = false
		unit_moved.emit(unit.id, from, unit.position, SIMULATION_TICK_SECONDS)


func _update_gathering_states() -> void:
	for unit: UnitState in units.values():
		var previous_type: UnitState.ResourceType = unit.gathering_resource_type
		if not unit.alive or unit.is_moving:
			unit.gathering_resource_type = UnitState.ResourceType.NONE
			if unit.gathering_resource_type != previous_type:
				unit_gathering_changed.emit(unit.id, unit.gathering_resource_type)
			continue
		var sample: ResourceSample = _map.sample_resources(unit.position)
		if sample.water_income > 0:
			unit.gathering_resource_type = UnitState.ResourceType.WATER
		elif sample.gold_income > 0:
			unit.gathering_resource_type = UnitState.ResourceType.GOLD
		else:
			unit.gathering_resource_type = UnitState.ResourceType.NONE
		if unit.gathering_resource_type != previous_type:
			unit_gathering_changed.emit(unit.id, unit.gathering_resource_type)


func _gather_resources() -> void:
	for unit: UnitState in units.values():
		if not unit.alive or unit.gathering_resource_type == UnitState.ResourceType.NONE:
			continue
		var income: ResourceSample = get_unit_income_preview(unit.id)
		var amount: int = 0
		if unit.gathering_resource_type == UnitState.ResourceType.WATER:
			amount = income.water_income
			players[unit.owner_id].water += amount
		else:
			amount = income.gold_income
			players[unit.owner_id].gold += amount
		gathering_result.emit(unit.id, unit.gathering_resource_type, amount)
		var player: PlayerState = players[unit.owner_id]
		resources_changed.emit(player.id, player.water, player.gold)


func _count_upstream_gatherers(sample: ResourceSample, excluded_unit_id: int) -> int:
	if sample.river_id == -1:
		return 0
	var count: int = 0
	for unit: UnitState in units.values():
		if unit.id == excluded_unit_id or not unit.alive or unit.is_moving:
			continue
		var other_sample: ResourceSample = _map.sample_resources(unit.position)
		if (
			other_sample.water_income > 0
			and other_sample.river_id == sample.river_id
			and other_sample.flow_offset < sample.flow_offset
		):
			count += 1
	return count


func _resolve_due_strikes() -> void:
	var due_strikes: Array[StrikeState] = []
	var destroyed_unit_ids: Dictionary[int, bool] = {}
	var reveal_started: bool = false
	for strike: StrikeState in strikes.values():
		if (
			not strike.reveal_started
			and strike.impact_tick - current_tick <= BOMB_REVEAL_LEAD_TICKS
		):
			_create_reveal_zone(strike)
			reveal_started = true
		if strike.impact_tick > current_tick:
			continue
		due_strikes.append(strike)
		for unit: UnitState in units.values():
			if unit.alive and unit.position.distance_to(strike.target) <= strike.damage_radius:
				destroyed_unit_ids[unit.id] = true

	# Emit visibility changes one tick before applying damage so newly revealed
	# enemy units get a frame in which they can be seen before destruction.
	if reveal_started:
		_refresh_visibility()

	for strike: StrikeState in due_strikes:
		strike_detonated.emit(strike.id, strike.target)
		strikes.erase(strike.id)

	for unit_id: int in destroyed_unit_ids:
		var unit: UnitState = units[unit_id]
		unit.alive = false
		unit.is_moving = false
		unit.gathering_resource_type = UnitState.ResourceType.NONE
		players[unit.owner_id].active_unit_ids.erase(unit_id)
		unit_destroyed.emit(unit.id, unit.position)


func _create_reveal_zone(strike: StrikeState) -> void:
	strike.reveal_started = true
	if strike.reveal_radius <= 0.0:
		return
	var zone: RevealZoneState = RevealZoneState.new(
		_next_reveal_zone_id,
		strike.owner_id,
		strike.target,
		strike.reveal_radius,
		strike.impact_tick + BOMB_REVEAL_DURATION_TICKS
	)
	reveal_zones[zone.id] = zone
	_next_reveal_zone_id += 1
	reveal_zone_created.emit(zone.id)


func _expire_reveal_zones() -> void:
	var expired_zone_ids: Array[int] = []
	for zone: RevealZoneState in reveal_zones.values():
		if zone.expires_at_tick <= current_tick:
			expired_zone_ids.append(zone.id)
	for zone_id: int in expired_zone_ids:
		reveal_zones.erase(zone_id)
		reveal_zone_removed.emit(zone_id)


func _advance_cooldowns() -> void:
	for player: PlayerState in players.values():
		player.bomb_cooldown_ticks = maxi(0, player.bomb_cooldown_ticks - 1)


func _rebuild_visibility_cache() -> void:
	_visibility_cache.clear()
	for player_id: int in players:
		for unit_id: int in units:
			_visibility_cache[_visibility_key(player_id, unit_id)] = is_unit_visible_to(
				unit_id,
				player_id
			)


func _refresh_visibility() -> void:
	for player_id: int in players:
		for unit_id: int in units:
			var key: String = _visibility_key(player_id, unit_id)
			var visible: bool = is_unit_visible_to(unit_id, player_id)
			if not _visibility_cache.has(key) or _visibility_cache[key] != visible:
				_visibility_cache[key] = visible
				unit_visibility_changed.emit(player_id, unit_id, visible)


func _visibility_key(player_id: int, unit_id: int) -> String:
	return "%d:%d" % [player_id, unit_id]


func _add_unit(unit_id: int, owner_id: int, initial_position: Vector2) -> void:
	units[unit_id] = UnitState.new(unit_id, owner_id, initial_position)
	players[owner_id].active_unit_ids.append(unit_id)


func _reject(command: GameCommand, reason: StringName) -> void:
	command_rejected.emit(command.player_id, command.type, reason)
