class_name Reputation
extends RefCounted
## How each faction feels about you this voyage, from -100 to 100.
##
## Starts from each faction's "starting_reputation" (data/factions), shifted by
## the ship you chose ("start_rep" in data/ships). Changes with what you do:
## beating a faction's ship ("on_defeat" in data/factions), attacking or
## looting its port, and event outcomes ("rep" effects).
## A faction's "rep_ceiling" caps where it can start, and "fixed" means
## nothing you do changes its mind: the Company wants the artifact back and
## stays Hostile (Hated if you sail one of its stolen ships) all voyage.
##
## What it changes:
##   ports        prices by tier; Hated factions won't trade at all;
##                Friendly ports have an extra specialist for hire
##   at sea       Friendly ships salute and let you pass; Wary ones can be
##                paid to sheer off; Hostile ones fight. "always_hostile"
##                factions (the Company, slavers) never parley.
##   events       choices can need a reputation ("rep_min" / "rep_max")

const MIN := -100
const MAX := 100
const HATED := -60  # at or below: won't trade, gives no quarter
const HOSTILE := -15  # at or below: fights on sight
const FRIENDLY := 15  # at or above: lets you pass, better prices
const ALLIED := 50

const ORDER: Array[String] = ["brotherhood", "rivals", "navy", "company", "slavers"]  # display order

const PORT_TREACHERY := -15  # attacking a faction's port
const PORT_LOOTED := -10  # sacking its town as well
const PASSED_IN_PEACE := 2  # a friendly ship let us by
const TREACHERY := -15  # attacking a ship that hailed us as friends
const BRIBE_BASE := 10  # gold to make a wary captain sheer off, plus per sea
const BRIBE_PER_SEA := 6


static func start(run: RunState, ship: Dictionary) -> void:
	run.reputation = {}
	var shift: Dictionary = ship.get("start_rep", {})
	for f: Dictionary in Data.get_all("factions"):
		var id := str(f["id"])
		run.reputation[id] = clampi(int(f.get("starting_reputation", 0)) + int(shift.get(id, 0)), MIN, ceiling(id))


## The best a faction will ever think of you.
static func ceiling(faction: String) -> int:
	return int(Data.get_item("factions", faction).get("rep_ceiling", MAX))


static func of(run: RunState, faction: String) -> int:
	if not run.reputation.has(faction):
		return mini(int(Data.get_item("factions", faction).get("starting_reputation", 0)), ceiling(faction))
	return mini(int(run.reputation[faction]), ceiling(faction))


## Changes a faction's opinion. Returns a line like "the Navy +5", or "" if
## nothing changed.
static func change(run: RunState, faction: String, amount: int) -> String:
	if amount == 0 or not Data.has_item("factions", faction):
		return ""
	if bool(Data.get_item("factions", faction).get("fixed", false)):
		return ""
	var before := of(run, faction)
	if amount > 0:
		amount = roundi(amount * Perks.mult(run, "rep_gain"))
	run.reputation[faction] = clampi(before + amount, MIN, ceiling(faction))
	var moved := int(run.reputation[faction]) - before
	if moved == 0:
		return ""
	var line := "%s %+d" % [short_name(faction), moved]
	if tier(of(run, faction)) != tier(before):
		line += " (now %s)" % tier(of(run, faction)).to_lower()
	return line


## Applies several changes, e.g. { "navy": 5, "brotherhood": -5 }.
static func apply(run: RunState, changes: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for f: String in changes:
		var l := change(run, f, int(changes[f]))
		if l != "":
			lines.append(l)
	return lines


## Word of a victory spreads: the loser's faction resents it, its enemies approve.
static func on_defeat(run: RunState, faction: String) -> Array[String]:
	return apply(run, Data.get_item("factions", faction).get("on_defeat", {faction: -10}))


static func tier(value: int) -> String:
	if value <= HATED:
		return "Hated"
	if value <= HOSTILE:
		return "Hostile"
	if value < FRIENDLY:
		return "Wary"
	if value < ALLIED:
		return "Friendly"
	return "Allied"


static func tier_color(value: int) -> Color:
	if value <= HATED:
		return Color("e74c3c")
	if value <= HOSTILE:
		return Color("e67e22")
	if value < FRIENDLY:
		return Color("bdc3c7")
	if value < ALLIED:
		return Color("7dcea0")
	return Color("2ecc71")


static func short_name(faction: String) -> String:
	var s := str(Data.get_item("factions", faction).get("short_name", faction))
	return s.substr(0, 1).to_upper() + s.substr(1)


static func always_hostile(faction: String) -> bool:
	return bool(Data.get_item("factions", faction).get("always_hostile", false))


# --- Ports ------------------------------------------------------------------

## Multiplies the owner's prices.
static func price_factor(run: RunState, faction: String) -> float:
	var v := of(run, faction)
	if v >= ALLIED:
		return 0.8
	if v >= FRIENDLY:
		return 0.9
	if v > HOSTILE:
		return 1.0
	return 1.2


static func will_trade(run: RunState, faction: String) -> bool:
	return of(run, faction) > HATED


# --- At sea -----------------------------------------------------------------

## What a ship of this faction does when she sights us:
## "salute" (lets us pass), "parley" (open to a bribe) or "fight".
static func stance(run: RunState, faction: String) -> String:
	if faction == "" or always_hostile(faction):
		return "fight"
	var v := of(run, faction)
	if v >= FRIENDLY:
		return "salute"
	if v > HOSTILE:
		return "parley"
	return "fight"


static func bribe_cost(run: RunState) -> int:
	return BRIBE_BASE + BRIBE_PER_SEA * run.sea_number
