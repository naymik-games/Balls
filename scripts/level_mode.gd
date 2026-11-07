class_name LevelMode
extends GameMode
## Plays a LevelData: a prebuilt board, a fixed ball reserve, and a finite list of
## waves. Win = no blocks left and no waves pending. Lose = a block reaches the
## bottom (inherited from GameMode).

var data: LevelData
var shots_taken := 0
var _waves_left: Array[WaveSpec] = []


func _init(level_data: LevelData) -> void:
	data = level_data


func starting_balls() -> int:
	return data.balls


func starting_abilities(_game) -> Dictionary:
	return data.granted_abilities


func powerups_enabled() -> bool:
	return data.powerups_enabled


func setup(game) -> void:
	shots_taken = 0
	_waves_left = data.waves.duplicate()
	_waves_left.sort_custom(func(a: WaveSpec, b: WaveSpec): return a.after_shot < b.after_shot)
	for spec in data.start_blocks:
		game.add_block(spec.col, game.SPAWN_ROW + spec.row, spec.hp, spec.is_circle)


func check_win(game) -> bool:
	return _waves_left.is_empty() and game.live_blocks().is_empty()


## One wave per round at most. A wave arrives when it is due, or early if the board
## has been cleared (so the player never fires into an empty field).
func on_round_end(game) -> void:
	shots_taken += 1
	if _waves_left.is_empty():
		return
	var due := _waves_left[0].after_shot <= shots_taken
	if due or game.live_blocks().is_empty():
		var wave: WaveSpec = _waves_left.pop_front()
		for cell in wave.cells:
			game.add_block(cell.col, game.SPAWN_ROW, cell.hp, cell.is_circle)


func waves_remaining() -> int:
	return _waves_left.size()
