class_name SeaMapGen
extends RefCounted
## Builds the chart for one sea: a web of places to sail between, FTL style.
##
## Nodes are scattered in COLUMNS from the sea's entrance (left) to its exit
## (right) and linked to their neighbours, so there are many routes and you
## can double back. Two columns hold a single node every route must pass:
## the port in the middle, on a strait between two landmasses (owned by a
## faction from the sea's "port_owners"), and the elite fight at the exit.
## A few outposts (OUTPOSTS, like FTL's stores) are scattered at random.
## Most of the sea is open water; what's at a node is only known once you're
## next to it (see the map screen).
##
## The map is plain data, so it saves with the run:
##   { "nodes": [ { id, layer, type, pos: [x, y], links: [ids], owner?, name? } ],
##     "islands": [ [x, y, rx, ry] ], "current": node id or -1, "visited": [ids] }
## "layer" is the node's column. Links go both ways. Positions are in screen
## pixels for the 640x360 map screen. Islands are only scenery.

const LAYERS := 9  # columns, entrance to exit
const PORT_LAYER := 4
const MIN_ROWS := 2
const MAX_ROWS := 4
const TYPE_WEIGHTS := {"calm": 0.45, "battle": 0.27, "event": 0.16, "storm": 0.07, "treasure": 0.05}
const OUTPOSTS := [1, 3]  # fewest and most places to trade in a sea, besides the port
const MIN_BATTLE_NODES := 6  # a sea always has at least this many ordinary fights somewhere in it
const SIDE_LINK_CHANCE := 0.5  # two nodes in the same column are linked
const EXTRA_LINK_CHANCE := 0.45  # a second link forward, to another near neighbour
const ISLANDS := 7
const LEFT := 60.0
const RIGHT := 590.0
const TOP := 64.0
const BOTTOM := 232.0


static func generate(run_seed: int, sea: int, sea_id := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, sea])
	var sea_data: Dictionary = Data.get_item("seas", sea_id) if Data.has_item("seas", sea_id) else {}
	var weights := TYPE_WEIGHTS.duplicate()
	weights["storm"] = float(weights["storm"]) * float(sea_data.get("storms", 1.0))  # the Cape lives up to its name
	weights["treasure"] = float(weights["treasure"]) * Hub.treasure_factor()  # the home port's cartographer
	var map := _build(rng, weights)
	_ensure_battles(map, rng)
	_place_outposts(map, rng)
	_name_port(map, rng, sea_data)
	map["islands"] = _islands(map, rng)
	return map


static func _build(rng: RandomNumberGenerator, weights: Dictionary) -> Dictionary:
	var nodes: Array = []
	var columns: Array = []  # column -> node ids, top to bottom
	for col in LAYERS:
		var single := col == LAYERS - 1 or col == PORT_LAYER
		var count := 1 if single else rng.randi_range(MIN_ROWS, MAX_ROWS)
		var ids: Array = []
		for k in count:
			var x := lerpf(LEFT, RIGHT, float(col) / (LAYERS - 1)) + (0.0 if single else rng.randf_range(-12.0, 12.0))
			var y := lerpf(TOP, BOTTOM, (k + 0.5) / count) + (0.0 if single else rng.randf_range(-10.0, 10.0))
			var type := "elite" if col == LAYERS - 1 else ("port" if col == PORT_LAYER else _pick_type(rng, weights))
			nodes.append({"id": nodes.size(), "layer": col, "type": type, "pos": [roundf(x), roundf(y)], "links": []})
			ids.append(nodes.size() - 1)
		columns.append(ids)

	for col in LAYERS:
		var here: Array = columns[col]
		# Sideways, between neighbours in the same column.
		for k in here.size() - 1:
			if rng.randf() < SIDE_LINK_CHANCE:
				_link(nodes, here[k], here[k + 1])
		if col == LAYERS - 1:
			break
		# Forward: every node reaches its nearest neighbour in the next column,
		# and sometimes the next nearest too. Then nobody ahead is left stranded.
		var there: Array = columns[col + 1]
		for id: int in here:
			var near := _by_distance(nodes, id, there)
			_link(nodes, id, near[0])
			if near.size() > 1 and rng.randf() < EXTRA_LINK_CHANCE:
				_link(nodes, id, near[1])
		for id: int in there:
			if not _has_link_into(nodes, id, here):
				_link(nodes, _by_distance(nodes, id, here)[0], id)
	return {"nodes": nodes, "current": -1, "visited": []}


## The ids in `candidates`, nearest to node `from_id` first.
static func _by_distance(nodes: Array, from_id: int, candidates: Array) -> Array:
	var sorted := candidates.duplicate()
	var origin := _pos(nodes[from_id])
	sorted.sort_custom(func(a: int, b: int) -> bool: return _pos(nodes[a]).distance_to(origin) < _pos(nodes[b]).distance_to(origin))
	return sorted


static func _has_link_into(nodes: Array, id: int, others: Array) -> bool:
	for l: Variant in nodes[id]["links"]:
		if others.has(int(l)):
			return true
	return false


