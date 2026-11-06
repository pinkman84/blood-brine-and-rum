class_name RunState
extends RefCounted
## Everything about the current voyage. Converted to and from a Dictionary
## for saving. When you add a field, add it to to_dict() and from_dict().

const SEAS_PER_RUN := 5
const NODES_PER_SEA := SeaMapGen.LAYERS  # steps from a sea's entrance to its exit
const START_HANDS := 0.8  # a run starts with this share of the ship's hands

var run_seed: int = 0
var ship_id: String = ""
var sea_number: int = 1  # which sea of the run we're in, 1-based
var node_index: int = 0  # nodes resolved in the current sea
var gold: int = 0
var hull: int = 0
var max_hull: int = 0
var sails: int = 0
var max_sails: int = 0
var hands: int = 0  # general crew: a resource, not individuals
var max_hands: int = 0
var crew: Array[Dictionary] = []  # specialists, each { name, role, level, health, post? }
var ammo: Dictionary = {}  # ammo id -> rounds
var prisoners: int = 0  # held below for ransom at a trading post
var morale: int = Morale.START
var rum: int = Morale.START_RUM  # rations; the crew drinks one per node
var days: int = 0  # days at sea this run; one per node
var map: Dictionary = {}  # this sea's node map (SeaMapGen); empty until first shown
var elite_pending := false  # the next battle is the sea's exit fight
var last_note := ""  # a line to show on the map when we return to it
var sea_id := ""  # which sea we're in (data/seas)
var route: Array = []  # sea ids sailed so far, in order
var hunt: int = 0  # the Company's hunt for us, 0 to 100 (see Voyage)
var hunter_pending := false  # the next battle is a Company hunter
var battles_won: int = 0


static func new_run(ship: Dictionary) -> RunState:
	var run := RunState.new()
	run.run_seed = randi()
	run.ship_id = str(ship["id"])
	run.max_hull = int(ship["max_hull"])
	run.hull = run.max_hull
	run.max_sails = int(ship.get("max_sails", 20))
	run.sails = run.max_sails
	run.gold = int(ship.get("starting_gold", 0))
	run.max_hands = int(ship.get("max_hands", 100))
	run.hands = roundi(run.max_hands * START_HANDS)
	var names: Array = Data.get_item("names", "crew_names").get("values", ["Sailor"])
	var rng := RandomNumberGenerator.new()
	rng.seed = run.run_seed
	for role: Variant in ship.get("starting_crew", []):
		run.crew.append({
			"name": str(names[rng.randi_range(0, names.size() - 1)]),
			"role": str(role),
			"level": 1,
			"health": 100,
		})
	var start_ammo: Dictionary = ship.get("starting_ammo", {})
	for ammo_id: Variant in start_ammo:
		run.ammo[str(ammo_id)] = int(start_ammo[ammo_id])
	return run


func to_dict() -> Dictionary:
	return {
		"run_seed": run_seed,
		"ship_id": ship_id,
		"sea_number": sea_number,
		"node_index": node_index,
		"gold": gold,
		"hull": hull,
		"max_hull": max_hull,
		"sails": sails,
		"max_sails": max_sails,
		"hands": hands,
		"max_hands": max_hands,
		"crew": crew,
		"ammo": ammo,
		"prisoners": prisoners,
		"morale": morale,
		"rum": rum,
		"days": days,
		"map": map,
		"elite_pending": elite_pending,
		"sea_id": sea_id,
		"route": route,
		"hunt": hunt,
		"hunter_pending": hunter_pending,
		"battles_won": battles_won,
	}


static func from_dict(data: Dictionary) -> RunState:
	var run := RunState.new()
	run.run_seed = int(data.get("run_seed", 0))
	run.ship_id = str(data.get("ship_id", ""))
	run.sea_number = int(data.get("sea_number", 1))
	run.node_index = int(data.get("node_index", 0))
	run.gold = int(data.get("gold", 0))
	run.hull = int(data.get("hull", 0))
	run.max_hull = int(data.get("max_hull", run.hull))
	run.max_sails = int(data.get("max_sails", 20))
	run.sails = int(data.get("sails", run.max_sails))
	run.max_hands = int(data.get("max_hands", 100))
	run.hands = int(data.get("hands", run.max_hands))
	for member: Variant in data.get("crew", []):
		var m: Dictionary = member
		run.crew.append({
			"name": str(m.get("name", "")),
			"role": str(m.get("role", "")),
			"level": int(m.get("level", 1)),
			"health": int(m.get("health", 100)),
			"post": str(m.get("post", "")),
		})
	var saved_ammo: Dictionary = data.get("ammo", {})
	for ammo_id: Variant in saved_ammo:
		run.ammo[str(ammo_id)] = int(saved_ammo[ammo_id])
	run.battles_won = int(data.get("battles_won", 0))
	run.prisoners = int(data.get("prisoners", 0))
	run.morale = int(data.get("morale", Morale.START))
	run.rum = int(data.get("rum", Morale.START_RUM))
	run.days = int(data.get("days", 0))
	run.map = data.get("map", {})
	run.elite_pending = bool(data.get("elite_pending", false))
	run.sea_id = str(data.get("sea_id", ""))
	run.route = data.get("route", [])
	run.hunt = int(data.get("hunt", 0))
	run.hunter_pending = bool(data.get("hunter_pending", false))
	if run.sea_id == "":  # saves from before the sea chart
		run.sea_id = Voyage.START_SEA
		run.route = [Voyage.START_SEA]
	return run


func is_last_node_of_sea() -> bool:
	return node_index >= NODES_PER_SEA - 1
