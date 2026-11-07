class_name LevelAnalyzer
extends RefCounted
## Estimates how hard a LevelData is, without playing it.
##
## Every block has a release shot (first shot it exists for) and a deadline shot
## (last shot that can kill it before it reaches the bottom):
##   starting block at row r:         release 1,     deadline LAST_ROW - r
##   block in a wave arriving after   release w + 1, deadline w + LAST_ROW - SPAWN_ROW
##   shot w:
## Damage delivered before a block's release is wasted on it, so feasibility is a
## scheduling question: in every window of shots [a, b], the HP that must be dealt
## inside the window can't exceed what the balls can deal in it.
##
##   required_rate = the worst window's  HP / (balls * shots)
##                   = the per-ball damage the player must average there.
##   pressure      = required_rate / typical per-ball damage (1.0 = break-even).
##
## win_probability comes from a Monte Carlo run: each shot draws a per-ball damage
## rate from the DamageModel, damage goes to the most urgent released block first
## (earliest deadline), and the run fails if any block outlives its deadline.
##
## This assumes good targeting and ignores powerups, abilities and ball pickups, so
## treat it as an optimistic estimate. Calibrate the rating bands with bots later.

## Lowest block should leave at least this many shots before it reaches the bottom.
const MIN_FIRST_DEADLINE := 4
## A single block can only absorb roughly this many hits per ball per shot.
const MAX_HITS_PER_BALL_PER_BLOCK := 1.0
const EPS := 1e-6


static func analyze(level: LevelData, model: DamageModel, last_row: int, spawn_row: int,
		trials := 1000, rng_seed := 1234) -> Dictionary:
	var warnings := PackedStringArray()
	var balls := level.balls
	var result := {
		"balls": balls,
		"block_count": 0,
		"total_hp": 0,
		"wave_count": level.waves.size(),
		"first_deadline": 0,
		"required_rate": 0.0,
		"tight_window": Vector2i.ZERO,
		"pressure": 0.0,
		"pressure_low": 0.0,
		"par_shots": -1,
		"win_probability": 0.0,
		"shots_median": -1,
		"shots_p90": -1,
		"rating": "invalid",
		"mean_rate": model.mean_rate,
		"low_rate": model.percentile(0.25),
		"model_source": model.source,
		"warnings": warnings,
	}

	if balls < 1:
		warnings.append("level has no balls")
		result["warnings"] = warnings
		return result

	# --- collect (release, deadline) -> HP --------------------------------------
	var demand := {}
	var block_count := 0
	var total_hp := 0
	var first_deadline := 1000000
	var overloaded := 0
	var worst_hp := 0

	for spec in level.start_blocks:
		var dl := last_row - (spawn_row + spec.row)
		first_deadline = mini(first_deadline, dl)
		_add(demand, Vector2i(1, dl), spec.hp)
		block_count += 1
		total_hp += spec.hp
		if float(spec.hp) > float(balls) * MAX_HITS_PER_BALL_PER_BLOCK * float(maxi(dl, 1)):
			overloaded += 1
			worst_hp = maxi(worst_hp, spec.hp)

	var waves := level.waves.duplicate()
	waves.sort_custom(func(a, b): return a.after_shot < b.after_shot)
	var window := last_row - spawn_row
	var prev := 0
	var delayed := 0
	for w in waves:
		# LevelMode spawns at most one wave per round
		var arrives := maxi(w.after_shot, prev + 1)
		prev = arrives
		if arrives > w.after_shot:
			delayed += 1
		for cell in w.cells:
			_add(demand, Vector2i(arrives + 1, arrives + window), cell.hp)
			block_count += 1
			total_hp += cell.hp
			if float(cell.hp) > float(balls) * MAX_HITS_PER_BALL_PER_BLOCK * float(window):
				overloaded += 1
				worst_hp = maxi(worst_hp, cell.hp)

	result["block_count"] = block_count
	result["total_hp"] = total_hp

	if demand.is_empty():
		warnings.append("level has no blocks")
		result["warnings"] = warnings
		return result

	if first_deadline == 1000000:
		first_deadline = window  # waves only
	result["first_deadline"] = first_deadline
	if first_deadline < 1:
		warnings.append("a block starts on or below the last row, so the level is lost immediately")
		result["rating"] = "unwinnable"
		result["warnings"] = warnings
		return result
	if first_deadline < MIN_FIRST_DEADLINE:
		warnings.append("the lowest block leaves only %d shots before it reaches the bottom" % first_deadline)
	if overloaded > 0:
		warnings.append("%d block(s) have more HP than %d balls can plausibly remove in time (worst: %d HP)"
				% [overloaded, balls, worst_hp])
	if delayed > 0:
		warnings.append("%d wave(s) share a shot with another wave and arrive one shot late each" % delayed)

	# --- flatten into arrays sorted by deadline ---------------------------------
	var keys := demand.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var n := keys.size()
	var rel := PackedInt32Array()
	var dl_arr := PackedInt32Array()
	var hp := PackedFloat64Array()
	rel.resize(n)
	dl_arr.resize(n)
	hp.resize(n)
	for i in n:
		rel[i] = keys[i].x
		dl_arr[i] = keys[i].y
		hp[i] = float(demand[keys[i]])

	# --- worst window: required damage per ball per shot ------------------------
	var rels := PackedInt32Array()
	var dls := PackedInt32Array()
	for i in n:
		if not rels.has(rel[i]):
			rels.append(rel[i])
		if not dls.has(dl_arr[i]):
			dls.append(dl_arr[i])
	var required := 0.0
	var tight := Vector2i.ZERO
	for a in rels:
		for b in dls:
			if b < a:
				continue
			var need := 0.0
			for i in n:
				if rel[i] >= a and dl_arr[i] <= b:
					need += hp[i]
			var rate := need / (float(b - a + 1) * float(balls))
			if rate > required:
				required = rate
				tight = Vector2i(a, b)
	result["required_rate"] = required
	result["tight_window"] = tight
	result["pressure"] = required / model.mean_rate
	result["pressure_low"] = required / maxf(result["low_rate"], EPS)

	# --- par: clear time if every shot does exactly the average -----------------
	var par := _run(dl_arr, rel, hp, balls, model, null)
	result["par_shots"] = par.y if par.x == 1 else -1

	# --- Monte Carlo ------------------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var wins := 0
	var finishes := PackedInt32Array()
	for _t in trials:
		var r := _run(dl_arr, rel, hp, balls, model, rng)
		if r.x == 1:
			wins += 1
			finishes.append(r.y)
	var win_probability := float(wins) / float(maxi(trials, 1))
	result["win_probability"] = win_probability
	if not finishes.is_empty():
		finishes.sort()
		result["shots_median"] = finishes[int(finishes.size() * 0.5)]
		result["shots_p90"] = finishes[int(0.9 * float(finishes.size() - 1))]
	result["rating"] = rating_for(win_probability)
	result["warnings"] = warnings
	return result


