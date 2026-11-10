class_name Events
extends RefCounted
## The event system: picking an event, checking a choice's requirements, and
## applying an outcome's effects to the run. Events live in data/events.
##
## Event:   { id, title, text, weight?, seas?: [ids], min_sea?, max_sea?, pool?, unless_meta?, choices: [...] }
##   unless_meta: a meta key (see Hub); once it's set the event never comes up again
##   pool: which kind of node draws it. None for "?" event nodes; "storm" and
##   "treasure" for those nodes; "mutiny" is only ever forced (GameState).
## Choice:  { text, requires?: {...}, outcomes: [ { chance?, text, effects: {...} } ] }
##
## requires (all must hold):
##   gold, hands, rum, morale_min, morale_max: numbers
##   role: a specialist role id that must be aboard (e.g. "carpenter")
##   ammo: { ammo id: rounds }
##   prisoners: number
##   rep_min, rep_max: { faction id: value } (see Reputation)
##
## effects (all optional, numbers can be negative):
##   gold, hull, sails, hands, morale, rum, hunt, prisoners: numbers
##   ammo: { ammo id: rounds }
##   wound: health a random specialist loses (they can die)
##   join: a specialist role id, or "random", who joins if there's a free slot
##   battle: "random" (this sea's mix) or an enemy id; the node becomes a fight
##   rep: { faction id: change }
##   quest: a quest id to start (data/quests; see Hub)
##   days: time lost; each day drinks a rum ration and lets the Company hunt grow
##   end_run: true; the voyage is over (the event screen ends the run)

const DEFAULT_WEIGHT := 1.0


## A random event from this pool, fit for this sea, that hasn't happened yet
## this run. Storms and treasure can repeat once every one has been seen.
static func pick(run: RunState, pool := "") -> Dictionary:
	var candidates := _candidates(run, pool, false)
	if candidates.is_empty() and pool != "":
		candidates = _candidates(run, pool, true)
	if candidates.is_empty():
		return {}
	var total := 0.0
	for e: Dictionary in candidates:
		total += float(e.get("weight", DEFAULT_WEIGHT))
	var roll := randf() * total
	for e: Dictionary in candidates:
		roll -= float(e.get("weight", DEFAULT_WEIGHT))
		if roll <= 0.0:
			return e
	return candidates.back()


static func _candidates(run: RunState, pool: String, allow_seen: bool) -> Array:
	var found: Array = []
	for e: Dictionary in Data.get_all("events"):
		if str(e.get("pool", "")) == pool and _fits(run, e, allow_seen):
			found.append(e)
	return found


static func _fits(run: RunState, e: Dictionary, allow_seen: bool) -> bool:
	if run.seen_events.has(e["id"]) and not allow_seen:
		return false
	var seas: Array = e.get("seas", [])
	if not seas.is_empty() and not seas.has(run.sea_id):
		return false
	if run.sea_number < int(e.get("min_sea", 1)) or run.sea_number > int(e.get("max_sea", 99)):
		return false
	if e.has("unless_meta") and SaveSystem.meta_int(str(e["unless_meta"])) > 0:
		return false
	return true


## Returns "" if the run meets the requirements, otherwise why not
## (e.g. "needs a carpenter").
static func unmet(run: RunState, requires: Dictionary) -> String:
	if run.gold < int(requires.get("gold", 0)):
		return "needs %d gold" % int(requires["gold"])
	if run.hands < int(requires.get("hands", 0)):
		return "needs %d hands" % int(requires["hands"])
	if run.rum < int(requires.get("rum", 0)):
		return "needs %d rum" % int(requires["rum"])
	if run.prisoners < int(requires.get("prisoners", 0)):
		return "needs %d prisoners" % int(requires["prisoners"])
	if run.morale < int(requires.get("morale_min", 0)):
		return "the crew won't stand for it"
	if run.morale > int(requires.get("morale_max", 100)):
		return "the crew are too content for that"
	if requires.has("role"):
		var role := str(requires["role"])
		if not run.crew.any(func(c: Dictionary) -> bool: return c.get("role") == role):
			return "needs a %s" % str(Data.get_item("crew", role).get("name", role)).to_lower()
	var rep_min: Dictionary = requires.get("rep_min", {})
	for f: String in rep_min:
		if Reputation.of(run, f) < int(rep_min[f]):
			return "%s won't trust you" % Reputation.short_name(f)
	var rep_max: Dictionary = requires.get("rep_max", {})
	for f: String in rep_max:
		if Reputation.of(run, f) > int(rep_max[f]):
			return "%s think too well of you" % Reputation.short_name(f)
	var ammo: Dictionary = requires.get("ammo", {})
	for id: String in ammo:
		if int(run.ammo.get(id, 0)) < int(ammo[id]):
			return "needs %d %s" % [int(ammo[id]), str(Data.get_item("ammo", id).get("name", id)).to_lower()]
	return ""


