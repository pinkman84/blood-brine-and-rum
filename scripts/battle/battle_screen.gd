extends Node
## Phase 1 battle: your ship and one enemy trade broadsides in pausable real time.
## SPACE pauses. F arms the next broadside (it fires as soon as the guns load).
## Ships and effects are drawn in code until the pixel art arrives.

const PLAYER_X := 160.0
const ENEMY_X := 480.0
const SHIP_Y := 252.0
const WATER_Y := 248.0
const SKY_COLOR := Color("8fb3c9")
const WATER_COLOR := Color("2f5a73")
const SINK_TIME := 2.5
const CARPENTER_REPAIR := 3  # hull each carpenter patches after a win

var player: BattleShip
var enemy: BattleShip

var _enemy_data: Dictionary
var _over := false

var _arena: Node2D
var _vfx: BattleVfx
var _player_view: ShipView
var _enemy_view: ShipView

var _player_status: Label
var _player_hull_bar: ProgressBar
var _player_reload_bar: ProgressBar
var _enemy_status: Label
var _enemy_hull_bar: ProgressBar
var _enemy_reload_bar: ProgressBar
var _fire_button: Button
var _auto_fire: CheckBox
var _ammo_select: OptionButton
var _pause_label: Label
var _result_box: CenterContainer
var _result_label: Label
var _result_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # input works while paused; the arena below pauses
	var run: RunState = GameState.run
	_enemy_data = _pick_enemy(run.sea_number)
	player = BattleShip.from_run(run, Data.get_item("ships", run.ship_id))
	enemy = BattleShip.from_enemy(_enemy_data)
	enemy.reload = randf() * 3.0  # so the first volleys don't land together
	_build_arena(run)
	_build_ui()
	_refresh_ui()


func _exit_tree() -> void:
	get_tree().paused = false


func _process(delta: float) -> void:
	if _over or get_tree().paused:
		return
	player.tick(delta)
	enemy.tick(delta)
	if player.is_loaded() and (player.armed or player.auto_fire) and player.shots_available() > 0:
		_fire(player, enemy, _player_view, _enemy_view)
	if enemy.is_loaded():
		_fire(enemy, player, _enemy_view, _player_view)
	_refresh_ui()


func _unhandled_input(event: InputEvent) -> void:
	if _over:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		_toggle_pause()
	elif key.keycode == KEY_F:
		_on_fire_pressed()
	else:
		return
	get_viewport().set_input_as_handled()


# --- Combat ---------------------------------------------------------------

func _pick_enemy(sea: int) -> Dictionary:
	var all: Array = Data.get_all("enemies")
	var options := all.filter(func(e: Dictionary) -> bool: return int(e.get("min_sea", 1)) <= sea)
	if options.is_empty():
		options = all
	return options.pick_random()


func _fire(shooter: BattleShip, target: BattleShip, from_view: ShipView, to_view: ShipView) -> void:
	var damage := shooter.damage_per_hit()
	var hits := shooter.fire()
	var dir := signf(to_view.base_position.x - from_view.base_position.x)
	for i in hits.size():
		var from := from_view.transform * from_view.muzzle_point(i, hits.size())
		var delay := i * 0.09
		if hits[i]:
			var local_hit := to_view.random_hit_point()
			var to := to_view.transform * local_hit
			_vfx.fire_shot(from, to, delay, _on_hit.bind(target, to_view, local_hit, damage))
		else:
			var splash_at := Vector2(to_view.base_position.x - dir * randf_range(70.0, 120.0), WATER_Y + randf_range(2.0, 10.0))
			_vfx.fire_shot(from, splash_at, delay, _vfx.splash.bind(splash_at))


func _on_hit(target: BattleShip, view: ShipView, local_hit: Vector2, damage: int) -> void:
	target.take_damage(damage)
	view.add_hole(local_hit)
	_vfx.impact(view.transform * local_hit)
	_check_end()
	_refresh_ui()


func _check_end() -> void:
	if _over:
		return
	if enemy.hull <= 0:
		_over = true
		_sink(_enemy_view)
		get_tree().create_timer(SINK_TIME, false).timeout.connect(_show_victory)
	elif player.hull <= 0:
		_over = true
		_sink(_player_view)
		get_tree().create_timer(SINK_TIME, false).timeout.connect(_show_defeat)


