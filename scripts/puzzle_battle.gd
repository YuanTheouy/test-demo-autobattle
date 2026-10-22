extends "res://scripts/beat_battle.gd"
## A separate 1v1 workbench. The full 2v2 scene remains available unchanged.
const OPEN_CELLS := Rect2i(5, 5, 3, 3)
const DUEL_SPAWNS := [Vector2i(5, 6), Vector2i(5, 5), Vector2i(7, 6), Vector2i(7, 7)]
const PARTICIPANTS := [0, 2]

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beat-"):
			set_process(false)
			set_physics_process(false)
			hide()
			get_tree().change_scene_to_file.call_deferred("res://beat_arena.tscn")
			return
	deployment_cells = DUEL_SPAWNS.duplicate()
	super._ready()
	DisplayServer.window_set_title("AutoBattle — 3×3 / 1v1 自由对战")
	for connection in arena_mode_button.pressed.get_connections(): arena_mode_button.pressed.disconnect(connection.callable)
	arena_mode_button.text = "← 返回2v2"
	arena_mode_button.pressed.connect(func(): get_tree().change_scene_to_file("res://beat_arena.tscn"))
	for child in get_children():
		if child is Label and child.text == "AUTOBATTLE / BEAT": child.text = "AUTOBATTLE / DUEL"
	if "--duel-presets-demo" in OS.get_cmdline_user_args():
		apply_preset(0, SOLDIER_PRESET + 1)
		apply_preset(1, SOLDIER_PRESET + 2)
	if "--prediction-demo" in OS.get_cmdline_user_args():
		apply_preset(0, SOLDIER_PRESET + 5)
		apply_preset(1, SOLDIER_PRESET + 2)
	choose_editor_unit(0)
	refresh_ui()
	if "--small-arena-test" in OS.get_cmdline_user_args() or "--puzzle-test" in OS.get_cmdline_user_args():
		run_small_arena_checks()
		get_tree().quit()
	if "--small-arena-preview" in OS.get_cmdline_user_args() or "--puzzle-preview" in OS.get_cmdline_user_args():
		set_process(false)
		set_physics_process(false)
		capture_puzzle_preview.call_deferred()

func make_arena_view():
	return preload("res://scripts/puzzle_view.gd").new()

func setup_loadouts() -> void:
	super.setup_loadouts()
	for uid in [1, 3]: loadouts[uid] = Tactics.build([], [])

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
			deployment_cells = DUEL_SPAWNS.duplicate()
			return
	if deployment_cells[0] == deployment_cells[2]: deployment_cells = DUEL_SPAWNS.duplicate()

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
	subtitle.text = "3×3 自由对战 · 1v1 · 双方策略均可调整"
	if not started: status_label.text = "3×3 自由布阵  |  空格连续战斗 / N逐拍 / R重开"
	for uid in range(roster_buttons.size()): roster_buttons[uid].visible = uid in PARTICIPANTS
	if soldier_hint != null: soldier_hint.text = "3×3 / 1v1\n单格吊射 · 射程4\nN逐拍 · R重开"
func run_small_arena_checks() -> void:
	assert(beat_sim.blocked_cells.size() == 55)
	for x in range(8):
		for y in range(8): assert(beat_sim.legal(Vector2i(x, y)) == OPEN_CELLS.has_point(Vector2i(x, y)))
	assert(units.filter(func(u): return u.enabled and u.hp == 2).size() == 2)
	assert(not can_deploy(0, Vector2i(4, 6)) and can_deploy(0, Vector2i(5, 5)))
	assert(place_unit(0, Vector2i(5, 5)))
	reset_round()
	assert(units[0].cell == Vector2i(5, 5))
	deployment_cells = DUEL_SPAWNS.duplicate()
	reset_round()
	assert(loadouts[0] == loadouts[2] and not loadouts[0].active.is_empty() and not loadouts[0].reaction.is_empty())
	step_forward(12)
	advance_playback(10)
	assert(logic_frame == 4 and units[0].hp == 1 and units[2].hp == 1)
	assert(beat_sim.shots == 2 and steps_remaining == 0 and not segment_active)
	reset_round()
	toggle_running()
	advance_playback(3.0)
	assert(logic_frame == 6 and running)
	advance_playback(20.0)
	assert(logic_frame == 46 and running and finished, "Free battle must continue past first shots and even the recorded match result")
	for u in units:
		if u.enabled: assert(OPEN_CELLS.has_point(u.cell))
	validate_duel_presets()
	var report := {"mode": "free_duel", "max_hp": Beat.MAX_HP, "open_cells": 9, "blocked_cells": 55, "participants": PARTICIPANTS,
		"checks": ["four selectable presets match benchmark ids 5/7/3/19 exactly; independent teams; no ultimates; full playback", "only two active bots", "all other cells blocked", "deployment survives reset", "both sides have editable soldier AP and PP", "four-step reaches endpoint4 past the first shots", "continuous playback reaches endpoint46 without puzzle pauses"]}
	var report_file := FileAccess.open("res://reports/small-arena-validation.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	print("SMALL ARENA PASSED: 3x3/1v1, equal editable loadouts, no first-shot stop, continuous playback through endpoint46")

func validate_duel_presets() -> void:
	var benchmark = JSON.parse_string(FileAccess.get_file_as_string("res://reports/duel-strategy-benchmark.json"))
	var candidate_ids := [5, 7, 3, 19]
	for offset in range(candidate_ids.size()):
		var preset_index := SOLDIER_PRESET + 1 + offset
		assert(preset_menus[0].item_count == preset_names().size())
		var pair := preset_loadouts(preset_index)
		assert(pair[0] == benchmark.candidates[candidate_ids[offset]].rules)
		pair[0].active[0][1] = "自己HP≤2"
		assert(pair[1] == benchmark.candidates[candidate_ids[offset]].rules, "Preset members must own separate rules")
		var red_before: Dictionary = loadouts[2].duplicate(true)
		preset_menus[0].item_selected.emit(preset_index)
		assert(loadouts[0] == benchmark.candidates[candidate_ids[offset]].rules and loadouts[2] == red_before)
		preset_menus[1].item_selected.emit(SOLDIER_PRESET + 1 + (offset + 1) % candidate_ids.size())
		assert(preset_menus[0].selected == preset_index)
		assert(units.filter(func(u): return u.enabled and u.hp > 0).size() == 2)
		assert(units[0].cell == DUEL_SPAWNS[0] and units[2].cell == DUEL_SPAWNS[2])
		started = true
		units[0].ult_charge = 100
		assert(not beat_ultimate_available(0))
		step_forward(12)
		advance_playback(10)
		assert(logic_frame == 4 and not segment_active)
	apply_preset(0, SOLDIER_PRESET)
	apply_preset(1, SOLDIER_PRESET)
	print("DUEL PRESETS PASSED: exact benchmark rules, independent teams, no ultimate, complete beat playback")

func capture_puzzle_preview() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/puzzle-preview.png")
	get_tree().quit()
