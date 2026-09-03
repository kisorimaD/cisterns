class_name StrikeState
extends RefCounted

enum Type {
	BOMB,
	MISSILE,
}

var id: int
var owner_id: int
var type: Type
var target: Vector2
var impact_tick: int
var damage_radius: float
var reveal_radius: float
var reveal_started: bool = false


func _init(
		strike_id: int,
		strike_owner_id: int,
		strike_type: Type,
		strike_target: Vector2,
		strike_impact_tick: int,
		strike_damage_radius: float,
		strike_reveal_radius: float
) -> void:
	id = strike_id
	owner_id = strike_owner_id
	type = strike_type
	target = strike_target
	impact_tick = strike_impact_tick
	damage_radius = strike_damage_radius
	reveal_radius = strike_reveal_radius
