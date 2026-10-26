extends SceneTree
const Sim = preload("res://scripts/squad_simulation.gd")

func run_case(settings: Dictionary) -> Dictionary:
	var sim = Sim.new()
	sim.reset(settings)
	while not sim.finished:
		sim.tick()
		for u in sim.units:
			var p: Vector2 = sim.pos(u.id)
			assert(p.x >= 20 and p.x <= 900 and p.y >= 65 and p.y <= 615, "formation out of arena")
			for wall in Sim.WALLS: assert(not wall.grow(20).has_point(p), "body intersects wall")
	var stopped: Dictionary = sim.summary()
	sim.tick()
	assert(sim.summary() == stopped, "result must freeze")
	return stopped

func _initialize() -> void:
	var baseline := run_case(Sim.defaults())
	assert(baseline == run_case(Sim.defaults()), "identical setup must replay exactly")
	assert(baseline.combos > 0, "default setup must actually create cross-squad combos")
	assert(baseline.events.any(func(e): return e.kind in ["PP", "治疗"] and e.actor == 3 and e.target == 0), "medic must be able to support another squad")
	for e in baseline.events:
		if e.kind == "连携":
			assert(e.actor == 2 and e.causes.size() == 2)
			var cause: Dictionary = baseline.events[e.causes[1] - 1]
			assert(cause.kind == "牵制" and cause.actor == 0 and cause.target == e.target)
	var support := Sim.defaults(); support.tasks[1] = "支援A队"
	var held := Sim.defaults(); held.tasks[1] = "原地驻守"
	var no_combo := Sim.defaults(); no_combo.rules[2][0] = ["留空", "无"]
	var no_wait := Sim.defaults(); no_wait.rules[2][1] = ["留空", "无", "无"]
	var outcomes := {"flank": baseline, "support": run_case(support), "hold": run_case(held), "no_combo": run_case(no_combo), "no_wait": run_case(no_wait)}
	for key in outcomes:
		var r: Dictionary = outcomes[key]
		print("%s: time=%s result=%s combo=%s hp=%s" % [key, r.time, r.result, r.combos, r.hp])
	var sim = Sim.new(); sim.reset()
	# Explicitly prove range filtering, no private chase, and role constraints.
	assert(sim.candidates(0, "盾击", "无").is_empty())
	assert(Sim.conditions_for("治疗") == ["无", "友军HP≤60%"])
	assert(Sim.options("法师") == ["留空", "火球"])
	var route: Array = sim.path_to(Vector2(140, 530), Vector2(765, 565))
	assert(not route.is_empty(), "flank must be navigable")
	var from := Vector2(140, 530)
	for to in route:
		assert(sim.clear_path(from, to)); from = to
	# Attack presentation has time to travel before publishing damage.
	sim.reset()
	for s in sim.squads: s.task = "原地驻守"
	sim.squads[0].pos = Vector2(420, 335)
	for u in sim.units: u.rules = []; u.pp_rules = []
	sim.units[1].rules = [["火球", "无"]]
	sim.choose_actions()
	assert(sim.units[1].mode == "施法")
	var target: int = sim.units[1].target
	var initial_hp: float = sim.units[target].hp
	for i in range(25): sim.tick()
	assert(sim.units[target].hp == initial_hp and not sim.impacts.is_empty(), "no HP loss during flight")
	sim.tick()
	assert(sim.units[target].hp == initial_hp - 20, "damage lands at projectile arrival")
	# All new action selections read old modes, never another choice made in the same tick.
	sim.reset()
	sim.squads[0].pos = Vector2(420, 335)
	for u in sim.units: u.rules = []
	sim.units[1].rules = [["火球", "无"]]
	sim.units[5].rules = [["箭击", "目标正在施法"]]
	sim.choose_actions()
	assert(sim.units[1].mode == "施法" and sim.units[5].mode == "待机")
	validate_new_mechanics()
	var output := FileAccess.open("res://reports/squad-validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": ["deterministic replay", "formation bounds and walls", "same-arena task variants", "cross-squad combo causality", "cross-squad healing", "range filtering", "result freeze", "flank navigation", "no damage during flight", "snapshot action selection", "bounded WAIT and early wake", "two conditions on same target", "cooldown fallback", "PP competition and recovery", "task retreat override", "snapshot isolation", "WAIT gives up immediate damage for later burst in an isolated fixture"], "outcomes": outcomes}, "\t"))
	print("SQUAD VALIDATION PASS")
	quit()

func isolated():
	var sim = Sim.new(); sim.reset()
	for s in sim.squads: s.task = "原地驻守"
	for u in sim.units: u.rules = []; u.pp_rules = []
	sim.squads[0].pos = Vector2(420, 335)
	sim.squads[1].pos = Vector2(640, 400)
	return sim

