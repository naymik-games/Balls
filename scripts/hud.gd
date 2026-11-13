extends CanvasLayer

signal reset_pressed
signal speed_pressed
signal ability_pressed(kind: String)
signal primary_button_pressed
signal secondary_button_pressed
signal extra_button_pressed
signal return_pressed

var _ability_buttons := {}
var _round_label: Label
var _balls_label: Label
var _speed_icon: Control
var _speed := 1

# End Panel UI Node References (adjust paths if your node names differ)
@onready var end_panel: ColorRect = $EndPanel
@onready var title_label: Label = $EndPanel/CenterContainer/Panel/VBox/TitleLabel
@onready var details_label: Label = $EndPanel/CenterContainer/Panel/VBox/DetailsLabel
@onready var primary_button: Button = $EndPanel/CenterContainer/Panel/VBox/PrimaryButton
@onready var secondary_button: Button = $EndPanel/CenterContainer/Panel/VBox/SecondaryButton
@onready var extra_button: Button = $EndPanel/CenterContainer/Panel/VBox/ExtraButton
@onready var return_button: Button = $ReturnButton


func _ready() -> void:
	_round_label = _make_label(Vector2(0, 2), 48, Color.WHITE)
	_balls_label = _make_label(Vector2(0, 54), 20, Color(0.7, 0.8, 0.9))
	
	if end_panel:
		end_panel.visible = false
		primary_button.pressed.connect(func(): primary_button_pressed.emit())
		secondary_button.pressed.connect(func(): secondary_button_pressed.emit())
		extra_button.pressed.connect(func(): extra_button_pressed.emit())

	# ... existing reset button, speed button, and ability buttons setup ...
	var button := Button.new()
	button.text = "Reset"
	button.position = Vector2(448, 12)
	button.size = Vector2(84, 44)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): reset_pressed.emit())
	add_child(button)
	
	var speed_button := Button.new()
	speed_button.position = Vector2(462, 922)
	speed_button.size = Vector2(68, 32)
	speed_button.focus_mode = Control.FOCUS_NONE
	speed_button.pressed.connect(func(): speed_pressed.emit())
	add_child(speed_button)

	_speed_icon = Control.new()
	_speed_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_icon.draw.connect(_draw_speed_icon)
	speed_button.add_child(_speed_icon)
	
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
	
	# Connect the return button if it exists in the scene
	if return_button:
		return_button.focus_mode = Control.FOCUS_NONE
		return_button.pressed.connect(func(): return_pressed.emit())
	
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

func show_end_panel(title: String, details: String, primary_text: String, secondary_text: String, extra_text: String = "") -> void:
	if not end_panel:
		return
	title_label.text = title
	details_label.text = details
	
	primary_button.text = primary_text
	primary_button.visible = not primary_text.is_empty()
	
	secondary_button.text = secondary_text
	secondary_button.visible = not secondary_text.is_empty()
	
	extra_button.text = extra_text
	extra_button.visible = not extra_text.is_empty()
	
	end_panel.visible = true

func hide_game_over() -> void:
	if end_panel:
		end_panel.visible = false

# ... keep set_ability, set_speed, _draw_speed_icon as before ...


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


func set_return_text(text: String) -> void:
	if return_button:
		return_button.text = text
