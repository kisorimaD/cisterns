class_name GameMap
extends Node2D

const MAP_SIZE := Vector2(960.0, 672.0)

@export var ground_color := Color("#263b42")
@export var border_color := Color("#d8e2dc")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), ground_color)
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
