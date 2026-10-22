extends SceneTree
## Deterministic strategy search against the real 3x3 combat engine. No balance changes.
const Beat = preload("res://scripts/beat_simulation.gd")
var source: Array
var walls: Array
var candidates: Array = []
var games := 0
var result_cache: Dictionary = {}
var started_ms := 0

func _initialize() -> void:
	call_deferred("run")

func rules(active: Array, dodge: bool) -> Dictionary:
	return {"active": active.duplicate(true), "reaction": [["侧闪", "无", "无"]] if dodge else []}

func add_pair(label: String, active: Array) -> void:
	for dodge in [false, true]:
		candidates.append({"name": label + ("＋侧闪" if dodge else ""), "rules": rules(active, dodge)})

func build_candidates() -> void:
	var gun := ["普通攻击", "无", "无"]
	add_pair("原地吊射", [gun])
	add_pair("先打再接敌", [gun, ["接敌", "无", "无"]])
	add_pair("先打再远敌", [gun, ["远敌", "无", "无"]])
	add_pair("无条件接敌优先", [["接敌", "无", "无"], gun])
	add_pair("无条件远敌优先", [["远敌", "无", "无"], gun])
	for amount in [2, 3, 4]:
		add_pair("距离≥%d接敌" % amount, [["接敌", "敌人距离≥%d格" % amount, "无"], gun])
	for amount in [1, 2, 3]:
		add_pair("距离≤%d远敌" % amount, [["远敌", "敌人距离≤%d格" % amount, "无"], gun])
	for near in [1, 2]:
		for far in [3, 4]:
			var retreat := ["远敌", "敌人距离≤%d格" % near, "无"]
			var approach := ["接敌", "敌人距离≥%d格" % far, "无"]
			add_pair("先退后进%d-%d" % [near, far], [retreat, approach, gun])
			add_pair("先进后退%d-%d" % [near, far], [approach, retreat, gun])
	for direction in ["向上移动", "向下移动", "向左移动", "向右移动"]:
		for condition in ["无", "敌人距离≤1格", "敌人距离≥3格"]:
			add_pair(direction + "优先/" + condition, [[direction, condition, "无"], gun])
	add_pair("收招反击再接敌", [["普通攻击", "敌人正在收招", "无"], ["接敌", "无", "无"]])
	add_pair("收招反击再远敌", [["普通攻击", "敌人正在收招", "无"], ["远敌", "无", "无"]])
	for threshold in [50, 80]:
		add_pair("精力≥%d吊射" % threshold, [["普通攻击", "自己精力≥%d" % threshold, "无"], ["接敌", "无", "无"]])

func match_game(a: int, b: int, p: Vector2i, q: Vector2i, trace := false) -> Dictionary:
	var key := "%d:%d:%s:%s" % [a, b, p, q]
	if not trace and result_cache.has(key): return result_cache[key]
	var units := source.duplicate(true)
	for u in units:
		u.hp = 5 if u.uid in [0, 2] else 0
		if u.uid == 0: u.p = Beat.center(p)
		elif u.uid == 2: u.p = Beat.center(q)
	var loadouts := [candidates[a].rules.duplicate(true), rules([], false), candidates[b].rules.duplicate(true), rules([], false)]
	var sim = Beat.new()
	sim.reset(units, loadouts, walls)
	var timeline: Array = []
	var counters := {"shots": [0, 0], "dodges": [0, 0], "moves": [0, 0], "collision_beats": 0}
	for tick in range(240):
		var old: Array = sim.units.duplicate(true)
		sim.tick()
		for index in range(2):
			var uid := index * 2
			var u: Dictionary = sim.units[uid]
			if u.phase == "释放硬直": counters.shots[index] += 1
			if u.phase == "侧闪跨格": counters.dodges[index] += 1
			if u.cell != old[uid].cell: counters.moves[index] += 1
		if sim.units[0].mode == "碰撞" or sim.units[2].mode == "碰撞": counters.collision_beats += 1
		if trace:
			timeline.append({"beat": sim.beat, "bots": [0, 2].map(func(uid):
				var u: Dictionary = sim.units[uid]
				return {"cell": Beat.name_of(u.cell), "hp": u.hp, "energy": u.energy, "posture": Beat.posture_label(u), "phase": u.phase, "rule": u.rule, "next": sim.next_segment.units[uid].phase})})
		if sim.finished: break
	var result := {"winner": sim.winner, "beats": sim.beat, "hp": [sim.units[0].hp, sim.units[2].hp], "reason": sim.result, "counters": counters}
	if trace: result.timeline = timeline
	else:
		games += 1
		result_cache[key] = result
	return result

