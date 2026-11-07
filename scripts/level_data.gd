class_name LevelData
extends Resource
## Everything that defines one level. Generated and hand-authored levels use the
## same format, so a generated level can be saved as a .tres and tweaked by hand.

@export var level_name := ""
## Fixed starting reserve.
@export var balls := 10
@export var start_blocks: Array[BlockSpec] = []
## Finite on purpose: the level can only be won once no waves remain.
@export var waves: Array[WaveSpec] = []
## {"bump": n, "bounce": n, "boost": n}. Empty = no abilities (opt-in).
@export var granted_abilities := {}
@export var powerups_enabled := true


## Builds a level from ASCII rows, top row first.
## '.' = empty, '1'-'9' = hp 1-9, 'a'-'z' = hp 10-35. All blocks are square.
static func from_ascii(lines: PackedStringArray, ball_count := 10) -> LevelData:
	var d := LevelData.new()
	d.balls = ball_count
	for r in lines.size():
		var line := lines[r]
		for c in line.length():
			var hp := char_to_hp(line[c])
			if hp > 0:
				d.start_blocks.append(BlockSpec.make(c, r, hp))
	return d


static func char_to_hp(ch: String) -> int:
	if ch >= "1" and ch <= "9":
		return ch.to_int()
	if ch >= "a" and ch <= "z":
		return 10 + ch.unicode_at(0) - "a".unicode_at(0)
	return 0


## A small hand-written level for testing the mode plumbing.
static func sample() -> LevelData:
	var d := from_ascii(PackedStringArray([
		"..333333..",
		".34444443.",
		"..333333..",
		"....22....",
	]), 8)
	d.level_name = "Sample"
	d.waves.append(WaveSpec.from_row(4, "2.2.2.2.2."))
	d.waves.append(WaveSpec.from_row(8, "3333333333"))
	return d
