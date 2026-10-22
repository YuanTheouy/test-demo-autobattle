extends RefCounted
const Beat = preload("res://scripts/beat_simulation.gd")
const Cases = preload("res://scripts/beat_validation.gd")

static func fixture(game):
	var sim = Cases.fixture(game)
	sim.units[2].cell = Vector2i(4, 3)
	sim.units[2].p = Beat.center(sim.units[2].cell)
	return sim

static func strike(sim, target: int, skill: String) -> void:
	sim.strikes.append({"cells": [sim.units[target].cell], "at": sim.beat + 1, "team": 1 - sim.units[target].team, "source": 2 if target < 2 else 0, "skill": skill, "damage": sim.damage_of(skill)})

static func run(game) -> Dictionary:
	var report := {"max_hp": Beat.MAX_HP, "skill_damage": Beat.DAMAGE, "attack_results": [], "checks": []}
	# Exercise real attack phases and emitted hits, including delayed thorns.
	for skill in Beat.DAMAGE:
		var sim = fixture(game)
		sim.start_attack(sim.units[0], 2, skill, sim.units[2].cell)
		for tick in range(24):
			sim.tick()
			for u in sim.units:
				assert(typeof(u.hp) == TYPE_INT and u.hp >= 0 and u.hp <= Beat.MAX_HP)
				assert(typeof(u.shield) == TYPE_INT)
		var count: int = Beat.Tactics.MAGIC.get(skill, {}).get("hits", 1)
		var expected: int = 2 if skill == "荆棘" else sim.damage_of(skill) * count
		assert(sim.units[2].hp == maxi(0, Beat.MAX_HP - expected), "Wrong total damage for " + skill)
		report.attack_results.append({"skill": skill, "hits": count, "total_damage": expected, "remaining_hp": sim.units[2].hp})
	report.checks.append("every attack uses real phases; integer HP/shields; burst totals and two thorn ticks")
	var sim = fixture(game)
	for hit in range(Beat.MAX_HP):
		strike(sim, 2, "点射")
		sim.tick()
		assert(sim.units[2].hp == Beat.MAX_HP - 1 - hit)
		assert(sim.finished == (hit == Beat.MAX_HP - 1))
	assert(sim.winner == 0)
	report.checks.append("exactly two ordinary hits kill a full-health bot")
	for skill in ["点射", "落岩", "火矢", "蓄能贯穿"]:
		sim = fixture(game)
		sim.units[2].guard = 1.0
		strike(sim, 2, skill)
		sim.tick()
		var reduction := 0 if skill in ["火矢", "蓄能贯穿"] else Beat.GUARD_REDUCTION
		assert(sim.units[2].hp == maxi(0, Beat.MAX_HP - maxi(0, sim.damage_of(skill) - reduction)))
		sim = fixture(game)
		sim.units[2].shield = 1
		sim.units[2].shield_time = 2.0
		strike(sim, 2, skill)
		sim.tick()
		assert(sim.units[2].hp == maxi(0, Beat.MAX_HP - maxi(0, sim.damage_of(skill) - 1)) and sim.units[2].shield == 0)
	sim = fixture(game)
	sim.units[2].marked = 5.0
	strike(sim, 2, "强力射击")
	sim.tick()
	assert(sim.units[2].hp == maxi(0, Beat.MAX_HP - 3))
	report.checks.append("guard subtracts one per physical hit; true damage bypasses guard; shield absorbs both; mark adds one")
	for skill in ["回春", "灵木护佑"]:
		sim = fixture(game)
		sim.units[0].hp = Beat.MAX_HP - 1
		sim.units[0].hurt_recent = 1.0
		sim.loadouts[0].reaction = [[skill, "无", "无"]]
		sim.tick()
		assert(sim.units[0].hp == Beat.MAX_HP and sim.units[0].frame_triggers == 1)
		assert(sim.units[0].shield == (1 if skill == "灵木护佑" else 0))
		# Full-health recipients must not consume a healing action.
		sim = fixture(game)
		sim.units[0].hurt_recent = 1.0
		sim.loadouts[0].reaction = [[skill, "无", "无"]]
		sim.tick()
		assert(sim.units[0].hp == Beat.MAX_HP and sim.units[0].frame_triggers == 0)
	sim = fixture(game)
	sim.units[1].hp = Beat.MAX_HP
	sim.units[1].cell = Vector2i(2, 4)
	sim.units[1].p = Beat.center(sim.units[1].cell)
	sim.units[1].shield = 1
	sim.units[1].shield_time = 2.0
	sim.loadouts[0].reaction = [["掩护队友", "无", "无"]]
	sim.strikes.append({"cells": [sim.units[1].cell], "at": 2, "team": 1, "source": 2, "skill": "落岩", "damage": 2})
	sim.tick()
	assert(sim.units[1].shield == 2 and sim.units[0].frame_triggers == 1)
	sim.tick()
	sim.tick()
	assert(sim.units[1].hp == Beat.MAX_HP and sim.units[1].shield == 0)
	report.checks.append("healing caps at two; wood grants one shield; ally cover replaces one shield with two and absorbs a heavy hit")
	sim = fixture(game)
	for hp in range(1, Beat.MAX_HP + 1):
		sim.units[0].hp = hp
		assert(sim.condition(sim.units[0], 2, "自己HP≤2", sim.units) == (hp <= 2))
	game.team_presets = [0, 4]
	game.setup_loadouts()
	game.rebuild_editor()
	for loadout in game.loadouts:
		for kind in ["active", "reaction"]:
			for rule in loadout[kind]:
				assert("自己HP≤50" not in rule and "队友HP≤50" not in rule)
	game.choose_editor_unit(0)
	game.edit_rule_cell(0, 1, "自己HP≤2")
	game.rebuild_editor()
	assert(game.loadouts[0].active[0][1] == "自己HP≤2")
	for row in game.editor_rows:
		for column in [1, 2]:
			var menu: OptionButton = row.menus[column]
			for item in range(menu.item_count): assert("HP≤50" not in menu.get_item_text(item))
	report.checks.append("low-health threshold is two; presets, editor persistence and menus use the new condition")
	return report
