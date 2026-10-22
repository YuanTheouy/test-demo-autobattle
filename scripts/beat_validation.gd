extends RefCounted

const Beat = preload("res://scripts/beat_simulation.gd")

static func fixture(game):
	game.reset_round()
	var source: Array = game.units.duplicate(true)
	var rules: Array = []
	for u in source:
		u.hp = Beat.MAX_HP if u.uid in [0, 2] else 0
		u.attack = u.team == 0
		u.p = Beat.center(Vector2i(2, 3) if u.uid == 0 else Vector2i(5, 4))
		rules.append({"active": [], "reaction": []})
	var sim = Beat.new()
	sim.reset(source, rules, [])
	return sim

static func ap(sim, uid: int, skill: String) -> void:
	sim.loadouts[uid].active = [[skill, "无", "无"]]

static func warning(sim, cell: Vector2i, due: int) -> void:
	sim.strikes.append({"cells": [cell], "at": due, "team": 1, "source": 2, "skill": "落岩", "damage": sim.damage_of("落岩")})

static func run(game) -> void:
	assert(game.speed == 1.0 and game.BASE_PLAYBACK_RATE == 0.5, "Default 1x must use the previous half-speed baseline")
	var report := {"beat_seconds": Beat.SECONDS, "default_real_beat_seconds": Beat.SECONDS / game.BASE_PLAYBACK_RATE, "checks": [], "symmetry": [], "matches": []}
	validate_presentation(game)
	report.checks.append("continuous presentation: movement/settling/collision/dodge, exact endpoints, no snapshot mutation, pause/step, frame-rate independence")
	var sim = fixture(game)
	ap(sim, 0, "向左移动")
	var start: Vector2i = sim.units[0].cell
	sim.tick()
	assert(sim.units[0].cell == start and sim.units[0].pose == "移动" and sim.units[0].trend == Vector2i.LEFT)
	sim.tick()
	assert(sim.units[0].cell == start + Vector2i.LEFT and sim.units[0].pose == "移动")
	ap(sim, 0, "站稳")
	sim.tick()
	assert(sim.units[0].cell == start + Vector2i.LEFT and sim.units[0].pose == "站稳" and sim.units[0].trend == Vector2i.ZERO)
	assert(sim.units[0].frame_triggers == 1)
	report.checks.append("T0 standing / T1 committed move / T2 adjacent cell / T3 explicit standing")

	sim = fixture(game)
	ap(sim, 0, "向右移动")
	for tick in range(4):
		sim.tick()
		assert(sim.units[0].cell == Vector2i(2 + (tick + 1) / 2, 3), "Every ordinary crossing consumes two beats, including consecutive moves")
	assert(sim.units[0].cell == Vector2i(4, 3))
	ap(sim, 0, "向上移动")
	sim.tick()
	assert(sim.units[0].cell == Vector2i(4, 3) and sim.units[0].pose == "站稳" and sim.units[0].phase == "转向站立")
	sim.tick()
	assert(sim.units[0].cell == Vector2i(4, 3) and sim.units[0].mode == "移动硬直")
	sim.tick()
	assert(sim.units[0].cell == Vector2i(4, 2))
	report.checks.append("ordinary crossing two beats; same direction continues; turning first consumes a separate standing beat")

	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.loadouts[0].active = [["站稳", "移动姿态", "无"], ["向右移动", "无", "无"]]
	sim.tick()
	sim.tick()
	assert(sim.units[0].cell == Vector2i(3, 3), "Committed move must cross before AP standing can take over")
	sim.tick()
	assert(sim.units[0].pose == "站稳")

	sim = fixture(game)
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.RIGHT
	sim.units[2].cell = Vector2i(4, 3)
	sim.loadouts[0].active = [["蓄能贯穿", "无", "无"], ["站稳", "无", "无"]]
	sim.tick()
	assert(sim.units[0].trace_ap[0] == "需要站稳" and sim.units[0].pose == "站稳" and sim.units[0].energy == 100)
	assert(sim.units[0].mode.is_empty() and sim.units[0].frame_triggers == 1)
	sim.tick()
	assert(sim.units[0].mode == "前摇" and sim.units[0].left == 2 and sim.units[0].energy == 55)
	report.checks.append("high skills require standing; standing cannot cast on the same beat")

	sim = fixture(game)
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.RIGHT
	sim.units[2].cell = Vector2i(4, 3)
	ap(sim, 0, "火矢")
	sim.tick()
	assert(sim.units[0].cell == Vector2i(2, 3) and sim.units[0].pose == "移动", "Low-tier magic retains mobile pose but never also moves")
	sim.tick()
	assert(sim.units[0].mode == "后摇" and sim.shots == 1)
	sim.tick()
	assert(sim.units[2].hp == 4 and sim.units[0].frame_triggers == 0)
	report.checks.append("low-tier magic allowed while mobile; ordinary gun has its own standing requirement; no AP on recovery completion beat")

	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	sim.start_attack(sim.units[0], 2, "蓄能贯穿", sim.units[2].cell)
	warning(sim, sim.units[0].cell, 1)
	sim.tick()
	assert(sim.units[0].cell != Vector2i(2, 3) and sim.units[0].energy == 80)
	assert(sim.units[0].hp == 5 and sim.units[0].mode.is_empty() and sim.units[0].frame_triggers == 1)
	assert(not sim.units[0].skill_cds.has("蓄能贯穿"))
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	sim.start_attack(sim.units[0], 2, "落岩", sim.units[2].cell)
	sim.units[0].mode = "释放硬直"
	sim.units[0].left = 1
	warning(sim, sim.units[0].cell, 1)
	sim.tick()
	assert(sim.units[0].cell == Vector2i(2, 3) and sim.units[0].hp == 3 and sim.units[0].energy == 75)
	warning(sim, sim.units[0].cell, 2)
	sim.tick()
	assert(sim.units[0].cell != Vector2i(2, 3) and sim.units[0].energy == 55)
	assert(sim.units[0].cooldown == 0 and sim.units[0].skill_cds["落岩"] > 0)
	report.checks.append("windup dodge refunds; release lock prevents dodge; recovery cancellation keeps cooldown and cost")

	sim = fixture(game)
	sim.units[0].cell = Vector2i(2, 3)
	sim.units[2].cell = Vector2i(4, 3)
	ap(sim, 0, "向右移动")
	ap(sim, 2, "向左移动")
	sim.tick()
	sim.tick()
	assert(sim.units[0].cell == Vector2i(3, 3) and sim.units[2].cell == Vector2i(3, 3))
	assert(sim.units[0].hp == 4 and sim.units[2].hp == 4 and sim.units[0].mode == "碰撞")
	sim.units[1].hp = Beat.MAX_HP
	sim.units[1].cell = Vector2i(1, 3)
	sim.units[1].pose = "移动"
	sim.units[1].trend = Vector2i.RIGHT
	ap(sim, 1, "向右移动")
	sim.units[1].mode = "移动硬直"
	sim.units[1].left = 1
	sim.units[1].move_total = 2
	sim.units[1].move_origin = Vector2i(1, 3)
	sim.units[1].move_target = Vector2i(2, 3)
	sim.units[1].action_goal = Beat.center(Vector2i(2, 3))
	sim.tick()
	assert(sim.units[0].cell == Vector2i(2, 3) and sim.units[2].cell == Vector2i(4, 3))
	assert(sim.units[0].hp == 4 and sim.units[0].frame_triggers == 0)
	assert(sim.units[1].cell == Vector2i(1, 3), "Collision return cell stays reserved")
	report.checks.append("simultaneous hostile collision once for 1HP, shared collision cell, next-beat forced return, reserved origins")

	for friendly in [true, false]:
		sim = fixture(game)
		sim.units[0].cell = Vector2i(2, 3)
		sim.units[2].cell = Vector2i(3, 3)
		if friendly: sim.units[2].team = 0
		ap(sim, 0, "向右移动")
		ap(sim, 2, "向左移动")
		sim.tick()
		sim.tick()
		assert(sim.units[0].cell == Vector2i(2, 3) and sim.units[2].cell == Vector2i(3, 3), "Head-on swaps collide on the edge")
		assert(sim.units[0].hp == (5 if friendly else 4) and sim.units[0].mode == "碰撞")
	report.checks.append("head-on exchange cannot cross bodies; friendly collision has no damage")
	sim = fixture(game)
	sim.units[0].cell = Vector2i(2, 3)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[1].hp = Beat.MAX_HP
	sim.units[1].cell = Vector2i(3, 2)
	ap(sim, 0, "向右移动")
	ap(sim, 2, "向左移动")
	ap(sim, 1, "向下移动")
	sim.tick()
	sim.tick()
	for uid in [0, 1, 2]: assert(sim.units[uid].hp == 4 and sim.units[uid].cell == Vector2i(3, 3))
	sim.tick()
	assert(sim.units[0].cell == Vector2i(2, 3) and sim.units[1].cell == Vector2i(3, 2) and sim.units[2].cell == Vector2i(4, 3))
	report.checks.append("three-way collision is one 1HP event per bot, not pairwise multiplied damage")

	for reverse in [false, true]:
		sim = fixture(game)
		var first := {"cells": [sim.units[2].cell], "at": 1, "team": 0, "source": 0, "skill": "标记弹", "damage": sim.damage_of("标记弹")}
		var second := {"cells": [sim.units[2].cell], "at": 1, "team": 0, "source": 1, "skill": "强力射击", "damage": sim.damage_of("强力射击")}
		sim.strikes.assign([second, first] if reverse else [first, second])
		sim.tick()
		assert(sim.units[2].hp == 2 and sim.units[2].marked == 5, "Same-beat marking becomes active after all damage is collected")
	report.checks.append("same-beat status/damage independent of projectile iteration order")

	sim = fixture(game)
	sim.units[0].ult_charge = 100.0
	sim.units[2].cell = Vector2i(4, 3)
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	sim.manual[0] = sim.units[2].cell
	sim.tick()
	assert(sim.units[0].energy == 30 and sim.units[0].mode == "前摇" and sim.units[0].ult_charge == 0)
	warning(sim, sim.units[0].cell, 2)
	sim.tick()
	assert(sim.units[0].energy == 80 and sim.units[0].ult_charge == 100 and not sim.manual.has(0))
	report.checks.append("commander ultimate starts on a beat and refunds charge/energy on windup dodge")

	for skill in ["普通攻击", "落岩", "烈焰爆破"]:
		for count in [1, 2]:
			sim = fixture(game)
			for uid in range(4):
				var u: Dictionary = sim.units[uid]
				u.hp = Beat.MAX_HP if count == 2 or uid in [0, 2] else 0
				u.cell = Vector2i(1, 2 if uid % 2 == 0 else 5) if uid < 2 else Vector2i(6, 5 if uid % 2 == 0 else 2)
				sim.loadouts[uid] = {"active": [["站稳", "移动姿态", "有射位"], [skill, "无", "无"], ["普通攻击", "无", "无"], ["接敌", "无", "无"]], "reaction": [["侧闪", "无", "无"]]}
			var difference := 0.0
			for tick in range(240):
				sim.tick()
				for member in range(count): difference = maxf(difference, absf(sim.units[member].hp - sim.units[member + 2].hp))
				assert(difference == 0, "Mirrored identical strategies must have equal HP every beat")
				if sim.finished: break
			assert(sim.finished and sim.winner == -1 and sim.shots > 0)
			report.symmetry.append({"skill": skill, "team_size": count, "beats": sim.beat, "max_hp_difference": difference, "result": sim.result, "shots": sim.shots, "final": sim.units.map(func(u): return {"hp": u.hp, "cell": u.cell, "pose": u.pose, "mode": u.mode, "trend": u.trend})})

	for preset in range(9):
		game.team_presets = [7, preset]
		game.setup_loadouts()
		game.reset_round()
		for tick in range(240):
			game.simulate(Beat.SECONDS)
			for u in game.units:
				assert(u.p == Beat.center(u.cell) and u.frame_triggers <= 1)
			if game.finished: break
		assert(game.finished and game.shots > 0)
		report.matches.append({"opponent": preset, "beats": game.logic_frame, "winner": game.winner_team, "shots": game.shots, "final_hp": game.units.map(func(u): return u.hp)})

	game.reset_round()
	sim = Beat.new()
	sim.reset(game.units, game.loadouts.duplicate(true), game.walls)
	var reverse_sim = Beat.new()
	reverse_sim.reset(game.units, game.loadouts.duplicate(true), game.walls)
	reverse_sim.decision_order = [3, 2, 1, 0]
	for tick in range(80):
		sim.tick()
		reverse_sim.tick()
		assert(sim.units == reverse_sim.units, "Reversing bot update order must preserve all combat state")
	report.checks.append("80 beats identical with reversed actor update order")

	# Playback speed changes display time only; N and editor changes use the same engine.
	var snapshots: Array = []
	for multiplier in [0.5, 1.0, 2.0]:
		game.reset_round()
		game.started = true
		game.running = true
		game.speed = multiplier
		for frame in range(int(120 / (game.BASE_PLAYBACK_RATE * multiplier))): game.advance_playback(1.0 / 60.0)
		assert(game.logic_frame == 8, "Playback rates must reach the same eight beats after adjusted wall time")
		var state: Array = [game.logic_frame, game.shots]
		for u in game.units: state.append([u.cell, u.hp, u.pose, u.mode, u.left])
		snapshots.append(state)
	assert(snapshots[0] == snapshots[1] and snapshots[1] == snapshots[2])
	game.reset_round()
	game.step_forward()
	assert(game.logic_frame == 0)
	game.advance_playback(Beat.SECONDS / game.playback_rate())
	assert(game.logic_frame == 1)
	game.step_forward(12)
	game.advance_playback(4 * Beat.SECONDS / game.playback_rate())
	assert(game.logic_frame == 5)
	game.reset_round()
	assert(game.place_unit(0, Vector2i(7, 7)))
	game.reset_round()
	assert(game.units[0].cell == Vector2i(7, 7))
	game.choose_editor_unit(0)
	game.edit_rule_cell(0, 0, "站稳")
	assert(game.loadouts[0].active[0][0] == "站稳" and game.units[0].cell == Vector2i(7, 7))
	game.edit_rule_cell(0, 1, "移动姿态")
	game.rebuild_editor()
	assert(game.loadouts[0].active[0][1] == "移动姿态", "Beat-only conditions survive editor rebuilding")
	report.checks.append("nine presets complete; speed independence; single beat stepping; deployment/edit persistence")
	report.balance = preload("res://scripts/beat_balance_validation.gd").run(game)
	report.telegraphs = preload("res://scripts/beat_telegraph_validation.gd").run(game)
	report.shooting = validate_shooting(game)
	report.shot_postures = validate_shot_postures(game)
	report.boundary = validate_boundaries(game)
	report.animate_then_settle = validate_live_steps(game)
	report.soldier = validate_soldier(game)
	report.movement_lock = validate_movement_lock(game)
	report.motion = validate_motion(game)
	report.playback_baseline = validate_playback_baseline(game)
	report.occupancy = validate_occupancy(game)
	var file := FileAccess.open("res://reports/beat-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("BEAT PASSED: soldier preset, 9-beat straight route/12-beat zigzag, turn-standing, smooth braking, two-beat committed movement, one-beat PP dodge, six symmetric cases, nine legacy presets and editor")

static func validate_live_steps(game) -> Dictionary:
	var checks: Array = []
	var sim = fixture(game)
	ap(sim, 0, "向右移动")
	game.beat_sim = sim
	game.loadouts = sim.loadouts
	game.units.assign(sim.units)
	game.presentation.reset(game.units)
	game.speed = 1.0
	var origin: Vector2 = game.units[0].p
	game.step_forward()
	game.step_forward() # Duplicate presses must not queue an unseen extra beat.
	assert(game.logic_frame == 0 and game.units[0].cell == Vector2i(2, 3))
	game.advance_playback(0.25)
	assert(game.logic_frame == 0 and game.units[0].cell == Vector2i(2, 3))
	game.toggle_running() # Switch from single-step to continuous, then pause mid-segment.
	game.toggle_running()
	var paused: float = game.presentation.time
	game._process(2.0)
	assert(game.presentation.time == paused and game.logic_frame == 0)
	game.step_forward() # Finish the same in-progress segment, without restarting it.

	assert(game.presentation.position(game.units[0]).distance_to(origin) > 0)
	game.advance_playback(10.0)
	assert(game.logic_frame == 1 and game.steps_remaining == 0 and not game.running)
	var frozen: float = game.presentation.time
	game._process(5.0)
	assert(game.logic_frame == 1 and game.presentation.time == frozen)
	game.step_forward()
	game.advance_playback(0.49)
	assert(game.logic_frame == 1 and game.units[0].cell == Vector2i(2, 3))
	game.advance_playback(0.01)
	assert(game.logic_frame == 2 and game.units[0].cell == Vector2i(3, 3))
	checks.append("N animates before settling; logical cell stays put during the segment, one press commits one endpoint, then both clocks freeze")
	# A lethal ordinary bullet must arrive before the real HP/death/result is published.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[2].p = Beat.center(sim.units[2].cell)
	sim.units[2].hp = 1
	ap(sim, 0, "普通攻击")
	game.beat_sim = sim
	game.loadouts = sim.loadouts
	game.units.assign(sim.units)
	game.presentation.reset(game.units)
	game.step_forward()
	assert(not preload("res://scripts/beat_telegraph.gd").cells(sim, 0.0, game.segment_preview).is_empty())
	game.advance_playback(0.5)
	assert(game.logic_frame == 1 and game.units[2].hp == 1)
	game.step_forward()
	assert(game.units[2].hp == 1 and game.presentation.flights.size() == 1)
	assert(is_equal_approx(game.presentation.flights[0].duration, Beat.SECONDS))
	game.advance_playback(0.49)
	assert(game.logic_frame == 1 and sim.beat == 1 and game.units[2].hp == 1 and sim.shots == 0 and not game.finished)
	assert(not game.presentation.flights.is_empty() and game.presentation.bursts.all(func(b): return b.age < 0))
	game.advance_playback(0.01)
	assert(game.logic_frame == 2 and game.units[2].hp == 0 and sim.shots == 1 and game.finished)
	assert(game.presentation.flights.is_empty() and game.presentation.bursts.any(func(b): return b.age >= -0.00001))
	checks.append("lethal bullet takes the full firing segment; HP, death and victory change only on arrival; impact remains visible at the paused endpoint")
	# Explicit four-beat playback stops at its fourth endpoint, even with a large frame.
	game.reset_round()
	game.step_forward(12)
	game.advance_playback(10.0)
	assert(game.logic_frame == 4 and game.steps_remaining == 0 and not game.segment_active)
	game.reset_round()
	return {"checks": checks, "real_seconds_per_step": 0.5}

static func validate_boundaries(game) -> Dictionary:
	var checks: Array = []
	var sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	ap(sim, 0, "普通攻击")
	sim.loadouts[2].reaction = [["侧闪", "无", "无"]]
	sim.tick()
	assert(sim.boundary_stages == ["格子更新", "攻击结算", "姿态更新", "下一拍决策"])
	assert(sim.units[2].cell == Vector2i(4, 3) and sim.units[2].hp == 5 and sim.shots == 0)
	assert(sim.next_segment.units[2].phase == "侧闪跨格" and sim.next_segment.units[0].phase == "释放硬直")
	assert(Beat.posture(sim.units[0]) == "僵直姿态")
	sim.tick()
	assert(sim.units[2].cell != Vector2i(4, 3) and sim.units[2].hp == 5 and sim.shots == 1)
	assert(Beat.posture(sim.units[0]) == "动作姿态")
	checks.append("boundary1 detects aim and chooses defender dodge for segment1-2; boundary2 moves defender first then resolves the locked shot")
	# A fresh hit can select a healing PP only for the following segment.
	sim = fixture(game)
	sim.loadouts[0].reaction = [["回春", "无", "无"]]
	warning(sim, sim.units[0].cell, 1)
	sim.tick()
	assert(sim.units[0].hp == 3 and sim.units[0].energy == 100)
	assert(sim.next_segment.units[0].active_skill == "回春" and sim.next_segment.supports.size() == 1)
	assert(sim.next_segment.key == sim.boundary_key(), "Normal ticks consume the decision already made at the preceding endpoint")
	sim.tick()
	assert(sim.units[0].hp == 4 and sim.units[0].energy == 75)
	checks.append("next PP sees damage at this endpoint; planning itself cannot heal, spend energy or undo the hit")
	# Dead units get no next action, but simultaneous completed shots both land.
	sim = fixture(game)
	sim.units[0].hp = 1
	sim.units[2].hp = 1
	sim.units[2].cell = Vector2i(4, 3)
	ap(sim, 0, "普通攻击")
	ap(sim, 2, "普通攻击")
	sim.tick()
	sim.tick()
	assert(sim.units[0].hp == 0 and sim.units[2].hp == 0 and sim.shots == 2 and sim.winner == -1)
	assert(sim.next_segment.strikes.is_empty() and sim.next_segment.units[0].frame_triggers == 0 and sim.next_segment.units[2].frame_triggers == 0)
	checks.append("all completed shots resolve before death; defeated units cannot choose a further action")
	return {"stages": sim.boundary_stages, "checks": checks}

static func validate_shot_postures(game) -> Dictionary:
	var sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	ap(sim, 0, "普通攻击")
	var poses: Array = []
	for tick in range(3):
		sim.tick()
		poses.append(Beat.posture(sim.units[0]))
	assert(poses == ["僵直姿态", "动作姿态", "站立姿态"])
	assert(sim.units[0].pose == "站稳")
	# A pending aim can be cancelled before its beat; no firing, cost or CD leak.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	sim.start_attack(sim.units[0], 2, "点射", sim.units[2].cell)
	warning(sim, sim.units[0].cell, 1)
	sim.tick()
	assert(sim.shots == 0 and sim.units[0].energy == 80 and sim.units[0].phase == "侧闪跨格" and not sim.units[0].skill_cds.has("点射"))
	# The aim endpoint is rigid; the next firing segment cannot be replaced.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	ap(sim, 0, "普通攻击")
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	sim.tick()
	warning(sim, sim.units[0].cell, 2)
	sim.tick()
	assert(sim.shots == 1 and sim.units[0].cell == Vector2i(2, 3) and Beat.posture(sim.units[0]) == "动作姿态")
	# Recovery can be dodged without undoing the shot, its paid cost or own CD.
	warning(sim, sim.units[0].cell, 3)
	sim.tick()
	assert(sim.units[0].phase == "侧闪跨格" and sim.units[0].pose == "移动" and sim.units[0].energy == 65 and sim.units[0].skill_cds["点射"] > 0 and sim.shots == 1)
	assert(Beat.posture(sim.units[0]) == "动作姿态")
	sim.units[0].skill_cds["点射"] = 0.0
	sim.loadouts[0].reaction.clear()
	sim.units[2].cell = sim.units[0].cell + Vector2i(2, 0)
	var energy: float = sim.units[0].energy
	sim.tick()
	assert(sim.units[0].phase == "射击站立" and sim.units[0].pose == "站稳" and sim.shots == 1 and sim.units[0].energy >= energy)
	sim.tick()
	assert(sim.units[0].phase == "前摇" and sim.shots == 1)
	return {"postures": poses, "checks": ["aim is cancellable before execution; refund retained", "release cannot be cancelled", "recovery dodge keeps shot, cost and independent CD", "dodge does not restore standing; a separate standing beat is required before shooting"]}

static func validate_shooting(game) -> Dictionary:
	var checks: Array = []
	var Telegraph = preload("res://scripts/beat_telegraph.gd")
	var sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[2].p = Beat.center(sim.units[2].cell)
	ap(sim, 0, "普通攻击")
	sim.tick()
	assert(sim.beat == 1 and sim.shots == 0 and sim.units[2].hp == 5)
	assert(sim.units[0].phase == "前摇" and sim.units[0].energy == 85 and sim.units[0].cooldown == 0 and not sim.units[0].skill_cds.has("点射"))
	var warnings: Array = Telegraph.cells(sim, 0.0)
	assert(warnings.size() == 1 and warnings[0].cell == Vector2i(4, 3) and warnings[0].due == 2 and warnings[0].total_beats == 1)
	sim.tick()
	assert(sim.beat == 2 and sim.shots == 1 and sim.units[2].hp == 4)
	assert(sim.units[0].phase == "释放硬直" and sim.units[0].mode == "后摇" and sim.units[0].left == 1)
	assert(sim.strikes.is_empty() and sim.effects.size() == 1 and Telegraph.cells(sim, 0.0).is_empty())
	assert(sim.units[0].skill_cds["点射"] == 6 * Beat.SECONDS and sim.units[0].cooldown == 0)
	sim.tick()
	assert(sim.beat == 3 and sim.units[0].mode.is_empty() and sim.units[0].pose == "站稳" and sim.units[0].trend == Vector2i.ZERO and sim.units[0].frame_triggers == 0)
	assert(sim.units[0].cooldown == 0 and sim.units[0].skill_cds["点射"] == 5 * Beat.SECONDS)
	checks.append("standing shot: beat1 aim, beat2 impact, beat3 recovery completes standing")
	while sim.beat < 9: sim.tick()
	assert(sim.shots == 1 and sim.units[0].skill_cds["点射"] == 0 and sim.units[0].phase == "前摇" and sim.units[0].frame_triggers == 1)
	sim.tick()
	assert(sim.beat == 10 and sim.shots == 2 and sim.units[2].hp == 3)
	checks.append("independent CD6 starts on firing and overlaps recovery; no public CD, CD ready at endpoint8, next aim ends at9 and impact at10")
	# Another ready skill can start the very next beat after recovery.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	ap(sim, 0, "普通攻击")
	for tick in range(3): sim.tick()
	ap(sim, 0, "火矢")
	sim.tick()
	assert(sim.beat == 4 and sim.units[0].active_skill == "火矢" and sim.units[0].phase == "前摇" and sim.units[0].skill_cds["点射"] > 0 and sim.units[0].cooldown == 0)
	checks.append("a different ready skill starts on beat4 immediately after recovery, despite the ordinary gun's independent cooldown")
	# No explicit standing rule is needed to enforce the ordinary gun's prerequisite.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.RIGHT
	ap(sim, 0, "普通攻击")
	sim.tick()
	assert(sim.units[0].phase == "射击站立" and sim.units[0].pose == "站稳" and sim.units[0].energy == 100 and sim.units[0].cooldown == 0 and sim.shots == 0)
	assert(Telegraph.cells(sim, 0.0).is_empty())
	sim.tick()
	assert(sim.units[0].phase == "前摇" and sim.units[0].energy == 85)
	sim.tick()
	assert(sim.shots == 1 and sim.units[2].hp == 4)
	sim.tick()
	assert(sim.units[0].pose == "站稳" and sim.units[0].mode.is_empty() and sim.units[0].frame_triggers == 0)
	checks.append("mobile shot automatically spends a separate standing beat even with the standing rule removed; no premature cost/CD/warning")
	# Target cells stay locked, and a simultaneous completed move can evade the shot.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	ap(sim, 0, "普通攻击")
	ap(sim, 2, "向下移动")
	sim.tick()
	sim.tick()
	assert(sim.units[2].cell == Vector2i(4, 4) and sim.units[2].hp == 5 and sim.effects[0].cells == [Vector2i(4, 3)])
	checks.append("shot resolves against the locked grid after simultaneous movement, with no homing or body-radius check")
	# Visual flight finishes inside the firing beat, instead of becoming an instant laser.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[2].p = Beat.center(sim.units[2].cell)
	ap(sim, 0, "普通攻击")
	var display = preload("res://scripts/beat_presentation.gd").new()
	display.reset(sim.units)
	for tick in range(2):
		var before: Array = sim.units.duplicate(true)
		sim.tick()
		display.begin(before, sim.units, sim)
		if tick == 0: display.advance(Beat.SECONDS)
	assert(display.flights.size() == 1 and not display.flights[0].beam and display.bursts[0].age < 0)
	display.advance(Beat.SECONDS * 0.4)
	assert(not display.flights.is_empty() and display.bursts[0].age < 0)
	display.advance(Beat.SECONDS * 0.3)
	assert(display.flights.is_empty() and display.bursts[0].age >= 0 and sim.beat == 2)
	checks.append("ordinary shot has a short visual projectile and a delayed impact flash within the same firing beat; animation never changes logic")
	return {"checks": checks, "independent_cd_beats": 6, "public_cd_beats": 0, "standing_action_beats": 3, "mobile_action_beats": 4}

static func validate_soldier(game) -> Dictionary:
	var checks: Array = []
	# Four straight crossings and one final standing beat: 2*4+1 = 9.
	var sim = fixture(game)
	sim.units[0].cell = Vector2i(1, 2)
	sim.units[0].p = Beat.center(sim.units[0].cell)
	ap(sim, 0, "向右移动")
	for tick in range(8):
		sim.tick()
		assert(sim.units[0].cell == Vector2i(1 + (tick + 1) / 2, 2))
		assert(sim.units[0].phase != "转向站立")
	ap(sim, 0, "站稳")
	sim.tick()
	assert(sim.beat == 9 and sim.units[0].cell == Vector2i(5, 2) and sim.units[0].pose == "站稳")
	checks.append("straight four cells plus final stand takes exactly nine beats")
	# Four one-cell legs with three direction changes and a final stand: 12.
	sim = fixture(game)
	var route := [["向右移动", Vector2i.RIGHT], ["向上移动", Vector2i.UP], ["向右移动", Vector2i.RIGHT], ["向下移动", Vector2i.DOWN]]
	for leg in range(route.size()):
		var origin: Vector2i = sim.units[0].cell
		ap(sim, 0, route[leg][0])
		if leg > 0:
			sim.tick()
			assert(sim.units[0].cell == origin and sim.units[0].phase == "转向站立" and sim.units[0].pose == "站稳")
		sim.tick()
		assert(sim.units[0].cell == origin and sim.units[0].mode == "移动硬直")
		sim.tick()
		assert(sim.units[0].cell == origin + route[leg][1])
	ap(sim, 0, "站稳")
	sim.tick()
	assert(sim.beat == 12 and sim.units[0].pose == "站稳")
	checks.append("four zigzag cells plus final stand takes exactly twelve beats")
	var directions := [["向右移动", Vector2i.RIGHT], ["向左移动", Vector2i.LEFT], ["向上移动", Vector2i.UP], ["向下移动", Vector2i.DOWN]]
	for prior in directions:
		for following in directions:
			sim = fixture(game)
			sim.units[0].pose = "移动"
			sim.units[0].trend = prior[1]
			ap(sim, 0, following[0])
			var origin: Vector2i = sim.units[0].cell
			var total := 2 if prior[1] == following[1] else 3
			for tick in range(total):
				sim.tick()
				assert(sim.units[0].cell == (origin if tick < total - 1 else origin + following[1]))
			assert(sim.beat == total)
	checks.append("all sixteen direction pairs: same direction costs two; perpendicular and reverse direction cost standing plus two")
	# Paid movement must not charge or start cooldown merely to stop for a turn.
	sim = fixture(game)
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.UP
	sim.units[2].cell = Vector2i(5, 3)
	ap(sim, 0, "短冲刺")
	sim.tick()
	assert(sim.units[0].phase == "转向站立" and sim.units[0].energy == 100 and not sim.units[0].skill_cds.has("短冲刺"))
	sim.tick()
	assert(sim.units[0].mode == "移动硬直" and sim.units[0].energy == 80 and sim.units[0].skill_cds["短冲刺"] > 0)
	checks.append("mandatory turn-standing does not consume paid movement energy or CD")
	# A dodge still bypasses the direction-change standing beat.
	sim = fixture(game)
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.LEFT
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	warning(sim, sim.units[0].cell, 1)
	sim.tick()
	assert(sim.units[0].cell == Vector2i(3, 3) and sim.units[0].phase == "侧闪跨格" and sim.units[0].energy == 80)
	checks.append("PP dodge changes direction immediately in one beat")
	# Direction changes decelerate forward, stop, and only then turn and accelerate.
	sim = fixture(game)
	var display = preload("res://scripts/beat_presentation.gd").new()
	display.reset(sim.units)
	ap(sim, 0, "向右移动")
	for tick in range(2):
		var before: Array = sim.units.duplicate(true)
		sim.tick()
		display.begin(before, sim.units, sim)
		display.advance(Beat.SECONDS)
	var origin: Vector2 = display.position(sim.units[0])
	ap(sim, 0, "向上移动")
	var before: Array = sim.units.duplicate(true)
	sim.tick()
	display.begin(before, sim.units, sim)
	assert(display.position(sim.units[0]).is_equal_approx(origin) and sim.units[0].phase == "转向站立")
	var previous := origin
	for frame in range(20):
		display.advance(Beat.SECONDS / 20)
		var point: Vector2 = display.position(sim.units[0])
		assert(point.x >= previous.x - 0.0001 and point.x <= sim.units[0].p.x + 0.0001 and is_equal_approx(point.y, sim.units[0].p.y), "Standing must brake forward without reversing or cutting the corner")
		previous = point
	assert(display.velocity(sim.units[0]).is_zero_approx() and display.position(sim.units[0]).is_equal_approx(sim.units[0].p))
	before = sim.units.duplicate(true)
	sim.tick()
	display.begin(before, sim.units, sim)
	assert(display.velocity(sim.units[0]).is_zero_approx())
	display.advance(Beat.SECONDS)
	assert(display.position(sim.units[0]).y < before[0].p.y and is_equal_approx(display.position(sim.units[0]).x, before[0].p.x))
	checks.append("turn animation brakes monotonically within the cell, reaches zero speed, then accelerates in the new direction")
	# Default UI preset is a plain soldier on both sides, without magic or ultimates.
	game.team_presets = [game.SOLDIER_PRESET, game.SOLDIER_PRESET]
	game.deployment_cells = game.DEFAULT_DEPLOYMENT.duplicate()
	game.setup_loadouts()
	game.rebuild_editor()
	game.reset_round()
	for loadout in game.loadouts:
		for rule in loadout.active: assert(rule[0] in ["站稳", "普通攻击", "接敌"])
		assert(loadout.reaction == [["侧闪", "无", "无"]])
	assert(game.basic_loadout() == game.preset_loadouts(game.SOLDIER_PRESET)[0])
	game.units[0].ult_charge = 100
	game.started = true
	assert(not game.beat_ultimate_available(0))
	for tick in range(240):
		if game.finished: break
		game.simulate(Beat.SECONDS)
	assert(game.finished and game.shots > 0)
	checks.append("default soldier preset uses only standing, ordinary attack, engagement and PP dodge; no ultimate")
	return {"checks": checks, "match": {"beats": game.logic_frame, "winner": game.winner_team, "shots": game.shots}}

static func validate_movement_lock(game) -> Array:
	var checks: Array = []
	# Changing AP to stand, attack or turn cannot interrupt a committed crossing.
	for replacement in ["站稳", "普通攻击", "向上移动"]:
		var sim = fixture(game)
		sim.units[2].cell = Vector2i(4, 3)
		ap(sim, 0, "向右移动")
		sim.tick()
		assert(sim.units[0].mode == "移动硬直" and sim.units[0].left == 1 and sim.units[0].frame_triggers == 1)
		ap(sim, 0, replacement)
		sim.tick()
		assert(sim.units[0].cell == Vector2i(3, 3) and sim.units[0].mode.is_empty() and sim.units[0].frame_triggers == 0 and sim.shots == 0)
		sim.tick()
		assert(sim.units[0].frame_triggers == 1, "New AP can start only on the beat after arrival")
	checks.append("stand/attack/turn AP cannot interrupt or start on the arrival beat")
	for skill in Beat.Tactics.REACTIONS + Beat.Tactics.BASIC_REACTIONS:
		if skill in ["侧闪", "留空"]: continue
		var sim = fixture(game)
		ap(sim, 0, "向右移动")
		sim.tick()
		sim.loadouts[0].reaction = [[skill, "无", "无"]]
		warning(sim, sim.units[0].cell, 2)
		sim.tick()
		assert(sim.units[0].cell == Vector2i(3, 3) and sim.units[0].frame_triggers == 0 and sim.units[0].trace_pp[0] == "当前动作只允许侧闪")
	checks.append("walking evade, guard, healing, protection and offensive PP cannot cancel movement")
	# Dodge redirects from the authoritative source cell and discards the old destination.
	var sim = fixture(game)
	ap(sim, 0, "向右移动")
	sim.tick()
	var old_goal: Vector2i = sim.units[0].move_target
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	warning(sim, Vector2i(2, 3), 2)
	warning(sim, old_goal, 2)
	sim.tick()
	var escaped: Vector2i = sim.units[0].cell
	assert(escaped != Vector2i(2, 3) and escaped != old_goal and Beat.distance(escaped, Vector2i(2, 3)) == 1)
	assert(sim.units[0].mode.is_empty() and sim.units[0].phase == "侧闪跨格" and sim.units[0].energy == 80 and sim.units[0].hp == 5 and sim.units[0].frame_triggers == 1)
	assert(sim.units[0].skill_cds["侧闪"] > 0 and sim.units[0].last_cancel.begins_with("移动硬直取消"))
	sim.loadouts[0].active.clear()
	sim.tick()
	assert(sim.units[0].cell == escaped and sim.units[0].mode.is_empty(), "Cancelled movement must never resume its former destination")
	checks.append("one-beat PP dodge cancels movement, costs 20, starts its CD and never resumes the old crossing")
	for failure in ["energy", "cooldown", "no safe cell"]:
		sim = fixture(game)
		ap(sim, 0, "向右移动")
		sim.tick()
		sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
		if failure == "energy": sim.units[0].energy = 10
		if failure == "cooldown": sim.units[0].skill_cds["侧闪"] = 2.0
		warning(sim, sim.units[0].cell, 2)
		if failure == "no safe cell":
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]: warning(sim, sim.units[0].cell + d, 2)
		sim.tick()
		assert(sim.units[0].cell == Vector2i(3, 3) and sim.units[0].frame_triggers == 0 and sim.units[0].last_cancel.is_empty())
	checks.append("unaffordable, cooling or unsafe dodge leaves the original movement committed")
	# Slow preserves its existing one-extra-beat penalty; dodge remains one beat.
	sim = fixture(game)
	sim.units[0].slow = 2.5
	ap(sim, 0, "向右移动")
	for tick in range(3):
		sim.tick()
		assert(sim.units[0].cell == (Vector2i(2, 3) if tick < 2 else Vector2i(3, 3)))
	sim = fixture(game)
	sim.units[0].slow = 2.5
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	warning(sim, sim.units[0].cell, 1)
	sim.tick()
	assert(Beat.distance(sim.units[0].cell, Vector2i(2, 3)) == 1 and sim.units[0].frame_triggers == 1)
	checks.append("slow adds one beat to walking but never to the one-beat dodge")
	return checks

