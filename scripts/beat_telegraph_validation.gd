extends RefCounted
const Beat = preload("res://scripts/beat_simulation.gd")
const Telegraph = preload("res://scripts/beat_telegraph.gd")

static func fixture(game):
	game.reset_round()
	var source: Array = game.units.duplicate(true)
	var rules: Array = []
	for u in source:
		u.hp = 5 if u.uid in [0, 2] else 0
		u.p = Beat.center(Vector2i(2, 3) if u.uid == 0 else Vector2i(4, 3))
		rules.append({"active": [], "reaction": []})
	var sim = Beat.new()
	sim.reset(source, rules, [])
	return sim

static func run(game) -> Array:
	var checks: Array = []
	for duration in range(1, 6):
		var sample = fixture(game)
		sample.strikes.append({"cells": [Vector2i(3, 3)], "at": duration, "warn_from": 0, "team": 0, "source": 0, "skill": "落岩", "damage": 2})
		var warning: Dictionary = Telegraph.cells(sample, 0.0)[0]
		assert(warning.total_beats == duration)
		var cuts := Telegraph.divisions(warning.total_beats)
		assert(cuts.size() == duration - 1, "One segment per beat: 1 beat has no cuts; 2 beats has one cut")
		for boundary in range(cuts.size()): assert(is_equal_approx(cuts[boundary], float(boundary + 1) / duration))
		for elapsed_beat in range(duration):
			sample.beat = elapsed_beat
			warning = Telegraph.cells(sample, 0.0)[0]
			assert(warning.total_beats == duration and warning.remaining == duration - elapsed_beat)
			assert(is_equal_approx(warning.progress, float(elapsed_beat) / duration), "Each completed beat must fill exactly one segment")
		sample.beat = 0
		for beat in range(duration): sample.tick()
		var presentation = preload("res://scripts/beat_presentation.gd").new()
		presentation.reset(sample.units)
		presentation.begin(sample.units.duplicate(true), sample.units, sample)
		assert(presentation.bursts[0].total_beats == duration, "Impact flash must preserve the same divisions")
	checks.append("1/2/3/4/5 beats use 0/1/2/3/4 cuts; each segment is one beat; divisions remain fixed through countdown and impact")
	for skill in ["普通攻击", "蓄能贯穿", "抛射轰击", "风刃", "疾风连刃"]:
		var sim = fixture(game)
		sim.loadouts[0].active = [[skill, "无", "无"]]
		sim.tick()
		sim.loadouts[0].active.clear()
		var previous: Dictionary = {}
		var actual_hits := 0
		for tick in range(12):
			var start := Telegraph.cells(sim, 0.0)
			var middle := Telegraph.cells(sim, Beat.SECONDS / 2)
			var late := Telegraph.cells(sim, Beat.SECONDS * 20)
			assert(start.size() == middle.size() and start.size() == late.size())
			var state: Array = sim.units.duplicate(true)
			for index in range(start.size()):
				var warning: Dictionary = start[index]
				assert(warning.remaining == warning.due - sim.beat and warning.remaining >= 1)
				assert(middle[index].progress > warning.progress and late[index].progress < 1.0)
				assert(middle[index].remaining == warning.remaining)
				if previous.has(warning.cell) and previous[warning.cell].due == warning.due:
					assert(warning.total_beats == previous[warning.cell].total_beats, "Windup and flight must keep the same segment count")
					assert(warning.start == previous[warning.cell].start and warning.progress > previous[warning.cell].progress, "Release must never restart the warning timer")
			assert(sim.units == state, "Drawing warnings must not change the combat snapshot")
			previous.clear()
			for warning in late: previous[warning.cell] = warning
			sim.tick()
			for effect in sim.effects:
				actual_hits += 1
				for cell in effect.cells:
					assert(previous.has(cell) and previous[cell].due == sim.beat, "Warning deadline must equal the actual impact beat")
		assert(actual_hits == int(Beat.Tactics.MAGIC.get(skill, {}).get("hits", 1)))
	checks.append("basic/beam/mortar/bursts: exact impact deadlines; no restart between windup and flight; continuous fractional progress; every burst hit forecast")
	var sim = fixture(game)
	sim.loadouts[0].active = [["蓄能贯穿", "无", "无"]]
	sim.tick()
	assert(not Telegraph.cells(sim, 0.0).is_empty())
	sim.cancel(sim.units[0])
	assert(Telegraph.cells(sim, 0.0).is_empty())
	sim = fixture(game)
	sim.loadouts[0].active = [["火矢", "无", "无"]]
	sim.tick()
	sim.tick()
	sim.cancel(sim.units[0])
	assert(Telegraph.cells(sim, 0.0).size() == 1, "Recovery cancellation must keep a launched attack's warning")
	checks.append("windup cancellation removes warning; recovery cancellation preserves launched attacks")
	sim.units[0].hp = 0
	assert(Telegraph.cells(sim, 0.0).size() == 1, "An attack already in flight survives its caster")
	sim = fixture(game)
	sim.start_attack(sim.units[0], 2, "落岩", sim.units[2].cell)
	sim.units[0].hp = 0
	assert(Telegraph.cells(sim, 0.0).is_empty(), "Dead casters cannot release future shots")
	sim = fixture(game)
	sim.strikes.append({"cells": [Vector2i(3, 3)], "at": 1, "warn_from": 0, "team": 0, "source": 0, "skill": "落岩", "damage": 2})
	assert(Telegraph.cells(sim, 0.0)[0].progress == 0.0)
	assert(Telegraph.cells(sim, Beat.SECONDS / 2)[0].progress == 0.5)
	assert(Telegraph.cells(sim, Beat.SECONDS)[0].progress < 1.0)
	sim.tick()
	assert(Telegraph.cells(sim, 0.0).is_empty() and sim.effects.size() == 1)
	checks.append("one-beat warnings fill the whole edge; full bright frame only on the impact beat; dead casters keep launched shots but no future casts")
	sim = fixture(game)
	for data in [[0, 4], [0, 2], [1, 3]]:
		sim.strikes.append({"cells": [Vector2i(3, 3)], "at": data[1], "warn_from": 0, "team": data[0], "source": 0, "skill": "落岩", "damage": 2})
	var warnings := Telegraph.cells(sim, 0.1)
	assert(warnings.size() == 2)
	for warning in warnings: assert(warning.due == (2 if warning.team == 0 else 3))
	assert(Telegraph.cells(sim, 0.1) == warnings, "Paused clocks must produce an identical warning")
	checks.append("overlaps show nearest strike per team; both teams remain visible; paused display is stable; single-step never prematurely completes")
	return checks
