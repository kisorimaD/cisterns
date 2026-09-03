class_name UnitView
extends Node2D

const UPSTREAM_BADGE_POSITION := Vector2(0.0, -34.0)
const UPSTREAM_BADGE_RADIUS := 10.0
const UPSTREAM_BADGE_COLOR := Color("#f4cf3f")
const UPSTREAM_TEXT_COLOR := Color("#111111")
const UPSTREAM_FONT_SIZE := 14

@export var unit_id := -1
@export var map_position := Vector2.ZERO
@export var team_color := Color("#67d5ff"):
	set(value):
		team_color = value
		queue_redraw()

var _movement_tween: Tween
var _upstream_count := 0
var _upstream_badge_visible := false


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


func set_upstream_count(count: int, is_visible: bool) -> void:
	if _upstream_count == count and _upstream_badge_visible == is_visible:
		return
	_upstream_count = count
	_upstream_badge_visible = is_visible
	queue_redraw()


func _draw() -> void:
	# Temporary cistern silhouette: chassis, tracks and a round water tank.
	draw_rect(Rect2(-Vector2(16.0, 10.0), Vector2(32.0, 20.0)), Color("#17262b"), true)
	draw_rect(Rect2(-Vector2(14.0, 12.0), Vector2(28.0, 24.0)), team_color, true)
	draw_circle(Vector2.ZERO, 9.0, team_color.lightened(0.18))
	draw_circle(Vector2.ZERO, 9.0, Color("#e8f4f2"), false, 2.0)
	draw_line(Vector2(7.0, 0.0), Vector2(18.0, 0.0), Color("#e8f4f2"), 3.0)
	if _upstream_badge_visible:
		_draw_upstream_badge()


func _draw_upstream_badge() -> void:
	draw_circle(UPSTREAM_BADGE_POSITION, UPSTREAM_BADGE_RADIUS, UPSTREAM_BADGE_COLOR)
	var font: Font = ThemeDB.fallback_font
	var text: String = str(_upstream_count)
	var text_size: Vector2 = font.get_string_size(
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		UPSTREAM_FONT_SIZE
	)
	var baseline: Vector2 = UPSTREAM_BADGE_POSITION + Vector2(
		-text_size.x * 0.5,
		text_size.y * 0.35
	)
	draw_string(
		font,
		baseline,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		UPSTREAM_FONT_SIZE,
		UPSTREAM_TEXT_COLOR
	)


func _update_world_position() -> void:
	position = map_position
