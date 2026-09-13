extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_scene := load("res://scenes/game/game.tscn") as PackedScene
	var game := game_scene.instantiate()
	root.add_child(game)
	await process_frame
	var hud: Control = game.get_node("UI/HUD")
	assert(hud.position == Vector2(24.0, 24.0))
	assert(hud.get_node_or_null("%WaterLabel") != null)
	assert(hud.get_node_or_null("%GoldLabel") != null)
	assert(hud.get_node_or_null("%BombButton") != null)
	assert(hud.get_node_or_null("%MissileButton") != null)
	assert(hud.get_node_or_null("%RepairButton") != null)
	assert(hud.get_node_or_null("%RepairButton").disabled)
	assert(hud.get_node_or_null("%DebugLabel") == null)
	assert(game.get_node("World/Map").clip_children == CanvasItem.CLIP_CHILDREN_AND_DRAW)
	assert(game.get_node("World/UnitViews").z_index > game.get_node("World/Map").z_index)
	print("Presentation scene checks passed")
	game.free()
	quit()
