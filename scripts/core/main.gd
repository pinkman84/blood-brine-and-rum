extends Node2D
## Entry scene. For now it proves the project boots, the autoload works
## and the data files load. Later it will host the screen manager.

const AMMO_PATH := "res://data/ammo/ammo.json"

@onready var _label: Label = $Label


func _ready() -> void:
	GameState.screen_changed.connect(_on_screen_changed)
	var ammo := _load_json(AMMO_PATH)
	_label.text = "Blood, Brine & Rum\nGodot %s\n%d ammo types loaded" % [
		Engine.get_version_info()["string"],
		ammo.size(),
	]


# Typed as int: an autoload's enum can't be used as a type hint here.
func _on_screen_changed(from: int, to: int) -> void:
	print("Screen: %s -> %s" % [GameState.screen_name(from), GameState.screen_name(to)])


func _load_json(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		return parsed
	push_error("%s is not a JSON array" % path)
	return []
