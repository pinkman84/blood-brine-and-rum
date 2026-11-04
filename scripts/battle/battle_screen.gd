extends Node
## Battle: your ship and one enemy, seen from above, trade broadsides in
## pausable real time.
##
## Hands (a number, not people you click) work the whole ship. The share of
## hands left scales every timing: reloads, firefighting, plugging, repairs.
## Specialists are the crew you move. Each buffs the hands in the room they
## stand in (see "buffs" in data/crew): a master gunner at the engaged guns
## speeds reloads and improves aim, a helmsman at the helm adds dodge, a
## carpenter doubles damage-control work in their room.
##
## Each broadside reloads on its own, but only the side facing the enemy can
## fire. Coming about swings the ship round to bring the other side to bear:
## no firing while turning, dodge is halved, and a hit taken mid-turn rakes
## the stern for double damage. A helmsman makes turns faster and less likely
## to stall halfway.
##
## Either side can make sail to escape: an escape bar fills while the fight
## goes on, faster with more canvas than the pursuer. Below a third of her
## sails a ship can't run at all, which is what chain shot is for.
##
## A ship that loses its hull sinks; one that loses all its hands strikes
## its colours. Controls: SPACE pause, F arm the next broadside, C come about,
## R make sail, click a specialist then a room to move them, right-click to
## deselect.

const PLAYER_POS := Vector2(200, 200)
const ENEMY_POS := Vector2(470, 200)
const BASE_TURN_TIME := 8.0  # seconds to come about with full hands and no helmsman
const BASE_STALL_CHANCE := 0.3  # chance a turn hangs halfway without a helmsman
const FLEE_TIME := 25.0  # seconds to escape when as fast as the pursuer
const MIN_FLEE_SAILS := 0.3  # below this share of sails a ship can't run
const ESCAPE_DECAY := 0.02  # escape lost per second while she can't run
const FLEE_DRIFT := 40.0  # pixels a fleeing ship pulls away by the time she escapes
const HEATED_MISHAP := 0.12  # chance per heated-shot volley of a fire on your own gun deck
const AI_TURN_AFTER_VOLLEY := 0.3  # chance the enemy comes about after firing, if the other side is ready
const WATER_COLOR := Color("2f5a73")
const SINK_TIME := 2.5
const CARPENTER_REPAIR := 3  # hull each carpenter patches after a win
const BOSUN_MEND := 5  # sails each bosun mends after a win
const HANDS_MEND := 5  # sails the hands mend after a win anyway
const STRUCK_GOLD := 1.5  # capturing a ship pays more than sinking it
const HEAL_AFTER_BATTLE := 20  # health every surviving specialist recovers after a win
const SURGEON_AFTER_BATTLE := 20  # extra if a surgeon survived
const LOG_TIME := 4.0

var player: BattleShip
var enemy: BattleShip
var player_crew: Array = []  # BattleCrew
var enemy_crew: Array = []

var _enemy_data: Dictionary
var _over := false
var _selected: BattleCrew = null

var _arena: Node2D
var _vfx: BattleVfx
var _player_view: ShipView
var _enemy_view: ShipView

var _player_status: Label
var _player_hull_bar: ProgressBar
var _player_sails_bar: ProgressBar
var _player_reload_bar: ProgressBar
var _player_reload_other: ProgressBar
var _enemy_status: Label
var _enemy_hull_bar: ProgressBar
var _enemy_sails_bar: ProgressBar
var _enemy_reload_bar: ProgressBar
var _enemy_reload_other: ProgressBar
var _turn_button: Button
var _flee_button: Button
var _player_escape_bar: ProgressBar
var _enemy_escape_bar: ProgressBar
var _crew_buttons: Dictionary = {}  # BattleCrew -> Button
var _crew_group := ButtonGroup.new()
var _fire_button: Button
var _auto_fire: CheckBox
var _ammo_select: OptionButton
var _pause_label: Label
var _result_box: CenterContainer
var _result_label: Label
var _result_button: Button
var _log_label: Label
var _log_timer: SceneTreeTimer
var _fallen: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # input works while paused; the arena below pauses
	var run: RunState = GameState.run
	var ship_data := Data.get_item("ships", run.ship_id)
	_enemy_data = _pick_enemy(run.sea_number)
	player = BattleShip.from_run(run, ship_data)
	enemy = BattleShip.from_enemy(_enemy_data)
	for side: String in BattleShip.SIDES:  # so the first volleys don't land together
		enemy.reloads[side] = randf() * 3.0
	_build_arena(ship_data)
	player.init_rooms(_player_view.rooms)
	enemy.init_rooms(_enemy_view.rooms)
	_player_view.room_states = player.rooms
	_enemy_view.room_states = enemy.rooms
	player_crew = _place_crew(_player_view, run.crew)
	enemy_crew = _place_crew(_enemy_view, _enemy_crew_entries())
	_player_view.crew = player_crew
	_enemy_view.crew = enemy_crew
	_build_ui()
	_update_stations()
	_refresh_ui()


