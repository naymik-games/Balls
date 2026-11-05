extends Node2D
## Game manager: board layout, aiming input, firing, round flow, spawning.

enum State { AIMING, FIRING, GAME_OVER }

# --- layout (viewport is 540 x 960) ---
const COLS := 10
const CELL := 54.0
const WIDTH := COLS * CELL            # 540
const CEIL_Y := 80.0                  # top of play area (HUD sits above)
const FLOOR_ROW := 15
const LAST_ROW := FLOOR_ROW - 1       # a block reaching this row = game over
const FLOOR_Y := CEIL_Y + FLOOR_ROW * CELL
const SPAWN_ROW := 1                  # one block height below the ceiling
const WALL_THICKNESS := 200.0
const MIN_AIM_ANGLE_DEG := 5.0
const SPEED_STEPS := [1.0, 2.0, 3.0]

const BLOCK_SCENE := preload("res://scenes/block.tscn")
const BALL_SCENE := preload("res://scenes/ball.tscn")
const PICKUP_SCENE := preload("res://scenes/ball_pickup.tscn")


const POWERUP_MIN_ROW := 0
const POWERUP_MAX_ROW := LAST_ROW - 1
# --- tuning ---
@export var ball_speed := 700.0
@export var ball_delay := 0.08
@export var min_blocks := 6
@export var max_blocks := 9
@export_range(0.0, 1.0) var pickup_chance := 0.5
## If true, the launcher moves to where the first ball landed (Ballz style).
@export var move_launcher_to_first_landing := false
@export_range(0.0, 1.0) var powerup_chance := 0.5

@onready var board: Node2D = $Board
@onready var balls_node: Node2D = $Balls
@onready var hud = $HUD


var state := State.AIMING
var round_number := 1
var ball_reserve := 1
var launcher_x := WIDTH / 2.0
var balls_in_flight := 0
var aiming := false
var aim_dir := Vector2.ZERO
var game_id := 0
var next_launcher_x := -1.0
var descend_tween: Tween
var launcher_tween: Tween

var speed_index := 0

var powerup_types: Array = [HorizontalBeam, VerticalBeam]
var active_powerup: Powerup

func _ready() -> void:
	_build_walls()
	hud.reset_pressed.connect(reset_game)
	hud.speed_pressed.connect(_cycle_speed)
	reset_game()


# ---------------------------------------------------------------- setup

func _build_walls() -> void:
	var t := WALL_THICKNESS
	var h := FLOOR_Y - CEIL_Y
	_add_wall(Rect2(-t, CEIL_Y - t, t, h + t))              # left
	_add_wall(Rect2(WIDTH, CEIL_Y - t, t, h + t))           # right
	_add_wall(Rect2(-t, CEIL_Y - t, WIDTH + 2.0 * t, t))    # ceiling


func _add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = rect.size
	shape.shape = r
	body.add_child(shape)
	add_child(body)


func reset_game() -> void:
	game_id += 1  # cancels any in-progress launch coroutine
	if descend_tween:
		descend_tween.kill()
	if launcher_tween:
		launcher_tween.kill()
	next_launcher_x = -1.0
	for c in board.get_children():
		c.queue_free()
	for c in balls_node.get_children():
		c.queue_free()
	_remove_powerup()
	round_number = 1
	ball_reserve = 1
	launcher_x = WIDTH / 2.0
	balls_in_flight = 0
	aiming = false
	aim_dir = Vector2.ZERO
	hud.hide_game_over()
	hud.set_round(round_number)
	hud.set_balls(ball_reserve)
	_set_speed_index(0)
	_spawn_row(round_number)
	_maybe_spawn_powerup()
	state = State.AIMING
	queue_redraw()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if state != State.AIMING:
		return
	# Touch is emulated as mouse by default, so this covers mobile too.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			aiming = true
			_update_aim(get_global_mouse_position())
		elif aiming:
			aiming = false
			var dir := aim_dir
			aim_dir = Vector2.ZERO
			queue_redraw()
			if dir != Vector2.ZERO:
				_fire(dir)
	elif event is InputEventMouseMotion and aiming:
		_update_aim(get_global_mouse_position())


