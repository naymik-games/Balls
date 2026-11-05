class_name Splitter
extends Powerup
## The first time each ball crosses it, spawns one temporary extra ball.
## Spawned balls arrive with has_split = true, so they never split.


func _init() -> void:
	color = Color(0.5, 1.0, 0.5)
	single_use = false  # every ball gets its own split


func apply(ball: Ball, game) -> void:
	if ball.has_split:
		return
	ball.has_split = true
	game.spawn_extra_ball(position, game.random_up_dir())


func _draw_icon() -> void:
	# a stem that forks into two balls
	draw_line(Vector2(0, 12), Vector2.ZERO, color, 3.0)
	draw_line(Vector2.ZERO, Vector2(-10, -11), color, 3.0)
	draw_line(Vector2.ZERO, Vector2(10, -11), color, 3.0)
	draw_circle(Vector2(-10, -11), 3.5, color)
	draw_circle(Vector2(10, -11), 3.5, color)