func _exit_tree() -> void:
	get_tree().paused = false


func _process(delta: float) -> void:
	if _over or get_tree().paused:
		return
	for c: BattleCrew in player_crew + enemy_crew:
		c.step(delta)
	DamageControl.tick(player, _player_view, player_crew, delta)
	DamageControl.tick(enemy, _enemy_view, enemy_crew, delta)
	DamageControl.tick_crew(player, _player_view, player_crew, delta)
	DamageControl.tick_crew(enemy, _enemy_view, enemy_crew, delta)
	_report_deaths()
	_check_end()
	if _over:
		_refresh_ui()
		return
	_update_stations()
	player.tick(delta)
	enemy.tick(delta)
	_tick_turn(player, _player_view, delta)
	_tick_turn(enemy, _enemy_view, delta)
	_tick_flight(player, enemy, _player_view, PLAYER_POS.x, -1.0, delta)
	_tick_flight(enemy, player, _enemy_view, ENEMY_POS.x, 1.0, delta)
	if _over:
		_refresh_ui()
		return
	_enemy_think()
	if player.can_fire() and (player.armed or player.auto_fire):
		_fire(player, enemy, _player_view, _enemy_view)
	if enemy.can_fire():
		_fire(enemy, player, _enemy_view, _player_view)
		if not enemy.turning and enemy.is_loaded(enemy.other_side()) and randf() < AI_TURN_AFTER_VOLLEY:
			_come_about(enemy, _enemy_view, enemy_crew)
	_refresh_ui()


func _unhandled_input(event: InputEvent) -> void:
	if _over:
		return
	if event is InputEventMouseMotion:
		var hovered := _player_view.room_at(_player_view.get_local_mouse_position())
		_player_view.hover_room_id = str(hovered.get("id", "")) if _selected != null else ""
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		if click.button_index == MOUSE_BUTTON_LEFT:
			_on_ship_clicked(_player_view.get_local_mouse_position())
		elif click.button_index == MOUSE_BUTTON_RIGHT:
			_select(null)
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE:
		_toggle_pause()
	elif key.keycode == KEY_F:
		_on_fire_pressed()
	elif key.keycode == KEY_C:
		_on_turn_pressed()
	elif key.keycode == KEY_R:
		_on_flee_pressed()
	else:
		return
	get_viewport().set_input_as_handled()


# --- Crew -----------------------------------------------------------------

func _enemy_crew_entries() -> Array:
	var names: Array = Data.get_item("names", "crew_names").get("values", ["Sailor"])
	var entries: Array = []
	for role: Variant in _enemy_data.get("crew", []):
		entries.append({"name": str(names.pick_random()), "role": str(role), "level": 1})
	return entries


