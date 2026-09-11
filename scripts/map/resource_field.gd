class_name ResourceField2D
extends Node2D

@export var radius := 58.0
@export var field_color := Color(0.95, 0.72, 0.14, 0.32)

var maximum_income := 0


func _ready() -> void:
	queue_redraw()


func sample(map_position: Vector2) -> int:
	var distance: float = position.distance_to(map_position)
	if distance > radius:
		return 0
	return roundi(maximum_income * (1.0 - distance / radius))


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, field_color)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-42.0, 24.0),
			Vector2(0.0, -42.0),
			Vector2(42.0, 24.0),
		]),
		Color("#68757b")
	)
	draw_circle(Vector2(0.0, 7.0), 13.0, Color("#f4c542"))
	draw_circle(Vector2(0.0, 7.0), 13.0, Color("#fff0a6"), false, 2.0)
