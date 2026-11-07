class_name LevelUI
extends RefCounted
## In-game UI for Levels mode, built in code so the HUD scene isn't touched:
##   - make_back_button(): small "Levels" button shown while playing a level
##   - make_end_panel():   win / lose panel with Next, Retry and Levels buttons
## main.gd adds the returned CanvasLayers as children.

const PANEL_BG := Color(0.14, 0.16, 0.24)
const BUTTON_BG := Color(0.20, 0.23, 0.33)
const ACCENT := Color(0.459, 0.732, 0.487)
const LOSE_COLOR := Color(0.90, 0.35, 0.40)
## Move this if it overlaps your HUD.
const BACK_BUTTON_POS := Vector2(8.0, 8.0)


## "Levels" while playing a level, "Menu" in Classic mode.
static func make_back_button() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 5
	var in_level := Session.current_number > 0
	var b := _button("Levels" if in_level else "Menu", false)
	b.custom_minimum_size = Vector2(76.0, 36.0)
	b.position = BACK_BUTTON_POS
	b.pressed.connect(Session.open_select if in_level else Session.open_menu)
	layer.add_child(b)
	return layer


## `info` is what Session.complete_level() returned (empty on a loss).
## `shots` is shots taken on a win, or the shot reached on a loss.
static func make_end_panel(game: Node, won: bool, shots: int, info: Dictionary) -> CanvasLayer:
	var n := Session.current_number
	var layer := CanvasLayer.new()
	layer.layer = 10

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, 18, 24))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(300.0, 0.0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	if won:
		box.add_child(_label("Level %d cleared" % n, 28, ACCENT))
		var line := "%d shots" % shots
		var par := Session.par_of(n)
		if par > 0:
			line += "   (par %d)" % par
		box.add_child(_label(line, 18, Color.WHITE))
		var best := int(info.get("best", shots))
		var best_text := "New best!" if info.get("new_best", false) else "Best: %d" % best
		box.add_child(_label(best_text, 16, Color(1, 1, 1, 0.65)))
		if info.get("has_next", false):
			var next := _button("Next level", true)
			next.pressed.connect(Session.start_level.bind(n + 1))
			box.add_child(next)
		var retry := _button("Retry", false)
		retry.pressed.connect(game.reset_game)
		box.add_child(retry)
	else:
		box.add_child(_label("Level %d failed" % n, 28, LOSE_COLOR))
		box.add_child(_label("Blocks reached the bottom on shot %d" % shots, 16, Color(1, 1, 1, 0.65)))
		var retry := _button("Retry", true)
		retry.pressed.connect(game.reset_game)
		box.add_child(retry)

	var levels := _button("Levels", false)
	levels.pressed.connect(Session.open_select)
	box.add_child(levels)
	return layer


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 48.0)
	b.add_theme_font_size_override("font_size", 18)
	var bg := ACCENT.darkened(0.25) if primary else BUTTON_BG
	b.add_theme_stylebox_override("normal", _box(bg, 12, 8))
	b.add_theme_stylebox_override("hover", _box(bg.lightened(0.1), 12, 8))
	b.add_theme_stylebox_override("pressed", _box(bg.lightened(0.2), 12, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func _box(bg: Color, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb
