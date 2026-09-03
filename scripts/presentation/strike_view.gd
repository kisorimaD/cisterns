class_name StrikeView
extends Node2D

var strike_id := -1
var damage_radius := 40.0
var reveal_radius := 80.0
var is_preview := false
var is_valid := true


func configure(
		view_strike_id: int,
		map_position: Vector2,
		view_damage_radius: float,
		view_reveal_radius: float,
		preview: bool = false,
		valid: bool = true
) -> void:
	strike_id = view_strike_id
	position = map_position
	damage_radius = view_damage_radius
	reveal_radius = view_reveal_radius
	is_preview = preview
	is_valid = valid
	queue_redraw()


func _draw() -> void:
	var damage_color: Color = Color(1.0, 0.23, 0.12, 0.20 if is_preview else 0.34)
	var outline_color: Color = Color(1.0, 0.58, 0.18, 0.72)
	if not is_valid:
		damage_color = Color(0.5, 0.5, 0.5, 0.18)
		outline_color = Color(0.72, 0.72, 0.72, 0.65)
	draw_circle(Vector2.ZERO, reveal_radius, Color(outline_color, 0.08))
	draw_circle(Vector2.ZERO, reveal_radius, outline_color, false, 2.0)
	draw_circle(Vector2.ZERO, damage_radius, damage_color)
	draw_circle(Vector2.ZERO, damage_radius, outline_color, false, 3.0)
	draw_line(Vector2(-8.0, 0.0), Vector2(8.0, 0.0), outline_color, 2.0)
	draw_line(Vector2(0.0, -8.0), Vector2(0.0, 8.0), outline_color, 2.0)
