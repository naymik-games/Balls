class_name LevelGenerator
extends RefCounted
## Generates a LevelData for a level number. Fully deterministic: the same
## (GENERATOR_VERSION, level_number) always gives the same level, so levels can be
## generated on the fly, baked to .tres files, or both.
##
## Two steps per level:
##   1. SHAPE  - seeded random layout: pattern, rows, density, ball count, waves,
##               circles. Each block gets a relative weight instead of an HP.
##   2. TUNE   - blocks get hp = round(weight * k). A log-scale bisection on k runs
##               LevelAnalyzer until the win probability matches the target for
##               this level number (see target_win_for).
## If a shape can't be tuned onto the target (or the analyzer warns about it), the
## next shape is drawn from the same seeded stream. The closest result wins if none
## is clean.
##
## Bump GENERATOR_VERSION whenever you change anything that alters output, so old
## baked levels can be told apart from new ones.

const GENERATOR_VERSION := 1

## Keep in sync with main.gd.
const COLS := 10
const HALF_COLS := 5

const MAX_HP := 99
const MAX_ATTEMPTS := 12
const TUNE_STEPS := 10
const MIN_SCALE := 0.5
const MAX_SCALE := 40.0
const SEARCH_TRIALS := 300
const FINAL_TRIALS := 1000
## How far the achieved win probability may be from the target and still count.
const WIN_TOLERANCE := 0.06
const MIN_START_BLOCKS := 12

const WAVES_FROM_LEVEL := 4
const CIRCLES_FROM_LEVEL := 10
const MAX_AVG_HP := 30.0
const MAX_AVG_HP_PER_BALL := 2.2
const PATTERNS := ["scatter", "symmetric", "bands", "pyramid"]

## Difficulty within each cycle of 5 levels, 0 = easiest, 1 = hardest. The last level
## of a cycle is a breather.
const CYCLE_INTENSITY := [0.0, 0.25, 0.55, 1.0, 0.1]


## Win probability the generator aims for at this level number. A sawtooth: each
## cycle ramps up and then eases off, and both the ceiling and the floor of the
## cycles drift down slowly. Never goes below 0.35 (analyzer says "hard" to "very
## hard" there; it is optimistic, so real players will find it harder).
static func target_win_for(level_number: int) -> float:
	var idx := maxi(level_number - 1, 0)
	var cycle := floori(float(idx) / float(CYCLE_INTENSITY.size()))
	var intensity: float = CYCLE_INTENSITY[idx % CYCLE_INTENSITY.size()]
	var top := clampf(0.99 - 0.012 * float(cycle), 0.92, 0.99)
	var bottom := clampf(0.85 - 0.04 * float(cycle), 0.35, 0.85)
	return lerpf(top, bottom, intensity)


static func generate(level_number: int, model: DamageModel, last_row: int, spawn_row: int) -> LevelData:
	return generate_full(level_number, model, last_row, spawn_row)["level"]


## Returns {"level": LevelData, "report": analyzer result, "target": float, "attempts": int}.
static func generate_full(level_number: int, model: DamageModel, last_row: int, spawn_row: int) -> Dictionary:
	var target := target_win_for(level_number)
	var rng := RandomNumberGenerator.new()
	rng.seed = GENERATOR_VERSION * 1000003 + level_number * 7919
	
	var best := {}
	var best_score := INF
	var attempts := 0
	for _a in MAX_ATTEMPTS:
		attempts += 1
		var shape := _make_shape(level_number, rng)
		var tuned := _tune(shape, level_number, target, model, last_row, spawn_row)
		var clean: bool = tuned["report"]["warnings"].is_empty()
		var rep: Dictionary = tuned["report"]
		var avg_hp := float(rep["total_hp"]) / float(maxi(rep["block_count"], 1))
		var ok: bool = clean and avg_hp <= MAX_AVG_HP_PER_BALL * float(rep["balls"])
		var score: float = tuned["err"] + (0.0 if ok else 1.0)
		
		if score < best_score:
			best_score = score
			best = tuned
		if ok and tuned["err"] <= WIN_TOLERANCE:
			break

	var level: LevelData = best["level"]
	# Full-precision report for the level we're keeping.
	var report := LevelAnalyzer.analyze(level, model, last_row, spawn_row, FINAL_TRIALS)
	level.set_meta("generator_version", GENERATOR_VERSION)
	level.set_meta("level_number", level_number)
	level.set_meta("target_win", target)
	return {"level": level, "report": report, "target": target, "attempts": attempts}


