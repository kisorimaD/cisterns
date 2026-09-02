class_name UnitState
extends RefCounted

var id: int
var owner_id: int
var position: Vector2
var movement_target: Vector2
var is_moving := false
var alive := true
var gathering_resource_type := -1


func _init(unit_id: int, unit_owner_id: int, initial_position: Vector2) -> void:
	id = unit_id
	owner_id = unit_owner_id
	position = initial_position
	movement_target = initial_position
