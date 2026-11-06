extends ScreenBase
## An event node: a scene, a few choices, and what came of the one you made.
## Choices whose requirements you don't meet show greyed out with the reason.
## The rules live in scripts/core/events.gd; the events in data/events.

var _event: Dictionary = {}
var _result_lines: Array[String] = []
var _result_text := ""
var _battle := ""  # set if the outcome turned into a fight


func _title() -> String:
	return str(_event.get("title", "Calm seas"))


func _ready() -> void:
	_event = Events.pick(GameState.run)
	if not _event.is_empty():
		GameState.run.seen_events.append(_event["id"])
	super()


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
	if _battle != "":
		if _battle != "random":
			GameState.run.forced_enemy = _battle
		add_button("Clear for action!", GameState.change_screen.bind(GameState.Screen.BATTLE))
	else:
		add_button("Sail on", GameState.finish_node)
	SaveSystem.save_run(GameState.run)
	refresh()
