extends Node
## All game content, loaded from res://data at startup. Autoloaded as `Data`.
##
## Each folder under data/ is a category. Every .json file in it holds an
## array of objects, and every object needs a unique "id". Add content by
## adding JSON; no code change needed.
##
## Note: JSON numbers load as floats. Wrap them in int() where you need ints.

const DATA_ROOT := "res://data"
const CATEGORIES: Array[String] = ["ammo", "ships", "enemies", "layouts", "crew", "names", "factions", "events"]

var _tables: Dictionary = {}  # category -> { id -> Dictionary }


func _ready() -> void:
	reload()


func reload() -> void:
	_tables.clear()
	for category in CATEGORIES:
		_tables[category] = _load_category(category)


## Every entry in a category, e.g. Data.get_all("ships").
func get_all(category: String) -> Array:
	var table: Dictionary = _tables.get(category, {})
	return table.values()


## One entry by id, e.g. Data.get_item("ammo", "chain_shot"). Empty if missing.
func get_item(category: String, id: String) -> Dictionary:
	var table: Dictionary = _tables.get(category, {})
	if not table.has(id):
		push_error("Data: no '%s' in %s" % [id, category])
		return {}
	return table[id]


func count(category: String) -> int:
	var table: Dictionary = _tables.get(category, {})
	return table.size()


func _load_category(category: String) -> Dictionary:
	var table := {}
	var dir_path := "%s/%s" % [DATA_ROOT, category]
	if not DirAccess.dir_exists_absolute(dir_path):
		push_warning("Data: missing folder %s" % dir_path)
		return table
	for file_name in DirAccess.get_files_at(dir_path):
		if not file_name.ends_with(".json"):
			continue
		var path := "%s/%s" % [dir_path, file_name]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Array):
			push_error("Data: %s must be a JSON array of objects" % path)
			continue
		for entry: Variant in parsed:
			if not (entry is Dictionary) or not entry.has("id"):
				push_error("Data: entry without an id in %s" % path)
				continue
			var id := str(entry["id"])
			if table.has(id):
				push_error("Data: duplicate id '%s' in %s" % [id, path])
				continue
			table[id] = entry
	return table
