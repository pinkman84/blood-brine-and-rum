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
## Grappling and boarding live in boarding.gd: hooks pull the ships together
## (better aim for both), all hooks fast lashes them alongside (guns silent,
## no running or turning), then the grappler may board with a party of hands.
##
## A ship that loses its hull sinks; one that loses all its hands strikes
## its colours. Controls: SPACE pause, F arm the next broadside, C come about,
## R make sail, G throw grapples or cut ropes, click a specialist then a room
## to move them, right-click to deselect.

const PLAYER_POS := Vector2(200, 200)
const STATUS_WIDTH := 290  # each ship's status column at the top; text wraps inside it
const ENEMY_POS := Vector2(470, 200)
const BASE_TURN_TIME := 8.0  # seconds to come about with full hands and no helmsman
const BASE_STALL_CHANCE := 0.3  # chance a turn hangs halfway without a helmsman
const FLEE_TIME := 25.0  # seconds to escape when as fast as the pursuer
const MIN_FLEE_SAILS := 0.3  # below this share of sails a ship can't run
const ESCAPE_DECAY := 0.02  # escape lost per second while she can't run
const FLEE_DRIFT := 40.0  # pixels a fleeing ship pulls away by the time she escapes
const HEATED_MISHAP := 0.12  # chance per heated-shot volley of a fire on your own gun deck
const AI_CREW_THINK := 1.5  # seconds between enemy crew decisions
const AI_WOUNDED := 35.0  # enemy specialists below this health head for the sickbay
const PULL_DISTANCE := 45.0  # pixels each ship moves inwards when fully lashed
const PARTY_SIZES := [0.33, 0.5, 1.0]  # shares of your hands you can send across
const PARTY_LABELS := ["a third", "half", "all hands"]
const AI_BOARD_DELAY := 1.5  # seconds an enemy captain waits once lashed before boarding
const PRISONER_RANSOM := 2  # gold per prisoner at a trading post
const RAID_HUNT := 15  # Company hunt for sacking a town
const RAID_MORALE := 5
const FORT_FALL_TIME := 3.0  # seconds of smoke and the banner before the result
const FORT_SMOKE_EVERY := 0.3  # a fallen fort keeps smouldering
const ELITE_BOOST := 1.3  # a sea's exit captain: this much more hull and hands
const ELITE_GOLD := 2.0
const SURVIVOR_SHARE := 0.4  # roughly this share of a sunk ship's hands can be pulled from the water
const DEBUG_BOARDING := true  # shows a "Lash now" test button (B key); set false to hide
const DEBUG_CHEATS := true  # shows a "God mode" test button (T key); set false to hide
const CHEAT_HULL := 999
const CHEAT_HANDS := 999
const CHEAT_RELOAD := 1.0  # seconds per broadside
const CHEAT_AMMO := 99
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
var _ui_root: Control  # the battle UI, for the fallen-fort banner
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
var _boarding := Boarding.new()
var _ai_board_wait := 0.0
var _ai_crew_t := 0.0
var _enemy_homes := {}  # BattleCrew -> room id they started the battle in
var _boarding_row: HBoxContainer
var _grapple_button: Button
var _board_buttons: Array[Button] = []
var _cut_loose_button: Button
var _fall_back_button: Button
var _debug_lash_button: Button
var _choice_buttons: Array[Button] = []
var _panel_column: VBoxContainer
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
var _start_hands := 0
var _intro_note := ""  # shown once the battle screen is built
var _elite_fight := false  # the sea's exit fight: richer plunder
var _can_parley := false  # an ordinary encounter: she might hail us first (see Reputation)
var _cheat_button: Button
static var _cheats_on := false  # testing: stays on for the rest of the session once pressed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # input works while paused; the arena below pauses
	var run: RunState = GameState.run
	var ship_data := Data.get_item("ships", run.ship_id)
	_enemy_data = _pick_enemy(run.sea_number)
	player = BattleShip.from_run(run, ship_data)
	if _cheats_on:
		_apply_cheats()
	_start_hands = player.hands
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
	for c: BattleCrew in enemy_crew:
		_enemy_homes[c] = c.room_id
	_player_view.crew = player_crew
	_enemy_view.crew = enemy_crew
	_build_ui()
	_update_stations()
	_refresh_ui()
	if _intro_note != "":
		_log(_intro_note)
	_hail()


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
	_boarding.tick(delta)
	_tick_melee(delta)
	if _over:
		_refresh_ui()
		return
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
	_enemy_board_think(delta)
	_enemy_crew_think(delta)
	var guns_free := not _boarding.guns_silent()
	if guns_free and player.can_fire() and (player.armed or player.auto_fire):
		_fire(player, enemy, _player_view, _enemy_view)
	if guns_free and enemy.can_fire():
		enemy.selected_ammo = _enemy_pick_ammo()
		_fire(enemy, player, _enemy_view, _player_view)
		var turn_chance := float(enemy.ai.get("turn_after_volley", 0.3))
		if not enemy.turning and enemy.is_loaded(enemy.other_side()) and randf() < turn_chance:
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
	elif key.keycode == KEY_G:
		_on_grapple_pressed()
	elif key.keycode == KEY_B and DEBUG_BOARDING:
		_on_debug_lash_pressed()
	elif key.keycode == KEY_T and DEBUG_CHEATS:
		_on_cheat_pressed()
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
	if _send_on(_player_view, player_crew, c, room):
		_refresh_ui()


## Moves a specialist on either ship to a free spot in a room. False if the
## room is full or they're already there.
func _send_on(view: ShipView, crew: Array, c: BattleCrew, room: Dictionary) -> bool:
	if room.is_empty() or c.room_id == room["id"]:
		return false
	var cell: Variant = _free_cell(view, room, crew, c)
	if cell == null:
		return false
	c.room_id = room["id"]
	c.target = cell
	return true


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
	var hands := ship.effort()

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
		if _cheats_on and ship == player:
			ship.gun_factors[side] = 1.0  # exactly CHEAT_RELOAD seconds, whatever the damage
	# Point-blank as the hooks draw the ships together: easier to hit.
	ship.accuracy = ship.base_accuracy + aim_bonus + Boarding.CLOSE_ACCURACY * _boarding.closeness()

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

