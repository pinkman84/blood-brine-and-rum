extends ScreenBase
## Placeholder sea map: pick the next node type by hand. Phase 4 replaces
## this with the generated node map.


func _title() -> String:
	return "Sea map"


func _build() -> void:
	add_button("Sail into battle", GameState.change_screen.bind(GameState.Screen.BATTLE))
	add_button("Sail to an event", GameState.change_screen.bind(GameState.Screen.EVENT))
	add_button("Sail to a trading post", GameState.change_screen.bind(GameState.Screen.SHOP))
	add_button("Save and quit to menu", GameState.save_and_quit_to_menu)


func refresh() -> void:
	var ammo_lines: Array[String] = []
	for ammo_id: String in GameState.run.ammo:
		var ammo_name := str(Data.get_item("ammo", ammo_id).get("name", ammo_id))
		if BattleShip.is_free_ammo(ammo_id):
			ammo_lines.append(ammo_name)
		else:
			ammo_lines.append("%s %d" % [ammo_name, GameState.run.ammo[ammo_id]])
	var crew_lines: Array[String] = []
	for m: Dictionary in GameState.run.crew:
		var role := str(Data.get_item("crew", str(m.get("role", ""))).get("name", ""))
		crew_lines.append("%s (%s) %d%%" % [m.get("name", ""), role, int(m.get("health", 100))])
	_info.text = run_summary() + "\nAmmo: " + ", ".join(ammo_lines) + "\nCrew: " + ", ".join(crew_lines)
