extends ScreenBase
## Shows a random event from data/events and applies the chosen outcome.
## Phase 5 grows this into the full event system (requirements, crew checks).
##
## Supported effects so far: gold, hull (both can be negative).

var _event: Dictionary = {}
var _result_text := ""


func _title() -> String:
	return "Event"


func _build() -> void:
	var events: Array = Data.get_all("events")
	if events.is_empty():
		_result_text = "Calm seas. Nothing happens."
		add_button("Sail on", GameState.finish_node)
		return
	_event = events.pick_random()
	for choice: Dictionary in _event.get("choices", []):
		add_button(str(choice.get("text", "...")), _choose.bind(choice))


func refresh() -> void:
	var body := str(_event.get("text", "")) if _result_text.is_empty() else _result_text
	_info.text = "%s\n\n%s\n\n%s" % [_event.get("title", ""), body, run_summary()]


func _choose(choice: Dictionary) -> void:
	var outcomes: Array = choice.get("outcomes", [])
	var outcome := _roll(outcomes)
	_apply(outcome.get("effects", {}))
	_result_text = str(outcome.get("text", ""))
	for button in _buttons.get_children():
		button.queue_free()
	if GameState.run.hull <= 0:
		add_button("Go down with the ship", GameState.end_run.bind(false))
	else:
		add_button("Sail on", GameState.finish_node)
	refresh()


# Pick an outcome weighted by its "chance" (defaults to 1).
func _roll(outcomes: Array) -> Dictionary:
	if outcomes.is_empty():
		return {}
	var total := 0.0
	for o: Dictionary in outcomes:
		total += float(o.get("chance", 1.0))
	var pick := randf() * total
	for o: Dictionary in outcomes:
		pick -= float(o.get("chance", 1.0))
		if pick <= 0.0:
			return o
	return outcomes.back()


func _apply(effects: Dictionary) -> void:
	var run: RunState = GameState.run
	run.gold = maxi(0, run.gold + int(effects.get("gold", 0)))
	run.hull = mini(run.max_hull, run.hull + int(effects.get("hull", 0)))
