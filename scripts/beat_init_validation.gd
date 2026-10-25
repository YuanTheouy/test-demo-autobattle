extends RefCounted
const Beat = preload("res://scripts/beat_simulation.gd")

static func fixture(game):
	var source: Array = game.units.duplicate(true)
	for u in source:
		u.hp = Beat.MAX_HP if u.uid in [0, 2] else 0
		u.energy = 100.0
		u.skill_cds = {}
		u.p = Beat.center(Vector2i(2, 3) if u.uid == 0 else Vector2i(5, 4))
	var sim = Beat.new()
	sim.reset(source, [{"active": [], "reaction": []}, {"active": [], "reaction": []}, {"active": [], "reaction": []}, {"active": [], "reaction": []}], [])
	return sim

static func run(game) -> Dictionary:
	var checks: Array = []
	var sim = fixture(game)
	sim.loadouts[0].active = [["站稳", "无", "无"], ["接敌", "无", "无"]]
	for step in range(3):
		sim.tick()
		assert(sim.units[0].pose == "站稳" and sim.units[0].cell == Vector2i(2, 3))
		assert(sim.units[0].frame_triggers == 1 and sim.activations.get("0:站稳", 0) == step + 1)
	checks.append("standing while already standing consumes one beat and wins Loop priority every time")

	sim = fixture(game)
	sim.loadouts[0].init = [["站稳", "无", "无"], ["站稳", "无", "无"], ["向右移动", "无", "无"]]
	sim.loadouts[0].active = [["站稳", "无", "无"]]
	var initial: Array = sim.units.duplicate(true)
	sim.preview_segment()
	assert(sim.units == initial and sim.units[0].init_index == 0 and sim.activations.is_empty())
	for endpoint in range(1, 5):
		sim.tick()
		assert(sim.units[0].init_index == mini(endpoint, 2) + (1 if endpoint == 4 else 0))
		assert(sim.units[0].frame_triggers <= 1 and sim.units[0].rule_kind == "init")
	assert(sim.units[0].cell == Vector2i(3, 3) and sim.activations.get("0:向右移动", 0) == 1)
	sim.tick()
	assert(sim.units[0].rule_kind == "active" and sim.units[0].init_index == 3 and sim.units[0].pose == "站稳")
	var rules: Array = sim.loadouts.duplicate(true)
	sim.reset(sim.units, rules, [])
	assert(sim.units[0].init_index == 0 and not sim.units[0].init_active)
	sim.tick()
	assert(sim.units[0].init_index == 1 and sim.units[0].rule_kind == "init")
	checks.append("two standing commands then full two-beat move; no early commit, no transition gap, reset restarts sequence")

	sim = fixture(game)
	sim.loadouts[0].init = [["普通攻击", "无", "无"], ["站稳", "无", "无"]]
	sim.loadouts[0].active = [["站稳", "无", "无"]]
	for endpoint in range(1, 4):
		sim.tick()
		assert(sim.units[0].init_index == (1 if endpoint == 3 else 0))
	assert(sim.shots == 1 and sim.units[2].hp == Beat.MAX_HP - 1)
	sim.tick()
	assert(sim.units[0].init_index == 2)
	sim.tick()
	assert(sim.units[0].rule_kind == "active")
	checks.append("Init attack waits for aiming, release and recovery; next command never starts on its completion beat")

	sim = fixture(game)
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.UP
	sim.loadouts[0].init = [["向右移动", "无", "无"]]
	sim.tick()
	assert(sim.units[0].phase == "转向站立" and sim.units[0].init_index == 0)
	sim.tick()
	assert(sim.units[0].init_index == 0)
	sim.tick()
	assert(sim.units[0].init_index == 1 and sim.units[0].cell == Vector2i(3, 3))
	sim = fixture(game)
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.RIGHT
	sim.loadouts[0].init = [["普通攻击", "无", "无"]]
	sim.tick()
	assert(sim.units[0].phase == "射击站立" and sim.units[0].init_index == 0)
	for step in range(3): sim.tick()
	assert(sim.units[0].init_index == 1 and sim.shots == 1)
	checks.append("automatic turn-standing and shooting-standing are preparation, not completed Init commands")

	sim = fixture(game)
	sim.loadouts[0].init = [["普通攻击", "无", "无"], ["站稳", "无", "无"]]
	sim.units[0].skill_cds["点射"] = 2 * Beat.SECONDS
	for step in range(2):
		sim.tick()
		assert(sim.units[0].init_index == 0 and sim.units[0].frame_triggers == 0)
	sim.tick()
	assert(sim.units[0].mode == "释放硬直" and sim.units[0].init_index == 0)
	checks.append("unavailable Init item waits without falling through to later commands or Loop")

	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.loadouts[0].init = [["落岩", "无", "无"]]
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	sim.tick()
	assert(sim.units[0].mode == "前摇")
	sim.strikes.append({"cells": [sim.units[0].cell], "at": 2, "team": 1, "source": 2, "skill": "点射", "damage": 1})
	sim.tick()
	assert(sim.units[0].phase == "侧闪跨格" and sim.units[0].init_index == 0 and not sim.units[0].init_active)
	assert(sim.units[0].energy == 80 and sim.units[0].hp == Beat.MAX_HP)
	sim.loadouts[0].reaction.clear()
	sim.tick()
	assert(sim.units[0].rule_kind == "init" and sim.units[0].mode == "前摇" and sim.units[0].init_index == 0)
	checks.append("PP can interrupt Init; windup refund preserved, canceled command retries instead of being skipped")

	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.loadouts[0].init = [["向右移动", "无", "无"]]
	sim.loadouts[2].init = [["向左移动", "无", "无"]]
	for step in range(2): sim.tick()
	assert(sim.units[0].mode == "碰撞" and sim.units[0].init_index == 0 and not sim.units[0].init_active)
	sim.tick()
	assert(sim.units[0].phase == "弹回" and sim.units[0].init_index == 0)
	checks.append("collision and bounce do not falsely complete Init movement")

	sim = fixture(game)
	sim.loadouts[0].init = [["站稳", "无", "无"]]
	sim.strikes.append({"cells": [sim.units[0].cell], "at": 1, "team": 1, "source": 2, "skill": "点射", "damage": Beat.MAX_HP})
	sim.tick()
	assert(sim.units[0].hp == 0 and sim.units[0].init_index == 0)
	checks.append("death prevents advancing the sequence")

	sim = fixture(game)
	sim.loadouts[0].init = [["站稳", "无", "无"], ["接敌", "无", "无"]]
	sim.loadouts[2].init = [["普通攻击", "无", "无"], ["站稳", "无", "无"]]
	sim.loadouts[0].active = [["远敌", "无", "无"]]
	sim.loadouts[2].active = [["普通攻击", "无", "无"]]
	var reversed = Beat.new()
	reversed.reset(sim.units, sim.loadouts.duplicate(true), [])
	reversed.decision_order = [3, 2, 1, 0]
	for step in range(20):
		sim.tick()
		reversed.tick()
		assert(sim.units == reversed.units and sim.strikes == reversed.strikes)
	checks.append("different Init lengths advance independently; reversed bot update order produces identical settled state")

	validate_editor(game)
	checks.append("Init/Loop UI selection, actual menu callbacks, reorder/delete, per-bot isolation, edit preservation and animated single-step")
	var coverage := dodge_coverage(game)
	var report := {"checks": checks, "dodge_coverage": coverage}
	var file := FileAccess.open("res://reports/beat-init-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("INIT PASSED: sequential full actions, one-beat standing, PP retry, collision/death, reset, editor and phase coverage")
	return report

static func validate_editor(game) -> void:
	game.apply_preset(0, game.SOLDIER_PRESET)
	game.choose_editor_unit(0)
	var original_loop: Dictionary = game.loadouts[0].duplicate(true)
	game.set_editor_zone("init")
	game.editor_rows[0].menus[0].item_selected.emit(1) # 站立
	game.editor_rows[1].menus[0].item_selected.emit(1)
	game.editor_rows[2].menus[0].item_selected.emit(2) # 接敌
	assert(game.loadouts[0].init == [["站稳", "无", "无"], ["站稳", "无", "无"], ["接敌", "无", "无"]])
	assert(game.loadouts[0].active == original_loop.active and game.loadouts[1].init.is_empty())
	assert(game.editor_rows[0].menus[1].disabled and game.editor_rows[0].menus[0].text == "站立")
	game.move_editor_row(2, -1)
	assert(game.loadouts[0].init[1][0] == "接敌")
	game.edit_rule_cell(1, 0, "留空")
	assert(game.loadouts[0].init.size() == 2)
	game.set_editor_zone("loop")
	game.edit_rule_cell(0, 1, "敌人处于移动姿态")
	assert(game.loadouts[0].init.size() == 2)
	game.set_editor_zone("init")
	game.step_forward(1)
	game.advance_playback(Beat.SECONDS / game.playback_rate() / 2)
	assert(game.units[0].init_index == 0)
	game.advance_playback(Beat.SECONDS / game.playback_rate() / 2)
	assert(game.units[0].init_index == 1 and game.logic_frame == 1)
	game.reset_round()
	assert(game.units[0].init_index == 0 and game.loadouts[0].init.size() == 2)
	game.clear_editor_zone()
	assert(game.loadouts[0].init.is_empty() and not game.loadouts[0].active.is_empty())
	game.edit_rule_cell(0, 0, "站立")
	game.set_editor_zone("loop")
	game.clear_editor_zone()
	assert(game.loadouts[0].init.size() == 1 and game.loadouts[0].active.is_empty() and game.loadouts[0].reaction.is_empty())
	game.apply_preset(0, game.SOLDIER_PRESET)

static func dodge_coverage(game) -> Dictionary:
	# Same fixed shooter and Loop, only the number of opening standing beats changes.
	var source: Array = fixture(game).units
	for u in source: u.p = Beat.center(Vector2i(5, 5))
	var coverage: Array = []
	var solved: Dictionary = {}
	for variant in range(24):
		var delay: int = variant % 8
		var prefix: String = ["", "接敌", "远敌"][variant / 8]
		var safe := 0
		for x in range(5, 8):
			for y in range(5, 8):
				for rx in range(5, 8):
					for ry in range(5, 8):
						if Vector2i(x, y) == Vector2i(rx, ry): continue
						var sim = Beat.new()
						var init: Array = []
						if not prefix.is_empty(): init.append([prefix, "无", "无"])
						for step in range(delay): init.append(["站稳", "无", "无"])
						var blue := {"init": init, "active": [["远敌", "敌人处于站立姿态", "无"], ["接敌", "无", "无"]], "reaction": []}
						var spawn: Array = source.duplicate(true)
						spawn[0].p = Beat.center(Vector2i(x, y))
						spawn[2].p = Beat.center(Vector2i(rx, ry))
						sim.reset(spawn, [blue, {"active": [], "reaction": []}, {"active": [["普通攻击", "无", "无"]], "reaction": []}, {"active": [], "reaction": []}], [Rect2(0, 0, 640, 400), Rect2(0, 400, 400, 240)])
						for step in range(240):
							sim.tick()
							if sim.units[0].hp < Beat.MAX_HP: break
						if sim.units[0].hp == Beat.MAX_HP:
							assert(sim.shots == 30)
							safe += 1
							var key := "%s/%s" % [Beat.name_of(Vector2i(x, y)), Beat.name_of(Vector2i(rx, ry))]
							if not solved.has(key): solved[key] = {"init": init, "blue": Beat.name_of(Vector2i(x, y)), "red": Beat.name_of(Vector2i(rx, ry))}
		coverage.append({"first_move": prefix, "standing_beats": delay, "unhurt_240_beats": safe, "spawn_pairs": 72})
	assert(coverage[0].unhurt_240_beats == 30)
	for delay in range(1, 8): assert(coverage[delay].unhurt_240_beats == 0)
	print("INIT DODGE COVERAGE: no Init 30/72; best per-spawn among 24 Init sequences ", solved.size(), "/72")
	return {"loop": "远敌〔敌人站立〕→接敌", "opponent": "stationary unconditional lob", "rows": coverage, "solved_spawn_pairs": solved.size(), "solutions": solved.values(),
		"interpretation": "Only these 24 Init sequences and this fixed shooter/Loop were tested. Opening standing alone cannot improve flawless coverage: first lob lands at beat2 before delayed movement finishes."}
