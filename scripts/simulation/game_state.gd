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
signal unit_spawned(unit_id: int, owner_id: int, position: Vector2)
signal resources_changed(player_id: int, water: int, gold: int)
signal gathering_result(unit_id: int, resource_type: int, amount: int)
signal unit_gathering_changed(unit_id: int, resource_type: int)
signal unit_visibility_changed(player_id: int, unit_id: int, visible: bool)
signal strike_scheduled(strike_id: int)
signal strike_detonated(strike_id: int, position: Vector2)
signal reveal_zone_created(zone_id: int)
signal reveal_zone_removed(zone_id: int)
signal command_rejected(player_id: int, command_type: int, reason: StringName)
signal match_ended(winner_player_id: int)
signal event_logged(message: String)

const PLAYER_ID := 0
const PLAYER_COUNT := 2

@export var rules: GameRules = preload("res://resources/default_game_rules.tres")

var current_tick := 0
var units: Dictionary[int, UnitState] = {}
var players: Dictionary[int, PlayerState] = {}
var strikes: Dictionary[int, StrikeState] = {}
var reveal_zones: Dictionary[int, RevealZoneState] = {}
var debug_full_visibility := false
var match_finished := false
var simulation_running := false
var winner_player_id := -1
var event_log: Array[String] = []
var total_commands_received := 0
var total_commands_rejected := 0
var total_strikes_launched := 0
var total_units_destroyed := 0
var total_replacements_purchased := 0

@onready var _map: GameMap = %Map

var _tick_accumulator := 0.0
var _pending_commands: Array[GameCommand] = []
var _expected_sequence_by_player: Dictionary[int, int] = {}
var _next_strike_id := 1
var _next_reveal_zone_id := 1
var _next_unit_id_by_player: Dictionary[int, int] = {}
var _visibility_cache: Dictionary[String, bool] = {}


func _ready() -> void:
	_map.configure(rules)


func start_match() -> void:
	current_tick = 0
	units.clear()
	players.clear()
	strikes.clear()
	reveal_zones.clear()
	event_log.clear()
	_pending_commands.clear()
	_expected_sequence_by_player.clear()
	_next_unit_id_by_player.clear()
	_visibility_cache.clear()
	_tick_accumulator = 0.0
	_next_strike_id = 1
	_next_reveal_zone_id = 1
	match_finished = false
	winner_player_id = -1
	total_commands_received = 0
	total_commands_rejected = 0
	total_strikes_launched = 0
	total_units_destroyed = 0
	total_replacements_purchased = 0
	for player_id: int in PLAYER_COUNT:
		players[player_id] = PlayerState.new(player_id)
		players[player_id].water = mini(rules.initial_water, rules.maximum_water)
		players[player_id].gold = rules.initial_gold
		_expected_sequence_by_player[player_id] = 0
	for index: int in rules.player_initial_positions.size():
		_add_unit(index + 1, 0, rules.player_initial_positions[index])
	for index: int in rules.bot_initial_positions.size():
		_add_unit(index + 101, 1, rules.bot_initial_positions[index])
	_next_unit_id_by_player[0] = rules.player_initial_positions.size() + 1
	_next_unit_id_by_player[1] = rules.bot_initial_positions.size() + 101
	_rebuild_visibility_cache()
	_log_event("Матч начат")
	simulation_running = true


func _process(delta: float) -> void:
	if not simulation_running or match_finished:
		return
	_tick_accumulator += delta
	while _tick_accumulator >= rules.simulation_tick_seconds:
		_tick_accumulator -= rules.simulation_tick_seconds
		_advance_tick()
		if match_finished:
			break


func queue_command(command: GameCommand) -> void:
	total_commands_received += 1
	if not simulation_running or match_finished:
		_reject(command, &"match_finished")
		return
	_pending_commands.append(command)