## Chooses the enemy: a Company hunter if the hunt has found us, otherwise a
## ship from this sea's mix of factions. Then scales her to how far we've come,
## and makes her a veteran if she guards the sea's exit.
func _pick_enemy(sea: int) -> Dictionary:
	var all: Array = Data.get_all("enemies")
	var run: RunState = GameState.run
	var elite := run.elite_pending
	run.elite_pending = false
	_elite_fight = elite
	var hunter := run.hunter_pending or (not elite and randf() < Voyage.hunter_chance(run))
	run.hunter_pending = false
	var picked: Dictionary = {}
	if run.forced_enemy != "" and Data.has_item("enemies", run.forced_enemy):
		picked = Data.get_item("enemies", run.forced_enemy)  # an event or port set this fight up
		hunter = false
		if run.port_owner != "":
			picked = _port_fort(picked, run.port_owner)
			run.port_owner = ""
	run.forced_enemy = ""
	if hunter:
		var hunters := all.filter(func(e: Dictionary) -> bool: return bool(e.get("hunter", false)))
		if not hunters.is_empty():
			picked = hunters.pick_random()
			_intro_note = "A Company hunter has run us down!"
	var captain := false
	if picked.is_empty() and elite:
		picked = _pick_captain(all, run, sea + 1)
		captain = not picked.is_empty()
	if picked.is_empty():
		# The sea's exit fight may draw from one sea ahead.
		var reach := sea + (1 if elite else 0)
		var options := all.filter(func(e: Dictionary) -> bool: return int(e.get("min_sea", 1)) <= reach and not bool(e.get("special", false)))
		if options.is_empty():
			options = all
		picked = _weighted_by_sea(options, run)
		_can_parley = not elite
	var boosted := picked.duplicate(true)
	var scale := Voyage.scale(run)
	boosted["max_hull"] = roundi(int(picked.get("max_hull", 20)) * scale)
	boosted["max_hands"] = roundi(int(picked.get("max_hands", 100)) * scale)
	boosted["accuracy"] = float(picked.get("accuracy", 0.5)) + Voyage.SEA_ACCURACY * (sea - 1)
	boosted["gold_reward"] = roundi(int(picked.get("gold_reward", 10)) * (1.0 + Voyage.SEA_GOLD * (sea - 1)))
	if not bool(picked.get("special", false)):
		# An ordinary ship: crewed and officered for how far we've come. A veteran is fully fitted out.
		Voyage.fit_out(boosted, 1.0 if elite else Voyage.progress(run))
	if elite and not captain:
		# No named captain left for these waters: a veteran guards the way out.
		boosted["name"] = "Veteran " + str(picked.get("name", "ship")).to_lower()
		boosted["max_hull"] = roundi(int(boosted["max_hull"]) * ELITE_BOOST)
		boosted["max_hands"] = roundi(int(boosted["max_hands"]) * ELITE_BOOST)
		boosted["accuracy"] = float(boosted["accuracy"]) + 0.05
		boosted["gold_reward"] = roundi(int(boosted["gold_reward"]) * ELITE_GOLD)
	return boosted


## A named elite captain for the sea's exit (enemies with "elite"), one we
## haven't met this run, weighted by this sea's factions. Empty if none left.
func _pick_captain(all: Array, run: RunState, reach: int) -> Dictionary:
	var options: Array = []
	for e: Dictionary in all:
		if bool(e.get("elite", false)) and int(e.get("min_sea", 1)) <= reach and not run.met_captains.has(e["id"]):
			options.append(e)
	if options.is_empty():
		return {}
	var picked := _weighted_by_sea(options, run)
	run.met_captains.append(picked["id"])
	_intro_note = str(picked.get("intro", "%s bars the way out of these waters!" % picked.get("captain", "A famous captain")))
	return picked


## The harbour fort, dressed for whoever owns the port (factions "port").
func _port_fort(base: Dictionary, owner: String) -> Dictionary:
	var port: Dictionary = Data.get_item("factions", owner).get("port", {})
	var fort := base.duplicate(true)
	var strength := float(port.get("fort_strength", 1.0))
	fort["faction"] = owner
	fort["name"] = str(port.get("fort_name", fort.get("name", "Fort")))
	fort["max_hull"] = roundi(int(base.get("max_hull", 50)) * strength)
	fort["max_hands"] = roundi(int(base.get("max_hands", 120)) * strength)
	fort["gold_reward"] = roundi(int(base.get("gold_reward", 40)) * float(port.get("plunder", 1.0)))
	fort["captives"] = int(port.get("captives", 0))
	fort["raid_morale"] = int(port.get("raid_morale", RAID_MORALE))
	fort["raid_hunt"] = int(port.get("raid_hunt", RAID_HUNT))
	return fort


# --- Hailing: reputation before the first shot -------------------------------

## Friends salute and let us pass; wary captains can be paid to sheer off;
## anyone else fights. The battle waits until we decide.
func _hail() -> void:
	var run: RunState = GameState.run
	var faction := str(_enemy_data.get("faction", ""))
	var value := Reputation.of(run, faction)
	var who := Reputation.short_name(faction)
	var stance := Reputation.stance(run, faction) if _can_parley else "fight"
	if stance == "fight":
		if value <= Reputation.HATED and faction != "":
			_log("%s know your colours. They'll give no quarter." % who)
		return
	_over = true  # hold everything while we talk
	if stance == "salute":
		_show_choices("The %s dips her colours in salute. %s count you a friend (%+d)." % [enemy.display_name, who, value], [
			["Return the salute and sail on (%s %+d)" % [who, Reputation.PASSED_IN_PEACE], _pass_in_peace],
			["Attack her anyway (treachery: %s %+d)" % [who, Reputation.TREACHERY], _end_hail.bind(true)],
		])
	else:
		var cost := Reputation.bribe_cost(run)
		var options: Array = []
		if run.gold >= cost:
			options.append(["Pay her captain %d gold to sheer off" % cost, _pay_off_captain.bind(cost)])
		options.append(["Clear for action!", _end_hail.bind(false)])
		_show_choices("The %s holds off with her guns run out, but silent. %s are wary of you (%+d); her captain might be persuaded to look the other way." % [
			enemy.display_name, who, value], options)


