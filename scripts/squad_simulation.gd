extends RefCounted
## Deterministic shared battlefield. Fixed step is numerical precision, not a player beat.
const DT := 0.05
const LIMIT := 55.0
const WALLS := [Rect2(405, 130, 35, 140), Rect2(405, 455, 35, 70)]
const TASKS := ["正面推进", "侧路突袭", "支援A队", "原地驻守"]
const CONDITIONS := ["无", "目标被牵制", "目标正在施法", "友军HP≤60%", "自己无护盾"]
const PP_SKILLS := {
	"援护": {"stage": "受击前", "self": false, "range": 175.0, "cd": 6.0, "amount": 26.0},
	"格挡": {"stage": "受击前", "self": true, "range": 0.0, "cd": 4.0, "amount": 18.0},
	"回春": {"stage": "受击后", "self": false, "range": 230.0, "cd": 6.0, "amount": 8.0}}
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
var decisions: Array = []

static func defaults() -> Dictionary:
	return {"tasks": ["正面推进", "侧路突袭"], "postures": ["贴近交战", "贴近交战"], "exceptions": ["无", "无"], "rules": [
		[["牵制", "无", "无"], ["盾击", "无", "无"], ["留空", "无", "无"]],
		[["火球", "目标被牵制", "无"], ["火球", "无", "无"], ["留空", "无", "无"]],
		[["协同突袭", "目标被牵制", "无"], ["等待牵制", "无", "无"], ["突刺", "无", "无"]],
		[["治疗", "友军HP≤60%", "无"], ["光弹", "无", "无"], ["留空", "无", "无"]]],
		"pp": [[["援护", "目标是后排", "无"], ["格挡", "无", "无"]],
			[["留空", "无", "无"], ["留空", "无", "无"]],
			[["留空", "无", "无"], ["留空", "无", "无"]],
			[["回春", "无", "无"], ["留空", "无", "无"]]]}

static func options(role: String) -> Array:
	match role:
		"盾兵": return ["留空", "牵制", "盾击"]
		"法师": return ["留空", "火球"]
		"刺客": return ["留空", "协同突袭", "等待牵制", "突刺"]
		_: return ["留空", "治疗", "光弹"]

static func conditions_for(skill: String) -> Array:
	if skill == "留空": return ["无"]
	if skill == "等待牵制": return ["无"]
	if PP_SKILLS.has(skill): return ["无", "目标是后排", "目标HP≤60%", "保留1PP", "自己HP≤50%"]
	if skill == "治疗": return ["无", "友军HP≤60%"]
	if skill == "牵制": return ["无", "自己无护盾", "目标正在施法"]
	return ["无", "目标被牵制", "目标正在施法"]

static func pp_options(role: String) -> Array:
	if role == "盾兵": return ["留空", "援护", "格挡"]
	if role == "牧师": return ["留空", "回春"]
	return ["留空"]

static func normalize(settings: Dictionary) -> Dictionary:
	var value: Dictionary = (defaults() if settings.is_empty() else settings).duplicate(true)
	if not value.has("postures"): value.postures = ["贴近交战", "贴近交战"]
	if not value.has("exceptions"): value.exceptions = ["无", "无"]
	for i in range(4):
		for rule in value.rules[i]:
			while rule.size() < 3: rule.append("无")
		while value.rules[i].size() < 3: value.rules[i].append(["留空", "无", "无"])
		if value.pp[i] is String: value.pp[i] = [[value.pp[i], "无", "无"], ["留空", "无", "无"]]
	return value