func finish_due_to_disconnect(remaining_player_id: int) -> void:
	if match_finished:
		return
	match_finished = true
	simulation_running = false
	winner_player_id = remaining_player_id
	_pending_commands.clear()
	_log_event("Матч завершён: соперник отключился")
	match_ended.emit(winner_player_id)


func get_player_unit_at_position(player_id: int, map_position: Vector2) -> int:
	var nearest_unit_id: int = -1
	var nearest_distance: float = rules.unit_selection_radius
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


func get_next_replacement_cost(player_id: int) -> int:
	var player: PlayerState = players.get(player_id)
	if player == null:
		return 0
	var expensive_purchase_index: int = maxi(
		0,
		player.replacements_bought - rules.cheap_replacement_count + 1
	)
	return rules.base_replacement_cost * (1 << expensive_purchase_index)


func get_replacement_spawn_candidates(player_id: int) -> Array[Vector2]:
	return _map.get_spawn_candidates(player_id)


func get_elapsed_seconds() -> float:
	return current_tick * rules.simulation_tick_seconds


func get_recent_events(maximum_count: int = 4) -> Array[String]:
	var first_index: int = maxi(0, event_log.size() - maximum_count)
	var recent_events: Array[String] = []
	for index: int in range(first_index, event_log.size()):
		recent_events.append(event_log[index])
	return recent_events


func get_match_metrics() -> Dictionary:
	return {
		"winner_player_id": winner_player_id,
		"elapsed_seconds": get_elapsed_seconds(),
		"commands_received": total_commands_received,
		"commands_accepted": total_commands_received - total_commands_rejected,
		"commands_rejected": total_commands_rejected,
		"strikes_launched": total_strikes_launched,
		"units_destroyed": total_units_destroyed,
		"replacements_purchased": total_replacements_purchased,
	}


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


func get_income_preview_for_unit(_unit_id: int, map_position: Vector2) -> ResourceSample:
	# A destination preview exposes only public map data. Applying upstream
	# attenuation here would turn the cursor into a detector for hidden units.
	return _map.sample_resources(map_position)


func get_unit_income_preview(unit_id: int) -> ResourceSample:
	var unit: UnitState = units.get(unit_id)
	if unit == null or not unit.alive or unit.is_moving:
		return ResourceSample.new()
	var sample: ResourceSample = get_income_preview_for_unit(unit_id, unit.position)
	if sample.water_income > 0:
		sample.water_income = maxi(
			0,
			sample.water_income - _count_upstream_gatherers(sample, unit_id)
		)
	return sample


func get_upstream_gatherer_count_for_unit(unit_id: int, perspective_player_id: int) -> int:
	var unit: UnitState = units.get(unit_id)
	if (
		unit == null
		or not unit.alive
		or unit.owner_id != perspective_player_id
		or unit.is_moving
		or unit.gathering_resource_type != UnitState.ResourceType.WATER
	):
		return -1
	var sample: ResourceSample = _map.sample_resources(unit.position)
	if sample.water_income <= 0:
		return -1
	return _count_upstream_gatherers(sample, unit_id)


func is_position_inside_map(map_position: Vector2) -> bool:
	return Rect2(Vector2.ZERO, rules.map_size).has_point(map_position)


