class_name UnitView
extends Node2D

const CISTERN_ATLAS: Texture2D = preload("res://assets/units/cistern_truck_directions.png")
const CISTERN_COLUMNS := 4
const CISTERN_ROWS := 2
const CISTERN_DISPLAY_SIZE := 52.0
const DIRECTION_STEP := TAU / 8.0
const UPSTREAM_BADGE_POSITION := Vector2(0.0, -40.0)
const UPSTREAM_BADGE_RADIUS := 10.0
const UPSTREAM_BADGE_COLOR := Color("#f4cf3f")
const UPSTREAM_TEXT_COLOR := Color("#111111")
const UPSTREAM_FONT_SIZE := 14

@export var unit_id := -1
@export var map_position := Vector2.ZERO
@export var team_color := Color("#67d5ff"):
	set(value):
		team_color = value
		if is_node_ready():
			_update_sprite_color()

@onready var _cistern_sprite: Sprite2D = %CisternSprite

var _movement_tween: Tween
var _upstream_count := 0
var _upstream_badge_visible := false
var _facing_angle := 0.0


func _ready() -> void:
	_configure_sprite()
	_update_world_position()


func snap_to_position(new_position: Vector2) -> void:
	if _movement_tween != null:
		_movement_tween.kill()
	map_position = new_position
	position = new_position


func move_to_position(new_position: Vector2, duration_seconds: float) -> void:
	if _movement_tween != null:
		_movement_tween.kill()
	var movement_direction: Vector2 = new_position - position
	if not movement_direction.is_zero_approx():
		_facing_angle = movement_direction.angle()
		_update_sprite_frame()
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
	if _upstream_badge_visible:
		_draw_upstream_badge()


func _configure_sprite() -> void:
	_cistern_sprite.texture = CISTERN_ATLAS
	_cistern_sprite.region_enabled = true
	_cistern_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var cell_size: Vector2 = _sprite_cell_size()
	_cistern_sprite.scale = Vector2.ONE * (CISTERN_DISPLAY_SIZE / cell_size.x)
	_update_sprite_color()
	_update_sprite_frame()


func _update_sprite_color() -> void:
	_cistern_sprite.modulate = team_color.lightened(0.22)


func _update_sprite_frame() -> void:
	var frame_index: int = posmod(roundi(_facing_angle / DIRECTION_STEP), 8)
	var cell_size: Vector2 = _sprite_cell_size()
	_cistern_sprite.region_rect = Rect2(
		Vector2(frame_index % CISTERN_COLUMNS, frame_index / CISTERN_COLUMNS) * cell_size,
		cell_size
	)


func _sprite_cell_size() -> Vector2:
	return Vector2(
		float(CISTERN_ATLAS.get_width()) / CISTERN_COLUMNS,
		float(CISTERN_ATLAS.get_height()) / CISTERN_ROWS
	)


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
