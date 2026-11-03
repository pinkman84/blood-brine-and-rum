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
		ammo_lines.append("%s %d" % [Data.get_item("ammo", ammo_id).get("name", ammo_id), GameState.run.ammo[ammo_id]])
	_info.text = run_summary() + "\nAmmo: " + ", ".join(ammo_lines)
