extends RefCounted
## Beat-only rules. No renderer, wall clock, random numbers or sub-cell collision.
const Tactics = preload("res://scripts/tactics.gd")
const SIZE := 8
const CELL_SIZE := 80.0
const SECONDS := 0.25
const MOVE_BEATS := 2
const NORMAL_RANGE := 4
const MAX_HP := 5
const COLLISION_DAMAGE := 1
const HEAL := 1
const WOOD_SHIELD := 1
const COVER_SHIELD := 2
const GUARD_REDUCTION := 1
const MARK_BONUS := 1
const THORN_DAMAGE := 1
const DAMAGE := {
	"点射": 1, "普通攻击": 1, "标记弹": 1, "强力射击": 2, "压制射击": 1, "协同追击": 1,
	"风刃": 1, "追风": 1, "火矢": 1, "焰返": 1, "落岩": 2, "震山": 2, "荆棘": 0,
	"蓄能贯穿": 2, "霰弹": 1, "抛射轰击": 2, "疾风连刃": 1, "烈焰爆破": 2, "裂地冲击": 2,
	"天穹贯穿": 3, "星火轰炸": 2,
}
const HIGH := ["抛射轰击", "烈焰爆破", "蓄能贯穿", "裂地冲击", "天穹贯穿", "星火轰炸"]
const MOVE := ["接敌", "调整站位", "搜寻", "绕侧", "后撤", "短冲刺", "步行避险", "向左移动", "向右移动", "向上移动", "向下移动"]
const SUPPORT := ["回春", "灵木护佑", "掩护队友", "架枪防御"]
var units: Array = []
var loadouts: Array = []
var blocked_cells: Array[Vector2i] = []
var strikes: Array = []
var effects: Array = []
var events: Array[String] = []
var hit_events: Array = []
var manual: Dictionary = {}
var beat := 0
var finished := false
var winner := -1
var result := ""
var activations: Dictionary = {}
var shots := 0
var hits := 0
var decision_order := [0, 1, 2, 3]
var next_segment: Dictionary = {}
var boundary_stages: Array = []

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL_SIZE), floori(p.y / CELL_SIZE))

static func center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_SIZE

static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func name_of(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]

func reset(source_units: Array, source_loadouts: Array, walls: Array) -> void:
	units = source_units.duplicate(true)
	loadouts = source_loadouts
	blocked_cells.clear()
	for x in range(SIZE):
		for y in range(SIZE):
			var p := center(Vector2i(x, y))
			for wall in walls:
				if wall.grow(25).has_point(p):
					blocked_cells.append(Vector2i(x, y))
					break
	beat = 0
	finished = false
	winner = -1
	result = ""
	shots = 0
	hits = 0
	strikes.clear()
	effects.clear()
	events.clear()
	hit_events.clear()
	manual.clear()
	activations.clear()
	next_segment.clear()
	boundary_stages.clear()
	for u in units:
		u.hp = MAX_HP if u.hp > 0 else 0
		u.cooldown = 0.0 # Compatibility with the shared legacy renderer; no public cooldown in beat combat.
		u.shield = 0
		u.cell = cell_of(u.p)
		u.p = center(u.cell)
		u.pose = "站稳"
		u.trend = Vector2i.ZERO
		u.mode = ""
		u.left = 0
		u.paid = 0.0
		u.committed = false
		u.attack_started = -1
		u.lock_cells = []
		u.return_cell = u.cell
		u.collision_at = Vector2i(-1, -1)
		u.last_blocked = Vector2i(-1, -1)
		u.blocked_until = 0
		u.move_target = u.cell
		u.move_origin = u.cell
		u.move_total = MOVE_BEATS
		u.phase = "站稳"
		u.intent = "等待决策"
		u.action_stage = ""
		u.stage_frames = 0
		u.last_cancel = ""
		u.last_cancel_frame = 0
		u.trace_ap.fill("未检查")
		u.trace_pp.fill("未检查")

static func posture(u: Dictionary) -> String:
	# Endpoint posture constrains the segment about to begin, not the one completed.
	if pp_locked(u): return "僵直姿态"
	if u.mode == "后摇" or u.pose == "动作": return "动作姿态"
	if u.pose == "移动": return "移动姿态"
	return "站立姿态"

static func posture_label(u: Dictionary) -> String:
	var kind := posture(u)
	if kind != "移动姿态": return kind
	return kind + "·" + str({Vector2i.RIGHT: "右", Vector2i.LEFT: "左", Vector2i.UP: "上", Vector2i.DOWN: "下"}.get(u.trend, "无"))

static func pp_locked(u: Dictionary) -> bool:
	# Decide from the stage about to execute, never from last beat's display pose.
	return u.mode in ["碰撞", "释放硬直"]

