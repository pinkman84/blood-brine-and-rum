class_name DamageControl
extends RefCounted
## Room damage, fire and flooding, and the crew work that deals with them.
##
## Each ship keeps a state per room (BattleShip.rooms). The hands deal with
## trouble automatically, in this order per room: fight the fire, plug the
## leak, repair damage. Their effort is shared between every room that needs
## it and scales with the share of hands left. A specialist with a "work" buff
## (the carpenter) doubles the work in the room they stand in.

const ROOM_HP := 3
const FIRE_CHANCE := 0.12
const MAGAZINE_FIRE_CHANCE := 0.35
const LEAK_CHANCE := 0.15
const LEAK_ROOMS: Array[String] = ["guns", "magazine", "sickbay", "hold"]  # lower deck

const FIRE_START := 40.0  # fire runs 0 (out) to 100 (blaze)
const FIRE_GROWTH := 4.0  # per second
const FIRE_FIGHTING := 6.0  # fire put out per unit of work
const FIRE_SPREAD := 0.03  # chance per second to reach each neighbour, at full blaze
const BURN_INTERVAL := 6.0  # seconds per point of room and hull damage from a fire

const FLOOD_RATE := 0.04  # per second while leaking (0 to 1)
const DRAIN_RATE := 0.05  # per second once plugged
const FLOOD_INTERVAL := 8.0  # seconds per hull point lost from a fully flooded room

const FIRE_WOUND := 6.0  # health per second for a specialist in a full blaze
const FLOOD_WOUND := 3.0  # health per second in a fully flooded room
const HEAL_RATE := 2.0  # health per second in the sickbay, before buffs
const HIT_WOUND := 10.0  # base wound when a shot lands in a specialist's room
const HIT_WOUND_PER_CREW_DAMAGE := 6.0  # plus this per point of the ammo's crew_damage

const DC_CAPACITY := 3.0  # work per second at full hands, shared between rooms in trouble
const PLUG_WORK := 6.0  # work to plug a leak
const REPAIR_WORK := 6.0  # work per point of room damage


static func new_room() -> Dictionary:
	return {"damage": 0, "fire": 0.0, "leak": false, "plug": 0.0, "flood": 0.0,
		"repair": 0.0, "burn_t": 0.0, "flood_t": 0.0}


## How well a room works right now, 0 to 1.
static func efficiency(state: Dictionary) -> float:
	var e := 1.0 - float(state["damage"]) / ROOM_HP
	e *= 1.0 - 0.6 * float(state["flood"])
	if float(state["fire"]) > 0.0:
		e *= 0.5
	return clampf(e, 0.0, 1.0)


## A shot has landed in `room` (a ShipView room). Light shot (grape, chain)
## only hurts people and rigging; it doesn't wreck rooms or hole the hull.
static func on_hit(ship: BattleShip, room: Dictionary, ammo_id: String) -> void:
	if int(Data.get_item("ammo", ammo_id).get("hull_damage", 0)) < 2:
		return
	var state: Dictionary = ship.rooms[room["id"]]
	state["damage"] = mini(ROOM_HP, int(state["damage"]) + 1)
	var fire_chance := MAGAZINE_FIRE_CHANCE if room["type"] == "magazine" else FIRE_CHANCE
	fire_chance += float(Data.get_item("ammo", ammo_id).get("fire_chance", 0.0))
	if randf() < fire_chance:
		ignite(state)
	if LEAK_ROOMS.has(room["type"]) and randf() < LEAK_CHANCE:
		state["leak"] = true
		state["plug"] = 0.0


static func ignite(state: Dictionary) -> void:
	if float(state["fire"]) <= 0.0:
		state["fire"] = FIRE_START
		state["burn_t"] = 0.0


