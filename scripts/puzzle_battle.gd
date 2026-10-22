extends "res://scripts/beat_battle.gd"
## A separate 1v1 workbench. The full 2v2 scene remains available unchanged.
const OPEN_CELLS := Rect2i(5, 5, 3, 3)
const PUZZLE_SPAWNS := [Vector2i(5, 6), Vector2i(5, 5), Vector2i(7, 6), Vector2i(7, 7)]
const PARTICIPANTS := [0, 2]
var puzzle_outcome := ""
var puzzle_hint: Label

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beat-"):
			set_process(false)
			set_physics_process(false)
			hide()
			get_tree().change_scene_to_file.call_deferred("res://beat_arena.tscn")
			return
	deployment_cells = PUZZLE_SPAWNS.duplicate()
	super._ready()
	DisplayServer.window_set_title("AutoBattle — 3×3 / 躲开第一枪")
	puzzle_hint = text_label(self, "", 16)
	puzzle_hint.position = Vector2(45, 225)
	puzzle_hint.modulate = Color("eee0ac")
	for connection in arena_mode_button.pressed.get_connections(): arena_mode_button.pressed.disconnect(connection.callable)
	arena_mode_button.text = "← 返回2v2"
	arena_mode_button.pressed.connect(func(): get_tree().change_scene_to_file("res://beat_arena.tscn"))
	for child in get_children():
		if child is Label and child.text == "AUTOBATTLE / BEAT": child.text = "AUTOBATTLE / PUZZLE"
	choose_editor_unit(0)
	refresh_ui()
	if "--puzzle-test" in OS.get_cmdline_user_args():
		run_puzzle_checks()
		get_tree().quit()
	if "--puzzle-preview" in OS.get_cmdline_user_args():
		set_process(false)
		set_physics_process(false)
		capture_puzzle_preview.call_deferred()

func make_arena_view():
	return preload("res://scripts/puzzle_view.gd").new()

func setup_loadouts() -> void:
	loadouts = [Tactics.build([], []), Tactics.build([], []), Tactics.build([["普通攻击", "无", "无"]], []), Tactics.build([], [])]

func reset_walls() -> void:
	# 55 filled cells; only F6:H8, the corner nearest the audience, is traversable.
	walls.assign([Rect2(0, 0, 640, 400), Rect2(0, 400, 400, 240)])
	wall_states.clear()
	wall_damage.clear()
	for index in range(walls.size()): wall_states.append({"id": index, "rect": walls[index], "hp": WALL_HP})

func deployment_position(uid: int) -> Vector2:
	var cell: Vector2i = deployment_cells[uid]
	if blue_attacks: cell.x = 12 - cell.x
	return Beat.center(cell)

func validate_deployment() -> void:
	for uid in PARTICIPANTS:
		if not OPEN_CELLS.has_point(deployment_cells[uid]):
			deployment_cells = PUZZLE_SPAWNS.duplicate()
			return
	if deployment_cells[0] == deployment_cells[2]: deployment_cells = PUZZLE_SPAWNS.duplicate()

func can_deploy(uid: int, cell: Vector2i) -> bool:
	if started or uid not in PARTICIPANTS or not OPEN_CELLS.has_point(cell): return false
	for other in PARTICIPANTS:
		if other != uid and Beat.cell_of(units[other].p) == cell: return false
	return true

func place_unit(uid: int, cell: Vector2i) -> bool:
	if not super.place_unit(uid, cell): return false
	deployment_cells[uid] = Vector2i(12 - cell.x, cell.y) if blue_attacks else cell
	return true

func choose_editor_unit(uid: int) -> void:
	if uid in PARTICIPANTS: super.choose_editor_unit(uid)

func reset_round() -> void:
	puzzle_outcome = ""
	super.reset_round()
	for u in units:
		u.enabled = u.uid in PARTICIPANTS
		if not u.enabled: u.hp = 0
	beat_sim.reset(units, loadouts, walls)
	units.assign(beat_sim.units)
	presentation.reset(units)
	refresh_ui()