## Puts each specialist back at the post they held at the end of the last
## battle, or else at their trained station, or else anywhere free.
func _place_crew(view: ShipView, members: Array) -> Array:
	var placed: Array = []
	for m: Dictionary in members:
		var c := BattleCrew.new()
		c.crew_name = str(m.get("name", ""))
		c.role = str(m.get("role", ""))
		c.level = int(m.get("level", 1))
		c.health = float(m.get("health", BattleCrew.MAX_HEALTH))
		c.source = m
		c.color = Color.from_string(str(Data.get_item("crew", c.role).get("color", "")), Color.WHITE)
		var room: Dictionary = {}
		var post := view.room_by_id(str(m.get("post", "")))
		if not post.is_empty() and _free_cell(view, post, placed, null) != null:
			room = post
		if room.is_empty():
			room = _station_room(view, c.station(), placed)
		if room.is_empty():
			for r in view.rooms:
				if _free_cell(view, r, placed, null) != null:
					room = r
					break
		var cell: Vector2 = Vector2.ZERO
		if not room.is_empty():
			cell = _free_cell(view, room, placed, null)
		c.room_id = str(room.get("id", ""))
		c.pos = cell
		c.target = cell
		placed.append(c)
	return placed


func _station_room(view: ShipView, station: String, crew: Array) -> Dictionary:
	if station == "guns":
		var guns := view.gun_room("starboard")  # every battle starts starboard side on
		if not guns.is_empty() and _free_cell(view, guns, crew, null) != null:
			return guns
	for room in view.rooms:
		if room["type"] == station and _free_cell(view, room, crew, null) != null:
			return room
	return {}


## A spot in the room nobody is standing on or heading to. Null if the room is full.
func _free_cell(view: ShipView, room: Dictionary, crew: Array, mover: BattleCrew) -> Variant:
	for cell in view.cells_of(room):
		var taken := false
		for c: BattleCrew in crew:
			if c != mover and c.alive and c.target.distance_to(cell) < 1.0:
				taken = true
				break
		if not taken:
			return cell
	return null


func _on_ship_clicked(local_point: Vector2) -> void:
	var clicked := _player_view.crew_at(local_point)
	if clicked != null:
		_select(clicked)
		return
	var room := _player_view.room_at(local_point)
	if _selected != null and not room.is_empty():
		_send(_selected, room)


func _send(c: BattleCrew, room: Dictionary) -> void:
	if c.room_id == room["id"]:
		return
	var cell: Variant = _free_cell(_player_view, room, player_crew, c)
	if cell == null:
		return  # room is full
	c.room_id = room["id"]
	c.target = cell
	_refresh_ui()


func _select(c: BattleCrew) -> void:
	if c != null and not c.alive:
		c = null
	_selected = c
	_player_view.selected = c
	if c == null:
		var pressed := _crew_group.get_pressed_button()
		if pressed != null:
			pressed.button_pressed = false
		_player_view.hover_room_id = ""
	elif _crew_buttons.has(c):
		(_crew_buttons[c] as Button).button_pressed = true


## Specialists standing (not walking) in a room of this type, on this side.
func _specialists_at(view: ShipView, crew: Array, room_type: String, side := "") -> Array:
	var found: Array = []
	for c: BattleCrew in crew:
		if not c.alive or c.is_moving():
			continue
		var room := view.room_by_id(c.room_id)
		if room.get("type", "") == room_type and (side == "" or room.get("side", "") == side):
			found.append(c)
	return found


## How well a room works: its damage, fire and flooding.
func _room_efficiency(ship: BattleShip, room: Dictionary) -> float:
	if room.is_empty():
		return 0.0
	return DamageControl.efficiency(ship.rooms[room["id"]])


func _update_stations() -> void:
	_apply_stations(player, _player_view, player_crew)
	_apply_stations(enemy, _enemy_view, enemy_crew)


