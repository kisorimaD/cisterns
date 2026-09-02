class_name GameState
extends Node

signal tick_advanced(tick: int)
signal unit_moved(
	unit_id: int,
	from: Vector2,
	to: Vector2,
	duration_seconds: float
)
signal resources_changed(player_id: int, water: int, gold: int)
signal gathering_result(unit_id: int, resource_type: int, amount: int)
signal unit_gathering_changed(unit_id: int, resource_type: int)
signal unit_visibility_changed(player_id: int, unit_id: int, visible: bool)
signal command_rejected(player_id: int, command_type: int, reason: StringName)

const MAP_SIZE := Vector2(960.0, 672.0)
const SIMULATION_TICK_SECONDS := 0.25
const UNIT_MOVE_SPEED := 96.0
const UNIT_SELECTION_RADIUS := 22.0
const GATHERING_INTERVAL_TICKS := 8
const PLAYER_ID := 0
const PLAYER_COUNT := 2

var current_tick := 0
var units: Dictionary[int, UnitState] = {}
var players: Dictionary[int, PlayerState] = {}
var debug_full_visibility := false

@onready var _map: GameMap = %Map

var _tick_accumulator := 0.0
var _pending_commands: Array[GameCommand] = []
var _expected_sequence_by_player: Dictionary[int, int] = {}


func _ready() -> void:
	for player_id: int in PLAYER_COUNT:
		players[player_id] = PlayerState.new(player_id)
		_expected_sequence_by_player[player_id] = 0
	_add_unit(1, 0, Vector2(120.0, 120.0))
	_add_unit(2, 0, Vector2(120.0, 336.0))
	_add_unit(3, 0, Vector2(120.0, 552.0))
	_add_unit(101, 1, Vector2(840.0, 120.0))
	_add_unit(102, 1, Vector2(840.0, 336.0))
	_add_unit(103, 1, Vector2(840.0, 552.0))


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


func is_unit_visible_to(unit_id: int, perspective_player_id: int) -> bool:
	var unit: UnitState = units.get(unit_id)
	if unit == null or not unit.alive or not players.has(perspective_player_id):
		return false
	return unit.owner_id == perspective_player_id or debug_full_visibility


func set_debug_full_visibility(enabled: bool) -> void:
	if debug_full_visibility == enabled:
		return
	debug_full_visibility = enabled
	for player_id: int in players:
		for unit_id: int in units:
			unit_visibility_changed.emit(
				player_id,
				unit_id,
				is_unit_visible_to(unit_id, player_id)
			)


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
	if unit == null or unit.is_moving:
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


func _add_unit(unit_id: int, owner_id: int, initial_position: Vector2) -> void:
	units[unit_id] = UnitState.new(unit_id, owner_id, initial_position)
	players[owner_id].active_unit_ids.append(unit_id)


func _reject(command: GameCommand, reason: StringName) -> void:
	command_rejected.emit(command.player_id, command.type, reason)
