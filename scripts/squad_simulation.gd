extends RefCounted
## Deterministic shared battlefield. Fixed step is numerical precision, not a player beat.
const DT := 0.05
const LIMIT := 55.0
const WALLS := [Rect2(405, 130, 35, 140), Rect2(405, 455, 35, 70)]
const TASKS := ["正面推进", "侧路突袭", "支援A队", "原地驻守"]
const CONDITIONS := ["无", "目标被牵制", "目标正在施法", "友军HP≤60%", "自己无护盾"]
const SKILLS := {
	"盾击": {"range": 100.0, "wind": 0.55, "flight": 0.0, "recover": 1.25, "cd": 2.0, "damage": 12.0},
	"牵制": {"range": 185.0, "wind": 0.5, "flight": 0.0, "recover": 1.0, "cd": 5.0, "damage": 0.0},
	"火球": {"range": 250.0, "wind": 0.9, "flight": 0.4, "recover": 1.5, "cd": 3.0, "damage": 20.0},
	"突刺": {"range": 115.0, "wind": 0.35, "flight": 0.0, "recover": 1.05, "cd": 1.8, "damage": 14.0},
	"协同突袭": {"range": 180.0, "wind": 0.55, "flight": 0.15, "recover": 1.3, "cd": 4.0, "damage": 14.0},
	"治疗": {"range": 260.0, "wind": 0.65, "flight": 0.2, "recover": 1.35, "cd": 4.0, "damage": -25.0},
	"光弹": {"range": 210.0, "wind": 0.65, "flight": 0.3, "recover": 1.4, "cd": 2.6, "damage": 10.0},
	"箭击": {"range": 230.0, "wind": 0.65, "flight": 0.35, "recover": 1.4, "cd": 2.7, "damage": 14.0},
	"雷击": {"range": 270.0, "wind": 1.4, "flight": 0.25, "recover": 1.8, "cd": 4.2, "damage": 27.0},
}
var squads: Array = []
var units: Array = []
var events: Array = []
var impacts: Array = []
var effects: Array = []
var clock := 0.0
var steps := 0
var finished := false
var result := ""
var sequence := 0
var combo_count := 0
var config: Dictionary = {}

static func defaults() -> Dictionary:
	return {"tasks": ["正面推进", "侧路突袭"], "rules": [
		[["牵制", "无"], ["盾击", "无"]],
		[["火球", "目标被牵制"], ["火球", "无"]],
		[["协同突袭", "目标被牵制"], ["突刺", "无"]],
		[["治疗", "友军HP≤60%"], ["光弹", "无"]]],
		"pp": ["援护", "留空", "留空", "回春"]}

static func options(role: String) -> Array:
	match role:
		"盾兵": return ["留空", "牵制", "盾击"]
		"法师": return ["留空", "火球"]
		"刺客": return ["留空", "协同突袭", "突刺"]
		_: return ["留空", "治疗", "光弹"]

static func conditions_for(skill: String) -> Array:
	if skill == "留空": return ["无"]
	if skill == "治疗": return ["无", "友军HP≤60%"]
	if skill == "牵制": return ["无", "自己无护盾", "目标正在施法"]
	return ["无", "目标被牵制", "目标正在施法"]

func reset(settings: Dictionary = {}) -> void:
	config = (defaults() if settings.is_empty() else settings).duplicate(true)
	clock = 0.0
	steps = 0
	sequence = 0
	combo_count = 0
	finished = false
	result = ""
	squads.clear(); units.clear(); events.clear(); impacts.clear(); effects.clear()
	var positions := [Vector2(135, 335), Vector2(140, 530), Vector2(595, 335), Vector2(755, 210)]
	var names := ["A · 盾法队", "B · 突袭队", "C · 守备队", "D · 雷法队"]
	for i in range(4):
		squads.append({"id": i, "team": 0 if i < 2 else 1, "name": names[i], "pos": positions[i],
			"task": config.tasks[i] if i < 2 else "原地驻守", "target": -1, "route": [], "phase": 0,
			"reason": "等待开始", "moving": false, "engaged": false})
	var roles := ["盾兵", "法师", "刺客", "牧师", "卫兵", "弓手", "卫兵", "雷法"]
	var health := [210.0, 100.0, 120.0, 100.0, 180.0, 100.0, 130.0, 100.0]
	for i in range(8):
		var rules: Array
		if i < 4: rules = config.rules[i].duplicate(true)
		else: rules = [["盾击" if i % 2 == 0 else ("箭击" if i == 5 else "雷击"), "无"]]
		units.append({"id": i, "squad": i / 2, "team": 0 if i < 4 else 1, "role": roles[i],
			"hp": health[i], "max_hp": health[i], "shield": 0.0, "rules": rules,
			"pp": config.pp[i] if i < 4 else "留空", "pp_cd": 0.0, "pp_until": 0.0,
			"taunt_until": 0.0, "taunt_source": -1, "taunt_event": -1, "cooldowns": {}, "mode": "待机", "skill": "", "slot": -1,
			"start": 0.0, "release": 0.0, "ready": 0.0, "target": -1, "why": "尚未选择技能"})
	log_event("部署", "A队正面接敌；B队沿下侧通道突袭。所有角色共享时间。", -1, -1)