## Advances fires, flooding and crew work on one ship.
static func tick(ship: BattleShip, view: ShipView, crew: Array, delta: float) -> void:
	var in_trouble := 0
	for id: String in ship.rooms:
		if job(ship.rooms[id]) != "":
			in_trouble += 1
	var share := DC_CAPACITY * ship.hands_ratio() / maxf(1.0, in_trouble)
	var boost := {}  # room id -> work multiplier from specialists standing there
	for c: BattleCrew in crew:
		if c.alive and not c.is_moving():
			boost[c.room_id] = float(boost.get(c.room_id, 1.0)) * c.buff("work")

	for room in view.rooms:
		var id: String = room["id"]
		var s: Dictionary = ship.rooms[id]
		var work := share * float(boost.get(id, 1.0))

		if float(s["fire"]) > 0.0:
			s["fire"] = minf(100.0, float(s["fire"]) + FIRE_GROWTH * delta) - work * FIRE_FIGHTING * delta
			if float(s["fire"]) <= 0.0:
				s["fire"] = 0.0
			else:
				s["burn_t"] = float(s["burn_t"]) + delta
				if float(s["burn_t"]) >= BURN_INTERVAL:
					s["burn_t"] = 0.0
					s["damage"] = mini(ROOM_HP, int(s["damage"]) + 1)
					ship.hull = maxi(0, ship.hull - 1)
					ship.lose_hands(1)
				var spread := FIRE_SPREAD * float(s["fire"]) / 100.0 * delta
				for neighbour in view.neighbours(id):
					if randf() < spread:
						ignite(ship.rooms[neighbour["id"]])
			work = 0.0  # everyone here is busy with the fire

		if s["leak"]:
			s["flood"] = minf(1.0, float(s["flood"]) + FLOOD_RATE * delta)
			s["plug"] = float(s["plug"]) + work * delta
			if float(s["plug"]) >= PLUG_WORK:
				s["leak"] = false
				s["plug"] = 0.0
			work = 0.0
		elif float(s["flood"]) > 0.0:
			s["flood"] = maxf(0.0, float(s["flood"]) - DRAIN_RATE * delta)

		if float(s["flood"]) >= 1.0:
			s["flood_t"] = float(s["flood_t"]) + delta
			if float(s["flood_t"]) >= FLOOD_INTERVAL:
				s["flood_t"] = 0.0
				ship.hull = maxi(0, ship.hull - 1)
				ship.lose_hands(1)

		if work > 0.0 and int(s["damage"]) > 0:
			s["repair"] = float(s["repair"]) + work * delta
			if float(s["repair"]) >= REPAIR_WORK:
				s["repair"] = 0.0
				s["damage"] = int(s["damage"]) - 1


## Specialists standing in fire or water get hurt; those in the sickbay heal,
## faster with a surgeon there and slower if the sickbay is damaged.
static func tick_crew(ship: BattleShip, view: ShipView, crew: Array, delta: float) -> void:
	var heal_boost := {}  # room id -> healing multiplier
	for c: BattleCrew in crew:
		if c.alive and not c.is_moving():
			heal_boost[c.room_id] = float(heal_boost.get(c.room_id, 1.0)) * c.buff("heal")
	for c: BattleCrew in crew:
		if not c.alive or c.is_moving() or not ship.rooms.has(c.room_id):
			continue
		var s: Dictionary = ship.rooms[c.room_id]
		var hurt := FIRE_WOUND * float(s["fire"]) / 100.0
		if float(s["flood"]) >= 0.5:
			hurt += FLOOD_WOUND * float(s["flood"])
		c.hurt(hurt * delta)
		if view.room_by_id(c.room_id).get("type", "") == "sickbay":
			c.heal(HEAL_RATE * float(heal_boost.get(c.room_id, 1.0)) * efficiency(s) * delta)


## A shot of this ammo landed in a room: wound every specialist standing there.
static func wound_room(crew: Array, room_id: String, ammo_id: String) -> void:
	var amount := HIT_WOUND + HIT_WOUND_PER_CREW_DAMAGE * float(Data.get_item("ammo", ammo_id).get("crew_damage", 0))
	for c: BattleCrew in crew:
		if c.alive and c.room_id == room_id and not c.is_moving():
			c.hurt(amount * randf_range(0.7, 1.3))


## What a crew member standing in this room is busy with, or "".
static func job(state: Dictionary) -> String:
	if float(state["fire"]) > 0.0:
		return "fighting fire"
	if state["leak"]:
		return "plugging leak"
	if int(state["damage"]) > 0:
		return "repairing"
	return ""


## Short alert text for a ship's status line, e.g. "2 fires, 1 leak".
static func alerts(ship: BattleShip) -> String:
	var fires := 0
	var leaks := 0
	for id: String in ship.rooms:
		var s: Dictionary = ship.rooms[id]
		if float(s["fire"]) > 0.0:
			fires += 1
		if s["leak"]:
			leaks += 1
	var parts: Array[String] = []
	if fires > 0:
		parts.append("%d fire%s" % [fires, "" if fires == 1 else "s"])
	if leaks > 0:
		parts.append("%d leak%s" % [leaks, "" if leaks == 1 else "s"])
	return ", ".join(parts)