func _pass_in_peace() -> void:
	var run: RunState = GameState.run
	Reputation.change(run, str(_enemy_data.get("faction", "")), Reputation.PASSED_IN_PEACE)
	run.last_note = "The %s let us pass in peace." % enemy.display_name
	GameState.finish_node()


func _pay_off_captain(cost: int) -> void:
	var run: RunState = GameState.run
	run.gold -= cost
	run.last_note = "Gold changed hands, and the %s sheered off." % enemy.display_name
	GameState.finish_node()


func _end_hail(treachery: bool) -> void:
	for b in _choice_buttons:
		b.queue_free()
	_choice_buttons.clear()
	_result_box.visible = false
	_result_button.visible = true
	_over = false
	if treachery:
		var line := Reputation.change(GameState.run, str(_enemy_data.get("faction", "")), Reputation.TREACHERY)
		_log("Treachery! They won't forget it (%s)." % line)
	_refresh_ui()


## A victory's news travels: the loser's faction and its enemies remember it.
func _rep_line() -> String:
	var lines := Reputation.on_defeat(GameState.run, str(_enemy_data.get("faction", "")))
	return "\nWord spreads: %s." % ", ".join(lines) if not lines.is_empty() else ""


## Taking a ship as a prize can finish a quest (see Hub.check_quests).
func _quest_lines(captured: bool) -> String:
	if not captured or enemy.is_static:
		return ""
	var lines := Hub.check_quests(GameState.run, {"type": "capture", "faction": str(_enemy_data.get("faction", ""))})
	return "\n" + "\n".join(lines) if not lines.is_empty() else ""


## Picks from the candidates by this sea's faction weights (data/seas "factions").
func _weighted_by_sea(options: Array, run: RunState) -> Dictionary:
	var total := 0.0
	for e: Dictionary in options:
		total += _encounter_weight(e, run)
	var roll := randf() * total
	for e: Dictionary in options:
		roll -= _encounter_weight(e, run)
		if roll <= 0.0:
			return e
	return options.back()


## The sea decides the faction, how far we've come decides light, medium or heavy.
func _encounter_weight(e: Dictionary, run: RunState) -> float:
	var factions: Dictionary = Voyage.sea(run).get("factions", {})
	return float(factions.get(e.get("faction", ""), 0.5)) * Voyage.class_weight(run, str(e.get("class", "")))


# --- Coming about -----------------------------------------------------------

## Orders a ship to come about. Turn speed and the chance of stalling come
## from the helm's condition, the hands, and any helmsman at the helm.
func _come_about(ship: BattleShip, view: ShipView, crew: Array) -> void:
	if ship.turning or _boarding.is_lashed() or ship.is_static:
		return
	var helm_room: Dictionary = {}
	for room in view.rooms:
		if room["type"] == "helm":
			helm_room = room
	var turn_buff := 1.0
	for c: BattleCrew in _specialists_at(view, crew, "helm"):
		turn_buff *= c.buff("turn")
	var speed := turn_buff * lerpf(0.5, 1.0, ship.effort()) * maxf(0.25, _room_efficiency(ship, helm_room))
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
	if _boarding.is_lashed():
		ship.fleeing = false  # lashed alongside: nobody is going anywhere
		ship.escape = 0.0
	if ship.fleeing and not ship.turning:
		if ship.sails_ratio() < MIN_FLEE_SAILS:
			ship.escape = maxf(0.0, ship.escape - ESCAPE_DECAY * delta)
		else:
			var edge := clampf(ship.speed() / maxf(0.25, pursuer.speed()), 0.3, 2.0)
			var held := 1.0 - _boarding.closeness()  # hooks in her hold her back
			ship.escape = minf(1.0, ship.escape + edge / FLEE_TIME * held * delta)
	elif not ship.fleeing:
		ship.escape = maxf(0.0, ship.escape - ESCAPE_DECAY * delta)
	view.base_position.x = start_x + away * FLEE_DRIFT * ship.escape - away * PULL_DISTANCE * _boarding.pull
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
	if _boarding.is_lashed():
		_log("We're lashed to her! Cut loose first.")
		return
	if not player.fleeing and player.sails_ratio() < MIN_FLEE_SAILS:
		_log("Not enough canvas left to run!")
		return
	player.fleeing = not player.fleeing
	_log("All hands, make sail! We're running." if player.fleeing else "Belay that, we stand and fight!")
	_refresh_ui()


# --- Grappling and boarding ------------------------------------------------------

## Product of a buff across every living specialist aboard (boarding skills
## work wherever they stand).
func _crew_buff(crew: Array, stat: String) -> float:
	var total := 1.0
	for c: BattleCrew in crew:
		total *= c.buff(stat)
	return total


func _grapple_skill(ship: BattleShip, crew: Array) -> float:
	return _crew_buff(crew, "grapple") * lerpf(0.5, 1.0, ship.effort())


func _throw(ship: BattleShip) -> void:
	var crew := player_crew if ship == player else enemy_crew
	var result := _boarding.try_throw(ship, _grapple_skill(ship, crew))
	var ours := ship == player
	match result:
		"missed":
			_log("Grapple falls short!" if ours else "Their grapple splashes short.")
		"hooked":
			_log("Grapple's fast! %d of %d." % [_boarding.hooks, Boarding.HOOKS_NEEDED] if ours
				else "They've got a hook in us! %d of %d. Cut it!" % [_boarding.hooks, Boarding.HOOKS_NEEDED])
		"lashed":
			player.turning = false
			enemy.turning = false
			_log("Lashed alongside! Guns fall silent. Choose your boarding party." if ours
				else "They've lashed us alongside! Stand by to repel boarders!")
			_ai_board_wait = AI_BOARD_DELAY


