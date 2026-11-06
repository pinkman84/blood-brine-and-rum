extends ScreenBase
## An event node: a scene, a few choices, and what came of the one you made.
## Choices whose requirements you don't meet show greyed out with the reason.
## The rules live in scripts/core/events.gd; the events in data/events.
## Storm and treasure nodes draw from their own pools. A forced event (a
## mutiny) happens between nodes, so it returns to the map without moving on.

var _event: Dictionary = {}
var _result_lines: Array[String] = []
var _result_text := ""
var _battle := ""  # set if the outcome turned into a fight
var _interlude := false  # a forced event between nodes (see GameState.finish_node)


func _title() -> String:
	return str(_event.get("title", "Calm seas"))


func _ready() -> void:
	var run: RunState = GameState.run
	if run.forced_event != "" and Data.has_item("events", run.forced_event):
		_event = Data.get_item("events", run.forced_event)
		_interlude = true
	else:
		_event = Events.pick(run, _pool(run))
	if not _event.is_empty() and not _interlude:
		run.seen_events.append(_event["id"])
	super()


## Which pool this node draws from: "storm", "treasure", or "" for a "?" node.
func _pool(run: RunState) -> String:
	var here := int(run.map.get("current", -1))
	if here < 0:
		return ""
	var type := str(run.map["nodes"][here].get("type", ""))
	return type if type == "storm" or type == "treasure" else ""


func _build() -> void:
	if _event.is_empty():
		_result_text = "Calm seas. Nothing happens."
		add_button("Sail on", GameState.finish_node)
		return
	var run: RunState = GameState.run
	for choice: Dictionary in _event.get("choices", []):
		var why := Events.unmet(run, choice.get("requires", {}))
		var label := str(choice.get("text", "..."))
		if why != "":
			label += " (%s)" % why
		add_button(label, _choose.bind(choice), why == "")


func refresh() -> void:
	var body := str(_event.get("text", ""))
	if _result_text != "":
		body = _result_text
		if not _result_lines.is_empty():
			body += "\n\n" + ", ".join(_result_lines) + "."
	_info.text = body + "\n\n" + run_summary()


func _choose(choice: Dictionary) -> void:
	var outcome := Events.roll_outcome(choice.get("outcomes", []))
	var effects: Dictionary = outcome.get("effects", {})
	_result_text = str(outcome.get("text", ""))
	_result_lines = Events.apply(GameState.run, effects)
	_battle = str(effects.get("battle", ""))
	for button in _buttons.get_children():
		button.queue_free()
	GameState.run.forced_event = ""
	if bool(effects.get("end_run", false)):
		add_button("Over the side...", GameState.end_run.bind(false))
		refresh()
		return
	if _interlude:
		add_button("Back to the helm", GameState.resume_map)
	elif _battle != "":
		if _battle != "random":
			GameState.run.forced_enemy = _battle
		add_button("Clear for action!", GameState.change_screen.bind(GameState.Screen.BATTLE))
	else:
		add_button("Sail on", GameState.finish_node)
	SaveSystem.save_run(GameState.run)
	refresh()
