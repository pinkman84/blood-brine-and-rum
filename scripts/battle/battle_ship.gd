class_name BattleShip
extends RefCounted
## One ship's state during a battle: hull, sails, guns, reload and ammo.
## Built from the run (player) or from data/enemies (enemy).

const BASE_RELOAD := 10.0  # seconds with a full gun crew (gun factor 1)
const SIDES: Array[String] = ["starboard", "port"]
const STALL_TIME := 3.0  # seconds stuck halfway ("in irons") when a turn goes wrong
const RAKE_MULTIPLIER := 2  # hull and hands lost to a hit taken mid-turn
const PLAYER_ACCURACY := 0.55
## Ammo whose effects work so far. The rest show in the picker but are locked.
const WORKING_AMMO: Array[String] = ["round_shot", "chain_shot", "grape_shot", "heated_shot"]

var display_name := ""
var hull := 0
var max_hull := 0
var sails := 0
var max_sails := 0
var base_evasion := 0.0  # chance to dodge a shot with full sails
var guns := 0
var reload_time := BASE_RELOAD
var base_accuracy := PLAYER_ACCURACY
var accuracy := PLAYER_ACCURACY  # base plus specialist bonuses, set each frame
var hands := 0
var max_hands := 0
## Each broadside loads on its own; only the side facing the enemy can fire.
var engaged_side := "starboard"
var reloads := {"starboard": 0.0, "port": 0.0}  # seconds of loading done
## Set each frame from the hands, rooms and specialists (see battle_screen.gd).
var gun_factors := {"starboard": 1.0, "port": 1.0}  # reload speed per side; 0 = out of action
var turning := false
var turn_time := 8.0
var turn_progress := 0.0  # 0 to 1
var will_stall := false
var stall_left := 0.0
var stalled := false
var fleeing := false  # making sail to escape
var escape := 0.0  # 0 to 1; at 1 she's away
var flees_at := 0.0  # hull share at which an enemy captain runs (0 = never)
var boards := false  # an enemy captain who likes to grapple and board
var ai: Dictionary = {}  # the enemy faction's fighting style (data/factions "ai")
var captives := 0  # people chained below decks (slavers)
var morale_factor := 1.0  # from Morale.factor(); enemies fight at 1.0 for now
var helm_factor := 1.0  # scales evasion; 0 = nobody steering
var armed := false  # fire as soon as loaded
var auto_fire := false
var unlimited_ammo := false
var ammo: Dictionary = {}  # ammo id -> rounds
var selected_ammo := "round_shot"
var rooms: Dictionary = {}  # room id -> damage, fire and flood state (see DamageControl)


static func from_run(run: RunState, ship: Dictionary) -> BattleShip:
	var s := BattleShip.new()
	s.display_name = str(ship.get("name", "Your ship"))
	s.hull = run.hull
	s.max_hull = run.max_hull
	s.sails = run.sails
	s.max_sails = run.max_sails
	s.base_evasion = float(ship.get("evasion", 0.1))
	s.guns = int(ship.get("guns_per_side", 4))
	s.hands = run.hands
	s.max_hands = run.max_hands
	s.morale_factor = Morale.factor(run.morale)
	s.ammo = run.ammo.duplicate()
	return s


static func from_enemy(data: Dictionary) -> BattleShip:
	var s := BattleShip.new()
	s.display_name = str(data.get("name", "Enemy"))
	s.max_hull = int(data.get("max_hull", 20))
	s.hull = s.max_hull
	s.max_sails = int(data.get("max_sails", 15))
	s.sails = s.max_sails
	s.base_evasion = float(data.get("evasion", 0.05))
	s.guns = int(data.get("guns_per_side", 3))
	s.reload_time = float(data.get("reload_time", BASE_RELOAD))
	s.base_accuracy = float(data.get("accuracy", 0.5))
	s.accuracy = s.base_accuracy
	s.max_hands = int(data.get("max_hands", 100))
	s.hands = s.max_hands
	s.unlimited_ammo = true
	s.flees_at = float(data.get("flees_at", 0.0))
	s.boards = bool(data.get("boards", false))
	s.captives = int(data.get("captives", 0))
	var faction := str(data.get("faction", ""))
	if Data.has_item("factions", faction):
		s.ai = Data.get_item("factions", faction).get("ai", {})
	return s


func init_rooms(view_rooms: Array[Dictionary]) -> void:
	rooms.clear()
	for room in view_rooms:
		rooms[room["id"]] = DamageControl.new_room()


