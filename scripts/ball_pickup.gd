class_name BallPickup
extends Area2D
## Powerup: touching it with a ball adds one ball to the reserve.

signal collected(pickup: BallPickup)

const RADIUS := 14.0

var row := 0
var col := 0
var _taken := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # detect balls
	add_to_group("pickups")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("balls"):
		return
	_taken = true
	collected.emit(self)
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 7.0, Color.WHITE)
	draw_arc(Vector2.ZERO, RADIUS - 2.0, 0.0, TAU, 32, Color(0.4, 0.9, 1.0), 3.0)
