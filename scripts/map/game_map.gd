class_name GameMap
extends Node2D

const SPAWN_AREA_COLORS: Array[Color] = [
	Color("#67d5ff"),
	Color("#ef4f45"),
]
const GROUND_PALETTE: Array[Color] = [
	Color("#263b36"),
	Color("#2b4038"),
	Color("#303e35"),
	Color("#293b32"),
]

@export var rules: GameRules = preload("res://resources/default_game_rules.tres")
@export var ground_color := Color("#263b42")
@export var border_color := Color("#d8e2dc")


func _ready() -> void:
	var visual_rng := RandomNumberGenerator.new()
	visual_rng.randomize()
	ground_color = GROUND_PALETTE[visual_rng.randi_range(0, GROUND_PALETTE.size() - 1)]
	queue_redraw()


func configure(game_rules: GameRules) -> void:
	rules = game_rules
	for child: Node in $Rivers.get_children():
		if child is RiverData:
			var river: RiverData = child as RiverData
			river.maximum_income = rules.maximum_water_income
			river.queue_redraw()
	var field_index := 0
	for child: Node in $ResourceFields.get_children():
		if child is ResourceField2D:
			var field: ResourceField2D = child as ResourceField2D
			field.maximum_income = rules.maximum_gold_income
			field.inner_radius = rules.gold_field_inner_radius
			field.radius = rules.gold_field_outer_radius
			field.obstacle_radius = rules.mountain_obstacle_radius
			if field_index < rules.gold_field_centers.size():
				field.position = rules.gold_field_centers[field_index]
			field_index += 1
			field.queue_redraw()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, rules.map_size), ground_color)
	for player_id: int in SPAWN_AREA_COLORS.size():
		var area: Rect2 = _get_spawn_area(player_id)
		var color: Color = SPAWN_AREA_COLORS[player_id]
		draw_rect(area, Color(color, 0.08), true)
		draw_rect(area, Color(color, 0.62), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, rules.map_size), border_color, false, 3.0)


func sample_resources(map_position: Vector2) -> ResourceSample:
	var result: ResourceSample = ResourceSample.new()
	for child: Node in $Rivers.get_children():
		if child is RiverData:
			var river: RiverData = child as RiverData
			var river_sample: ResourceSample = river.sample(map_position)
			if river_sample.water_income > result.water_income:
				result.water_income = river_sample.water_income
				result.river_id = river_sample.river_id
				result.flow_offset = river_sample.flow_offset

	for child: Node in $ResourceFields.get_children():
		if child is ResourceField2D:
			var field: ResourceField2D = child as ResourceField2D
			result.gold_income = maxi(result.gold_income, field.sample(map_position))
	return result


func is_position_in_spawn_area(player_id: int, map_position: Vector2) -> bool:
	return (
		player_id >= 0
		and player_id < SPAWN_AREA_COLORS.size()
		and _get_spawn_area(player_id).has_point(map_position)
	)


func is_position_blocked(map_position: Vector2, clearance := 0.0) -> bool:
	for child: Node in $ResourceFields.get_children():
		if child is ResourceField2D:
			var field: ResourceField2D = child as ResourceField2D
			if map_position.distance_to(field.position) < field.obstacle_radius + clearance:
				return true
	return false


func build_movement_path(
		start: Vector2,
		requested_target: Vector2,
		clearance: float
) -> PackedVector2Array:
	var target: Vector2 = _push_outside_obstacles(requested_target, start, clearance)
	var path := PackedVector2Array()
	var current: Vector2 = start
	var routed_fields: Dictionary[ResourceField2D, bool] = {}
	for _iteration: int in $ResourceFields.get_child_count():
		var field: ResourceField2D = _first_intersecting_field(
			current,
			target,
			clearance,
			routed_fields
		)
		if field == null:
			break
		var detour: PackedVector2Array = _build_circle_detour(
			current,
			target,
			field.position,
			field.obstacle_radius + clearance
		)
		for waypoint: Vector2 in detour:
			if path.is_empty() or not path[-1].is_equal_approx(waypoint):
				path.append(waypoint)
		current = path[-1] if not path.is_empty() else current
		routed_fields[field] = true
	if path.is_empty() or not path[-1].is_equal_approx(target):
		path.append(target)
	return path


