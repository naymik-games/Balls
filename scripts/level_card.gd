class_name LevelCard
extends Button
## One card in the level select grid: level number, difficulty rating (colored pips),
## and a lock icon or a check mark. Everything is drawn in code, so there are no
## icon assets to import.

const CARD_SIZE := Vector2(112.0, 128.0)
const ACCENT := Color(0.459, 0.732, 0.487)

const RATING_COLORS := {
	"easy": Color(0.45, 0.78, 0.50),
	"medium": Color(0.95, 0.80, 0.35),
	"hard": Color(0.95, 0.55, 0.30),
	"very hard": Color(0.90, 0.30, 0.35),
	"unfair": Color(0.70, 0.40, 0.90),
	"?": Color(0.55, 0.58, 0.65),
}
const RATING_PIPS := {"easy": 1, "medium": 2, "hard": 3, "very hard": 4, "unfair": 5}

var number := 0
var rating := "?"
var unlocked := false
var completed := false
var best := 0
var is_current := false


func setup(n: int, rating_name: String, is_unlocked: bool, is_completed: bool,
		best_shots: int, current: bool) -> void:
	number = n
	rating = rating_name
	unlocked = is_unlocked
	completed = is_completed
	best = best_shots
	is_current = current
	custom_minimum_size = CARD_SIZE
	focus_mode = Control.FOCUS_NONE
	text = ""
	var base := Color(0.15, 0.17, 0.25) if unlocked else Color(0.11, 0.12, 0.17)
	var border := ACCENT if is_current else Color(0, 0, 0, 0)
	var border_w := 3 if is_current else 0
	add_theme_stylebox_override("normal", _box(base, border, border_w))
	add_theme_stylebox_override("hover", _box(base.lightened(0.08), border, border_w))
	add_theme_stylebox_override("pressed", _box(base.lightened(0.15), border, border_w))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	queue_redraw()


func shake() -> void:
	pivot_offset = size * 0.5
	var t := create_tween()
	t.tween_property(self, "rotation", 0.06, 0.05)
	t.tween_property(self, "rotation", -0.06, 0.08)
	t.tween_property(self, "rotation", 0.0, 0.05)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var text_color := Color.WHITE if unlocked else Color(1, 1, 1, 0.35)

	draw_string(font, Vector2(0.0, size.y * 0.5 + 12.0), str(number),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, text_color)
	if completed and best > 0:
		draw_string(font, Vector2(0.0, size.y * 0.5 + 34.0), "best %d" % best,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(1, 1, 1, 0.55))

	# difficulty: 5 pips, filled up to the rating
	var pips: int = RATING_PIPS.get(rating, 0)
	var fill: Color = RATING_COLORS.get(rating, RATING_COLORS["?"])
	var fade := 1.0 if unlocked else 0.45
	var gap := 14.0
	var x0 := size.x * 0.5 - gap * 2.0
	for i in 5:
		var c := fill if i < pips else Color(1, 1, 1, 0.12)
		c.a *= fade
		draw_circle(Vector2(x0 + gap * float(i), size.y - 18.0), 4.5, c)

	# top-right: lock when locked, check mark when completed
	var x := size.x - 26.0
	var y := 10.0
	if not unlocked:
		var lock := Color(1, 1, 1, 0.5)
		draw_arc(Vector2(x + 7.0, y + 7.0), 5.0, PI, TAU, 12, lock, 2.0)
		draw_rect(Rect2(x, y + 7.0, 14.0, 10.0), lock)
	elif completed:
		draw_polyline(PackedVector2Array([
			Vector2(x, y + 8.0), Vector2(x + 5.0, y + 13.0), Vector2(x + 14.0, y + 3.0),
		]), ACCENT, 3.0)


static func _box(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(border_w)
	sb.border_color = border
	return sb