func score_results(ids: Array, positions: Array) -> Dictionary:
	var stats: Dictionary = {}
	var matrix: Dictionary = {}
	for id in ids: stats[id] = {"id": id, "name": candidates[id].name, "wins": 0, "draws": 0, "losses": 0, "beats": 0, "score": 0.0}
	for a in ids:
		matrix[a] = {}
		for b in ids:
			if a == b: continue
			var row := {"wins": 0, "draws": 0, "losses": 0}
			for pair in positions:
				for swapped in [false, true]:
					var result := match_game(b if swapped else a, a if swapped else b, pair[0], pair[1])
					var own_team := 1 if swapped else 0
					var category := "draws" if result.winner == -1 else ("wins" if result.winner == own_team else "losses")
					row[category] += 1
					stats[a][category] += 1
					stats[a].beats += result.beats
			matrix[a][b] = row
		if positions.size() > 2: print("FINAL ", candidates[a].name, " games=", games)
		var total: int = stats[a].wins + stats[a].draws + stats[a].losses
		stats[a].score = (stats[a].wins + stats[a].draws * 0.5) / maxf(1, total)
	var ranking: Array = stats.values()
	ranking.sort_custom(func(a, b): return a.score > b.score if a.score != b.score else (a.wins > b.wins if a.wins != b.wins else a.id < b.id))
	return {"ranking": ranking, "matrix": matrix}

