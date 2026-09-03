class_name GameMap
extends Node2D

const MAP_SIZE := Vector2(960.0, 672.0)
const SPAWN_AREAS: Array[Rect2] = [
	Rect2(48.0, 48.0, 144.0, 576.0),
	Rect2(768.0, 48.0, 144.0, 576.0),
]
const SPAWN_AREA_COLORS: Array[Color] = [
	Color("#67d5ff"),
	Color("#ef4f45"),
]
const SPAWN_CANDIDATE_Y: Array[float] = [120.0, 228.0, 336.0, 444.0, 552.0]

@export var ground_color := Color("#263b42")
@export var border_color := Color("#d8e2dc")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), ground_color)
	for player_id: int in SPAWN_AREAS.size():
		var area: Rect2 = SPAWN_AREAS[player_id]
		var color: Color = SPAWN_AREA_COLORS[player_id]
		draw_rect(area, Color(color, 0.08), true)
		draw_rect(area, Color(color, 0.62), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), border_color, false, 3.0)


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
		and player_id < SPAWN_AREAS.size()
		and SPAWN_AREAS[player_id].has_point(map_position)
	)


func get_spawn_candidates(player_id: int) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	if player_id < 0 or player_id >= SPAWN_AREAS.size():
		return candidates
	var center_x: float = SPAWN_AREAS[player_id].get_center().x
	for y: float in SPAWN_CANDIDATE_Y:
		candidates.append(Vector2(center_x, y))
	return candidates
