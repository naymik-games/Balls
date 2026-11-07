extends Control
## Title screen: Classic and Levels tiles, plus two debug-ish controls in the lower
## corners (reset progress, unlock-all toggle) that you can delete before release.
##
## Scene setup: New Scene > root node "Control" > attach this script > save as
## res://scenes/main_menu.tscn, then make it the project's main scene.
## Everything is built in code.

## Change the working title here (also set Project Settings > Application > Config > Name).
const GAME_TITLE := "SplitShot"

const BG := Color(0.09, 0.10, 0.15)
const ACCENT := Color(0.459, 0.732, 0.487)
const TILE_BG := Color(0.15, 0.17, 0.25)
const TILE_SIZE := Vector2(300.0, 96.0)

var _progress_label: Label
var _confirm: ConfirmationDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	var title := Label.new()
	title.text = GAME_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 24.0)
	box.add_child(gap)

	var classic := _tile("Classic", "", true)
	classic.pressed.connect(Session.start_classic)
	box.add_child(classic)

	var levels := _tile("Levels", "", false)
	levels.pressed.connect(Session.open_select)
	box.add_child(levels)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 16)
	_progress_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	box.add_child(_progress_label)
	_refresh_progress()

	_build_corner_controls()


func _build_corner_controls() -> void:
	var reset := Button.new()
	reset.text = "Reset progress"
	reset.focus_mode = Control.FOCUS_NONE
	reset.add_theme_font_size_override("font_size", 14)
	reset.pressed.connect(_on_reset_pressed)
	add_child(reset)
	reset.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)

	var unlock := CheckButton.new()
	unlock.text = "Unlock all (debug)"
	unlock.focus_mode = Control.FOCUS_NONE
	unlock.add_theme_font_size_override("font_size", 14)
	unlock.button_pressed = Session.debug_unlock_all  # set before connecting, so it doesn't fire
	unlock.toggled.connect(Session.set_debug_unlock_all)
	add_child(unlock)
	unlock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Reset progress"
	_confirm.dialog_text = "Erase all level progress and best scores?"
	_confirm.ok_button_text = "Reset"
	_confirm.confirmed.connect(_on_reset_confirmed)
	add_child(_confirm)


func _on_reset_pressed() -> void:
	_confirm.popup_centered()


func _on_reset_confirmed() -> void:
	Session.reset_progress()
	_refresh_progress()


func _refresh_progress() -> void:
	var count := Session.level_count()
	if count == 0:
		_progress_label.text = "No levels baked yet"
	else:
		_progress_label.text = "Levels: %d / %d cleared" % [Session.completed_count(), count]


## A big two-line button: title plus an optional smaller subtitle.
func _tile(title: String, subtitle: String, primary: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = TILE_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.text = title if subtitle == "" else "%s\n%s" % [title, subtitle]
	b.add_theme_font_size_override("font_size", 28)
	var bg := ACCENT.darkened(0.25) if primary else TILE_BG
	b.add_theme_stylebox_override("normal", _box(bg))
	b.add_theme_stylebox_override("hover", _box(bg.lightened(0.08)))
	b.add_theme_stylebox_override("pressed", _box(bg.lightened(0.16)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _box(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(12)
	return sb
