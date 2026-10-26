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
	var outcomes := {"flank": baseline, "support": run_case(support), "hold": run_case(held), "no_combo": run_case(no_combo)}
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
	for u in sim.units: u.rules = []; u.pp = "留空"
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
	var output := FileAccess.open("res://reports/squad-validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": ["deterministic replay", "formation bounds and walls", "same-arena task variants", "cross-squad combo causality", "cross-squad healing", "range filtering", "result freeze", "flank navigation", "no damage during flight", "snapshot action selection"], "outcomes": outcomes}, "\t"))
	print("SQUAD VALIDATION PASS")
	quit()
