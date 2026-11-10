extends ScreenBase
## The port at the middle of each sea. Who owns it (a faction, set on the map
## node) decides what's on offer; see "port" in data/factions:
##   trade        repairs, a surgeon, supplies, hands and hiring, at the
##                owner's prices
##   shore leave, paying off crew, lying low   pirate havens only
##   tavern       a drink for the crew, in towns that will serve you
##   ransom       lawful ports buy prisoners
##   attack       fight the harbour fort (the owner sets how strong it is and
##                what it costs you). Win, and you come back here with the town
##                at your mercy (run.port_taken):
##     forced labour  a free full refit and a free surgeon
##     who's left     supplies and hiring at half price, townsfolk pressed into the crew
##     loot           gold, rum and shot, but the market is stripped and the hunt grows
## Arriving with low morale, some hands desert (or, in a haven, stay ashore).
## The owner's opinion of you (Reputation) scales prices, adds a hire when
## they're friendly, and if they hate you they won't trade at all.

const REFIT_HULL_COST := 2  # gold per point of hull, before the owner's prices
const REFIT_SAILS_COST := 1  # gold per point of sail
const SURGEON_COST := 15  # tend every wounded specialist
const SURGEON_HEAL := 50
const CHAIN_SHOT_AMOUNT := 5
const CHAIN_SHOT_COST := 8
const HEATED_AMOUNT := 5
const HEATED_COST := 12
const RECRUIT_AMOUNT := 10
const RECRUIT_COST := 12
const HIRE_COST := 35
const RUM_AMOUNT := 5
const RUM_COST := 8
const DRINK_COST := 15
const SHORE_LEAVE_COST := 20
const SHORE_LEAVE_MORALE := 20
const STAY_ASHORE_MORALE := 55  # in a haven, below this some hands stay ashore
const LIE_LOW_HUNT := -20
const LIE_LOW_RUM := 3
const RANSOM_EACH := 2  # keep in step with PRISONER_RANSOM in battle_screen.gd
const TAKEN_PRICES := 0.5  # what's left of a beaten town sells cheap
const PRESS_HANDS := 10  # townsfolk forced into the crew
const LOOT_HUNT := 10  # on top of the raid itself
const LOOT_MORALE := 5

var _owner := "company"
var _port: Dictionary = {}  # the owner's port rules
var _name := ""
var _arrived := false
var _left_ship := 0
var _offers: Array = []
var _used := {}  # one-off services already taken this visit
var _taken := false  # we beat the fort: the town is ours
var _note := ""  # what just happened ashore


func _title() -> String:
	_read_port()
	if _taken:
		return "%s (taken)" % _name
	return "%s (%s)" % [_name, _port.get("kind", "port")]


## Who owns this port, from the map node we're on (older maps: by node type).
func _read_port() -> void:
	if _name != "":
		return
	var run: RunState = GameState.run
	var here := int(run.map.get("current", -1))
	var node: Dictionary = run.map["nodes"][here] if here >= 0 else {}
	_owner = str(node.get("owner", "brotherhood" if node.get("type", "") == "haven" else "company"))
	_port = Data.get_item("factions", _owner).get("port", {})
	_name = str(node.get("name", "the harbour"))
	_taken = run.port_taken


func _build() -> void:
	var run: RunState = GameState.run
	if not _arrived:
		_arrived = true
		_arrive(run)
	if _taken:
		_add_occupied(run)
	elif bool(_port.get("trade", false)) and Reputation.will_trade(run, _owner):
		_add_trade(run)
	elif bool(_port.get("trade", false)):
		add_button("They know your name here. Nobody will trade with you.", func() -> void: pass, false)
	else:
		add_button("They won't trade with pirates. Only the guns will do here.", func() -> void: pass, false)
	if not _taken:
		add_button(str(_port.get("attack_text", "Attack the fort")), _attack)
	add_button("Sail on", GameState.finish_node)