func pos(uid: int) -> Vector2:
	var u: Dictionary = units[uid]
	var facing := 1.0 if u.team == 0 else -1.0
	return squads[u.squad].pos + Vector2(25 * facing if uid % 2 == 0 else -25 * facing, -14 if uid % 2 == 0 else 14)

func alive_squad(sid: int) -> bool:
	for u in units:
		if u.squad == sid and u.hp > 0: return true
	return false

func log_event(kind: String, message: String, actor: int, target: int, parent := -1) -> int:
	sequence += 1
	events.append({"id": sequence, "time": clock, "kind": kind, "text": message, "actor": actor, "target": target, "parent": parent})
	return sequence

func title(uid: int) -> String:
	return ["A", "B", "C", "D"][units[uid].squad] + "·" + units[uid].role

# Visibility graph with fixed vertex order and deterministic shortest-path tie breaking.
func clear_path(a: Vector2, b: Vector2) -> bool:
	for wall in WALLS:
		var expanded: Rect2 = wall.grow(49)
		if expanded.has_point(a) or expanded.has_point(b): return false
		var corners := [expanded.position, Vector2(expanded.end.x, expanded.position.y), expanded.end, Vector2(expanded.position.x, expanded.end.y)]
		for j in range(4):
			if Geometry2D.segment_intersects_segment(a, b, corners[j], corners[(j + 1) % 4]) != null: return false
	return true

func path_to(a: Vector2, b: Vector2) -> Array:
	b = b.clamp(Vector2(70, 180), Vector2(845, 565))
	if clear_path(a, b): return [b]
	var nodes: Array = [a, b]
	for wall in WALLS:
		var r: Rect2 = wall.grow(51)
		for v in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			if v.y >= 180 and v.y <= 585: nodes.append(v)
	var distance: Array = []; var previous: Array = []; var visited: Array = []
	for i in nodes.size(): distance.append(0.0 if i == 0 else INF); previous.append(-1); visited.append(false)
	for iteration in nodes.size():
		var best := -1
		for i in nodes.size():
			if not visited[i] and (best == -1 or distance[i] < distance[best]): best = i
		if best == -1 or distance[best] == INF: break
		visited[best] = true
		if best == 1: break
		for j in nodes.size():
			if visited[j] or not clear_path(nodes[best], nodes[j]): continue
			var cost: float = distance[best] + nodes[best].distance_to(nodes[j])
			if cost < distance[j] - 0.001: distance[j] = cost; previous[j] = best
	var route: Array = []; var at := 1
	if previous[at] == -1: return route
	while at != 0:
		route.push_front(nodes[at]); at = previous[at]
	return route

func nearest_enemy(sid: int) -> int:
	var selected := -1; var best := INF
	for s in squads:
		if s.team == squads[sid].team or not alive_squad(s.id): continue
		var d: float = squads[sid].pos.distance_to(s.pos)
		if d < best: best = d; selected = s.id
	return selected

