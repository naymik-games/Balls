class_name GameMode
extends RefCounted
## Rules for one kind of run. main.gd owns the board, balls, input and round flow;
## a mode decides what starts on the board, what spawns between rounds, and when
## the run ends. `game` is main.gd (left untyped on purpose).


## Round counter at the start of a run.
func starting_round(_game) -> int:
	return 1


## Balls in the reserve at the start of a run.
func starting_balls() -> int:
	return 1


## {"bump": n, "bounce": n, "boost": n}. Missing keys mean 0 uses (opt-in).
func starting_abilities(_game) -> Dictionary:
	return {}


## Whether random board powerups (beams, splitter, upper) can appear.
func powerups_enabled() -> bool:
	return true


## Called once from reset_game(), after the board is cleared. Build the starting board.
func setup(_game) -> void:
	pass


## Called after each round's descent, if the run hasn't ended. Spawn new rows here.
func on_round_end(_game) -> void:
	pass


## Checked when the balls have landed, before blocks descend.
func check_win(_game) -> bool:
	return false


## Checked after blocks descend. Default: a live block on the last row.
func check_lose(game) -> bool:
	for b in game.live_blocks():
		if b.row >= game.LAST_ROW:
			return true
	return false