func _push_outside_obstacles(
		requested_target: Vector2,
		start: Vector2,
		clearance: float
) -> Vector2:
	var target: Vector2 = requested_target
	for child: Node in $ResourceFields.get_children():
		if not child is ResourceField2D:
			continue
		var field: ResourceField2D = child as ResourceField2D
		var blocked_radius: float = field.obstacle_radius + clearance
		if target.distance_to(field.position) >= blocked_radius:
			continue
		var direction: Vector2 = (target - field.position).normalized()
		if direction.is_zero_approx():
			direction = (start - field.position).normalized()
		if direction.is_zero_approx():
			direction = Vector2.RIGHT
		target = field.position + direction * blocked_radius
	return target


func _first_intersecting_field(
		start: Vector2,
		target: Vector2,
		clearance: float,
		excluded: Dictionary[ResourceField2D, bool]
) -> ResourceField2D:
	var result: ResourceField2D
	var nearest_distance := INF
	for child: Node in $ResourceFields.get_children():
		if not child is ResourceField2D:
			continue
		var field: ResourceField2D = child as ResourceField2D
		if excluded.has(field):
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
			field.position,
			start,
			target
		)
		if closest.distance_to(field.position) >= field.obstacle_radius + clearance:
			continue
		var distance_from_start: float = start.distance_to(closest)
		if distance_from_start < nearest_distance:
			nearest_distance = distance_from_start
			result = field
	return result


func _build_circle_detour(
		start: Vector2,
		target: Vector2,
		center: Vector2,
		blocked_radius: float
) -> PackedVector2Array:
	const ARC_STEP := PI / 9.0
	var route_radius: float = blocked_radius + 8.0
	var route_start: Vector2 = _push_to_radius(start, center, route_radius)
	var route_target: Vector2 = _push_to_radius(target, center, route_radius)
	var result := PackedVector2Array()
	if not route_start.is_equal_approx(start):
		result.append(route_start)
	var start_angles: PackedFloat32Array = _tangent_angles(route_start, center, route_radius)
	var target_angles: PackedFloat32Array = _tangent_angles(route_target, center, route_radius)
	var best_start_angle: float = start_angles[0]
	var best_target_angle: float = target_angles[0]
	var best_delta: float = wrapf(best_target_angle - best_start_angle, -PI, PI)
	var best_length := INF
	for start_angle: float in start_angles:
		for target_angle: float in target_angles:
			var delta: float = wrapf(target_angle - start_angle, -PI, PI)
			var start_tangent := center + Vector2.from_angle(start_angle) * route_radius
			var target_tangent := center + Vector2.from_angle(target_angle) * route_radius
			var length: float = (
				route_start.distance_to(start_tangent)
				+ absf(delta) * route_radius
				+ target_tangent.distance_to(route_target)
			)
			if length < best_length:
				best_length = length
				best_start_angle = start_angle
				best_target_angle = target_angle
				best_delta = delta
	var start_tangent := center + Vector2.from_angle(best_start_angle) * route_radius
	if result.is_empty() or not result[-1].is_equal_approx(start_tangent):
		result.append(start_tangent)
	var arc_segments: int = maxi(1, ceili(absf(best_delta) / ARC_STEP))
	for index: int in range(1, arc_segments + 1):
		var angle: float = best_start_angle + best_delta * float(index) / arc_segments
		result.append(center + Vector2.from_angle(angle) * route_radius)
	if not route_target.is_equal_approx(target):
		result.append(route_target)
	return result


func _push_to_radius(point: Vector2, center: Vector2, radius: float) -> Vector2:
	var offset: Vector2 = point - center
	if offset.length() >= radius:
		return point
	return center + offset.normalized() * radius


func _tangent_angles(point: Vector2, center: Vector2, radius: float) -> PackedFloat32Array:
	var offset: Vector2 = point - center
	var distance: float = maxf(offset.length(), radius)
	var tangent_offset: float = acos(clampf(radius / distance, -1.0, 1.0))
	return PackedFloat32Array([
		offset.angle() - tangent_offset,
		offset.angle() + tangent_offset,
	])


func get_spawn_candidates(player_id: int) -> Array[Vector2]:
	var candidates: Array[Vector2] = []
	if player_id < 0 or player_id >= SPAWN_AREA_COLORS.size():
		return candidates
	var center_x: float = _get_spawn_area(player_id).get_center().x
	for y: float in rules.replacement_spawn_candidate_y:
		candidates.append(Vector2(center_x, y))
	return candidates


func _get_spawn_area(player_id: int) -> Rect2:
	return rules.get_spawn_area(player_id)
