extends Control
## Level select: a scrollable grid of LevelCards.
##
## Scene setup: New Scene > root node "Control" > attach this script > save as
## res://scenes/level_select.tscn. The whole UI is built in code, so there is nothing
## else to add to the scene.

const COLUMNS := 4
const BG := Color(0.09, 0.10, 0.15)
const MARGIN := 16

var _scroll: ScrollContainer
var _focus_card: LevelCard


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var count := Session.level_count()
	root.add_child(_header(count))

	if count == 0:
		var empty := Label.new()
		empty.text = "No levels found in res://levels/.\nBake some first (bake_levels in main.gd)."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(empty)
		return

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	center.add_child(grid)

	var target := Session.last_played if Session.last_played > 0 else Session.frontier()
	target = clampi(target, 1, count)
	for i in range(1, count + 1):
		var card := LevelCard.new()
		card.setup(i, Session.rating_of(i), Session.is_unlocked(i), Session.is_completed(i),
				int(Session.best_shots.get(i, 0)), i == Session.frontier())
		card.pressed.connect(_on_card_pressed.bind(i, card))
		grid.add_child(card)
		if i == target:
			_focus_card = card

	# Layout isn't final until a couple of frames in.
	await get_tree().process_frame
	await get_tree().process_frame
	if _focus_card != null and is_instance_valid(_focus_card):
		_scroll.ensure_control_visible(_focus_card)


func _header(count: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var menu := LevelUI._button("Menu", false)
	menu.custom_minimum_size = Vector2(76.0, 40.0)
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu.pressed.connect(Session.open_menu)
	row.add_child(menu)
	var title := Label.new()
	title.text = "Levels"
	title.add_theme_font_size_override("font_size", 32)
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var progress := Label.new()
	progress.text = "%d / %d cleared" % [Session.completed_count(), count]
	progress.add_theme_font_size_override("font_size", 16)
	progress.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	progress.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(progress)
	return row


func _on_card_pressed(n: int, card: LevelCard) -> void:
	if Session.is_unlocked(n):
		Session.start_level(n)
	else:
		card.shake()