## Prints one line per level so you can eyeball the difficulty curve.
static func print_report(from_level: int, to_level: int, model: DamageModel, last_row: int, spawn_row: int) -> void:
	print("lvl  target   win  rating      balls blocks    hp waves pressure  par  tries")
	for n in range(from_level, to_level + 1):
		var g := generate_full(n, model, last_row, spawn_row)
		var r: Dictionary = g["report"]
		print("%3d   %4.2f  %4.2f  %-10s  %4d  %5d  %4d  %4d  %7.2f  %3d  %4d%s" % [
				n, g["target"], r["win_probability"], r["rating"], r["balls"],
				r["block_count"], r["total_hp"], r["wave_count"], r["pressure"],
				r["par_shots"], g["attempts"],
				"  WARN" if not r["warnings"].is_empty() else ""])


# ---------------------------------------------------------------------------
# Tuning
# ---------------------------------------------------------------------------

## Bisects the HP scale k (on a log scale) so the win probability lands on `target`.
## Returns {"level", "report", "err"} for the closest k seen. On ties it prefers the
## harder (higher total HP) level, because win probability plateaus at 100%.
static func _tune(shape: Dictionary, n: int, target: float, model: DamageModel,
		last_row: int, spawn_row: int) -> Dictionary:
	var lo := MIN_SCALE
	var hi := MAX_SCALE
	var best_level: LevelData = null
	var best_report := {}
	var best_err := INF
	for _i in TUNE_STEPS:
		var k := sqrt(lo * hi)
		var level := _build(shape, k, n)
		var r := LevelAnalyzer.analyze(level, model, last_row, spawn_row, SEARCH_TRIALS)
		var win: float = r["win_probability"]
		var err := absf(win - target)
		var better := err < best_err - 0.0001
		if not better and absf(err - best_err) <= 0.0001 and best_level != null:
			better = int(r["total_hp"]) > int(best_report["total_hp"])
		if better:
			best_err = err
			best_level = level
			best_report = r
		if win > target:
			lo = k  # too easy: more HP
		else:
			hi = k  # too hard: less HP
	return {"level": best_level, "report": best_report, "err": best_err}


# ---------------------------------------------------------------------------
# Shape
# ---------------------------------------------------------------------------

## A shape is a layout with relative weights and no HP yet:
##   balls, cells: [{col,row,w,circle}], waves: [{after_shot, cells: [{col,w,circle}]}]
static func _make_shape(n: int, rng: RandomNumberGenerator) -> Dictionary:
	var balls := clampi(10 + floori(float(n) * 0.3) + rng.randi_range(0, 4), 10, 40)
	var rows := clampi(3 + floori(float(n) / 12.0) + rng.randi_range(0, 2), 3, 7)
	var density := clampf(0.55 + 0.004 * float(n) + rng.randf_range(-0.1, 0.1), 0.45, 0.85)
	var pattern: String = PATTERNS[rng.randi_range(0, PATTERNS.size() - 1)]
	# Positive slope = lower rows are heavier, which is harder (shorter deadlines).
	var slope := rng.randf_range(-0.15, 0.25)
	var circle_chance := 0.0
	if n >= CIRCLES_FROM_LEVEL:
		circle_chance = clampf(0.08 + 0.003 * float(n), 0.08, 0.3)
	var wave_count := 0
	if n >= WAVES_FROM_LEVEL:
		var max_waves := clampi(1 + floori(float(n - WAVES_FROM_LEVEL) / 8.0), 1, 4)
		wave_count = rng.randi_range(maxi(1, max_waves - 1), max_waves)

	var positions := _pattern_cells(pattern, rows, density, rng)
	_pad_cells(positions, rows, rng)

	var span := maxf(float(rows - 1), 1.0)
	var cells: Array = []
	for v: Vector2i in positions:
		cells.append({
			"col": v.x,
			"row": v.y,
			"w": rng.randf_range(0.7, 1.3) * (1.0 + slope * float(v.y) / span),
			"circle": rng.randf() < circle_chance,
		})

	var waves: Array = []
	var shot := rng.randi_range(2, 4)
	for i in wave_count:
		var wave_cells: Array = []
		for col in _pick_cols(rng, rng.randi_range(4, 8)):
			wave_cells.append({
				"col": col,
				"w": rng.randf_range(0.8, 1.2) * (1.0 + 0.2 * float(i)),
				"circle": rng.randf() < circle_chance,
			})
		waves.append({"after_shot": shot, "cells": wave_cells})
		# Strictly increasing: the analyzer warns when two waves share a shot.
		shot += rng.randi_range(2, 4)

	return {"balls": balls, "cells": cells, "waves": waves}