func _apply_stations(ship: BattleShip, view: ShipView, crew: Array) -> void:
	var hands := ship.hands_ratio()

	# Guns: hands load both broadsides; each gun deck's condition and any master
	# gunner standing in it matter. A damaged magazine slows the powder supply,
	# down to half speed when wrecked. Aim comes from gunners on the side firing.
	var powder := 1.0
	for room in view.rooms:
		if room["type"] == "magazine":
			powder *= lerpf(0.5, 1.0, _room_efficiency(ship, room))
	var aim_bonus := 0.0
	for side: String in BattleShip.SIDES:
		var reload_buff := 1.0
		for c: BattleCrew in _specialists_at(view, crew, "guns", side):
			reload_buff *= c.buff("reload")
			if side == ship.engaged_side:
				aim_bonus += c.buff("accuracy", 0.0)
		ship.gun_factors[side] = hands * _room_efficiency(ship, view.gun_room(side)) * reload_buff * powder
	ship.accuracy = ship.base_accuracy + aim_bonus

	# Dodging: the helm's condition, specialists at the helm and in the rigging,
	# and enough hands to work the sails (half as nimble with none).
	var helm_room: Dictionary = {}
	for room in view.rooms:
		if room["type"] == "helm":
			helm_room = room
	var dodge_buff := 1.0
	for c: BattleCrew in _specialists_at(view, crew, "helm") + _specialists_at(view, crew, "sails"):
		dodge_buff *= c.buff("evasion")
	ship.helm_factor = _room_efficiency(ship, helm_room) * dodge_buff * lerpf(0.5, 1.0, hands)


# --- Combat ---------------------------------------------------------------

func _pick_enemy(sea: int) -> Dictionary:
	var all: Array = Data.get_all("enemies")
	var options := all.filter(func(e: Dictionary) -> bool: return int(e.get("min_sea", 1)) <= sea)
	if options.is_empty():
		options = all
	return options.pick_random()


# --- Coming about -----------------------------------------------------------

## Orders a ship to come about. Turn speed and the chance of stalling come
## from the helm's condition, the hands, and any helmsman at the helm.
func _come_about(ship: BattleShip, view: ShipView, crew: Array) -> void:
	if ship.turning:
		return
	var helm_room: Dictionary = {}
	for room in view.rooms:
		if room["type"] == "helm":
			helm_room = room
	var turn_buff := 1.0
	for c: BattleCrew in _specialists_at(view, crew, "helm"):
		turn_buff *= c.buff("turn")
	var speed := turn_buff * lerpf(0.5, 1.0, ship.hands_ratio()) * maxf(0.25, _room_efficiency(ship, helm_room))
	var stall_chance := BASE_STALL_CHANCE / (1.0 + (turn_buff - 1.0) * 4.0)
	ship.start_turn(BASE_TURN_TIME / speed, stall_chance)
	if ship == player:
		_log("Hands to the braces! Coming about.")


func _tick_turn(ship: BattleShip, view: ShipView, delta: float) -> void:
	var event := ship.tick_turn(delta)
	view.rotation = ship.facing_angle()
	if event == "stalled":
		_log("We're in irons!" if ship == player else "She's hung up in irons! Rake her!")
	elif event == "done" and ship == player:
		_log("%s guns bearing." % ship.engaged_side.capitalize())


## Enemy captains come about when the guns facing you are wrecked or out of
## action and the other side is ready (they also sometimes turn after a volley).
func _enemy_think() -> void:
	if not enemy.fleeing and enemy.flees_at > 0.0 and enemy.hull_ratio() <= enemy.flees_at \
			and enemy.sails_ratio() >= MIN_FLEE_SAILS:
		enemy.fleeing = true
		_log("She's making sail to run! Chain shot her rigging!")
	if enemy.turning or not enemy.is_loaded(enemy.other_side()):
		return
	var facing := _room_efficiency(enemy, _enemy_view.gun_room(enemy.engaged_side))
	if facing <= 0.34 or enemy.gun_factor() <= 0.01:
		_come_about(enemy, _enemy_view, enemy_crew)


# --- Running away -----------------------------------------------------------

