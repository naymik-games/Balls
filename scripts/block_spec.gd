class_name BlockSpec
extends Resource
## One block in a level.

@export var col := 0
## 0 = the row new rows spawn on (the top row), counting down from there.
@export var row := 0
@export var hp := 1
@export var is_circle := false


static func make(c: int, r: int, h: int, circle := false) -> BlockSpec:
	var s := BlockSpec.new()
	s.col = c
	s.row = r
	s.hp = h
	s.is_circle = circle
	return s
