extends Node
## Global game state. Autoloaded as `GameState` (see project.godot).
##
## Tracks which screen the game is on and announces changes, so scenes
## never need to know about each other. Run and save data will live here
## or in sibling autoloads as Phase 0 continues.

enum Screen { MENU, SEA_MAP, BATTLE, EVENT, SHOP, GAME_OVER }

signal screen_changed(from: Screen, to: Screen)

var current_screen: Screen = Screen.MENU


func change_screen(to: Screen) -> void:
	if to == current_screen:
		return
	var from := current_screen
	current_screen = to
	screen_changed.emit(from, to)


func screen_name(screen: Screen) -> String:
	return Screen.keys()[screen]