## Fills a fleeing ship's escape bar. `away` is the direction she pulls off in.
func _tick_flight(ship: BattleShip, pursuer: BattleShip, view: ShipView, start_x: float, away: float, delta: float) -> void:
	if ship.fleeing and not ship.turning:
		if ship.sails_ratio() < MIN_FLEE_SAILS:
			ship.escape = maxf(0.0, ship.escape - ESCAPE_DECAY * delta)
		else:
			var edge := clampf(ship.speed() / maxf(0.25, pursuer.speed()), 0.3, 2.0)
			ship.escape = minf(1.0, ship.escape + edge / FLEE_TIME * delta)
	elif not ship.fleeing:
		ship.escape = maxf(0.0, ship.escape - ESCAPE_DECAY * delta)
	view.base_position.x = start_x + away * FLEE_DRIFT * ship.escape
	if ship.escape >= 1.0 and not _over:
		_over = true
		_select(null)
		var tween := _arena.create_tween()
		tween.tween_property(view, "modulate:a", 0.0, 1.0)
		if ship == player:
			get_tree().create_timer(1.0, false).timeout.connect(_show_escape.bind(true))
		else:
			get_tree().create_timer(1.0, false).timeout.connect(_show_escape.bind(false))


func _on_flee_pressed() -> void:
	if _over:
		return
	if not player.fleeing and player.sails_ratio() < MIN_FLEE_SAILS:
		_log("Not enough canvas left to run!")
		return
	player.fleeing = not player.fleeing
	_log("All hands, make sail! We're running." if player.fleeing else "Belay that, we stand and fight!")
	_refresh_ui()


func _on_turn_pressed() -> void:
	if not _over:
		_come_about(player, _player_view, player_crew)
		_refresh_ui()


func _fire(shooter: BattleShip, target: BattleShip, from_view: ShipView, to_view: ShipView) -> void:
	var ammo_id := shooter.selected_ammo
	var high := BattleShip.aims_high(ammo_id)
	var hits := shooter.fire(target.evasion())
	if ammo_id == "heated_shot":
		var crew := player_crew if shooter == player else enemy_crew
		var careful := not _specialists_at(from_view, crew, "guns", shooter.engaged_side).is_empty()
		if randf() < HEATED_MISHAP * (0.5 if careful else 1.0):
			var deck := from_view.gun_room(shooter.engaged_side)
			if not deck.is_empty():
				DamageControl.ignite(shooter.rooms[deck["id"]])
				if shooter == player:
					_log("A hot shot rolls loose! Fire on the gun deck!")
	var dir := signf(to_view.base_position.x - from_view.base_position.x)
	for i in hits.size():
		var from := from_view.transform * from_view.muzzle_point(shooter.engaged_side, i, hits.size())
		var delay := i * 0.09
		if hits[i]:
			var local_hit := to_view.random_sail_point() if high else to_view.random_hit_point()
			var to := to_view.transform * local_hit
			_vfx.fire_shot(from, to, delay, _on_hit.bind(target, to_view, local_hit, ammo_id, high))
		else:
			var splash_at := to_view.base_position + Vector2(-dir * randf_range(60.0, 85.0), randf_range(-90.0, 90.0))
			_vfx.fire_shot(from, splash_at, delay, _vfx.splash.bind(splash_at))


func _on_hit(target: BattleShip, view: ShipView, local_hit: Vector2, ammo_id: String, high: bool) -> void:
	if target.take_hit(ammo_id):
		_vfx.shake(5.0)
		_log("Raked! A shot down the length of the deck." if target == player else "You rake her stern!")
	view.sails_ratio = target.sails_ratio()
	if high:
		view.add_sail_hole(local_hit)
		_vfx.sail_hit(view.transform * local_hit)
	else:
		view.add_hole(local_hit)
		_vfx.impact(view.transform * local_hit)
		var room := view.room_at(local_hit)
		if not room.is_empty():
			DamageControl.on_hit(target, room, ammo_id)
			DamageControl.wound_room(player_crew if target == player else enemy_crew, room["id"], ammo_id)
			_report_deaths()
	view.add_hands_lost(target.hands_ratio())
	_check_end()
	_refresh_ui()


func _check_end() -> void:
	if _over:
		return
	if enemy.hull <= 0:
		_over = true
		_sink(_enemy_view)
		get_tree().create_timer(SINK_TIME, false).timeout.connect(_show_victory.bind(false))
	elif enemy.hands <= 0:
		_over = true
		_select(null)
		_enemy_view.strike_colours()
		get_tree().create_timer(1.0, false).timeout.connect(_show_victory.bind(true))
	elif player.hull <= 0:
		_over = true
		_sink(_player_view)
		get_tree().create_timer(SINK_TIME, false).timeout.connect(_show_defeat.bind("Your ship goes down with all hands."))
	elif player.hands <= 0:
		_over = true
		_select(null)
		_player_view.strike_colours()
		get_tree().create_timer(1.0, false).timeout.connect(_show_defeat.bind("No hands left to fight her. You strike your colours."))