func _cut(ship: BattleShip) -> void:
	var crew := player_crew if ship == player else enemy_crew
	var result := _boarding.try_cut(ship, _grapple_skill(ship, crew))
	var ours := ship == player
	match result:
		"failed":
			if ours:
				_log("The rope holds!")
		"cut":
			_log("Rope cut! %d hooks left." % _boarding.hooks if ours else "They've cut a rope! %d hooks left." % _boarding.hooks)
		"free":
			_log("Cut loose! We're free of her." if ours else "They've cut themselves free!")


func _on_grapple_pressed() -> void:
	if _over or _boarding.state == "melee":
		return
	if _boarding.grappler == enemy or _boarding.state == "lashed":
		_cut(player)
	else:
		_throw(player)
	_refresh_ui()


## Testing only: hull and hands to 999, one-second reloads, 99 of every shot.
## Hull and hands carry into the run; reloads stay fast for the rest of the session.
func _on_cheat_pressed() -> void:
	if _over:
		return
	_cheats_on = true
	_apply_cheats()
	_log("TEST: god mode. Hull and hands %d, %ds reloads, %d of every shot." % [CHEAT_HULL, int(CHEAT_RELOAD), CHEAT_AMMO])
	_refresh_ui()


func _apply_cheats() -> void:
	var run: RunState = GameState.run
	run.max_hull = maxi(run.max_hull, CHEAT_HULL)
	run.max_hands = maxi(run.max_hands, CHEAT_HANDS)
	player.max_hull = run.max_hull
	player.hull = player.max_hull
	player.max_hands = run.max_hands
	player.hands = player.max_hands
	player.reload_time = CHEAT_RELOAD
	for side: String in BattleShip.SIDES:
		player.reloads[side] = minf(float(player.reloads[side]), CHEAT_RELOAD)
	for a: Dictionary in Data.get_all("ammo"):
		player.ammo[str(a["id"])] = maxi(int(player.ammo.get(str(a["id"]), 0)), CHEAT_AMMO)


## Testing only: skip the grappling and lash the ships together right away.
func _on_debug_lash_pressed() -> void:
	if _over or _boarding.state == "melee":
		return
	_boarding.debug_lash(player)
	player.turning = false
	enemy.turning = false
	_log("TEST: lashed alongside. Choose your boarding party.")
	_refresh_ui()


func _on_board_pressed(share: float) -> void:
	if _boarding.state != "lashed" or _boarding.initiative != player or player.hands < 2:
		return
	var size := maxi(1, roundi(player.hands * share))
	_boarding.start_melee(player, enemy, size)
	_log("Away boarders! %d hands over the rail." % size)
	_refresh_ui()


func _on_fall_back_pressed() -> void:
	if _boarding.state == "melee" and _boarding.attacker == player:
		_boarding.fall_back()
		_log("Fall back! Back to the ship!")
		_refresh_ui()


func _tick_melee(delta: float) -> void:
	if _boarding.state != "melee":
		return
	var att := _boarding.attacker
	var att_crew := player_crew if att == player else enemy_crew
	var def_crew := enemy_crew if att == player else player_crew
	var axes := Perks.mult(GameState.run, "boarding")  # our people fight harder, attacking or defending
	var event := _boarding.tick_melee(delta,
		_crew_buff(att_crew, "boarding") * att.morale_factor * (axes if att == player else 1.0),
		_crew_buff(def_crew, "boarding") * _boarding.defender.morale_factor * (axes if att != player else 1.0))
	if event == "":
		return
	# Boarding masters lead from the front on both sides, and get hurt doing it.
	for c: BattleCrew in att_crew + def_crew:
		if c.alive and c.buff("boarding") > 1.0:
			c.hurt(Boarding.WOUND_PER_ROUND * randf_range(0.5, 1.5))
	_report_deaths()
	var mid := (_player_view.base_position + _enemy_view.base_position) / 2.0
	for i in 3:
		_vfx.melee_clash(mid + Vector2(randf_range(-20, 20), randf_range(-80, 80)))
	var ours := att == player
	match event:
		"round":
			_log("Boarding: %d of ours against %d of theirs." % [_boarding.party, _boarding.defender.hands] if ours
				else "Repel boarders! %d of ours against %d of theirs." % [_boarding.defender.hands, _boarding.party])
		"repelled":
			if ours and _boarding.wiped_out:
				_log("Our boarding party is cut down to the last man!")
			else:
				_log("We're thrown back! Survivors return. They may counter-board!" if ours
					else "Boarders repelled! Board them back, or cut loose.")
			_ai_board_wait = AI_BOARD_DELAY
		"taken":
			_over = true
			_select(null)
			if ours:
				_enemy_view.strike_colours()
				get_tree().create_timer(1.0, false).timeout.connect(_show_boarding_victory.bind(enemy.hands))
			else:
				_player_view.strike_colours()
				get_tree().create_timer(1.0, false).timeout.connect(_show_defeat.bind("Boarded and taken. Your ship is theirs."))


