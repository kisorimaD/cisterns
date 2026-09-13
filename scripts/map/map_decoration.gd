class_name MapDecoration
extends Node2D

const DECORATION_ATLAS: Texture2D = preload("res://assets/map/land_decorations.png")
const ATLAS_COLUMNS := 4
const ATLAS_ROWS := 3
const DECORATION_COUNT := 42
const PATCH_CLUSTER_COUNT := 14
const PATCH_COLORS: Array[Color] = [
	Color("#52714a"),
	Color("#6d7543"),
	Color("#3e6953"),
	Color("#786044"),
]

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_generate_diffuse_ground_color()
	_generate_sprites()


func _generate_diffuse_ground_color() -> void:
	var map_size: Vector2 = _map_size()
	for _cluster: int in PATCH_CLUSTER_COUNT:
		var center := Vector2(
			_rng.randf_range(0.0, map_size.x),
			_rng.randf_range(0.0, map_size.y)
		)
		var base_color: Color = PATCH_COLORS[
			_rng.randi_range(0, PATCH_COLORS.size() - 1)
		]
		for layer: int in 3:
			var gradient := Gradient.new()
			var center_color := Color(base_color, 0.14 - layer * 0.025)
			gradient.offsets = PackedFloat32Array([0.0, 0.46, 1.0])
			gradient.colors = PackedColorArray([
				center_color,
				Color(base_color, center_color.a * 0.48),
				Color(base_color, 0.0),
			])
			var texture := GradientTexture2D.new()
			texture.width = 96
			texture.height = 96
			texture.fill = GradientTexture2D.FILL_RADIAL
			texture.fill_from = Vector2(0.5, 0.5)
			texture.fill_to = Vector2(1.0, 0.5)
			texture.gradient = gradient
			var tint := Sprite2D.new()
			tint.texture = texture
			tint.position = center + Vector2(
				_rng.randf_range(-34.0, 34.0),
				_rng.randf_range(-28.0, 28.0)
			)
			tint.scale = Vector2(
				_rng.randf_range(1.0, 2.5),
				_rng.randf_range(0.65, 1.65)
			)
			tint.rotation = _rng.randf_range(0.0, TAU)
			add_child(tint)


func _generate_sprites() -> void:
	var cell_size := Vector2(
		float(DECORATION_ATLAS.get_width()) / ATLAS_COLUMNS,
		float(DECORATION_ATLAS.get_height()) / ATLAS_ROWS
	)
	var map_size: Vector2 = _map_size()
	for _index: int in DECORATION_COUNT:
		var atlas_index: int = _rng.randi_range(0, ATLAS_COLUMNS * ATLAS_ROWS - 1)
		var sprite := Sprite2D.new()
		sprite.texture = DECORATION_ATLAS
		sprite.region_enabled = true
		sprite.region_rect = Rect2(
			Vector2(atlas_index % ATLAS_COLUMNS, atlas_index / ATLAS_COLUMNS) * cell_size,
			cell_size
		)
		sprite.position = Vector2(
			_rng.randf_range(28.0, map_size.x - 28.0),
			_rng.randf_range(28.0, map_size.y - 28.0)
		)
		var visual_scale: float = _rng.randf_range(0.10, 0.16)
		sprite.scale = Vector2.ONE * visual_scale
		sprite.rotation = _rng.randf_range(-0.12, 0.12)
		sprite.modulate = Color(1.0, 1.0, 1.0, _rng.randf_range(0.55, 0.86))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)


func _map_size() -> Vector2:
	var game_map: GameMap = get_parent() as GameMap
	return game_map.rules.map_size if game_map != null else Vector2(960.0, 640.0)
