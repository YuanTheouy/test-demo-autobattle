extends SceneTree
## Search existing presets/spawns for visible shots and a prediction finish without dodge. No rule changes.
const Beat = preload("res://scripts/beat_simulation.gd")
func _initialize(): call_deferred("search")
func play(game, a, b, p, q):
	var source = game.units.duplicate(true)
	for u in source:
		u.hp = Beat.MAX_HP if u.uid in [0,2] else 0
		if u.uid in [0,2]: u.p = Beat.center(p if u.uid == 0 else q)
	var rules = [game.preset_loadouts(a)[0], {"active":[],"reaction":[]},game.preset_loadouts(b)[0],{"active":[],"reaction":[]}]
	var sim = Beat.new()
	sim.reset(source,rules,game.walls)
	var counts = {"shots":[0,0],"dodges":[0,0],"hits":[0,0],"prediction_hits":0,"collisions":0}
	var trace = []
	for i in range(240):
		var before = sim.units.duplicate(true)
		sim.tick()
		var actions = []
		for uid in [0,2]:
			var u = sim.units[uid]
			if u.phase == "侧闪跨格": counts.dodges[uid / 2] += 1
			if u.mode == "碰撞": counts.collisions += 1
			actions.append({"id":uid,"cell":Beat.name_of(u.cell),"phase":u.phase,"hp":u.hp,"cd":u.skill_cds.get("侧闪",0)/Beat.SECONDS})
		for effect in sim.effects:
			var uid = effect.source
			if uid not in [0,2]: continue
			counts.shots[uid / 2] += 1
			var other = 2 if uid == 0 else 0
			var hit = sim.units[other].cell in effect.cells and before[other].hp > 0
			if hit:
				counts.hits[uid / 2] += 1
				var slot = sim.units[uid].rule_slot
				if slot >= 0 and "沿移动方向预判1格" in rules[uid].active[slot]: counts.prediction_hits += 1
			actions.append({"shot":uid,"cell":str(effect.cells),"hit":hit})
		trace.append({"beat":sim.beat,"actions":actions})
		if sim.finished: break
	return {"presets":[a,b],"spawns":[[p.x,p.y],[q.x,q.y]],"beats":sim.beat,"winner":sim.winner,"counts":counts,"trace":trace}
func search():
	var game = load("res://puzzle_arena.tscn").instantiate()
	root.add_child(game)
	var picks = []
	var total = 0
	for opponent in [9,10,11,12,13,14]:
		for x in range(5,8):
			for y in range(5,8):
				for xx in range(5,8):
					for yy in range(5,8):
						if x == xx and y == yy: continue
						var r = play(game,14,opponent,Vector2i(x,y),Vector2i(xx,yy))
						total += 1
						var c = r.counts
						if c.prediction_hits > 0 and c.hits[0] > 0 and c.hits[1] > 0 and c.shots[0] >= 2 and c.shots[1] >= 2 and c.dodges == [0,0] and c.collisions == 0 and r.winner >= 0 and r.beats >= 12 and r.beats <= 60: picks.append(r)
	picks.sort_custom(func(a,b): return abs(a.beats - 24) < abs(b.beats - 24))
	print("SEARCH ",total," matches; watchable ",picks.size())
	var report = {"tested":total,"eligible":picks.size(),"max_hp": Beat.MAX_HP, "beat_limit": 240, "best":picks.slice(0,3), "demo": play(game,14,10,Vector2i(5,5),Vector2i(7,7)), "without_prediction": play(game,12,10,Vector2i(5,5),Vector2i(7,7))}
	var file = FileAccess.open("res://reports/duel-watchable.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	for r in [report.demo]: print("SELECTED ", r.presets, " ", r.spawns, " beats=", r.beats, " counters=",r.counts)
	print("WITHOUT PREDICTION: ",report.without_prediction.beats," beats; winner=",report.without_prediction.winner, " counters=",report.without_prediction.counts)
	quit()
