class_name Boarding
extends RefCounted
## Grappling and boarding between the two ships in a battle.
##
## Stages (each is a plain chance roll for now; mini-games replace them later):
##   grappling  one ship throws hooks; each hook pulls the ships closer, which
##              makes broadsides more accurate for both. The other ship can cut
##              hooks. A ship with hooks in her can barely run.
##   lashed     all hooks fast: no running, no turning, and both batteries fall
##              silent. The ship that grappled may board first; either side may
##              try to cut loose.
##   melee      a boarding party fights the defending hands in rounds. Hands
##              sent across leave their own ship short. Defenders fight harder
##              on their own deck. A side breaks when it's badly outmatched:
##              beaten defenders surrender (prisoners); beaten boarders fall
##              back home and the initiative passes to the other ship.

const HOOKS_NEEDED := 3
const THROW_COOLDOWN := 2.0  # seconds between grapple throws or cuts
const THROW_CHANCE := 0.45
const CUT_CHANCE := 0.5
const CLOSE_ACCURACY := 0.2  # added hit chance when fully pulled together
const DEFENDER_BONUS := 1.25
const ROUND_TIME := 1.5
const LOSS_RATE := 0.08  # share of the enemy's strength lost per round
const BREAK_RATIO := 0.25  # a side breaks when it has less than this of the other's strength
const WOUND_PER_ROUND := 6.0  # to each specialist fighting in the melee

var state := "none"  # none, grappling, lashed, melee, taken
var hooks := 0
var grappler: BattleShip = null  # whose hooks are in
var initiative: BattleShip = null  # who may board next while lashed
var attacker: BattleShip = null
var defender: BattleShip = null
var party := 0  # attackers still fighting
var wiped_out := false  # the last boarding party died to the last man
var pull := 0.0  # how far the ships have been drawn together, 0 to 1 (eased)

var _cooldowns := {}  # BattleShip -> seconds
var _round_t := 0.0


func closeness() -> float:
	return float(hooks) / HOOKS_NEEDED


func guns_silent() -> bool:
	return state == "lashed" or state == "melee" or state == "taken"


func is_lashed() -> bool:
	return state == "lashed" or state == "melee" or state == "taken"


func cooldown(ship: BattleShip) -> float:
	return float(_cooldowns.get(ship, 0.0))


func tick(delta: float) -> void:
	for ship: BattleShip in _cooldowns:
		_cooldowns[ship] = maxf(0.0, float(_cooldowns[ship]) - delta)
	pull = move_toward(pull, closeness(), delta * 0.6)


## Throws a grapple at the other ship. Returns "hooked", "lashed", "missed"
## or "" if a throw isn't possible right now.
func try_throw(ship: BattleShip, skill: float) -> String:
	if is_lashed() or cooldown(ship) > 0.0 or (grappler != null and grappler != ship):
		return ""
	_cooldowns[ship] = THROW_COOLDOWN
	if randf() >= clampf(THROW_CHANCE * skill, 0.05, 0.95):
		return "missed"
	hooks += 1
	grappler = ship
	state = "grappling"
	if hooks >= HOOKS_NEEDED:
		state = "lashed"
		initiative = ship
		return "lashed"
	return "hooked"


## Testing shortcut: all hooks fast at once, with `ship` to board first.
func debug_lash(ship: BattleShip) -> void:
	if state == "melee":
		return
	hooks = HOOKS_NEEDED
	grappler = ship
	initiative = ship
	state = "lashed"


## Cuts one hook. Either ship can cut, except during a melee. Returns "cut",
## "free" (no hooks left), "failed", or "" if not possible right now.
func try_cut(ship: BattleShip, skill: float) -> String:
	if hooks == 0 or state == "melee" or cooldown(ship) > 0.0:
		return ""
	_cooldowns[ship] = THROW_COOLDOWN
	if randf() >= clampf(CUT_CHANCE * skill, 0.05, 0.95):
		return "failed"
	hooks -= 1
	if hooks == 0:
		state = "none"
		grappler = null
		initiative = null
		return "free"
	state = "grappling"
	return "cut"


## Sends `size` hands from `from` across to `to`.
func start_melee(from: BattleShip, to: BattleShip, size: int) -> void:
	size = clampi(size, 1, from.hands)
	from.lose_hands(size)
	attacker = from
	defender = to
	party = size
	wiped_out = false
	state = "melee"
	_round_t = 0.0


## Runs the melee. Returns "round" after each exchange, "repelled" when the
## boarders break, "taken" when the defenders surrender, else "".
func tick_melee(delta: float, attack_buff: float, defend_buff: float) -> String:
	if state != "melee":
		return ""
	_round_t += delta
	if _round_t < ROUND_TIME:
		return ""
	_round_t = 0.0
	var attack := party * attack_buff
	var defend := defender.hands * DEFENDER_BONUS * defend_buff
	party = maxi(0, party - ceili(defend * LOSS_RATE * randf_range(0.5, 1.5)))
	defender.lose_hands(ceili(attack * LOSS_RATE * randf_range(0.5, 1.5)))
	attack = party * attack_buff
	defend = defender.hands * DEFENDER_BONUS * defend_buff
	if party <= 0 or attack < defend * BREAK_RATIO:
		wiped_out = party <= 0
		fall_back()
		return "repelled"
	if defender.hands <= 0 or defend < attack * BREAK_RATIO:
		# The boarders hold her deck; the survivors are still our crew.
		attacker.hands = mini(attacker.max_hands, attacker.hands + party)
		state = "taken"
		return "taken"
	return "round"


## The boarders retreat to their own ship; the other side gets the initiative.
func fall_back() -> void:
	attacker.hands = mini(attacker.max_hands, attacker.hands + party)
	party = 0
	initiative = defender
	state = "lashed"
