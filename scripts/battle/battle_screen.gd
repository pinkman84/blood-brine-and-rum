extends ScreenBase
## Placeholder battle: buttons stand in for the fight. Phase 1 replaces
## this with the real broadside battle.

const WIN_GOLD := 15
const HIT_DAMAGE := 5


func _title() -> String:
	return "Battle (placeholder)"


func _build() -> void:
	add_button("Win the battle (+%d gold)" % WIN_GOLD, _win)
	add_button("Take a broadside (-%d hull)" % HIT_DAMAGE, _take_hit)
	add_button("Strike your colours (lose the run)", GameState.end_run.bind(false))


func refresh() -> void:
	_info.text = run_summary()


func _win() -> void:
	GameState.run.gold += WIN_GOLD
	GameState.run.battles_won += 1
	GameState.finish_node()


func _take_hit() -> void:
	GameState.run.hull -= HIT_DAMAGE
	if GameState.run.hull <= 0:
		GameState.end_run(false)
	else:
		refresh()
