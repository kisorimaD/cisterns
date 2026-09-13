class_name NetworkProtocol
extends RefCounted

const VERSION := 2
const MAXIMUM_COMMAND_TARGETS := 8


static func encode_command(command: GameCommand) -> Dictionary:
	return {
		"version": VERSION,
		"sequence": command.sequence_number,
		"type": int(command.type),
		"unit_id": command.unit_id,
		"target": command.target,
		"targets": command.targets,
	}


static func decode_command(payload: Variant, player_id: int) -> GameCommand:
	if not payload is Dictionary:
		return null
	var data: Dictionary = payload
	if (
		typeof(data.get("version")) != TYPE_INT
		or data["version"] != VERSION
		or typeof(data.get("sequence")) != TYPE_INT
		or data["sequence"] < 0
		or typeof(data.get("type")) != TYPE_INT
		or data["type"] < 0
		or data["type"] >= GameCommand.Type.size()
		or typeof(data.get("unit_id")) != TYPE_INT
		or typeof(data.get("target")) != TYPE_VECTOR2
	):
		return null
	var target: Vector2 = data["target"]
	if not is_finite(target.x) or not is_finite(target.y):
		return null
	var targets_value: Variant = data.get("targets", PackedVector2Array())
	if typeof(targets_value) != TYPE_PACKED_VECTOR2_ARRAY:
		return null
	var targets: PackedVector2Array = targets_value
	if targets.size() > MAXIMUM_COMMAND_TARGETS:
		return null
	for command_target: Vector2 in targets:
		if not is_finite(command_target.x) or not is_finite(command_target.y):
			return null
	var command := GameCommand.new()
	command.type = data["type"] as GameCommand.Type
	command.player_id = player_id
	command.unit_id = data["unit_id"]
	command.target = target
	command.targets = targets.duplicate()
	command.sequence_number = data["sequence"]
	return command


static func rules_signature(rules: GameRules) -> String:
	var stored_property_names: Array[String] = []
	for property: Dictionary in rules.get_property_list():
		if int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE:
			var property_name: String = property.get("name", "")
			if property_name != "script":
				stored_property_names.append(property_name)
	stored_property_names.sort()
	var signature_source := "protocol=%d" % VERSION
	for property_name: String in stored_property_names:
		signature_source += "|%s=%s" % [
			property_name,
			var_to_str(rules.get(property_name)),
		]
	return signature_source.sha256_text()
