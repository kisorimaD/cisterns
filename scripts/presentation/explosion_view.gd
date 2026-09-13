class_name ExplosionView
extends Node2D

const DURATION := 0.8
const PIXEL := 4.0
const DIRECTIONS: Array[Vector2] = [
	Vector2(1, 0),
	Vector2(0.707, 0.707),
	Vector2(0, 1),
	Vector2(-0.707, 0.707),
	Vector2(-1, 0),
	Vector2(-0.707, -0.707),
	Vector2(0, -1),
	Vector2(0.707, -0.707),
]

var _elapsed := 0.0


func _ready() -> void:
	z_index = 40
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var progress: float = clampf(_elapsed / DURATION, 0.0, 1.0)
	var burst_progress: float = minf(progress / 0.58, 1.0)
	var fade: float = 1.0 - smoothstep(0.55, 1.0, progress)
	var core_size: float = roundf(lerpf(9.0, 3.0, progress)) * PIXEL
	_draw_pixel_square(Vector2.ZERO, core_size, Color(1.0, 0.93, 0.48, fade))
	_draw_pixel_square(Vector2(-8, -8), core_size * 0.62, Color(1.0, 0.35, 0.05, fade))
	_draw_pixel_square(Vector2(9, 7), core_size * 0.55, Color(1.0, 0.58, 0.08, fade))
	for index: int in DIRECTIONS.size():
		var direction: Vector2 = DIRECTIONS[index]
		var distance: float = roundf(lerpf(8.0, 42.0 + float(index % 3) * 4.0, burst_progress))
		var spark_size: float = PIXEL * (2.0 if index % 2 == 0 else 1.0)
		var spark_color := Color(1.0, 0.72, 0.12, fade)
		if progress > 0.55:
			spark_color = Color(0.22, 0.18, 0.15, fade * 0.8)
		_draw_pixel_square(direction * distance, spark_size, spark_color)


func _draw_pixel_square(center: Vector2, size: float, color: Color) -> void:
	var snapped_center := Vector2(roundf(center.x / PIXEL), roundf(center.y / PIXEL)) * PIXEL
	var snapped_size: float = maxf(PIXEL, roundf(size / PIXEL) * PIXEL)
	draw_rect(Rect2(snapped_center - Vector2.ONE * snapped_size * 0.5, Vector2.ONE * snapped_size), color)