func move_squads() -> void:
	var proposals: Array = []
	for s in squads:
		s.moving = false
		var old: Vector2 = s.pos
		if not alive_squad(s.id): proposals.append(old); continue
		if s.target < 0 or not alive_squad(s.target): s.target = nearest_enemy(s.id)
		if s.target < 0: proposals.append(old); continue
		var destination: Vector2 = old
		var enemy: Vector2 = squads[s.target].pos
		s.engaged = old.distance_to(enemy) <= 180
		if s.task == "原地驻守": s.reason = "驻守阵地，不追击"
		elif s.task == "侧路突袭" and s.phase < 2:
			var marks := [Vector2(350, 565), Vector2(765, 565)]
			destination = marks[s.phase]
			s.reason = "侧路 %d/2 → 绕过正面" % (s.phase + 1)
			if old.distance_to(destination) < 4:
				s.phase += 1
				if s.phase == 2:
					s.target = 2 if alive_squad(2) else nearest_enemy(s.id)
					log_event("任务", "%s完成绕行，从侧面攻击正面敌人" % s.name, -1, -1)
		elif s.task == "支援A队" and alive_squad(0):
			s.target = squads[0].target
			destination = (squads[0].pos + Vector2(-55, 100)).clamp(Vector2(70, 180), Vector2(845, 565))
			s.reason = "跟随A队侧后方，提供治疗与协同"
		else:
			if old.distance_to(enemy) > 100: destination = enemy + (old - enemy).normalized() * 98
			s.reason = "接近%s" % squads[s.target].name if destination != old else "保持交战距离"
		if old.distance_to(destination) > 3:
			var route := path_to(old, destination)
			s.route = route
			if not route.is_empty(): proposals.append(old.move_toward(route[0], 82 * DT))
			else: proposals.append(old); s.reason = "无可达路线，保持位置"
		else: proposals.append(old); s.route = []
	# Entire formations collide. A blocked squad waits rather than splitting its members.
	for i in squads.size():
		for j in range(i + 1, squads.size()):
			if alive_squad(i) and alive_squad(j) and proposals[i].distance_to(proposals[j]) < 86:
				proposals[i] = squads[i].pos; proposals[j] = squads[j].pos
	for i in squads.size():
		squads[i].moving = squads[i].pos.distance_to(proposals[i]) > 0.01
		squads[i].pos = proposals[i]

func candidates(uid: int, skill: String, condition: String) -> Array:
	var result_targets: Array = []
	if not SKILLS.has(skill): return result_targets
	var caster: Dictionary = units[uid]
	if condition == "自己无护盾" and caster.shield > 0: return result_targets
	for t in units:
		if t.hp <= 0: continue
		if skill == "治疗":
			if t.team != caster.team or t.hp >= t.max_hp: continue
			if condition == "友军HP≤60%" and t.hp / t.max_hp > 0.6: continue
		else:
			if t.team == caster.team: continue
			if condition == "目标被牵制" and t.taunt_until <= clock: continue
			if condition == "目标正在施法" and t.mode != "施法": continue
		if pos(uid).distance_to(pos(t.id)) <= SKILLS[skill].range: result_targets.append(t.id)
	result_targets.sort_custom(func(a, b):
		if skill == "治疗":
			var ah: float = units[a].hp / units[a].max_hp; var bh: float = units[b].hp / units[b].max_hp
			if not is_equal_approx(ah, bh): return ah < bh
		# A taunted unit attacks its taunter when that target is in this skill's range.
		if caster.taunt_until > clock:
			if a == caster.taunt_source: return true
			if b == caster.taunt_source: return false
		var ad := pos(uid).distance_squared_to(pos(a)); var bd := pos(uid).distance_squared_to(pos(b))
		return a < b if is_equal_approx(ad, bd) else ad < bd)
	return result_targets

func choose_actions() -> void:
	# All choices read the same post-impact snapshot; effects are applied in later ticks.
	var planned: Array = []
	for original in units:
		if original.hp <= 0 or original.mode != "待机": continue
		var u: Dictionary = original.duplicate(true)
		u.slot = -1
		var reasons: Array[String] = []
		for i in u.rules.size():
			var rule: Array = u.rules[i]; var skill: String = rule[0]
			if skill == "留空": continue
			if u.cooldowns.get(skill, 0.0) > clock:
				reasons.append("%s冷却%.1fs" % [skill, u.cooldowns[skill] - clock]); continue
			var targets := candidates(u.id, skill, rule[1])
			if targets.is_empty(): reasons.append("%s无符合条件的射程内目标" % skill); continue
			u.mode = "施法"; u.skill = skill; u.target = targets[0]; u.slot = i
			u.start = clock; u.release = clock + SKILLS[skill].wind
			u.ready = u.release + SKILLS[skill].flight + SKILLS[skill].recover
			u.why = "AP%d %s → %s" % [i + 1, rule[1], title(u.target)]
			log_event("AP", "%s：%s · %s" % [title(u.id), skill, u.why], u.id, u.target)
			break
		if u.mode == "待机": u.why = "；".join(reasons) if not reasons.is_empty() else "AP为空，等待"
		planned.append(u)
	for u in planned: units[u.id] = u

func react_before(target: int, source_event: int) -> void:
	for u in units:
		if u.hp <= 0 or u.pp != "援护" or u.team != units[target].team or u.id == target or u.pp_cd > clock: continue
		if pos(u.id).distance_to(pos(target)) > 175: continue
		u.pp_cd = clock + 6; u.pp_until = clock + 0.8
		units[target].shield += 26
		var id := log_event("PP", "%s援护%s，获得26护盾（不打断AP）" % [title(u.id), title(target)], u.id, target, source_event)
		effects.append({"kind": "shield", "a": pos(u.id), "b": pos(target), "end": clock + 0.6, "start": clock, "team": u.team, "event": id})
		break