func _advance_tick() -> void:
	_accept_pending_commands()
	_advance_units()
	_update_gathering_states()
	current_tick += 1
	if current_tick % rules.gathering_interval_ticks == 0:
		_gather_resources()
	_resolve_due_strikes()
	if match_finished:
		_refresh_visibility()
		tick_advanced.emit(current_tick)
		return
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
	if match_finished:
		_reject(command, &"match_finished")
		return
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
		GameCommand.Type.LAUNCH_MISSILE:
			_apply_missile_command(command)
		GameCommand.Type.BUY_REPLACEMENT:
			_apply_replacement_command(command)
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
	var path: PackedVector2Array = _map.build_movement_path(
		unit.position,
		command.target,
		rules.unit_obstacle_clearance
	)
	unit.movement_waypoints.clear()
	for waypoint: Vector2 in path:
		unit.movement_waypoints.append(waypoint)
	unit.movement_target = path[-1] if not path.is_empty() else unit.position
	unit.is_moving = not unit.movement_waypoints.is_empty()
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
	if player.water < rules.bomb_water_cost:
		_reject(command, &"not_enough_water")
		return
	if player.bomb_cooldown_ticks > 0:
		_reject(command, &"bomb_on_cooldown")
		return

	player.water -= rules.bomb_water_cost
	player.bomb_cooldown_ticks = rules.bomb_cooldown_ticks
	var strike: StrikeState = StrikeState.new(
		_next_strike_id,
		command.player_id,
		StrikeState.Type.BOMB,
		command.target,
		current_tick + rules.bomb_warning_ticks,
		rules.bomb_damage_radius,
		rules.bomb_reveal_radius
	)
	strikes[strike.id] = strike
	_next_strike_id += 1
	resources_changed.emit(player.id, player.water, player.gold)
	strike_scheduled.emit(strike.id)
	total_strikes_launched += 1
	_log_event("Игрок %d запустил бомбу" % player.id)


func _apply_missile_command(command: GameCommand) -> void:
	var player: PlayerState = players.get(command.player_id)
	if player == null or player.active_unit_ids.is_empty():
		_reject(command, &"no_active_units")
		return
	if command.targets.size() != rules.airstrike_target_count:
		_reject(command, &"invalid_airstrike_target_count")
		return
	for target: Vector2 in command.targets:
		if not is_position_inside_map(target):
			_reject(command, &"target_outside_map")
			return
	if player.gold < rules.missile_gold_cost:
		_reject(command, &"not_enough_gold")
		return
	if player.missile_cooldown_ticks > 0:
		_reject(command, &"missile_on_cooldown")
		return

	player.gold -= rules.missile_gold_cost
	player.missile_cooldown_ticks = rules.missile_cooldown_ticks
	for target: Vector2 in command.targets:
		var strike: StrikeState = StrikeState.new(
			_next_strike_id,
			command.player_id,
			StrikeState.Type.MISSILE,
			target,
			current_tick + rules.missile_warning_ticks,
			rules.missile_damage_radius,
			rules.missile_reveal_radius
		)
		strikes[strike.id] = strike
		_next_strike_id += 1
		strike_scheduled.emit(strike.id)
	resources_changed.emit(player.id, player.water, player.gold)
	total_strikes_launched += command.targets.size()
	_log_event("Игрок %d вызвал авиаудар" % player.id)


func _apply_replacement_command(command: GameCommand) -> void:
	var player: PlayerState = players.get(command.player_id)
	if player == null or player.active_unit_ids.is_empty():
		_reject(command, &"no_active_units")
		return
	if player.active_unit_ids.size() >= rules.maximum_active_units:
		_reject(command, &"maximum_units_reached")
		return
	if not is_position_inside_map(command.target):
		_reject(command, &"target_outside_map")
		return
	if not _map.is_position_in_spawn_area(command.player_id, command.target):
		_reject(command, &"outside_spawn_area")
		return
	if not _is_replacement_position_free(command.target):
		_reject(command, &"spawn_position_blocked")
		return
	var replacement_cost: int = get_next_replacement_cost(command.player_id)
	if player.gold < replacement_cost:
		_reject(command, &"not_enough_gold")
		return

	var unit_id: int = _next_unit_id_by_player[command.player_id]
	_next_unit_id_by_player[command.player_id] = unit_id + 1
	player.gold -= replacement_cost
	player.replacements_bought += 1
	_add_unit(unit_id, command.player_id, command.target)
	resources_changed.emit(player.id, player.water, player.gold)
	unit_spawned.emit(unit_id, command.player_id, command.target)
	total_replacements_purchased += 1
	_log_event("Игрок %d купил замену за %d золота" % [player.id, replacement_cost])


