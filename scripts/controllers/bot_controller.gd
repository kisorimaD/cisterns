class_name BotController
extends Node

const MOVE_DECISION_INTERVAL_TICKS: int = 20
const BOMB_DECISION_INTERVAL_TICKS: int = 8
const MISSILE_DECISION_INTERVAL_TICKS: int = 12
const REPLACEMENT_DECISION_INTERVAL_TICKS: int = 8
const ECONOMY_SAMPLE_STEP: int = 48
const ECONOMY_SAMPLE_MARGIN: float = 24.0
const TARGET_SEPARATION: float = 72.0
const FRIENDLY_FIRE_MARGIN: float = 18.0
const INVALID_TARGET: Vector2 = Vector2(-1.0, -1.0)

@export var bot_player_id: int = 1
@export var random_seed: int = 6026

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _paused_for_debug_control: bool = false
var _next_move_decision_tick: int = 2
var _next_bomb_decision_tick: int = 8
var _next_missile_decision_tick: int = 16
var _next_replacement_decision_tick: int = 6
var _last_known_enemy_positions: Dictionary[int, Vector2] = {}
var _game_state: GameState
var _command_gateway: CommandGateway


func configure(game_state: GameState, command_gateway: CommandGateway) -> void:
	_game_state = game_state
	_command_gateway = command_gateway
	_rng.seed = random_seed


func on_tick_advanced(tick: int) -> void:
	if _paused_for_debug_control:
		return
	_remember_visible_enemies()
	if tick >= _next_replacement_decision_tick:
		_try_buy_replacement()
		_next_replacement_decision_tick = tick + REPLACEMENT_DECISION_INTERVAL_TICKS
	if tick >= _next_move_decision_tick:
		_make_movement_decisions()
		_next_move_decision_tick = tick + MOVE_DECISION_INTERVAL_TICKS
	if tick >= _next_bomb_decision_tick:
		_try_launch_bomb()
		_next_bomb_decision_tick = tick + BOMB_DECISION_INTERVAL_TICKS
	if tick >= _next_missile_decision_tick:
		_try_launch_missile()
		_next_missile_decision_tick = tick + MISSILE_DECISION_INTERVAL_TICKS


func on_debug_controlled_player_changed(player_id: int) -> void:
	_paused_for_debug_control = player_id == bot_player_id


func _make_movement_decisions() -> void:
	var player: PlayerState = _game_state.get_player_state(bot_player_id)
	if player == null:
		return
	var reserved_targets: Array[Vector2] = []
	for unit_id: int in player.active_unit_ids:
		var unit: UnitState = _game_state.units.get(unit_id)
		if unit == null or not unit.alive or unit.is_moving:
			continue
		var prefer_gold: bool = unit.id % 100 == 3
		var current_income: ResourceSample = _game_state.get_unit_income_preview(unit.id)
		var useful_income: int = (
			current_income.gold_income if prefer_gold else current_income.water_income
		)
		var comfortable_income: int = 2 if prefer_gold else 7
		if useful_income >= comfortable_income:
			if _rng.randf() > 0.18:
				reserved_targets.append(unit.position)
				continue
			# Treat the current productive spot as reserved during an occasional
			# relocation so the unit actually chooses another useful position.
			reserved_targets.append(unit.position)
		var target: Vector2 = _find_economic_target(unit, prefer_gold, reserved_targets)
		if target == INVALID_TARGET or unit.position.distance_to(target) < 12.0:
			continue
		reserved_targets.append(target)
		_command_gateway.submit(GameCommand.move_unit(bot_player_id, unit.id, target))


func _find_economic_target(
		unit: UnitState,
		prefer_gold: bool,
		reserved_targets: Array[Vector2]
) -> Vector2:
	var best_target: Vector2 = INVALID_TARGET
	var best_score: float = -INF
	var maximum_x: int = floori(GameState.MAP_SIZE.x - ECONOMY_SAMPLE_MARGIN)
	var maximum_y: int = floori(GameState.MAP_SIZE.y - ECONOMY_SAMPLE_MARGIN)
	for y: int in range(int(ECONOMY_SAMPLE_MARGIN), maximum_y + 1, ECONOMY_SAMPLE_STEP):
		for x: int in range(int(ECONOMY_SAMPLE_MARGIN), maximum_x + 1, ECONOMY_SAMPLE_STEP):
			var candidate: Vector2 = Vector2(float(x), float(y))
			var sample: ResourceSample = _game_state.get_income_preview_for_unit(
				unit.id,
				candidate
			)
			var score: float = _score_economic_sample(sample, prefer_gold)
			if score <= 0.0:
				continue
			score -= unit.position.distance_to(candidate) * 0.004
			for reserved_target: Vector2 in reserved_targets:
				if reserved_target.distance_to(candidate) < TARGET_SEPARATION:
					score -= 80.0
			score += _rng.randf_range(-0.2, 0.2)
			if score > best_score:
				best_score = score
				best_target = candidate
	return best_target


func _score_economic_sample(sample: ResourceSample, prefer_gold: bool) -> float:
	if prefer_gold:
		return float(sample.gold_income) * 32.0 + float(sample.water_income) * 0.5
	return float(sample.water_income) * 10.0 + float(sample.gold_income)


func _remember_visible_enemies() -> void:
	for unit: UnitState in _game_state.units.values():
		if unit.owner_id == bot_player_id or not unit.alive:
			continue
		if _game_state.is_unit_visible_to(unit.id, bot_player_id):
			_last_known_enemy_positions[unit.id] = unit.position


