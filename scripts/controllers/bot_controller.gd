class_name BotController
extends Node

const INVALID_TARGET: Vector2 = Vector2(-1.0, -1.0)

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _paused_for_debug_control: bool = false
var _next_move_decision_tick: int
var _next_bomb_decision_tick: int
var _next_missile_decision_tick: int
var _next_replacement_decision_tick: int
var _last_known_enemy_positions: Dictionary[int, Vector2] = {}
var _game_state: GameState
var _command_gateway: CommandGateway
var _rules: GameRules
var _bot_player_id: int


func configure(game_state: GameState, command_gateway: CommandGateway) -> void:
	_game_state = game_state
	_command_gateway = command_gateway
	_rules = game_state.rules
	_bot_player_id = _rules.bot_player_id
	_rng.seed = _rules.bot_random_seed
	_next_move_decision_tick = _rules.bot_first_move_tick
	_next_bomb_decision_tick = _rules.bot_first_bomb_tick
	_next_missile_decision_tick = _rules.bot_first_missile_tick
	_next_replacement_decision_tick = _rules.bot_first_replacement_tick


func on_tick_advanced(tick: int) -> void:
	if _paused_for_debug_control or _game_state.match_finished:
		return
	_remember_visible_enemies()
	if tick >= _next_replacement_decision_tick:
		_try_buy_replacement()
		_next_replacement_decision_tick = tick + _rules.bot_replacement_decision_interval_ticks
	if tick >= _next_move_decision_tick:
		_make_movement_decisions()
		_next_move_decision_tick = tick + _rules.bot_move_decision_interval_ticks
	if tick >= _next_bomb_decision_tick:
		_try_launch_bomb()
		_next_bomb_decision_tick = tick + _rules.bot_bomb_decision_interval_ticks
	if tick >= _next_missile_decision_tick:
		_try_launch_missile()
		_next_missile_decision_tick = tick + _rules.bot_missile_decision_interval_ticks


func on_debug_controlled_player_changed(player_id: int) -> void:
	_paused_for_debug_control = player_id == _bot_player_id


func _make_movement_decisions() -> void:
	var player: PlayerState = _game_state.get_player_state(_bot_player_id)
	if player == null:
		return
	var reserved_targets: Array[Vector2] = []
	for unit_index: int in player.active_unit_ids.size():
		var unit_id: int = player.active_unit_ids[unit_index]
		var unit: UnitState = _game_state.units.get(unit_id)
		if unit == null or not unit.alive or unit.is_moving:
			continue
		var prefer_gold: bool = unit_index == player.active_unit_ids.size() - 1
		var current_income: ResourceSample = _game_state.get_unit_income_preview(unit.id)
		var useful_income: int = (
			current_income.gold_income if prefer_gold else current_income.water_income
		)
		var comfortable_income: int = (
			_rules.bot_comfortable_gold_income
			if prefer_gold
			else _rules.bot_comfortable_water_income
		)
		if useful_income >= comfortable_income:
			if _rng.randf() > _rules.bot_productive_relocation_chance:
				reserved_targets.append(unit.position)
				continue
			# Treat the current productive spot as reserved during an occasional
			# relocation so the unit actually chooses another useful position.
			reserved_targets.append(unit.position)
		var target: Vector2 = _find_economic_target(unit, prefer_gold, reserved_targets)
		if (
			target == INVALID_TARGET
			or unit.position.distance_to(target) < _rules.bot_minimum_move_distance
		):
			continue
		reserved_targets.append(target)
		_command_gateway.submit(GameCommand.move_unit(_bot_player_id, unit.id, target))


func _find_economic_target(
		unit: UnitState,
		prefer_gold: bool,
		reserved_targets: Array[Vector2]
) -> Vector2:
	var best_target: Vector2 = INVALID_TARGET
	var best_score: float = -INF
	var maximum_x: int = floori(_rules.map_size.x - _rules.bot_economy_sample_margin)
	var maximum_y: int = floori(_rules.map_size.y - _rules.bot_economy_sample_margin)
	for y: int in range(
		int(_rules.bot_economy_sample_margin),
		maximum_y + 1,
		_rules.bot_economy_sample_step
	):
		for x: int in range(
			int(_rules.bot_economy_sample_margin),
			maximum_x + 1,
			_rules.bot_economy_sample_step
		):
			var candidate: Vector2 = Vector2(float(x), float(y))
			var sample: ResourceSample = _game_state.get_income_preview_for_unit(
				unit.id,
				candidate
			)
			var score: float = _score_economic_sample(sample, prefer_gold)
			if score <= 0.0:
				continue
			score -= unit.position.distance_to(candidate) * _rules.bot_distance_score_penalty
			for reserved_target: Vector2 in reserved_targets:
				if reserved_target.distance_to(candidate) < _rules.bot_target_separation:
					score -= _rules.bot_reserved_target_score_penalty
			score += _rng.randf_range(-_rules.bot_score_jitter, _rules.bot_score_jitter)
			if score > best_score:
				best_score = score
				best_target = candidate
	return best_target


func _score_economic_sample(sample: ResourceSample, prefer_gold: bool) -> float:
	if prefer_gold:
		return (
			float(sample.gold_income) * _rules.bot_gold_primary_score_weight
			+ float(sample.water_income) * _rules.bot_secondary_water_score_weight
		)
	return (
		float(sample.water_income) * _rules.bot_water_primary_score_weight
		+ float(sample.gold_income) * _rules.bot_secondary_gold_score_weight
	)


