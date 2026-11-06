extends ScreenBase
## The sea chart: shown at each sea's exit (except before the last leg).
## Pick which sea to sail into next. Placeholder layout; a drawn chart of the
## world comes later.

var _options: Array = []


func _title() -> String:
	return "The sea chart"


func _build() -> void:
	var run: RunState = GameState.run
	_options = Voyage.chart_options(run)
	if _options.is_empty():  # nothing left to choose: straight on to the final sea
		Voyage.enter_sea(run, Voyage.FINAL_SEA)
		_sail()
		return
	for s: Dictionary in _options:
		add_button("Set a course for %s" % s.get("name", "?"), _choose.bind(str(s["id"])))


func refresh() -> void:
	var run: RunState = GameState.run
	var lines: Array[String] = []
	lines.append("Sea %d of %d. Where next, captain?" % [run.sea_number, RunState.SEAS_PER_RUN])
	lines.append("")
	for s: Dictionary in _options:
		lines.append("%s: %s" % [s.get("name", "?"), s.get("description", "")])
		lines.append("")
	lines.append("The voyage ends in %s." % Data.get_item("seas", Voyage.FINAL_SEA).get("name", "the Company's home waters"))
	_info.text = "\n".join(lines)


func _choose(id: String) -> void:
	Voyage.enter_sea(GameState.run, id)
	_sail()


func _sail() -> void:
	SaveSystem.save_run(GameState.run)
	GameState.change_screen.call_deferred(GameState.Screen.SEA_MAP)
