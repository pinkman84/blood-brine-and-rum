class_name ShipView
extends Node2D
## A ship drawn with plain shapes: hull, masts, sails, flag and a row of rooms.
## Placeholder until the pixel art is ready. The origin sits on the waterline;
## the bow points right. Flip an enemy with scale.x = -1.

const ROOMS_LEFT := -70.0
const ROOMS_RIGHT := 66.0
const ROOM_TOP := -36.0
const ROOM_BOTTOM := -8.0
const MAX_HOLES := 40

var hull_color := Color("6b4a2f")
var trim_color := Color("8a6440")
var room_color := Color("2e2118")
var sail_color := Color("e8dfc8")
var flag_color := Color("111111")
var rooms: Array = []
var base_position := Vector2.ZERO  # bobbing and sinking move around this

var _holes: Array[Vector2] = []
var _time := randf() * TAU


func setup(data: Dictionary) -> void:
	rooms = data.get("rooms", ["helm", "guns", "magazine"])
	hull_color = Color.from_string(str(data.get("hull_color", "")), hull_color)
	sail_color = Color.from_string(str(data.get("sail_color", "")), sail_color)
	flag_color = Color.from_string(str(data.get("flag_color", "")), flag_color)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	position = base_position + Vector2(0, roundf(sin(_time * 1.7) * 1.5))


func _draw() -> void:
	var mast_color := Color("3b2a1a")
	for mast_x: float in [-30.0, 34.0]:
		draw_line(Vector2(mast_x, -40), Vector2(mast_x, -128), mast_color, 3.0)
		draw_rect(Rect2(mast_x - 22, -120, 44, 30), sail_color)
		draw_rect(Rect2(mast_x - 18, -86, 36, 30), sail_color)
	draw_rect(Rect2(-44, -136, 14, 9), flag_color)

	var hull := PackedVector2Array([
		Vector2(-96, -50), Vector2(-60, -44), Vector2(70, -42),
		Vector2(104, -48), Vector2(88, 2), Vector2(-84, 2),
	])
	draw_colored_polygon(hull, hull_color)
	var outline := hull.duplicate()
	outline.append(hull[0])
	draw_polyline(outline, Color("2a1c10"), 1.0)

	var count := maxi(1, rooms.size())
	var width := (ROOMS_RIGHT - ROOMS_LEFT) / count
	for i in count:
		var room := Rect2(ROOMS_LEFT + i * width + 1, ROOM_TOP, width - 2, ROOM_BOTTOM - ROOM_TOP)
		draw_rect(room, room_color)
		draw_rect(room, trim_color, false, 1.0)

	for hole in _holes:
		draw_circle(hole, 2.5, Color("120c08"))


## Where gun number `index` of `count` fires from, in this ship's local space.
func muzzle_point(index: int, count: int) -> Vector2:
	var t := (index + 0.5) / maxf(1.0, count)
	return Vector2(94, lerpf(ROOM_TOP + 4, ROOM_BOTTOM - 4, t))


## A random point on the hull to land a hit, in local space.
func random_hit_point() -> Vector2:
	return Vector2(randf_range(-80, 85), randf_range(-44, -4))


func add_hole(local_point: Vector2) -> void:
	_holes.append(local_point.round())
	if _holes.size() > MAX_HOLES:
		_holes.pop_front()
	queue_redraw()