static func _pattern_cells(pattern: String, rows: int, density: float, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match pattern:
		"symmetric":
			for r in rows:
				for c in HALF_COLS:
					if rng.randf() < density:
						out.append(Vector2i(c, r))
						out.append(Vector2i(COLS - 1 - c, r))
		"bands":
			for r in rows:
				var d := clampf(density + (0.25 if r % 2 == 0 else -0.3), 0.15, 0.95)
				for c in COLS:
					if rng.randf() < d:
						out.append(Vector2i(c, r))
		"pyramid":
			# Narrow at the top, widening by one cell on each side per row.
			for r in rows:
				var width := mini(COLS, 2 + 2 * r)
				var start := floori(float(COLS - width) * 0.5)
				for c in range(start, start + width):
					if rng.randf() < clampf(density + 0.2, 0.0, 0.95):
						out.append(Vector2i(c, r))
		_:  # scatter
			for r in rows:
				for c in COLS:
					if rng.randf() < density:
						out.append(Vector2i(c, r))
	return out


## Makes sure there are enough blocks that tuning has something to work with.
static func _pad_cells(cells: Array[Vector2i], rows: int, rng: RandomNumberGenerator) -> void:
	var guard := 0
	while cells.size() < MIN_START_BLOCKS and guard < 500:
		guard += 1
		var v := Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, rows - 1))
		if not cells.has(v):
			cells.append(v)


## `count` distinct columns. Uses the seeded rng (Array.shuffle() would use the
## global RNG and break determinism).
static func _pick_cols(rng: RandomNumberGenerator, count: int) -> Array[int]:
	var cols: Array[int] = []
	for c in COLS:
		cols.append(c)
	for i in range(cols.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cols[i]
		cols[i] = cols[j]
		cols[j] = tmp
	return cols.slice(0, clampi(count, 0, COLS))


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

static func _build(shape: Dictionary, k: float, n: int) -> LevelData:
	var d := LevelData.new()
	d.level_name = "Level %d" % n
	d.balls = shape["balls"]
	for c: Dictionary in shape["cells"]:
		d.start_blocks.append(_spec(c["col"], c["row"], _hp(c["w"], k), c["circle"]))
	for w: Dictionary in shape["waves"]:
		var ws := WaveSpec.new()
		ws.after_shot = w["after_shot"]
		for c: Dictionary in w["cells"]:
			ws.cells.append(_spec(c["col"], 0, _hp(c["w"], k), c["circle"]))
		d.waves.append(ws)
	# Abilities stay off (opt-in) and the analyzer ignores powerups, so board
	# powerups only make a generated level slightly easier than reported.
	return d


static func _hp(weight: float, k: float) -> int:
	return clampi(roundi(weight * k), 1, MAX_HP)


static func _spec(col: int, row: int, hp: int, circle: bool) -> BlockSpec:
	var s := BlockSpec.make(col, row, hp)
	s.is_circle = circle
	return s