func _sink(view: ShipView) -> void:
	var tween := _arena.create_tween().set_parallel()
	tween.tween_property(view, "base_position:y", view.base_position.y + 150.0, SINK_TIME) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(view, "rotation", 0.3 * signf(view.scale.x), SINK_TIME)
	tween.tween_property(view, "modulate:a", 0.0, SINK_TIME).set_ease(Tween.EASE_IN)
	for i in 4:
		var at := view.transform * view.random_hit_point()
		get_tree().create_timer(i * 0.35, false).timeout.connect(_vfx.impact.bind(at))


func _show_victory() -> void:
	var run: RunState = GameState.run
	var gold := int(_enemy_data.get("gold_reward", 10))
	var carpenters := run.crew.filter(func(c: Dictionary) -> bool: return c.get("role") == "carpenter").size()
	var repair := carpenters * CARPENTER_REPAIR
	run.gold += gold
	run.battles_won += 1
	run.hull = mini(run.max_hull, player.hull + repair)
	run.ammo = player.ammo
	_show_result("The %s goes down!\n+%d gold. Carpenters patch %d hull." % [enemy.display_name, gold, repair],
		"Return to the map", GameState.finish_node)


func _show_defeat() -> void:
	_show_result("Your ship goes down with all hands.", "Abandon ship", GameState.end_run.bind(false))


# --- Controls -------------------------------------------------------------

func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	_pause_label.visible = get_tree().paused


func _on_fire_pressed() -> void:
	if player.shots_available() > 0 and not player.auto_fire:
		player.armed = not player.armed
	_refresh_ui()


func _on_auto_fire_toggled(on: bool) -> void:
	player.auto_fire = on
	_refresh_ui()


func _on_ammo_selected(index: int) -> void:
	player.selected_ammo = str(_ammo_select.get_item_metadata(index))
	_refresh_ui()


# --- Building the scene ---------------------------------------------------

func _build_arena(run: RunState) -> void:
	_arena = Node2D.new()
	_arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_arena)
	_add_rect(_arena, SKY_COLOR, Vector2(-32, -32), Vector2(704, WATER_Y + 32))
	_add_rect(_arena, WATER_COLOR, Vector2(-32, WATER_Y), Vector2(704, 160))
	_player_view = _add_ship(Data.get_item("ships", run.ship_id), PLAYER_X, false)
	_enemy_view = _add_ship(_enemy_data, ENEMY_X, true)
	# A strip of water in front of the hulls so the ships sit in the sea.
	_add_rect(_arena, Color(WATER_COLOR, 0.85), Vector2(-32, SHIP_Y - 4), Vector2(704, 160))
	_vfx = BattleVfx.new()
	_vfx.shake_target = _arena
	_arena.add_child(_vfx)


func _add_rect(parent: Node, color: Color, pos: Vector2, size: Vector2) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = pos
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


