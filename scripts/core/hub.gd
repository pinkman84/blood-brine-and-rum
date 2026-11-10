class_name Hub
extends RefCounted
## Everything that lasts between voyages: the home port and what you've
## unlocked. All of it lives in SaveSystem.meta (meta.json).
##
## Home port (data/hub): places you build and improve with doubloons, each
## up to three levels. Every voyage after that starts a little better:
##   tavern        specialists are more often seasoned or veteran (SPECIALIST_ODDS)
##   cartographer  more treasure on every sea (TREASURE_PER_LEVEL)
##   carpenter     more hull to start with (HULL_PER_LEVEL)
##   old_captain   room for more hands, and a fuller crew (HANDS_PER_LEVEL, CREW_PER_LEVEL)
## Meta keys: "doubloons", "hub_<id>" = level.
##
## Ships (data/ships "unlock"): { type: "always" } or
## { type: "meta", key, hint }, unlocked once that meta key is above zero:
##   "reached_final_sea"   set the first time a voyage gets to the last sea
##   "victories"           counts voyages won
##   "quest_<id>"          set when that quest is completed
##
## Quests (data/quests): started by an event's "quest" effect, tracked for the
## voyage in run.quests, completed by Hub.check_quests when their goal
## happens. A finished quest stays finished.

const HOME_PORT := "Blackwater Cay"
const TREASURE_PER_LEVEL := 0.6  # extra weight for treasure nodes
const HULL_PER_LEVEL := 4
const HANDS_PER_LEVEL := 5
const CREW_PER_LEVEL := 0.05  # share of the ship's hands aboard at the start
# Tavern level -> [chance of seasoned (level 2), chance of veteran (level 3)]
const SPECIALIST_ODDS := [[0.0, 0.0], [0.25, 0.0], [0.45, 0.1], [0.5, 0.25]]
const RANKS := ["", "", "seasoned ", "veteran "]  # by specialist level
const LEVEL_BONUS := 0.25  # each level above 1 makes a specialist's buffs this much stronger
const HIRE_PER_LEVEL := 10  # extra gold to hire, per level above 1


# --- Home port --------------------------------------------------------------

static func level(id: String) -> int:
	return SaveSystem.meta_int("hub_" + id)


static func max_level(id: String) -> int:
	return (Data.get_item("hub", id).get("costs", []) as Array).size()


## Doubloons for the next level, or -1 if there isn't one.
static func next_cost(id: String) -> int:
	var costs: Array = Data.get_item("hub", id).get("costs", [])
	return int(costs[level(id)]) if level(id) < costs.size() else -1


static func doubloons() -> int:
	return SaveSystem.meta_int("doubloons")


static func improve(id: String) -> bool:
	var cost := next_cost(id)
	if cost < 0 or doubloons() < cost:
		return false
	SaveSystem.add_meta("doubloons", -cost)
	SaveSystem.add_meta("hub_" + id, 1)
	SaveSystem.save_meta()
	return true


## What the place does for you at its current level ("" if not built).
static func effect_text(id: String) -> String:
	var lvl := level(id)
	var texts: Array = Data.get_item("hub", id).get("levels", [])
	return str(texts[lvl - 1]) if lvl > 0 and lvl <= texts.size() else ""


# --- What the home port does for a voyage --------------------------------------

static func treasure_factor() -> float:
	return 1.0 + TREASURE_PER_LEVEL * level("cartographer")


static func start_hull() -> int:
	return HULL_PER_LEVEL * level("carpenter")


static func start_max_hands() -> int:
	return HANDS_PER_LEVEL * level("old_captain")


static func start_crew_share() -> float:
	return CREW_PER_LEVEL * level("old_captain")


## A new specialist: a random name, the given role (or any), and a level that
## depends on how good a name your tavern has.
static func new_specialist(role := "") -> Dictionary:
	if role == "" or role == "random":
		role = str((Data.get_all("crew").pick_random() as Dictionary)["id"])
	var names: Array = Data.get_item("names", "crew_names").get("values", ["Sailor"])
	var odds: Array = SPECIALIST_ODDS[clampi(level("tavern"), 0, SPECIALIST_ODDS.size() - 1)]
	var roll := randf()
	var lvl := 3 if roll < float(odds[1]) else (2 if roll < float(odds[1]) + float(odds[0]) else 1)
	return {"name": str(names.pick_random()), "role": role, "level": lvl, "health": 100}


## "seasoned bosun", "veteran master gunner", or just "carpenter".
static func specialist_title(member: Dictionary) -> String:
	var role := str(Data.get_item("crew", str(member.get("role", ""))).get("name", "specialist")).to_lower()
	return str(RANKS[clampi(int(member.get("level", 1)), 1, RANKS.size() - 1)]) + role


## Extra gold a better specialist asks for.
static func hire_extra(member: Dictionary) -> int:
	return HIRE_PER_LEVEL * (int(member.get("level", 1)) - 1)


## How much stronger a specialist's buffs are at this level (1 at level 1).
static func buff_scale(lvl: int) -> float:
	return 1.0 + LEVEL_BONUS * (lvl - 1)


# --- Ships --------------------------------------------------------------------

static func ship_unlocked(ship: Dictionary) -> bool:
	var rule: Dictionary = ship.get("unlock", {"type": "always"})
	if str(rule.get("type", "always")) == "always":
		return true
	return SaveSystem.meta_int(str(rule.get("key", ""))) > 0


static func unlock_hint(ship: Dictionary) -> String:
	return str((ship.get("unlock", {}) as Dictionary).get("hint", ""))


## Sets a one-off flag (e.g. "reached_final_sea"). Returns the names of any
## ships this has just unlocked.
static func mark(key: String) -> Array[String]:
	var before: Array = []
	for s: Dictionary in Data.get_all("ships"):
		if ship_unlocked(s):
			before.append(s["id"])
	SaveSystem.add_meta(key, 1)
	SaveSystem.save_meta()
	var gained: Array[String] = []
	for s: Dictionary in Data.get_all("ships"):
		if ship_unlocked(s) and not before.has(s["id"]):
			gained.append(str(s.get("name", s["id"])))
	return gained


# --- Quests -------------------------------------------------------------------

static func quest_done(id: String) -> bool:
	return SaveSystem.meta_int("quest_" + id) > 0


static func start_quest(run: RunState, id: String) -> String:
	if not Data.has_item("quests", id) or quest_done(id):
		return ""
	run.quests[id] = "active"
	return "Quest: %s" % Data.get_item("quests", id).get("goal_text", id)


## Something happened that a quest might be waiting for, e.g.
## { "type": "capture", "faction": "company" }. Completes any active quest
## whose goal it matches and returns what to tell the player.
static func check_quests(run: RunState, happened: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for id: Variant in run.quests.keys():
		if str(run.quests[id]) != "active" or not Data.has_item("quests", str(id)):
			continue
		var quest := Data.get_item("quests", str(id))
		var goal: Dictionary = quest.get("goal", {})
		var met := true
		for k: String in goal:
			if str(happened.get(k, "")) != str(goal[k]):
				met = false
		if not met:
			continue
		run.quests[id] = "done"
		mark("quest_" + str(id))
		lines.append(str(quest.get("done_text", "Quest complete.")))
	return lines


## The goals of the quests we're on, for the map screen.
static func active_quests(run: RunState) -> Array[String]:
	var goals: Array[String] = []
	for id: Variant in run.quests:
		if str(run.quests[id]) == "active" and Data.has_item("quests", str(id)):
			goals.append(str(Data.get_item("quests", str(id)).get("goal_text", id)))
	return goals
