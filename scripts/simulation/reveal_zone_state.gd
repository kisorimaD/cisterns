class_name RevealZoneState
extends RefCounted

var id: int
var owner_id: int
var center: Vector2
var radius: float
var expires_at_tick: int


func _init(
		zone_id: int,
		zone_owner_id: int,
		zone_center: Vector2,
		zone_radius: float,
		zone_expires_at_tick: int
) -> void:
	id = zone_id
	owner_id = zone_owner_id
	center = zone_center
	radius = zone_radius
	expires_at_tick = zone_expires_at_tick
