extends RefCounted
## Standalone, deterministic short encounter: two independent tracks per bot.
const LIMIT := 18
const START_MORALE := 3
const SHOT_CD := 6
const RANGE := 4
const CONDITIONS := ["无", "敌人站立", "敌人移动", "敌人收招", "敌人击发", "敌人距离≥3格", "敌人距离≤2格"]
const MOVE_ACTIONS := ["接敌", "远敌", "站立"]
const WEAPON_ACTIONS := ["吊射", "等待"]
var beat := 0
var morale := [START_MORALE, START_MORALE]
var units: Array = []
var profiles: Array = []
var walls: Array = []
var next_segment: Dictionary = {}
var history: Array = []
var finished := false
var winner := -1
var end_reason := ""
var decision_order := [0, 1]

static func player_profile() -> Dictionary:
	return {"move": {"condition": "敌人站立", "yes": ["远敌", "站立"], "no": ["接敌"]},
		"weapon": {"condition": "敌人收招", "yes": ["吊射"], "no": ["等待"]}}

static func enemy_profile(kind: int) -> Dictionary:
	var movement := {"condition": "无", "yes": ["站立"], "no": ["站立"]}
	if kind == 1: movement = {"condition": "敌人距离≥3格", "yes": ["接敌"], "no": ["站立"]}
	if kind == 2: movement = {"condition": "敌人距离≤2格", "yes": ["远敌"], "no": ["站立"]}
	if kind == 3: movement = {"condition": "无", "yes": ["接敌"], "no": ["站立"]}
	return {"move": movement, "weapon": {"condition": "无", "yes": ["吊射"], "no": ["等待"]}}

func reset(plans: Array, spawns: Array, obstacles: Array = []) -> void:
	assert(plans.size() == 2 and spawns.size() == 2 and spawns[0] != spawns[1])
	for profile in plans:
		for lane in ["move", "weapon"]:
			var rule: Dictionary = profile[lane]
			assert(rule.condition in CONDITIONS and rule.yes.size() in [1,2] and rule.no.size() == 1)
			assert(rule.yes.size() + rule.no.size() <= 3)
			for action in rule.yes + rule.no: assert(action in (MOVE_ACTIONS if lane == "move" else WEAPON_ACTIONS))
	profiles = plans.duplicate(true)
	walls = obstacles.duplicate()
	units.clear()
	for uid in range(2):
		units.append({"id": uid, "cell": spawns[uid], "pose": "站立", "direction": Vector2i.ZERO,
			"move_mode": "", "move_left": 0, "origin": spawns[uid], "destination": spawns[uid], "pending_direction": Vector2i.ZERO,
			"move_queue": [], "move_branch": "", "move_test": "", "move_action": "站立", "move_slot": -1,
			"weapon_mode": "", "weapon_queue": [], "weapon_branch": "", "weapon_test": "", "weapon_action": "等待", "weapon_slot": -1,
			"lock": Vector2i(-1, -1), "cd": 0})
	beat = 0
	morale = [START_MORALE, START_MORALE]
	history.clear()
	finished = false
	winner = -1
	end_reason = ""
	next_segment = calculate()

static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func legal(c: Vector2i) -> bool:
	return Rect2i(0, 0, 3, 3).has_point(c) and c not in walls

func condition(text: String, u: Dictionary, enemy: Dictionary) -> bool:
	match text:
		"无": return true
		"敌人站立": return enemy.pose == "站立"
		"敌人移动": return enemy.pose == "移动"
		"敌人收招": return enemy.weapon_mode == "后摇"
		"敌人击发": return enemy.weapon_mode == "击发"
		"敌人距离≥3格": return distance(u.cell, enemy.cell) >= 3
		"敌人距离≤2格": return distance(u.cell, enemy.cell) <= 2
	return false

func step_direction(u: Dictionary, enemy: Dictionary, away: bool) -> Vector2i:
	var costs := {enemy.cell: 0}
	var queue: Array = [enemy.cell]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for d in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = cell + d
			if legal(next) and not costs.has(next):
				costs[next] = int(costs[cell]) + 1
				queue.append(next)
	if not costs.has(u.cell): return Vector2i.ZERO
	var best: Vector2i = Vector2i.ZERO
	var value: int = costs[u.cell]
	var dirs := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT] if u.id == 0 else [Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i.RIGHT]
	for d in dirs:
		var next: Vector2i = u.cell + d
		if next == enemy.cell or not costs.has(next): continue
		var score: int = costs[next]
		if (score > value if away else score < value):
			best = d
			value = score
		elif score == value and best != Vector2i.ZERO and d == u.direction: best = d
	return best

func select_branch(u: Dictionary, enemy: Dictionary, kind: String) -> void:
	var rule: Dictionary = profiles[u.id][kind]
	var passed := condition(rule.condition, u, enemy)
	u[kind + "_branch"] = "yes" if passed else "no"
	u[kind + "_test"] = "%s → %s" % [rule.condition, "成立" if passed else "不成立"]
	u[kind + "_queue"] = rule[u[kind + "_branch"]].duplicate()
	u[kind + "_slot"] = 0

