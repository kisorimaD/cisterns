class_name PlayerState
extends RefCounted

var id: int
var water := 0
var gold := 0
var active_unit_ids: Array[int] = []
var bomb_cooldown_ticks := 0


func _init(player_id: int) -> void:
	id = player_id