func _sink(view: ShipView) -> void:
	_select(null)
	var tween := _arena.create_tween().set_parallel()
	tween.tween_property(view, "scale", view.scale * 0.8, SINK_TIME).set_ease(Tween.EASE_IN)
	tween.tween_property(view, "rotation", view.rotation + 0.25 * signf(view.scale.x), SINK_TIME)
	tween.tween_property(view, "modulate", Color(0.4, 0.5, 0.6, 0.0), SINK_TIME).set_ease(Tween.EASE_IN)
	for i in 4:
		var at := view.transform * view.random_hit_point()
		get_tree().create_timer(i * 0.35, false).timeout.connect(_vfx.impact.bind(at))


func _show_victory(captured: bool) -> void:
	var run: RunState = GameState.run
	var gold := int(_enemy_data.get("gold_reward", 10))
	if captured:
		gold = roundi(gold * STRUCK_GOLD)
	var patched := _write_back(true)
	run.gold += gold
	run.battles_won += 1
	var headline := "The %s strikes her colours! Prize taken." if captured else "The %s goes down!"
	var text := (headline % enemy.display_name) + "\n+%d gold. Hull patched %d, sails mended %d. Hands left: %d." % [
		gold, patched["repair"], patched["mend"], player.hands]
	if not _fallen.is_empty():
		text += "\nLost: " + ", ".join(_fallen) + "."
	_show_result(text, "Return to the map", GameState.finish_node)


## Someone got away. Nobody is paid and nothing is mended; the damage stays.
func _show_escape(we_ran: bool) -> void:
	_write_back(false)
	var text := "You slip away under full sail." if we_ran else "The %s escapes into the haze." % enemy.display_name
	text += "\nHull %d/%d. Hands left: %d." % [player.hull, player.max_hull, player.hands]
	if not _fallen.is_empty():
		text += "\nLost: " + ", ".join(_fallen) + "."
	_show_result(text, "Return to the map", GameState.finish_node)


## Saves the battle's results to the run: surviving specialists (with their
## health and posts), hull, sails, hands and ammo. After a win, carpenters
## patch the hull, the hands and bosuns mend sails, and the wounded recover.
func _write_back(won: bool) -> Dictionary:
	var run: RunState = GameState.run
	var survivors := player_crew.filter(func(c: BattleCrew) -> bool: return c.alive)
	var repair := 0
	var mend := 0
	var recovery := 0
	if won:
		repair = survivors.filter(func(c: BattleCrew) -> bool: return c.role == "carpenter").size() * CARPENTER_REPAIR
		mend = HANDS_MEND + survivors.filter(func(c: BattleCrew) -> bool: return c.role == "bosun").size() * BOSUN_MEND
		var has_surgeon := survivors.any(func(c: BattleCrew) -> bool: return c.role == "surgeon")
		recovery = HEAL_AFTER_BATTLE + (SURGEON_AFTER_BATTLE if has_surgeon else 0)
	var kept: Array[Dictionary] = []
	for c: BattleCrew in survivors:
		c.heal(recovery)
		c.source["health"] = roundi(c.health)
		c.source["post"] = c.room_id  # they start the next battle here
		kept.append(c.source)
	run.crew = kept
	run.hull = mini(run.max_hull, player.hull + repair)
	run.sails = mini(run.max_sails, player.sails + mend)
	run.hands = player.hands
	run.ammo = player.ammo
	return {"repair": repair, "mend": mend}


