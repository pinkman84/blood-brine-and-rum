class_name ShipView
extends Node2D
## A ship seen from above with its decks cut away, FTL style: hull, rooms,
## masts, sails and crew. Drawn with plain shapes until the pixel art arrives.
##
## The origin is the middle of the room grid. The bow points up and starboard
## is on the right. Flip an enemy with scale.x = -1 so its starboard faces left.
## Room layouts come from data/layouts.

const CELL := 22.0
const HULL_MARGIN := 11.0
const BOW_LENGTH := 36.0
const MAX_HOLES := 40
const ROOM_LETTERS := {"sails": "S", "guns": "G", "magazine": "M", "sickbay": "+", "helm": "H", "hold": "D"}

var hull_color := Color("6b4a2f")
var floor_color := Color("4a3524")
var wall_color := Color("24170d")
var sail_color := Color("e8dfc8")
var flag_color := Color("111111")
var guns_per_side := 4
var rooms: Array[Dictionary] = []  # { id, type, side, rect }
var mast_ys: Array[float] = []
var crew: Array = []  # BattleCrew, drawn on top of the decks
var selected: BattleCrew = null
var hover_room_id := ""
var base_position := Vector2.ZERO  # bobbing and sinking move around this
var sails_ratio := 1.0:  # 0 = shredded, 1 = full; shortens the drawn sails
	set(value):
		sails_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()

var _grid := Vector2.ZERO
var _holes: Array[Vector2] = []
var _sail_holes: Array[Vector2] = []
var _time := randf() * TAU


func setup(data: Dictionary) -> void:
	hull_color = Color.from_string(str(data.get("hull_color", "")), hull_color)
	sail_color = Color.from_string(str(data.get("sail_color", "")), sail_color)
	flag_color = Color.from_string(str(data.get("flag_color", "")), flag_color)
	guns_per_side = int(data.get("guns_per_side", 4))
	var layout := Data.get_item("layouts", str(data.get("layout", "sloop")))
	_grid = Vector2(float(layout.get("cols", 3)), float(layout.get("rows", 8))) * CELL
	var origin := -_grid / 2.0
	rooms.clear()
	for r: Dictionary in layout.get("rooms", []):
		var cell_pos := Vector2(float(r.get("x", 0)), float(r.get("y", 0)))
		var cell_size := Vector2(float(r.get("w", 1)), float(r.get("h", 1)))
		rooms.append({
			"id": str(r.get("id", "")),
			"type": str(r.get("type", "")),
			"side": str(r.get("side", "")),
			"rect": Rect2(origin + cell_pos * CELL, cell_size * CELL),
		})
	mast_ys.clear()
	for row: Variant in layout.get("mast_rows", []):
		mast_ys.append(origin.y + float(row) * CELL)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	position = base_position + Vector2(0, roundf(sin(_time * 1.3)))
	queue_redraw()  # crew move every frame


# --- Drawing --------------------------------------------------------------

func _draw() -> void:
	var hw := half_width()
	var top := -_grid.y / 2.0 - HULL_MARGIN
	var bottom := _grid.y / 2.0 + HULL_MARGIN
	var hull := PackedVector2Array([
		Vector2(0, top - BOW_LENGTH), Vector2(hw * 0.7, top - BOW_LENGTH * 0.45),
		Vector2(hw, top + 8), Vector2(hw, bottom - 6), Vector2(hw - 6, bottom),
		Vector2(-hw + 6, bottom), Vector2(-hw, bottom - 6), Vector2(-hw, top + 8),
		Vector2(-hw * 0.7, top - BOW_LENGTH * 0.45),
	])
	draw_colored_polygon(hull, hull_color)
	var outline := hull.duplicate()
	outline.append(hull[0])
	draw_polyline(outline, wall_color, 2.0)

	var font := ThemeDB.fallback_font
	for room in rooms:
		var rect: Rect2 = room["rect"]
		draw_rect(rect, floor_color)
		if room["id"] == hover_room_id:
			draw_rect(rect, Color(1, 1, 0.6, 0.18))
		draw_rect(rect, wall_color, false, 2.0)
		if room["type"] == "guns":
			_draw_gun_ports(rect, hw if room["side"] == "starboard" else -hw)
		if scale.x > 0:  # letters would be mirrored on a flipped ship
			draw_string(font, rect.position + Vector2(3, 9), ROOM_LETTERS.get(room["type"], "?"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.35))

	for hole in _holes:
		draw_circle(hole, 2.5, Color("120c08"))

	var sail_width := lerpf(0.35, 1.0, sails_ratio) * (hw * 2.0 + 24.0)
	for y in mast_ys:
		draw_rect(Rect2(-sail_width / 2.0, y - 4, sail_width, 8), Color(sail_color, 0.85))
		draw_circle(Vector2(0, y), 3.0, Color("3b2a1a"))
	for hole in _sail_holes:
		draw_circle(hole, 1.5, Color("3b3a36"))
	if not mast_ys.is_empty():
		draw_rect(Rect2(-4, mast_ys[0] - 12, 8, 5), flag_color)

	for c: BattleCrew in crew:
		if not c.alive:
			continue
		draw_circle(c.pos, 4.0, Color("111111"))
		draw_circle(c.pos, 3.0, c.color)
		if c == selected:
			draw_arc(c.pos, 6.5, 0, TAU, 16, Color.WHITE, 1.0)