## Provisional bands, from the model only. Re-tune after bot playtesting.
static func rating_for(win_probability: float) -> String:
	if win_probability >= 0.97:
		return "easy"
	if win_probability >= 0.80:
		return "medium"
	if win_probability >= 0.50:
		return "hard"
	if win_probability >= 0.15:
		return "very hard"
	return "unfair"


## One simulated level. Blocks are bucketed by (release, deadline) and sorted by
## deadline. Returns Vector2i(1 if cleared else 0, shot the run ended on).
## rng == null uses the average rate every shot (deterministic).
static func _run(dl: PackedInt32Array, rel: PackedInt32Array, hp: PackedFloat64Array,
		balls: int, model: DamageModel, rng: RandomNumberGenerator) -> Vector2i:
	var rem := hp.duplicate()
	var horizon := dl[dl.size() - 1]
	for t in range(1, horizon + 1):
		var rate := model.mean_rate if rng == null else model.sample(rng)
		var cap := float(balls) * rate
		for i in rem.size():
			if cap <= 0.0:
				break
			if rel[i] <= t and rem[i] > EPS:
				var used := minf(rem[i], cap)
				rem[i] -= used
				cap -= used
		var all_done := true
		for i in rem.size():
			if rem[i] > EPS:
				all_done = false
				if dl[i] <= t:
					return Vector2i(0, t)
		if all_done:
			return Vector2i(1, t)
	return Vector2i(0, horizon)


static func _add(demand: Dictionary, key: Vector2i, hp: int) -> void:
	demand[key] = int(demand.get(key, 0)) + hp


static func report_text(level: LevelData, r: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Level \"%s\": %d balls, %d blocks, %d HP, %d waves" % [
			level.level_name, r["balls"], r["block_count"], r["total_hp"], r["wave_count"]])
	if r["rating"] == "invalid" or r["rating"] == "unwinnable":
		lines.append("Rating: %s" % r["rating"])
	else:
		var tight: Vector2i = r["tight_window"]
		lines.append("Tightest window: shots %d-%d needs %.2f damage per ball per shot (average player %.2f, weak %.2f)" % [
				tight.x, tight.y, r["required_rate"], r["mean_rate"], r["low_rate"]])
		lines.append("Pressure: %.2f  (%.2f for a weak player; 1.0 = break-even)" % [
				r["pressure"], r["pressure_low"]])
		lines.append("Win probability: %d%%  ->  %s" % [roundi(r["win_probability"] * 100.0), r["rating"]])
		if r["shots_median"] >= 0:
			lines.append("Shots to clear: median %d, p90 %d, average-damage par %d" % [
					r["shots_median"], r["shots_p90"], r["par_shots"]])
		lines.append("Lowest block has %d shots; model: %s" % [r["first_deadline"], r["model_source"]])
	for w in r["warnings"]:
		lines.append("WARNING: %s" % w)
	return "\n".join(lines)
