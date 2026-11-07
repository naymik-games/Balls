class_name WaveSpec
extends Resource
## A row of blocks that arrives during a level. Always spawns on the spawn row
## (only col, hp and is_circle of each cell are used; row is ignored).

## Spawns once this many shots have finished. If the board is empty it arrives early.
@export var after_shot := 3
@export var cells: Array[BlockSpec] = []


## One wave from an ASCII row, same characters as LevelData.from_ascii.
static func from_row(shot: int, line: String) -> WaveSpec:
	var w := WaveSpec.new()
	w.after_shot = shot
	for c in line.length():
		var hp := LevelData.char_to_hp(line[c])
		if hp > 0:
			w.cells.append(BlockSpec.make(c, 0, hp))
	return w
