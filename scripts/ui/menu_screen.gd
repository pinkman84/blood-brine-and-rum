extends ScreenBase


func _title() -> String:
	return "Blood, Brine & Rum"


func _build() -> void:
	add_button("New voyage", GameState.start_new_run)
	add_button("Continue voyage", GameState.continue_run, SaveSystem.has_run())
	add_button("Quit", get_tree().quit)


func refresh() -> void:
	_info.text = "Voyages %d   Victories %d   Doubloons %d" % [
		SaveSystem.meta_int("voyages"),
		SaveSystem.meta_int("victories"),
		SaveSystem.meta_int("doubloons"),
	]