func advance_move(u: Dictionary, enemy: Dictionary) -> void:
	u.move_running_slot = u.get("move_running_slot", 0)
	if u.move_mode == "跨格":
		u.move_left -= 1
		u.move_action = "移动第2拍"
		if u.move_left == 0:
			u.cell = u.destination
			u.move_mode = ""
			u.move_queue.pop_front()
			u.move_slot += 1
		return
	if u.move_mode == "转向":
		# The previous segment already completed standing. Re-read direction for this item.
		u.move_mode = ""
	if u.move_queue.is_empty(): select_branch(u, enemy, "move")
	u.move_running_slot = u.move_slot
	var action: String = u.move_queue[0]
	if action == "站立":
		u.pose = "站立"
		u.direction = Vector2i.ZERO
		u.move_action = "站立1拍"
		u.move_queue.pop_front()
		u.move_slot += 1
		return
	var d := step_direction(u, enemy, action == "远敌")
	if d == Vector2i.ZERO:
		u.move_action = action + "无路 · 等待"
		u.pose = "站立"
		u.direction = Vector2i.ZERO
		u.move_queue.clear() # A blocked route waits one beat, then rechecks its own condition.
		u.move_slot = -1
		return
	if u.pose == "移动" and u.direction != d:
		u.pose = "站立"
		u.direction = Vector2i.ZERO
		u.move_mode = "转向"
		u.move_action = "换向先站立"
		return
	u.origin = u.cell
	u.destination = u.cell + d
	u.pose = "移动"
	u.direction = d
	u.move_mode = "跨格"
	u.move_left = 1
	u.move_action = action + "第1拍"

func advance_weapon(u: Dictionary, enemy: Dictionary, shots: Array) -> void:
	match u.weapon_mode:
		"击发":
			u.weapon_action = "击发"
			shots.append({"source": u.id, "from": u.cell, "cell": u.lock})
			u.cd = SHOT_CD
			u.weapon_mode = "后摇"
			return
		"后摇":
			u.weapon_action = "后摇"
			u.weapon_mode = ""
			u.weapon_queue.pop_front()
			u.weapon_slot += 1
			return
	if u.cd > 0:
		u.weapon_action = "冷却 · 等待"
		return
	if u.weapon_queue.is_empty(): select_branch(u, enemy, "weapon")
	u.weapon_running_slot = u.weapon_slot
	var action: String = u.weapon_queue[0]
	if action == "等待":
		u.weapon_action = "等待1拍"
		u.weapon_queue.pop_front()
		u.weapon_slot += 1
		return
	if u.cd > 0:
		u.weapon_action = "冷却 · 等待"
		return
	if distance(u.cell, enemy.cell) > RANGE:
		u.weapon_action = "超射程 · 等待"
		return
	u.lock = enemy.cell
	u.weapon_action = "瞄准"
	u.weapon_mode = "击发"

func calculate() -> Dictionary:
	var next := units.duplicate(true)
	var shots: Array = []
	for uid in decision_order:
		# Both tracks see the same published endpoint, including the shooter's old cell.
		advance_weapon(next[uid], units[1 - uid], shots)
		advance_move(next[uid], units[1 - uid])
		if units[uid].cd > 0: next[uid].cd = maxi(0, units[uid].cd - 1)
	var collision: bool = (next[0].cell == next[1].cell or (next[0].cell == units[1].cell and next[1].cell == units[0].cell))
	if collision:
		for uid in range(2):
			next[uid].cell = units[uid].cell
			next[uid].move_mode = ""
			next[uid].pose = "站立"
			next[uid].direction = Vector2i.ZERO
			next[uid].move_action = "争位阻挡"
	var next_morale := morale.duplicate()
	for shot in shots:
		shot.hit = next[1 - shot.source].cell == shot.cell
		if shot.hit: next_morale[1 - shot.source] = maxi(0, next_morale[1 - shot.source] - 1)
	return {"units": next, "shots": shots, "morale": next_morale, "collision": collision}

func tick() -> void:
	if finished: return
	var before: Array = units.duplicate(true)
	units = next_segment.units
	morale = next_segment.morale
	beat += 1
	var record := {"beat": beat, "morale": morale.duplicate(), "units": units.duplicate(true), "shots": next_segment.shots.duplicate(true), "collision": next_segment.collision}
	history.append(record)
	for uid in range(2):
		assert(legal(units[uid].cell))
		assert(distance(units[uid].cell, before[uid].cell) <= 1)
		assert(units[uid].move_queue.size() <= 2 and units[uid].weapon_queue.size() <= 2)
	if 0 in morale or beat >= LIMIT:
		finished = true
		winner = -1 if morale[0] == morale[1] else (0 if morale[0] > morale[1] else 1)
		end_reason = "士气归零" if 0 in morale else "18拍交锋结束"
		next_segment = {}
	else: next_segment = calculate()

func run() -> Dictionary:
	while not finished: tick()
	var shots := [0, 0]
	var hits := [0, 0]
	var concurrent := [0, 0]
	for row in history:
		for shot in row.shots:
			shots[shot.source] += 1
			if shot.hit: hits[shot.source] += 1
		for uid in range(2):
			if row.units[uid].move_action in ["移动第2拍", "接敌第1拍", "远敌第1拍"] and row.units[uid].weapon_action in ["瞄准", "击发", "后摇"]: concurrent[uid] += 1
	return {"winner": winner, "morale": morale.duplicate(), "beats": beat, "shots": shots, "hits": hits, "concurrent": concurrent, "history": history.duplicate(true)}
