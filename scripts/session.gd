extends Node
## Autoload (Project Settings > Globals > Autoload, name it "Session").
## Do not give this script a class_name: it would clash with the autoload name.
##
## Owns three things:
##   - the hand-off between the level select scene and main.gd (current_level)
##   - progress: highest unlocked level and best shots per level, saved to user://
##   - lookups into the baked levels in res://levels/ (see LevelBaker)

const SAVE_PATH := "user://progress.cfg"
## Adjust both to wherever your scenes live.
const SELECT_SCENE := "res://scenes/level_select.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

## Set by start_level(); main.gd plays this instead of its own `level` export.
var current_level: LevelData = null
## 0 when main.gd is run directly (no progress is recorded then).
var current_number := 0
## Last level started, so the select scene can scroll back to it.
var last_played := 0
var highest_unlocked := 1
## level number -> fewest shots it was cleared in.
var best_shots := {}
## True while Classic mode was started from the menu (main.gd shows a Menu button).
var classic_active := false
## Debug: every level shows as unlocked. Toggled from the menu; remove when done.
var debug_unlock_all := false

var _count := -1
var _levels := {}
var classic_best: int = 999

func _ready() -> void:
	load_progress()


# ---------------------------------------------------------------- levels

## How many consecutive baked levels exist, counting from level 1.
func level_count() -> int:
	if _count < 0:
		_count = 0
		while ResourceLoader.exists(LevelBaker.path_for(_count + 1)):
			_count += 1
	return _count


## Null if the file is missing. Levels are never modified while playing, so they are
## safe to cache.
func get_level(n: int) -> LevelData:
	if not _levels.has(n):
		_levels[n] = ResourceLoader.load(LevelBaker.path_for(n)) as LevelData
	return _levels[n]


## "easy", "medium", "hard", "very hard", "unfair" or "?" (read from the baked metadata).
func rating_of(n: int) -> String:
	var data := get_level(n)
	return str(data.get_meta("rating", "?")) if data != null else "?"


func par_of(n: int) -> int:
	var data := get_level(n)
	return int(data.get_meta("par_shots", -1)) if data != null else -1


# ---------------------------------------------------------------- progress

func is_unlocked(n: int) -> bool:
	return debug_unlock_all or n <= highest_unlocked


func is_completed(n: int) -> bool:
	return best_shots.has(n)


func completed_count() -> int:
	return best_shots.size()


## The level the player should play next (the frontier, capped at the last level).
func frontier() -> int:
	return clampi(highest_unlocked, 1, maxi(level_count(), 1))


## Call once when the current level is won. Returns
## {"new_best": bool, "best": int, "unlocked_next": bool, "has_next": bool}.
func complete_level(shots: int) -> Dictionary:
	var n := current_number
	var previous: int = best_shots.get(n, 0)
	var new_best := previous == 0 or shots < previous
	if new_best:
		best_shots[n] = shots
	var unlocked_next := false
	if n >= highest_unlocked:
		highest_unlocked = n + 1
		unlocked_next = true
	save_progress()
	return {
		"new_best": new_best,
		"best": int(best_shots[n]),
		"unlocked_next": unlocked_next,
		"has_next": n + 1 <= level_count(),
	}
func complete_classic(shots: int):
	var pre_best = classic_best
	var new: bool = false
	if shots < classic_best:
		classic_best = shots
		new = true
		save_progress()
	return {
		"previous": pre_best,
		"new": new
	}
func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	highest_unlocked = maxi(int(cfg.get_value("progress", "highest_unlocked", 1)), 1)
	debug_unlock_all = bool(cfg.get_value("debug", "unlock_all", false))
	classic_best = cfg.get_value("classic", "classic_best",999)
	var saved: Dictionary = cfg.get_value("progress", "best_shots", {})
	best_shots = {}
	for k in saved:
		best_shots[int(k)] = int(saved[k])


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "highest_unlocked", highest_unlocked)
	cfg.set_value("progress", "best_shots", best_shots)
	cfg.set_value("debug", "unlock_all", debug_unlock_all)
	cfg.set_value("classic", "classic_best", classic_best)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("Session: could not save progress (%s)" % error_string(err))


## Debug helper: forget all progress.
func reset_progress() -> void:
	highest_unlocked = 1
	best_shots = {}
	last_played = 0
	save_progress()


func set_debug_unlock_all(on: bool) -> void:
	debug_unlock_all = on
	save_progress()


# ---------------------------------------------------------------- scene flow

func start_level(n: int) -> void:
	var data := get_level(n)
	if data == null:
		push_error("Session: no baked level %d at %s" % [n, LevelBaker.path_for(n)])
		return
	current_level = data
	current_number = n
	last_played = n
	classic_active = false
	get_tree().change_scene_to_file(GAME_SCENE)


## Classic mode: main.gd falls back to its own mode when there is no current level.
func start_classic() -> void:
	current_level = null
	current_number = 0
	classic_active = true
	get_tree().change_scene_to_file(GAME_SCENE)


func open_select() -> void:
	current_level = null
	current_number = 0
	classic_active = false
	get_tree().change_scene_to_file(SELECT_SCENE)


func open_menu() -> void:
	current_level = null
	current_number = 0
	classic_active = false
	get_tree().change_scene_to_file(MENU_SCENE)