func _launch_origin() -> Vector2:
	return Vector2(launcher_x, FLOOR_Y - Ball.RADIUS)


func _update_aim(pointer: Vector2) -> void:
	var d := pointer - _launch_origin()
	if d.y > -10.0:
		aim_dir = Vector2.ZERO  # pointer below launcher = no shot (release to cancel)
	else:
		var min_a := deg_to_rad(MIN_AIM_ANGLE_DEG)
		var angle := clampf(d.angle(), -PI + min_a, -min_a)
		aim_dir = Vector2.from_angle(angle)
	queue_redraw()


# ---------------------------------------------------------------- round flow

func _fire(dir: Vector2) -> void:
	state = State.FIRING
	var origin := _launch_origin()
	next_launcher_x = -1.0
	var my_game := game_id
	var to_launch := ball_reserve
	balls_in_flight = to_launch
	queue_redraw()

	for i in to_launch:
		if my_game != game_id:
			return
		var ball: Ball = BALL_SCENE.instantiate()
		ball.speed = ball_speed
		ball.floor_y = FLOOR_Y
		ball.position = origin 
		ball.landed.connect(_on_ball_landed)
		balls_node.add_child(ball)
		ball.launch(dir)
		await get_tree().create_timer(ball_delay).timeout


func _on_ball_landed(ball: Ball) -> void:
	if next_launcher_x < 0.0 and move_launcher_to_first_landing:
		next_launcher_x = clampf(ball.position.x, Ball.RADIUS, WIDTH - Ball.RADIUS)
		_slide_launcher(next_launcher_x)
	ball.queue_free()
	balls_in_flight -= 1
	if balls_in_flight == 0:
		_end_round()

func _cycle_speed() -> void:
	_set_speed_index((speed_index + 1) % SPEED_STEPS.size())


func _set_speed_index(i: int) -> void:
	speed_index = i
	Engine.time_scale = SPEED_STEPS[i]
	hud.set_speed(int(SPEED_STEPS[i]))


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _end_round() -> void:
	var my_game := game_id
	_set_speed_index(0)
	_remove_powerup()
	round_number += 1
	#if next_launcher_x >= 0.0:
		#launcher_x = next_launcher_x
	hud.set_round(round_number)

	await _descend_rows()
	if my_game != game_id:
		return

	# pickups that reach the floor are lost
	for n in board.get_children():
		if n is BallPickup and n.row >= LAST_ROW:
			n.queue_free()
	# any block on the last row = game over
	for n in board.get_children():
		if n is Block and not n.dying and n.row >= LAST_ROW:
			state = State.GAME_OVER
			hud.show_game_over(round_number)
			queue_redraw()
			return

	_spawn_row(round_number)
	_maybe_spawn_powerup()
	state = State.AIMING
	queue_redraw()

func _descend_rows() -> void:
	var nodes := board.get_children()
	if nodes.is_empty():
		return
	descend_tween = create_tween().set_parallel(true)
	for n in nodes:
		n.row += 1
		descend_tween.tween_property(n, "position:y", _row_to_y(n.row), 0.25)
	await descend_tween.finished


# ---------------------------------------------------------------- spawning

func _row_to_y(row: int) -> float:
	return CEIL_Y + row * CELL + CELL / 2.0


func _col_to_x(col: int) -> float:
	return col * CELL + CELL / 2.0


func _spawn_row(hp: int) -> void:
	var cols: Array = range(COLS)
	cols.shuffle()
	var count := clampi(randi_range(min_blocks, max_blocks), 0, COLS)
	for i in count:
		_add_block(cols[i], SPAWN_ROW, hp)
	# a pickup goes in one of the remaining empty columns
	if count < COLS and randf() < pickup_chance:
		_add_pickup(cols[count], SPAWN_ROW)