func _advance_units() -> void:
	for unit: UnitState in units.values():
		if not unit.alive or not unit.is_moving:
			continue

		var from: Vector2 = unit.position
		var remaining_distance: float = rules.unit_move_speed * rules.simulation_tick_seconds
		while remaining_distance > 0.0 and not unit.movement_waypoints.is_empty():
			var waypoint: Vector2 = unit.movement_waypoints[0]
			var distance_to_waypoint: float = unit.position.distance_to(waypoint)
			if distance_to_waypoint <= remaining_distance:
				unit.position = waypoint
				remaining_distance -= distance_to_waypoint
				unit.movement_waypoints.pop_front()
			else:
				unit.position = unit.position.move_toward(waypoint, remaining_distance)
				remaining_distance = 0.0
		unit.is_moving = not unit.movement_waypoints.is_empty()
		unit_moved.emit(unit.id, from, unit.position, rules.simulation_tick_seconds)


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
			var player: PlayerState = players[unit.owner_id]
			var previous_water: int = player.water
			player.water = mini(rules.maximum_water, player.water + income.water_income)
			amount = player.water - previous_water
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
			and strike.impact_tick - current_tick <= _get_reveal_lead_ticks(strike)
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
		total_units_destroyed += 1
		_log_event("Уничтожен юнит %d игрока %d" % [unit.id, unit.owner_id])
	_finish_match_if_needed()


func _create_reveal_zone(strike: StrikeState) -> void:
	strike.reveal_started = true
	if strike.reveal_radius <= 0.0:
		return
	var zone: RevealZoneState = RevealZoneState.new(
		_next_reveal_zone_id,
		strike.owner_id,
		strike.target,
		strike.reveal_radius,
		strike.impact_tick + _get_reveal_duration_ticks(strike)
	)
	reveal_zones[zone.id] = zone
	_next_reveal_zone_id += 1
	reveal_zone_created.emit(zone.id)


func _get_reveal_lead_ticks(strike: StrikeState) -> int:
	if strike.type == StrikeState.Type.MISSILE:
		return rules.missile_reveal_lead_ticks
	return rules.bomb_reveal_lead_ticks


func _get_reveal_duration_ticks(strike: StrikeState) -> int:
	if strike.type == StrikeState.Type.MISSILE:
		return rules.missile_reveal_duration_ticks
	return rules.bomb_reveal_duration_ticks


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
		player.missile_cooldown_ticks = maxi(0, player.missile_cooldown_ticks - 1)


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


func _is_replacement_position_free(map_position: Vector2) -> bool:
	for unit: UnitState in units.values():
		if (
			unit.alive
			and unit.position.distance_to(map_position) < rules.replacement_clearance_radius
		):
			return false
	return true


func _finish_match_if_needed() -> void:
	var eliminated_players: Array[int] = []
	for player_id: int in players:
		var player: PlayerState = players[player_id]
		if player.active_unit_ids.is_empty():
			eliminated_players.append(player_id)
	if eliminated_players.is_empty():
		return
	match_finished = true
	simulation_running = false
	_pending_commands.clear()
	if eliminated_players.size() == 1:
		winner_player_id = (eliminated_players[0] + 1) % PLAYER_COUNT
	else:
		winner_player_id = -1
	var result_text: String = (
		"Матч завершён вничью"
		if winner_player_id == -1
		else "Матч завершён, победил игрок %d" % winner_player_id
	)
	_log_event("%s за %.1f с" % [result_text, get_elapsed_seconds()])
	match_ended.emit(winner_player_id)


func _reject(command: GameCommand, reason: StringName) -> void:
	total_commands_rejected += 1
	_log_event("Команда игрока %d отклонена: %s" % [command.player_id, reason])
	command_rejected.emit(command.player_id, command.type, reason)


func _log_event(message: String) -> void:
	var entry: String = "[%05.1f] %s" % [get_elapsed_seconds(), message]
	event_log.append(entry)
	while event_log.size() > rules.event_log_capacity:
		event_log.pop_front()
	event_logged.emit(entry)
