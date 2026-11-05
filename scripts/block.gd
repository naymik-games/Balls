class_name Block
extends StaticBody2D

signal destroyed(block: Block)
var start_hp: int
var hp := 1
var row := 0
var col := 0
var cell_size := 54.0
var dying := false

var visual: Node2D
var _tween: Tween


func setup(p_hp: int, p_cell_size: float) -> void:
	hp = p_hp
	start_hp = p_hp
	cell_size = p_cell_size
	collision_layer = 1
	collision_mask = 0
	add_to_group("blocks")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(cell_size - 4.0, cell_size - 4.0)
	shape.shape = rect
	add_child(shape)

	visual = Node2D.new()
	visual.draw.connect(_draw_visual)
	add_child(visual)


func hit(damage: int = 1) -> void:
	if dying:
		return
	hp -= damage
	if hp <= 0:
		_destroy()
	else:
		visual.queue_redraw()
		_play_hit()


func _play_hit() -> void:
	if _tween:
		_tween.kill()
	visual.scale = Vector2(0.75, 0.75)
	_tween = create_tween()
	_tween.tween_property(visual, "scale", Vector2.ONE, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _destroy() -> void:
	dying = true
	set_deferred("collision_layer", 0)  # balls pass through while it animates out
	destroyed.emit(self)
	_spawn_burst()
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(visual, "scale", Vector2(1.3, 1.3), 0.15)
	_tween.tween_property(visual, "modulate:a", 0.0, 0.15)
	_tween.chain().tween_callback(queue_free)


func _spawn_burst() -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = 16
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0               # full circle, so particles go every direction
	p.gravity = Vector2.ZERO       # no falling
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 280.0
	p.damping_min = 120.0          # particles decelerate as they travel outward
	p.damping_max = 200.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 8.0
	p.color = _color_for_hp(start_hp)

	var shrink := Curve.new()      # particles shrink to nothing over their life
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink

	# add to Main, not Board: Main loops over Board's children expecting a .row
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _draw_visual() -> void:
	var half := (cell_size - 4.0) / 2.0
	visual.draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), _color_for_hp(hp))
	visual.draw_string(ThemeDB.fallback_font, Vector2(-half, 22 * 0.35), str(hp),
			HORIZONTAL_ALIGNMENT_CENTER, half * 2.0, 22, Color.WHITE)


func _color_for_hp(value: int) -> Color:
	return Color.from_hsv(fposmod(0.95 - value * 0.03, 1.0), 0.65, 0.9)
