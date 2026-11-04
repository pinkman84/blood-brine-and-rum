class_name BattleVfx
extends Node2D
## Placeholder battle effects: cannonballs, muzzle flash, smoke, hits,
## splashes and screen shake, built from CPUParticles2D. No art needed.
## If Kenney's Particle Pack is anywhere under res://assets/vfx/, its smoke
## and muzzle textures are picked up automatically.

const SHOT_TIME := 0.45
const ARC_HEIGHT := 18.0

var shake_target: Node2D

var _shake := 0.0
var _smoke_tex: Texture2D
var _flash_tex: Texture2D
var _add_material := CanvasItemMaterial.new()


func _ready() -> void:
	_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_smoke_tex = _find_texture("smoke")
	_flash_tex = _find_texture("muzzle")
	if _flash_tex == null:
		_flash_tex = _find_texture("flare")


func _process(delta: float) -> void:
	if shake_target == null:
		return
	_shake = maxf(0.0, _shake - delta * 20.0)
	shake_target.position = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)).round()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Fires a cannonball from `from` to `to` after `delay`, then calls on_arrive.
func fire_shot(from: Vector2, to: Vector2, delay: float, on_arrive: Callable) -> void:
	var ball := ColorRect.new()
	ball.color = Color("161616")
	ball.size = Vector2(3, 3)
	ball.visible = false
	ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ball)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(_launch.bind(ball, from, signf(to.x - from.x)))
	tween.tween_method(_move_ball.bind(ball, from, to), 0.0, 1.0, SHOT_TIME)
	tween.tween_callback(ball.queue_free)
	tween.tween_callback(on_arrive)


func muzzle_flash(pos: Vector2, dir: float) -> void:
	_burst(pos, Color(1.0, 0.85, 0.45), 8, 0.15, Vector2(dir, 0), 25.0, 70.0, Vector2.ZERO, 5.0, _flash_tex, true)
	_burst(pos, Color(0.9, 0.9, 0.9, 0.8), 10, 1.4, Vector2(dir, -0.3), 30.0, 28.0, Vector2(0, -12), 12.0, _smoke_tex, false)


func impact(pos: Vector2) -> void:
	_burst(pos, Color(1.0, 0.6, 0.2), 10, 0.2, Vector2(0, -1), 180.0, 60.0, Vector2.ZERO, 7.0, _flash_tex, true)
	_burst(pos, Color("6b4a2f"), 10, 0.7, Vector2(0, -1), 70.0, 100.0, Vector2(0, 260), 2.0, null, false)
	_burst(pos, Color(0.25, 0.22, 0.2, 0.8), 8, 1.6, Vector2(0, -1), 40.0, 18.0, Vector2(0, -10), 12.0, _smoke_tex, false)
	shake(3.0)


func sail_hit(pos: Vector2) -> void:
	_burst(pos, Color(0.95, 0.92, 0.85), 12, 0.9, Vector2(0, -1), 120.0, 50.0, Vector2(0, 60), 2.0, null, false)
	shake(1.5)


## Steel and pistol flashes where boarders are fighting.
func melee_clash(pos: Vector2) -> void:
	_burst(pos, Color(1.0, 0.95, 0.7), 6, 0.25, Vector2(0, -1), 180.0, 40.0, Vector2.ZERO, 2.0, null, true)


func splash(pos: Vector2) -> void:
	_burst(pos, Color(0.9, 0.95, 1.0), 16, 0.7, Vector2(0, -1), 18.0, 110.0, Vector2(0, 320), 2.0, null, false)


func _launch(ball: ColorRect, from: Vector2, dir: float) -> void:
	ball.visible = true
	muzzle_flash(from, dir)


func _move_ball(t: float, ball: ColorRect, from: Vector2, to: Vector2) -> void:
	ball.position = (from.lerp(to, t) + Vector2(0, -sin(t * PI) * ARC_HEIGHT) - ball.size / 2).round()


func _burst(pos: Vector2, color: Color, amount: int, lifetime: float, direction: Vector2,
		spread: float, speed: float, gravity: Vector2, size: float, tex: Texture2D, additive: bool) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lifetime
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = gravity
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	if tex != null:
		p.texture = tex
		p.scale_amount_min = size / tex.get_width() * 0.6
		p.scale_amount_max = size / tex.get_width()
	else:
		p.scale_amount_min = size * 0.5
		p.scale_amount_max = size
	if additive:
		p.material = _add_material
	add_child(p)
	p.emitting = true
	get_tree().create_timer(lifetime + 0.3, false).timeout.connect(p.queue_free)


func _find_texture(prefix: String) -> Texture2D:
	var path := _search("res://assets/vfx", prefix)
	if path.is_empty():
		return null
	return load(path) as Texture2D


func _search(dir_path: String, prefix: String) -> String:
	for file_name in DirAccess.get_files_at(dir_path):
		var png := file_name.trim_suffix(".import")
		if png.begins_with(prefix) and png.ends_with(".png"):
			return dir_path.path_join(png)
	for sub in DirAccess.get_directories_at(dir_path):
		var found := _search(dir_path.path_join(sub), prefix)
		if not found.is_empty():
			return found
	return ""
