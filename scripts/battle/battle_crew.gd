class_name BattleCrew
extends RefCounted
## One crew member during a battle: where they are, where they're going,
## and who they are. Positions are in their ship's local space.

const SPEED := 45.0  # pixels per second
const MAX_HEALTH := 100.0
const WOUNDED := 50.0  # below this, a specialist's buff is halved

var crew_name := ""
var role := ""
var level := 1
var alive := true
var health := MAX_HEALTH
var death_reported := false
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


## This specialist's multiplier or bonus for a stat (from "buffs" in data/crew).
## Multipliers default to 1, bonuses (like accuracy) to 0. A wounded specialist
## gives half the effect; a dead one gives none.
func buff(stat: String, default := 1.0) -> float:
	var buffs: Dictionary = Data.get_item("crew", role).get("buffs", {})
	var value := float(buffs.get(stat, default))
	value = default + (value - default) * Hub.buff_scale(level)  # seasoned and veteran hands are better at it
	if not alive:
		return default
	if is_wounded():
		return default + (value - default) * 0.5
	return value


func is_wounded() -> bool:
	return alive and health < WOUNDED


## Takes damage. Returns true if this killed them.
func hurt(amount: float) -> bool:
	if not alive or amount <= 0.0:
		return false
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		alive = false
		return true
	return false


func heal(amount: float) -> void:
	if alive:
		health = minf(MAX_HEALTH, health + amount)


func role_name() -> String:
	return str(Data.get_item("crew", role).get("name", role))