func refresh_ui() -> void:
	super.refresh_ui()
	if units.is_empty(): return
	subtitle.text = "3×3 谜题工作台 · 1v1 · 只保留前方 F6—H8 九格"
	if not started: status_label.text = "题目01：躲开第一枪  |  修改策略后按 N，完整播放一拍"
	for uid in range(roster_buttons.size()): roster_buttons[uid].visible = uid in PARTICIPANTS
	if soldier_hint != null: soldier_hint.text = "3×3 / 1v1\n单格吊射 · 射程4\nN逐拍 · R重试"
	if puzzle_hint != null:
		puzzle_hint.text = "题目01 · 躲开第一枪\n目标：红方第一枪结算时，蓝方不受伤。\n蓝方策略留空；右侧选择技能和条件，修改后重开。\nN：播放一拍并暂停    R：重试" if puzzle_outcome.is_empty() else puzzle_outcome + "\n按 R 重试，或修改蓝方策略后再试。"

func simulate(dt: float, animate_after := true) -> void:
	super.simulate(dt, animate_after)
	if puzzle_outcome.is_empty() and beat_sim.effects.any(func(effect): return effect.source == 2):
		puzzle_outcome = "通过：蓝方躲开了第一枪。" if units[0].hp == Beat.MAX_HP else "未通过：第一枪命中了蓝方。"
		running = false
		steps_remaining = 0
	refresh_ui()

func step_forward(frame_count := 1) -> void:
	if puzzle_outcome.is_empty(): super.step_forward(frame_count)

func toggle_running() -> void:
	if puzzle_outcome.is_empty(): super.toggle_running()

func run_puzzle_checks() -> void:
	assert(beat_sim.blocked_cells.size() == 55)
	for x in range(8):
		for y in range(8): assert(beat_sim.legal(Vector2i(x, y)) == OPEN_CELLS.has_point(Vector2i(x, y)))
	assert(units.filter(func(u): return u.enabled and u.hp > 0).size() == 2)
	assert(not can_deploy(0, Vector2i(4, 6)) and can_deploy(0, Vector2i(5, 5)))
	assert(place_unit(0, Vector2i(5, 5)))
	reset_round()
	assert(units[0].cell == Vector2i(5, 5))
	deployment_cells = PUZZLE_SPAWNS.duplicate()
	reset_round()
	step_forward()
	advance_playback(0.5)
	assert(logic_frame == 1 and units[0].hp == 5 and puzzle_outcome.is_empty())
	step_forward()
	advance_playback(0.5)
	assert(units[0].hp == 4 and puzzle_outcome.begins_with("未通过"))
	loadouts[0] = Tactics.build([], [["侧闪", "无", "无"]])
	reset_round()
	step_forward(12)
	advance_playback(10)
	assert(logic_frame == 2 and units[0].hp == 5 and puzzle_outcome.begins_with("通过"))
	assert(Beat.posture(units[0]) == "移动姿态")
	for u in units:
		if u.enabled: assert(OPEN_CELLS.has_point(u.cell))
	assert(not running and steps_remaining == 0 and not segment_active)
	var report := {"open_cells": 9, "blocked_cells": 55, "participants": PARTICIPANTS,
		"checks": ["inactive slots are not rendered or selectable", "all cells outside F6:H8 blocked", "deployment survives reset", "empty blue rules fail at first impact", "PP dodge succeeds and retains directed movement", "single-step and four-step both stop at the puzzle result"]}
	var report_file := FileAccess.open("res://reports/puzzle-validation.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	print("PUZZLE PASSED: 9 open/55 blocked cells, exactly 1v1, placement persistence, empty rules fail, PP dodge succeeds at endpoint2")

func capture_puzzle_preview() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/puzzle-preview.png")
	get_tree().quit()