func _add_ship(data: Dictionary, x: float, flipped: bool) -> ShipView:
	var view := ShipView.new()
	view.setup(data)
	view.base_position = Vector2(x, SHIP_Y)
	view.position = view.base_position
	if flipped:
		view.scale.x = -1
	_arena.add_child(view)
	return view


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var theme := Theme.new()
	theme.default_font_size = 10
	theme.set_constant("outline_size", "Label", 3)
	theme.set_color("font_outline_color", "Label", Color.BLACK)

	var root := Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	# Top: both ships' hull and reload.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var left := VBoxContainer.new()
	top.add_child(left)
	_add_label(left, player.display_name)
	_player_status = _add_label(left, "")
	_player_hull_bar = _add_bar(left, Color("c0392b"))
	_player_reload_bar = _add_bar(left, Color("f1c40f"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	var right := VBoxContainer.new()
	top.add_child(right)
	var enemy_name := _add_label(right, enemy.display_name)
	enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_status = _add_label(right, "")
	_enemy_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_hull_bar = _add_bar(right, Color("c0392b"))
	_enemy_reload_bar = _add_bar(right, Color("f1c40f"))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	# Bottom: orders.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	column.add_child(bottom)
	_fire_button = Button.new()
	_fire_button.focus_mode = Control.FOCUS_NONE
	_fire_button.custom_minimum_size = Vector2(150, 0)
	_fire_button.pressed.connect(_on_fire_pressed)
	bottom.add_child(_fire_button)
	_ammo_select = OptionButton.new()
	_ammo_select.focus_mode = Control.FOCUS_NONE
	_fill_ammo_select()
	_ammo_select.item_selected.connect(_on_ammo_selected)
	bottom.add_child(_ammo_select)
	_auto_fire = CheckBox.new()
	_auto_fire.text = "Auto-fire"
	_auto_fire.focus_mode = Control.FOCUS_NONE
	_auto_fire.toggled.connect(_on_auto_fire_toggled)
	bottom.add_child(_auto_fire)
	_add_label(bottom, "SPACE pause   F fire")

	_pause_label = Label.new()
	_pause_label.text = "PAUSED"
	_pause_label.add_theme_font_size_override("font_size", 24)
	_pause_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_label.visible = false
	root.add_child(_pause_label)

	_result_box = CenterContainer.new()
	_result_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_box.visible = false
	root.add_child(_result_box)
	var panel := PanelContainer.new()
	_result_box.add_child(panel)
	var panel_column := VBoxContainer.new()
	panel_column.add_theme_constant_override("separation", 8)
	panel.add_child(panel_column)
	_result_label = _add_label(panel_column, "")
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_button = Button.new()
	_result_button.focus_mode = Control.FOCUS_NONE
	panel_column.add_child(_result_button)


func _add_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _add_bar(parent: Node, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	parent.add_child(bar)
	return bar


func _fill_ammo_select() -> void:
	_ammo_select.clear()
	for ammo_id: String in player.ammo:
		var index := _ammo_select.item_count
		_ammo_select.add_item("")
		_ammo_select.set_item_metadata(index, ammo_id)
		# Only round shot works until Phase 3 adds the special ammo effects.
		_ammo_select.set_item_disabled(index, ammo_id != "round_shot")
		if ammo_id == player.selected_ammo:
			_ammo_select.select(index)


func _show_result(text: String, button_text: String, action: Callable) -> void:
	get_tree().paused = false
	_pause_label.visible = false
	_result_label.text = text
	_result_button.text = button_text
	_result_button.pressed.connect(action, CONNECT_ONE_SHOT)
	_result_box.visible = true
	_refresh_ui()


# --- UI refresh -----------------------------------------------------------

func _refresh_ui() -> void:
	_player_status.text = _status_text(player)
	_player_hull_bar.max_value = player.max_hull
	_player_hull_bar.value = player.hull
	_player_reload_bar.value = player.reload_ratio() * 100.0
	_enemy_status.text = _status_text(enemy)
	_enemy_hull_bar.max_value = enemy.max_hull
	_enemy_hull_bar.value = enemy.hull
	_enemy_reload_bar.value = enemy.reload_ratio() * 100.0

	var ammo_name := str(Data.get_item("ammo", player.selected_ammo).get("name", player.selected_ammo))
	_fire_button.disabled = _over or player.auto_fire or player.shots_available() == 0
	if player.shots_available() == 0:
		_fire_button.text = "Out of %s" % ammo_name.to_lower()
	elif player.auto_fire:
		_fire_button.text = "Auto-firing"
	elif player.armed:
		_fire_button.text = "Armed: fires when loaded"
	else:
		_fire_button.text = "Fire broadside (F)"

	for i in _ammo_select.item_count:
		var ammo_id := str(_ammo_select.get_item_metadata(i))
		var label := str(Data.get_item("ammo", ammo_id).get("name", ammo_id))
		if BattleShip.is_free_ammo(ammo_id):
			_ammo_select.set_item_text(i, label)
		else:
			_ammo_select.set_item_text(i, "%s x%d" % [label, int(player.ammo.get(ammo_id, 0))])


func _status_text(ship: BattleShip) -> String:
	var guns := "Guns ready" if ship.is_loaded() else "Loading %d%%" % int(ship.reload_ratio() * 100.0)
	return "Hull %d/%d   %s" % [ship.hull, ship.max_hull, guns]
