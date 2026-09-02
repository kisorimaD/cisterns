class_name UnitState
extends RefCounted

enum ResourceType {
	NONE = -1,
	WATER,
	GOLD,
}

var id: int
var owner_id: int
var position: Vector2
var movement_target: Vector2
var is_moving := false
var alive := true
var gathering_resource_type: ResourceType = ResourceType.NONE


func _init(unit_id: int, unit_owner_id: int, initial_position: Vector2) -> void:
	id = unit_id
	owner_id = unit_owner_id
	position = initial_position
	movement_target = initial_position