func react_after(target: int, source_event: int) -> void:
	for u in units:
		if u.hp <= 0 or u.pp != "回春" or u.team != units[target].team or u.pp_cd > clock: continue
		if units[target].hp <= 0 or units[target].hp >= units[target].max_hp or pos(u.id).distance_to(pos(target)) > 230: continue
		u.pp_cd = clock + 6; u.pp_until = clock + 0.8
		units[target].hp = minf(units[target].max_hp, units[target].hp + 8)
		log_event("PP", "%s回春%s，恢复8HP" % [title(u.id), title(target)], u.id, target, source_event)
		break

func tick() -> void:
	if finished: return
	steps += 1; clock = steps * DT
	effects = effects.filter(func(e): return e.end > clock)
	move_squads()
	for u in units:
		if u.hp <= 0: u.mode = "阵亡"; continue
		if u.mode == "施法" and clock + 0.0001 >= u.release:
			u.mode = "收招"; u.cooldowns[u.skill] = clock + SKILLS[u.skill].cd
			var impact := {"source": u.id, "target": u.target, "skill": u.skill, "due": clock + SKILLS[u.skill].flight,
				"a": pos(u.id), "b": pos(u.target), "event": log_event("释放", "%s释放%s" % [title(u.id), u.skill], u.id, u.target)}
			impacts.append(impact)
			if SKILLS[u.skill].flight > 0:
				effects.append({"kind": "projectile", "a": impact.a, "b": impact.b, "target": u.target, "start": clock, "end": impact.due, "team": u.team, "skill": u.skill})
		if u.mode == "收招" and clock + 0.0001 >= u.ready: u.mode = "待机"; u.slot = -1
	var due := impacts.filter(func(p): return p.due <= clock + 0.0001)
	impacts = impacts.filter(func(p): return p.due > clock + 0.0001)
	# Already released projectiles survive the caster; all due hits land, allowing mutual defeat.
	var hit_targets: Array = []
	for p in due:
		var t: Dictionary = units[p.target]; var u: Dictionary = units[p.source]
		if t.hp <= 0: continue
		var hp_before: float = t.hp
		var damage: float = SKILLS[p.skill].damage
		if p.skill == "牵制":
			t.taunt_until = clock + 6; t.taunt_source = u.id
			u.shield = minf(u.shield + 24, 48)
			t.taunt_event = log_event("牵制", "%s牵制%s 6秒，自身获得24护盾" % [title(u.id), title(t.id)], u.id, t.id, p.event)
		elif damage < 0:
			t.hp = minf(t.max_hp, t.hp - damage)
			log_event("治疗", "%s治疗%s +25HP" % [title(u.id), title(t.id)], u.id, t.id, p.event)
		else:
			if p.skill == "协同突袭" and t.taunt_until > clock:
				damage = 32; combo_count += 1
				log_event("连携", "%s利用%s的牵制 → 协同突袭32伤害" % [title(u.id), title(t.taunt_source)], u.id, t.id, p.event)
				events.back()["causes"] = [p.event, t.taunt_event]
			react_before(t.id, p.event)
			var absorbed := minf(t.shield, damage)
			t.shield -= absorbed; t.hp = maxf(0, t.hp - damage + absorbed)
			log_event("命中", "%s命中%s：%.0f伤害 / 护盾抵消%.0f" % [title(u.id), title(t.id), damage - absorbed, absorbed], u.id, t.id, p.event)
			hit_targets.append([t.id, p.event])
		effects.append({"kind": "hit", "a": p.a, "b": pos(t.id), "start": clock, "end": clock + 0.65, "team": u.team, "skill": p.skill, "delta": t.hp - hp_before})
	for hit in hit_targets: react_after(hit[0], hit[1])
	for u in units:
		if u.hp <= 0 and u.mode != "阵亡":
			u.mode = "阵亡"; u.slot = -1
			log_event("阵亡", "%s阵亡" % title(u.id), u.id, u.id)
	var blue := false; var red := false
	for u in units:
		if u.hp > 0:
			if u.team == 0: blue = true
			else: red = true
	if not blue or not red or clock >= LIMIT:
		finished = true
		result = "蓝方胜利" if blue and not red else ("红方胜利" if red and not blue else ("双方全灭" if not red and not blue else "时间到 · 战斗结束"))
		log_event("结束", result, -1, -1)
		return
	choose_actions()

func summary() -> Dictionary:
	return {"time": clock, "result": result, "combos": combo_count, "hp": units.map(func(u): return snappedf(u.hp, 0.01)), "events": events.duplicate(true)}
