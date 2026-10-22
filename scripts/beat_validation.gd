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
	assert(sim.units[0].cell == Vector2i(4, 3) and sim.units[0].mode == "移动硬直")
	sim.tick()
	assert(sim.units[0].cell == Vector2i(4, 2))
	report.checks.append("ordinary movement always two beats; no same-direction acceleration or extra turning cost; one selection per action")

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
	ap(sim, 0, "普通攻击")
	sim.tick()
	assert(sim.units[0].cell == Vector2i(2, 3) and sim.units[0].pose == "移动", "Mobile attack retains momentum but never also moves")
	sim.tick()
	assert(sim.units[0].mode == "后摇" and sim.shots == 1)
	sim.tick()
	assert(sim.units[2].hp == 4 and sim.units[0].frame_triggers == 0)
	report.checks.append("low skill allowed while mobile; locked-cell impact; no AP on recovery completion beat")

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
	assert(sim.units[0].cooldown > 0 and sim.units[0].skill_cds["落岩"] > 0)
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
	assert(game.logic_frame == 1)
	game.step_forward(12)
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
	report.movement_lock = validate_movement_lock(game)
	report.motion = validate_motion(game)
	report.playback_baseline = validate_playback_baseline(game)
	report.occupancy = validate_occupancy(game)
	var file := FileAccess.open("res://reports/beat-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("BEAT PASSED: two-beat committed movement, one-beat PP dodge, cancellation gates, standing gate, AP/PP exclusivity, refunds, collisions/return reservation, six symmetric cases, nine presets, playback and editor")

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
	game.settle_visual = 0.0
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
	assert(is_equal_approx(game.presentation.beat_age, 0.125) and game.logic_frame == 1)
	game._process(0.25)
	assert(is_equal_approx(game.presentation.beat_age, 0.25) and game.logic_frame == 1, "Single-step animation must take half a real second at the new baseline")
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
