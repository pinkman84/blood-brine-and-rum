extends Control
## The sea chart: a web of places from the sea's entrance (left) to the exit
## fight (right), with the port on a strait in the middle. Click a glowing
## node to sail there: any neighbour, forwards, sideways or back. Every move
## costs a day and a rum ration and lets the Company hunt grow, so wandering
## has a price (see GameState.finish_node).
##
## Most of the sea is open water, where now and then a sail finds you
## (AMBUSH_CHANCE). Waters you've already sailed are empty. Fog of war: you
## know what's at the places next to anywhere you've been, plus the port and
## the exit; the rest shows as "?". The map itself comes from SeaMapGen.

const BG_COLOR := Color("1d3b4f")
const NODE_RADIUS := 9.0
const AMBUSH_CHANCE := 0.15  # a ship finds us in open water we haven't sailed before
const ISLAND_COLOR := Color("b8a47a")
const REEF_COLOR := Color("5f8f8a")
const STYLES := {
	"battle": ["B", Color("c0392b"), "Enemy ship"],
	"elite": ["!", Color("8e44ad"), "Sea exit: veteran captain"],
	"event": ["?", Color("2980b9"), "Something on the horizon"],
	"shop": ["$", Color("27ae60"), "Settlement: trade or raid"],
	"settlement": ["$", Color("27ae60"), "Settlement: trade or raid"],
	"haven": ["H", Color("a93226"), "Pirate haven: shore leave, hire crew"],
	"port": ["P", Color("d4ac0d"), "Port"],
	"outpost": ["$", Color("27ae60"), "Outpost: a place to trade"],
	"calm": ["~", Color("3f6f8a"), "Open water"],
	"storm": ["S", Color("34495e"), "Storm clouds"],
	"treasure": ["X", Color("e67e22"), "Treasure, if the old chart is true"],
}
const UNKNOWN_COLOR := Color("4a5a66")

var _run: RunState
var _hover := -1
var _info: Label
var _note: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme_ := Theme.new()
	theme_.default_font_size = 11
	theme = theme_
	_run = GameState.run
	if _run.map.is_empty():
		_run.map = SeaMapGen.generate(_run.run_seed, _run.sea_number, _run.sea_id)
		SaveSystem.save_run(_run)

	var title := Label.new()
	title.text = "Sea %d of %d: %s" % [_run.sea_number, RunState.SEAS_PER_RUN, Voyage.sea_name(_run)]
	title.add_theme_font_size_override("font_size", 18)
	title.position = Vector2(12, 8)
	add_child(title)

	_note = Label.new()
	_note.position = Vector2(12, 32)
	_note.size = Vector2(616, 20)
	_note.text = _run.last_note
	_run.last_note = ""
	add_child(_note)

	_info = Label.new()
	_info.position = Vector2(12, 246)
	_info.size = Vector2(440, 112)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)

	var quit := Button.new()
	quit.text = "Save and quit to menu"
	quit.position = Vector2(470, 322)
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(GameState.save_and_quit_to_menu)
	add_child(quit)
	_refresh_info()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.from_string(str(Voyage.sea(_run).get("color", "")), BG_COLOR))
	_draw_hunt()
	_draw_reputation()
	_draw_islands()
	var nodes: Array = _run.map["nodes"]
	var font := ThemeDB.fallback_font

	for node: Dictionary in nodes:
		for l: Variant in node["links"]:
			var other: Dictionary = nodes[int(l)]
			var travelled := _was_visited(int(node["id"])) and _was_visited(int(other["id"]))
			var colour := Color(1, 1, 1, 0.7) if travelled else Color(1, 1, 1, 0.15)
			draw_line(_pos(node), _pos(other), colour, 2.0 if travelled else 1.0)

	var reachable := _reachable()
	var here := int(_run.map["current"])
	for node: Dictionary in nodes:
		var id := int(node["id"])
		var p := _pos(node)
		var known := _is_known(node)
		var style: Array = STYLES.get(str(node["type"]), ["?", UNKNOWN_COLOR, ""])
		var fill: Color = style[1] if known else UNKNOWN_COLOR
		if _was_visited(id) and id != here and str(node["type"]) != "port" and str(node["type"]) != "outpost":
			fill = fill.darkened(0.55)
		if reachable.has(id):
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)
			draw_circle(p, NODE_RADIUS + 4.0, Color(1, 0.9, 0.4, 0.35 * pulse + (0.3 if id == _hover else 0.0)))
		draw_circle(p, NODE_RADIUS, fill)
		draw_arc(p, NODE_RADIUS, 0, TAU, 20, Color(0, 0, 0, 0.6), 1.5)
		var letter: String = style[0] if known else "?"
		draw_string(font, p + Vector2(-NODE_RADIUS, 4), letter, HORIZONTAL_ALIGNMENT_CENTER, NODE_RADIUS * 2, 11, Color.WHITE)
		if id == here:
			draw_arc(p, NODE_RADIUS + 3.0, 0, TAU, 20, Color.WHITE, 2.0)

	# Where we entered the sea.
	if here == -1:
		var start := Vector2(SeaMapGen.LEFT - 45, (SeaMapGen.TOP + SeaMapGen.BOTTOM) / 2.0)
		draw_circle(start, 5.0, Color.WHITE)
		for node: Dictionary in nodes:
			if int(node["layer"]) == 0:
				draw_line(start, _pos(node), Color(1, 1, 1, 0.25), 1.0)


