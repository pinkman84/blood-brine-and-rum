class_name BossFight
extends Node2D
## The fight with the Company's flagship, in three phases. The battle screen
## owns the ships and the UI; this runs what's special about her and draws the
## boats. Her numbers are in data/enemies ("boss_fight" on company_flagship).
##
## She has three banks of guns a side (the three gun rooms in her layout),
## each on its own timer, a third of a reload apart, so shot arrives in a
## rolling fire instead of one broadside. Her hull is a separate pool for each
## phase ("phase_hull").
##
##   Phase 1  Guns against guns. Empty her hull pool and a gun deck blows up:
##            that bank is gone for good.
##   Phase 2  She sends marines over in boats while her two banks keep firing.
##            Boats shoot swivel guns on the way; any that reach us put their
##            marines aboard to fight our hands. Switch target (X) to fire on
##            the boats instead of her. The boats stop coming when her hands
##            fall to "boats_stop_at" of her full crew. Empty the pool and a
##            second deck blows up.
##   Phase 3  One bank left, and the great gun: slow to load, but a hit takes
##            "great_gun_damage" of our hull and holes every lower room. Empty
##            the last pool and she sinks.
##
## Between phases there's a lull while she fights her fires: a breather with
## one thing to do (patch, tend the wounded, or rally the crew).
## There is no boarding her and no running from her.

const PHASES := 3
const MIN_EFFORT := 0.6  # her gunners keep a steady fire however many hands she's lost
const BOAT_FIRE_EVERY := 5.0
const MARINES_KILL := 0.05  # hands we lose each second, per marine aboard
const HANDS_KILL := 0.03  # marines killed each second, per hand of ours
const DEFENDER_BONUS := 1.25  # we're fighting on our own deck
const BREATHER_HEAL := 40
const BREATHER_MORALE := 10
const BOAT_COLOR := Color("5a4636")
const GREAT_GUN_HEAD_START := 0.4  # share of a load done when phase 3 begins

var phase := 1
var targeting_boats := false
var boats: Array = []  # each { t: 0..1 across the water, y, hull, marines, fire }
var marines_aboard := 0.0

var _b: Node  # the battle screen
var _cfg: Dictionary = {}
var _bank_timers: Array[float] = []
var _bank_alive: Array[bool] = []
var _great_gun := 0.0  # seconds of loading done
var _boat_timer := 0.0
var _boats_done := false
var _melee_t := 0.0
var _full_hands := 1


func setup(battle: Node) -> void:
	_b = battle
	_cfg = battle._enemy_data.get("boss_fight", {})
	var banks := int(_cfg.get("banks", 3))
	for i in banks:
		_bank_alive.append(true)
		_bank_timers.append(_b.enemy.reload_time * float(i) / banks)  # staggered: a rolling fire
	_full_hands = _b.enemy.max_hands
	_start_pool()


func _start_pool() -> void:
	var pools: Array = _cfg.get("phase_hull", [45, 45, 60])
	_b.enemy.max_hull = int(pools[clampi(phase - 1, 0, pools.size() - 1)])
	_b.enemy.hull = _b.enemy.max_hull


# --- Every frame (called by the battle screen while the fight is live) --------

func tick(delta: float) -> void:
	_tick_banks(delta)
	if phase == 2:
		_tick_boats(delta)
	if phase == 3:
		_tick_great_gun(delta)
	_tick_melee(delta)
	queue_redraw()


## Each bank loads and fires on its own. A wrecked or burning deck is slower.
func _tick_banks(delta: float) -> void:
	var enemy: BattleShip = _b.enemy
	var view: ShipView = _b._enemy_view
	var rooms := view.gun_rooms(enemy.engaged_side)
	var effort := maxf(MIN_EFFORT, enemy.effort())
	for i in _bank_timers.size():
		if not _bank_alive[i] or i >= rooms.size():
			continue
		var room: Dictionary = rooms[i]
		_bank_timers[i] += delta * effort * DamageControl.efficiency(enemy.rooms[room["id"]])
		if _bank_timers[i] >= enemy.reload_time:
			_bank_timers[i] = 0.0
			_fire_bank(room)


