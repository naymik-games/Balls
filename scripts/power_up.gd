class_name Powerup
extends Area2D
## Base class for board powerups. Balls pass straight through (this area is on no
## collision layer and balls don't mask it), but it detects a ball entering it.
## Subclasses override apply() and _draw_icon().

signal triggered(powerup: Powerup, ball: Ball)

const HIT_SIZE := 44.0  # a bit smaller than a 54px cell

var col := 0
var row := 0
## If true, the first ball to cross it uses it up.
var single_use := true
var color := Color.WHITE
var _used := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # balls
	monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(HIT_SIZE, HIT_SIZE)
	shape.shape = rect
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body is Ball or _used:
		return
	if single_use:
		_used = true  # two balls can enter in the same physics frame
	triggered.emit(self, body)


## Override. `game` is the main script (untyped, like `hud` in main.gd).
func apply(_ball: Ball, _game) -> void:
	pass


func _draw() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color(color, 0.18))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 32, Color(color, 0.8), 2.0)
	_draw_icon()


func _draw_icon() -> void:
	pass
