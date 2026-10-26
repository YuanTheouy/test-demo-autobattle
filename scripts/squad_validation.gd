extends SceneTree
const Sim = preload("res://scripts/squad_simulation.gd")

func _initialize() -> void:
	validate_flow()
	validate_wait()
	validate_reactions()
	var baseline := run_case(Sim.defaults())
	assert(baseline == run_case(Sim.defaults()), "identical setup must replay exactly")
	assert(baseline.combos > 0, "ordinary attacks must actually follow cross-squad state conditions")
	for event in baseline.events:
		if event.kind == "连携":
			assert(event.causes.size() == 2)
			var cause: Dictionary = baseline.events[event.causes[1] - 1]
			assert(cause.kind == "牵制" and cause.target == event.target)
	var held := Sim.defaults(); held.tasks[1] = "原地驻守"
	var support := Sim.defaults(); support.tasks[1] = "支援A队"
	var immediate := Sim.defaults(); immediate.programs[2] = Sim.action("重刺")
	var outcomes := {"default": baseline, "hold": run_case(held), "support": run_case(support), "immediate_heavy": run_case(immediate)}
	var file := FileAccess.open("res://reports/squad-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": ["real IF/THEN/ELSE and second IF", "condition truth separated from skill availability", "one condition per IF; nested target scope", "snapshot decision isolation", "generic WAIT, early wake, timeout and no renewal", "WAIT works for casting predicate too", "same ordinary skill has identical damage with or without coordination", "PP stage/priority/resource recovery while waiting", "formation bounds/walls", "deterministic replay", "projectile arrival timing", "cross-squad state causality", "task exception and snapshot isolation"], "outcomes": outcomes}, "\t"))
	print("SQUAD FLOW VALIDATION PASS: true branches, generic WAIT, ordinary damage, PP and deterministic battlefield")
	quit()

func run_case(settings: Dictionary) -> Dictionary:
	var sim = Sim.new(); sim.reset(settings)
	while not sim.finished:
		sim.tick()
		for u in sim.units:
			var p: Vector2 = sim.pos(u.id)
			assert(p.x >= 20 and p.x <= 900 and p.y >= 65 and p.y <= 615)
			for wall in Sim.WALLS: assert(not wall.grow(20).has_point(p))
	var stopped: Dictionary = sim.summary(); sim.tick()
	assert(sim.summary() == stopped)
	return stopped

func isolated():
	var sim = Sim.new(); sim.reset()
	for s in sim.squads: s.task = "原地驻守"
	for u in sim.units: u.program = Sim.action("留空"); u.pp_rules = []
	sim.squads[0].pos = Vector2(420, 335)
	sim.squads[1].pos = Vector2(630, 390)
	sim.units[5].hp = 0
	return sim

func validate_flow() -> void:
	var sim = isolated()
	sim.units[2].program = Sim.branch("目标被牵制", Sim.action("重刺"), Sim.action("突刺"))
	sim.choose_actions()
	assert(sim.units[2].skill == "突刺" and sim.units[2].checks[0].branch == "ELSE")
	sim = isolated(); sim.units[4].taunt_until = 5.0
	sim.units[2].program = Sim.branch("目标被牵制", Sim.action("重刺"), Sim.action("突刺"))
	sim.units[2].cooldowns["重刺"] = 5.0
	sim.choose_actions()
	assert(sim.units[2].mode == "待机" and sim.units[2].checks[0].branch == "THEN")
	assert(sim.units[2].checks.back().cooldown == 5.0 and not sim.units[2].checks.back().chosen)
	assert(not sim.events.any(func(e): return e.kind == "AP" and e.actor == 2), "true + cooling must not silently execute ELSE")
	sim = isolated()
	sim.units[2].program = Sim.branch("目标被牵制", Sim.action("重刺"), Sim.branch("自己无护盾", Sim.action("突刺"), Sim.action("留空")))
	sim.choose_actions()
	assert(sim.units[2].skill == "突刺" and sim.units[2].branch_path == "root.else.then")
	sim = isolated(); sim.units[4].taunt_until = 5.0; sim.units[6].mode = "施法"
	sim.units[2].program = Sim.branch("目标被牵制", Sim.branch("目标正在施法", Sim.action("重刺"), Sim.action("留空")), Sim.action("突刺"))
	sim.choose_actions()
	assert(sim.units[2].mode == "待机" and sim.units[2].checks[1].branch == "ELSE")
	sim.units[4].mode = "施法"; sim.choose_actions()
	assert(sim.units[2].skill == "重刺" and sim.units[2].target == 4)
	for check in sim.units[2].checks:
		if check.kind == "IF": assert(check.condition is String and not check.has("condition2"))
	sim = isolated()
	sim.units[1].program = Sim.action("火球")
	sim.units[4].program = Sim.branch("目标正在施法", Sim.action("盾击"), Sim.action("留空"))
	sim.choose_actions()
	assert(sim.units[1].mode == "施法" and sim.units[4].mode == "待机")
	var target: int = sim.units[1].target
	var hp: float = sim.units[target].hp
	for tick in range(25): sim.tick()
	assert(sim.units[target].hp == hp and not sim.impacts.is_empty())
	sim.tick(); assert(sim.units[target].hp == hp - 20)
	assert("协同突袭" not in Sim.options("刺客") and "等待牵制" not in Sim.options("刺客"))
	assert(not Sim.SKILLS.has("等待") and not Sim.SKILLS.has("协同突袭"))
	var nested := Sim.branch("无", Sim.branch("无", Sim.branch("无", Sim.action("重刺"), Sim.action("重刺")), Sim.action("突刺")), Sim.action("突刺"))
	assert(Sim.clean_program(nested, "刺客")["then"]["then"].type == "skill")

