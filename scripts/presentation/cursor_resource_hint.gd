class_name CursorResourceHint
extends PanelContainer

const CURSOR_OFFSET := Vector2(14.0, 18.0)
const VIEWPORT_MARGIN := Vector2(8.0, 8.0)

@onready var _water_value: Label = %WaterValue
@onready var _gold_value: Label = %GoldValue


func _ready() -> void:
	visible = false


func on_target_preview_changed(
		screen_position: Vector2,
		_map_position: Vector2,
		water_income: int,
		gold_income: int,
		valid: bool
) -> void:
	visible = valid
	if not valid:
		return
	_water_value.text = str(water_income)
	_gold_value.text = str(gold_income)
	var viewport_size: Vector2 = get_viewport_rect().size
	position = (screen_position + CURSOR_OFFSET).clamp(
		VIEWPORT_MARGIN,
		viewport_size - size - VIEWPORT_MARGIN
	)