## Announces specialists who died since the last check, on both ships.
func _report_deaths() -> void:
	for c: BattleCrew in player_crew + enemy_crew:
		if c.alive or c.death_reported:
			continue
		c.death_reported = true
		var ours := player_crew.has(c)
		if ours:
			_fallen.append("%s (%s)" % [c.crew_name, c.role_name()])
			if c == _selected:
				_select(null)
			if _crew_buttons.has(c):
				(_crew_buttons[c] as Button).disabled = true
			_log("%s the %s has fallen!" % [c.crew_name, c.role_name().to_lower()])
		else:
			_log("Their %s is down." % c.role_name().to_lower())


func _log(text: String) -> void:
	_log_label.text = text
	_log_label.visible = true
	_log_timer = get_tree().create_timer(LOG_TIME)
	_log_timer.timeout.connect(_hide_log.bind(_log_timer))


# Only the newest message's timer hides the label.
func _hide_log(timer: SceneTreeTimer) -> void:
	if timer == _log_timer:
		_log_label.visible = false


func _show_defeat(text: String) -> void:
	_show_result(text, "Abandon ship", GameState.end_run.bind(false))


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

func _build_arena(ship_data: Dictionary) -> void:
	_arena = Node2D.new()
	_arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_arena)
	var sea := ColorRect.new()
	sea.color = WATER_COLOR
	sea.position = Vector2(-32, -32)
	sea.size = Vector2(704, 424)
	sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(sea)
	_player_view = _add_ship(ship_data, PLAYER_POS, false, player)
	_enemy_view = _add_ship(_enemy_data, ENEMY_POS, true, enemy)
	_vfx = BattleVfx.new()
	_vfx.shake_target = _arena
	_arena.add_child(_vfx)