## Enemy captains who like to board grapple when they have the bigger crew,
## board as soon as they're lashed (if still stronger), and otherwise cut loose.
func _enemy_board_think(delta: float) -> void:
	var stronger := enemy.hands >= player.hands * float(enemy.ai.get("board_edge", 1.3))
	match _boarding.state:
		"none", "grappling":
			if _boarding.grappler == player:
				if not enemy.boards or not stronger:
					_cut(enemy)
			elif enemy.boards and stronger and not enemy.fleeing:
				_throw(enemy)
		"lashed":
			if _boarding.initiative != enemy:
				# Our move. A captain who doesn't fancy a melee tries to cut free.
				if not enemy.boards or not stronger:
					_cut(enemy)
				return
			_ai_board_wait -= delta
			if _ai_board_wait > 0.0:
				return
			if enemy.hands >= player.hands * 1.1:
				var share := 0.75 if enemy.hands >= player.hands * 2.0 else 0.5
				var size := maxi(1, roundi(enemy.hands * share))
				_boarding.start_melee(enemy, player, size)
				_log("Boarders! %d of them coming over the rail!" % size)
			else:
				_cut(enemy)


## We took her by boarding. Her surviving hands are now our prisoners.
func _show_boarding_victory(prisoners: int) -> void:
	var run: RunState = GameState.run
	var gold := roundi(int(_enemy_data.get("gold_reward", 10)) * STRUCK_GOLD * Perks.mult(run, "gold"))
	var patched := _write_back(true)
	run.gold += gold
	run.battles_won += 1
	var text := "The %s is ours! Taken by boarding.\n+%d gold. Hull patched %d, sails mended %d. Hands left: %d." % [
		enemy.display_name, gold, patched["repair"], patched["mend"], player.hands]
	var morale := Morale.WIN + Morale.CAPTURE + (Morale.FREED_CAPTIVES if enemy.captives > 0 else 0)
	text = _free_captives(text)
	if not _fallen.is_empty():
		text += "\nLost: " + ", ".join(_fallen) + "."
	text += _rep_line()
	text += _quest_lines(true)
	text += _morale_line(morale)
	if prisoners <= 0:
		_show_result(text, "Share out the plunder", _to_plunder)
		return
	text += "\n%d of her crew have surrendered. What's to be done with them?" % prisoners
	_offer_prisoners(text, prisoners, "Set them adrift")


## The choice of what to do with captured or rescued enemy sailors.
func _offer_prisoners(text: String, count: int, leave_text: String) -> void:
	var run: RunState = GameState.run
	var room := run.max_hands - run.hands
	_show_choices(text, [
		["Press %d into service (morale %d)" % [mini(count, room), Morale.PRESSED_PRISONERS], _settle_prisoners.bind("press", count)],
		["Lock them up for ransom (%d gold at port)" % (count * PRISONER_RANSOM), _settle_prisoners.bind("ransom", count)],
		[leave_text, _settle_prisoners.bind("adrift", count)],
	])


func _settle_prisoners(mode: String, count: int) -> void:
	var run: RunState = GameState.run
	match mode:
		"press":
			run.hands = mini(run.max_hands, run.hands + count)
			Morale.change(run, Morale.PRESSED_PRISONERS)  # the crew don't trust them
		"ransom":
			run.prisoners += count
	_to_plunder()


## A ship is beaten: on to choosing what we take from her (the plunder screen).
func _to_plunder() -> void:
	GameState.take_plunder("elite" if _elite_fight else "battle")


# --- Enemy captain and crew ------------------------------------------------

## Picks the enemy's next shot from its faction's style: chain at a ship
## that's running, grape to soften us up before boarding, now and then a
## heated ball, otherwise round shot.
func _enemy_pick_ammo() -> String:
	var ai := enemy.ai
	if bool(ai.get("chain_on_runner", false)) and player.fleeing and player.sails_ratio() >= MIN_FLEE_SAILS:
		return "chain_shot"
	if bool(ai.get("grape_before_boarding", false)) and enemy.boards and player.hands > 10 \
			and enemy.hands >= player.hands * float(ai.get("board_edge", 1.3)) * 0.8:
		return "grape_shot"
	if randf() < float(ai.get("heated_chance", 0.0)):
		return "heated_shot"
	return "round_shot"


## Enemy specialists look after their ship: the badly wounded go below to the
## sickbay, anyone with a work buff (the carpenter) goes where the trouble is,
## and everyone else returns to their post.
func _enemy_crew_think(delta: float) -> void:
	_ai_crew_t -= delta
	if _ai_crew_t > 0.0:
		return
	_ai_crew_t = AI_CREW_THINK
	var sickbay: Dictionary = {}
	for room in _enemy_view.rooms:
		if room["type"] == "sickbay":
			sickbay = room
	var trouble := _worst_room(enemy, _enemy_view)
	for c: BattleCrew in enemy_crew:
		if not c.alive or c.is_moving():
			continue
		if c.health < AI_WOUNDED and not sickbay.is_empty():
			_send_on(_enemy_view, enemy_crew, c, sickbay)
		elif c.buff("work") > 1.0 and not trouble.is_empty():
			_send_on(_enemy_view, enemy_crew, c, trouble)
		elif c.health >= BattleCrew.WOUNDED:
			_send_on(_enemy_view, enemy_crew, c, _enemy_view.room_by_id(str(_enemy_homes.get(c, ""))))


## The room most in need of hands: fires first, then leaks, then damage.
func _worst_room(ship: BattleShip, view: ShipView) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0.0
	for room in view.rooms:
		var s: Dictionary = ship.rooms[room["id"]]
		var score := float(s["fire"]) * 3.0 + (150.0 if s["leak"] else 0.0) + int(s["damage"]) * 20.0
		if score > best_score:
			best_score = score
			best = room
	return best


