class_name ScreenBase
extends Control
## A placeholder screen: title, then info text on the left and a scrolling
## column of buttons on the right, so any number of options fits on screen.
## Each screen extends this and overrides _title(), _build() and refresh().
## Later phases replace these with real screens one at a time.

const BG_COLOR := Color("1b2633")
const FONT_SIZE := 12
const INFO_WIDTH := 280

var _info: Label
var _buttons: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var theme_ := Theme.new()
	theme_.default_font_size = FONT_SIZE
	theme = theme_

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title := Label.new()
	title.text = _title()
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)

	_info = Label.new()
	_info.custom_minimum_size = Vector2(INFO_WIDTH, 0)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_info)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_buttons = VBoxContainer.new()
	_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buttons.add_theme_constant_override("separation", 4)
	scroll.add_child(_buttons)

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
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long choices wrap onto a second line
	button.pressed.connect(action)
	_buttons.add_child(button)
	return button


func run_summary() -> String:
	return summary(GameState.run)


static func summary(run: RunState) -> String:
	if run == null:
		return ""
	return "Sea %d of %d (%s)   Step %d of %d\nGold %d   Hull %d/%d   Sails %d/%d\nHands %d/%d   Specialists %d\nMorale %d (%s)   Rum %d%s\nCompany hunt %d%%%s" % [
		run.sea_number, RunState.SEAS_PER_RUN, Voyage.sea_name(run),
		run.node_index + 1, RunState.NODES_PER_SEA,
		run.gold, run.hull, run.max_hull, run.sails, run.max_sails,
		run.hands, run.max_hands, run.crew.size(),
		run.morale, Morale.mood(run.morale), run.rum, "  (cask dry!)" if run.rum <= 0 else "",
		run.hunt, "  (hunters about!)" if run.hunt >= Voyage.HUNTED else "",
	]
