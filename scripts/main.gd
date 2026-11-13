extends Node2D
## Game manager: board layout, aiming input, firing, round flow, spawning.

enum State { AIMING, FIRING, GAME_OVER, WON }

# --- layout (viewport is 540 x 960) ---
const COLS := 10
const CELL := 54.0
const WIDTH := COLS * CELL            # 540
const CEIL_Y := 80.0                  # top of play area (HUD sits above)
const FLOOR_ROW := 15
const LAST_ROW := FLOOR_ROW - 1       # a block reaching this row = game over
const FLOOR_Y := CEIL_Y + FLOOR_ROW * CELL
const HEIGHT := 960
const SPAWN_ROW := 1                  # one block height below the ceiling
const WALL_THICKNESS := 200.0
const MIN_AIM_ANGLE_DEG := 2.0
const AIM_MAX_LENGTH := 2000.0
const AIM_COLOR := Color(0.459, 0.732, 0.487, 0.502)
const AIM_WIDTH := 4.0
const SPEED_STEPS := [1.0, 2.0, 3.0]

const BLOCK_SCENE := preload("res://scenes/block.tscn")
const BALL_SCENE := preload("res://scenes/ball.tscn")
const PICKUP_SCENE := preload("res://scenes/ball_pickup.tscn")


const POWERUP_MIN_ROW := 0
const POWERUP_MAX_ROW := LAST_ROW - 1

const ABILITIES := ["bump", "bounce", "boost"]
const ABILITY_USES := 3
const BOOST_BALLS := 10
const BOUNCE_COLOR := Color(0.3, 0.9, 1.0)



# --- tuning ---
@export var ball_speed := 700.0
@export var ball_delay := 0.08
@export var min_blocks := 6
@export var max_blocks := 9
@export_range(0.0, 1.0) var pickup_chance := 0.5
## If true, the launcher moves to where the first ball landed (Ballz style).
@export var move_launcher_to_first_landing := false
@export_range(0.0, 1.0) var powerup_chance := 0.5
@export_range(0, 10) var aim_bounces := 1
@export_range(0.0, 1.0) var circle_chance := 0.2
## Levels mode: assign a LevelData to play it. Leave empty for Classic.
@export var level: LevelData
## Quick test switch: plays LevelData.sample() when no level is assigned.
@export var use_sample_level := false
## Writes per-shot damage stats to user://damage_log.csv and prints a running average.
@export var log_damage := false
## Levels: prints the LevelAnalyzer report (pressure, win probability) when the game starts.
@export var analyze_level := false
## Debug: added to the starting reserve, so you can sample at higher ball counts.
@export var debug_extra_balls := 0
## Debug (Classic): start as if the run had already reached this round, with block HP
## to match and a few older rows already on the board.
@export var debug_start_round := 1

@export var report_generated_levels := false
@export var play_generated_level := 0   # >0 plays that level number

## Bakes levels bake_from..bake_to to res://levels/ and quits. Run from the editor.
@export var bake_levels := false
@export var bake_from := 1
@export var bake_to := 100
## Replaces existing files, including any hand edits.
@export var bake_overwrite := false

@onready var board: Node2D = $Board
@onready var balls_node: Node2D = $Balls
@onready var hud = $HUD


var state := State.AIMING:
	set(v):
		state = v
		_refresh_abilities()
var round_number := 1
var ball_reserve := 1
var launcher_x := WIDTH / 2.0
var balls_in_flight := 0
var aiming := false:
	set(v):
		aiming = v
		_refresh_abilities()
var aim_dir := Vector2.ZERO
var aim_path := PackedVector2Array()  # [origin, bounce point, end point]
var _aim_shape: CircleShape2D
var game_id := 0
var next_launcher_x := -1.0
var descend_tween: Tween
var launcher_tween: Tween

var speed_index := 0
var mode: GameMode
var damage_log: DamageLog

var powerup_types: Array = [HorizontalBeam, VerticalBeam, Splitter, Upper]#HorizontalBeam, VerticalBeam, Splitter, Upper
var active_powerup: Powerup

var uses_left := {}
var used_this_round := {}
var bounce_armed := false
var bounce_hits_left := 0
var temp_balls := 0
var bumping := false
var bump_tween: Tween

var _pending_end_action: Callable = func(): pass
#e

