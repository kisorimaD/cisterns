extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var map_scene := load("res://scenes/map/map.tscn") as PackedScene
	var game_map := map_scene.instantiate() as GameMap
	root.add_child(game_map)
	var rules := GameRules.new()
	game_map.configure(rules)
	_test_gold_ring(game_map, rules)
	_test_mountain_detour(game_map, rules)
	print("Map navigation checks passed")
	game_map.free()
	quit()


func _test_gold_ring(game_map: GameMap, rules: GameRules) -> void:
	for center: Vector2 in rules.gold_field_centers:
		assert(game_map.sample_resources(center).gold_income == 0)
		assert(
			game_map.sample_resources(
				center + Vector2.RIGHT * (rules.gold_field_inner_radius + 1.0)
			).gold_income > 0
		)
		assert(
			game_map.sample_resources(
				center + Vector2.RIGHT * (rules.gold_field_outer_radius + 1.0)
			).gold_income == 0
		)


func _test_mountain_detour(game_map: GameMap, rules: GameRules) -> void:
	var center: Vector2 = rules.gold_field_centers[0]
	var start := Vector2(100.0, center.y)
	var target := Vector2(410.0, center.y)
	var path: PackedVector2Array = game_map.build_movement_path(
		start,
		target,
		rules.unit_obstacle_clearance
	)
	assert(path.size() > 2)
	var blocked_radius: float = (
		rules.mountain_obstacle_radius + rules.unit_obstacle_clearance
	)
	var segment_start: Vector2 = start
	for waypoint: Vector2 in path:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
			center,
			segment_start,
			waypoint
		)
		assert(closest.distance_to(center) >= blocked_radius - 0.1)
		segment_start = waypoint
	var center_target_path: PackedVector2Array = game_map.build_movement_path(
		start,
		center,
		rules.unit_obstacle_clearance
	)
	assert(not center_target_path.is_empty())
	assert(center_target_path[-1].distance_to(center) >= blocked_radius - 0.1)
