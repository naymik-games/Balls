class_name ClassicMode
extends GameMode
## The game as it is today: one ball, a new random row every round with
## hp = round number, endless until a block reaches the bottom.


## Cap on the rows faked by debug_start_round, so a debug start can't begin near the floor.
const MAX_PREFILL_ROWS := 6


func starting_round(game) -> int:
	return maxi(game.debug_start_round, 1)


func starting_balls() -> int:
	return 1


func starting_abilities(game) -> Dictionary:
	var granted := {}
	for a in game.ABILITIES:
		granted[a] = game.ABILITY_USES
	return granted


## Normally one row at hp 1. With debug_start_round > 1 it fakes the history of a run
## that got that far: the newest row on top, older rows below with lower hp.
func setup(game) -> void:
	var rows := clampi(game.round_number, 1, MAX_PREFILL_ROWS)
	for i in rows:
		game.spawn_random_row(maxi(game.round_number - i, 1), game.SPAWN_ROW + i)


func on_round_end(game) -> void:
	game.spawn_random_row(game.round_number)