func _ready() -> void:
	_build_walls()
	hud.reset_pressed.connect(reset_game)
	hud.speed_pressed.connect(_cycle_speed)
	hud.ability_pressed.connect(_on_ability_pressed)
	_aim_shape = CircleShape2D.new()
	_aim_shape.radius = Ball.RADIUS
	
	var gen_model := DamageModel.from_csv(DamageLog.PATH)
	if gen_model == null:
		gen_model = DamageModel.default()
	if report_generated_levels:
		LevelGenerator.print_report(80,100, gen_model, LAST_ROW, SPAWN_ROW)
	if level == null and play_generated_level > 0:
		level = LevelGenerator.generate(play_generated_level, gen_model, LAST_ROW, SPAWN_ROW)
	
	if bake_levels:
		LevelBaker.bake(bake_from, bake_to, gen_model, LAST_ROW, SPAWN_ROW, bake_overwrite)
		get_tree().quit()
		return
	
	if Session.current_level != null:
		level = Session.current_level
	elif Session.classic_active:
		# Classic from the menu is always a plain run, whatever the debug exports say.
		level = null
		use_sample_level = false
		debug_start_round = 1
	
	if mode == null:
		if level == null and use_sample_level:
			level = LevelData.sample()
		if level != null:
			mode = LevelMode.new(level)
		else:
			mode = ClassicMode.new()
	if analyze_level and level != null:
		var model := DamageModel.from_csv(DamageLog.PATH)
		if model == null:
			model = DamageModel.default()
		print(LevelAnalyzer.report_text(level, LevelAnalyzer.analyze(level, model, LAST_ROW, SPAWN_ROW)))
	if log_damage:
		damage_log = DamageLog.new()
		
	#if Session.current_number > 0 or Session.classic_active:
		#back_button = LevelUI.make_back_button()
		#add_child(back_button)
	hud.primary_button_pressed.connect(_on_primary_end_pressed)
	hud.secondary_button_pressed.connect(_on_secondary_end_pressed)
	hud.extra_button_pressed.connect(_on_extra_end_pressed)
	hud.return_pressed.connect(_on_return_pressed)
	reset_game()


## Switch rules and restart.
func set_mode(m: GameMode) -> void:
	mode = m
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
	#if is_instance_valid(end_panel):
		#end_panel.queue_free()
	#end_panel = null
	if descend_tween:
		descend_tween.kill()
	if launcher_tween:
		launcher_tween.kill()
	if bump_tween:
		bump_tween.kill()
	bumping = false
	var granted := mode.starting_abilities(self)
	uses_left = {}
	for a in ABILITIES:
		uses_left[a] = granted.get(a, 0)
	used_this_round.clear()
	bounce_armed = false
	bounce_hits_left = 0
	temp_balls = 0
	next_launcher_x = -1.0
	for c in board.get_children():
		c.queue_free()
	for c in balls_node.get_children():
		c.queue_free()
	_remove_powerup()
	round_number = mode.starting_round(self)
	ball_reserve = mode.starting_balls() + debug_extra_balls
	launcher_x = WIDTH / 2.0
	balls_in_flight = 0
	aiming = false
	aim_dir = Vector2.ZERO
	hud.hide_game_over()
	hud.set_round(round_number)
	hud.set_balls(_total_balls())
	_set_speed_index(0)
	mode.setup(self)
	if mode.powerups_enabled():
		_maybe_spawn_powerup()
		
	if mode is LevelMode:
		hud.set_return_text("Levels")
	else:
		hud.set_return_text("Home")
		
	state = State.AIMING
	queue_redraw()


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if state != State.AIMING or bumping:
		return
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
		aim_path = PackedVector2Array()
	else:
		var min_a := deg_to_rad(MIN_AIM_ANGLE_DEG)
		var angle := clampf(d.angle(), -PI + min_a, -min_a)
		aim_dir = Vector2.from_angle(angle)
		aim_path = _trace_aim(_launch_origin(), aim_dir)
	queue_redraw()