func _draw_gun_ports(rect: Rect2, x: float) -> void:
	for i in guns_per_side:
		var y := lerpf(rect.position.y + 6, rect.end.y - 6, (i + 0.5) / guns_per_side)
		draw_rect(Rect2(x - 2, y - 2, 4, 4), Color("1a120b"))


# --- Geometry -------------------------------------------------------------

func half_width() -> float:
	return _grid.x / 2.0 + HULL_MARGIN


## Where gun `index` of `count` fires from on the starboard side, in local space.
func muzzle_point(index: int, count: int) -> Vector2:
	var rect := gun_room("starboard").get("rect", Rect2()) as Rect2
	var y := lerpf(rect.position.y + 6, rect.end.y - 6, (index + 0.5) / maxf(1.0, count))
	return Vector2(half_width() + 2, y)


## A random point inside a random room, for a hit, in local space.
func random_hit_point() -> Vector2:
	var rect: Rect2 = rooms.pick_random()["rect"]
	rect = rect.grow(-4)
	return Vector2(randf_range(rect.position.x, rect.end.x), randf_range(rect.position.y, rect.end.y))


## A random point on the sails, for chain shot, in local space.
func random_sail_point() -> Vector2:
	var y: float = mast_ys.pick_random() if not mast_ys.is_empty() else 0.0
	var half := lerpf(0.35, 1.0, sails_ratio) * (half_width() + 12.0) - 3.0
	return Vector2(randf_range(-half, half), y + randf_range(-3, 3))


func gun_room(side: String) -> Dictionary:
	for room in rooms:
		if room["type"] == "guns" and room["side"] == side:
			return room
	return {}


func room_by_id(id: String) -> Dictionary:
	for room in rooms:
		if room["id"] == id:
			return room
	return {}


func room_at(local_point: Vector2) -> Dictionary:
	for room in rooms:
		if (room["rect"] as Rect2).has_point(local_point):
			return room
	return {}


## The middle of every grid cell in a room: where crew can stand.
func cells_of(room: Dictionary) -> Array[Vector2]:
	var cells: Array[Vector2] = []
	var rect: Rect2 = room["rect"]
	var cols := int(rect.size.x / CELL)
	var rows := int(rect.size.y / CELL)
	for row in rows:
		for col in cols:
			cells.append(rect.position + Vector2(col + 0.5, row + 0.5) * CELL)
	return cells


func crew_at(local_point: Vector2) -> BattleCrew:
	for c: BattleCrew in crew:
		if c.alive and c.pos.distance_to(local_point) <= 6.0:
			return c
	return null


func add_hole(local_point: Vector2) -> void:
	_holes.append(local_point.round())
	if _holes.size() > MAX_HOLES:
		_holes.pop_front()


func add_sail_hole(local_point: Vector2) -> void:
	_sail_holes.append(local_point.round())
	if _sail_holes.size() > MAX_HOLES:
		_sail_holes.pop_front()