static func _link(nodes: Array, a: int, b: int) -> void:
	if not (nodes[a]["links"] as Array).has(b):
		(nodes[a]["links"] as Array).append(b)
	if not (nodes[b]["links"] as Array).has(a):
		(nodes[b]["links"] as Array).append(a)


static func _pos(node: Dictionary) -> Vector2:
	return Vector2(float(node["pos"][0]), float(node["pos"][1]))


static func _pick_type(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for type: String in weights:
		total += float(weights[type])
	var roll := rng.randf() * total
	for type: String in weights:
		roll -= float(weights[type])
		if roll <= 0.0:
			return type
	return "calm"


static func is_battle(type: String) -> bool:
	return type == "battle" or type == "elite"


## Turns open water into fights until the sea has enough of them, split
## between the waters before the port and after it.
static func _ensure_battles(map: Dictionary, rng: RandomNumberGenerator) -> void:
	for half in 2:
		var battles := 0
		var water: Array = []
		for node: Dictionary in map["nodes"]:
			var col := int(node["layer"])
			if (col < PORT_LAYER) != (half == 0) or col == PORT_LAYER:
				continue
			if node["type"] == "battle":
				battles += 1
			elif node["type"] == "calm":
				water.append(node)
		while battles < MIN_BATTLE_NODES / 2 and not water.is_empty():
			var node: Dictionary = water.pop_at(rng.randi_range(0, water.size() - 1))
			node["type"] = "battle"
			battles += 1


## Scatters a few outposts over open water (or failing that, event nodes),
## anywhere but the sea's entrance. Each is a kind from data/outposts.
static func _place_outposts(map: Dictionary, rng: RandomNumberGenerator) -> void:
	var kinds: Array = Data.get_all("outposts")
	if kinds.is_empty():
		return
	var spots: Array = []
	for want: String in ["calm", "event"]:
		for node: Dictionary in map["nodes"]:
			if node["type"] == want and int(node["layer"]) > 0:
				spots.append(node)
		if spots.size() >= int(OUTPOSTS[1]):
			break
	for i in rng.randi_range(int(OUTPOSTS[0]), int(OUTPOSTS[1])):
		if spots.is_empty():
			return
		var node: Dictionary = spots.pop_at(rng.randi_range(0, spots.size() - 1))
		var kind: Dictionary = kinds[rng.randi_range(0, kinds.size() - 1)]
		node["type"] = "outpost"
		node["kind"] = str(kind["id"])
		node["name"] = str(kind["name"])


## Decide who owns this sea's port, and what it's called.
static func _name_port(map: Dictionary, rng: RandomNumberGenerator, sea: Dictionary) -> void:
	var weights: Dictionary = sea.get("port_owners", {"company": 1})
	var total := 0.0
	for f: String in weights:
		total += float(weights[f])
	var roll := rng.randf() * total
	var owner := "company"
	for f: String in weights:
		roll -= float(weights[f])
		if roll <= 0.0:
			owner = f
			break
	var names: Array = sea.get("havens" if owner == "brotherhood" else "settlements", ["a harbour"])
	for node: Dictionary in map["nodes"]:
		if node["type"] == "port":
			node["owner"] = owner
			node["name"] = str(names[rng.randi_range(0, names.size() - 1)])


## Scenery: the two shores of the port's strait, and a scatter of islands and
## reefs in the gaps between nodes. Each is [x, y, radius x, radius y].
static func _islands(map: Dictionary, rng: RandomNumberGenerator) -> Array:
	var islands: Array = []
	var nodes: Array = map["nodes"]
	for node: Dictionary in nodes:
		if node["type"] == "port":
			var p := _pos(node)
			var gap := 26.0  # clear water either side of the port
			var north := TOP - 14.0
			var south := BOTTOM + 8.0
			islands.append([p.x, (north + p.y - gap) / 2.0, 18.0, (p.y - gap - north) / 2.0])
			islands.append([p.x, (south + p.y + gap) / 2.0, 18.0, (south - p.y - gap) / 2.0])
	var tries := 0
	while islands.size() < ISLANDS + 2 and tries < 200:
		tries += 1
		var at := Vector2(rng.randf_range(LEFT, RIGHT), rng.randf_range(TOP - 10.0, BOTTOM + 10.0))
		var radius := Vector2(rng.randf_range(8.0, 18.0), rng.randf_range(6.0, 12.0))
		if _clear_of_routes(nodes, at, maxf(radius.x, radius.y) + 8.0):
			islands.append([roundf(at.x), roundf(at.y), roundf(radius.x), roundf(radius.y)])
	return islands


## True if nothing sails within `gap` of this point: no node and no link.
static func _clear_of_routes(nodes: Array, at: Vector2, gap: float) -> bool:
	for node: Dictionary in nodes:
		var a := _pos(node)
		if a.distance_to(at) < gap + 8.0:
			return false
		for l: Variant in node["links"]:
			var b := _pos(nodes[int(l)])
			if Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) < gap:
				return false
	return true