## Picks one of a choice's outcomes, weighted by "chance" (default 1).
static func roll_outcome(outcomes: Array) -> Dictionary:
	if outcomes.is_empty():
		return {}
	var total := 0.0
	for o: Dictionary in outcomes:
		total += float(o.get("chance", 1.0))
	var pick := randf() * total
	for o: Dictionary in outcomes:
		pick -= float(o.get("chance", 1.0))
		if pick <= 0.0:
			return o
	return outcomes.back()


## Applies effects to the run. Returns short lines describing what changed,
## e.g. ["+15 gold", "-5 hull", "Finn the master gunner joins the crew"].
static func apply(run: RunState, effects: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var g := int(effects.get("gold", 0))
	if g != 0:
		var before := run.gold
		run.gold = maxi(0, run.gold + g)
		lines.append("%+d gold" % (run.gold - before))
	var h := int(effects.get("hull", 0))
	if h != 0:
		var before := run.hull
		run.hull = clampi(run.hull + h, 1, run.max_hull)  # events wound ships, they don't sink them
		lines.append("%+d hull" % (run.hull - before))
	var s := int(effects.get("sails", 0))
	if s != 0:
		var before := run.sails
		run.sails = clampi(run.sails + s, 0, run.max_sails)
		lines.append("%+d sails" % (run.sails - before))
	var hands := int(effects.get("hands", 0))
	if hands != 0:
		var before := run.hands
		run.hands = clampi(run.hands + hands, 1, run.max_hands)
		lines.append("%+d hands" % (run.hands - before))
	var m := int(effects.get("morale", 0))
	if m != 0:
		lines.append("%+d morale" % Morale.change(run, m))
	var r := int(effects.get("rum", 0))
	if r != 0:
		var before := run.rum
		run.rum = maxi(0, run.rum + r)
		lines.append("%+d rum" % (run.rum - before))
	var hunt := int(effects.get("hunt", 0))
	if hunt != 0:
		var before := run.hunt
		Voyage.change_hunt(run, hunt)
		lines.append("Company hunt %+d%%" % (run.hunt - before))
	var days := int(effects.get("days", 0))
	if days > 0:
		var rum_before := run.rum
		var hunt_before := run.hunt
		run.days += days
		run.rum = maxi(0, run.rum - days)
		Voyage.change_hunt(run, days * Voyage.HUNT_PER_DAY)
		lines.append("%d day%s lost (%+d rum, Company hunt %+d%%)" % [days, "" if days == 1 else "s", run.rum - rum_before, run.hunt - hunt_before])
	var p := int(effects.get("prisoners", 0))
	if p != 0:
		var before := run.prisoners
		run.prisoners = maxi(0, run.prisoners + p)
		lines.append("%+d prisoners" % (run.prisoners - before))
	var ammo: Dictionary = effects.get("ammo", {})
	for id: String in ammo:
		var have := int(run.ammo.get(id, 0))
		run.ammo[id] = maxi(0, have + int(ammo[id]))
		lines.append("%+d %s" % [int(run.ammo[id]) - have, str(Data.get_item("ammo", id).get("name", id)).to_lower()])
	lines.append_array(Reputation.apply(run, effects.get("rep", {})))
	if effects.has("quest"):
		lines.append(Hub.start_quest(run, str(effects["quest"])))
	if effects.has("wound"):
		lines.append(_wound(run, int(effects["wound"])))
	if effects.has("join"):
		lines.append(_join(run, str(effects["join"])))
	var kept: Array[String] = []
	for l in lines:
		if l != "":
			kept.append(l)
	return kept


static func _wound(run: RunState, amount: int) -> String:
	if run.crew.is_empty():
		return ""
	var victim: Dictionary = run.crew.pick_random()
	var role := str(Data.get_item("crew", str(victim.get("role", ""))).get("name", "specialist")).to_lower()
	var health := int(victim.get("health", 100)) - amount
	if health <= 0:
		run.crew.erase(victim)
		Morale.change(run, Morale.SPECIALIST_DIED)
		return "%s the %s is killed" % [victim.get("name", "?"), role]
	victim["health"] = health
	return "%s the %s is hurt (%d health left)" % [victim.get("name", "?"), role, health]


static func _join(run: RunState, role: String) -> String:
	var slots := int(Data.get_item("ships", run.ship_id).get("specialist_slots", 8))
	if run.crew.size() >= slots:
		return "No berth free for a new specialist"
	var member := Hub.new_specialist(role)
	run.crew.append(member)
	return "%s the %s joins the crew" % [member["name"], Hub.specialist_title(member)]
