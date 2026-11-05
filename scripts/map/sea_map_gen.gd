class_name SeaMapGen
extends RefCounted
## Builds the branching node map for one sea, Slay the Spire style.
##
## A sea is LAYERS steps from entry to exit. Each step has 2 or 3 nodes, each
## linked to 1 or 2 nodes in the next step. The last step is a single elite
## fight at the sea's exit. Every route through the sea must hold at least
## MIN_BATTLES battles (the exit fight counts); maps that fail are rerolled.
##
## The map is plain data, so it saves with the run:
##   { "nodes": [ { id, layer, type, pos: [x, y], links: [ids] } ],
##     "current": node id or -1 before the first step, "visited": [ids] }
## Positions are in screen pixels for the 640x360 map screen.

const LAYERS := 7
const MIN_BATTLES := 4
const TYPE_WEIGHTS := {"battle": 0.5, "event": 0.25, "shop": 0.12, "calm": 0.13}
const LEFT := 70.0
const RIGHT := 590.0
const TOP := 70.0
const BOTTOM := 230.0


static func generate(run_seed: int, sea: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, sea])
	for attempt in 60:
		var map := _build(rng)
		if min_battles(map) >= MIN_BATTLES:
			return map
	var fallback := _build(rng)
	_force_battles(fallback, rng)
	return fallback


static func _build(rng: RandomNumberGenerator) -> Dictionary:
	var nodes: Array = []
	var layers: Array = []  # layer -> array of node ids
	for layer in LAYERS:
		var count := 1 if layer == LAYERS - 1 else rng.randi_range(2, 3)
		var ids: Array = []
		for k in count:
			var x := lerpf(LEFT, RIGHT, float(layer) / (LAYERS - 1))
			var y := lerpf(TOP, BOTTOM, (k + 0.5) / count) + rng.randf_range(-8.0, 8.0)
			var type := "elite" if layer == LAYERS - 1 else _pick_type(rng, layer)
			nodes.append({"id": nodes.size(), "layer": layer, "type": type, "pos": [roundf(x), roundf(y)], "links": []})
			ids.append(nodes.size() - 1)
		layers.append(ids)

	# Link each step to the next, keeping links roughly straight so routes don't tangle.
	for layer in LAYERS - 1:
		var here: Array = layers[layer]
		var there: Array = layers[layer + 1]
		var reached := {}
		for i in here.size():
			var j := roundi(float(i) * (there.size() - 1) / maxf(1.0, here.size() - 1))
			_link(nodes, here[i], there[j], reached)
			var extra := j + (1 if rng.randf() < 0.5 else -1)
			if extra >= 0 and extra < there.size() and rng.randf() < 0.5:
				_link(nodes, here[i], there[extra], reached)
		for j in there.size():
			if not reached.has(there[j]):
				var i := roundi(float(j) * (here.size() - 1) / maxf(1.0, there.size() - 1))
				_link(nodes, here[i], there[j], reached)
	return {"nodes": nodes, "current": -1, "visited": []}


static func _link(nodes: Array, from_id: int, to_id: int, reached: Dictionary) -> void:
	var links: Array = nodes[from_id]["links"]
	if not links.has(to_id):
		links.append(to_id)
	reached[to_id] = true


static func _pick_type(rng: RandomNumberGenerator, layer: int) -> String:
	var total := 0.0
	for type: String in TYPE_WEIGHTS:
		if layer == 0 and type == "shop":
			continue  # no trading post right at the sea's entrance
		total += float(TYPE_WEIGHTS[type])
	var roll := rng.randf() * total
	for type: String in TYPE_WEIGHTS:
		if layer == 0 and type == "shop":
			continue
		roll -= float(TYPE_WEIGHTS[type])
		if roll <= 0.0:
			return type
	return "battle"


static func is_battle(type: String) -> bool:
	return type == "battle" or type == "elite"


## The fewest battles on any route from the sea's entrance to its exit.
static func min_battles(map: Dictionary) -> int:
	var nodes: Array = map["nodes"]
	var best := {}
	for n in range(nodes.size() - 1, -1, -1):  # later layers have higher ids
		var node: Dictionary = nodes[n]
		var after := 0
		var links: Array = node["links"]
		if not links.is_empty():
			after = 1 << 30
			for l: Variant in links:
				after = mini(after, int(best[int(l)]))
		best[n] = after + (1 if is_battle(str(node["type"])) else 0)
	var fewest := 1 << 30
	for node: Dictionary in nodes:
		if int(node["layer"]) == 0:
			fewest = mini(fewest, int(best[int(node["id"])]))
	return fewest


## Last resort: turn whole steps into battles until every route has enough.
static func _force_battles(map: Dictionary, rng: RandomNumberGenerator) -> void:
	var guard := 0
	while min_battles(map) < MIN_BATTLES and guard < LAYERS:
		guard += 1
		var layer := rng.randi_range(0, LAYERS - 2)
		for node: Dictionary in map["nodes"]:
			if int(node["layer"]) == layer:
				node["type"] = "battle"
