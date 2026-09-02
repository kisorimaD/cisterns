class_name UnitView
extends Node2D

@export var unit_id := -1
@export var map_position := Vector2.ZERO
@export var team_color := Color("#67d5ff"):
	set(value):
		team_color = value
		queue_redraw()

var _movement_tween: Tween


func _ready() -> void:
	_update_world_position()


func snap_to_position(new_position: Vector2) -> void:
	if _movement_tween != null:
		_movement_tween.kill()
	map_position = new_position
	position = new_position


func move_to_position(new_position: Vector2, duration_seconds: float) -> void:
	if _movement_tween != null:
		_movement_tween.kill()
	map_position = new_position
	_movement_tween = create_tween()
	_movement_tween.set_trans(Tween.TRANS_LINEAR)
	_movement_tween.tween_property(self, "position", new_position, duration_seconds)


func set_selected(is_selected: bool) -> void:
	$SelectionRing.visible = is_selected


func set_gathering(is_gathering: bool) -> void:
	$GatheringIndicator.visible = is_gathering


func _draw() -> void:
	# Temporary cistern silhouette: chassis, tracks and a round water tank.
	draw_rect(Rect2(-Vector2(16.0, 10.0), Vector2(32.0, 20.0)), Color("#17262b"), true)
	draw_rect(Rect2(-Vector2(14.0, 12.0), Vector2(28.0, 24.0)), team_color, true)
	draw_circle(Vector2.ZERO, 9.0, team_color.lightened(0.18))
	draw_circle(Vector2.ZERO, 9.0, Color("#e8f4f2"), false, 2.0)
	draw_line(Vector2(7.0, 0.0), Vector2(18.0, 0.0), Color("#e8f4f2"), 3.0)


func _update_world_position() -> void:
	position = map_position
