extends ScreenBase
## An outpost: a small place to trade somewhere out in a sea, like an FTL
## store. Unlike the port it belongs to no faction, can't be attacked, and
## only has a few things on its shelves.
##
## What kind of outpost it is (data/outposts) decides what it "always" sells
## and what it "sometimes" does. The stock is rolled the first time you call
## and kept on the map node, so it's the same if you sail back.
##
## Goods (see GOODS): rum, shot and hands come in limited lots; hull and sail
## repairs are by the patch, as often as you can pay; the surgeon, a ship
## upgrade and a relic are one each.
##
## On top of that, each outpost rolls separately for two extras:
##   specialists for hire   "hire_chance": one or two looking for a berth
##   ship augments          "augment_chance": a stall that fits augments.
##                          Augments aren't built yet, so its shelves are
##                          empty (stock["augments"] is the list to fill).

const GOODS := {
	"rum": {"label": "Buy 5 rum", "cost": 8, "lots": 3},
	"chain_shot": {"label": "Buy 5 chain shot", "cost": 8, "lots": 2},
	"grape_shot": {"label": "Buy 5 grape shot", "cost": 8, "lots": 2},
	"heated_shot": {"label": "Buy 5 heated shot", "cost": 12, "lots": 2},
	"hands": {"label": "Sign on 10 hands", "cost": 12, "lots": 2},
	"hull": {"label": "Patch the hull: +5 hull", "cost": 12, "lots": -1},
	"sails": {"label": "New canvas: +5 sails", "cost": 6, "lots": -1},
	"surgeon": {"label": "A healer tends the wounded: +50 health", "cost": 15, "lots": 1},
	"upgrade": {"lots": 1},
	"relic": {"cost": 60, "lots": 1},
}
const LOT := 5  # rum, shot, hull and sails per purchase
const HANDS_LOT := 10
const HEAL := 50
const HIRE_COST := 35
const MAX_HIRES := 2

var _node: Dictionary = {}
var _kind: Dictionary = {}
var _note := ""


func _title() -> String:
	_read()
	return str(_node.get("name", _kind.get("name", "Outpost")))


func _read() -> void:
	if not _kind.is_empty():
		return
	var run: RunState = GameState.run
	var here := int(run.map.get("current", -1))
	_node = run.map["nodes"][here] if here >= 0 else {}
	var kind_id := str(_node.get("kind", "trading_hulk"))
	_kind = Data.get_item("outposts", kind_id if Data.has_item("outposts", kind_id) else "trading_hulk")
	if not _node.has("stock"):
		_node["stock"] = _roll_stock(run)


## What's on the shelves: { good id: lots left (-1 = no limit) }, plus who's
## for hire and which upgrade and relic, if any.
func _roll_stock(run: RunState) -> Dictionary:
	var goods: Array = (_kind.get("always", []) as Array).duplicate()
	var maybe: Array = (_kind.get("sometimes", []) as Array).duplicate()
	maybe.shuffle()
	for i in mini(int(_kind.get("extras", 2)), maybe.size()):
		goods.append(maybe[i])
	var stock := {}
	for g: Variant in goods:
		var id := str(g)
		match id:
			"upgrade":
				var ups := Perks.upgrade_offers(run, 1)
				if ups.is_empty():
					continue
				stock["upgrade_id"] = str(ups[0]["id"])
			"relic":
				var relics := Perks.relic_offers(run, 1)
				if relics.is_empty():
					continue
				stock["relic_id"] = str(relics[0]["id"])
		if GOODS.has(id):
			stock[id] = int(GOODS[id]["lots"])
	# Rolled separately from the shelves: who's looking for a berth, and an augment stall.
	if randf() < float(_kind.get("hire_chance", 0.0)):
		var hires: Array = []
		for i in randi_range(1, MAX_HIRES):
			hires.append(Hub.new_specialist())
		stock["hires"] = hires
	if randf() < float(_kind.get("augment_chance", 0.0)):
		stock["augments"] = []  # to be filled once augments exist
	return stock


