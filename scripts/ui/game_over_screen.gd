extends ScreenBase


func _title() -> String:
	return "Victory!" if GameState.last_run_summary.get("won", false) else "Sunk"


func _build() -> void:
	add_button("Return to %s" % Hub.HOME_PORT, GameState.change_screen.bind(GameState.Screen.HUB))


func refresh() -> void:
	var s: Dictionary = GameState.last_run_summary
	_info.text = "Reached sea %d   Battles won %d\nDoubloons earned %d (you have %d to spend at home)" % [
		int(s.get("sea_number", 1)),
		int(s.get("battles_won", 0)),
		int(s.get("doubloons", 0)),
		Hub.doubloons(),
	]
	var unlocked: Array = s.get("unlocked", [])
	if not unlocked.is_empty():
		_info.text += "\n\nA new ship is waiting at home: %s." % ", ".join(unlocked)
