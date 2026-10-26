extends "res://scripts/beat_battle.gd"
## A separate 1v1 workbench. The full 2v2 scene remains available unchanged.
const OPEN_CELLS := Rect2i(5, 5, 3, 3)
const DUEL_SPAWNS := [Vector2i(5, 6), Vector2i(5, 5), Vector2i(7, 6), Vector2i(7, 7)]
const PARTICIPANTS := [0, 2]
const WATCHABLE_PRESETS := [14, 10]
const WATCHABLE_SPAWNS := [Vector2i(5, 5), Vector2i(7, 7)]

func _ready() -> void:
	if not get_tree().has_meta("dual_track_entry_consumed") and ("--dual-track-demo" in OS.get_cmdline_user_args() or "--dual-track-test" in OS.get_cmdline_user_args() or "--dual-track-preview" in OS.get_cmdline_user_args()):
		get_tree().set_meta("dual_track_entry_consumed", true)
		hide()
		set_process(false)
		set_physics_process(false)
		get_tree().change_scene_to_file.call_deferred("res://dual_track_arena.tscn")
		return
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
		load_prediction_demo()
	if "--init-demo" in OS.get_cmdline_user_args() or "--init-demo-test" in OS.get_cmdline_user_args(): load_init_demo()
	var demo_button := MenuButton.new()
	demo_button.text = "载入示范"
	demo_button.custom_minimum_size.y = 34
	demo_button.add_theme_font_override("font", font)
	add_child(demo_button)
	demo_button.position = Vector2(650, 738)
	demo_button.get_popup().add_item("双轨短交锋：只改一格", 2)
	demo_button.get_popup().add_item("Init走位躲弹", 0)
	demo_button.get_popup().add_item("旧：预判吊射", 1)
	demo_button.get_popup().id_pressed.connect(func(id: int):
		if id == 2: get_tree().change_scene_to_file("res://dual_track_arena.tscn")
		elif id == 0: load_init_demo()
		else: load_prediction_demo()
	)
	demo_button.tooltip_text = "载入后暂停；空格观看、N逐拍、R重播。走位示范仅用普通移动和站立，双方PP为空。"
	choose_editor_unit(0)
	refresh_ui()
	if "--init-demo-test" in OS.get_cmdline_user_args():
		validate_init_demo()
		get_tree().quit()
		return
	if "--watchable-preview" in OS.get_cmdline_user_args():
		set_process(false)
		set_physics_process(false)
		capture_watchable_preview.call_deferred()
	if "--small-arena-test" in OS.get_cmdline_user_args() or "--puzzle-test" in OS.get_cmdline_user_args():
		run_small_arena_checks()
		get_tree().quit()
	if "--small-arena-preview" in OS.get_cmdline_user_args() or "--puzzle-preview" in OS.get_cmdline_user_args():
		set_process(false)
		set_physics_process(false)
		capture_puzzle_preview.call_deferred()

func load_prediction_demo() -> void:
	blue_attacks = false
	deployment_cells = DUEL_SPAWNS.duplicate()
	deployment_cells[0] = WATCHABLE_SPAWNS[0]
	deployment_cells[2] = WATCHABLE_SPAWNS[1]
	apply_preset(0, WATCHABLE_PRESETS[0])
	apply_preset(1, WATCHABLE_PRESETS[1])
	choose_editor_unit(0)
	set_editor_zone("loop")

func load_init_demo() -> void:
	blue_attacks = false
	deployment_cells = DUEL_SPAWNS.duplicate()
	deployment_cells[0] = Vector2i(5, 5) # F6
	deployment_cells[2] = Vector2i(5, 6) # F7
	apply_preset(0, SOLDIER_PRESET)
	apply_preset(1, SOLDIER_PRESET)
	loadouts[0] = {
		"init": [["远敌", "无", "无"], ["站稳", "无", "无"], ["站稳", "无", "无"], ["站稳", "无", "无"]],
		"active": [["远敌", "敌人处于站立姿态", "无"], ["接敌", "无", "无"]], "reaction": []
	}
	loadouts[2] = {"init": [], "active": [["普通攻击", "无", "无"]], "reaction": []}
	choose_editor_unit(0)
	set_editor_zone("init")
	reset_round()

