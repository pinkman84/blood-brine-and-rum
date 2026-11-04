extends ScreenBase
## Placeholder trading post. Phase 5 replaces this with the real shop.

const REPAIR_AMOUNT := 5
const REPAIR_COST := 10
const CHAIN_SHOT_AMOUNT := 5
const CHAIN_SHOT_COST := 8
const RECRUIT_AMOUNT := 10
const RECRUIT_COST := 15


func _title() -> String:
	return "Trading post"


func _build() -> void:
	add_button("Repair %d hull (%d gold)" % [REPAIR_AMOUNT, REPAIR_COST], _repair)
	add_button("Buy %d chain shot (%d gold)" % [CHAIN_SHOT_AMOUNT, CHAIN_SHOT_COST], _buy_chain_shot)
	add_button("Recruit %d hands (%d gold)" % [RECRUIT_AMOUNT, RECRUIT_COST], _recruit)
	add_button("Leave port", GameState.finish_node)


func refresh() -> void:
	_info.text = run_summary()


func _repair() -> void:
	var run: RunState = GameState.run
	if run.gold < REPAIR_COST or run.hull >= run.max_hull:
		return
	run.gold -= REPAIR_COST
	run.hull = mini(run.max_hull, run.hull + REPAIR_AMOUNT)
	refresh()


func _recruit() -> void:
	var run: RunState = GameState.run
	if run.gold < RECRUIT_COST or run.hands >= run.max_hands:
		return
	run.gold -= RECRUIT_COST
	run.hands = mini(run.max_hands, run.hands + RECRUIT_AMOUNT)
	refresh()


func _buy_chain_shot() -> void:
	var run: RunState = GameState.run
	if run.gold < CHAIN_SHOT_COST:
		return
	run.gold -= CHAIN_SHOT_COST
	run.ammo["chain_shot"] = int(run.ammo.get("chain_shot", 0)) + CHAIN_SHOT_AMOUNT
	refresh()
