class_name Upper
extends Powerup
## Any ball that crosses it is relaunched at a random upward angle. Unlimited uses.


func _init() -> void:
	color = Color(1.0, 0.6, 0.3)
	single_use = false


func apply(ball: Ball, game) -> void:
	ball.launch(game.random_up_dir())


func _draw_icon() -> void:
	# up arrow
	draw_line(Vector2(0, 13), Vector2(0, -13), color, 3.0)
	draw_line(Vector2(0, -13), Vector2(-8, -5), color, 3.0)
	draw_line(Vector2(0, -13), Vector2(8, -5), color, 3.0)
