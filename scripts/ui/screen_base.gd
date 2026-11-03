class_name ScreenBase
extends Control
## A placeholder screen: title, info text and a column of buttons.
## Each screen extends this and overrides _title(), _build() and refresh().
## Later phases replace these with real screens one at a time.

const BG_COLOR := Color("1b2633")

var _info: Label
var _buttons: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = _title()
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)

	_info = Label.new()
	column.add_child(_info)

	_buttons = VBoxContainer.new()
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_buttons)

	_build()
	refresh()


func _title() -> String:
	return "Screen"


## Add buttons here with add_button().
func _build() -> void:
	pass


## Update _info.text from the current state.
func refresh() -> void:
	pass


func add_button(text: String, action: Callable, enabled := true) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.pressed.connect(action)
	_buttons.add_child(button)
	return button


func run_summary() -> String:
	var run: RunState = GameState.run
	if run == null:
		return ""
	return "Sea %d of %d   Node %d of %d\nGold %d   Hull %d/%d   Sails %d/%d   Crew %d" % [
		run.sea_number, RunState.SEAS_PER_RUN,
		run.node_index + 1, RunState.NODES_PER_SEA,
		run.gold, run.hull, run.max_hull, run.sails, run.max_sails, run.crew.size(),
	]