## The fort has fallen. The town's people work for us now, or we take everything.
func _add_occupied(run: RunState) -> void:
	if (run.hull < run.max_hull or run.sails < run.max_sails) and not _used.has("refit"):
		add_button("Put the shipwrights to work: full refit (free)", _forced_refit)
	if _wounded(run) > 0 and not _used.has("surgeon"):
		add_button("Make the town surgeon tend %d wounded (free)" % _wounded(run), _forced_surgeon)
	if not _used.has("press") and run.hands < run.max_hands:
		add_button("Press %d townsfolk into the crew (free, %d morale)" % [PRESS_HANDS, Morale.PRESSED_PRISONERS], _press)
	if _used.has("loot"):
		add_button("The town has been stripped bare. Nothing left to buy.", func() -> void: pass, false)
		return
	add_button("Loot the town: %s (hunt +%d, ends trade)" % [_loot_preview(run), LOOT_HUNT], _loot)
	add_button("Buy %d rum (%d gold)" % [RUM_AMOUNT, _price(RUM_COST)], _buy.bind("rum", RUM_AMOUNT, RUM_COST))
	add_button("Buy %d chain shot (%d gold)" % [CHAIN_SHOT_AMOUNT, _price(CHAIN_SHOT_COST)], _buy.bind("chain_shot", CHAIN_SHOT_AMOUNT, CHAIN_SHOT_COST))
	add_button("Buy %d heated shot (%d gold)" % [HEATED_AMOUNT, _price(HEATED_COST)], _buy.bind("heated_shot", HEATED_AMOUNT, HEATED_COST))
	for i in _offers.size():
		var o: Dictionary = _offers[i]
		add_button("Hire %s, %s (%d gold)" % [o["name"], _role_name(o), _price(HIRE_COST)], _hire.bind(i))


func _add_trade(run: RunState) -> void:
	var missing_hull := run.max_hull - run.hull
	var missing_sails := run.max_sails - run.sails
	if missing_hull > 0 or missing_sails > 0:
		add_button("Full refit: hull and sails (%d gold)" % _refit_cost(run), _refit)
	if _wounded(run) > 0 and not _used.has("surgeon"):
		add_button("Surgeon tends %d wounded (%d gold)" % [_wounded(run), _price(SURGEON_COST)], _surgeon)
	if bool(_port.get("shore_leave", false)) and not _used.has("leave"):
		add_button("Shore leave for all hands (%d gold, +%d morale)" % [_price(SHORE_LEAVE_COST), SHORE_LEAVE_MORALE], _shore_leave)
	if bool(_port.get("tavern", false)) and not _used.has("drink"):
		add_button("Stand the crew a drink (%d gold, +%d morale)" % [_price(DRINK_COST), Morale.DRINK], _stand_drink)
	if bool(_port.get("lie_low", false)) and not _used.has("lie_low"):
		add_button("Lie low a few days (Company hunt %d, %d rum)" % [LIE_LOW_HUNT, LIE_LOW_RUM], _lie_low)
	add_button("Buy %d rum (%d gold)" % [RUM_AMOUNT, _price(RUM_COST)], _buy.bind("rum", RUM_AMOUNT, RUM_COST))
	add_button("Buy %d chain shot (%d gold)" % [CHAIN_SHOT_AMOUNT, _price(CHAIN_SHOT_COST)], _buy.bind("chain_shot", CHAIN_SHOT_AMOUNT, CHAIN_SHOT_COST))
	add_button("Buy %d heated shot (%d gold)" % [HEATED_AMOUNT, _price(HEATED_COST)], _buy.bind("heated_shot", HEATED_AMOUNT, HEATED_COST))
	add_button("Sign on %d hands (%d gold)" % [RECRUIT_AMOUNT, _price(RECRUIT_COST)], _buy.bind("hands", RECRUIT_AMOUNT, RECRUIT_COST))
	for i in _offers.size():
		var o: Dictionary = _offers[i]
		add_button("Hire %s, %s (%d gold)" % [o["name"], _role_name(o), _price(HIRE_COST)], _hire.bind(i))
	if bool(_port.get("pay_off", false)):
		for m: Dictionary in run.crew:
			add_button("Pay off %s, %s" % [m.get("name", "?"), _role_name(m)], _pay_off.bind(m))
	if bool(_port.get("ransom", false)) and run.prisoners > 0:
		add_button("Ransom %d prisoners (%d gold)" % [run.prisoners, run.prisoners * RANSOM_EACH], _ransom)