func setup_wait():
	var sim = isolated()
	var shield: Dictionary = sim.units[0]
	shield.mode = "施法"; shield.skill = "牵制"; shield.target = 4
	shield.release = 0.5; shield.ready = 1.5
	sim.units[2].rules = [["协同突袭", "目标被牵制", "无"], ["等待牵制", "无", "无"], ["突刺", "无", "无"]]
	sim.choose_actions()
	assert(sim.units[2].mode == "等待")
	return sim

func validate_new_mechanics() -> void:
	var sim = setup_wait()
	for i in range(10): sim.tick()
	assert(sim.units[2].mode == "施法" and sim.units[2].skill == "协同突袭", "waiting must wake in same tick as taunt lands")
	assert(sim.events.any(func(e): return e.kind == "等待结束" and "提前" in e.text))
	# Cancel the promised ally action; waiting must expire, not renew indefinitely.
	sim = setup_wait(); sim.units[0].mode = "待机"
	for i in range(20): sim.tick()
	assert(sim.units[2].mode != "等待")
	assert(sim.units[2].skill == "突刺" or sim.units[2].mode == "待机")
	# Missing fallback still cannot re-enter WAIT when its original promise persists.
	sim = setup_wait(); sim.units[2].rules[2] = ["留空", "无", "无"]
	sim.units[0].release = 1.5
	for i in range(25): sim.tick()
	assert(sim.units[2].mode != "等待" and sim.units[2].wait_spent)
	# Truth of a condition does not imply availability: CD falls through to next action.
	sim = isolated(); sim.squads[1].pos = Vector2(630, 390); sim.units[4].taunt_until = 5.0
	sim.units[2].rules = [["协同突袭", "目标被牵制", "无"], ["突刺", "无", "无"]]
	sim.units[2].cooldowns["协同突袭"] = 5.0
	sim.choose_actions()
	assert(sim.units[2].checks[0].condition_ok and sim.units[2].checks[0].cooldown == 5.0)
	assert(sim.units[2].checks[1].chosen, "unavailable higher rule must not trap execution")
	# Two target conditions must match the SAME enemy, not separate enemies.
	sim = isolated(); sim.units[4].taunt_until = 5.0; sim.units[5].mode = "施法"
	var row: Dictionary = sim.assessment(1, ["火球", "目标被牵制", "目标正在施法"], 0)
	assert(not row.condition_ok)
	sim.units[4].mode = "施法"
	assert(sim.assessment(1, ["火球", "目标被牵制", "目标正在施法"], 0).condition_ok)
	# Shared PP, intrinsic event stage, and no interruption of active/waiting action.
	sim = isolated(); sim.units[0].pp_rules = [["援护", "无", "无"], ["格挡", "无", "无"]]
	sim.units[0].mode = "等待"
	sim.react_before(1, 0)
	assert(sim.units[1].shield == 26 and sim.units[0].pp_points == 1)
	sim.react_before(0, 1)
	assert(sim.units[0].shield == 18 and sim.units[0].pp_points == 0 and sim.units[0].mode == "等待")
	sim.units[0].pp_cooldowns.clear(); sim.react_before(1, 2)
	assert(sim.units[1].shield == 26, "zero PP must prevent further reactions")
	sim.units[0].mode = "待机"
	for i in range(160): sim.tick()
	assert(sim.units[0].pp_points == 1, "PP recovers one point each eight world seconds")
	# Conditional task override is stable until recovery, and never edits character rules.
	sim = isolated(); sim.squads[0].exception = "小队HP≤35% → 撤回部署区"
	sim.units[0].hp = 20; sim.units[1].hp = 20
	var old: Vector2 = sim.squads[0].pos
	sim.tick()
	assert(sim.squads[0].retreating and sim.squads[0].pos.x < old.x)
	sim.units[0].hp = 210; sim.units[1].hp = 100; sim.tick()
	assert(not sim.squads[0].retreating)
	# Saved snapshots are copies and never mutate/resume the live simulation.
	var state: Dictionary = sim.snapshot()
	var view = Sim.new(); view.load_view(state, sim.events)
	view.units[0].hp = 1
	assert(sim.units[0].hp == 210 and state.units[0].hp == 210)
	# A genuine opportunity cost: same target, immediate weak hit vs later stronger hit.
	var delayed = setup_wait(); var immediate = setup_wait()
	for fight in [delayed, immediate]:
		fight.squads[1].pos = Vector2(630, 390); fight.units[5].hp = 0
	immediate.units[2].mode = "待机"; immediate.units[2].wait_spent = false
	immediate.units[2].rules[1] = ["留空", "无", "无"]; immediate.choose_actions()
	for i in range(8): delayed.tick(); immediate.tick()
	assert(delayed.units[4].hp == 180 and immediate.units[4].hp == 166)
	for i in range(16): delayed.tick(); immediate.tick()
	assert(delayed.units[4].hp == 148 and immediate.units[4].hp == 166)
	print("NEW TACTICS PASS: bounded WAIT, two-condition AND, cooldown fallback, PP competition, task exception, read-only snapshots")
