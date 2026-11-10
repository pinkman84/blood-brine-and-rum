extends ScreenBase
## Choose your ship before a voyage. Each one has its own stats, crew and
## stores, and changes how the factions greet you ("start_rep" in data/ships).

var _ships: Array = []
var _selected := 0


func _title() -> String:
	return "Choose your ship"


func _build() -> void:
	if _ships.is_empty():
		for s: Dictionary in Data.get_all("ships"):
			if bool(s.get("unlocked_at_start", true)):
				_ships.append(s)
	for i in _ships.size():
		var mark := "> " if i == _selected else "   "
		add_button(mark + str(_ships[i].get("name", "Ship")), _select.bind(i))
	add_button("Set sail in the %s" % str(_ships[_selected].get("name", "ship")).to_lower(), _sail)
	add_button("Back", GameState.change_screen.bind(GameState.Screen.MENU))


func refresh() -> void:
	var s: Dictionary = _ships[_selected]
	var crew: Array[String] = []
	for role: Variant in s.get("starting_crew", []):
		crew.append(str(Data.get_item("crew", str(role)).get("name", role)).to_lower())
	var lines: Array[String] = [
		str(s.get("description", "")),
		"",
		"Hull %d   Sails %d   Guns %d a side   Hands %d" % [
			int(s.get("max_hull", 0)), int(s.get("max_sails", 0)), int(s.get("guns_per_side", 0)),
			roundi(int(s.get("max_hands", 100)) * RunState.START_HANDS)],
		"Gold %d   Crew: %s" % [int(s.get("starting_gold", 0)), ", ".join(crew)],
		"",
		"How they'll greet you:",
	]
	var shift: Dictionary = s.get("start_rep", {})
	for f in Reputation.ORDER:
		var value := clampi(int(Data.get_item("factions", f).get("starting_reputation", 0)) + int(shift.get(f, 0)),
			Reputation.MIN, Reputation.MAX)
		lines.append("  %s: %s (%+d)" % [Reputation.short_name(f), Reputation.tier(value), value])
	_info.text = "\n".join(lines)


func _select(index: int) -> void:
	_selected = index
	for b in _buttons.get_children():
		b.queue_free()
	_build()
	refresh()


func _sail() -> void:
	GameState.start_new_run(str(_ships[_selected]["id"]))
