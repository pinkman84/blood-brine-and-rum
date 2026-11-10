extends ScreenBase
## The home port, between voyages (see Hub). Spend doubloons to build and
## improve its places, see which ships you've earned, and set sail.

var _note := ""


func _title() -> String:
	return Hub.HOME_PORT


func _build() -> void:
	add_button("Set sail", GameState.change_screen.bind(GameState.Screen.SHIP_SELECT))
	for place: Dictionary in Data.get_all("hub"):
		var id := str(place["id"])
		var cost := Hub.next_cost(id)
		var lvl := Hub.level(id)
		if cost < 0:
			add_button("%s: as good as it gets" % place["name"], func() -> void: pass, false)
		else:
			var verb := "Build" if lvl == 0 else "Improve"
			add_button("%s %s, level %d of %d (%d doubloons)" % [verb, str(place["name"]).trim_prefix("The ").insert(0, "the "),
				lvl + 1, Hub.max_level(id), cost], _improve.bind(id), Hub.doubloons() >= cost)
	add_button("Back to the menu", GameState.change_screen.bind(GameState.Screen.MENU))


func refresh() -> void:
	var lines: Array[String] = ["Doubloons: %d" % Hub.doubloons()]
	if _note != "":
		lines.append(_note)
	lines.append("")
	for place: Dictionary in Data.get_all("hub"):
		var id := str(place["id"])
		var first := str((place.get("levels", [""]) as Array)[0])
		var state := "not built. Level 1: %s" % first if Hub.level(id) == 0 else "level %d. %s" % [Hub.level(id), Hub.effect_text(id)]
		lines.append("%s (%s): %s" % [place["name"], place["role"], state])
	lines.append("")
	var ships: Array = Data.get_all("ships")
	var ready := ships.filter(Hub.ship_unlocked).size()
	lines.append("Ships ready to sail: %d of %d. Set sail to see how to earn the rest." % [ready, ships.size()])
	_info.text = "\n".join(lines)


func _improve(id: String) -> void:
	if Hub.improve(id):
		_note = "Done. %s" % Data.get_item("hub", id).get("description", "")
	for b in _buttons.get_children():
		b.queue_free()
	_build()
	refresh()