func refresh() -> void:
	var run: RunState = GameState.run
	var lines: Array[String] = []
	var prices := float(_port.get("prices", 1.0)) * Reputation.price_factor(run, _owner)
	lines.append("Standing with %s: %s (%+d)." % [Data.get_item("factions", _owner).get("short_name", _owner), Reputation.tier(Reputation.of(run, _owner)), Reputation.of(run, _owner)])
	if _taken:
		lines.append("The fort is ours and %s lies at our mercy. What's left of the town sells at half price, or we take the lot." % _name)
	elif bool(_port.get("trade", false)) and Reputation.will_trade(run, _owner):
		lines.append("Prices here: %s (x%.2f)." % ["cheap, among friends" if prices < 1.0 else ("steep for the likes of you" if prices > 1.0 else "fair"), prices])
	if _left_ship > 0:
		var where := "stayed ashore" if bool(_port.get("stay_ashore", false)) else "deserted"
		lines.append("%d hands %s when we made port." % [_left_ship, where])
	if _note != "":
		lines.append(_note)
	lines.append(run_summary())
	var slots := int(Data.get_item("ships", run.ship_id).get("specialist_slots", 8))
	lines.append("Specialists %d of %d berths. Prisoners %d." % [run.crew.size(), slots, run.prisoners])
	_info.text = "\n".join(lines)


func _arrive(run: RunState) -> void:
	if _taken:
		pass  # fresh from a victory: nobody's leaving now
	elif bool(_port.get("stay_ashore", false)):
		if run.morale < STAY_ASHORE_MORALE:
			_left_ship = roundi(run.hands * float(STAY_ASHORE_MORALE - run.morale) / 100.0)
	else:
		_left_ship = roundi(run.hands * Morale.desertion_share(run.morale))
	run.hands = maxi(1, run.hands - _left_ship)
	var names: Array = Data.get_item("names", "crew_names").get("values", ["Sailor"])
	var roles: Array = Data.get_all("crew")
	var hires := int(_port.get("hire_offers", 0))
	if _taken:
		hires = maxi(1, hires)  # someone in a beaten town will sign on
	elif Reputation.of(run, _owner) >= Reputation.FRIENDLY and Reputation.will_trade(run, _owner):
		hires += 1  # friends put the word out for you
	for i in hires:
		var role: Dictionary = roles.pick_random()
		_offers.append({"name": str(names.pick_random()), "role": str(role["id"]), "level": 1, "health": 100})


func _rebuild() -> void:
	for b in _buttons.get_children():
		b.queue_free()
	_build()
	refresh()


func _price(base: int) -> int:
	var prices := TAKEN_PRICES if _taken else float(_port.get("prices", 1.0)) * Reputation.price_factor(GameState.run, _owner)
	return maxi(1, roundi(base * prices))


func _pay(base: int) -> bool:
	var run: RunState = GameState.run
	var cost := _price(base)
	if run.gold < cost:
		return false
	run.gold -= cost
	return true


func _role_name(m: Dictionary) -> String:
	return str(Data.get_item("crew", str(m.get("role", ""))).get("name", "specialist")).to_lower()


func _wounded(run: RunState) -> int:
	return run.crew.filter(func(m: Dictionary) -> bool: return int(m.get("health", 100)) < 100).size()


func _refit_cost(run: RunState) -> int:
	return _price((run.max_hull - run.hull) * REFIT_HULL_COST + (run.max_sails - run.sails) * REFIT_SAILS_COST)


# --- Services -------------------------------------------------------------

func _refit() -> void:
	var run: RunState = GameState.run
	var cost := _refit_cost(run)
	if run.gold < cost:
		return
	run.gold -= cost
	run.hull = run.max_hull
	run.sails = run.max_sails
	_rebuild()


func _surgeon() -> void:
	if _pay(SURGEON_COST):
		for m: Dictionary in GameState.run.crew:
			m["health"] = mini(100, int(m.get("health", 100)) + SURGEON_HEAL)
		_used["surgeon"] = true
		_rebuild()