func _remember_visible_enemies() -> void:
	for unit: UnitState in _game_state.units.values():
		if unit.owner_id == _bot_player_id or not unit.alive:
			continue
		if _game_state.is_unit_visible_to(unit.id, _bot_player_id):
			_last_known_enemy_positions[unit.id] = unit.position


func _try_launch_bomb() -> void:
	var player: PlayerState = _game_state.get_player_state(_bot_player_id)
	if (
		player == null
		or player.active_unit_ids.is_empty()
		or player.water < _rules.bomb_water_cost
		or player.bomb_cooldown_ticks > 0
	):
		return
	var target: Vector2 = _choose_bomb_target()
	if target == INVALID_TARGET:
		return
	_command_gateway.submit(GameCommand.launch_bomb(_bot_player_id, target))


func _choose_bomb_target() -> Vector2:
	var visible_targets: Array[Vector2] = []
	for unit: UnitState in _game_state.units.values():
		if (
			unit.owner_id != _bot_player_id
			and unit.alive
			and _game_state.is_unit_visible_to(unit.id, _bot_player_id)
		):
			visible_targets.append(unit.position)
	var target: Vector2 = _pick_safe_target(
		visible_targets,
		_rules.bot_bomb_visible_jitter_radius
	)
	if target != INVALID_TARGET:
		return target

	var remembered_targets: Array[Vector2] = []
	for remembered_position: Vector2 in _last_known_enemy_positions.values():
		remembered_targets.append(remembered_position)
	target = _pick_safe_target(remembered_targets, _rules.bot_bomb_remembered_jitter_radius)
	if target != INVALID_TARGET:
		return target

	# Spawn lanes and resource landmarks are public map knowledge. Random jitter
	# keeps scouting useful without granting the bot access to hidden positions.
	var scouting_centers: Array[Vector2] = []
	for center: Vector2 in _rules.bot_bomb_scouting_centers:
		scouting_centers.append(center)
	return _pick_safe_target(scouting_centers, _rules.bot_bomb_scouting_jitter_radius)


func _pick_safe_target(candidates: Array[Vector2], jitter_radius: float) -> Vector2:
	if candidates.is_empty():
		return INVALID_TARGET
	var start_index: int = _rng.randi_range(0, candidates.size() - 1)
	for offset: int in candidates.size():
		var candidate: Vector2 = candidates[(start_index + offset) % candidates.size()]
		var jitter: Vector2 = Vector2.from_angle(_rng.randf_range(0.0, TAU))
		jitter *= _rng.randf_range(0.0, jitter_radius)
		candidate = (candidate + jitter).clamp(Vector2.ZERO, _rules.map_size)
		if _is_safe_from_friendly_units(candidate):
			return candidate
	return INVALID_TARGET


func _is_safe_from_friendly_units(target: Vector2) -> bool:
	return _is_safe_from_friendly_units_for_radius(target, _rules.bomb_damage_radius)


func _try_launch_missile() -> void:
	var player: PlayerState = _game_state.get_player_state(_bot_player_id)
	if (
		player == null
		or player.active_unit_ids.is_empty()
		or player.gold < _rules.missile_gold_cost
		or player.missile_cooldown_ticks > 0
	):
		return
	var target: Vector2 = _choose_missile_target()
	if target != INVALID_TARGET:
		_command_gateway.submit(GameCommand.launch_missile(_bot_player_id, target))


func _choose_missile_target() -> Vector2:
	var candidates: Array[Vector2] = []
	for unit: UnitState in _game_state.units.values():
		if (
			unit.owner_id != _bot_player_id
			and unit.alive
			and _game_state.is_unit_visible_to(unit.id, _bot_player_id)
		):
			candidates.append(unit.position)
	for remembered_position: Vector2 in _last_known_enemy_positions.values():
		candidates.append(remembered_position)
	# These are public high-value gathering zones. The long warning turns a
	# missile aimed here into area denial even when no enemy is currently seen.
	for center: Vector2 in _rules.bot_missile_zoning_centers:
		candidates.append(center)
	if candidates.is_empty():
		return INVALID_TARGET
	var start_index: int = _rng.randi_range(0, candidates.size() - 1)
	for offset: int in candidates.size():
		var target: Vector2 = candidates[(start_index + offset) % candidates.size()]
		if _is_safe_from_friendly_units_for_radius(target, _rules.missile_damage_radius):
			return target
	return INVALID_TARGET


func _is_safe_from_friendly_units_for_radius(target: Vector2, damage_radius: float) -> bool:
	var safe_distance: float = damage_radius + _rules.bot_friendly_fire_margin
	for unit: UnitState in _game_state.units.values():
		if (
			unit.owner_id == _bot_player_id
			and unit.alive
			and unit.position.distance_to(target) < safe_distance
		):
			return false
	return true


func _try_buy_replacement() -> void:
	var player: PlayerState = _game_state.get_player_state(_bot_player_id)
	if (
		player == null
		or player.active_unit_ids.is_empty()
		or player.active_unit_ids.size() >= _rules.maximum_active_units
		or player.gold < _game_state.get_next_replacement_cost(_bot_player_id)
	):
		return
	var candidates: Array[Vector2] = _game_state.get_replacement_spawn_candidates(_bot_player_id)
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
				and unit.position.distance_to(target) < _rules.replacement_clearance_radius
			):
				blocked_by_own_unit = true
				break
		if not blocked_by_own_unit:
			_command_gateway.submit(GameCommand.buy_replacement(_bot_player_id, target))
			return
