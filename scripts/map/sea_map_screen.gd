extends Control
## The sea map: one sea's branching routes from entry (left) to the exit
## fight (right). Click a highlighted node to sail there. Each step costs a
## day and a rum ration (see GameState.finish_node).
##
## Fog of war: you can see what lies in the next REVEAL steps, and the exit.
## Anything further shows as "?". The map itself comes from SeaMapGen.

const BG_COLOR := Color("1d3b4f")
const NODE_RADIUS := 9.0
const REVEAL := 2
const STYLES := {
	"battle": ["B", Color("c0392b"), "Enemy ship"],
	"elite": ["!", Color("8e44ad"), "Sea exit: veteran captain"],
	"event": ["?", Color("2980b9"), "Something on the horizon"],
	"shop": ["$", Color("27ae60"), "Trading post"],
	"calm": ["~", Color("7f8c8d"), "Calm seas"],
}
const UNKNOWN_COLOR := Color("4a5a66")
const CALM_MORALE := 1

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
		_run.map = SeaMapGen.generate(_run.run_seed, _run.sea_number)
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
	_info.position = Vector2(12, 262)
	_info.size = Vector2(440, 90)
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
		if _was_visited(id) and id != here:
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
	_run.map["current"] = id
	(_run.map["visited"] as Array).append(id)
	_run.days += 1
	Voyage.change_hunt(_run, Voyage.HUNT_PER_DAY)
	var type := str(node["type"])
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
		"event":
			GameState.change_screen(GameState.Screen.EVENT)
		"shop":
			GameState.change_screen(GameState.Screen.SHOP)
		_:
			Morale.change(_run, CALM_MORALE)
			_run.last_note = "Calm seas and a fair wind. The crew rests (+%d morale)." % CALM_MORALE
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


## Fog of war: the next REVEAL steps, anything visited, and the exit are known.
func _is_known(node: Dictionary) -> bool:
	var layer := int(node["layer"])
	return layer < _run.node_index + REVEAL or str(node["type"]) == "elite" \
		or _was_visited(int(node["id"]))


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
	var text := ScreenBase.summary(_run) + "\nDay %d at sea." % _run.days
	if _hover >= 0:
		var node: Dictionary = _run.map["nodes"][_hover]
		var style: Array = STYLES.get(str(node["type"]), ["?", UNKNOWN_COLOR, "Unknown"])
		text = (str(style[2]) if _is_known(node) else "Unknown waters") + "\n" + text
	else:
		text = "Choose your heading: click a glowing node.\n" + text
	_info.text = text
