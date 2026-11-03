class_name BattleShip
extends RefCounted
## One ship's state during a battle: hull, guns, reload and ammo.
## Built from the run (player) or from data/enemies (enemy).

const BASE_RELOAD := 10.0  # seconds with 2 gunners; more gunners reload faster
const PLAYER_ACCURACY := 0.55

var display_name := ""
var hull := 0
var max_hull := 0
var guns := 0
var reload_time := BASE_RELOAD
var accuracy := PLAYER_ACCURACY
var reload := 0.0  # seconds of loading done
var armed := false  # fire as soon as loaded
var auto_fire := false
var unlimited_ammo := false
var ammo: Dictionary = {}  # ammo id -> rounds
var selected_ammo := "round_shot"


static func from_run(run: RunState, ship: Dictionary) -> BattleShip:
	var s := BattleShip.new()
	s.display_name = str(ship.get("name", "Your ship"))
	s.hull = run.hull
	s.max_hull = run.max_hull
	s.guns = int(ship.get("guns_per_side", 4))
	var gunners := run.crew.filter(func(c: Dictionary) -> bool: return c.get("role") == "gunner").size()
	s.reload_time = clampf(BASE_RELOAD * 2.0 / maxf(1.0, gunners), 4.0, 16.0)
	s.ammo = run.ammo.duplicate()
	return s


static func from_enemy(data: Dictionary) -> BattleShip:
	var s := BattleShip.new()
	s.display_name = str(data.get("name", "Enemy"))
	s.max_hull = int(data.get("max_hull", 20))
	s.hull = s.max_hull
	s.guns = int(data.get("guns_per_side", 3))
	s.reload_time = float(data.get("reload_time", BASE_RELOAD))
	s.accuracy = float(data.get("accuracy", 0.5))
	s.unlimited_ammo = true
	return s


func tick(delta: float) -> void:
	if not is_loaded():
		reload = minf(reload + delta, reload_time)


func is_loaded() -> bool:
	return reload >= reload_time


func reload_ratio() -> float:
	return reload / reload_time


func shots_available() -> int:
	if unlimited_ammo or is_free_ammo(selected_ammo):
		return guns
	return mini(guns, int(ammo.get(selected_ammo, 0)))


## Fires the broadside. Returns one entry per gun: true for a hit.
func fire() -> Array[bool]:
	var shots := shots_available()
	var hits: Array[bool] = []
	for i in shots:
		hits.append(randf() < accuracy)
	if not unlimited_ammo and not is_free_ammo(selected_ammo):
		ammo[selected_ammo] = int(ammo.get(selected_ammo, 0)) - shots
	reload = 0.0
	armed = false
	return hits


## Round shot never runs out; special ammo is counted.
static func is_free_ammo(ammo_id: String) -> bool:
	return bool(Data.get_item("ammo", ammo_id).get("unlimited", false))


func damage_per_hit() -> int:
	return int(Data.get_item("ammo", selected_ammo).get("hull_damage", 1))


func take_damage(amount: int) -> void:
	hull = maxi(0, hull - amount)