static func validate_presentation(game) -> void:
	var sim = fixture(game)
	var display = preload("res://scripts/beat_presentation.gd").new()
	display.reset(sim.units)
	ap(sim, 0, "向右移动")
	for stage in range(3):
		if stage == 2: ap(sim, 0, "站稳")
		var before: Array = sim.units.duplicate(true)
		var origin: Vector2 = display.position(before[0])
		sim.tick()
		display.begin(before, sim.units, sim)
		assert(display.position(sim.units[0]).is_equal_approx(origin), "A new beat must not teleport the body")
		var snapshot: Array = sim.units.duplicate(true)
		display.advance(Beat.SECONDS / 2)
		var middle: Vector2 = display.position(sim.units[0])
		var target: Vector2 = display.destination(sim.units[0])
		assert(middle.distance_to(origin) > 0 and middle.distance_to(target) > 0, "The body must move between beats")
		display.advance(Beat.SECONDS / 2)
		assert(display.position(sim.units[0]).is_equal_approx(target))
		assert(sim.units == snapshot, "Visual updates must never change combat state")
		if stage == 1:
			# Independent render frame sizes must produce the same pose.
			var other = preload("res://scripts/beat_presentation.gd").new()
			other.reset(before)
			other.begin(before, sim.units, sim)
			for frame in range(30): other.advance(Beat.SECONDS / 30.0)
			assert(other.position(sim.units[0]).is_equal_approx(target))
	# Collision approach, then continuous rebound without a position jump.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[2].p = Beat.center(sim.units[2].cell)
	ap(sim, 0, "向右移动")
	ap(sim, 2, "向左移动")
	display.reset(sim.units)
	for tick in range(3):
		var before: Array = sim.units.duplicate(true)
		var origin: Vector2 = display.position(before[0])
		sim.tick()
		display.begin(before, sim.units, sim)
		assert(display.position(sim.units[0]).is_equal_approx(origin))
		display.advance(Beat.SECONDS)
		assert(display.position(sim.units[0]).is_equal_approx(display.destination(sim.units[0])))
	# Dodging animates an actual crossing while the engine cell is already discrete.
	sim = fixture(game)
	sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
	warning(sim, sim.units[0].cell, 1)
	display.reset(sim.units)
	var before_dodge: Array = sim.units.duplicate(true)
	sim.tick()
	display.begin(before_dodge, sim.units, sim)
	display.advance(Beat.SECONDS / 2)
	assert(display.visual(sim.units[0]).dodge > 0)
	assert(display.position(sim.units[0]) != display.destination(sim.units[0]))
	assert(sim.units[0].p == Beat.center(sim.units[0].cell))
	# Release flash and projectile move/fade without another combat tick.
	sim = fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[2].p = Beat.center(sim.units[2].cell)
	ap(sim, 0, "普通攻击")
	display.reset(sim.units)
	for tick in range(2):
		var before: Array = sim.units.duplicate(true)
		sim.tick()
		display.begin(before, sim.units, sim)
		if tick == 0: display.advance(Beat.SECONDS)
	assert(display.flights.size() == 1 and display.visual(sim.units[0]).fire_flash > 0)
	var flash: float = display.visual(sim.units[0]).fire_flash
	display.advance(0.1)
	assert(display.flights[0].age > 0 and display.visual(sim.units[0]).fire_flash < flash)
	display.advance(0.15)
	assert(display.flights.is_empty() and display.visual(sim.units[0]).fire_flash == 0)
	game.reset_round()
	game.step_forward()
	var state: Array = game.units.duplicate(true)
	var beat: int = game.logic_frame
	game._process(0.1)
	assert(game.units == state and game.logic_frame == beat, "Single-step animates without advancing another beat")
	game.advance_playback(Beat.SECONDS / game.playback_rate())
	assert(game.steps_remaining == 0 and game.logic_frame == beat + 1)
	var frozen: float = game.presentation.time
	game._process(0.1)
	assert(game.presentation.time == frozen, "Pause freezes the visual clock")

