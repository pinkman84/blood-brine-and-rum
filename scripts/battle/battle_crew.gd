class_name BattleCrew
extends RefCounted
## One crew member during a battle: where they are, where they're going,
## and who they are. Positions are in their ship's local space.

const SPEED := 45.0  # pixels per second

var crew_name := ""
var role := ""
var level := 1
var alive := true
var color := Color.WHITE
var room_id := ""
var pos := Vector2.ZERO
var target := Vector2.ZERO
var source: Dictionary = {}  # the run's crew entry, for writing results back


func is_moving() -> bool:
	return pos.distance_to(target) > 0.5


func step(delta: float) -> void:
	pos = pos.move_toward(target, SPEED * delta)


## The room type this crew member is trained for (from data/crew).
func station() -> String:
	return str(Data.get_item("crew", role).get("station", "hold"))


func role_name() -> String:
	return str(Data.get_item("crew", role).get("name", role))