func _fire_bank(room: Dictionary) -> void:
	var enemy: BattleShip = _b.enemy
	var player: BattleShip = _b.player
	var from_view: ShipView = _b._enemy_view
	var to_view: ShipView = _b._player_view
	var hit_chance := enemy.accuracy * (1.0 - player.evasion())
	for i in enemy.guns:
		var from: Vector2 = from_view.transform * from_view.muzzle_in(room, i, enemy.guns)
		_b._vfx.muzzle_flash(from, -1.0)
		if randf() < hit_chance:
			var local_hit := to_view.random_hit_point()
			_b._vfx.fire_shot(from, to_view.transform * local_hit, i * 0.12,
				_b._on_hit.bind(player, to_view, local_hit, "round_shot", false))
		else:
			var splash_at: Vector2 = to_view.base_position + Vector2(randf_range(60.0, 85.0), randf_range(-90.0, 90.0))
			_b._vfx.fire_shot(from, splash_at, i * 0.12, _b._vfx.splash.bind(splash_at))


# --- Phase 2: the boats --------------------------------------------------------

func _tick_boats(delta: float) -> void:
	var enemy: BattleShip = _b.enemy
	if not _boats_done and enemy.hands <= _full_hands * float(_cfg.get("boats_stop_at", 0.25)):
		_boats_done = true
		_b._log("She has no more marines to send. Now finish her!")
	if not _boats_done:
		_boat_timer -= delta
		if _boat_timer <= 0.0:
			_boat_timer = float(_cfg.get("boat_every", 12.0))
			_launch_boat()
	for boat: Dictionary in boats.duplicate():
		boat["t"] = float(boat["t"]) + delta / float(_cfg.get("boat_time", 14.0))
		boat["fire"] = float(boat["fire"]) - delta
		if float(boat["fire"]) <= 0.0:
			boat["fire"] = BOAT_FIRE_EVERY * randf_range(0.8, 1.2)
			_b.player.lose_hands(randi_range(0, 2))  # swivel guns and musketry
			_b._vfx.muzzle_flash(_boat_pos(boat), -1.0)
		if float(boat["t"]) >= 1.0:
			boats.erase(boat)
			marines_aboard += float(boat["marines"])
			_b._log("Boarders! %d marines over the rail!" % int(boat["marines"]))
			_b._vfx.shake(4.0)
	if boats.is_empty():
		targeting_boats = false


func _launch_boat() -> void:
	var enemy: BattleShip = _b.enemy
	var marines := mini(int(_cfg.get("boat_marines", 20)), enemy.hands - 1)
	if marines <= 0:
		_boats_done = true
		return
	enemy.hands -= marines
	boats.append({"t": 0.0, "y": randf_range(-70.0, 70.0), "hull": int(_cfg.get("boat_hull", 6)),
		"marines": marines, "fire": BOAT_FIRE_EVERY})
	if boats.size() == 1:
		_b._log("Boats in the water! Marines pulling for us. Press X to fire on them.")


## Our broadside, aimed at the boats instead of the flagship. `hits` is one
## entry per gun (true for a hit), as BattleShip.fire returns.
func fire_at_boats(hits: Array, ammo_id: String) -> void:
	var a := Data.get_item("ammo", ammo_id)
	var from_view: ShipView = _b._player_view
	for i in hits.size():
		var from: Vector2 = from_view.transform * from_view.muzzle_point(_b.player.engaged_side, i, hits.size())
		if boats.is_empty() or not hits[i]:
			var miss := _water_point()
			_b._vfx.fire_shot(from, miss, i * 0.09, _b._vfx.splash.bind(miss))
			continue
		var boat: Dictionary = boats.pick_random()
		_b._vfx.fire_shot(from, _boat_pos(boat), i * 0.09, _hit_boat.bind(boat, int(a.get("hull_damage", 1)), int(a.get("crew_damage", 0))))


func _hit_boat(boat: Dictionary, hull_damage: int, crew_damage: int) -> void:
	if not boats.has(boat):
		return
	_b._vfx.impact(_boat_pos(boat))
	boat["hull"] = int(boat["hull"]) - hull_damage
	boat["marines"] = int(boat["marines"]) - crew_damage * 2 - 1  # packed shoulder to shoulder
	if int(boat["hull"]) <= 0 or int(boat["marines"]) <= 0:
		boats.erase(boat)
		_b._vfx.splash(_boat_pos(boat))
		_b._log("A boat goes down with all aboard!")