## Freed captives (slavers): they join if there's room aboard.
func _free_captives(text: String) -> String:
	if enemy.captives <= 0:
		return text
	var run: RunState = GameState.run
	var joined := mini(enemy.captives, run.max_hands - run.hands)
	run.hands += joined
	return text + "\n%d captives freed from her hold; %d join your crew." % [enemy.captives, joined]


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
	if enemy.is_static and (enemy.hull <= 0 or enemy.hands + _party_of(enemy) <= 0):
		_over = true
		_fort_falls()  # forts don't sink: the walls are breached and the flag comes down
		get_tree().create_timer(FORT_FALL_TIME, false).timeout.connect(_show_victory.bind(enemy.hull > 0))
	elif enemy.hull <= 0:
		_over = true
		_sink(_enemy_view)
		get_tree().create_timer(SINK_TIME, false).timeout.connect(_show_victory.bind(false))
	elif enemy.hands + _party_of(enemy) <= 0:
		_over = true
		_select(null)
		_enemy_view.strike_colours()
		get_tree().create_timer(1.0, false).timeout.connect(_show_victory.bind(true))
	elif player.hull <= 0:
		_over = true
		_sink(_player_view)
		get_tree().create_timer(SINK_TIME, false).timeout.connect(_show_defeat.bind("Your ship goes down with all hands."))
	elif player.hands + _party_of(player) <= 0:
		_over = true
		_select(null)
		_player_view.strike_colours()
		var why := "No hands left to fight her. You strike your colours."
		if _boarding.wiped_out and _boarding.attacker == player:
			why = "Your boarding party was cut down to the last man, and there's no one left aboard to sail her. You strike your colours."
		get_tree().create_timer(1.0, false).timeout.connect(_show_defeat.bind(why))


## Hands a ship has away in a boarding party (they still count as hers).
func _party_of(ship: BattleShip) -> int:
	if _boarding.state == "melee" and _boarding.attacker == ship:
		return _boarding.party
	return 0


func _sink(view: ShipView) -> void:
	_select(null)
	var tween := _arena.create_tween().set_parallel()
	tween.tween_property(view, "scale", view.scale * 0.8, SINK_TIME).set_ease(Tween.EASE_IN)
	tween.tween_property(view, "rotation", view.rotation + 0.25 * signf(view.scale.x), SINK_TIME)
	tween.tween_property(view, "modulate", Color(0.4, 0.5, 0.6, 0.0), SINK_TIME).set_ease(Tween.EASE_IN)
	for i in 4:
		var at := view.transform * view.random_hit_point()
		get_tree().create_timer(i * 0.35, false).timeout.connect(_vfx.impact.bind(at))


## A beaten fort: a last few blasts, the walls broken, the white flag up, and
## smoke that keeps rising while we decide what to do with the town.
func _fort_falls() -> void:
	_select(null)
	_enemy_view.ruin()
	for i in 5:
		var at := _enemy_view.transform * _enemy_view.random_hit_point()
		get_tree().create_timer(i * 0.3, false).timeout.connect(_vfx.impact.bind(at))
	var smoke := Timer.new()
	smoke.wait_time = FORT_SMOKE_EVERY
	smoke.autostart = true
	smoke.timeout.connect(_fort_smoke)
	_arena.add_child(smoke)
	_fort_banner()


func _fort_smoke() -> void:
	_vfx.smoke_plume(_enemy_view.transform * _enemy_view.random_hit_point())