func run() -> void:
	started_ms = Time.get_ticks_msec()
	var game = load("res://puzzle_arena.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	source = game.units.duplicate(true)
	walls = game.walls.duplicate()
	build_candidates()
	if "--duel-followup" in OS.get_cmdline_user_args():
		run_followup()
		return
	var anchors := [0, 1, 3, 7, 9, 23]
	var baseline := [[Vector2i(5, 6), Vector2i(7, 6)], [Vector2i(7, 6), Vector2i(5, 6)]]
	var scout: Array = []
	for id in range(candidates.size()):
		var row := {"id": id, "name": candidates[id].name, "wins": 0, "draws": 0, "losses": 0, "score": 0.0}
		for anchor in anchors:
			for pair in baseline:
				for swapped in [false, true]:
					var result := match_game(anchor if swapped else id, id if swapped else anchor, pair[0], pair[1])
					var own_team := 1 if swapped else 0
					var category := "draws" if result.winner == -1 else ("wins" if result.winner == own_team else "losses")
					row[category] += 1
		row.score = (row.wins + row.draws * 0.5) / 24.0
		scout.append(row)
		if id % 8 == 7: print("SCOUT ", id + 1, "/", candidates.size(), " games=", games)
	scout.sort_custom(func(a, b): return a.score > b.score if a.score != b.score else (a.wins > b.wins if a.wins != b.wins else a.id < b.id))
	var shortlist: Array = anchors.duplicate()
	for item in scout.slice(0, 10):
		if item.id not in shortlist: shortlist.append(item.id)
	var screening := score_results(shortlist, baseline)
	print("SCREENING TOP ", JSON.stringify(screening.ranking.slice(0, 6)))
	var finalists: Array = []
	for item in screening.ranking.slice(0, 6): finalists.append(item.id)
	if 3 not in finalists: finalists.append(3)
	var positions: Array = []
	for x in range(5, 8):
		for y in range(5, 8):
			for xx in range(5, 8):
				for yy in range(5, 8):
					if Vector2i(x, y) != Vector2i(xx, yy): positions.append([Vector2i(x, y), Vector2i(xx, yy)])
	# Exhaust every distinct ordered spawn pair for each finalist matchup.
	var final := score_results(finalists, positions)
	var best: int = final.ranking[0].id
	var counters: Array = []
	var holdouts := [[Vector2i(5, 5), Vector2i(7, 7)], [Vector2i(7, 7), Vector2i(5, 5)], [Vector2i(6, 6), Vector2i(5, 6)], [Vector2i(5, 6), Vector2i(6, 6)]]
	for id in range(candidates.size()):
		if id == best: continue
		var row := {"id": id, "name": candidates[id].name, "wins": 0, "draws": 0, "losses": 0}
		for pair in holdouts:
			for swapped in [false, true]:
				var result := match_game(id if swapped else best, best if swapped else id, pair[0], pair[1])
				var own_team := 1 if swapped else 0
				row["draws" if result.winner == -1 else ("wins" if result.winner == own_team else "losses")] += 1
		counters.append(row)
	counters.sort_custom(func(a, b): return a.losses > b.losses if a.losses != b.losses else a.id < b.id)
	var examples: Array = []
	for id in [0, 1, 3, counters[0].id]:
		examples.append({"a": best, "b": id, "spawn": baseline[0], "result": match_game(best, id, baseline[0][0], baseline[0][1], true)})
	var report := {"scope": "finite candidate search, not a proof of globally optimal policy", "candidate_count": candidates.size(), "unique_matches": games,
		"source_head": "5327ed0afbc4783f99e501e881b16d577b7e3be5", "rules": {"hp": 5, "shot_damage": 1, "shot_cd": 6, "dodge_cd": 12, "energy_regen": 3, "timeout_beats": 240, "draw_score": 0.5},
		"candidates": candidates, "scout": scout, "screening": screening, "finalists": finalists, "spawn_pairs": positions.size(), "roles": "both colors for every candidate and spawn pair", "final": final,
		"winner_holdout_opponents": counters, "examples": examples, "elapsed_seconds": (Time.get_ticks_msec() - started_ms) / 1000.0}
	report.ranking_note = "Raw finalist pool includes equivalent configurations; use duel-strategy-followup.json for deduplicated rankings."
	var file := FileAccess.open("res://reports/duel-strategy-benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("BENCHMARK DONE ", games, " games / ", report.elapsed_seconds, " seconds\n", JSON.stringify(final.ranking))
	quit()

func run_followup() -> void:
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/duel-strategy-benchmark.json"))
	var groups: Dictionary = {}
	var ids: Array = []
	for id in previous.finalists:
		var config: Dictionary = candidates[int(id)].rules.duplicate(true)
		for row in config.active:
			# Adjacent occupied enemy cells cannot be entered, making these two rules equivalent.
			if row == ["接敌", "敌人距离≥2格", "无"]: row[1] = "无"
		var key := JSON.stringify(config)
		if not groups.has(key):
			groups[key] = []
			ids.append(int(id))
		groups[key].append(int(id))
	for group in groups.values():
		if group.size() < 2: continue
		for alias in group.slice(1):
			for opponent in previous.finalists:
				if int(opponent) in group: continue
				assert(previous.final.matrix[str(group[0])][str(int(opponent))] == previous.final.matrix[str(alias)][str(int(opponent))])
	var ranking: Array = []
	for a in ids:
		var row := {"id": a, "name": candidates[a].name, "wins": 0, "draws": 0, "losses": 0}
		for b in ids:
			if a == b: continue
			var pair: Dictionary = previous.final.matrix[str(a)][str(b)]
			for category in ["wins", "draws", "losses"]: row[category] += int(pair[category])
		var count: int = row.wins + row.draws + row.losses
		row.score = (row.wins + row.draws * 0.5) / count
		ranking.append(row)
	ranking.sort_custom(func(a, b): return a.score > b.score if a.score != b.score else a.wins > b.wins)
	var best: int = ranking[0].id
	var holdouts := [[Vector2i(5, 5), Vector2i(7, 7)], [Vector2i(7, 7), Vector2i(5, 5)], [Vector2i(6, 6), Vector2i(5, 6)], [Vector2i(5, 6), Vector2i(6, 6)]]
	var opponents: Array = []
	for id in range(candidates.size()):
		if id == best: continue
		var row := {"id": id, "name": candidates[id].name, "wins": 0, "draws": 0, "losses": 0}
		for pair in holdouts:
			for swapped in [false, true]:
				var result := match_game(id if swapped else best, best if swapped else id, pair[0], pair[1])
				var own_team := 1 if swapped else 0
				row["draws" if result.winner == -1 else ("wins" if result.winner == own_team else "losses")] += 1
		opponents.append(row)
		if id % 16 == 15: print("FOLLOWUP ", id + 1, "/", candidates.size())
	opponents.sort_custom(func(a, b): return a.losses > b.losses if a.losses != b.losses else a.id < b.id)
	var examples: Array = []
	for id in [0, 1, 3, 5, 7, opponents[0].id]:
		examples.append({"a": best, "b": id, "spawn": [Vector2i(5, 6), Vector2i(7, 6)], "result": match_game(best, id, Vector2i(5, 6), Vector2i(7, 6), true)})
	var replay: Dictionary = match_game(5, 0, Vector2i(5, 6), Vector2i(7, 6), true)
	assert(replay.winner == previous.examples[0].result.winner and replay.hp[0] == previous.examples[0].result.hp[0] and replay.hp[1] == previous.examples[0].result.hp[1] and replay.beats == previous.examples[0].result.beats)
	var report := {"distinct_finalists": ids, "equivalent_groups": groups.values(), "ranking": ranking,
		"leader_rules": candidates[best].rules, "leader_id": best, "leader_holdout_opponents": opponents,
		"followup_matches": games, "note": "Followup is a separate dataset; some finalist matchups repeat main-tournament states for verification", "deterministic_replay": true,
		"examples": examples, "elapsed_seconds": (Time.get_ticks_msec() - started_ms) / 1000.0}
	var file := FileAccess.open("res://reports/duel-strategy-followup.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FOLLOWUP DONE ", games, " games / ", report.elapsed_seconds, " seconds\n", JSON.stringify(ranking), "\nCOUNTERS ", JSON.stringify(opponents.slice(0, 6)))
	quit()
