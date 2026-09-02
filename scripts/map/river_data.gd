class_name RiverData
extends Node2D

@export var river_id := 0
@export var start_point := Vector2.ZERO
@export var end_point := Vector2.RIGHT * 100.0
@export var half_width := 42.0
@export var maximum_income := 10
@export var river_color := Color("#287fb8")
@export var center_color := Color("#5fc3df")


func _ready() -> void:
	queue_redraw()


func sample(map_position: Vector2) -> ResourceSample:
	var result: ResourceSample = ResourceSample.new()
	var local_position: Vector2 = map_position - position
	var closest_point: Vector2 = Geometry2D.get_closest_point_to_segment(
		local_position,
		start_point,
		end_point
	)
	var distance: float = local_position.distance_to(closest_point)
	if distance > half_width:
		return result

	var length: float = start_point.distance_to(end_point)
	var direction: Vector2 = (end_point - start_point).normalized()
	result.water_income = roundi(maximum_income * (1.0 - distance / half_width))
	result.river_id = river_id
	result.flow_offset = clampf((closest_point - start_point).dot(direction), 0.0, length)
	return result


func _draw() -> void:
	draw_line(start_point, end_point, river_color, half_width * 2.0, true)
	draw_line(start_point, end_point, center_color, 4.0, true)
	draw_circle(start_point, half_width, river_color)
	draw_circle(end_point, half_width, river_color)
	var direction: Vector2 = (end_point - start_point).normalized()
	var midpoint: Vector2 = start_point.lerp(end_point, 0.5)
	var side: Vector2 = direction.orthogonal() * 7.0
	draw_colored_polygon(
		PackedVector2Array([
			midpoint + direction * 12.0,
			midpoint - direction * 8.0 + side,
			midpoint - direction * 8.0 - side,
		]),
		center_color
	)
