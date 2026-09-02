class_name GameState
extends Node

signal tick_advanced(tick: int)
signal unit_moved(
	unit_id: int,
	from: Vector2,
	to: Vector2,
	duration_seconds: float
)
signal command_rejected(player_id: int, command_type: int, reason: StringName)

const MAP_SIZE := Vector2(960.0, 672.0)
const SIMULATION_TICK_SECONDS := 0.25
const UNIT_MOVE_SPEED := 96.0
const UNIT_SELECTION_RADIUS := 22.0
const PLAYER_ID := 0
const INITIAL_UNITS: Dictionary[int, Vector2] = {
	1: Vector2(120.0, 120.0),
	2: Vector2(120.0, 336.0),
	3: Vector2(120.0, 552.0),
}

var current_tick := 0
var units: Dictionary[int, UnitState] = {}

var _tick_accumulator := 0.0
var _pending_commands: Array[GameCommand] = []
var _expected_sequence_by_player: Dictionary[int, int] = {PLAYER_ID: 0}


func _ready() -> void:
	for unit_id: int in INITIAL_UNITS:
		units[unit_id] = UnitState.new(unit_id, PLAYER_ID, INITIAL_UNITS[unit_id])


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


func is_position_inside_map(map_position: Vector2) -> bool:
	return Rect2(Vector2.ZERO, MAP_SIZE).has_point(map_position)


func _advance_tick() -> void:
	_accept_pending_commands()
	_advance_units()
	current_tick += 1
	tick_advanced.emit(current_tick)


func _accept_pending_commands() -> void:
	var commands: Array[GameCommand] = _pending_commands
	_pending_commands = []
	for command: GameCommand in commands:
		_validate_and_apply(command)


func _validate_and_apply(command: GameCommand) -> void:
	if command.player_id != PLAYER_ID:
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
	unit.gathering_resource_type = -1


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


func _reject(command: GameCommand, reason: StringName) -> void:
	command_rejected.emit(command.player_id, command.type, reason)
