extends Node2D
## Boot scene. Reports what loaded, then hands over to the main menu.


func _ready() -> void:
	print("Blood, Brine & Rum on Godot %s" % Engine.get_version_info()["string"])
	for category in Data.CATEGORIES:
		print("  %s: %d" % [category, Data.count(category)])
	GameState.change_screen.call_deferred(GameState.Screen.MENU)
