class_name LevelBaker
extends RefCounted
## Generates levels with LevelGenerator and saves each one as res://levels/level_NNN.tres.
##
## Runs inside the game (see the bake_levels export in main.gd), not as an
## EditorScript: non-@tool scripts only get placeholder instances in the editor, so
## DamageModel / LevelData would come out empty there.
##
## Baked files are the source of truth. By default an existing file is kept, so a
## level you hand-edited survives a re-bake. Pass overwrite = true to regenerate
## (for example after changing LevelGenerator and bumping GENERATOR_VERSION).
##
## Each file carries metadata: generator_version, level_number, target_win (from the
## generator) plus rating, win_probability, pressure, par_shots and model_source
## (from the analysis at bake time). The level select scene can read the rating
## straight from the file.

const OUT_DIR := "res://levels"


static func path_for(level_number: int) -> String:
	return "%s/level_%03d.tres" % [OUT_DIR, level_number]


static func bake(from_level: int, to_level: int, model: DamageModel, last_row: int,
		spawn_row: int, overwrite := false) -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("Baking levels %d-%d to %s  (model: %s, overwrite: %s)" % [
			from_level, to_level, OUT_DIR, model.source, overwrite])
	print("lvl  target   win  rating      balls blocks    hp waves pressure  par  status")

	var tally := {}
	var baked := 0
	var kept := 0
	var failed := 0
	var warned := 0

	for n in range(from_level, to_level + 1):
		var path := path_for(n)

		if not overwrite and FileAccess.file_exists(path):
			var old := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
			var old_rating := str(old.get_meta("rating", "?")) if old != null else "?"
			tally[old_rating] = int(tally.get(old_rating, 0)) + 1
			kept += 1
			print("%3d  (file exists, kept)  %s" % [n, old_rating])
			continue

		var g := LevelGenerator.generate_full(n, model, last_row, spawn_row)
		var level: LevelData = g["level"]
		var r: Dictionary = g["report"]
		level.set_meta("rating", r["rating"])
		level.set_meta("win_probability", r["win_probability"])
		level.set_meta("pressure", r["pressure"])
		level.set_meta("par_shots", r["par_shots"])
		level.set_meta("model_source", r["model_source"])

		var status := "ok"
		var err := ResourceSaver.save(level, path)
		if err != OK:
			status = "SAVE FAILED (%s)" % error_string(err)
			failed += 1
		else:
			var problem := _verify(level, path)
			if problem != "":
				status = "VERIFY FAILED: %s" % problem
				failed += 1
			else:
				baked += 1
				tally[r["rating"]] = int(tally.get(r["rating"], 0)) + 1
		if not r["warnings"].is_empty():
			warned += 1
			status += "  WARN"

		print("%3d   %4.2f  %4.2f  %-10s  %4d  %5d  %4d  %4d  %7.2f  %3d  %s" % [
				n, g["target"], r["win_probability"], r["rating"], r["balls"],
				r["block_count"], r["total_hp"], r["wave_count"], r["pressure"],
				r["par_shots"], status])
		for w in r["warnings"]:
			print("       warning: %s" % w)

	print("Done: %d baked, %d kept, %d failed, %d with warnings" % [baked, kept, failed, warned])
	print("Ratings: %s" % str(tally))
	if failed > 0:
		push_error("LevelBaker: %d level(s) failed to save or verify. If blocks came back empty, check that BlockSpec's fields are @export." % failed)


## Reloads the saved file (bypassing the cache) and compares it with what we meant to
## save. Catches fields that don't serialize (e.g. a BlockSpec var missing @export).
## Returns "" when everything matches.
static func _verify(level: LevelData, path: String) -> String:
	var back := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelData
	if back == null:
		return "could not reload the file"
	if back.balls != level.balls:
		return "balls %d != %d" % [back.balls, level.balls]
	if back.start_blocks.size() != level.start_blocks.size():
		return "start block count %d != %d" % [back.start_blocks.size(), level.start_blocks.size()]
	if back.waves.size() != level.waves.size():
		return "wave count %d != %d" % [back.waves.size(), level.waves.size()]
	var a := _fingerprint(level)
	var b := _fingerprint(back)
	if a != b:
		return "block data differs (hp/col/row/circle: %s vs %s)" % [str(a), str(b)]
	if back.get_meta("rating", "") != level.get_meta("rating", ""):
		return "metadata was not saved"
	return ""


## [total hp, sum of col+row positions, circle count, wave after_shot sum] over the
## whole level, cheap enough to compare before and after saving.
static func _fingerprint(level: LevelData) -> Array:
	var hp := 0
	var pos := 0
	var circles := 0
	var shots := 0
	for s in level.start_blocks:
		hp += s.hp
		pos += s.col * 31 + s.row
		circles += 1 if s.is_circle else 0
	for w in level.waves:
		shots += w.after_shot
		for s in w.cells:
			hp += s.hp
			pos += s.col * 31 + s.row
			circles += 1 if s.is_circle else 0
	return [hp, pos, circles, shots]