func _build() -> void:
	var run: RunState = GameState.run
	var stock: Dictionary = _node.get("stock", {})
	for id: String in GOODS:
		if not stock.has(id) or int(stock[id]) == 0:
			continue
		var label := _label(run, id, stock)
		if label == "":
			continue
		var lots := int(stock[id])
		var left := "" if lots < 0 or int(GOODS[id]["lots"]) == 1 else ", %d left" % lots
		add_button("%s (%d gold%s)" % [label, _cost(run, id, stock), left], _buy.bind(id))
	var hires: Array = stock.get("hires", [])
	for i in hires.size():
		var who: Dictionary = hires[i]
		add_button("Hire %s, %s (%d gold)" % [who.get("name", "?"), Hub.specialist_title(who), _price(run, HIRE_COST + Hub.hire_extra(who))], _hire.bind(i))
	if stock.has("augments"):
		add_button("Ship augments: the stall is here, but its shelves are bare for now", func() -> void: pass, false)
	add_button("Sail on", GameState.finish_node)


## The button text for a good, or "" if there's no point offering it now.
func _label(run: RunState, id: String, stock: Dictionary) -> String:
	match id:
		"hull":
			return str(GOODS[id]["label"]) if run.hull < run.max_hull else ""
		"sails":
			return str(GOODS[id]["label"]) if run.sails < run.max_sails else ""
		"surgeon":
			return str(GOODS[id]["label"]) if run.crew.any(func(m: Dictionary) -> bool: return int(m.get("health", 100)) < 100) else ""
		"upgrade":
			var u := Data.get_item("upgrades", str(stock.get("upgrade_id", "")))
			return "Fit %s. %s" % [str(u.get("name", "an upgrade")).to_lower(), u.get("description", "")] if Perks.can_upgrade(run, str(u.get("id", ""))) else ""
		"relic":
			var r := Data.get_item("relics", str(stock.get("relic_id", "")))
			return "Relic: %s. %s" % [r.get("name", "?"), r.get("description", "")] if not Perks.has_relic(run, str(r.get("id", ""))) else ""
	return str(GOODS[id]["label"])


func _cost(run: RunState, id: String, stock: Dictionary) -> int:
	var base := int(GOODS[id].get("cost", 0))
	if id == "upgrade":
		base = Perks.upgrade_cost(run, str(stock.get("upgrade_id", "")))
	return _price(run, base)


func _price(run: RunState, base: int) -> int:
	return maxi(1, roundi(base * float(_kind.get("prices", 1.0)) * Perks.mult(run, "price")))


func refresh() -> void:
	var lines: Array[String] = [str(_kind.get("text", ""))]
	if _note != "":
		lines.append(_note)
	lines.append("")
	lines.append(run_summary())
	_info.text = "\n".join(lines)


func _buy(id: String) -> void:
	var run: RunState = GameState.run
	var stock: Dictionary = _node["stock"]
	var cost := _cost(run, id, stock)
	if run.gold < cost:
		_note = "Not enough gold for that."
	elif id == "hands" and run.hands >= run.max_hands:
		_note = "No room for more hands."
	else:
		run.gold -= cost
		match id:
			"rum":
				run.rum += LOT
			"hands":
				run.hands = mini(run.max_hands, run.hands + HANDS_LOT)
			"hull":
				run.hull = mini(run.max_hull, run.hull + LOT)
			"sails":
				run.sails = mini(run.max_sails, run.sails + LOT)
			"surgeon":
				for m: Dictionary in run.crew:
					m["health"] = mini(100, int(m.get("health", 100)) + HEAL)
			"upgrade":
				Perks.buy_upgrade(run, str(stock["upgrade_id"]))
			"relic":
				Perks.give_relic(run, str(stock["relic_id"]))
			_:
				run.ammo[id] = int(run.ammo.get(id, 0)) + LOT
		if int(stock[id]) > 0:
			stock[id] = int(stock[id]) - 1
		_note = "Done, and paid for."
	_rebuild()


func _hire(index: int) -> void:
	var run: RunState = GameState.run
	var hires: Array = _node["stock"].get("hires", [])
	var cost := _price(run, HIRE_COST + (Hub.hire_extra(hires[index]) if index < hires.size() else 0))
	var slots := int(Data.get_item("ships", run.ship_id).get("specialist_slots", 8))
	if index >= hires.size():
		return
	if run.gold < cost:
		_note = "Not enough gold for that."
	elif run.crew.size() >= slots:
		_note = "No berth free for another specialist."
	else:
		run.gold -= cost
		var who: Dictionary = hires.pop_at(index)
		run.crew.append(who)
		_note = "%s signs the articles." % who.get("name", "A new hand")
	_rebuild()


func _rebuild() -> void:
	for b in _buttons.get_children():
		b.queue_free()
	_build()
	refresh()