func _boat_pos(boat: Dictionary) -> Vector2:
	var from: Vector2 = _b._enemy_view.base_position + Vector2(-70.0, 0.0)
	var to: Vector2 = _b._player_view.base_position + Vector2(45.0, 0.0)
	return from.lerp(to, clampf(float(boat["t"]), 0.0, 1.0)) + Vector2(0.0, float(boat["y"]))


func _water_point() -> Vector2:
	var a: Vector2 = _b._player_view.base_position
	var c: Vector2 = _b._enemy_view.base_position
	return a.lerp(c, randf_range(0.3, 0.7)) + Vector2(0.0, randf_range(-90.0, 90.0))


## Marines who made it aboard fight our hands until one side is gone.
func _tick_melee(delta: float) -> void:
	if marines_aboard <= 0.0:
		return
	_melee_t += delta
	if _melee_t < 1.0:
		return
	_melee_t = 0.0
	var player: BattleShip = _b.player
	var ours: float = _b._crew_buff(_b.player_crew, "boarding") * player.morale_factor * Perks.mult(GameState.run, "boarding") * DEFENDER_BONUS
	var lost := maxi(1, roundi(marines_aboard * MARINES_KILL))
	marines_aboard = maxf(0.0, marines_aboard - maxf(1.0, player.hands * HANDS_KILL * ours))
	player.lose_hands(lost)
	_b._vfx.melee_clash(_b._player_view.transform * _b._player_view.random_hit_point())
	if marines_aboard <= 0.0:
		_b._log("The last of the boarders is cut down. The deck is ours!")


# --- Phase 3: the great gun ------------------------------------------------------

func _tick_great_gun(delta: float) -> void:
	var enemy: BattleShip = _b.enemy
	var view: ShipView = _b._enemy_view
	var room := view.room_by_id("great_gun")
	var working := DamageControl.efficiency(enemy.rooms[room["id"]]) if not room.is_empty() else 1.0
	var before := great_gun_ratio()
	_great_gun += delta * maxf(0.6, working)  # her gun crew keep loading through fire and damage
	if before < 0.8 and great_gun_ratio() >= 0.8:
		_b._log("The great gun is run out! Brace!")
	if great_gun_ratio() < 1.0:
		return
	_great_gun = 0.0
	var player: BattleShip = _b.player
	var to_view: ShipView = _b._player_view
	var from: Vector2 = view.transform * (room["rect"] as Rect2).get_center() if not room.is_empty() else view.base_position
	_b._vfx.muzzle_flash(from, -1.0)
	_b._vfx.shake(6.0)
	if randf() < float(_cfg.get("great_gun_accuracy", 0.75)) * (1.0 - player.evasion()):
		var local_hit := to_view.random_hit_point()
		_b._vfx.fire_shot(from, to_view.transform * local_hit, 0.0, _great_gun_hit.bind(local_hit))
	else:
		var miss: Vector2 = to_view.base_position + Vector2(randf_range(60.0, 85.0), randf_range(-90.0, 90.0))
		_b._vfx.fire_shot(from, miss, 0.0, _b._vfx.splash.bind(miss))
		_b._log("The great gun's shot screams past and throws up a wall of water.")


func _great_gun_hit(local_hit: Vector2) -> void:
	var player: BattleShip = _b.player
	var to_view: ShipView = _b._player_view
	var at: Vector2 = to_view.transform * local_hit
	explosion(at)
	player.hull = maxi(0, player.hull - roundi(player.max_hull * float(_cfg.get("great_gun_damage", 0.25))))
	for room in to_view.rooms:  # holed below the waterline, everywhere
		if DamageControl.LEAK_ROOMS.has(room["type"]):
			player.rooms[room["id"]]["leak"] = true
			player.rooms[room["id"]]["plug"] = 0.0
	to_view.add_hole(local_hit)
	_b._log("The great gun hits us! Holed below the waterline, every hand to the pumps!")
	_b._check_end()
	_b._refresh_ui()


func great_gun_ratio() -> float:
	return clampf(_great_gun / float(_cfg.get("great_gun_reload", 22.0)), 0.0, 1.0)


# --- Phases ----------------------------------------------------------------------