## Predicts the ball's route: straight to the first thing it hits, then `aim_bounces` bounces.
## Returns ball-center positions: [origin, hit 1, hit 2, ...].
func _trace_aim(origin: Vector2, dir: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array([origin])
	var pos := origin
	for i in aim_bounces + 1:
		var hit := _sweep_ball(pos, dir)
		path.append(hit.pos)
		if hit.normal == Vector2.ZERO:  # reached the floor, nothing to bounce off
			break
		dir = Ball.bounced_dir(dir, hit.normal)
		# start a hair off the surface so the next sweep doesn't re-hit it
		pos = hit.pos + hit.normal * 0.5
	return path


## Slides a ball-sized circle from `from` along `dir` until it touches a wall or block,
## or reaches the floor. Returns {pos: where it stops, normal: surface normal, or ZERO
## if it didn't hit anything solid}.
func _sweep_ball(from: Vector2, dir: Vector2) -> Dictionary:
	var motion := dir * AIM_MAX_LENGTH
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _aim_shape
	params.transform = Transform2D(0.0, from)
	params.motion = motion
	params.collision_mask = 1  # walls + blocks, same as Ball

	var space := get_world_2d().direct_space_state
	var fractions := space.cast_motion(params)  # [safe, unsafe]; [1, 1] = no hit
	var safe: float = fractions[0]
	var unsafe: float = fractions[1]
	var pos := from + motion * safe
	var normal := Vector2.ZERO

	if unsafe < 1.0:
		# ask the physics server which way the surface faces at the contact point
		params.transform = Transform2D(0.0, from + motion * unsafe)
		params.motion = Vector2.ZERO
		params.margin = 1.0
		var rest := space.get_rest_info(params)
		normal = rest["normal"] if not rest.is_empty() else -dir
		if normal.dot(dir) > 0.0:  # must face back toward the ball
			normal = -normal

	# a ball heading down lands on the floor instead
	if dir.y > 0.0:
		var floor_dist := (FLOOR_Y - Ball.RADIUS - from.y) / dir.y
		if floor_dist < pos.distance_to(from):
			pos = from + dir * floor_dist
			normal = Vector2.ZERO

	return {"pos": pos, "normal": normal}
# ---------------------------------------------------------------- round flow

func _fire(dir: Vector2) -> void:
	state = State.FIRING
	var origin := _launch_origin()
	next_launcher_x = -1.0
	var my_game := game_id
	var to_launch := _total_balls()
	if damage_log != null:
		damage_log.begin(self, to_launch, bounce_armed or temp_balls > 0)
	if bounce_armed:
		bounce_armed = false
		bounce_hits_left = to_launch   # one floor hit per ball launched
	balls_in_flight = to_launch
	queue_redraw()

	for i in to_launch:
		if my_game != game_id:
			return
		spawn_ball(origin, dir)
		await get_tree().create_timer(ball_delay).timeout


func spawn_ball(pos: Vector2, dir: Vector2) -> Ball:
	var ball: Ball = BALL_SCENE.instantiate()
	ball.speed = ball_speed
	ball.floor_y = FLOOR_Y
	ball.position = pos
	ball.landed.connect(_on_ball_landed)
	ball.floor_check = _try_floor_bounce
	balls_node.add_child(ball)
	ball.launch(dir)
	return ball


## Temporary ball from a splitter. It isn't part of the reserve, but it is counted
## in flight so the round can't end while it's still bouncing around.
func spawn_extra_ball(pos: Vector2, dir: Vector2) -> void:
	balls_in_flight += 1
	_add_extra_ball.call_deferred(pos, dir)  # can't add physics bodies mid-collision callback


func _add_extra_ball(pos: Vector2, dir: Vector2) -> void:
	var ball := spawn_ball(pos, dir)
	ball.has_split = true


## Same angle range as the player's aim.
func random_up_dir() -> Vector2:
	var min_a := deg_to_rad(MIN_AIM_ANGLE_DEG)
	return Vector2.from_angle(randf_range(-PI + min_a, -min_a))

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
	bounce_hits_left = 0
	temp_balls = 0
	used_this_round.clear()
	hud.set_balls(ball_reserve)
	if damage_log != null:
		damage_log.end(self)

	# win is checked before anything moves (round_number == shots taken so far)
	if mode.check_win(self):
		_finish_run(true, round_number)
		return

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

	if mode.check_lose(self):
		_finish_run(false, round_number)
		return

	mode.on_round_end(self)
	if mode.powerups_enabled():
		_maybe_spawn_powerup()
	state = State.AIMING
	queue_redraw()


## Ends the run. `count` is the shots taken (win) or the round reached (lose).
#func _finish_run(won: bool, count: int) -> void:
	#if Session.current_number > 0 and mode is LevelMode:
		#var info := {}
		#if won:
			#info = Session.complete_level(count)
		#state = State.WON if won else State.GAME_OVER
		#end_panel = LevelUI.make_end_panel(self, won, count, info)
		#add_child(end_panel)
		#queue_redraw()
		#return
	#if won:
		#state = State.WON
		#if hud.has_method("show_win"):
			#hud.show_win(count)
		#else:
			#print("Level cleared in %d shots" % count)  # TODO: add show_win() to the HUD
	#else:
		#state = State.GAME_OVER
		#hud.show_game_over(count)
		#
	#queue_redraw()
func _finish_run(won: bool, count: int) -> void:
	state = State.WON if won else State.GAME_OVER
	
	if mode is LevelMode:
		var n := Session.current_number
		var info := {}
		if won:
			info = Session.complete_level(count)
			var shots_text := "%d shots" % count
			var par := Session.par_of(n)
			if par > 0:
				shots_text += "   (par %d)" % par
			var best := int(info.get("best", count))
			var best_text := "New best!" if info.get("new_best", false) else "Best: %d" % best
			
			var primary_text = "Next level" if info.get("has_next", false) else ""
			if info.get("has_next", false):
				_pending_end_action = func(): Session.start_level.bind(n + 1).call()
			
			hud.show_end_panel("Level %d cleared" % n, "%s\n%s" % [shots_text, best_text], primary_text, "Retry", "Levels")
		else:
			hud.show_end_panel("Level %d failed" % n, "Blocks reached the bottom on shot %d" % count, "Retry", "Levels", "")
			_pending_end_action = func(): reset_game()
	else:
		var info = Session.complete_classic(count)
		if info.new:
			hud.show_end_panel("Victory!", "Reached Round %d. Previous best was %d." % [count,info.previous], "Play Again", "Menu", "")
		else:
			hud.show_end_panel("Game Over", "Reached Round %d. Current best is %d." % [count, info.previous], "Play Again", "Menu", "")
		_pending_end_action = func(): reset_game()
	
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


## Classic-style row: random columns, random shapes, maybe a ball pickup.
func spawn_random_row(hp: int, row := SPAWN_ROW) -> void:
	var cols: Array = range(COLS)
	cols.shuffle()
	var count := clampi(randi_range(min_blocks, max_blocks), 0, COLS)
	for i in count:
		add_block(cols[i], row, hp, randf() < circle_chance)
	# a pickup goes in one of the remaining empty columns
	if count < COLS and randf() < pickup_chance:
		add_pickup(cols[count], row)


func add_block(col: int, row: int, hp: int, circle := false) -> void:
	var b: Block = BLOCK_SCENE.instantiate()
	b.setup(hp, CELL, circle)
	b.col = col
	b.row = row
	b.position = Vector2(_col_to_x(col), _row_to_y(row))
	board.add_child(b)


func add_pickup(col: int, row: int) -> void:
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
	hud.set_balls(_total_balls())


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
	if damage_log != null:
		damage_log.note_assist()
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


## Blocks that haven't started their destroy animation.
func live_blocks() -> Array:
	return board.get_children().filter(
			func(n): return n is Block and not n.dying)


func blocks_in_row(row: int) -> Array:
	return board.get_children().filter(
			func(n): return n is Block and not n.dying and n.row == row)


func blocks_in_col(col: int) -> Array:
	return board.get_children().filter(
			func(n): return n is Block and not n.dying and n.col == col)


# ---------------------------------------------------------------- abilities

func _total_balls() -> int:
	return ball_reserve + temp_balls


func _refresh_abilities() -> void:
	if hud == null:
		return
	var can_use := state == State.AIMING and not aiming and not bumping
	for a in ABILITIES:
		var used: bool = used_this_round.has(a)
		hud.set_ability(a, uses_left[a], can_use and uses_left[a] > 0 and not used, used)


func _on_ability_pressed(kind: String) -> void:
	if state != State.AIMING or aiming or bumping:
		return
	if uses_left[kind] <= 0 or used_this_round.has(kind):
		return
	match kind:
		"bump":
			if not _activate_bump():
				return
		"bounce":
			bounce_armed = true
		"boost":
			temp_balls = BOOST_BALLS
			hud.set_balls(_total_balls())
	uses_left[kind] -= 1
	used_this_round[kind] = true
	_refresh_abilities()
	queue_redraw()


## Pops everything in the top row, then slides the rest up one row.
func _activate_bump() -> bool:
	var nodes: Array = board.get_children().filter(
			func(n): return not (n is Block and n.dying))
	if nodes.is_empty():
		return false  # nothing to bump, don't spend a use
	bumping = true
	bump_tween = create_tween().set_parallel(true)
	for n in nodes:
		if n.row <= SPAWN_ROW:
			if n is Block:
				n.hit(n.hp)  # normal destroy effect
			else:
				n.queue_free()  # ball pickup in the top row is lost
		else:
			n.row -= 1
			bump_tween.tween_property(n, "position:y", _row_to_y(n.row), 0.25)
	bump_tween.chain().tween_callback(_on_bump_done)
	return true


func _on_bump_done() -> void:
	bumping = false
	# a bump can clear the last block (round_number - 1 = shots taken so far)
	if mode.check_win(self):
		_finish_run(true, round_number - 1)
		return
	_refresh_abilities()


## Called by each ball when it reaches the floor. True = reflect instead of landing.
func _try_floor_bounce(_ball: Ball) -> bool:
	if bounce_hits_left <= 0:
		return false
	bounce_hits_left -= 1
	queue_redraw()
	return true

# -------------------------- end buttons
func _on_primary_end_pressed() -> void:
	if mode is LevelMode and Session.current_number > 0 and state == State.WON:
		var n := Session.current_number
		Session.start_level(n + 1)
	else:
		reset_game()

func _on_secondary_end_pressed() -> void:
	if mode is LevelMode and Session.current_number > 0:
		Session.open_select()
	else:
		Session.open_menu()

func _on_extra_end_pressed() -> void:
	if mode is LevelMode and Session.current_number > 0:
		Session.open_select()

func _on_return_pressed() -> void:
	if mode is LevelMode:
		Session.open_select()
	else:
		Session.open_menu()

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	#draw_rect(Rect2(0, 0, WIDTH, CEIL_Y), Color(0.09, 0.10, 0.15))
	#draw_line(Vector2(0, CEIL_Y), Vector2(WIDTH, CEIL_Y), Color.WHITE, 2.0)
	#
	#draw_rect(Rect2(0, CEIL_Y, WIDTH, FLOOR_Y - CEIL_Y), Color(0.09, 0.10, 0.15))
	#
	#draw_rect(Rect2(0, FLOOR_Y, WIDTH, HEIGHT - FLOOR_Y), Color(0.09, 0.10, 0.15))
	#
	#draw_line(Vector2(0, FLOOR_Y), Vector2(WIDTH, FLOOR_Y), Color.WHITE, 2.0)
	draw_rect(Rect2(0, 0, WIDTH, HEIGHT), Color(0.09, 0.10, 0.15))
	draw_line(Vector2(0, CEIL_Y), Vector2(WIDTH, CEIL_Y), Color.WHITE, 4.0)
	draw_line(Vector2(0, FLOOR_Y), Vector2(WIDTH, FLOOR_Y), Color.WHITE, 4.0)

	var origin := _launch_origin()
	draw_circle(origin, Ball.RADIUS, Color.WHITE)
	if state == State.AIMING:
		draw_string(ThemeDB.fallback_font, Vector2(launcher_x - 30.0, FLOOR_Y - 30.0),
				"x%d" % _total_balls(), HORIZONTAL_ALIGNMENT_CENTER, 60.0, 18, Color.WHITE)
		if aim_dir != Vector2.ZERO:
			if aim_dir != Vector2.ZERO and aim_path.size() >= 2:
				for i in aim_path.size() - 1:
					draw_dashed_line(aim_path[i], aim_path[i + 1], AIM_COLOR, AIM_WIDTH, 8.0)
		if bounce_armed or bounce_hits_left > 0:
			draw_line(Vector2(0, FLOOR_Y), Vector2(WIDTH, FLOOR_Y), BOUNCE_COLOR, 6.0)
			if bounce_hits_left > 0:
				draw_string(ThemeDB.fallback_font, Vector2(WIDTH - 90.0, FLOOR_Y - 10.0),
						"Bounce %d" % bounce_hits_left, HORIZONTAL_ALIGNMENT_RIGHT, 80.0, 16, BOUNCE_COLOR)