func legal(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE and cell not in blocked_cells

func directions(u: Dictionary) -> Array[Vector2i]:
	var sign_value := 1 if u.attack else -1
	return [Vector2i(sign_value, 0), Vector2i(0, sign_value), Vector2i(0, -sign_value), Vector2i(-sign_value, 0)]

func cardinal(u: Dictionary, target: Vector2i) -> Vector2i:
	var delta: Vector2i = target - u.cell
	if absi(delta.x) >= absi(delta.y) and delta.x != 0: return Vector2i(signi(delta.x), 0)
	if delta.y != 0: return Vector2i(0, signi(delta.y))
	return Vector2i(1 if u.attack else -1, 0)

func ray(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := signi(b.x - a.x)
	var sy := signi(b.y - a.y)
	var error := dx - dy
	var p := a
	while true:
		cells.append(p)
		if p == b: break
		var twice := 2 * error
		if twice > -dy: error -= dy; p.x += sx
		if twice < dx: error += dx; p.y += sy
	return cells

func sight(a: Vector2i, b: Vector2i) -> bool:
	for p in ray(a, b):
		if p in blocked_cells: return false
	return true

func coverage(u: Dictionary, skill: String, target: Vector2i) -> Array:
	var cells: Array = []
	if skill in ["抛射轰击", "烈焰爆破", "星火轰炸"]:
		var centers: Array = [target]
		if skill == "星火轰炸":
			centers.clear()
			var d := cardinal(u, target)
			for n in [2, 3, 4]: centers.append(u.cell + d * n)
		for c in centers:
			for x in range(-1, 2):
				for y in range(-1, 2):
					if skill != "烈焰爆破" and absi(x) + absi(y) > 1: continue
					var p: Vector2i = c + Vector2i(x, y)
					if p.x >= 0 and p.y >= 0 and p.x < SIZE and p.y < SIZE and p not in cells: cells.append(p)
	elif skill in ["蓄能贯穿", "裂地冲击", "天穹贯穿"]:
		var d := cardinal(u, target)
		for n in range(1, 7 if skill == "天穹贯穿" else 5):
			var p: Vector2i = u.cell + d * n
			if not legal(p): break
			cells.append(p)
	elif skill == "霰弹":
		var d := cardinal(u, target)
		var side := Vector2i(-d.y, d.x)
		for p in [u.cell + d, u.cell + d * 2, u.cell + d * 2 + side, u.cell + d * 2 - side]:
			if legal(p) and sight(u.cell, p): cells.append(p)
	else:
		cells.append(target)
	return cells

static func flight_delay(skill: String) -> int:
	return 0 if skill in ["点射", "普通攻击", "蓄能贯穿", "裂地冲击", "天穹贯穿"] else (2 if skill in ["抛射轰击", "烈焰爆破", "星火轰炸"] else 1)

func cost(skill: String) -> float:
	if skill in ["天穹贯穿", "星火轰炸"]: return 70.0
	if skill in HIGH: return 45.0
	if skill in ["点射", "普通攻击"]: return 15.0
	if skill in ["侧闪", "短冲刺"]: return 20.0
	if skill == "架枪防御": return 10.0
	if skill in MOVE or skill == "站稳": return 0.0
	return 25.0

func skill_cd(skill: String) -> float:
	if skill == "普通攻击": skill = "点射"
	var seconds: float = Tactics.MAGIC.get(skill, {}).get("cd", {"点射": 1.5, "标记弹": 5, "强力射击": 6, "压制射击": 6, "协同追击": 5, "侧闪": 2.8, "回春": 8, "灵木护佑": 9, "掩护队友": 6, "架枪防御": 5, "短冲刺": 4}.get(skill, 0))
	return ceilf(seconds / SECONDS) * SECONDS

func windup(skill: String) -> int:
	if skill == "蓄能贯穿": return 3
	return 2 if skill in HIGH or skill in ["落岩", "震山"] else 1

func damage_of(skill: String) -> int:
	assert(DAMAGE.has(skill), "Attack requires an explicit beat damage value: " + skill)
	return DAMAGE.get(skill, 0)

func ranged(u: Dictionary, target: Dictionary, skill: String) -> bool:
	if distance(u.cell, target.cell) > (2 if skill == "霰弹" else (NORMAL_RANGE if skill in ["普通攻击", "点射"] else 4)): return false
	if skill in ["蓄能贯穿", "裂地冲击", "天穹贯穿"] and target.cell not in coverage(u, skill, target.cell): return false
	return skill in ["普通攻击", "点射", "抛射轰击", "烈焰爆破", "星火轰炸"] or sight(u.cell, target.cell)

func ally_of(u: Dictionary, snapshot: Array) -> int:
	for v in snapshot:
		if v.uid != u.uid and v.team == u.team and v.hp > 0: return v.uid
	return -1

func condition(u: Dictionary, target: int, text: String, snapshot: Array) -> bool:
	var ally := ally_of(u, snapshot)
	match text:
		"有射位": return target >= 0 and ranged(u, snapshot[target], "点射")
		"站稳姿态": return posture(u) == "站立姿态"
		"移动姿态": return posture(u) == "移动姿态"
		"动作姿态": return posture(u) == "动作姿态"
		"僵直姿态": return posture(u) == "僵直姿态"
		"自己精力≥80": return u.energy >= 80
		"自己精力≥50": return u.energy >= 50
		"自己精力≤30": return u.energy <= 30
		"自己HP≤2", "自己HP≤50": return u.hp <= 2
		"队友HP≤2", "队友HP≤50": return ally >= 0 and snapshot[ally].hp <= 2
		"敌人距离≤2米": return target >= 0 and distance(u.cell, snapshot[target].cell) <= 2
		"敌人距离≥3米": return target >= 0 and distance(u.cell, snapshot[target].cell) >= 3
		"仅已标记敌人": return target >= 0 and snapshot[target].marked > 0
		"仅未标记敌人": return target >= 0 and snapshot[target].marked <= 0
		"敌人正在收招": return target >= 0 and snapshot[target].mode == "后摇"
		"敌人正在攻击队友": return target >= 0 and ally >= 0 and snapshot[target].target == ally and snapshot[target].mode in ["前摇", "释放硬直"]
		"队友正在被瞄准":
			for v in snapshot:
				if ally >= 0 and v.hp > 0 and v.team != u.team and v.target == ally and v.mode in ["前摇", "释放硬直"]: return true
			return false
		"自己被两人瞄准":
			var count := 0
			for v in snapshot:
				if v.hp > 0 and v.team != u.team and v.target == u.uid and v.mode in ["前摇", "释放硬直"]: count += 1
			return count >= 2
	return true

func target_for(u: Dictionary, rule: Array, snapshot: Array, shooting: bool, eligible: Array = []) -> int:
	var candidates: Array = []
	for v in snapshot:
		if v.team == u.team or v.hp <= 0: continue
		if not eligible.is_empty() and v.uid not in eligible: continue
		if not condition(u, v.uid, rule[1], snapshot) or not condition(u, v.uid, rule[2], snapshot): continue
		if shooting and not ranged(u, v, rule[0]): continue
		candidates.append(v.uid)
	var ally := ally_of(u, snapshot)
	if "优先队友目标" in rule and ally >= 0 and snapshot[ally].target in candidates: return snapshot[ally].target
	var best := -1
	var best_score := INF
	for uid in candidates:
		var v: Dictionary = snapshot[uid]
		var local: Vector2i = v.cell if u.attack else Vector2i(7, 7) - v.cell
		var score: float = distance(u.cell, v.cell) * 1000 + local.x * 8 + local.y
		if "优先低血量" in rule: score += v.hp * 100000
		if score < best_score: best = uid; best_score = score
	return best

func ready(u: Dictionary, skill: String, refund := false) -> String:
	if skill == "普通攻击": skill = "点射"
	if float(u.skill_cds.get(skill, 0)) > 0: return "技能CD中"
	if skill in HIGH and u.pose != "站稳": return "需要站稳"
	var available: float = u.energy + (u.paid if refund and u.mode == "前摇" and not u.committed else 0.0)
	if available < cost(skill): return "精力不足"
	if skill == "点射" and u.pose != "站稳": return "需要站稳"
	return ""

func select_rule(u: Dictionary, kind: String, slot: int, skill: String) -> void:
	u.frame_triggers += 1
	assert(u.frame_triggers == 1, "Only one AP or PP selection per beat")
	u.rule_kind = kind
	u.rule_slot = slot
	u.rule = ("AP" if kind == "active" else "PP") + "%d %s" % [slot + 1, skill]
	u.active_skill = "点射" if skill == "普通攻击" else skill
	u.intent = skill
	u.frame_branch = u.rule
	u.reason = "第%d拍 · %s" % [beat, u.rule]
	var trace: Array = u.trace_ap if kind == "active" else u.trace_pp
	trace[slot] = "本拍选中"
	var key := "%d:%s" % [u.uid, skill]
	activations[key] = int(activations.get(key, 0)) + 1

func occupied(cell: Vector2i, snapshot: Array, ignore := -1) -> bool:
	for v in snapshot:
		if v.hp <= 0 or v.uid == ignore: continue
		if v.cell == cell or (v.mode == "碰撞" and v.return_cell == cell): return true
	return false

func move_score(u: Dictionary, c: Vector2i, target: int, skill: String, snapshot: Array) -> float:
	if target < 0: return float(distance(c, Vector2i(3 if u.attack else 4, 3 if u.attack else 4)))
	var v: Dictionary = snapshot[target]
	var d := distance(c, v.cell)
	if skill == "后撤": return -d * 10.0
	var desired := 2 if "霰弹" in loadouts[u.uid].active.map(func(r): return r[0]) else 3
	var score: float = absf(d - desired) * 10.0
	if skill in ["接敌", "短冲刺", "搜寻"]: score = d * 10.0
	if not sight(c, v.cell): score += 30
	for rule in loadouts[u.uid].active:
		if rule[0] in ["站稳", "普通攻击"] or rule[0] in MOVE: continue
		if rule[0] in ["蓄能贯穿", "裂地冲击"] and c.x != v.cell.x and c.y != v.cell.y: score += 20
		break
	if occupied(c, snapshot, u.uid): score += 40
	var ally := ally_of(u, snapshot)
	if ally >= 0 and distance(c, snapshot[ally].cell) <= 1: score += 10
	if c == u.last_blocked and beat <= u.blocked_until: score += 50
	return score

func path_direction(u: Dictionary, target: int, skill: String, snapshot: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var best_score := INF
	# BFS makes cover routing a grid decision; local direction order breaks ties symmetrically.
	for direction in directions(u):
		var first: Vector2i = u.cell + direction
		if not legal(first): continue
		var score := move_score(u, first, target, skill, snapshot)
		if target >= 0 and skill in ["接敌", "搜寻", "短冲刺"]:
			var queue: Array = [[first, 1]]
			var seen: Array = [u.cell, first]
			var route_cost := 100.0
			while not queue.is_empty():
				var item: Array = queue.pop_front()
				var p: Vector2i = item[0]
				if distance(p, snapshot[target].cell) <= 3 and sight(p, snapshot[target].cell): route_cost = float(item[1]); break
				for d in directions(u):
					var next: Vector2i = p + d
					if not legal(next) or next in seen: continue
					seen.append(next)
					queue.append([next, item[1] + 1])
			score = route_cost * 10 + score * 0.01 + Vector2(first).distance_squared_to(Vector2(snapshot[target].cell)) * 0.001
		if u.pose == "移动":
			if u.trend == direction: score -= 0.001
			else: score += 10.0 # A direction change includes a full standing beat.
		if score < best_score - 0.0001: best_score = score; best = direction
	return best

func request_move(u: Dictionary, direction: Vector2i, proposals: Dictionary, immediate := false) -> bool:
	if direction == Vector2i.ZERO or not legal(u.cell + direction): return false
	if not immediate and u.pose == "移动" and u.trend != direction:
		stand(u, "转向站立")
		u.frame_branch = "转向：先站立1拍"
		u.reason += "；换方向前先站立1拍，本拍不跨格"
		return true
	u.move_origin = u.cell
	u.move_target = u.cell + direction
	u.move_total = 1 if immediate else MOVE_BEATS + (1 if u.slow > 0 else 0)
	u.pose = "移动"
	u.trend = direction
	u.action_goal = center(u.move_target)
	if immediate:
		# PP dodge commits exactly one adjacent-cell crossing this beat.
		proposals[u.uid] = u.move_target
		u.mode = ""
		u.left = 0
		u.phase = "侧闪跨格"
	else:
		# Standing or same-direction movement starts a full two-beat crossing.
		u.angle = Vector2(direction).angle()
		u.mode = "移动硬直"
		u.left = u.move_total - 1
		u.phase = "移动硬直"
	return true

func stand(u: Dictionary, phase := "站稳") -> void:
	u.pose = "站稳"
	u.trend = Vector2i.ZERO
	u.mode = ""
	u.left = 0
	u.phase = phase
	u.move_origin = u.cell
	u.move_target = u.cell
	u.action_goal = center(u.cell)

func advance_move(u: Dictionary, proposals: Dictionary) -> void:
	u.left -= 1
	if u.left > 0:
		u.phase = "移动硬直"
		return
	proposals[u.uid] = u.move_target
	u.mode = ""
	u.left = 0
	u.phase = "跨格"

func threats(u: Dictionary, snapshot: Array, old_strikes: Array) -> Array:
	var dangers: Array = []
	for strike in old_strikes:
		if strike.team != u.team and strike.at <= beat + 1: dangers.append(strike.cells)
	for v in snapshot:
		if v.hp > 0 and v.team != u.team and v.mode in ["前摇", "释放硬直"]:
			if v.mode == "释放硬直" or v.left <= 1: dangers.append(v.lock_cells)
	return dangers

func escape(u: Dictionary, dangers: Array, snapshot: Array) -> Vector2i:
	var threatened := false
	for cells in dangers:
		if u.cell in cells: threatened = true
	if not threatened: return Vector2i.ZERO
	for d in directions(u):
		var c: Vector2i = u.cell + d
		if not legal(c) or occupied(c, snapshot, u.uid): continue
		var safe := true
		for cells in dangers:
			if c in cells: safe = false
		if safe: return d
	return Vector2i.ZERO

func cancel(u: Dictionary) -> void:
	var refund: float = u.paid if u.mode == "前摇" and not u.committed else 0.0
	var old: String = u.mode
	if refund > 0:
		u.energy = minf(100, u.energy + refund)
		if u.active_skill in ["天穹贯穿", "星火轰炸"]: u.ult_charge = 100.0
	if u.rule_slot >= 0 and not old.is_empty():
		var trace: Array = u.trace_ap if u.rule_kind == "active" else u.trace_pp
		trace[u.rule_slot] = "%s取消·退%d" % [old, refund]
	u.last_cancel = "%s取消，退%d精力" % [old if not old.is_empty() else "移动", refund]
	u.last_cancel_frame = beat
	u.mode = ""
	u.paid = 0.0
	u.left = 0
	u.lock_cells = []
	u.move_origin = u.cell
	u.move_target = u.cell
	u.move_total = MOVE_BEATS

func start_attack(u: Dictionary, target: int, skill: String, target_cell: Vector2i) -> void:
	if skill == "普通攻击": skill = "点射"
	if skill == "点射":
		assert(u.pose == "站稳", "Ordinary shooting must start from a completed standing pose")
	u.attack_started = beat
	u.energy -= cost(skill)
	u.paid = cost(skill)
	u.committed = false
	u.target = target
	u.active_skill = skill
	u.mode = "前摇"
	u.left = windup(skill)
	u.lock_cells = coverage(u, skill, target_cell)
	u.shot_count = 0
	u.angle = (center(target_cell) - center(u.cell)).angle()
	if skill in ["天穹贯穿", "星火轰炸"]: u.ult_charge = 0.0

func advance_attack(u: Dictionary) -> void:
	u.phase = u.mode
	if u.mode == "前摇":
		u.left -= 1
		if u.left == 0:
			u.mode = "释放硬直"
			u.left = int(Tactics.MAGIC.get(u.active_skill, {}).get("hits", 1))
	elif u.mode == "释放硬直":
		var skill: String = u.active_skill
		if skill == "点射":
			u.pose = "动作"
			u.trend = Vector2i.ZERO
		if not u.committed:
			u.committed = true
			u.skill_cds[skill] = skill_cd(skill)
		var delay := flight_delay(skill)
		strikes.append({"cells": u.lock_cells.duplicate(), "at": beat + delay, "team": u.team, "source": u.uid, "skill": skill, "damage": damage_of(skill), "warn_from": u.attack_started})
		shots += 1
		u.shot_count += 1
		u.fire_flash = SECONDS
		u.left -= 1
		if u.left == 0:
			u.mode = "后摇"
			u.left = 2 if skill in HIGH or skill in ["强力射击", "落岩", "震山"] else 1
	elif u.mode == "后摇":
		u.left -= 1
		if u.left == 0:
			u.mode = ""
			u.rule_kind = ""
			u.rule_slot = -1
			if u.active_skill == "点射": stand(u)
			else: u.phase = u.pose

func try_pp(u: Dictionary, snapshot: Array, old_strikes: Array, proposals: Dictionary, supports: Array) -> bool:
	var rows: Array = loadouts[u.uid].reaction
	u.trace_pp.fill("未检查（上方优先）")
	for slot in range(rows.size()):
		var rule: Array = rows[slot]
		var skill: String = rule[0]
		if pp_locked(u):
			u.trace_pp[slot] = "碰撞/释放硬直中"
			continue
		if not u.mode.is_empty() and skill != "侧闪":
			u.trace_pp[slot] = "当前动作只允许侧闪"
			continue
		var gate := ready(u, skill, skill == "侧闪")
		if not gate.is_empty(): u.trace_pp[slot] = gate; continue
		var target := target_for(u, rule, snapshot, false)
		if target < 0: u.trace_pp[slot] = "事件/条件未满足"; continue
		if skill in ["侧闪", "步行避险"]:
			var d := escape(u, threats(u, snapshot, old_strikes), snapshot)
			if d == Vector2i.ZERO: u.trace_pp[slot] = "无威胁或无安全格"; continue
			if skill == "侧闪": cancel(u)
			select_rule(u, "reaction", slot, skill)
			u.energy -= cost(skill)
			if skill == "侧闪": u.skill_cds[skill] = skill_cd(skill)
			request_move(u, d, proposals, skill == "侧闪")
			return true
		if skill in SUPPORT:
			var recipient: int = u.uid
			var ally := ally_of(u, snapshot)
			if skill == "掩护队友":
				if ally < 0: continue
				recipient = ally
			elif skill in ["回春", "灵木护佑"]:
				if ally >= 0 and snapshot[ally].hp < snapshot[recipient].hp: recipient = ally
				if snapshot[recipient].hp >= MAX_HP or snapshot[recipient].hurt_recent <= 0: continue
			if distance(u.cell, snapshot[recipient].cell) > 3 or not sight(u.cell, snapshot[recipient].cell): continue
			if skill in ["掩护队友", "架枪防御"] and threats(snapshot[recipient], snapshot, old_strikes).is_empty(): continue
			select_rule(u, "reaction", slot, skill)
			u.energy -= cost(skill)
			u.skill_cds[skill] = skill_cd(skill)
			supports.append({"target": recipient, "skill": skill})
			u.mode = "后摇"
			u.left = 1
			u.phase = skill
			return true
		if skill in ["协同追击", "追风"]:
			var event_targets: Array = []
			for event in hit_events:
				if event.source != u.uid and event.team == u.team and event.beat == beat - 1 and snapshot[event.target].hp > 0 and event.target not in event_targets: event_targets.append(event.target)
			if event_targets.is_empty(): continue
			var event_target := target_for(u, rule, snapshot, true, event_targets)
			if event_target < 0: continue
			target = event_target
		elif skill in ["焰返", "震山"]:
			if threats(u, snapshot, old_strikes).is_empty(): continue
		else: continue
		if not ranged(u, snapshot[target], skill): continue
		select_rule(u, "reaction", slot, skill)
		start_attack(u, target, skill, snapshot[target].cell)
		advance_attack(u)
		return true
	return false

func try_ap(u: Dictionary, snapshot: Array, proposals: Dictionary) -> void:
	u.trace_ap.fill("未检查（上方优先）")
	for slot in range(loadouts[u.uid].active.size()):
		var rule: Array = loadouts[u.uid].active[slot]
		var skill: String = rule[0]
		var actual := "点射" if skill == "普通攻击" else skill
		var gate := ready(u, actual)
		if actual == "点射" and gate == "需要站稳":
			var aim_target := target_for(u, rule, snapshot, true)
			if aim_target < 0: u.trace_ap[slot] = "没有符合条件的目标"; continue
			select_rule(u, "active", slot, skill)
			u.target = aim_target
			stand(u, "射击站立")
			u.frame_branch = "射击：先站立1拍"
			u.reason += "；普通射击必须先站立，本拍不瞄准、不消耗精力或CD"
			return
		if not gate.is_empty(): u.trace_ap[slot] = gate; continue
		var target := target_for(u, rule, snapshot, skill not in MOVE and skill != "站稳")
		if skill == "站稳":
			if u.pose == "站稳" or not condition(u, target, rule[1], snapshot) or not condition(u, target, rule[2], snapshot): u.trace_ap[slot] = "姿态/条件未满足"; continue
			select_rule(u, "active", slot, skill)
			stand(u)
			return
		if skill in ["向左移动", "向右移动", "向上移动", "向下移动"]:
			if not condition(u, target, rule[1], snapshot) or not condition(u, target, rule[2], snapshot): continue
			var d: Vector2i = {"向左移动": Vector2i.LEFT, "向右移动": Vector2i.RIGHT, "向上移动": Vector2i.UP, "向下移动": Vector2i.DOWN}[skill]
			if not legal(u.cell + d): u.trace_ap[slot] = "边界/掩体阻挡"; continue
			select_rule(u, "active", slot, skill)
			request_move(u, d, proposals)
			return
		if target < 0: u.trace_ap[slot] = "没有符合条件的目标"; continue
		if skill in MOVE:
			if skill == "搜寻": u.trace_ap[slot] = "敌人已知，无需搜寻"; continue
			if skill == "调整站位" and not ranged(u, snapshot[target], "点射"): continue
			if skill == "接敌" and ranged(u, snapshot[target], "点射"): continue
			var d := path_direction(u, target, skill, snapshot)
			if d == Vector2i.ZERO: continue
			if skill == "调整站位" and move_score(u, u.cell + d, target, skill, snapshot) >= move_score(u, u.cell, target, skill, snapshot): continue
			select_rule(u, "active", slot, skill)
			u.target = target
			request_move(u, d, proposals)
			if u.phase != "转向站立":
				u.energy -= cost(skill)
				if skill == "短冲刺": u.skill_cds[skill] = skill_cd(skill)
			return
		if skill == "留空": continue
		select_rule(u, "active", slot, skill)
		start_attack(u, target, actual, snapshot[target].cell)
		advance_attack(u)
		return
	u.phase = u.pose
	u.intent = "待命"
	u.rule_kind = ""
	u.rule_slot = -1
	u.reason = "没有可执行的AP/PP；保留当前姿态"

func collide(ids: Array, destination: Vector2i, snapshot: Array, next_units: Array, damage: Array, moved: Dictionary) -> void:
	for uid in ids:
		var u: Dictionary = next_units[uid]
		u.return_cell = snapshot[uid].cell
		u.cell = destination if destination != Vector2i(-1, -1) else snapshot[uid].cell
		u.mode = "碰撞"
		u.phase = "碰撞硬直"
		u.pose = "移动"
		u.left = 1
		u.lock_cells = []
		u.collision_at = u.cell
		u.last_blocked = destination
		u.blocked_until = beat + 4
		moved[uid] = true
		var hostile := false
		for other in ids:
			if snapshot[other].team != u.team: hostile = true
		if hostile: damage[uid] += COLLISION_DAMAGE
		u.reason = "第%d拍：抢格碰撞%s；下一拍强制弹回%s" % [beat, "，碰撞伤害%d" % COLLISION_DAMAGE if hostile else "（友军无伤害）", name_of(u.return_cell)]
	events.append("第%d拍 · %s发生碰撞，下一拍弹回" % [beat, name_of(destination) if destination != Vector2i(-1, -1) else "相邻边"])

func resolve_moves(snapshot: Array, next_units: Array, proposals: Dictionary, damage: Array) -> void:
	var handled: Dictionary = {}
	# Returning origins stay reserved throughout collision and bounce.
	for uid in proposals.keys():
		for old in snapshot:
			if old.hp > 0 and old.mode == "碰撞" and proposals[uid] in [old.cell, old.return_cell]:
				next_units[uid].phase = "退路保留"
				handled[uid] = true
	# Head-on exchanges collide on the edge; neither gets the other's source cell.
	for uid in proposals.keys():
		if handled.has(uid): continue
		for other in proposals.keys():
			if uid == other or handled.has(other): continue
			if proposals[uid] == snapshot[other].cell and proposals[other] == snapshot[uid].cell:
				collide([uid, other], Vector2i(-1, -1), snapshot, next_units, damage, handled)
				break
	for uid in proposals.keys():
		if handled.has(uid): continue
		var destination: Vector2i = proposals[uid]
		var group: Array = []
		for other in proposals.keys():
			if not handled.has(other) and proposals[other] == destination: group.append(other)
		for old in snapshot:
			if old.hp > 0 and old.cell == destination and not proposals.has(old.uid) and old.uid not in group: group.append(old.uid)
		if group.size() > 1:
			collide(group, destination, snapshot, next_units, damage, handled)
		else:
			next_units[uid].cell = destination
			handled[uid] = true
	# A collision discovered this beat also reserves its sources immediately.
	# Rollbacks propagate, so an incoming chain cannot occupy a blocked bot's source.
	for pass_index in range(next_units.size()):
		var rejected: Array = []
		for uid in proposals.keys():
			if next_units[uid].mode == "碰撞" or next_units[uid].cell == snapshot[uid].cell: continue
			for other in next_units:
				if other.hp <= 0 or other.uid == uid: continue
				if (other.mode == "碰撞" and other.return_cell == next_units[uid].cell) or other.cell == next_units[uid].cell:
					if uid not in rejected: rejected.append(uid)
		if rejected.is_empty(): break
		for uid in rejected:
			next_units[uid].cell = snapshot[uid].cell
			next_units[uid].phase = "退路保留"

func boundary_key() -> int:
	return hash([beat, units, loadouts, strikes, manual, hit_events, decision_order, blocked_cells])

func choose_next_segment() -> void:
	var key := boundary_key()
	var snapshot: Array = units.duplicate(true)
	var next_units: Array = snapshot.duplicate(true)
	var old_strikes: Array = strikes.duplicate(true)
	var proposals: Dictionary = {}
	var supports: Array = []
	var saved_beat := beat
	var saved_shots := shots
	var saved_strikes: Array = strikes
	var saved_manual: Dictionary = manual
	var saved_activations: Dictionary = activations
	beat += 1 # Dates belong to the endpoint of the next segment.
	strikes = []
	manual = manual.duplicate(true)
	activations = activations.duplicate(true)
	for uid in decision_order:
		var u: Dictionary = next_units[uid]
		u.frame_triggers = 0
		u.frame_branch = "等待决策"
		if u.hp <= 0: continue
		if u.mode == "碰撞":
			u.cell = u.return_cell
			u.mode = ""
			u.phase = "弹回"
			u.frame_branch = "碰撞：强制弹回"
			u.rule_kind = ""
			u.rule_slot = -1
			continue
		if try_pp(u, snapshot, old_strikes, proposals, supports): continue
		if u.mode == "移动硬直":
			u.frame_branch = ("PP" if u.rule_kind == "reaction" else "AP") + "：继续移动"
			advance_move(u, proposals)
			continue
		if not u.mode.is_empty():
			u.frame_branch = ("PP：" if u.rule_kind == "reaction" else "AP：") + u.mode
			advance_attack(u)
			continue
		if manual.has(u.uid) and u.pose == "站稳" and u.ult_charge >= 100 and u.energy >= 70:
			var skill := "天穹贯穿" if u.member == 0 else "星火轰炸"
			u.frame_triggers = 1
			u.frame_branch = "指挥官：" + skill
			u.rule_kind = "ultimate"
			u.rule_slot = -1
			start_attack(u, -1, skill, manual[u.uid])
			manual.erase(u.uid)
			advance_attack(u)
			continue
		try_ap(u, snapshot, proposals)
	next_segment = {"key": key, "units": next_units, "moves": proposals, "supports": supports,
		"strikes": strikes, "shots": shots, "manual": manual, "activations": activations}
	beat = saved_beat
	shots = saved_shots
	strikes = saved_strikes
	manual = saved_manual
	activations = saved_activations

func preview_segment() -> Dictionary:
	# Preview only trajectories and due effects; no HP, cell or decision is committed.
	if next_segment.is_empty() or next_segment.key != boundary_key(): choose_next_segment()
	var projected: Array = next_segment.units.duplicate(true)
	var saved_events: Array[String] = events
	events = []
	resolve_moves(units, projected, next_segment.moves, [0, 0, 0, 0])
	events = saved_events
	for u in projected:
		u.p = center(u.cell)
		u.hp = units[u.uid].hp
	var due: Array = []
	for strike in strikes + next_segment.strikes:
		if strike.at == beat + 1: due.append(strike.duplicate(true))
	return {"units": projected, "strikes": next_segment.strikes.duplicate(true), "effects": due, "beat": beat + 1}

func tick() -> void:
	# Only initial deployment or an explicit edit needs a plan at the starting point.
	if next_segment.is_empty() or next_segment.key != boundary_key(): choose_next_segment()
	var snapshot: Array = units.duplicate(true)
	var next_units: Array = next_segment.units.duplicate(true)
	var proposals: Dictionary = next_segment.moves.duplicate(true)
	var supports: Array = next_segment.supports
	strikes.append_array(next_segment.strikes.duplicate(true))
	shots = next_segment.shots
	manual = next_segment.manual.duplicate(true)
	activations = next_segment.activations.duplicate(true)
	beat += 1
	effects.clear()
	events.clear()
	boundary_stages.clear()
	var damage := [0, 0, 0, 0]
	# 1. Finish everyone's movement before testing any attack.
	resolve_moves(snapshot, next_units, proposals, damage)
	boundary_stages.append("格子更新")
	for u in next_units:
		if snapshot[u.uid].hp <= 0: continue
		var old: Dictionary = snapshot[u.uid]
		u.ult_charge = minf(100, u.ult_charge + SECONDS * 100 / 12.0) if u.ult_charge == old.ult_charge else u.ult_charge
		for skill in old.skill_cds.keys():
			if u.skill_cds.get(skill, 0) == old.skill_cds[skill]: u.skill_cds[skill] = maxf(0, old.skill_cds[skill] - SECONDS)
		u.hurt_recent = maxf(0, u.hurt_recent - SECONDS)
		u.marked = maxf(0, u.marked - SECONDS)
		u.slow = maxf(0, u.slow - SECONDS)
		u.guard = maxf(0, u.guard - SECONDS)
		if u.thorns > 0:
			u.thorns = maxf(0, u.thorns - SECONDS)
			u.thorn_tick -= SECONDS
			if u.thorn_tick <= 0: damage[u.uid] += THORN_DAMAGE; u.thorn_tick += 2.0
		u.shield_time = maxf(0, u.shield_time - SECONDS)
		if u.shield_time <= 0: u.shield = 0
		if old.mode in ["", "移动硬直"]:
			u.energy = minf(100, u.energy + minf(3, 100 - old.energy))
	# 2. Support and due attacks resolve against endpoint cells. Postures are not published yet.
	for support in supports:
		var u: Dictionary = next_units[support.target]
		match support.skill:
			"回春": u.hp = mini(MAX_HP, u.hp + HEAL)
			"灵木护佑": u.hp = mini(MAX_HP, u.hp + HEAL); u.shield = maxi(u.shield, WOOD_SHIELD); u.shield_time = 2.0
			"掩护队友": u.shield = maxi(u.shield, COVER_SHIELD); u.shield_time = 2.0
			"架枪防御": u.guard = 1.0
	hit_events = hit_events.filter(func(e): return e.beat >= beat - 1)
	var marks := [false, false, false, false]
	var slows := [false, false, false, false]
	var thorns := [false, false, false, false]
	for strike in strikes:
		if strike.at > beat: continue
		assert(typeof(strike.damage) == TYPE_INT and strike.damage >= 0, "Beat damage must be a nonnegative integer")
		effects.append(strike.duplicate(true))
		for u in next_units:
			if u.hp <= 0 or u.team == strike.team or u.cell not in strike.cells: continue
			var amount: int = int(strike.damage)
			if strike.skill == "强力射击" and u.marked > 0: amount += MARK_BONUS
			if u.guard > 0 and strike.skill not in ["火矢", "焰返", "烈焰爆破", "蓄能贯穿", "天穹贯穿"]: amount = maxi(0, amount - GUARD_REDUCTION)
			damage[u.uid] += amount
			if strike.skill == "标记弹": marks[u.uid] = true
			if strike.skill == "压制射击": slows[u.uid] = true
			if strike.skill == "荆棘": thorns[u.uid] = true
			if strike.skill not in ["协同追击", "追风"]: hit_events.append({"source": strike.source, "target": u.uid, "team": strike.team, "beat": beat})
			hits += 1
	strikes = strikes.filter(func(s): return s.at > beat)
	for u in next_units:
		assert(u.frame_triggers <= 1)
		assert(legal(u.cell))
		var absorbed: int = mini(u.shield, damage[u.uid])
		u.shield -= absorbed
		u.hp = maxi(0, u.hp - damage[u.uid] + absorbed)
		assert(typeof(u.hp) == TYPE_INT and u.hp >= 0 and u.hp <= MAX_HP)
		assert(typeof(u.shield) == TYPE_INT and u.shield >= 0)
		if damage[u.uid] > absorbed: u.hurt_recent = 1.0
		if marks[u.uid]: u.marked = 5.0
		if slows[u.uid]: u.slow = 2.5
		if thorns[u.uid]:
			if u.thorns <= 0: u.thorn_tick = 2.0
			u.thorns = 4.0
		u.p = center(u.cell)
		u.action_stage = u.mode if u.mode in ["前摇", "释放硬直", "后摇"] else ""
		u.stage_frames = u.left
		u.timer = u.left * SECONDS
	boundary_stages.append("攻击结算")
	# 3. Publish completed action transitions only after damage/status/death settlement.
	units = next_units
	boundary_stages.append("姿态更新")
	if not finished:
		var alive := [0, 0]
		for u in units:
			if u.hp > 0: alive[u.team] += 1
		if alive[0] == 0 or alive[1] == 0:
			finished = true
			winner = -1 if alive[0] == alive[1] else (0 if alive[0] > 0 else 1)
			result = "双方同时全灭" if winner == -1 else "对方全部倒下"
		elif beat >= 240:
			finished = true
			winner = -1
			result = "240拍结束，双方仍有存活角色"
	# 4. Choose the next segment from the fully settled shared endpoint snapshot.
	choose_next_segment()
	boundary_stages.append("下一拍决策")
