class_name GameMap
extends Node2D

const SPAWN_AREA_COLORS: Array[Color] = [
	Color("#67d5ff"),
	Color("#ef4f45"),
]

@export var rules: GameRules = preload("res://resources/default_game_rules.tres")
@export var ground_color := Color("#263b42")
@export var border_color := Color("#d8e2dc")


func configure(game_rules: GameRules) -> void:
	rules = game_rules
	for child: Node in $Rivers.get_children():
		if child is RiverData:
			var river: RiverData = child as RiverData
			river.maximum_income = rules.maximum_water_income
			river.queue_redraw()
	for child: Node in $ResourceFields.get_children():
		if child is ResourceField2D:
			var field: ResourceField2D = child as ResourceField2D
			field.maximum_income = rules.maximum_gold_income
			field.queue_redraw()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, rules.map_size), ground_color)
	for player_id: int in SPAWN_AREA_COLORS.size():
		var area: Rect2 = _get_spawn_area(player_id)
		var color: Color = SPAWN_AREA_COLORS[player_id]
		draw_rect(area, Color(color, 0.08), true)
		draw_rect(area, Color(color, 0.62), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, rules.map_size), border_color, false, 3.0)


func sample_resources(map_position: Vector2) -> ResourceSample:
	var result: ResourceSample = ResourceSample.new()
	for child: Node in $Rivers.get_children():
		if child is RiverData:
			var river: RiverData = child as RiverData
			var river_sample: ResourceSample = river.sample(map_position)
			if river_sample.water_income > result.water_income:
				result.water_income = river_sample.water_income
				result.river_id = river_sample.river_id
				result.flow_offset = river_sample.flow_offset

	for child: Node in $ResourceFields.get_children():
		if child is ResourceField2D:
			var field: ResourceField2D = child as ResourceField2D
			result.gold_income = maxi(result.gold_income, field.sample(map_position))
	return result


func is_position_in_spawn_area(player_id: int, map_position: Vector2) -> bool:
	return (
		player_id >= 0
		and player_id < SPAWN_AREA_COLORS.size()
		and _get_spawn_area(player_id).has_point(map_position)
	)


func get_spawn_candidates(player_id: int) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	if player_id < 0 or player_id >= SPAWN_AREA_COLORS.size():
		return candidates
	var center_x: float = _get_spawn_area(player_id).get_center().x
	for y: float in rules.replacement_spawn_candidate_y:
		candidates.append(Vector2(center_x, y))
	return candidates


func _get_spawn_area(player_id: int) -> Rect2:
	return rules.get_spawn_area(player_id)
