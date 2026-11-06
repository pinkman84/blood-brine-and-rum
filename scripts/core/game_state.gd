extends Node
## Global game state. Autoloaded as `GameState` (see project.godot).
##
## Owns the current run and decides which screen is showing. Screens call
## into here (start a run, finish a node, end the run) and never load each
## other directly.

enum Screen { MENU, SEA_MAP, BATTLE, EVENT, SHOP, GAME_OVER, SEA_CHART }

const SCREEN_SCENES := {
	Screen.MENU: "res://scenes/ui/menu.tscn",
	Screen.SEA_MAP: "res://scenes/map/sea_map.tscn",
	Screen.BATTLE: "res://scenes/battle/battle.tscn",
	Screen.EVENT: "res://scenes/ui/event.tscn",
	Screen.SHOP: "res://scenes/ui/shop.tscn",
	Screen.GAME_OVER: "res://scenes/ui/game_over.tscn",
	Screen.SEA_CHART: "res://scenes/map/sea_chart.tscn",
}

const STARTING_SHIP := "sloop"

signal screen_changed(from: Screen, to: Screen)

var current_screen: Screen = Screen.MENU
var run: RunState = null
var last_run_summary: Dictionary = {}


func change_screen(to: Screen) -> void:
	var from := current_screen
	current_screen = to
	get_tree().change_scene_to_file(SCREEN_SCENES[to])
	screen_changed.emit(from, to)


func screen_name(screen: Screen) -> String:
	return Screen.keys()[screen]


func start_new_run() -> void:
	run = RunState.new_run(Data.get_item("ships", STARTING_SHIP))
	Voyage.enter_sea(run, Voyage.START_SEA)
	SaveSystem.add_meta("voyages", 1)
	SaveSystem.save_meta()
	SaveSystem.save_run(run)
	change_screen(Screen.SEA_MAP)


func continue_run() -> void:
	run = SaveSystem.load_run()
	if run == null:
		change_screen(Screen.MENU)
	elif run.route.size() < run.sea_number:
		change_screen(Screen.SEA_CHART)  # we quit while choosing the next sea
	else:
		change_screen(Screen.SEA_MAP)


## Call when the player finishes a node. Moves on, saves, and returns to the map.
func finish_node() -> void:
	# A day's sailing: the crew drinks its rum ration, or grumbles without one.
	if run.rum > 0:
		run.rum -= 1
	else:
		Morale.change(run, Morale.NO_RUM)
	# Steps through the sea follow the map: we're one past the node just finished.
	var here := int(run.map.get("current", -1))
	if here >= 0:
		run.node_index = int(run.map["nodes"][here]["layer"]) + 1
	else:
		run.node_index += 1
	if run.node_index >= RunState.NODES_PER_SEA:
		run.node_index = 0
		run.sea_number += 1
		run.map = {}  # the next sea's map is drawn when we first see it
		if run.sea_number > RunState.SEAS_PER_RUN:
			end_run(true)
			return
		if run.sea_number == RunState.SEAS_PER_RUN:
			Voyage.enter_sea(run, Voyage.FINAL_SEA)  # the last leg is always the Company's home waters
		else:
			SaveSystem.save_run(run)
			change_screen(Screen.SEA_CHART)  # choose the next sea
			return
	SaveSystem.save_run(run)
	change_screen(Screen.SEA_MAP)


func end_run(won: bool) -> void:
	var doubloons := run.battles_won + (25 if won else 0)
	last_run_summary = {
		"won": won,
		"sea_number": mini(run.sea_number, RunState.SEAS_PER_RUN),
		"battles_won": run.battles_won,
		"doubloons": doubloons,
	}
	SaveSystem.add_meta("doubloons", doubloons)
	if won:
		SaveSystem.add_meta("victories", 1)
	SaveSystem.save_meta()
	SaveSystem.delete_run()
	run = null
	change_screen(Screen.GAME_OVER)


func save_and_quit_to_menu() -> void:
	if run != null:
		SaveSystem.save_run(run)
	run = null
	change_screen(Screen.MENU)


# Save if the window is closed mid-run.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and run != null:
		SaveSystem.save_run(run)
