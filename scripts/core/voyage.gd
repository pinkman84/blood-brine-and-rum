class_name Voyage
extends RefCounted
## The run's route across the seas, and the Company's hunt for you.
##
## Route: every run starts in the Caribbean and ends in the South China Sea.
## In between, at each sea's exit you choose the next sea on the sea chart,
## from CHART_CHOICES you haven't sailed yet (data/seas, role "middle").
##
## Difficulty rises with how many seas you've crossed, not which sea it is:
## enemies get tougher and pay better by SEA_SCALE per sea.
##
## Who you meet also changes as the voyage goes on (progress, 0 at the start
## to 1 at the end). Every faction has a light, a medium and a heavy ship
## ("class" in data/enemies). Early on they're mostly light and medium,
## under-crewed and short of specialists; by the end they're mostly medium
## and heavy, with full crews and every specialist aboard.
##
## The Hunt (0 to 100): the Company closing in. It rises every day at sea and
## whenever you sink or take a Company ship, and eases a little when you cross
## into new waters. From HUNTED, Company hunter frigates start replacing
## ordinary enemies; at 100 a hunter intercepts you at your next node.

const START_SEA := "caribbean"
const FINAL_SEA := "south_china_sea"
const CHART_CHOICES := 2

const SEA_SCALE := 0.12  # extra hull and hands per sea crossed
const SEA_ACCURACY := 0.02  # extra enemy accuracy per sea crossed
const SEA_GOLD := 0.15  # extra prize gold per sea crossed

# Enemy ships by progress: each value goes from its EARLY figure to its LATE one.
const CLASS_WEIGHTS_EARLY := {"light": 6.0, "medium": 3.5, "heavy": 0.5}
const CLASS_WEIGHTS_LATE := {"light": 1.5, "medium": 4.5, "heavy": 4.0}
const HANDS_EARLY := 0.6  # share of her full crew an early enemy has aboard
const HANDS_LATE := 1.0
const HANDS_SPREAD := 0.1  # each ship varies by up to this much either way
const SPECIALISTS_EARLY := 0.34  # share of her specialists an early enemy carries (at least one)
const SPECIALISTS_LATE := 1.0

const HUNT_PER_DAY := 4
const HUNT_PER_COMPANY_SHIP := 8
const HUNT_NEW_SEA := -15
const HUNTED := 50  # hunters start to appear
const INTERCEPT := 100  # a hunter finds you
const AFTER_INTERCEPT := 60  # where the hunt drops to once a hunter has found you


static func sea(run: RunState) -> Dictionary:
	var id := run.sea_id if run.sea_id != "" else START_SEA
	return Data.get_item("seas", id)


static func sea_name(run: RunState) -> String:
	return str(sea(run).get("name", "Unknown waters"))


## Seas offered on the chart: middle seas not yet sailed, CHART_CHOICES at most.
static func chart_options(run: RunState) -> Array:
	var options: Array = []
	for s: Dictionary in Data.get_all("seas"):
		if s.get("role", "") == "middle" and not run.route.has(s["id"]):
			options.append(s)
	options.shuffle()
	return options.slice(0, CHART_CHOICES)


## Move into a sea: record it, draw a fresh map on first sight, ease the hunt.
static func enter_sea(run: RunState, id: String) -> void:
	run.sea_id = id
	run.route.append(id)
	run.map = {}
	if run.route.size() > 1:
		change_hunt(run, HUNT_NEW_SEA)


static func change_hunt(run: RunState, amount: int) -> void:
	run.hunt = clampi(run.hunt + amount, 0, INTERCEPT)


## Multiplier for enemy hull, hands and so on in the current sea.
static func scale(run: RunState) -> float:
	return 1.0 + SEA_SCALE * (run.sea_number - 1)


## How far through the voyage we are: 0 at the first node, 1 at the last.
static func progress(run: RunState) -> float:
	var done := (run.sea_number - 1) + float(run.node_index) / RunState.NODES_PER_SEA
	return clampf(done / RunState.SEAS_PER_RUN, 0.0, 1.0)


## How likely a ship of this class ("light", "medium", "heavy") is right now.
## Ships without a class (elites, forts) count as 1.
static func class_weight(run: RunState, ship_class: String) -> float:
	if not CLASS_WEIGHTS_EARLY.has(ship_class):
		return 1.0
	return lerpf(float(CLASS_WEIGHTS_EARLY[ship_class]), float(CLASS_WEIGHTS_LATE[ship_class]), progress(run))


## Fits an ordinary enemy out for this point in the voyage: how much of her
## crew she has aboard and how many of her specialists (listed most important
## first in data/enemies "crew"). `at` is the progress to fit her out for.
static func fit_out(enemy: Dictionary, at: float) -> void:
	var share := lerpf(HANDS_EARLY, HANDS_LATE, at) + randf_range(-HANDS_SPREAD, HANDS_SPREAD)
	enemy["hands_share"] = clampf(share, 0.4, 1.0)
	var crew: Array = enemy.get("crew", [])
	var keep := maxi(1, roundi(crew.size() * lerpf(SPECIALISTS_EARLY, SPECIALISTS_LATE, at)))
	enemy["crew"] = crew.slice(0, keep)


## Chance the next ordinary battle is a Company hunter instead.
static func hunter_chance(run: RunState) -> float:
	if run.hunt < HUNTED:
		return 0.0
	return clampf(float(run.hunt - HUNTED + 10) / 60.0, 0.0, 1.0)