func _add_block(col: int, row: int, hp: int) -> void:
	var b: Block = BLOCK_SCENE.instantiate()
	b.setup(hp, CELL)
	b.col = col
	b.row = row
	b.position = Vector2(_col_to_x(col), _row_to_y(row))
	board.add_child(b)


func _add_pickup(col: int, row: int) -> void:
	var p: BallPickup = PICKUP_SCENE.instantiate()
	p.col = col
	p.row = row
	p.position = Vector2(_col_to_x(col), _row_to_y(row))
	p.collected.connect(_on_pickup_collected)
	board.add_child(p)


func _slide_launcher(target_x: float) -> void:
	if launcher_tween:
		launcher_tween.kill()
	var duration := clampf(absf(target_x - launcher_x) / 1500.0, 0.08, 0.3)
	launcher_tween = create_tween()
	launcher_tween.tween_method(_set_launcher_x, launcher_x, target_x, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_launcher_x(x: float) -> void:
	launcher_x = x
	queue_redraw()


func _on_pickup_collected(_pickup: BallPickup) -> void:
	ball_reserve += 1
	hud.set_balls(ball_reserve)


# ---------------------------------------------------------------- powerups

func _maybe_spawn_powerup() -> void:
	if active_powerup != null or randf() >= powerup_chance:
		return
	var open := _open_cells()
	if open.is_empty():
		return
	var cell: Vector2i = open.pick_random()
	var p: Powerup = powerup_types.pick_random().new()
	p.col = cell.x
	p.row = cell.y
	p.position = Vector2(_col_to_x(cell.x), _row_to_y(cell.y))
	p.triggered.connect(_on_powerup_triggered)
	add_child(p)
	active_powerup = p


func _open_cells() -> Array[Vector2i]:
	var taken := {}
	for n in board.get_children():  # blocks and ball pickups
		taken[Vector2i(n.col, n.row)] = true
	var open: Array[Vector2i] = []
	for r in range(POWERUP_MIN_ROW, POWERUP_MAX_ROW + 1):
		for c in COLS:
			if not taken.has(Vector2i(c, r)):
				open.append(Vector2i(c, r))
	return open


func _on_powerup_triggered(p: Powerup, ball: Ball) -> void:
	p.apply(ball, self)
	if p.single_use:
		_remove_powerup()


func _remove_powerup() -> void:
	if active_powerup == null:
		return
	# can't change monitoring while physics callbacks are running, so defer it
	active_powerup.set_deferred("monitoring", false)
	active_powerup.queue_free()
	active_powerup = null


# helpers the powerups call through `game`
func play_rect() -> Rect2:
	return Rect2(0.0, CEIL_Y, WIDTH, FLOOR_Y - CEIL_Y)


func blocks_in_row(row: int) -> Array:
	return board.get_children().filter(
			func(n): return n is Block and not n.dying and n.row == row)


func blocks_in_col(col: int) -> Array:
	return board.get_children().filter(
			func(n): return n is Block and not n.dying and n.col == col)

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(0, CEIL_Y, WIDTH, FLOOR_Y - CEIL_Y), Color(0.09, 0.10, 0.15))
	draw_line(Vector2(0, FLOOR_Y), Vector2(WIDTH, FLOOR_Y), Color.WHITE, 2.0)

	var origin := _launch_origin()
	draw_circle(origin, Ball.RADIUS, Color.WHITE)
	if state == State.AIMING:
		draw_string(ThemeDB.fallback_font, Vector2(launcher_x - 30.0, FLOOR_Y + 30.0),
				"x%d" % ball_reserve, HORIZONTAL_ALIGNMENT_CENTER, 60.0, 18, Color.WHITE)
		if aim_dir != Vector2.ZERO:
			draw_dashed_line(origin, origin + aim_dir * 600.0, Color(1, 1, 1, 0.5), 2.0, 8.0)
