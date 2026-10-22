extends RefCounted
const Beat = preload("res://scripts/beat_simulation.gd")
const Cases = preload("res://scripts/beat_validation.gd")

static func fixture(game, predict := true):
	var sim = Cases.fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[2].pose = "移动"
	sim.units[2].trend = Vector2i.RIGHT
	sim.loadouts[0].active = [["普通攻击", "敌人处于移动姿态", "沿移动方向预判1格"], ["普通攻击", "无", "无"]] if predict else [["普通攻击", "无", "无"]]
	sim.loadouts[2].active = [["向右移动", "无", "无"]]
	return sim

static func run(game) -> Array:
	var checks: Array = []
	for predict in [false, true]:
		var sim = fixture(game, predict)
		sim.tick()
		assert(sim.units[0].lock_cells == [Vector2i(5 if predict else 4, 3)])
		assert(sim.units[0].energy == 85 and sim.shots == 0)
		# The very same lock feeds both the telegraph and the actual strike.
		var warnings := preload("res://scripts/beat_telegraph.gd").cells(sim, 0.0)
		assert(warnings.any(func(w): return w.cell == sim.units[0].lock_cells[0]))
		sim.tick()
		assert(sim.units[2].cell == Vector2i(5, 3))
		assert(sim.units[2].hp == (Beat.MAX_HP - 1 if predict else Beat.MAX_HP))
		assert(sim.units[0].skill_cds["点射"] == 6 * Beat.SECONDS and sim.shots == 1)
	checks.append("same two-beat straight movement: current-cell lob misses, one-cell prediction hits; identical cost/CD/timing and visible warning")
	for response in ["站稳", "向上移动", "侧闪"]:
		var sim = fixture(game)
		if response == "侧闪": sim.loadouts[2].reaction = [["侧闪", "无", "无"]]
		else: sim.loadouts[2].active = [[response, "无", "无"]]
		sim.tick()
		assert(sim.units[0].lock_cells == [Vector2i(5, 3)], "Do not read hidden next action, even if target plans to stop or turn")
		sim.tick()
		assert(sim.units[0].lock_cells == [Vector2i(5, 3)] and sim.units[2].hp == Beat.MAX_HP, "No tracking after initial lock")
	checks.append("stopping, turning and PP dodge can defeat the prediction; no lookahead into next_segment or homing")
	for invalid in ["wall", "edge", "range", "standing", "no_direction", "wrong_skill"]:
		var sim = fixture(game)
		match invalid:
			"wall": sim.blocked_cells.append(Vector2i(5, 3))
			"edge": sim.units[0].cell = Vector2i(5, 3); sim.units[2].cell = Vector2i(7, 3)
			"range": sim.units[0].cell = Vector2i(0, 3)
			"standing": sim.units[2].pose = "站稳"; sim.units[2].trend = Vector2i.ZERO
			"no_direction": sim.units[2].trend = Vector2i.ZERO
			"wrong_skill": sim.loadouts[0].active[0][0] = "火矢"
		sim.tick()
		assert(sim.units[0].rule_slot == 1 and sim.units[0].lock_cells == [sim.units[2].cell], "Invalid prediction must fall through without spending an extra action")
		assert(sim.units[0].energy == 85 and sim.units[0].frame_triggers == 1)
	checks.append("wall/outside/range/nonmoving/no-direction/unsupported-skill skip prediction and select ordinary fallback")
	var swapped = fixture(game)
	swapped.loadouts[0].active[0] = ["普通攻击", "沿移动方向预判1格", "敌人处于移动姿态"]
	swapped.tick()
	assert(swapped.units[0].lock_cells == [Vector2i(5, 3)])
	var filtered = fixture(game)
	filtered.blocked_cells.append(Vector2i(5, 3))
	filtered.units[3].hp = Beat.MAX_HP
	filtered.units[3].cell = Vector2i(3, 4)
	filtered.units[3].pose = "移动"
	filtered.units[3].trend = Vector2i.RIGHT
	filtered.tick()
	assert(filtered.units[0].target == 3 and filtered.units[0].lock_cells == [Vector2i(4, 4)])
	checks.append("modifier works in either condition column; invalid nearest target does not hide another valid moving target")
	var sim = fixture(game)
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.UP
	sim.tick()
	assert(sim.units[0].phase == "射击站立" and sim.units[0].energy == 100 and sim.units[0].lock_cells.is_empty())
	checks.append("prediction preserves mandatory standing preparation")
	game.apply_preset(0, game.SOLDIER_PRESET + 5)
	game.choose_editor_unit(0)
	game.rebuild_editor()
	assert(game.loadouts[0].active[0] == ["普通攻击", "敌人处于移动姿态", "沿移动方向预判1格"])
	for column in [1, 2]:
		var menu: OptionButton = game.editor_rows[0].menus[column]
		assert(menu.get_item_text(menu.selected) == game.loadouts[0].active[0][column])
	checks.append("prediction demo preset and both condition columns survive editor rebuilding")
	assert(game.SIMPLE_CONDITIONS.size() == 7)
	for column in [1, 2]:
		var menu: OptionButton = game.editor_rows[0].menus[column]
		assert(menu.item_count == 7)
		for item in range(menu.item_count): assert(menu.get_item_text(item) == game.SIMPLE_CONDITIONS[item])
	game.edit_rule_cell(0, 0, "接敌")
	assert(game.loadouts[0].active[0] == ["接敌", "敌人处于移动姿态", "无"])
	for column in [1, 2]:
		var menu: OptionButton = game.editor_rows[0].menus[column]
		assert(menu.item_count == 6)
		for item in range(menu.item_count): assert(menu.get_item_text(item) != "沿移动方向预判1格")
	game.edit_rule_cell(0, 1, "敌人处于站立姿态")
	game.rebuild_editor()
	assert(game.loadouts[0].active[0][1] == "敌人处于站立姿态")
	assert(game.conditions_for_skill("站稳") == ["无", "自己HP≤2"])
	assert(game.conditions_for_skill("回春") == ["无", "自己HP≤2"])
	var standing = fixture(game)
	assert(not standing.condition(standing.units[0], 2, "敌人处于站立姿态", standing.units))
	standing.units[2].pose = "站稳"
	standing.units[2].trend = Vector2i.ZERO
	assert(standing.condition(standing.units[0], 2, "敌人处于站立姿态", standing.units))
	standing.units[2].mode = "后摇"
	assert(not standing.condition(standing.units[0], 2, "敌人处于站立姿态", standing.units))
	checks.append("seven-condition menu; skill-specific subsets; switching skills preserves valid filters and clears unsupported prediction; standing filter excludes recovery")
	game.apply_preset(0, game.SOLDIER_PRESET + 5)
	game.choose_editor_unit(0)
	for row in game.editor_rows:
		var skills: OptionButton = row.menus[0]
		assert(skills.item_count == game.PLAYER_SKILLS.size())
		for item in range(skills.item_count): assert(skills.get_item_text(item) == game.skill_label(game.PLAYER_SKILLS[item]))
	for picker in game.preset_menus:
		assert(picker.item_count == game.PLAYER_PRESETS.size())
		for item in range(picker.item_count): assert(picker.get_item_id(item) in game.PLAYER_PRESETS)
	var rows_before: Array = game.loadouts[0].duplicate(true).active
	game.edit_rule_cell(0, 0, "火矢")
	assert(game.loadouts[0].active == rows_before and Beat.DAMAGE.has("火矢"))
	game.editor_rows[0].menus[0].item_selected.emit(1) # Visible label is 吊射, stored rule is 普通攻击.
	assert(game.loadouts[0].active[0][0] == "普通攻击")
	game.editor_rows[3].menus[0].item_selected.emit(4)
	assert(game.loadouts[0].reaction == [["侧闪", "无", "无"]])
	game.editor_rows[3].menus[0].item_selected.emit(0)
	assert(game.loadouts[0].reaction.is_empty())
	checks.append("player skill menus expose only lob/approach/retreat/dodge plus empty; legacy presets hidden; visible lob label and AP/PP add/delete work; hidden skills remain implemented")
	print("PREDICTION PASSED: straight-move hit, stop/turn/dodge counterplay, fixed telegraph, invalid fallback and editor persistence")
	return checks
