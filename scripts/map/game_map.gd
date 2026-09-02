class_name GameMap
extends Node2D

const MAP_SIZE := Vector2(960.0, 672.0)

@export var ground_color := Color("#263b42")
@export var border_color := Color("#d8e2dc")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), ground_color)
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), border_color, false, 3.0)
