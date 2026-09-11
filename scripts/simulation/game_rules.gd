class_name GameRules
extends Resource

@export_category("Match")
@export var map_size := Vector2(960.0, 672.0)
@export var maximum_active_units := 3
@export var simulation_tick_seconds := 0.25
@export var gathering_interval_ticks := 8
@export var initial_water := 12
@export var initial_gold := 0
@export var event_log_capacity := 12

@export_category("Units")
@export var unit_move_speed := 96.0
@export var unit_selection_radius := 22.0
@export var player_initial_positions := PackedVector2Array([
	Vector2(120.0, 120.0),
	Vector2(120.0, 336.0),
	Vector2(120.0, 552.0),
])
@export var bot_initial_positions := PackedVector2Array([
	Vector2(840.0, 120.0),
	Vector2(840.0, 336.0),
	Vector2(840.0, 552.0),
])

@export_category("Map resources")
@export var maximum_water_income := 10
@export var maximum_gold_income := 3

@export_category("Bomb")
@export var bomb_water_cost := 6
@export var bomb_cooldown_ticks := 20
@export var bomb_warning_ticks := 6
@export var bomb_damage_radius := 40.0
@export var bomb_reveal_radius := 80.0
@export var bomb_reveal_lead_ticks := 1
@export var bomb_reveal_duration_ticks := 12

@export_category("Missile")
@export var missile_gold_cost := 10
@export var missile_cooldown_ticks := 40
@export var missile_warning_ticks := 28
@export var missile_damage_radius := 96.0
@export var missile_reveal_radius := 0.0
@export var missile_reveal_lead_ticks := 1
@export var missile_reveal_duration_ticks := 12

@export_category("Replacements")
@export var base_replacement_cost := 4
@export var cheap_replacement_count := 2
@export var replacement_clearance_radius := 44.0
@export var player_spawn_area := Rect2(48.0, 48.0, 144.0, 576.0)
@export var bot_spawn_area := Rect2(768.0, 48.0, 144.0, 576.0)
@export var replacement_spawn_candidate_y := PackedFloat32Array([
	120.0,
	228.0,
	336.0,
	444.0,
	552.0,
])

@export_category("Bot")
@export var bot_player_id := 1
@export var bot_random_seed := 6026
@export var bot_move_decision_interval_ticks := 20
@export var bot_bomb_decision_interval_ticks := 8
@export var bot_missile_decision_interval_ticks := 12
@export var bot_replacement_decision_interval_ticks := 8
@export var bot_first_move_tick := 2
@export var bot_first_bomb_tick := 8
@export var bot_first_missile_tick := 16
@export var bot_first_replacement_tick := 6
@export var bot_economy_sample_step := 48
@export var bot_economy_sample_margin := 24.0
@export var bot_target_separation := 72.0
@export var bot_friendly_fire_margin := 18.0
@export var bot_comfortable_water_income := 7
@export var bot_comfortable_gold_income := 2
@export_range(0.0, 1.0) var bot_productive_relocation_chance := 0.18
@export var bot_minimum_move_distance := 12.0
@export var bot_water_primary_score_weight := 10.0
@export var bot_gold_primary_score_weight := 32.0
@export var bot_secondary_water_score_weight := 0.5
@export var bot_secondary_gold_score_weight := 1.0
@export var bot_distance_score_penalty := 0.004
@export var bot_reserved_target_score_penalty := 80.0
@export var bot_score_jitter := 0.2
@export var bot_bomb_visible_jitter_radius := 10.0
@export var bot_bomb_remembered_jitter_radius := 28.0
@export var bot_bomb_scouting_jitter_radius := 52.0
@export var bot_bomb_scouting_centers := PackedVector2Array([
	Vector2(255.0, 325.0),
	Vector2(705.0, 355.0),
	Vector2(280.0, 110.0),
	Vector2(470.0, 330.0),
	Vector2(630.0, 510.0),
])
@export var bot_missile_zoning_centers := PackedVector2Array([
	Vector2(255.0, 325.0),
	Vector2(705.0, 355.0),
	Vector2(470.0, 330.0),
	Vector2(630.0, 510.0),
])


func get_spawn_area(player_id: int) -> Rect2:
	return player_spawn_area if player_id == 0 else bot_spawn_area
