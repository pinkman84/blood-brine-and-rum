extends Node
## Saves the current run and long-term progress. Autoloaded as `SaveSystem`.
##
## Files live in user://, which on Windows is
## %APPDATA%\Godot\app_userdata\Blood, Brine & Rum\
##   run.json  - the voyage in progress (deleted when the run ends)
##   meta.json - progress kept between runs (voyages, victories, unlocks)
##
## Every save carries a save_version. When the save format changes, bump
## SAVE_VERSION and add a step to _migrate() so old saves still load.

const SAVE_VERSION := 3
const RUN_PATH := "user://run.json"
const META_PATH := "user://meta.json"

var meta: Dictionary = {}


func _ready() -> void:
	meta = _read(META_PATH)
	if meta.is_empty():
		meta = _default_meta()


func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


func save_run(run: RunState) -> void:
	_write(RUN_PATH, run.to_dict())


func load_run() -> RunState:
	var data := _read(RUN_PATH)
	if data.is_empty():
		return null
	return RunState.from_dict(data)


func delete_run() -> void:
	if has_run():
		DirAccess.remove_absolute(RUN_PATH)


func save_meta() -> void:
	_write(META_PATH, meta)


func meta_int(key: String) -> int:
	return int(meta.get(key, 0))


func add_meta(key: String, amount: int) -> void:
	meta[key] = meta_int(key) + amount


func _default_meta() -> Dictionary:
	return {"voyages": 0, "victories": 0, "doubloons": 0, "unlocks": []}


# Write to a temp file first, then swap it in, so a crash mid-save can't
# leave a half-written file behind.
func _write(path: String, data: Dictionary) -> void:
	var payload := data.duplicate(true)
	payload["save_version"] = SAVE_VERSION
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("Save: can't write %s (error %d)" % [tmp_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("Save: can't move %s into place (error %d)" % [tmp_path, err])


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		# Keep the broken file for debugging instead of crashing or overwriting it.
		push_error("Save: %s is unreadable, moved to %s.corrupt" % [path, path])
		DirAccess.rename_absolute(path, path + ".corrupt")
		return {}
	return _migrate(parsed)


func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 1))
	if version > SAVE_VERSION:
		push_warning("Save: file is from a newer version of the game (%d > %d)" % [version, SAVE_VERSION])
	# One step per format change. Each brings a save up by one version.
	if version < 2:
		# v2 added sails to the run. Give old runs their ship's full sails.
		if data.has("ship_id"):
			var ship := Data.get_item("ships", str(data["ship_id"]))
			data["max_sails"] = int(ship.get("max_sails", 20))
			data["sails"] = data["max_sails"]
		version = 2
	if version < 3:
		# v3 split crew into hands (a number) and specialists. Sailors and
		# boarders became hands; give old runs 80% of their ship's hands.
		if data.has("ship_id"):
			var ship := Data.get_item("ships", str(data["ship_id"]))
			data["max_hands"] = int(ship.get("max_hands", 100))
			data["hands"] = roundi(int(data["max_hands"]) * RunState.START_HANDS)
			var kept: Array = []
			for member: Variant in data.get("crew", []):
				if Data.has_item("crew", str((member as Dictionary).get("role", ""))):
					kept.append(member)
			data["crew"] = kept
		version = 3
	data["save_version"] = version
	return data
