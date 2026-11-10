class_name Perks
extends RefCounted
## Relics and ship upgrades: the things that make one voyage's ship different
## from another's. Both are data (data/relics, data/upgrades).
##
## Relic:   { id, name, description, mods?, gain?, story? }   you own it or you don't
## Upgrade: { id, name, description, cost, max_level, mods?, gain? }   bought at ports, in levels
##
## "gain" is applied once when you get it (per level for upgrades):
##   max_hull, max_sails, max_hands   raises the maximum and what you have now
## "mods" apply all the time. A key ending in _add is summed, one ending in
## _mult is multiplied; upgrades count once per level. The game asks for them
## with Perks.add(run, "evasion") and Perks.mult(run, "reload"):
##   guns_add           guns a side
##   evasion_add        dodge
##   accuracy_add       hit chance
##   reload_mult        broadside reload time
##   boarding_mult      how hard our people fight hand to hand
##   gold_mult          prize gold
##   repair_add, mend_add, heal_add   hull, sails and specialist health after a win
##   price_mult         port prices
##   rep_gain_mult      reputation gains
##   morale_loss_mult   morale losses
##   morale_per_node_add, hunt_per_day_add   each day at sea

const UPGRADE_COST_GROWTH := 1.5  # each level costs this much more than the last
const RELIC_CHANCE := 0.25  # chance an ordinary prize has a relic aboard
const STARTING_RELIC := "aeolus_horn"


static func add(run: RunState, stat: String) -> float:
	var total := 0.0
	var key := stat + "_add"
	if run == null:
		return total
	for id: Variant in run.relics:
		total += float(_mods("relics", str(id)).get(key, 0.0))
	for id: Variant in run.upgrades:
		total += float(_mods("upgrades", str(id)).get(key, 0.0)) * int(run.upgrades[id])
	return total


static func mult(run: RunState, stat: String) -> float:
	var total := 1.0
	var key := stat + "_mult"
	if run == null:
		return total
	for id: Variant in run.relics:
		total *= float(_mods("relics", str(id)).get(key, 1.0))
	for id: Variant in run.upgrades:
		total *= pow(float(_mods("upgrades", str(id)).get(key, 1.0)), int(run.upgrades[id]))
	return total


static func _mods(category: String, id: String) -> Dictionary:
	if not Data.has_item(category, id):
		return {}
	return Data.get_item(category, id).get("mods", {})


# --- Relics -----------------------------------------------------------------

static func has_relic(run: RunState, id: String) -> bool:
	return run.relics.has(id)


static func give_relic(run: RunState, id: String) -> void:
	if run.relics.has(id) or not Data.has_item("relics", id):
		return
	run.relics.append(id)
	_gain(run, Data.get_item("relics", id).get("gain", {}))


## Up to `count` relics we don't have yet, in random order.
static func relic_offers(run: RunState, count: int) -> Array:
	var pool: Array = []
	for r: Dictionary in Data.get_all("relics"):
		if not bool(r.get("story", false)) and not run.relics.has(r["id"]):
			pool.append(r)
	pool.shuffle()
	return pool.slice(0, count)


## The relics we carry, as a list. The Aeolus Horn (a "story" relic) is always
## aboard, so it can be left out.
static func relic_names(run: RunState, with_story := true) -> String:
	var names: Array[String] = []
	for id: Variant in run.relics:
		if not Data.has_item("relics", str(id)):
			continue
		var r := Data.get_item("relics", str(id))
		if with_story or not bool(r.get("story", false)):
			names.append(str(r.get("name", id)))
	return ", ".join(names)


# --- Upgrades ---------------------------------------------------------------

static func level(run: RunState, id: String) -> int:
	return int(run.upgrades.get(id, 0))


static func can_upgrade(run: RunState, id: String) -> bool:
	return level(run, id) < int(Data.get_item("upgrades", id).get("max_level", 1))


## Gold for the next level, before port prices.
static func upgrade_cost(run: RunState, id: String) -> int:
	return roundi(int(Data.get_item("upgrades", id).get("cost", 50)) * pow(UPGRADE_COST_GROWTH, level(run, id)))


static func buy_upgrade(run: RunState, id: String) -> void:
	run.upgrades[id] = level(run, id) + 1
	_gain(run, Data.get_item("upgrades", id).get("gain", {}))


## Up to `count` upgrades that still have a level to buy, in random order.
static func upgrade_offers(run: RunState, count: int) -> Array:
	var pool: Array = []
	for u: Dictionary in Data.get_all("upgrades"):
		if can_upgrade(run, str(u["id"])):
			pool.append(u)
	pool.shuffle()
	return pool.slice(0, count)


static func _gain(run: RunState, gain: Dictionary) -> void:
	var hull := int(gain.get("max_hull", 0))
	run.max_hull += hull
	run.hull += hull
	var sails := int(gain.get("max_sails", 0))
	run.max_sails += sails
	run.sails += sails
	run.max_hands += int(gain.get("max_hands", 0))  # room for more; the hands still have to be found