func _fort_banner() -> void:
	var banner := Label.new()
	banner.text = "%s HAS FALLEN!" % _port_name().to_upper()
	banner.add_theme_font_size_override("font_size", 22)
	banner.add_theme_color_override("font_color", Color("f5c542"))
	banner.add_theme_constant_override("outline_size", 6)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -300
	banner.offset_right = 300
	banner.offset_top = 52
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	banner.pivot_offset = Vector2(300, 14)
	banner.scale = Vector2(1.6, 1.6)
	_ui_root.add_child(banner)
	var tween := banner.create_tween().set_parallel()
	tween.tween_property(banner, "modulate:a", 1.0, 0.5)
	tween.tween_property(banner, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(FORT_FALL_TIME - 0.9)
	tween.chain().tween_property(banner, "modulate:a", 0.0, 0.4)


## The port we're attacking, from the map node we're on.
func _port_name() -> String:
	var run: RunState = GameState.run
	var here := int(run.map.get("current", -1))
	if here < 0:
		return "The fort"
	return str(run.map["nodes"][here].get("name", "The fort"))


func _show_victory(captured: bool) -> void:
	var run: RunState = GameState.run
	var gold := roundi(int(_enemy_data.get("gold_reward", 10)) * Perks.mult(run, "gold"))
	if captured:
		gold = roundi(gold * STRUCK_GOLD)
	var patched := _write_back(true)
	run.gold += gold
	run.battles_won += 1
	var headline := "The %s strikes her colours! Prize taken." if captured else "The %s goes down!"
	if enemy.is_static:
		headline = "The guns of the %s fall silent and her colours come down." if captured else "The walls of the %s are breached. The white flag goes up."
	var text := (headline % enemy.display_name) + "\n+%d gold. Hull patched %d, sails mended %d. Hands left: %d." % [
		gold, patched["repair"], patched["mend"], player.hands]
	var morale := Morale.WIN + (Morale.CAPTURE if captured else 0)
	var reward: Dictionary = _enemy_data.get("reward", {})
	if not reward.is_empty():
		# An elite captain's cabin: her strongbox, her charts, maybe a man of hers.
		text += "\n%s is beaten! From the captain's cabin: %s." % [_enemy_data.get("captain", "Her captain"), ", ".join(Events.apply(run, reward))]
		morale += Morale.CAPTURE
	if enemy.is_static:
		# The town is ours: what we take from it is chosen ashore. Word spreads.
		Voyage.change_hunt(run, int(_enemy_data.get("raid_hunt", RAID_HUNT)))
		morale += int(_enemy_data.get("raid_morale", RAID_MORALE))
	if captured or enemy.is_static:  # a fort's walls fall, but her cells are still standing
		text = _free_captives(text)
		if enemy.captives > 0:
			morale += Morale.FREED_CAPTIVES
	elif enemy.captives > 0:
		text += "\nThe captives chained below went down with her."
	if not _fallen.is_empty():
		text += "\nLost: " + ", ".join(_fallen) + "."
	text += _rep_line()
	text += _quest_lines(captured)
	text += _morale_line(morale)
	if enemy.is_static:
		text += "\n%s is yours. The townsfolk wait to see what you'll do." % _port_name()
		_show_result(text, "Go ashore", _go_ashore)
		return
	var survivors := 0
	if not captured:
		survivors = roundi(enemy.hands * SURVIVOR_SHARE * randf_range(0.7, 1.3))
	if survivors <= 0:
		_show_result(text, "Share out the plunder", _to_plunder)
		return
	text += "\n%d of her crew are clinging to the wreckage. What's to be done with them?" % survivors
	_offer_prisoners(text, survivors, "Leave them to the sea")


func _go_ashore() -> void:
	var run: RunState = GameState.run
	run.port_taken = true
	var here := int(run.map.get("current", -1))
	if here >= 0:
		run.map["nodes"][here]["taken"] = true  # she stays ours if we sail back this way
	SaveSystem.save_run(run)
	GameState.change_screen(GameState.Screen.SHOP)


## Someone got away. Nobody is paid and nothing is mended; the damage stays.
func _show_escape(we_ran: bool) -> void:
	_write_back(false)
	var text := "You slip away under full sail." if we_ran else "The %s escapes into the haze." % enemy.display_name
	text += "\nHull %d/%d. Hands left: %d." % [player.hull, player.max_hull, player.hands]
	if not _fallen.is_empty():
		text += "\nLost: " + ", ".join(_fallen) + "."
	text += _morale_line(Morale.RAN_AWAY if we_ran else Morale.ENEMY_ESCAPED)
	_show_result(text, "Return to the map", GameState.finish_node)


## Applies this battle's morale: the given result, minus the dead and any
## heavy losses among the hands. Returns a line for the result screen.
func _morale_line(result: int) -> String:
	var run: RunState = GameState.run
	var amount := result + _fallen.size() * Morale.SPECIALIST_DIED
	if _start_hands > 0 and float(_start_hands - player.hands) / _start_hands > Morale.HEAVY_LOSS_SHARE:
		amount += Morale.HEAVY_LOSSES
	var before := run.morale
	var changed := Morale.change(run, amount)
	if changed == 0:
		return "\nMorale holds at %d (%s)." % [run.morale, Morale.mood(run.morale)]
	return "\nMorale %+d: %d to %d (%s)." % [changed, before, run.morale, Morale.mood(run.morale)]


## Saves the battle's results to the run: surviving specialists (with their
## health and posts), hull, sails, hands and ammo. After a win, carpenters
## patch the hull, the hands and bosuns mend sails, and the wounded recover.
func _write_back(won: bool) -> Dictionary:
	var run: RunState = GameState.run
	if won and str(_enemy_data.get("faction", "")) == "company":
		Voyage.change_hunt(run, Voyage.HUNT_PER_COMPANY_SHIP)  # the Company notices its losses
	var survivors := player_crew.filter(func(c: BattleCrew) -> bool: return c.alive)
	var repair := 0
	var mend := 0
	var recovery := 0
	if won:
		repair = survivors.filter(func(c: BattleCrew) -> bool: return c.role == "carpenter").size() * CARPENTER_REPAIR
		mend = HANDS_MEND + survivors.filter(func(c: BattleCrew) -> bool: return c.role == "bosun").size() * BOSUN_MEND
		var has_surgeon := survivors.any(func(c: BattleCrew) -> bool: return c.role == "surgeon")
		recovery = HEAL_AFTER_BATTLE + (SURGEON_AFTER_BATTLE if has_surgeon else 0)
		repair += roundi(Perks.add(run, "repair"))
		mend += roundi(Perks.add(run, "mend"))
		recovery += roundi(Perks.add(run, "heal"))
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
	_ui_root = root

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
	left.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	left.add_theme_constant_override("separation", 1)
	var morale := GameState.run.morale
	_add_label(left, "%s   MORALE %d (%s)" % [player.display_name, morale, Morale.mood(morale)])
	_player_status = _add_label(left, "")
	_player_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	right.custom_minimum_size = Vector2(STATUS_WIDTH, 0)
	right.add_theme_constant_override("separation", 1)
	var enemy_name := _add_label(right, enemy.display_name)
	enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_status = _add_label(right, "")
	_enemy_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enemy_hull_bar = _add_bar(right, Color("c0392b"))
	_enemy_sails_bar = _add_bar(right, Color("ecf0f1"))
	_enemy_reload_bar = _add_bar(right, Color("f1c40f"))
	_enemy_reload_other = _add_bar(right, Color("8a7a2a"))
	_enemy_escape_bar = _add_bar(right, Color("5dade2"))
	for bar in [_enemy_hull_bar, _enemy_sails_bar, _enemy_reload_bar, _enemy_reload_other, _enemy_escape_bar]:
		(bar as ProgressBar).size_flags_horizontal = Control.SIZE_SHRINK_END  # hug the right edge
	_enemy_sails_bar.visible = not enemy.is_static  # a fort has no sails

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
		button.custom_minimum_size = Vector2(130, 0)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.clip_text = true
		button.add_theme_color_override("font_color", c.color)
		button.pressed.connect(_select.bind(c))
		roster.add_child(button)
		_crew_buttons[c] = button

	# Boarding controls: only the ones that make sense right now are shown.
	_boarding_row = HBoxContainer.new()
	_boarding_row.add_theme_constant_override("separation", 8)
	_boarding_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_boarding_row)
	_grapple_button = _add_order_button(_boarding_row, _on_grapple_pressed, 130)
	for i in PARTY_SIZES.size():
		_board_buttons.append(_add_order_button(_boarding_row, _on_board_pressed.bind(float(PARTY_SIZES[i])), 0))
	_cut_loose_button = _add_order_button(_boarding_row, _on_grapple_pressed, 0)
	_cut_loose_button.text = "Cut loose (G)"
	_fall_back_button = _add_order_button(_boarding_row, _on_fall_back_pressed, 0)
	_fall_back_button.text = "Fall back!"
	_debug_lash_button = _add_order_button(_boarding_row, _on_debug_lash_pressed, 0)
	_debug_lash_button.text = "TEST: lash now (B)"
	_debug_lash_button.add_theme_color_override("font_color", Color("ff9f43"))
	_cheat_button = _add_order_button(_boarding_row, _on_cheat_pressed, 0)
	_cheat_button.text = "TEST: god mode (T)"
	_cheat_button.add_theme_color_override("font_color", Color("ff9f43"))

	# Bottom: orders.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	_fire_button = Button.new()
	_fire_button.focus_mode = Control.FOCUS_NONE
	_fire_button.custom_minimum_size = Vector2(130, 0)
	_fire_button.pressed.connect(_on_fire_pressed)
	bottom.add_child(_fire_button)
	_turn_button = Button.new()
	_turn_button.focus_mode = Control.FOCUS_NONE
	_turn_button.custom_minimum_size = Vector2(100, 0)
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

	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 12)
	_log_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_log_label.offset_top = -84  # room for two lines of a long message, growing upwards
	_log_label.offset_bottom = -36
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_log_label.offset_left = -200
	_log_label.offset_right = 200
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_label.visible = false
	root.add_child(_log_label)

	_pause_label = Label.new()
	_pause_label.text = "PAUSED\nSPACE resume   F fire   C come about   R make sail   G grapple"
	_pause_label.add_theme_font_size_override("font_size", 16)
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
	_panel_column = panel_column
	_result_label = _add_label(panel_column, "")
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_button = Button.new()
	_result_button.focus_mode = Control.FOCUS_NONE
	panel_column.add_child(_result_button)


