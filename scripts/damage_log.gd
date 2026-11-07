class_name DamageLog
extends RefCounted
## Measures how much block HP each shot removes, to calibrate `e` (average damage
## per ball per shot) for the level analyzer.
##
## damage = HP removed from the blocks that were on the board when the shot was
## fired. It's measured as an HP difference, so it needs no changes to Ball or
## Block, and it correctly ignores overkill (three balls hitting a 1-HP block
## count as 1 damage).
##
## Shots where a powerup fired, Bounce was armed, or Boost balls were added are
## tagged `assisted` and kept out of the running average.

const PATH := "user://damage_log.csv"
const HEADER := "game,shot,balls,blocks,block_rows,fill,hp_before,damage,per_ball,assisted"

var _active := false
var _before: Array = []  # [[block, hp], ...] captured when the shot is fired
var _game := 0
var _shot := 0
var _balls := 0
var _blocks := 0
var _span := 0
var _fill := 0.0
var _hp_before := 0
var _assisted := false

var _clean_damage := 0
var _clean_balls := 0
var _clean_shots := 0
var _announced := false


## Call when a shot is fired, before any ball is launched.
func begin(game, balls: int, assisted: bool) -> void:
	_before.clear()
	_hp_before = 0
	var min_row := 9999
	var max_row := -1
	for b in game.live_blocks():
		_before.append([b, b.hp])
		_hp_before += b.hp
		min_row = mini(min_row, b.row)
		max_row = maxi(max_row, b.row)
	_game = game.game_id
	_shot = game.round_number
	_balls = balls
	_blocks = _before.size()
	_span = 0 if _blocks == 0 else max_row - min_row + 1
	_fill = 0.0 if _span == 0 else float(_blocks) / float(game.COLS * _span)
	_assisted = assisted
	_active = true


## A powerup triggered during this shot.
func note_assist() -> void:
	_assisted = true


## Call when the last ball has landed, before blocks descend.
func end(_game_node) -> void:
	if not _active:
		return
	_active = false
	var remaining := 0
	for pair in _before:
		var b = pair[0]
		if is_instance_valid(b) and not b.dying:
			remaining += maxi(b.hp, 0)
	var damage := _hp_before - remaining
	var per_ball := float(damage) / float(maxi(_balls, 1))

	if not _assisted:
		_clean_damage += damage
		_clean_balls += _balls
		_clean_shots += 1

	_append_csv("%d,%d,%d,%d,%d,%.2f,%d,%d,%.2f,%d" % [
			_game, _shot, _balls, _blocks, _span, _fill,
			_hp_before, damage, per_ball, 1 if _assisted else 0])
	print("[dmg] shot %d: %d balls, %d of %d HP removed (%.2f/ball)%s | clean avg %.2f/ball over %d shots" % [
			_shot, _balls, damage, _hp_before, per_ball,
			" [assisted]" if _assisted else "", average_per_ball(), _clean_shots])


## Weighted average damage per ball over unassisted shots (total damage / total balls).
func average_per_ball() -> float:
	if _clean_balls == 0:
		return 0.0
	return float(_clean_damage) / float(_clean_balls)


func _append_csv(line: String) -> void:
	var is_new := not FileAccess.file_exists(PATH)
	var f := FileAccess.open(PATH, FileAccess.WRITE if is_new else FileAccess.READ_WRITE)
	if f == null:
		push_warning("DamageLog: can't open %s" % PATH)
		return
	if is_new:
		f.store_line(HEADER)
	else:
		f.seek_end()
	f.store_line(line)
	if not _announced:
		_announced = true
		print("[dmg] logging to ", ProjectSettings.globalize_path(PATH))
