class_name Morale
extends RefCounted
## Crew morale: a ship stat from 0 to 100 that scales how hard the hands work.
##
## High morale speeds every timing a little and makes boarders fight harder;
## low morale slows everything, and in port unhappy hands desert. Rum is
## drunk one ration per node; running dry hurts morale.
## Later: a mutiny event below MUTINY, and pirate havens for rest and
## recreation (see the plan, Phase 5).

const START := 70
const HIGH := 75
const LOW := 40
const MUTINY := 20

const START_RUM := 10
const NO_RUM := -6  # each node sailed with an empty rum cask

# Battle results
const WIN := 5
const CAPTURE := 3  # on top of WIN when she strikes or is boarded
const FREED_CAPTIVES := 5
const SPECIALIST_DIED := -8  # each
const HEAVY_LOSSES := -6  # lost more than a quarter of the hands in one fight
const HEAVY_LOSS_SHARE := 0.25
const RAN_AWAY := -5
const ENEMY_ESCAPED := -2
const PRESSED_PRISONERS := -4

# Port
const DRINK := 10  # standing the crew a drink


## How much harder (or slower) the hands work at this morale.
static func factor(morale: int) -> float:
	if morale < MUTINY:
		return 0.8
	if morale < LOW:
		return 0.9
	if morale >= HIGH:
		return 1.1
	return 1.0


static func mood(morale: int) -> String:
	if morale < MUTINY:
		return "mutinous"
	if morale < LOW:
		return "sullen"
	if morale >= HIGH:
		return "in high spirits"
	return "steady"


## Applies a change to the run's morale. Returns the change actually made.
static func change(run: RunState, amount: int) -> int:
	var before := run.morale
	run.morale = clampi(run.morale + amount, 0, 100)
	return run.morale - before


## Share of hands who desert on reaching port, when morale is low.
static func desertion_share(morale: int) -> float:
	if morale >= LOW:
		return 0.0
	return float(LOW - morale) / 100.0