static func validate_motion(game) -> Array:
	var display = preload("res://scripts/beat_presentation.gd").new()
	var sim = fixture(game)
	ap(sim, 0, "向右移动")
	display.reset(sim.units)
	for tick in range(4):
		var before: Array = sim.units.duplicate(true)
		var p: Vector2 = display.position(before[0])
		var v: Vector2 = display.velocity(before[0])
		sim.tick()
		display.begin(before, sim.units, sim)
		assert(display.position(sim.units[0]).is_equal_approx(p))
		assert(display.velocity(sim.units[0]).is_equal_approx(v), "Beat boundaries must preserve velocity")
		var guide: Dictionary = display.guide(sim.units[0])
		var expected_target: Vector2 = sim.units[0].action_goal if sim.units[0].mode == "移动硬直" else sim.units[0].p
		assert(not guide.is_empty() and guide.to == expected_target)
		for sample in range(20):
			display.advance(Beat.SECONDS / 20)
			if tick >= 1: assert(display.velocity(sim.units[0]).is_equal_approx(Vector2(160, 0)), "Two-beat walking stays continuous at half the old cruise speed")
		assert(display.position(sim.units[0]).is_equal_approx(display.destination(sim.units[0])))
	# Braking remains inside the committed cell and finishes with zero velocity.
	var before: Array = sim.units.duplicate(true)
	var speed_before: Vector2 = display.velocity(before[0])
	ap(sim, 0, "站稳")
	sim.tick()
	display.begin(before, sim.units, sim)
	assert(display.velocity(sim.units[0]).is_equal_approx(speed_before))
	assert(display.guide(sim.units[0]).is_empty(), "Standing must clear the old movement destination")
	var cell_rect := Rect2(Vector2(sim.units[0].cell) * 80, Vector2.ONE * 80)
	for sample in range(20):
		display.advance(Beat.SECONDS / 20)
		assert(cell_rect.has_point(display.position(sim.units[0])), "Visual braking cannot drift into another grid cell")
	assert(display.velocity(sim.units[0]).is_zero_approx() and display.position(sim.units[0]).is_equal_approx(sim.units[0].p))
	var expected: Array = []
	for fps in [30, 60, 144]:
		for multiplier in [0.5, 1.0, 2.0]:
			sim = fixture(game)
			ap(sim, 0, "向右移动")
			game.beat_sim = sim
			game.units.assign(sim.units)
			game.loadouts = sim.loadouts
			game.presentation.reset(game.units)
			game.running = true
			game.started = true
			game.speed = multiplier
			var real_duration: float = 1.125 / (game.BASE_PLAYBACK_RATE * multiplier)
			var frames := floori(real_duration * fps)
			for frame in range(frames): game.advance_playback(1.0 / fps)
			game.advance_playback(real_duration - float(frames) / fps)
			var state: Array = [game.logic_frame, game.units[0].cell, game.presentation.position(game.units[0]), game.presentation.velocity(game.units[0])]
			if expected.is_empty(): expected = state
			assert(state[0] == expected[0] and state[1] == expected[1] and Vector2(state[2]).is_equal_approx(expected[2]) and Vector2(state[3]).is_equal_approx(expected[3]), "Render rate and playback speed must preserve the same combat and visual state")
			assert(absf(game.presentation.beat_age - game.accumulator) < 0.00001, "Animation and combat must share the same clock")
	game.reset_round()
	return ["position and velocity continuous at beat boundaries", "two-beat crossings keep 160 logical px/s without per-cell braking", "standing brakes within its own cell and ends at rest", "movement guides show actual committed destinations", "30/60/144 FPS and 0.5/1/2x agree on logic, position, velocity and beat phase"]