func _add_ship(data: Dictionary, pos: Vector2, flipped: bool, ship: BattleShip) -> ShipView:
	var view := ShipView.new()
	view.setup(data)
	view.sails_ratio = ship.sails_ratio()
	view.base_position = pos
	view.position = pos
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

	var column := _vbox(margin)

	# Top: both ships' hull, sails and reload.
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var left := _vbox(top)
	_add_label(left, player.display_name)
	_player_status = _add_label(left, "")
	_player_hull_bar = _add_bar(left, Color("c0392b"))
	_player_sails_bar = _add_bar(left, Color("ecf0f1"))
	_player_reload_bar = _add_bar(left, Color("f1c40f"))
	_player_reload_other = _add_bar(left, Color("8a7a2a"))
	_player_escape_bar = _add_bar(left, Color("5dade2"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	var right := _vbox(top)
	var enemy_name := _add_label(right, enemy.display_name)
	enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_status = _add_label(right, "")
	_enemy_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_hull_bar = _add_bar(right, Color("c0392b"))
	_enemy_sails_bar = _add_bar(right, Color("ecf0f1"))
	_enemy_reload_bar = _add_bar(right, Color("f1c40f"))
	_enemy_reload_other = _add_bar(right, Color("8a7a2a"))
	_enemy_escape_bar = _add_bar(right, Color("5dade2"))

	# Left: the crew roster. Click a name to select, then click a room.
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(middle)
	var roster := _vbox(middle)
	roster.add_theme_constant_override("separation", 2)
	for c: BattleCrew in player_crew:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _crew_group
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(108, 0)
		button.add_theme_color_override("font_color", c.color)
		button.pressed.connect(_select.bind(c))
		roster.add_child(button)
		_crew_buttons[c] = button

	# Bottom: orders.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	_fire_button = Button.new()
	_fire_button.focus_mode = Control.FOCUS_NONE
	_fire_button.custom_minimum_size = Vector2(150, 0)
	_fire_button.pressed.connect(_on_fire_pressed)
	bottom.add_child(_fire_button)
	_turn_button = Button.new()
	_turn_button.focus_mode = Control.FOCUS_NONE
	_turn_button.custom_minimum_size = Vector2(110, 0)
	_turn_button.pressed.connect(_on_turn_pressed)
	bottom.add_child(_turn_button)
	_flee_button = Button.new()
	_flee_button.focus_mode = Control.FOCUS_NONE
	_flee_button.custom_minimum_size = Vector2(90, 0)
	_flee_button.pressed.connect(_on_flee_pressed)
	bottom.add_child(_flee_button)
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
	_add_label(bottom, "SPACE pause  F fire  C turn  R run")

	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 12)
	_log_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_log_label.offset_top = -52
	_log_label.offset_bottom = -36
	_log_label.offset_left = -200
	_log_label.offset_right = 200
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_label.visible = false
	root.add_child(_log_label)

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


func _vbox(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box


func _add_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _add_bar(parent: Node, fill: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 5)
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
		# Ammo whose effects aren't built yet shows but can't be picked.
		_ammo_select.set_item_disabled(index, not BattleShip.WORKING_AMMO.has(ammo_id))
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
	_player_sails_bar.max_value = player.max_sails
	_player_sails_bar.value = player.sails
	_player_reload_bar.value = player.reload_ratio() * 100.0
	_player_reload_other.value = player.reload_ratio(player.other_side()) * 100.0
	_enemy_status.text = _status_text(enemy)
	_enemy_hull_bar.max_value = enemy.max_hull
	_enemy_hull_bar.value = enemy.hull
	_enemy_sails_bar.max_value = enemy.max_sails
	_enemy_sails_bar.value = enemy.sails
	_enemy_reload_bar.value = enemy.reload_ratio() * 100.0
	_enemy_reload_other.value = enemy.reload_ratio(enemy.other_side()) * 100.0

	_player_escape_bar.value = player.escape * 100.0
	_player_escape_bar.visible = player.escape > 0.0
	_enemy_escape_bar.value = enemy.escape * 100.0
	_enemy_escape_bar.visible = enemy.escape > 0.0
	_flee_button.disabled = _over
	if player.fleeing:
		_flee_button.text = "Stand and fight"
	else:
		_flee_button.text = "Make sail (R)"

	_turn_button.disabled = _over or player.turning
	if player.turning and player.stall_left > 0.0:
		_turn_button.text = "In irons!"
	elif player.turning:
		_turn_button.text = "Turning %d%%" % roundi(player.turn_progress * 100.0)
	else:
		_turn_button.text = "Come about (C)"

	for c: BattleCrew in _crew_buttons:
		var room := _player_view.room_by_id(c.room_id)
		var where := str(room.get("id", "")).replace("starboard", "stbd").replace("_", " ")
		if not c.alive:
			(_crew_buttons[c] as Button).text = "%s  DEAD" % c.crew_name
			continue
		if c.is_wounded():
			where = "wounded, " + where
		if c.is_moving():
			where = "moving"
		elif player.rooms.has(c.room_id):
			var busy := DamageControl.job(player.rooms[c.room_id])
			if busy != "":
				where = busy
		(_crew_buttons[c] as Button).text = "%s %d%%  %s" % [c.crew_name, roundi(c.health), where]

	var ammo_name := str(Data.get_item("ammo", player.selected_ammo).get("name", player.selected_ammo))
	_fire_button.disabled = _over or player.auto_fire or player.shots_available() == 0 or player.turning
	if player.turning:
		_fire_button.text = "Can't fire while turning"
	elif player.shots_available() == 0:
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
	var side := "Stbd" if ship.engaged_side == "starboard" else "Port"
	var guns := "%s guns ready" % side
	if ship.turning:
		guns = "COMING ABOUT"
	elif not ship.is_loaded():
		guns = "%s guns out of action" % side if ship.gun_factor() <= 0.0 else "%s loading %d%%" % [side, int(ship.reload_ratio() * 100.0)]
	if not ship.turning and ship.is_loaded(ship.other_side()):
		guns += " (other side ready)"
	if ship.fleeing:
		guns += "  RUNNING %d%%" % roundi(ship.escape * 100.0)
		if ship.sails_ratio() < MIN_FLEE_SAILS:
			guns += " (no canvas!)"
	var trouble := DamageControl.alerts(ship)
	if trouble != "":
		guns += "  " + trouble.to_upper()
	return "Hull %d/%d  Sails %d/%d  HANDS %d/%d\nDodge %d%%  %s" % [
		ship.hull, ship.max_hull, ship.sails, ship.max_sails, ship.hands, ship.max_hands,
		int(ship.evasion() * 100.0), guns]