func tick(delta: float) -> void:
	for side: String in SIDES:
		reloads[side] = minf(float(reloads[side]) + delta * float(gun_factors[side]), reload_time)


func other_side() -> String:
	return "port" if engaged_side == "starboard" else "starboard"


## Is a broadside loaded? Defaults to the side facing the enemy.
func is_loaded(side := "") -> bool:
	return float(reloads[side if side != "" else engaged_side]) >= reload_time


func reload_ratio(side := "") -> float:
	return float(reloads[side if side != "" else engaged_side]) / reload_time


func gun_factor(side := "") -> float:
	return float(gun_factors[side if side != "" else engaged_side])


func can_fire() -> bool:
	return not turning and is_loaded() and shots_available() > 0


# --- Coming about -----------------------------------------------------------

## Starts turning to bring the other broadside to bear. Returns false if
## already turning.
func start_turn(time: float, stall_chance: float) -> bool:
	if turning:
		return false
	turning = true
	turn_time = maxf(1.0, time)
	turn_progress = 0.0
	will_stall = randf() < stall_chance
	stalled = false
	stall_left = 0.0
	return true


## Advances a turn. Returns "stalled" or "done" when those happen, else "".
func tick_turn(delta: float) -> String:
	if not turning:
		return ""
	if stall_left > 0.0:
		stall_left -= delta
		return ""
	if will_stall and not stalled and turn_progress >= 0.5:
		stalled = true
		stall_left = STALL_TIME
		return "stalled"
	turn_progress = minf(1.0, turn_progress + delta / turn_time)
	if turn_progress >= 1.0:
		turning = false
		engaged_side = other_side()
		return "done"
	return ""


## The ship's rotation: 0 with starboard facing the enemy, PI with port.
func facing_angle() -> float:
	var base := 0.0 if engaged_side == "starboard" else PI
	if turning:
		base += PI * smoothstep(0.0, 1.0, turn_progress)
	return base


func hands_ratio() -> float:
	return float(hands) / maxf(1.0, max_hands)


## How hard the hands can work: how many are left, times their morale.
## Scales reloads, damage control, turning and grappling.
func effort() -> float:
	return hands_ratio() * morale_factor


func hull_ratio() -> float:
	return float(hull) / maxf(1.0, max_hull)


## How fast she can sail right now, for running and chasing.
func speed() -> float:
	return sails_ratio() * helm_factor


func lose_hands(amount: int) -> void:
	hands = maxi(0, hands - amount)


func sails_ratio() -> float:
	return float(sails) / maxf(1.0, max_sails)


## Dodge chance right now. Shredded sails, a wrecked helm or a turn in
## progress leave a ship wallowing.
func evasion() -> float:
	var e := base_evasion * sails_ratio() * helm_factor
	return e * 0.5 if turning else e


func shots_available() -> int:
	if unlimited_ammo or is_free_ammo(selected_ammo):
		return guns
	return mini(guns, int(ammo.get(selected_ammo, 0)))


## Fires the broadside at a target with the given evasion.
## Returns one entry per gun: true for a hit.
func fire(target_evasion: float) -> Array[bool]:
	var shots := shots_available()
	var hit_chance := accuracy * (1.0 - target_evasion)
	var hits: Array[bool] = []
	for i in shots:
		hits.append(randf() < hit_chance)
	if not unlimited_ammo and not is_free_ammo(selected_ammo):
		ammo[selected_ammo] = int(ammo.get(selected_ammo, 0)) - shots
	reloads[engaged_side] = 0.0
	armed = false
	return hits


## Round shot never runs out; special ammo is counted.
static func is_free_ammo(ammo_id: String) -> bool:
	return bool(Data.get_item("ammo", ammo_id).get("unlimited", false))


## Applies one hit of the given ammo type. A ship caught mid-turn shows her
## stern, and a raking shot does double hull and crew damage. Returns true if
## the hit raked her.
func take_hit(ammo_id: String) -> bool:
	var a := Data.get_item("ammo", ammo_id)
	var mult := RAKE_MULTIPLIER if turning else 1
	hull = maxi(0, hull - int(a.get("hull_damage", 1)) * mult)
	sails = maxi(0, sails - int(a.get("sail_damage", 0)))
	lose_hands(roundi(float(a.get("crew_damage", 0)) * randf_range(0.5, 1.5)) * mult)
	return turning


## True if this ammo mostly hits rigging rather than the hull.
static func aims_high(ammo_id: String) -> bool:
	var a := Data.get_item("ammo", ammo_id)
	return int(a.get("sail_damage", 0)) > int(a.get("hull_damage", 0))
