extends CanvasLayer
## Round counter, reserve counter, reset button, game-over message.
## Built in code so the scene is just a CanvasLayer + this script.


signal reset_pressed
signal speed_pressed
signal ability_pressed(kind: String)

var _ability_buttons := {}
var _round_label: Label
var _balls_label: Label
var _game_over_label: Label
var _speed_icon: Control
var _speed := 1



func _ready() -> void:
	_round_label = _make_label(Vector2(0, 2), 48, Color.WHITE)
	_balls_label = _make_label(Vector2(0, 54), 20, Color(0.7, 0.8, 0.9))

	_game_over_label = _make_label(Vector2(0, 380), 56, Color(1.0, 0.4, 0.4))
	_game_over_label.visible = false

	var button := Button.new()
	button.text = "Reset"
	button.position = Vector2(448, 12)
	button.size = Vector2(84, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): reset_pressed.emit())
	add_child(button)
	
		# Speed button (bottom right). The icon is drawn in code: 1-3 play triangles.
	var speed_button := Button.new()
	speed_button.position = Vector2(462, 922)
	speed_button.size = Vector2(68, 32)
	speed_button.focus_mode = Control.FOCUS_NONE
	speed_button.pressed.connect(func(): speed_pressed.emit())
	add_child(speed_button)

	_speed_icon = Control.new()
	_speed_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let the button get the click
	_speed_icon.draw.connect(_draw_speed_icon)
	speed_button.add_child(_speed_icon)
	
		# Ability buttons (bottom left)
	var x := 8.0
	for a in ["bump", "bounce", "boost"]:
		var b := Button.new()
		b.position = Vector2(x, 922)
		b.size = Vector2(78, 32)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): ability_pressed.emit(a))
		add_child(b)
		_ability_buttons[a] = b
		x += 84.0


func _make_label(pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(540, font_size + 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func set_round(value: int) -> void:
	_round_label.text = str(value)


func set_balls(value: int) -> void:
	_balls_label.text = "Balls: %d" % value


func show_game_over(final_round: int) -> void:
	_game_over_label.text = "Game Over\nRound %d" % final_round
	_game_over_label.size.y = 160
	_game_over_label.visible = true


func hide_game_over() -> void:
	_game_over_label.visible = false


func set_ability(kind: String, uses: int, enabled: bool, active: bool) -> void:
	var b: Button = _ability_buttons[kind]
	b.text = "%s %d" % [kind.capitalize(), uses]
	b.disabled = not enabled
	b.modulate = Color(1.0, 0.8, 0.3) if active else Color.WHITE

func set_speed(value: int) -> void:
	_speed = value
	_speed_icon.queue_redraw()


func _draw_speed_icon() -> void:
	var tri_w := 10.0
	var tri_h := 14.0
	var gap := 4.0
	var total := _speed * tri_w + (_speed - 1) * gap
	var x := (_speed_icon.size.x - total) / 2.0
	var cy := _speed_icon.size.y / 2.0
	var color := Color.WHITE if _speed == 1 else Color(1.0, 0.8, 0.3)
	for i in _speed:
		var pts := PackedVector2Array([
			Vector2(x, cy - tri_h / 2.0),
			Vector2(x + tri_w, cy),
			Vector2(x, cy + tri_h / 2.0),
		])
		_speed_icon.draw_colored_polygon(pts, color)
		x += tri_w + gap
