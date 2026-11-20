extends ScreenBase
## After a victory: choose one thing to take from the beaten ship.
##
## Three offers. Usually stores (gold, shot, rum, timber, medicine, hands);
## an ordinary prize sometimes has a relic aboard (Perks.RELIC_CHANCE), and a
## sea's elite captain always offers a choice of relics. Now and then a ship
## augment is among the offers (Augments.BATTLE_CHANCE / ELITE_CHANCE); taking
## one when the ship is full asks which to throw over (ScreenBase.offer_augment).

const OFFERS := 3
const GOLD_BASE := 12
const GOLD_PER_SEA := 6
const ELITE_GOLD := 2.0  # if an elite's offers have to fall back to stores
const TIMBER_HULL := 10
const MEDICINE := 40
const VOLUNTEERS := 12

var _offers: Array = []  # each { text, detail, relic? or augment? or effects? }
var _taken := ""


func _title() -> String:
	return "The captain's cabin" if GameState.run.loot_pending == "elite" else "The plunder"


func _build() -> void:
	if _taken != "":
		add_button("Sail on", GameState.finish_node)
		return
	if _offers.is_empty():
		_roll(GameState.run)
	for i in _offers.size():
		add_button(str(_offers[i]["text"]), _take.bind(i))


func refresh() -> void:
	var lines: Array[String] = []
	if _taken != "":
		lines.append(_taken)
	else:
		lines.append("Her hold is ours, but there's only time and room for one thing. What do we take?")
		lines.append("")
		for o: Dictionary in _offers:
			if o.has("relic") or o.has("augment"):
				lines.append("%s: %s" % [o["name"], o["detail"]])
	lines.append("")
	lines.append(run_summary())
	_info.text = "\n".join(lines)


func _roll(run: RunState) -> void:
	var elite := run.loot_pending == "elite"
	if randf() < (Augments.ELITE_CHANCE if elite else Augments.BATTLE_CHANCE):
		var aug := Augments.roll(run)
		if aug != "":
			var a := Data.get_item("augments", aug)
			_offers.append({"augment": aug, "name": str(a["name"]), "detail": "(%s) %s" % [Augments.rarity(aug), a["description"]],
				"text": "Augment: %s (%s)" % [a["name"], Augments.rarity(aug)]})
	var relics := Perks.relic_offers(run, (OFFERS - _offers.size()) if elite else (1 if randf() < Perks.RELIC_CHANCE else 0))
	for r: Dictionary in relics:
		_offers.append({"relic": str(r["id"]), "name": str(r["name"]), "detail": str(r["description"]),
			"text": "Relic: %s" % r["name"]})
	var stores := _stores(run, elite)
	stores.shuffle()
	while _offers.size() < OFFERS and not stores.is_empty():
		_offers.append(stores.pop_back())


## The ordinary things worth carrying off, with their effects (see Events.apply).
func _stores(run: RunState, elite: bool) -> Array:
	var gold := roundi((GOLD_BASE + GOLD_PER_SEA * run.sea_number) * (ELITE_GOLD if elite else 1.0) * Perks.mult(run, "gold"))
	var found: Array = [
		{"text": "Her strongbox (+%d gold)" % gold, "effects": {"gold": gold}},
		{"text": "Her powder and shot (+6 chain, +6 grape, +4 heated)", "effects": {"ammo": {"chain_shot": 6, "grape_shot": 6, "heated_shot": 4}}},
		{"text": "Her rum (+6 rum, +5 morale)", "effects": {"rum": 6, "morale": 5}},
	]
	if run.hull < run.max_hull or run.sails < run.max_sails:
		found.append({"text": "Her timber and canvas (+%d hull, sails made good)" % TIMBER_HULL,
			"effects": {"hull": TIMBER_HULL, "sails": run.max_sails}})
	if run.crew.any(func(m: Dictionary) -> bool: return int(m.get("health", 100)) < 100):
		found.append({"text": "Her surgeon's stores (every specialist +%d health)" % MEDICINE, "heal": MEDICINE})
	if run.hands < run.max_hands:
		found.append({"text": "Volunteers from her crew (+%d hands)" % mini(VOLUNTEERS, run.max_hands - run.hands),
			"effects": {"hands": VOLUNTEERS}})
	return found


func _take(index: int) -> void:
	var run: RunState = GameState.run
	var o: Dictionary = _offers[index]
	if o.has("augment"):
		offer_augment(str(o["augment"]), _augment_done.bind(o))
		return
	if o.has("relic"):
		Perks.give_relic(run, str(o["relic"]))
		_taken = "%s is yours. %s" % [o["name"], o["detail"]]
	else:
		var lines := Events.apply(run, o.get("effects", {}))
		if o.has("heal"):
			for m: Dictionary in run.crew:
				m["health"] = mini(100, int(m.get("health", 100)) + int(o["heal"]))
			lines.append("the wounded are tended")
		_taken = "Carried aboard: %s." % ", ".join(lines)
	_finish()


## Back from the augment prompt: fitted, or left behind to choose again.
func _augment_done(fitted: bool, o: Dictionary) -> void:
	if fitted:
		_taken = "%s comes aboard. %s" % [o["name"], o["detail"]]
		_finish()
		return
	clear_buttons()
	_build()
	refresh()


func _finish() -> void:
	GameState.run.loot_pending = ""
	SaveSystem.save_run(GameState.run)
	clear_buttons()
	_build()
	refresh()
