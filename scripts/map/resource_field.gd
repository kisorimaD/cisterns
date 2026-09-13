class_name ResourceField2D
extends Node2D

const MOUNTAIN_ATLAS: Texture2D = preload("res://assets/map/gold_mountains.png")

@export var radius := 126.0
@export var inner_radius := 94.0
@export var obstacle_radius := 64.0
@export var field_color := Color(0.95, 0.72, 0.14, 0.32)
@export_range(0, 1) var visual_variant := 0

var maximum_income := 0


func _ready() -> void:
	_create_mountain_sprite()
	queue_redraw()


func sample(map_position: Vector2) -> int:
	var distance: float = position.distance_to(map_position)
	if distance < inner_radius or distance > radius:
		return 0
	var ring_depth: float = (distance - inner_radius) / (radius - inner_radius)
	return roundi(maximum_income * (1.0 - ring_depth))


func _draw() -> void:
	var ring_radius: float = (inner_radius + radius) * 0.5
	draw_arc(
		Vector2.ZERO,
		ring_radius,
		0.0,
		TAU,
		72,
		field_color,
		radius - inner_radius
	)
	draw_arc(
		Vector2.ZERO,
		inner_radius,
		0.0,
		TAU,
		64,
		Color(1.0, 0.82, 0.27, 0.72),
		2.0
	)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(1.0, 0.82, 0.27, 0.58), 2.0)


func _create_mountain_sprite() -> void:
	var cell_width: float = float(MOUNTAIN_ATLAS.get_width()) / 2.0
	var sprite := Sprite2D.new()
	sprite.texture = MOUNTAIN_ATLAS
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		Vector2(cell_width * visual_variant, 0.0),
		Vector2(cell_width, MOUNTAIN_ATLAS.get_height())
	)
	sprite.scale = Vector2.ONE * 0.18
	sprite.position.y = -7.0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 1
	add_child(sprite)