func _process(_delta: float) -> void:
	queue_redraw()  # the reachable nodes pulse


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := _node_at((event as InputEventMouseMotion).position)
		if hovered != _hover:
			_hover = hovered
			_refresh_info()
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var id := _node_at(click.position)
		if id >= 0 and _reachable().has(id):
			_sail_to(id)


func _sail_to(id: int) -> void:
	var node: Dictionary = _run.map["nodes"][id]
	var been_here := _was_visited(id)
	_run.map["current"] = id
	if not been_here:
		(_run.map["visited"] as Array).append(id)
	_run.days += 1
	Voyage.change_hunt(_run, maxi(1, Voyage.HUNT_PER_DAY + roundi(Perks.add(_run, "hunt_per_day"))))
	var type := str(node["type"])
	if been_here and type != "port" and type != "outpost":
		type = "sailed"  # nothing left here; ports and outposts stay where they are
	elif type == "calm" and randf() < AMBUSH_CHANCE:
		type = "battle"  # a sail on the horizon, closing fast
	if _run.hunt >= Voyage.INTERCEPT and type != "elite":
		# The hunt has found us: whatever was waiting here, a Company hunter is upon us.
		_run.hunter_pending = true
		_run.hunt = Voyage.AFTER_INTERCEPT
		type = "battle"
	SaveSystem.save_run(_run)
	match type:
		"battle":
			GameState.change_screen(GameState.Screen.BATTLE)
		"elite":
			_run.elite_pending = true
			GameState.change_screen(GameState.Screen.BATTLE)
		"event", "storm", "treasure":
			GameState.change_screen(GameState.Screen.EVENT)
		"shop", "settlement", "haven", "port":
			GameState.change_screen(GameState.Screen.SHOP)
		"outpost":
			GameState.change_screen(GameState.Screen.OUTPOST)
		"sailed":
			_run.last_note = "Waters we've sailed before. Nothing here but our own wake."
			GameState.finish_node()
		_:
			_run.last_note = "Open water and a fair wind. A quiet day's sailing."
			GameState.finish_node()


# --- Helpers ----------------------------------------------------------------

## The Company's hunt as a bar in the top-right corner.
func _draw_hunt() -> void:
	var bar := Rect2(470, 12, 158, 6)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var share := float(_run.hunt) / Voyage.INTERCEPT
	var colour := Color("e67e22") if _run.hunt < Voyage.HUNTED else Color("e74c3c")
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), colour)
	draw_string(ThemeDB.fallback_font, Vector2(470, 30), "Company hunt %d%%" % _run.hunt,
		HORIZONTAL_ALIGNMENT_LEFT, 158, 10, Color(1, 1, 1, 0.8))


## How each faction feels about us, bottom right above the quit button.
func _draw_reputation() -> void:
	var font := ThemeDB.fallback_font
	var y := 258.0
	for f in Reputation.ORDER:
		var value := Reputation.of(_run, f)
		draw_string(font, Vector2(470, y), Reputation.short_name(f), HORIZONTAL_ALIGNMENT_LEFT, 90, 10, Color(1, 1, 1, 0.8))
		draw_string(font, Vector2(560, y), "%s %+d" % [Reputation.tier(value), value], HORIZONTAL_ALIGNMENT_LEFT, 80, 10, Reputation.tier_color(value))
		y += 12.0