static func validate_playback_baseline(game) -> Array:
	for setting in [[0.5, 1], [1.0, 2], [2.0, 4]]:
		game.reset_round()
		game.speed = setting[0]
		game.started = true
		game.running = true
		for frame in range(60): game.advance_playback(1.0 / 60.0)
		assert(game.logic_frame == setting[1], "One real second must advance 1/2/4 beats at new 0.5/1/2x")
	game.reset_round()
	game.speed = 1.0
	game.step_forward()
	game._process(0.25)
	assert(is_equal_approx(game.presentation.beat_age, 0.125) and game.logic_frame == 0)
	game._process(0.25)
	assert(is_equal_approx(game.presentation.beat_age, 0.0) and game.logic_frame == 1, "Single-step animation must take half a real second at the new baseline")
	game.reset_round()
	return ["new default 1x equals previous 0.5x", "0.5x/1x/2x use 1.0/0.5/0.25 real seconds per beat", "single-step animation follows the same new baseline"]

static func validate_occupancy(game) -> Array:
	var Markers = preload("res://scripts/beat_occupancy.gd")
	var sim = fixture(game)
	var display = preload("res://scripts/beat_presentation.gd").new()
	display.reset(sim.units)
	var initial := Markers.markers(sim.units)
	assert(initial.size() == 2 and initial[0].stationary and initial[0].pose_text == "站稳")
	var origin: Vector2i = sim.units[0].cell
	ap(sim, 0, "向左移动")
	for beat in range(2):
		var before: Array = sim.units.duplicate(true)
		sim.tick()
		display.begin(before, sim.units, sim)
		var markers := Markers.markers(sim.units)
		var marker: Dictionary = markers[0]
		assert(marker.cell == (origin if beat == 0 else origin + Vector2i.LEFT))
		assert(not marker.stationary and marker.trend == Vector2i.LEFT and marker.pose_text == "移动·左")
		assert(marker.p == Beat.center(sim.units[0].cell))
		display.advance(Beat.SECONDS / 2)
		assert(Markers.markers(sim.units) == markers, "Occupancy must not move with the animated body")
		assert(not display.position(sim.units[0]).is_equal_approx(marker.p))
		display.advance(Beat.SECONDS / 2)
	ap(sim, 0, "站稳")
	sim.tick()
	assert(Markers.markers(sim.units)[0].stationary)
	# A mobile pose remains mobile while an attack holds the body in its cell.
	sim.units[0].pose = "移动"
	sim.units[0].trend = Vector2i.RIGHT
	sim.start_attack(sim.units[0], 2, "落岩", sim.units[2].cell)
	assert(not Markers.markers(sim.units)[0].stationary)
	# Collision occupants each retain a stable identity and their own label lane.
	sim = fixture(game)
	sim.units[1].hp = 5
	for uid in [0, 1, 2]: sim.units[uid].cell = Vector2i(3, 3)
	var shared := Markers.markers(sim.units)
	assert(shared.size() == 3)
	for lane in range(3):
		assert(shared[lane].uid == lane and shared[lane].lane == lane and shared[lane].count == 3)
	var reversed: Array = sim.units.duplicate(true)
	reversed.reverse()
	assert(Markers.markers(reversed) == shared)
	sim.units[1].hp = 0
	assert(Markers.markers(sim.units).size() == 2)
	game.reset_round()
	return ["markers remain in the source cell during the first move beat and switch on arrival, independent of body interpolation", "standing/mobile pose is explicit, including attacking in mobile pose", "shared cells keep separate stable bot labels; dead bots release markers"]