## Her hull pool is empty. Returns true if that only ended a phase (the fight
## goes on), false if it was the last pool and she's finished.
func hull_gone() -> bool:
	if phase >= PHASES:
		return false
	_wreck_bank()
	boats.clear()
	targeting_boats = false
	_b._over = true  # a lull while she fights her fires
	var hull := roundi(_b.player.max_hull * float(_cfg.get("breather_hull", 0.3)))
	var what := "Her upper gun deck goes up in a sheet of flame!" if phase == 1 else "A second deck erupts and her mainmast comes down!"
	_b._show_choices("%s The %s hauls off to fight her fires. A breathing space, and time for one thing:" % [what, _b.enemy.display_name], [
		["All hands to patch the hull (+%d hull, leaks plugged)" % hull, _breather.bind("hull", hull)],
		["Tend the wounded (every specialist +%d health)" % BREATHER_HEAL, _breather.bind("heal", 0)],
		["Splice the mainbrace (+%d morale, guns reloaded)" % BREATHER_MORALE, _breather.bind("rally", 0)],
	])
	return true


func _breather(choice: String, hull: int) -> void:
	var player: BattleShip = _b.player
	match choice:
		"hull":
			player.hull = mini(player.max_hull, player.hull + hull)
			for id: Variant in player.rooms:
				player.rooms[id]["leak"] = false
				player.rooms[id]["flood"] = 0.0
		"heal":
			for c: BattleCrew in _b.player_crew:
				if c.alive:
					c.heal(BREATHER_HEAL)
		"rally":
			Morale.change(GameState.run, BREATHER_MORALE)
			player.morale_factor = Morale.factor(GameState.run.morale)
			for side: String in BattleShip.SIDES:
				player.reloads[side] = player.reload_time
	phase += 1
	_start_pool()
	_boat_timer = 0.0
	if phase == 3:
		_great_gun = float(_cfg.get("great_gun_reload", 22.0)) * GREAT_GUN_HEAD_START  # she was loading it during the lull
	if phase == 2:
		for i in int(_cfg.get("boats_at_start", 2)):
			_launch_boat()
		_boat_timer = float(_cfg.get("boat_every", 12.0))
	_b._end_hail(false)  # closes the choice and lets the fight go on
	_b._log("She comes on again. %s" % ("Boats in the water! Press X to fire on them." if phase == 2 else "She's running out her great gun!"))


## The highest bank still firing blows up: its deck is wrecked and burning.
func _wreck_bank() -> void:
	var enemy: BattleShip = _b.enemy
	var view: ShipView = _b._enemy_view
	for i in range(_bank_alive.size() - 1, -1, -1):
		if not _bank_alive[i]:
			continue
		_bank_alive[i] = false
		for side: String in BattleShip.SIDES:
			var rooms := view.gun_rooms(side)
			if i < rooms.size():
				var state: Dictionary = enemy.rooms[rooms[i]["id"]]
				state["damage"] = DamageControl.ROOM_HP
				DamageControl.ignite(state)
				for k in 3:
					get_tree().create_timer(k * 0.25, false).timeout.connect(
						explosion.bind(view.transform * (rooms[i]["rect"] as Rect2).get_center()))
		return


func banks_left() -> int:
	return _bank_alive.count(true)


func explosion(at: Vector2) -> void:
	_b._vfx.explosion(at)


## One line for her status display.
func status() -> String:
	var text := "PHASE %d OF %d   %d GUN DECK%s" % [phase, PHASES, banks_left(), "" if banks_left() == 1 else "S"]
	if phase == 2 and not boats.is_empty():
		text += "   %d BOAT%s" % [boats.size(), "" if boats.size() == 1 else "S"]
	if phase == 3:
		text += "   GREAT GUN %d%%" % roundi(great_gun_ratio() * 100.0)
	return text


func _draw() -> void:
	for boat: Dictionary in boats:
		var p := _boat_pos(boat)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-9, 0), p + Vector2(-5, -3), p + Vector2(6, -3), p + Vector2(6, 3), p + Vector2(-5, 3)]), BOAT_COLOR)
		for k in mini(4, ceili(int(boat["marines"]) / 5.0)):  # a red coat per five marines
			draw_circle(p + Vector2(-3 + k * 3, 0), 1.2, Color("b03a2e"))
		if targeting_boats:
			draw_arc(p, 11.0, 0, TAU, 14, Color(1, 0.9, 0.4, 0.8), 1.0)
