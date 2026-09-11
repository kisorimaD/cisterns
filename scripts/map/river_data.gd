class_name RiverData
extends Node2D

@export var river_id := 0
@export var path_points := PackedVector2Array([
	Vector2.ZERO,
	Vector2.RIGHT * 100.0,
])
@export var half_width := 42.0
@export var river_color := Color("#287fb8")
@export var center_color := Color("#5fc3df")

var maximum_income := 0
var _curve := Curve2D.new()


func _ready() -> void:
	_rebuild_curve()
	queue_redraw()


func sample(map_position: Vector2) -> ResourceSample:
	var result: ResourceSample = ResourceSample.new()
	if _curve.point_count < 2:
		return result
	var local_position: Vector2 = map_position - position
	var closest_point: Vector2 = _curve.get_closest_point(local_position)
	var distance: float = local_position.distance_to(closest_point)
	if distance > half_width:
		return result

	result.water_income = roundi(maximum_income * (1.0 - distance / half_width))
	result.river_id = river_id
	result.flow_offset = _curve.get_closest_offset(local_position)
	return result


func _draw() -> void:
	if _curve.point_count < 2:
		return
	var baked_points: PackedVector2Array = _curve.get_baked_points()
	draw_polyline(baked_points, river_color, half_width * 2.0, true)
	draw_polyline(baked_points, center_color, 4.0, true)
	draw_circle(path_points[0], half_width, river_color)
	draw_circle(path_points[path_points.size() - 1], half_width, river_color)
	var half_offset: float = _curve.get_baked_length() * 0.5
	var midpoint: Vector2 = _curve.sample_baked(half_offset)
	var direction: Vector2 = (
		_curve.sample_baked(half_offset + 4.0)
		- _curve.sample_baked(half_offset - 4.0)
	).normalized()
	var side: Vector2 = direction.orthogonal() * 7.0
	draw_colored_polygon(
		PackedVector2Array([
			midpoint + direction * 12.0,
			midpoint - direction * 8.0 + side,
			midpoint - direction * 8.0 - side,
		]),
		center_color
	)


func _rebuild_curve() -> void:
	_curve.clear_points()
	for index: int in path_points.size():
		var point: Vector2 = path_points[index]
		var previous: Vector2 = path_points[maxi(0, index - 1)]
		var next: Vector2 = path_points[mini(path_points.size() - 1, index + 1)]
		var tangent: Vector2 = (next - previous) * 0.2
		_curve.add_point(point, -tangent, tangent)
	_curve.bake_interval = 12.0