## Scenery from the map: islands, reefs and the shores of the port's strait.
func _draw_islands() -> void:
	for i: Variant in _run.map.get("islands", []):
		var at := Vector2(float(i[0]), float(i[1]))
		var radius := Vector2(float(i[2]), float(i[3]))
		draw_set_transform(at, 0.0, radius)
		draw_circle(Vector2.ZERO, 1.25, Color(REEF_COLOR, 0.35))  # shallows
		draw_circle(Vector2.ZERO, 1.0, ISLAND_COLOR)
		draw_circle(Vector2(-0.1, -0.1), 0.6, ISLAND_COLOR.darkened(0.25))  # scrub
	draw_set_transform(Vector2.ZERO)


func _pos(node: Dictionary) -> Vector2:
	var p: Array = node["pos"]
	return Vector2(float(p[0]), float(p[1]))


func _reachable() -> Array:
	var here := int(_run.map["current"])
	var result: Array = []
	for node: Dictionary in _run.map["nodes"]:
		if here == -1 and int(node["layer"]) == 0:
			result.append(int(node["id"]))
	if here >= 0:
		for l: Variant in _run.map["nodes"][here]["links"]:
			result.append(int(l))
	return result


## Fog of war: we know the port, the exit, anywhere we've been, and whatever
## the lookout can see from there (their neighbours). Before the first move,
## that's the places we could enter the sea.
func _is_known(node: Dictionary) -> bool:
	var id := int(node["id"])
	if str(node["type"]) == "elite" or str(node["type"]) == "port" or _was_visited(id):
		return true
	if int(_run.map["current"]) == -1:
		return int(node["layer"]) == 0
	for l: Variant in node["links"]:
		if _was_visited(int(l)):
			return true
	return false


## Saved maps come back from JSON with numbers as floats, so compare as ints.
func _was_visited(id: int) -> bool:
	for v: Variant in _run.map["visited"]:
		if int(v) == id:
			return true
	return false


func _node_at(point: Vector2) -> int:
	for node: Dictionary in _run.map["nodes"]:
		if _pos(node).distance_to(point) <= NODE_RADIUS + 3.0:
			return int(node["id"])
	return -1


func _refresh_info() -> void:
	# The sea, step and hunt are shown elsewhere on this screen, so keep this short.
	var text := "Gold %d   Hull %d/%d   Sails %d/%d   Hands %d/%d\nMorale %d (%s)   Rum %d%s   Specialists %d   Day %d" % [
		_run.gold, _run.hull, _run.max_hull, _run.sails, _run.max_sails, _run.hands, _run.max_hands,
		_run.morale, Morale.mood(_run.morale), _run.rum, " (cask dry!)" if _run.rum <= 0 else "", _run.crew.size(), _run.days]
	var relics := Perks.relic_names(_run, false)
	if relics != "":
		text += "\nRelics: %s" % relics
	for goal in Hub.active_quests(_run):
		text += "\nQuest: %s" % goal
	if not _run.upgrades.is_empty():
		var fitted: Array[String] = []
		for id: Variant in _run.upgrades:
			fitted.append("%s x%d" % [str(Data.get_item("upgrades", str(id)).get("name", id)).to_lower(), int(_run.upgrades[id])])
		text += "\nFitted: %s" % ", ".join(fitted)
	if _hover >= 0:
		var node: Dictionary = _run.map["nodes"][_hover]
		var style: Array = STYLES.get(str(node["type"]), ["?", UNKNOWN_COLOR, "Unknown"])
		var label := str(style[2])
		if node.has("owner"):
			var kind := str(Data.get_item("factions", str(node["owner"])).get("port", {}).get("kind", "port"))
			label = "%s, %s: trade, or attack for a richer prize" % [node.get("name", "Port"), kind]
		if str(node["type"]) == "outpost":
			label = "%s: a place to trade" % node.get("name", "Outpost")
		elif _was_visited(_hover) and str(node["type"]) != "port":
			label = "Waters we've sailed: nothing left here"
		text = (label if _is_known(node) else "Uncharted waters") + "\n" + text
	else:
		text = "Sound the Aeolus Horn and choose your heading: click a glowing node.\n" + text
	_info.text = text