func setup_wait():
	var sim = isolated()
	var shield: Dictionary = sim.units[0]
	shield.mode = "施法"; shield.skill = "牵制"; shield.target = 4; shield.release = 0.5; shield.ready = 1.5
	sim.units[2].program = Sim.branch("目标被牵制", Sim.action("重刺"), Sim.wait_action())
	sim.choose_actions()
	assert(sim.units[2].mode == "等待")
	return sim

func validate_wait() -> void:
	var sim = setup_wait()
	for tick in range(10): sim.tick()
	assert(sim.units[2].mode == "施法" and sim.units[2].skill == "重刺")
	assert(sim.events.any(func(e): return e.kind == "等待结束" and "提前满足" in e.text))
	for tick in range(14): sim.tick()
	assert(sim.units[4].hp == 156, "ordinary heavy strike does exactly 24, no scripted combo bonus")
	assert(sim.events.any(func(e): return e.kind == "连携" and e.actor == 2))
	sim = setup_wait(); sim.units[0].release = 1.0; sim.units[0].ready = 2.0
	for tick in range(20): sim.tick()
	assert(sim.units[2].skill == "重刺" and sim.units[2].branch_path.ends_with("满足"), "condition met exactly at deadline takes success exit")
	sim = setup_wait(); sim.units[0].mode = "待机"
	for tick in range(20): sim.tick()
	assert(sim.units[2].mode == "施法" and sim.units[2].skill == "突刺" and sim.units[2].branch_path.ends_with("超时"))
	sim = setup_wait(); sim.units[0].mode = "待机"
	sim.units[2].wait_node.timeout = Sim.action("留空")
	sim.units[2].program["else"].timeout = Sim.action("留空")
	for tick in range(40): sim.tick()
	assert(sim.units[2].mode == "待机" and sim.units[2].wait_spent)
	assert(sim.events.filter(func(e): return e.kind == "等待" and e.actor == 2).size() == 1)
	sim = isolated(); sim.units[2].pending_action = Sim.action("重刺"); sim.units[2].pending_scope = [4]
	sim.units[4].hp = 0; sim.choose_actions()
	assert(sim.units[2].pending_action.is_empty(), "a target lost after WAIT cannot permanently trap the actor")
	sim = isolated(); sim.units[2].program = Sim.wait_action("目标正在施法")
	sim.choose_actions()
	for tick in range(6): sim.tick()
	sim.units[4].mode = "施法"; sim.units[4].skill = "盾击"; sim.units[4].release = 5.0; sim.units[4].ready = 6.0
	sim.choose_actions()
	assert(sim.units[2].mode == "施法" and sim.units[2].skill == "重刺")
	var immediate = isolated(); immediate.units[2].program = Sim.action("重刺"); immediate.choose_actions()
	for tick in range(14): immediate.tick()
	assert(immediate.units[4].hp == 156, "unconditional same skill must have identical damage")
	var delayed = setup_wait(); immediate = isolated(); immediate.units[2].program = Sim.action("重刺"); immediate.choose_actions()
	for tick in range(16): delayed.tick(); immediate.tick()
	assert(delayed.units[4].hp == 180 and immediate.units[4].hp == 156, "WAIT actually gives up earlier damage")

func validate_reactions() -> void:
	var sim = isolated(); sim.units[0].pp_rules = [["援护", "无"], ["格挡", "无"]]
	sim.units[0].mode = "等待"; sim.units[0].wait_node = Sim.wait_action(); sim.units[0].wait_until = 30
	sim.react_before(1, 1)
	assert(sim.units[1].shield == 26 and sim.units[0].pp_points == 1)
	sim.react_before(0, 2)
	assert(sim.units[0].shield == 18 and sim.units[0].pp_points == 0 and sim.units[0].mode == "等待")
	sim.units[0].pp_cooldowns.clear(); sim.react_before(1, 3)
	assert(sim.units[1].shield == 26)
	sim.units[0].mode = "待机"
	for tick in range(160): sim.tick()
	assert(sim.units[0].pp_points == 1)
	sim = isolated(); sim.squads[0].exception = "小队HP≤35% → 撤回部署区"
	sim.units[0].hp = 20; sim.units[1].hp = 20
	var old: Vector2 = sim.squads[0].pos; sim.tick()
	assert(sim.squads[0].retreating and sim.squads[0].pos.x < old.x)
	sim.units[0].hp = 210; sim.units[1].hp = 100; sim.tick()
	assert(not sim.squads[0].retreating)
	var state: Dictionary = sim.snapshot(); var view = Sim.new(); view.load_view(state, sim.events)
	view.units[0].hp = 1
	assert(sim.units[0].hp == 210 and state.units[0].hp == 210)
