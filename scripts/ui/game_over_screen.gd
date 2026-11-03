extends ScreenBase


func _title() -> String:
	return "Victory!" if GameState.last_run_summary.get("won", false) else "Sunk"


func _build() -> void:
	add_button("Return to port", GameState.change_screen.bind(GameState.Screen.MENU))


func refresh() -> void:
	var s: Dictionary = GameState.last_run_summary
	_info.text = "Reached sea %d   Battles won %d\nDoubloons earned %d" % [
		int(s.get("sea_number", 1)),
		int(s.get("battles_won", 0)),
		int(s.get("doubloons", 0)),
	]