func _try_launch_bomb() -> void:
	var player: PlayerState = _game_state.get_player_state(bot_player_id)
	if (
		player == null
		or player.active_unit_ids.is_empty()
		or player.water < GameState.BOMB_WATER_COST
		or player.bomb_cooldown_ticks > 0
	):
		return
	var target: Vector2 = _choose_bomb_target()
	if target == INVALID_TARGET:
		return
	_command_gateway.submit(GameCommand.launch_bomb(bot_player_id, target))


func _choose_bomb_target() -> Vector2:
	var visible_targets: Array[Vector2] = []
	for unit: UnitState in _game_state.units.values():
		if (
			unit.owner_id != bot_player_id
			and unit.alive
			and _game_state.is_unit_visible_to(unit.id, bot_player_id)
		):
			visible_targets.append(unit.position)
	var target: Vector2 = _pick_safe_target(visible_targets, 10.0)
	if target != INVALID_TARGET:
		return target

	var remembered_targets: Array[Vector2] = []
	for remembered_position: Vector2 in _last_known_enemy_positions.values():
		remembered_targets.append(remembered_position)
	target = _pick_safe_target(remembered_targets, 28.0)
	if target != INVALID_TARGET:
		return target

	# Spawn lanes and resource landmarks are public map knowledge. Random jitter
	# keeps scouting useful without granting the bot access to hidden positions.
	var scouting_centers: Array[Vector2] = [
		Vector2(140.0, 120.0),
		Vector2(140.0, 336.0),
		Vector2(140.0, 552.0),
		Vector2(360.0, 185.0),
		Vector2(530.0, 470.0),
	]
	return _pick_safe_target(scouting_centers, 52.0)


func _pick_safe_target(candidates: Array[Vector2], jitter_radius: float) -> Vector2:
	if candidates.is_empty():
		return INVALID_TARGET
	var start_index: int = _rng.randi_range(0, candidates.size() - 1)
	for offset: int in candidates.size():
		var candidate: Vector2 = candidates[(start_index + offset) % candidates.size()]
		var jitter: Vector2 = Vector2.from_angle(_rng.randf_range(0.0, TAU))
		jitter *= _rng.randf_range(0.0, jitter_radius)
		candidate = (candidate + jitter).clamp(Vector2.ZERO, GameState.MAP_SIZE)
		if _is_safe_from_friendly_units(candidate):
			return candidate
	return INVALID_TARGET


func _is_safe_from_friendly_units(target: Vector2) -> bool:
	return _is_safe_from_friendly_units_for_radius(target, GameState.BOMB_DAMAGE_RADIUS)


func _try_launch_missile() -> void:
	var player: PlayerState = _game_state.get_player_state(bot_player_id)
	if (
		player == null
		or player.active_unit_ids.is_empty()
		or player.gold < GameState.MISSILE_GOLD_COST
		or player.missile_cooldown_ticks > 0
	):
		return
	var target: Vector2 = _choose_missile_target()
	if target != INVALID_TARGET:
		_command_gateway.submit(GameCommand.launch_missile(bot_player_id, target))


func _choose_missile_target() -> Vector2:
	var candidates: Array[Vector2] = []
	for unit: UnitState in _game_state.units.values():
		if (
			unit.owner_id != bot_player_id
			and unit.alive
			and _game_state.is_unit_visible_to(unit.id, bot_player_id)
		):
			candidates.append(unit.position)
	for remembered_position: Vector2 in _last_known_enemy_positions.values():
		candidates.append(remembered_position)
	# These are public high-value gathering zones. The long warning turns a
	# missile aimed here into area denial even when no enemy is currently seen.
	candidates.append_array([
		Vector2(300.0, 185.0),
		Vector2(480.0, 185.0),
		Vector2(660.0, 185.0),
		Vector2(530.0, 470.0),
	])
	if candidates.is_empty():
		return INVALID_TARGET
	var start_index: int = _rng.randi_range(0, candidates.size() - 1)
	for offset: int in candidates.size():
		var target: Vector2 = candidates[(start_index + offset) % candidates.size()]
		if _is_safe_from_friendly_units_for_radius(target, GameState.MISSILE_DAMAGE_RADIUS):
			return target
	return INVALID_TARGET


func _is_safe_from_friendly_units_for_radius(target: Vector2, damage_radius: float) -> bool:
	var safe_distance: float = damage_radius + FRIENDLY_FIRE_MARGIN
	for unit: UnitState in _game_state.units.values():
		if (
			unit.owner_id == bot_player_id
			and unit.alive
			and unit.position.distance_to(target) < safe_distance
		):
			return false
	return true


func _try_buy_replacement() -> void:
	var player: PlayerState = _game_state.get_player_state(bot_player_id)
	if (
		player == null
		or player.active_unit_ids.is_empty()
		or player.active_unit_ids.size() >= GameState.MAXIMUM_ACTIVE_UNITS
		or player.gold < _game_state.get_next_replacement_cost(bot_player_id)
	):
		return
	var candidates: Array[Vector2] = _game_state.get_replacement_spawn_candidates(bot_player_id)
	if candidates.is_empty():
		return
	var start_index: int = _rng.randi_range(0, candidates.size() - 1)
	for offset: int in candidates.size():
		var target: Vector2 = candidates[(start_index + offset) % candidates.size()]
		var blocked_by_own_unit := false
		for unit_id: int in player.active_unit_ids:
			var unit: UnitState = _game_state.units.get(unit_id)
			if (
				unit != null
				and unit.alive
				and unit.position.distance_to(target) < GameState.REPLACEMENT_CLEARANCE_RADIUS
			):
				blocked_by_own_unit = true
				break
		if not blocked_by_own_unit:
			_command_gateway.submit(GameCommand.buy_replacement(bot_player_id, target))
			return
