class_name BeamPowerup
extends Powerup
## Damages every block in this powerup's row (or column) by 1 and plays a beam effect.

const BEAM_THICKNESS := 14.0
const BEAM_COLOR := Color(0.4, 0.9, 1.0)

var horizontal := true


func _init() -> void:
	color = BEAM_COLOR
	


func apply(_ball: Ball, game) -> void:
	var targets: Array = game.blocks_in_row(row) if horizontal else game.blocks_in_col(col)
	for block in targets:
		block.hit()
	_play_fx(game)


func _play_fx(game) -> void:
	var area: Rect2 = game.play_rect()
	var rect: Rect2
	if horizontal:
		rect = Rect2(area.position.x, position.y - BEAM_THICKNESS / 2.0, area.size.x, BEAM_THICKNESS)
	else:
		rect = Rect2(position.x - BEAM_THICKNESS / 2.0, area.position.y, BEAM_THICKNESS, area.size.y)

	var beam := ColorRect.new()
	beam.color = Color(BEAM_COLOR, 0.9)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam.position = rect.position
	beam.size = rect.size
	beam.pivot_offset = position - rect.position  # grow outward from the powerup
	# tiny instead of 0 to avoid a zero-scale transform
	beam.scale = Vector2(0.01, 1.0) if horizontal else Vector2(1.0, 0.01)
	game.add_child(beam)  # on the game, not on this node: we're about to be freed

	var tween := beam.create_tween()
	tween.tween_property(beam, "scale", Vector2.ONE, 0.12) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(beam, "modulate:a", 0.0, 0.2)
	tween.tween_callback(beam.queue_free)


func _draw_icon() -> void:
	# double-headed arrow along the beam's axis
	var axis := Vector2.RIGHT if horizontal else Vector2.DOWN
	var perp := axis.orthogonal()
	var half := 14.0
	draw_line(-axis * half, axis * half, color, 3.0)
	for s in [-1.0, 1.0]:
		var tip: Vector2 = axis * half * s
		draw_line(tip, tip - axis * 7.0 * s + perp * 6.0, color, 3.0)
		draw_line(tip, tip - axis * 7.0 * s - perp * 6.0, color, 3.0)
