class_name Ball
extends CharacterBody2D
## A single ball. Moves at a constant speed and reflects off anything it hits.
## Anything it hits that has a hit() method gets that method called.

signal landed(ball: Ball)

const RADIUS := 8.0
const MIN_VERTICAL := 0.15  # stops near-horizontal "forever" bounces

var speed := 700.0
var floor_y := 890.0
var active := false


func _ready() -> void:
	collision_layer = 2  # balls
	collision_mask = 1   # walls + blocks (balls ignore each other)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("balls")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color.WHITE)


func launch(direction: Vector2) -> void:
	velocity = direction.normalized() * speed
	active = true


func _physics_process(delta: float) -> void:
	if not active:
		return

	var collision := move_and_collide(velocity * delta)
	if collision:
		var collider := collision.get_collider()
		var remainder := collision.get_remainder()
		velocity = velocity.bounce(collision.get_normal()).normalized() * speed
		_prevent_flat_bounce()
		# spend the rest of this frame's movement in the new direction
		move_and_collide(velocity.normalized() * remainder.length())
		if collider and collider.has_method("hit"):
			collider.hit()

	if velocity.y > 0.0 and global_position.y >= floor_y - RADIUS:
		active = false
		global_position.y = floor_y - RADIUS
		landed.emit(self)


func _prevent_flat_bounce() -> void:
	var d := velocity.normalized()
	if absf(d.y) < MIN_VERTICAL:
		var sy := signf(d.y) if d.y != 0.0 else -1.0
		d.y = MIN_VERTICAL * sy
		d.x = signf(d.x) * sqrt(1.0 - d.y * d.y)
		velocity = d * speed