func validate_init_demo() -> void:
	assert(not running and not started and editor_zone == "init" and editor_unit == 0)
	assert(units[0].cell == Vector2i(5, 5) and units[2].cell == Vector2i(5, 6))
	var saved: Array = loadouts.duplicate(true)
	for endpoint in range(1, 241):
		step_forward(1)
		advance_playback(Beat.SECONDS / playback_rate())
		assert(logic_frame == endpoint and not segment_active and not running)
		assert(units[0].hp == Beat.MAX_HP and units[2].hp == Beat.MAX_HP)
		assert(loadouts[0].reaction.is_empty() and loadouts[2].reaction.is_empty())
		if endpoint <= 5: assert(units[0].init_index == maxi(0, endpoint - 1))
	assert(beat_sim.shots == 30 and units[0].init_index == 4)
	reset_round()
	assert(loadouts == saved and units[0].init_index == 0 and logic_frame == 0 and not running)
	loadouts[0].init = []
	reset_round()
	for endpoint in range(10): simulate(Beat.SECONDS, false)
	assert(units[0].hp < Beat.MAX_HP)
	load_init_demo()
	var report := {"blue": "F6", "red": "F7", "blue_profile": loadouts[0], "red_profile": loadouts[2],
		"animated_beats": 240, "incoming_shots": 30, "blue_hp": Beat.MAX_HP,
		"checks": ["starts paused on blue Init", "full single-step playback preserves HP for 240 beats", "Init completes at endpoint5", "reset preserves setup and restarts Init", "same Loop without Init takes damage by beat10"]}
	var file := FileAccess.open("res://reports/init-demo-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("INIT DEMO PASSED: F6/F7, 240 animated beats, 30 shots, no damage; no-Init control hit by beat10; replay resets correctly")

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
	assert(units.filter(func(u): return u.enabled and u.hp == Beat.MAX_HP).size() == 2)
	assert(not can_deploy(0, Vector2i(4, 6)) and can_deploy(0, Vector2i(5, 5)))
	assert(place_unit(0, Vector2i(5, 5)))
	reset_round()
	assert(units[0].cell == Vector2i(5, 5))
	deployment_cells = DUEL_SPAWNS.duplicate()
	reset_round()
	assert(loadouts[0] == loadouts[2] and not loadouts[0].active.is_empty() and loadouts[0].reaction.is_empty())
	step_forward(12)
	advance_playback(10)
	assert(logic_frame == 4 and units[0].hp == Beat.MAX_HP - 1 and units[2].hp == Beat.MAX_HP - 1)
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
	validate_watchable_demo()
	var report := {"mode": "free_duel", "max_hp": Beat.MAX_HP, "open_cells": 9, "blocked_cells": 55, "participants": PARTICIPANTS,
		"checks": ["four selectable AP presets match original priorities; no dodge; independent teams; no ultimates; full playback", "selected demo: 3HP/no dodge, actual playback settles 19 beats with prediction hit and replayable setup", "only two active bots", "all other cells blocked", "deployment survives reset", "both sides have editable soldier AP and PP", "four-step reaches endpoint4 past the first shots", "continuous playback reaches endpoint46 without puzzle pauses"]}
	var report_file := FileAccess.open("res://reports/small-arena-validation.json", FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report, "\t"))
	print("SMALL ARENA PASSED: 3x3/1v1, equal editable loadouts, no first-shot stop, continuous playback through endpoint46")

func validate_watchable_demo() -> void:
	load_prediction_demo()
	assert(units[0].cell == WATCHABLE_SPAWNS[0] and units[2].cell == WATCHABLE_SPAWNS[1])
	assert(team_presets == WATCHABLE_PRESETS)
	var observed: Array = []
	for endpoint in range(1, 20):
		step_forward(1)
		advance_playback(Beat.SECONDS / playback_rate())
		assert(logic_frame == endpoint and not segment_active and not running)
		if endpoint == 2: assert(units[0].hp == Beat.MAX_HP - 1 and units[2].hp == Beat.MAX_HP - 1)
		assert(loadouts[0].reaction.is_empty() and loadouts[2].reaction.is_empty())
		for uid in PARTICIPANTS: assert(units[uid].phase != "侧闪跨格" and not units[uid].skill_cds.has("侧闪"))
		if endpoint == 10:
			assert(units[0].hp == 2 and units[2].hp == 1 and units[0].lock_cells == [Vector2i(7, 6)])
			observed.append(endpoint)
		if endpoint == 12: assert(units[0].hp == 1 and units[2].hp == 1)
	assert(observed == [10] and finished and beat_sim.winner == 0 and units[0].hp == 1 and units[2].hp == 0)
	assert(beat_sim.shots == 5)
	reset_round()
	assert(team_presets == WATCHABLE_PRESETS and units[0].cell == WATCHABLE_SPAWNS[0] and units[2].cell == WATCHABLE_SPAWNS[1])
	print("WATCHABLE DEMO PASSED: full animated 19-beat replay, 3HP/no dodge and prediction hit; reset preserves setup")

func validate_duel_presets() -> void:
	var benchmark = JSON.parse_string(FileAccess.get_file_as_string("res://reports/duel-strategy-benchmark.json"))
	var candidate_ids := [5, 7, 3, 19]
	for offset in range(candidate_ids.size()):
		var preset_index := SOLDIER_PRESET + 1 + offset
		assert(preset_menus[0].item_count == PLAYER_PRESETS.size())
		var pair := preset_loadouts(preset_index)
		assert(pair[0] == {"active": benchmark.candidates[candidate_ids[offset]].rules.active, "reaction": []})
		pair[0].active[0][1] = "自己HP≤2"
		assert(pair[1] == {"active": benchmark.candidates[candidate_ids[offset]].rules.active, "reaction": []}, "Preset members must own separate rules")
		var red_before: Dictionary = loadouts[2].duplicate(true)
		preset_menus[0].item_selected.emit(preset_menus[0].get_item_index(preset_index))
		assert(loadouts[0] == {"init": [], "active": benchmark.candidates[candidate_ids[offset]].rules.active, "reaction": []} and loadouts[2] == red_before)
		preset_menus[1].item_selected.emit(preset_menus[1].get_item_index(SOLDIER_PRESET + 1 + (offset + 1) % candidate_ids.size()))
		assert(preset_menus[0].get_selected_id() == preset_index)
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
	print("DUEL PRESETS PASSED: original AP priorities without dodge, independent teams, no ultimate, complete beat playback")

func capture_puzzle_preview() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/puzzle-preview.png")
	get_tree().quit()

func capture_watchable_preview() -> void:
	load_prediction_demo()
	for endpoint in range(1, 20):
		step_forward(1)
		for frame in range(20):
			advance_playback(Beat.SECONDS / playback_rate() / 20.0)
			await RenderingServer.frame_post_draw
		if endpoint in [10, 13, 18, 19]:
			get_viewport().get_texture().get_image().save_png("res://reports/duel-demo-%02d.png" % endpoint)
	get_tree().quit()