func _add_order_button(parent: Node, action: Callable, width: float) -> Button:
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	if width > 0.0:
		button.custom_minimum_size = Vector2(width, 0)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


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
	bar.custom_minimum_size = Vector2(150, 4)
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


## Like _show_result, but with a choice of buttons: [[text, Callable], ...].
func _show_choices(text: String, options: Array) -> void:
	_show_result(text, "", Callable())
	_result_button.visible = false
	for option: Array in options:
		var button := Button.new()
		button.text = str(option[0])
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(option[1], CONNECT_ONE_SHOT)
		_panel_column.add_child(button)
		_choice_buttons.append(button)


func _show_result(text: String, button_text: String, action: Callable) -> void:
	get_tree().paused = false
	_pause_label.visible = false
	_result_label.text = text
	_result_button.text = button_text
	if action.is_valid():
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
	_refresh_boarding_ui()
	_flee_button.disabled = _over or _boarding.is_lashed()
	if player.fleeing:
		_flee_button.text = "Stand and fight"
	else:
		_flee_button.text = "Make sail (R)"

	_turn_button.disabled = _over or player.turning or _boarding.is_lashed()
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
	_fire_button.disabled = _over or player.auto_fire or player.shots_available() == 0 or player.turning \
		or _boarding.guns_silent()
	if _boarding.guns_silent():
		_fire_button.text = "Guns silent"
	elif player.turning:
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


func _refresh_boarding_ui() -> void:
	var b := _boarding
	var hooks := "%d/%d" % [b.hooks, Boarding.HOOKS_NEEDED]
	var our_turn_to_board := b.state == "lashed" and b.initiative == player
	_grapple_button.visible = b.state == "none" or b.state == "grappling"
	_grapple_button.disabled = _over or b.cooldown(player) > 0.0
	if b.grappler == enemy:
		_grapple_button.text = "Cut ropes (G) %s" % hooks
	else:
		_grapple_button.text = "Throw grapples (G) %s" % hooks
	for i in _board_buttons.size():
		var button := _board_buttons[i]
		button.visible = our_turn_to_board
		button.disabled = _over or player.hands < 2
		button.text = "Board: %s (%d)" % [PARTY_LABELS[i], maxi(1, roundi(player.hands * float(PARTY_SIZES[i])))]
	_cut_loose_button.visible = b.state == "lashed"
	_cut_loose_button.disabled = _over or b.cooldown(player) > 0.0
	_cut_loose_button.text = "Cut loose (G) %s" % hooks
	_fall_back_button.visible = b.state == "melee" and b.attacker == player
	_debug_lash_button.visible = DEBUG_BOARDING and b.state != "lashed" and b.state != "melee"
	_debug_lash_button.disabled = _over
	_cheat_button.visible = DEBUG_CHEATS and b.state != "lashed" and b.state != "melee"  # T still works
	_cheat_button.disabled = _over


func _status_text(ship: BattleShip) -> String:
	var side := "Stbd" if ship.engaged_side == "starboard" else "Port"
	var guns := "%s guns ready" % side
	if ship.turning:
		guns = "COMING ABOUT"
	elif not ship.is_loaded():
		guns = "%s guns out of action" % side if ship.gun_factor() <= 0.0 else "%s loading %d%%" % [side, int(ship.reload_ratio() * 100.0)]
	if not ship.turning and ship.is_loaded(ship.other_side()):
		guns += " (other side ready)"
	if _boarding.guns_silent():
		guns = "LASHED ALONGSIDE" if _boarding.state == "lashed" else "BOARDING ACTION"
	if ship.fleeing:
		guns += "  RUNNING %d%%" % roundi(ship.escape * 100.0)
		if ship.sails_ratio() < MIN_FLEE_SAILS:
			guns += " (no canvas!)"
	var trouble := DamageControl.alerts(ship)
	if trouble != "":
		guns += "  " + trouble.to_upper()
	if ship.is_static:  # a fort: no sails, and it can't dodge
		return "Walls %d/%d  HANDS %d/%d\n%s" % [ship.hull, ship.max_hull, ship.hands, ship.max_hands, guns]
	return "Hull %d/%d  Sails %d/%d  HANDS %d/%d\nDodge %d%%  %s" % [
		ship.hull, ship.max_hull, ship.sails, ship.max_sails, ship.hands, ship.max_hands,
		int(ship.evasion() * 100.0), guns]
