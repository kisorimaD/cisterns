class_name StateProjector
extends RefCounted


static func build_snapshot(game_state: GameState, player_id: int, match_id: int) -> Dictionary:
	var player: PlayerState = game_state.get_player_state(player_id)
	if player == null:
		return {}
	var unit_records: Array[Dictionary] = []
	for unit: UnitState in game_state.units.values():
		if not unit.alive:
			continue
		if not should_include_unit(
			unit.owner_id,
			player_id,
			game_state.is_unit_visible_to(unit.id, player_id)
		):
			continue
		var income: ResourceSample = game_state.get_unit_income_preview(unit.id)
		var upstream_count := -1
		if unit.owner_id == player_id:
			upstream_count = game_state.get_upstream_gatherer_count_for_unit(unit.id, player_id)
		unit_records.append({
			"id": unit.id,
			"owner_id": unit.owner_id,
			"position": unit.position,
			"is_moving": unit.is_moving,
			"gathering_type": int(unit.gathering_resource_type),
			"water_income": income.water_income if unit.owner_id == player_id else 0,
			"gold_income": income.gold_income if unit.owner_id == player_id else 0,
			"upstream_count": upstream_count,
		})

	var strike_records: Array[Dictionary] = []
	for strike: StrikeState in game_state.strikes.values():
		if not should_include_strike(strike.owner_id, strike.type, player_id):
			continue
		strike_records.append({
			"id": strike.id,
			"owner_id": strike.owner_id,
			"type": int(strike.type),
			"target": strike.target,
			"impact_tick": strike.impact_tick,
			"damage_radius": strike.damage_radius,
			"reveal_radius": strike.reveal_radius,
		})

	var reveal_records: Array[Dictionary] = []
	for zone: RevealZoneState in game_state.reveal_zones.values():
		reveal_records.append({
			"id": zone.id,
			"owner_id": zone.owner_id,
			"center": zone.center,
			"radius": zone.radius,
			"expires_at_tick": zone.expires_at_tick,
		})

	return {
		"protocol_version": NetworkProtocol.VERSION,
		"match_id": match_id,
		"tick": game_state.current_tick,
		"player_id": player_id,
		"player": {
			"water": player.water,
			"gold": player.gold,
			"active_unit_count": player.active_unit_ids.size(),
			"bomb_cooldown_ticks": player.bomb_cooldown_ticks,
			"missile_cooldown_ticks": player.missile_cooldown_ticks,
			"replacement_cost": game_state.get_next_replacement_cost(player_id),
		},
		"units": unit_records,
		"strikes": strike_records,
		"reveal_zones": reveal_records,
		"match_finished": game_state.match_finished,
		"winner_player_id": game_state.winner_player_id,
		"metrics": game_state.get_match_metrics() if game_state.match_finished else {},
	}


static func contains_hidden_enemy(
		snapshot: Dictionary,
		game_state: GameState,
		player_id: int
) -> bool:
	for record: Dictionary in snapshot.get("units", []):
		var unit_id: int = record.get("id", -1)
		var unit: UnitState = game_state.units.get(unit_id)
		if (
			unit != null
			and unit.owner_id != player_id
			and not game_state.is_unit_visible_to(unit_id, player_id)
		):
			return true
	return false


static func should_include_unit(owner_id: int, player_id: int, visible: bool) -> bool:
	return owner_id == player_id or visible


static func should_include_strike(
		owner_id: int,
		strike_type: StrikeState.Type,
		player_id: int
) -> bool:
	return owner_id == player_id or strike_type == StrikeState.Type.MISSILE