func _shore_leave() -> void:
	if _pay(SHORE_LEAVE_COST):
		Morale.change(GameState.run, SHORE_LEAVE_MORALE)
		_used["leave"] = true
		_rebuild()


func _stand_drink() -> void:
	if _pay(DRINK_COST):
		Morale.change(GameState.run, Morale.DRINK)
		_used["drink"] = true
		_rebuild()


func _lie_low() -> void:
	var run: RunState = GameState.run
	if run.rum < LIE_LOW_RUM:
		return
	run.rum -= LIE_LOW_RUM
	run.days += LIE_LOW_RUM
	Voyage.change_hunt(run, LIE_LOW_HUNT)
	_used["lie_low"] = true
	_rebuild()


## Buys supplies: "rum", "hands", or an ammo id.
func _buy(what: String, amount: int, base_cost: int) -> void:
	var run: RunState = GameState.run
	if what == "hands" and run.hands >= run.max_hands:
		return
	if not _pay(base_cost):
		return
	match what:
		"rum":
			run.rum += amount
		"hands":
			run.hands = mini(run.max_hands, run.hands + amount)
		_:
			run.ammo[what] = int(run.ammo.get(what, 0)) + amount
	refresh()


func _hire(index: int) -> void:
	var run: RunState = GameState.run
	var slots := int(Data.get_item("ships", run.ship_id).get("specialist_slots", 8))
	if run.crew.size() >= slots or index >= _offers.size() or not _pay(HIRE_COST):
		return
	run.crew.append(_offers[index])
	_offers.remove_at(index)
	_rebuild()


func _pay_off(member: Dictionary) -> void:
	GameState.run.crew.erase(member)
	_rebuild()


func _ransom() -> void:
	var run: RunState = GameState.run
	run.gold += run.prisoners * RANSOM_EACH
	run.prisoners = 0
	_rebuild()


# --- A taken town ----------------------------------------------------------

func _forced_refit() -> void:
	var run: RunState = GameState.run
	run.hull = run.max_hull
	run.sails = run.max_sails
	_used["refit"] = true
	_note = "The town's shipwrights work through the night. She's as good as new."
	_rebuild()


func _forced_surgeon() -> void:
	for m: Dictionary in GameState.run.crew:
		m["health"] = 100
	_used["surgeon"] = true
	_note = "The town surgeon patches up every wounded man aboard."
	_rebuild()


func _press() -> void:
	var run: RunState = GameState.run
	var joined := mini(PRESS_HANDS, run.max_hands - run.hands)
	run.hands += joined
	Morale.change(run, Morale.PRESSED_PRISONERS)
	_used["press"] = true
	_note = "%d townsfolk are dragged aboard. The crew don't like it." % joined
	_rebuild()


## What looting would bring: the fort's plunder, by owner and how far we've come.
func _loot_effects(run: RunState) -> Dictionary:
	var plunder: Dictionary = Data.get_item("enemies", "shore_fort").get("plunder", {}).duplicate(true)
	var mult := float(_port.get("plunder", 1.0)) * (1.0 + Voyage.SEA_GOLD * (run.sea_number - 1))
	plunder["gold"] = roundi(int(plunder.get("gold", 0)) * mult)
	return plunder


func _loot_preview(run: RunState) -> String:
	var p := _loot_effects(run)
	return "%d gold, %d rum, shot" % [int(p.get("gold", 0)), int(p.get("rum", 0))]


func _loot() -> void:
	var run: RunState = GameState.run
	var taken := Events.apply(run, _loot_effects(run))
	Voyage.change_hunt(run, LOOT_HUNT)
	Morale.change(run, LOOT_MORALE)
	var rep := Reputation.change(run, _owner, Reputation.PORT_LOOTED)
	_used["loot"] = true
	_offers.clear()
	_note = "The town is sacked: " + ", ".join(taken) + ". The crew roar. Word will spread%s." % ((" (%s)" % rep) if rep != "" else "")
	_rebuild()


func _attack() -> void:
	var run: RunState = GameState.run
	Reputation.change(run, _owner, Reputation.PORT_TREACHERY)
	run.forced_enemy = "shore_fort"
	run.port_owner = _owner
	GameState.change_screen(GameState.Screen.BATTLE)