func reset(settings: Dictionary = {}) -> void:
	config = normalize(settings)
	clock = 0.0
	steps = 0
	sequence = 0
	combo_count = 0
	finished = false
	result = ""
	squads.clear(); units.clear(); events.clear(); impacts.clear(); effects.clear(); decisions.clear()
	var positions := [Vector2(135, 335), Vector2(140, 530), Vector2(595, 335), Vector2(755, 210)]
	var names := ["A · 盾法队", "B · 突袭队", "C · 守备队", "D · 雷法队"]
	for i in range(4):
		squads.append({"id": i, "team": 0 if i < 2 else 1, "name": names[i], "pos": positions[i],
			"task": config.tasks[i] if i < 2 else "原地驻守", "target": -1, "route": [], "phase": 0,
			"home": positions[i], "retreating": false, "posture": config.postures[i] if i < 2 else "贴近交战",
			"exception": config.exceptions[i] if i < 2 else "无", "reason": "等待开始", "moving": false, "engaged": false})
	var roles := ["盾兵", "法师", "刺客", "牧师", "卫兵", "弓手", "卫兵", "雷法"]
	var health := [210.0, 100.0, 120.0, 100.0, 180.0, 100.0, 130.0, 100.0]
	for i in range(8):
		var rules: Array
		if i < 4: rules = config.rules[i].duplicate(true)
		else: rules = [["盾击" if i % 2 == 0 else ("箭击" if i == 5 else "雷击"), "无"]]
		units.append({"id": i, "squad": i / 2, "team": 0 if i < 4 else 1, "role": roles[i],
			"hp": health[i], "max_hp": health[i], "shield": 0.0, "rules": rules,
			"pp_rules": config.pp[i].duplicate(true) if i < 4 else [], "pp": "", "pp_cd": 0.0, "pp_until": 0.0,
			"pp_points": 2, "pp_next": 8.0, "pp_cooldowns": {}, "pp_slot": -1, "pp_checks": [], "reacted_event": -1,
			"checks": [], "check_time": 0.0, "pp_check_time": 0.0, "cast_event": -1, "wait_event": -1, "wait_until": 0.0, "wait_spent": false,
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
		var hp := 0.0; var maximum := 0.0
		for u in units:
			if u.squad == s.id: hp += u.hp; maximum += u.max_hp
		if s.exception != "无" and hp / maximum <= 0.35 and not s.retreating:
			s.retreating = true
			log_event("任务", "%s触发低血例外：撤回部署区，恢复至65%%才解除" % s.name, -1, -1)
		if s.retreating and hp / maximum > 0.65: s.retreating = false
		if s.retreating:
			destination = s.home; s.reason = "低血例外：撤回部署区（高于65%解除）"
		elif s.task == "原地驻守": s.reason = "驻守阵地，不追击"
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
			var reach := 200.0 if s.posture == "保持距离" else 100.0
			if old.distance_to(enemy) > reach or (s.posture == "保持距离" and old.distance_to(enemy) < reach - 20):
				destination = enemy + (old - enemy).normalized() * (reach - 2)
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

func candidates(uid: int, skill: String, condition: String, in_range := true) -> Array:
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
		if not in_range or pos(uid).distance_to(pos(t.id)) <= SKILLS[skill].range: result_targets.append(t.id)
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

func assessment(uid: int, rule: Array, slot: int) -> Dictionary:
	var skill: String = rule[0]
	var c2: String = rule[2] if rule.size() > 2 else "无"
	var row := {"slot": slot, "skill": skill, "condition1": rule[1], "condition2": c2,
		"condition_ok": false, "range_ok": false, "cooldown": 0.0, "targets": [], "chosen": false, "reason": "空槽"}
	if skill == "留空": return row
	if skill == "等待牵制":
		if units[uid].wait_spent: row.reason = "等待已用完；须先执行非等待动作"; return row
		for ally in units:
			if ally.hp > 0 and ally.team == units[uid].team and ally.mode == "施法" and ally.skill == "牵制" and ally.release - clock <= 1.0:
				if units[ally.target].hp > 0 and pos(uid).distance_to(pos(ally.target)) <= 180:
					row.condition_ok = true; row.range_ok = true; row.targets = [ally.target]; row.reason = "友军正施放牵制，目标在180范围内"; return row
		row.reason = "没有1秒内即将完成的射程内牵制"; return row
	var first := candidates(uid, skill, rule[1], false)
	var second := candidates(uid, skill, c2, false)
	var matching: Array = first.filter(func(id): return second.has(id))
	row.condition_ok = not matching.is_empty()
	row.targets = matching.filter(func(id): return pos(uid).distance_to(pos(id)) <= SKILLS[skill].range)
	row.range_ok = not row.targets.is_empty()
	row.cooldown = maxf(0, units[uid].cooldowns.get(skill, 0.0) - clock)
	if not row.condition_ok: row.reason = "没有同时满足两个条件的合法目标"
	elif not row.range_ok: row.reason = "条件满足，但目标超出射程"
	elif row.cooldown > 0: row.reason = "条件和射程满足，但技能冷却%.1fs" % row.cooldown
	else: row.reason = "可执行"
	return row

func choose_actions() -> void:
	var planned: Array = []
	for original in units:
		if original.hp <= 0 or original.mode not in ["待机", "等待"]: continue
		var u: Dictionary = original.duplicate(true)
		u.check_time = clock
		var waiting: bool = u.mode == "等待" and clock < u.wait_until - 0.0001
		var max_slot: int = u.slot if waiting else u.rules.size()
		if u.mode == "等待" and not waiting:
			u.mode = "待机"
			log_event("等待结束", "%s等待超时，跳过等待并寻找后备动作" % title(u.id), u.id, -1)
		u.checks = []
		var chosen := false
		for i in u.rules.size():
			if i >= max_slot:
				u.checks.append({"slot": i, "skill": u.rules[i][0], "chosen": false, "reason": "等待中：只重查等待之前的战术"}); continue
			var row := assessment(u.id, u.rules[i], i)
			# Copy the waiting lock from the planned state if it just timed out.
			if u.rules[i][0] == "等待牵制" and u.wait_spent:
				row.condition_ok = false; row.reason = "本轮等待已消耗，不能续期"
			u.checks.append(row)
			if not row.condition_ok or not row.range_ok or row.cooldown > 0: continue
			row.chosen = true; chosen = true
			u.slot = i; u.skill = row.skill; u.target = row.targets[0]
			u.why = "AP%d %s / %s → %s" % [i + 1, row.condition1, row.condition2, title(u.target)]
			if row.skill == "等待牵制":
				u.mode = "等待"; u.wait_until = clock + 1.0; u.wait_spent = true
				u.why = "最多等待1秒；提前出现可用的上方战术就结束等待"
				u.wait_event = log_event("等待", "%s保留行动，等待牵制（最多1秒）" % title(u.id), u.id, u.target)
			else:
				u.mode = "施法"; u.wait_spent = false
				if original.mode == "等待": log_event("等待结束", "%s提前结束等待 → %s" % [title(u.id), u.skill], u.id, u.target)
				u.start = clock; u.release = clock + SKILLS[u.skill].wind
				u.ready = u.release + SKILLS[u.skill].flight + SKILLS[u.skill].recover
				u.cast_event = log_event("AP", "%s：%s · %s" % [title(u.id), u.skill, u.why], u.id, u.target, u.wait_event if original.mode == "等待" else -1)
			for j in range(i + 1, u.rules.size()):
				u.checks.append({"slot": j, "skill": u.rules[j][0], "chosen": false, "reason": "未检查：上方战术已选中"})
			break
		if not chosen and not waiting:
			u.mode = "待机"; u.slot = -1
			var reasons: Array[String] = []
			for row in u.checks:
				if row.skill != "留空": reasons.append(row.skill + "：" + row.reason)
			u.why = "；".join(reasons) if not reasons.is_empty() else "AP为空，等待"
		if chosen: decisions.append({"time": clock, "actor": u.id, "kind": "主动", "checks": u.checks.duplicate(true)})
		planned.append(u)
	for u in planned: units[u.id] = u

func reaction(stage: String, target: int, source_event: int) -> void:
	for u in units:
		if u.hp <= 0 or u.team != units[target].team: continue
		if source_event > 0 and u.reacted_event == source_event: continue
		var rows: Array = []
		for i in u.pp_rules.size():
			var rule: Array = u.pp_rules[i]; var skill: String = rule[0]
			if not PP_SKILLS.has(skill): continue
			var data: Dictionary = PP_SKILLS[skill]
			if data.stage != stage: continue # intrinsic stage filter, not a player condition
			var row := {"slot": i, "skill": skill, "chosen": false, "reason": "", "stage": stage, "event": source_event}
			if data.self and u.id != target: row.reason = "固有要求：仅自己受击"
			elif not data.self and skill == "援护" and u.id == target: row.reason = "固有要求：只能援护其他人"
			elif pos(u.id).distance_to(pos(target)) > data.range and not data.self: row.reason = "目标超出反应范围"
			elif units[target].hp <= 0: row.reason = "目标已阵亡"
			elif skill == "回春" and units[target].hp >= units[target].max_hp: row.reason = "目标未受伤"
			elif u.pp_points < 1: row.reason = "反应资源不足：需要1PP"
			elif u.pp_cooldowns.get(skill, 0.0) > clock: row.reason = "技能冷却中"
			else:
				for condition in [rule[1], rule[2]]:
					if condition == "目标是后排" and target % 2 == 0: row.reason = "额外条件不满足：目标不是后排"
					elif condition == "目标HP≤60%" and units[target].hp / units[target].max_hp > 0.6: row.reason = "额外条件不满足：目标HP>60%"
					elif condition == "保留1PP" and u.pp_points < 2: row.reason = "额外条件不满足：需至少2PP以保留1PP"
					elif condition == "自己HP≤50%" and u.hp / u.max_hp > 0.5: row.reason = "额外条件不满足：自己HP>50%"
			rows.append(row)
			if not row.reason.is_empty(): continue
			row.chosen = true; row.reason = "本事件合法，消耗1PP"
			u.pp_points -= 1; u.pp_cooldowns[skill] = clock + data.cd
			u.reacted_event = source_event
			u.pp_until = clock + 0.8; u.pp_slot = i; u.pp = skill
			if skill in ["格挡", "援护"]: units[target].shield += data.amount
			else: units[target].hp = minf(units[target].max_hp, units[target].hp + data.amount)
			var id := log_event("PP", "%s%s%s：%s%.0f，消耗1PP（剩%d）" % [title(u.id), skill, title(target), "护盾+" if skill != "回春" else "HP+", data.amount, u.pp_points], u.id, target, source_event)
			effects.append({"kind": "shield", "a": pos(u.id), "b": pos(target), "end": clock + 0.6, "start": clock, "team": u.team, "event": id})
			break # one reaction per caster per source event; effects don't generate hit events
		if not rows.is_empty(): u.pp_checks = rows; u.pp_check_time = clock
		if not rows.is_empty(): decisions.append({"time": clock, "actor": u.id, "kind": "反应", "event": source_event, "checks": rows.duplicate(true)})

func react_before(target: int, source_event: int) -> void:
	reaction("受击前", target, source_event)

func react_after(target: int, source_event: int) -> void:
	reaction("受击后", target, source_event)

func tick() -> void:
	if finished: return
	steps += 1; clock = steps * DT
	effects = effects.filter(func(e): return e.end > clock)
	move_squads()
	for u in units:
		if clock + 0.0001 >= u.pp_next:
			u.pp_points = mini(2, u.pp_points + 1); u.pp_next += 8.0
		if u.hp <= 0: u.mode = "阵亡"; continue
		if u.mode == "施法" and clock + 0.0001 >= u.release:
			u.mode = "收招"; u.cooldowns[u.skill] = clock + SKILLS[u.skill].cd
			var impact := {"source": u.id, "target": u.target, "skill": u.skill, "due": clock + SKILLS[u.skill].flight,
				"a": pos(u.id), "b": pos(u.target), "event": log_event("释放", "%s释放%s" % [title(u.id), u.skill], u.id, u.target, u.cast_event)}
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

func snapshot() -> Dictionary:
	return {"clock": clock, "steps": steps, "units": units.duplicate(true), "squads": squads.duplicate(true),
		"effects": effects.duplicate(true), "combo_count": combo_count, "finished": finished, "result": result, "event_count": events.size()}

func load_view(state: Dictionary, recorded_events: Array) -> void:
	clock = state.clock; steps = state.steps; units = state.units.duplicate(true); squads = state.squads.duplicate(true)
	effects = state.effects.duplicate(true); combo_count = state.combo_count; finished = state.finished; result = state.result
	events = recorded_events.slice(0, state.event_count)
