extends RefCounted

const Timeline = preload("res://scripts/action_timeline.gd")
const STEP := 1.0 / 60.0

static func fixture(g) -> void:
	g.pattern_fixture()
	g.walls.clear()
	g.wall_states.clear()
	g.setup_navigation()
	for u in g.units:
		g.loadouts[u.uid] = g.Tactics.build([], [])
		Timeline.clear(u)
	g.units[0].p = Vector2(100, 320)
	g.units[0].angle = 0.0
	g.units[2].p = Vector2(300, 320)
	g.units[2].angle = PI

static func incoming(g, target := 0) -> void:
	var u: Dictionary = g.units[target]
	var direction := Vector2.LEFT if target == 0 else Vector2.RIGHT
	g.bullets.append({"p": u.p - direction * 100, "v": direction * 360, "life": 1.0, "damage": 20.0, "team": 1 - u.team, "source": 2 if target == 0 else 0})

static func run(g) -> void:
	var report := {"fps": 60, "arena": "open floor; positions/angles rotated 180 degrees about arena center", "checks": [], "symmetry": []}
	fixture(g)
	g.begin_shot(g.units[0], 2, "落岩")
	Timeline.enter(g.units[0], Timeline.WINDUP, 5)
	g.units[0].recovery_frames = 3
	for frame in range(1, 11):
		g.simulate(STEP)
		var u: Dictionary = g.units[0]
		if frame < 5: assert(u.action_stage == Timeline.WINDUP and u.stage_frames == 5 - frame)
		elif frame == 5: assert(u.action_stage == Timeline.RELEASE and g.shots == 0)
		elif frame == 6: assert(u.action_stage == Timeline.RELEASE and u.shot_count == 1)
		elif frame < 10: assert(u.action_stage == Timeline.RECOVERY and u.stage_frames == 10 - frame)
		else: assert(not Timeline.busy(u))
	report.checks.append("exact 5-frame windup / 2-frame release / 3-frame recovery")

	fixture(g)
	g.loadouts[0] = g.Tactics.build([["火矢", "无", "无"]], [["侧闪", "无", "无"]])
	g.begin_shot(g.units[0], 2, "蓄能贯穿")
	Timeline.enter(g.units[0], Timeline.WINDUP, 5)
	g.begin_shot(g.units[2], 0, "火矢")
	Timeline.enter(g.units[2], Timeline.WINDUP, 100)
	for frame in range(4): g.simulate(STEP)
	assert(g.units[0].stage_frames == 1)
	incoming(g)
	var origin: Vector2 = g.units[0].p
	g.simulate(STEP)
	assert(g.units[0].phase == "侧闪" and g.units[0].frame_triggers == 1)
	assert(g.units[0].energy == 80, "Refund 45, then spend 20 exactly once")
	assert(g.units[0].p.distance_to(origin) > 3.9, "Dodge starts moving on its selection frame")
	assert(g.units[0].p.distance_to(origin) < 4.1, "Dodge may advance only once per frame")
	assert(g.units[2].stage_frames == 95, "Another bot must advance on the same frame")
	assert(g.shots == 0 and not g.units[0].skill_cds.has("蓄能贯穿"))
	for frame in range(19): g.simulate(STEP)
	assert(g.units[0].dodge_frames == 0 and g.units[0].frame_triggers == 0)
	assert(not Timeline.busy(g.units[0]) and g.units[0].path.is_empty())
	g.simulate(STEP)
	assert(g.units[0].active_skill == "火矢" and g.units[0].frame_triggers == 1)
	report.checks.append("last-windup-frame refund, immediate single dodge step, independent bots, fresh AP after dodge")

	fixture(g)
	g.loadouts[0] = g.Tactics.build([], [["侧闪", "无", "无"]])
	g.begin_shot(g.units[0], 2, "落岩")
	Timeline.enter(g.units[0], Timeline.WINDUP, 1)
	g.simulate(STEP)
	incoming(g)
	g.simulate(STEP)
	assert(g.units[0].action_stage == Timeline.RELEASE and g.units[0].shot_count == 1)
	assert(g.units[0].phase != "侧闪" and g.units[0].energy == 75)
	assert(g.units[0].trace_pp[0] == "释放硬直中，不能侧闪")
	g.simulate(STEP)
	assert(g.units[0].action_stage == Timeline.RECOVERY)
	var own_projectiles := 0
	for b in g.bullets:
		if b.get("source", -1) == 0: own_projectiles += 1
	g.simulate(STEP)
	assert(g.units[0].phase == "侧闪" and g.units[0].energy == 55, "Recovery cancellation must not refund attack energy")
	assert(g.units[0].cooldown > 0 and g.units[0].skill_cds["落岩"] > 0)
	var after_cancel := 0
	for b in g.bullets:
		if b.get("source", -1) == 0: after_cancel += 1
	assert(own_projectiles == 1 and after_cancel == 1, "Already emitted projectile survives cancellation")
	report.checks.append("release lock, recovery bonus, preserved attack cooldown and projectile")

	fixture(g)
	g.loadouts[0] = g.Tactics.build([], [["侧闪", "无", "无"]])
	g.units[0].energy = 35
	g.begin_shot(g.units[0], 2, "落岩")
	incoming(g)
	g.simulate(STEP)
	assert(g.units[0].phase == "侧闪" and g.units[0].energy == 15, "Refund is available to pay dodge")
	fixture(g)
	g.loadouts[0] = g.Tactics.build([], [["侧闪", "无", "无"]])
	g.begin_shot(g.units[0], 2, "蓄能贯穿")
	g.units[0].skill_cds["侧闪"] = 1.0
	incoming(g)
	g.simulate(STEP)
	assert(g.units[0].action_stage == Timeline.WINDUP and g.units[0].energy == 55, "Rejected dodge must not refund/cancel")
	fixture(g)
	g.loadouts[0] = g.Tactics.build([], [["侧闪", "无", "无"]])
	g.begin_shot(g.units[0], 2, "蓄能贯穿")
	g.walls.assign([Rect2(40, 260, 120, 20), Rect2(40, 360, 120, 20), Rect2(40, 280, 20, 80), Rect2(140, 280, 20, 80)])
	g.hazards.append({"kind": "area", "skill": "抛射轰击", "p": g.units[0].p, "origin": g.units[2].p, "radius": 64.0, "left": 0.5, "damage": 18.0, "team": 1, "source": 2})
	g.simulate(STEP)
	assert(g.units[0].action_stage == Timeline.WINDUP and g.units[0].energy == 55, "No escape path must not cancel/refund the attack")
	report.checks.append("low-energy refund eligibility and rejected dodge leaves action intact")

	for shooter in [0, 2]:
		fixture(g)
		var defender := 2 if shooter == 0 else 0
		g.loadouts[defender] = g.Tactics.build([], [["侧闪", "无", "无"]])
		g.begin_shot(g.units[shooter], defender, "落岩")
		Timeline.enter(g.units[shooter], Timeline.RELEASE, 2)
		g.simulate(STEP)
		assert(g.units[defender].dodge <= 0, "No actor may see another actor's same-frame emission")
		g.simulate(STEP)
		assert(g.units[defender].phase == "侧闪", "Published projectile is visible next frame regardless of actor order")
	report.checks.append("same perception frame for earlier/later actor indices")

	for scenario in [{"count": 1, "skill": ""}, {"count": 2, "skill": ""}, {"count": 1, "skill": "落岩"}, {"count": 2, "skill": "落岩"}, {"count": 1, "skill": "风刃"}, {"count": 2, "skill": "风刃"}]:
		var count: int = scenario.count
		fixture(g)
		if count == 2:
			g.units[1].hp = 100.0
			g.units[3].hp = 100.0
		for uid in range(4):
			var u: Dictionary = g.units[uid]
			var left := uid < 2
			u.p = Vector2(220 if left else 420, (220 if uid % 2 == 0 else 420) if left else (420 if uid % 2 == 0 else 220)) if count == 2 else Vector2(220 if left else 420, 320)
			u.angle = 0.0 if left else PI
			g.loadouts[uid] = g.Tactics.basics()
			if not scenario.skill.is_empty():
				g.loadouts[uid].active.push_front([scenario.skill, "无", "无"])
				g.loadouts[uid].reaction.push_front(["侧闪", "无", "无"])
		var max_difference := 0.0
		var trace: Array = []
		for frame in range(3602):
			g.simulate(STEP)
			var state: Array = []
			for actor in g.units: state.append({"hp": actor.hp, "p": actor.p, "goal": actor.action_goal, "phase": actor.phase, "stage": actor.action_stage, "left": actor.stage_frames, "target": actor.target, "angle": actor.angle})
			trace.append({"frame": frame + 1, "actors": state})
			if trace.size() > 120: trace.pop_front()
			for member in range(count): max_difference = maxf(max_difference, absf(g.units[member].hp - g.units[member + 2].hp))
			if max_difference >= 0.0001:
				var debug_file := FileAccess.open("res://reports/lifecycle-symmetry-debug.json", FileAccess.WRITE)
				debug_file.store_string(JSON.stringify({"scenario": scenario, "trace": trace}, "\t"))
			assert(max_difference < 0.0001, "Symmetric actors must take equal damage on every frame")
			if g.finished: break
		assert(g.finished and g.winner_team == -1)
		var dodges: Array = []
		for uid in range(4): dodges.append(int(g.reaction_counts.get("%d:侧闪" % uid, 0)))
		for member in range(count): assert(dodges[member] == dodges[member + 2])
		if scenario.skill == "落岩": assert(dodges[0] > 0, "Symmetry case must exercise actual dodge reactions")
		report.symmetry.append({"bots_per_team": count, "skill": "普通攻击" if scenario.skill.is_empty() else scenario.skill, "dodges": dodges, "max_hp_difference": max_difference, "frames": g.logic_frame, "result": g.win_reason, "final_hp": [g.units[0].hp, g.units[1].hp, g.units[2].hp, g.units[3].hp]})
	var file := FileAccess.open("res://reports/lifecycle-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("LIFECYCLE PASSED: frame boundaries, windup refund, recovery cancel, release lock, independent branches, immutable perception, 1v1/2v2 frame-exact symmetric damage")
