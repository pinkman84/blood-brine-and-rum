class_name Augments
extends RefCounted
## Ship augments: people and kit you carry aboard that change how the ship
## fights or sails, like FTL's augments. Data in data/augments.
##
## How they differ from relics and upgrades: a ship has only MAX_SLOTS of
## them, so finding a new one when full means choosing one to throw over
## (ScreenBase.offer_augment). Each has a rarity, which sets how often it
## turns up and what it costs.
##
## Augment: { id, name, description, rarity, mods?, faction? }
##   rarity   common, uncommon or rare (see RARITY)
##   mods     same keys as relics (see Perks); Perks.add/mult count augments too.
##            Keys only augments use so far:
##              firefight_mult      how fast fires are put out
##              cut_mult            chance to cut a grapple rope
##              sniper_add          snipers in the rigging (see battle_screen)
##              last_stand_add      chance a fallen specialist stays in service
##              catch_add           chance a day at sea brings in cargo
##              shot_damage_add     hull damage per round or heated shot
##              explode_chance_add  chance a round shot hit explodes
##              hunt_mult           how fast the Company hunt grows (Voyage)
##              enemy_effort_mult   how hard the enemy's hands work
##              grapple_mult        chance our grapples catch
##              fire_chance_add     chance any hull hit starts a fire
##              escape_mult         how fast we escape (enemies escape us slower)
##   faction  only found by beating that faction: in plunder from her ships
##            (FACTION_SHARE of augment finds) and in her forts' armouries
##            (the occupied town, see shop_screen). data/augments/faction_augments.json
##
## Where they come from: plunder after a battle (BATTLE_CHANCE, or
## ELITE_CHANCE from a sea's exit captain), outpost augment stalls, events
## (the "augment" effect, see Events), and faction armouries.
##
## Cargo (data/cargo: { id, name, value, weight }) is the whaler's catch,
## carried in run.cargo and sold at ports and outposts.

const MAX_SLOTS := 3
const BATTLE_CHANCE := 0.10  # an ordinary prize has an augment among her plunder
const ELITE_CHANCE := 0.25  # a sea's exit captain
const STALL_OFFERS := 2  # most augments an outpost stall has for sale
const FACTION_SHARE := 0.5  # an augment found aboard a beaten ship is one of her faction's own
## How often each rarity turns up (relative weights) and its base price.
const RARITY := {
	"common": {"weight": 6.0, "cost": 60},
	"uncommon": {"weight": 3.0, "cost": 100},
	"rare": {"weight": 1.0, "cost": 150},
}


static func name_of(id: String) -> String:
	return str(Data.get_item("augments", id).get("name", id))


static func rarity(id: String) -> String:
	return str(Data.get_item("augments", id).get("rarity", "common"))


## Base price before an outpost's prices.
static func cost(id: String) -> int:
	return int(RARITY.get(rarity(id), RARITY["common"])["cost"])


## "Navy training (uncommon): reload 15% faster..."
static func describe(id: String) -> String:
	var a := Data.get_item("augments", id)
	return "%s (%s): %s" % [a.get("name", id), label(id), a.get("description", "")]


## "rare", or "uncommon, Navy" for a faction's own.
static func label(id: String) -> String:
	var who := faction_name(id)
	return rarity(id) if who == "" else "%s, %s" % [rarity(id), who]


static func is_full(run: RunState) -> bool:
	return run.augments.size() >= MAX_SLOTS


## Fits an augment if there's a free slot. Returns false if the ship is full.
static func fit(run: RunState, id: String) -> bool:
	if is_full(run) or not Data.has_item("augments", id):
		return false
	run.augments.append(id)
	return true


static func swap(run: RunState, old_id: String, new_id: String) -> void:
	var i := run.augments.find(old_id)
	if i >= 0:
		run.augments[i] = new_id


## A random augment we don't carry, rarer ones less often. `exclude` keeps
## two offers from being the same. With a `faction`, only that faction's own
## augments; without, only ones anyone can find. "" if there are none left.
static func roll(run: RunState, exclude: Array = [], faction := "") -> String:
	var pool: Array = []
	var total := 0.0
	for a: Dictionary in Data.get_all("augments"):
		var id := str(a["id"])
		if run.augments.has(id) or exclude.has(id) or str(a.get("faction", "")) != faction:
			continue
		pool.append(a)
		total += float(RARITY.get(str(a.get("rarity", "common")), RARITY["common"])["weight"])
	var pick := randf() * total
	for a: Dictionary in pool:
		pick -= float(RARITY.get(str(a.get("rarity", "common")), RARITY["common"])["weight"])
		if pick <= 0.0:
			return str(a["id"])
	return "" if pool.is_empty() else str(pool.back()["id"])


## An augment found aboard a beaten ship of this faction: sometimes one of
## her faction's own, otherwise any.
static func roll_plunder(run: RunState, faction: String) -> String:
	if faction != "" and randf() < FACTION_SHARE:
		var own := roll(run, [], faction)
		if own != "":
			return own
	return roll(run)


static func faction_name(id: String) -> String:
	var faction := str(Data.get_item("augments", id).get("faction", ""))
	if faction == "":
		return ""
	return str(Data.get_item("factions", faction).get("short_name", faction)).trim_prefix("the ").capitalize()


static func names(run: RunState) -> String:
	var found: Array[String] = []
	for id: Variant in run.augments:
		found.append(name_of(str(id)))
	return ", ".join(found)


# --- Cargo (the whaler's catch) ----------------------------------------------

## A day's sailing: maybe the whaler brings something in. Returns a line for
## the map, or "".
static func catch_at_sea(run: RunState) -> String:
	if randf() >= Perks.add(run, "catch"):
		return ""
	var all := Data.get_all("cargo")
	var total := 0.0
	for c: Dictionary in all:
		total += float(c.get("weight", 1.0))
	var pick := randf() * total
	for c: Dictionary in all:
		pick -= float(c.get("weight", 1.0))
		if pick <= 0.0:
			var id := str(c["id"])
			run.cargo[id] = int(run.cargo.get(id, 0)) + 1
			return "Thar she blows! The whaler brings in %s (worth %d gold)." % [str(c["name"]).to_lower(), int(c["value"])]
	return ""


static func cargo_value(run: RunState) -> int:
	var total := 0
	for id: Variant in run.cargo:
		total += int(Data.get_item("cargo", str(id)).get("value", 0)) * int(run.cargo[id])
	return total


## "2 whale oil, 1 ambergris"
static func cargo_text(run: RunState) -> String:
	var parts: Array[String] = []
	for id: Variant in run.cargo:
		parts.append("%d %s" % [int(run.cargo[id]), str(Data.get_item("cargo", str(id)).get("name", id)).to_lower()])
	return ", ".join(parts)


## Sells the whole hold. Returns the gold made.
static func sell_cargo(run: RunState) -> int:
	var gold := cargo_value(run)
	run.gold += gold
	run.cargo.clear()
	return gold
