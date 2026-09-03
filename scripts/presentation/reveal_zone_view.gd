class_name RevealZoneView
extends Node2D

var zone_id := -1
var owner_id := -1
var radius := 80.0


func configure(
		view_zone_id: int,
		view_owner_id: int,
		map_position: Vector2,
		view_radius: float
) -> void:
	zone_id = view_zone_id
	owner_id = view_owner_id
	position = map_position
	radius = view_radius
	queue_redraw()


func _draw() -> void:
	var fill: Color = Color(0.72, 0.94, 1.0, 0.13)
	var outline: Color = Color(0.72, 0.94, 1.0, 0.62)
	draw_circle(Vector2.ZERO, radius, fill)
	draw_circle(Vector2.ZERO, radius, outline, false, 2.0)
