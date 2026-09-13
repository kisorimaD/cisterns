extends SceneTree


func _init() -> void:
	_test_command_round_trip()
	_test_airstrike_command_round_trip()
	_test_command_rejects_bad_payloads()
	_test_player_identity_is_server_owned()
	_test_visibility_projection_rule()
	_test_rules_signature_is_stable_and_complete()
	_test_network_scenes_and_project_settings()
	print("Network contract checks passed")
	quit()


func _test_command_round_trip() -> void:
	var source := GameCommand.move_unit(99, 7, Vector2(123.0, 456.0))
	source.sequence_number = 12
	var decoded: GameCommand = NetworkProtocol.decode_command(
		NetworkProtocol.encode_command(source),
		1
	)
	assert(decoded != null)
	assert(decoded.player_id == 1)
	assert(decoded.unit_id == 7)
	assert(decoded.target == Vector2(123.0, 456.0))
	assert(decoded.sequence_number == 12)


func _test_airstrike_command_round_trip() -> void:
	var targets := PackedVector2Array([
		Vector2(100.0, 200.0),
		Vector2(300.0, 400.0),
		Vector2(500.0, 600.0),
	])
	var source := GameCommand.launch_airstrike(0, targets)
	source.sequence_number = 13
	var decoded: GameCommand = NetworkProtocol.decode_command(
		NetworkProtocol.encode_command(source),
		1
	)
	assert(decoded != null)
	assert(decoded.player_id == 1)
	assert(decoded.targets == targets)


func _test_command_rejects_bad_payloads() -> void:
	assert(NetworkProtocol.decode_command({}, 0) == null)
	assert(NetworkProtocol.decode_command({
		"version": NetworkProtocol.VERSION,
		"sequence": 0,
		"type": 999,
		"unit_id": -1,
		"target": Vector2.ZERO,
	}, 0) == null)
	assert(NetworkProtocol.decode_command({
		"version": NetworkProtocol.VERSION,
		"sequence": 0,
		"type": GameCommand.Type.LAUNCH_BOMB,
		"unit_id": -1,
		"target": Vector2(NAN, 0.0),
	}, 0) == null)


func _test_player_identity_is_server_owned() -> void:
	var source := GameCommand.launch_bomb(0, Vector2(40.0, 50.0))
	source.sequence_number = 1
	var payload: Dictionary = NetworkProtocol.encode_command(source)
	assert(not payload.has("player_id"))
	var decoded: GameCommand = NetworkProtocol.decode_command(payload, 1)
	assert(decoded.player_id == 1)


func _test_visibility_projection_rule() -> void:
	assert(StateProjector.should_include_unit(0, 0, false))
	assert(StateProjector.should_include_unit(1, 0, true))
	assert(not StateProjector.should_include_unit(1, 0, false))
	assert(StateProjector.should_include_strike(0, StrikeState.Type.BOMB, 0))
	assert(not StateProjector.should_include_strike(1, StrikeState.Type.BOMB, 0))
	assert(StateProjector.should_include_strike(1, StrikeState.Type.MISSILE, 0))


func _test_rules_signature_is_stable_and_complete() -> void:
	var first := GameRules.new()
	var second := GameRules.new()
	assert(NetworkProtocol.rules_signature(first) == NetworkProtocol.rules_signature(second))
	second.unit_move_speed += 1.0
	assert(NetworkProtocol.rules_signature(first) != NetworkProtocol.rules_signature(second))


func _test_network_scenes_and_project_settings() -> void:
	assert(
		ProjectSettings.get_setting("application/run/main_scene")
		== "res://scenes/bootstrap/bootstrap.tscn"
	)
	assert(
		ProjectSettings.get_setting("autoload/NetworkSession")
		== "*res://scripts/network/network_session.gd"
	)
	var rules := load("res://resources/default_game_rules.tres") as GameRules
	assert(rules != null)
	assert(rules.player_initial_positions.size() == rules.maximum_active_units)
	assert(rules.bot_initial_positions.size() == rules.maximum_active_units)
	assert(rules.maximum_water == 30)
	assert(rules.airstrike_target_count == 3)
	var menu_scene := load("res://scenes/menu/network_menu.tscn") as PackedScene
	var game_scene := load("res://scenes/game/game.tscn") as PackedScene
	var bootstrap_scene := load("res://scenes/bootstrap/bootstrap.tscn") as PackedScene
	assert(bootstrap_scene != null)
	assert(menu_scene != null)
	assert(game_scene != null)
	var menu := menu_scene.instantiate()
	var game := game_scene.instantiate()
	assert(menu.get_node_or_null("%HostButton") != null)
	assert(menu.get_node_or_null("%PublicButton") != null)
	assert(menu.get_node_or_null("%SoloButton") != null)
	assert(menu.get_node_or_null("%DisconnectButton") != null)
	assert(game.get_node_or_null("%GameState") != null)
	assert(game.get_node_or_null("%ClientMatchState") != null)
	assert(game.get_node_or_null("%NetworkMatch") != null)
	assert(game.get_node_or_null("%UnitViews").get_child_count() == 0)
	menu.free()
	game.free()
