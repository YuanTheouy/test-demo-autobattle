extends "res://scripts/battle.gd"

# Grid simulation. p is always the occupied cell center; movement is animated separately.
const CELL := 80.0
const DIRS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
var pending: Array = []
var grid_fx: Array = []
var tick_number := 0

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Heiti SC", "Arial"])
	DisplayServer.window_set_title("AutoBattle — 格子战术实验 / grid-tactics")
	setup_loadouts()
	setup_ui()
	update_grid_labels(self)
	status_label.position.y = 94
	reset_round()
	if "--grid-test" in OS.get_cmdline_user_args():
		run_grid_tests()
		get_tree().quit()
	elif "--batch-test" in OS.get_cmdline_user_args():
		run_grid_matches()
		get_tree().quit()
	elif "--preview" in OS.get_cmdline_user_args() or "--demo" in OS.get_cmdline_user_args():
		started = true
		running = true

func update_grid_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label:
			if child.text.begins_with("消灭对方"): child.text = "整格移动 · 固定8×8地图 · 消灭对方获胜 / 60秒平局"
			if child.text.begins_with("反应 ·"): child.text = "反应 · 事件触发；移动、前摇与收招期间不能插入"
			if child.text.begins_with("AUTOBATTLE"): child.text = "AUTOBATTLE  /  格子战术"
		update_grid_labels(child)
	skill_help.text = "步行 / 闪避：相邻1格 · 攻击距离：曼哈顿3格\n贯穿一列 · 霰弹扇形 · 炮击十字；亮格才会命中"

func setup_navigation() -> void: pass
func refresh_boundary_navigation() -> void: pass

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func center(c: Vector2i) -> Vector2:
	return Vector2(c) * CELL + Vector2.ONE * CELL / 2

func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func ground(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= 8 or c.y >= 8: return false
	for wall in walls:
		if wall.has_point(center(c)): return false
	return true

func free_cell(c: Vector2i, uid: int) -> bool:
	if not ground(c): return false
	for u in units:
		if u.uid == uid or u.hp <= 0: continue
		if cell_of(u.p) == c or (u.get("moving", false) and u.move_to == c): return false
	return true

func reset_round() -> void:
	super.reset_round()
	pending.clear()
	grid_fx.clear()
	tick_number = 0
	for u in units:
		u.p = center(cell_of(u.p))
		u.moving = false
		u.move_to = cell_of(u.p)
		u.move_left = 0.0
		u.move_total = 0.0
		u.phase = "待命"
		u.attack_cells = []
		u.last_cell = Vector2i(-1, -1)
		u.pp_seen = {}
	refresh_ui()

func refresh_ui() -> void:
	if not is_instance_valid(status_label) or units.is_empty(): return
	super.refresh_ui()
	status_label.text = "实时格子战术 · %04.1f 秒 · 每次移动一整格" % maxf(clock, 0)
	var u: Dictionary = units[editor_unit]
	var c := cell_of(u.p)
	info_label.text = "%s%d · HP %d/4 · 格子 %s%d · %s\n%s" % ["蓝" if u.team == 0 else "红", u.member + 1, u.hp, char(65 + c.x), c.y + 1, u.phase, u.reason]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: toggle_running()
		if event.keycode == KEY_R: reset_round()
		if event.keycode == KEY_N: step_forward()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var c := cell_of(get_global_mouse_position() - ORIGIN)
		for u in units:
			if cell_of(u.p) == c:
				selected = u.uid
				editor_unit = u.uid
				unit_menu.select(editor_unit)
				rebuild_editor()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not started and selected >= 0:
		var u: Dictionary = units[selected]
		var c := cell_of(get_global_mouse_position() - ORIGIN)
		if u.team == 0 and (c.x < 2 if u.attack else c.x >= 6) and free_cell(c, u.uid): u.p = center(c)
	refresh_ui()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if running: advance_playback(delta)
	refresh_ui()
	queue_redraw()
	if "--preview" in OS.get_cmdline_user_args():
		preview_frames += 1
		if preview_frames == 600: capture_preview.call_deferred()

func passes_condition(u: Dictionary, target: int, condition: String) -> bool:
	if condition == "敌人距离≤2格": return target >= 0 and distance(cell_of(u.p), cell_of(units[target].p)) <= 2
	if condition == "敌人距离≥3格": return target >= 0 and distance(cell_of(u.p), cell_of(units[target].p)) >= 3
	return super.passes_condition(u, target, condition)

func contacts(team: int) -> Array[int]:
	var found: Array[int] = []
	for enemy in units:
		if enemy.hp <= 0 or enemy.team == team: continue
		for ally in units:
			if ally.hp > 0 and ally.team == team and distance(cell_of(ally.p), cell_of(enemy.p)) <= 5 and not blocked(ally.p, enemy.p):
				found.append(enemy.uid)
				break
	return found

func facing(a: Vector2i, b: Vector2i) -> Vector2i:
	var d := b - a
	if absi(d.x) >= absi(d.y): return Vector2i(1 if d.x >= 0 else -1, 0)
	return Vector2i(0, 1 if d.y >= 0 else -1)

func attack_pattern(skill: String, from: Vector2i, target: Vector2i) -> Array:
	var cells: Array = []
	var forward := facing(from, target)
	if skill == "抛射轰击":
		for d in [Vector2i.ZERO] + DIRS:
			if ground(target + d): cells.append(target + d)
	elif skill == "蓄能贯穿":
		for step in range(1, 4):
			var c := from + forward * step
			if not ground(c): break
			cells.append(c)
	elif skill == "霰弹":
		var side := Vector2i(-forward.y, forward.x)
		for step in range(1, 3):
			for spread in range(-(step - 1), step):
				var c := from + forward * step + side * spread
				if ground(c) and not blocked(center(from), center(c)): cells.append(c)
	elif ground(target): cells.append(target)
	return cells

func can_attack(u: Dictionary, target: int, skill: String) -> bool:
	if target < 0 or units[target].hp <= 0 or u.cooldown > 0: return false
	var a := cell_of(u.p)
	var b := cell_of(units[target].p)
	if distance(a, b) > 3 or blocked(u.p, units[target].p): return false
	return b in attack_pattern(skill, a, b)

func grid_target(u: Dictionary, candidates: Array, rule: Array, shooting: bool) -> int:
	var allowed: Array = []
	for i in candidates:
		if units[i].hp <= 0: continue
		if shooting and not can_attack(u, i, rule[0]): continue
		if not passes_condition(u, i, rule[1]) or not passes_condition(u, i, rule[2]): continue
		allowed.append(i)
	for condition in [rule[1], rule[2]]:
		if allowed.is_empty(): break
		if condition == "优先队友目标":
			var ally := ally_index(u)
			if ally >= 0 and units[ally].target in allowed: allowed = [units[ally].target]
		elif condition == "优先低血量":
			var lowest := 5.0
			for i in allowed: lowest = minf(lowest, units[i].hp)
			allowed = allowed.filter(func(i): return units[i].hp == lowest)
		elif condition == "优先最近敌人":
			var nearest := 99
			for i in allowed: nearest = mini(nearest, distance(cell_of(u.p), cell_of(units[i].p)))
			allowed = allowed.filter(func(i): return distance(cell_of(u.p), cell_of(units[i].p)) == nearest)
	var best := -1
	for i in allowed:
		if best < 0 or distance(cell_of(u.p), cell_of(units[i].p)) < distance(cell_of(u.p), cell_of(units[best].p)): best = i
	return best

func begin_grid_attack(u: Dictionary, target: int, skill: String) -> void:
	u.target = target
	u.active_skill = skill
	u.attack_cells = attack_pattern(skill, cell_of(u.p), cell_of(units[target].p))
	u.phase = "吟唱"
	u.timer = {"蓄能贯穿": 1.1, "霰弹": 0.55, "抛射轰击": 0.65, "落岩": 0.8, "震山": 0.7}.get(skill, 0.35)
	u.cast_total = u.timer
	u.angle = (units[target].p - u.p).angle()
	u.intent = skill
	u.reason = "已锁定高亮格；前摇结束后出手"

func launch(u: Dictionary) -> void:
	var skill: String = u.active_skill
	var delay := 0.0 if skill == "蓄能贯穿" else (0.8 if skill == "抛射轰击" else 0.25)
	var count := 2 if skill in ["风刃", "追风"] else 1
	for shot in range(count):
		pending.append({"cells": u.attack_cells.duplicate(), "team": u.team, "source": u.uid, "skill": skill, "left": delay + shot * 0.35, "total": delay + shot * 0.35, "origin": u.p, "damage": shot_damage(skill), "id": tick_number * 16 + u.uid * 2 + shot})
		shots += 1
	u.phase = "收招"
	u.reason = "攻击已出手；收招结束后重新检查 AP"
	u.timer = 0.85 if skill in ["落岩", "震山", "蓄能贯穿", "强力射击"] else 0.6
	u.fire_flash = 0.18

func start_step(u: Dictionary, c: Vector2i, duration := 0.55) -> bool:
	if u.get("moving", false) or distance(cell_of(u.p), c) != 1 or not free_cell(c, u.uid): return false
	u.moving = true
	u.move_to = c
	u.move_total = duration * (1.5 if u.slow > 0 else 1.0)
	u.move_left = u.move_total
	u.phase = "移动"
	u.reason = "移动到 %s%d；到达后重新检查规则" % [char(65 + c.x), c.y + 1]
	return true

func first_step(u: Dictionary, goal: Vector2i) -> Vector2i:
	var start := cell_of(u.p)
	var queue: Array = [start]
	var previous := {start: start}
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == goal:
			while previous[c] != start and c != start: c = previous[c]
			return c
		for d in DIRS:
			var next: Vector2i = c + d
			if next not in previous and free_cell(next, u.uid):
				previous[next] = c
				queue.append(next)
	return start

func movement_skill(u: Dictionary, target: int, skill: String) -> bool:
	var best := cell_of(u.p)
	var score := -INF
	var enemy := cell_of(units[target].p)
	var forward := facing(best, enemy)
	for d in DIRS:
		var c: Vector2i = cell_of(u.p) + d
		if not free_cell(c, u.uid): continue
		var value: float = distance(c, enemy) if skill == "后撤" else -distance(c, enemy)
		if skill == "绕侧": value = 2.0 if Vector2(d).dot(Vector2(forward)) == 0 else -2.0
		if value > score: score = value; best = c
	if best == cell_of(u.p): return false
	return start_step(u, best, 0.25 if skill == "短冲刺" else 0.55)

func active_choice(u: Dictionary, visible: Array) -> bool:
	for slot in range(loadouts[u.uid].active.size()):
		var rule: Array = loadouts[u.uid].active[slot]
		var skill: String = rule[0]
		if skill == "留空" or u.skill_cds.get(skill, 0.0) > 0: continue
		var movement: bool = skill in ["短冲刺", "后撤", "绕侧"]
		var target := grid_target(u, visible, rule, not movement)
		if target < 0: continue
		if movement:
			if not movement_skill(u, target, skill): continue
		else: begin_grid_attack(u, target, skill)
		u.skill_cds[skill] = Tactics.MAGIC.get(skill, {}).get("cd", 3.0)
		record_rule(u, "主动", slot, skill)
		return true
	return false

func danger_cells(team: int) -> Array:
	var danger: Array = []
	for enemy in units:
		if enemy.hp > 0 and enemy.team != team and enemy.phase == "吟唱":
			for c in enemy.attack_cells:
				if c not in danger: danger.append(c)
	for attack in pending:
		if attack.team != team:
			for c in attack.cells:
				if c not in danger: danger.append(c)
	return danger

func escape_cell(u: Dictionary) -> Vector2i:
	var danger := danger_cells(u.team)
	var origin := cell_of(u.p)
	for d in DIRS:
		if free_cell(origin + d, u.uid) and origin + d not in danger: return origin + d
	return origin

func threat_sources(u: Dictionary) -> Array:
	var sources: Array = []
	var c := cell_of(u.p)
	for enemy in units:
		if enemy.hp > 0 and enemy.team != u.team and enemy.phase == "吟唱" and c in enemy.attack_cells: sources.append(enemy.uid)
	for attack in pending:
		if attack.team != u.team and c in attack.cells and attack.source not in sources: sources.append(attack.source)
	return sources

func reaction_choice(u: Dictionary, visible: Array) -> bool:
	var threats := threat_sources(u)
	for slot in range(loadouts[u.uid].reaction.size()):
		var rule: Array = loadouts[u.uid].reaction[slot]
		var skill: String = rule[0]
		if skill == "留空" or u.skill_cds.get(skill, 0.0) > 0: continue
		var targets: Array = threats.duplicate()
		var ally := ally_index(u)
		if skill == "回春":
			var recipient := -1
			for other in units:
				if other.hp <= 0 or other.hp >= 4 or other.team != u.team or other.hurt_recent <= 0: continue
				if distance(cell_of(u.p), cell_of(other.p)) > 3 or blocked(u.p, other.p): continue
				if not passes_condition(u, other.uid, rule[1]) or not passes_condition(u, other.uid, rule[2]): continue
				if recipient < 0 or other.hp < units[recipient].hp: recipient = other.uid
			if recipient < 0: continue
			units[recipient].hp = minf(4, units[recipient].hp + 1)
			units[recipient].heal_flash = 0.5
		elif skill == "掩护队友":
			if ally < 0 or units[ally].shield > 0 or distance(cell_of(u.p), cell_of(units[ally].p)) > 3 or blocked(u.p, units[ally].p): continue
			targets = threat_sources(units[ally])
			if grid_target(u, targets, rule, false) < 0: continue
			units[ally].shield = 1
			units[ally].shield_time = 2
		else:
			if skill in ["协同追击", "追风"]:
				targets = []
				for e in hit_events:
					if e.team == u.team and e.source != u.uid and e.target in visible: targets.append(e.target)
			var shooting: bool = skill not in ["侧闪", "架枪防御"]
			var target := grid_target(u, targets, rule, shooting)
			if target < 0: continue
			if skill == "侧闪":
				var c := escape_cell(u)
				if c == cell_of(u.p) or not start_step(u, c, 0.25): continue
			elif skill == "架枪防御": u.guard = 1.2
			else: begin_grid_attack(u, target, skill)
		u.skill_cds[skill] = 3.5
		if not u.moving and u.phase != "吟唱": u.phase = "收招"; u.timer = 0.45
		record_rule(u, "反应", slot, skill)
		return true
	# Lowest-priority reaction: ordinary movement to an unthreatened adjacent tile.
	if not threats.is_empty():
		var c := escape_cell(u)
		if c != cell_of(u.p) and start_step(u, c):
			u.intent = "基础避险"
			return true
	return false

func baseline_grid(u: Dictionary, visible: Array) -> void:
	u.rule_kind = ""
	u.rule_slot = -1
	u.rule_flash = 0
	var target := grid_target(u, visible, ["点射", "优先最近敌人", "无"], true)
	if target >= 0:
		begin_grid_attack(u, target, "点射")
		u.intent = "基础攻击"
		return
	# A valid firing tile remains useful while the weapon is cooling down.
	for i in visible:
		if distance(cell_of(u.p), cell_of(units[i].p)) <= 3 and not blocked(u.p, units[i].p):
			u.phase = "待命"
			u.reason = "保持射位，等待武器恢复"
			return
	var goal := cell_of(u.p)
	var best := INF
	for x in range(8):
		for y in range(8):
			var c := Vector2i(x, y)
			if not free_cell(c, u.uid): continue
			var cost: float = distance(cell_of(u.p), c)
			if not visible.is_empty():
				var can_fire := false
				for i in visible:
					if distance(c, cell_of(units[i].p)) <= 3 and not blocked(center(c), units[i].p): can_fire = true
				if not can_fire: continue
			else:
				var search: Vector2i = u.last_cell if u.memory > 0 else [Vector2i(3, 3), Vector2i(4, 4), Vector2i(2, 5), Vector2i(5, 2)][(u.patrol + u.member * 2) % 4]
				cost += distance(c, search) * 5
			if c in danger_cells(u.team): cost += 20
			if cost < best and first_step(u, c) != cell_of(u.p): best = cost; goal = c
	var step := first_step(u, goal)
	if step == cell_of(u.p): u.patrol += 1; u.phase = "待命"; return
	start_step(u, step)
	u.intent = "基础接敌" if not visible.is_empty() else "基础搜寻"

func simulate(dt: float) -> void:
	clock -= dt
	tick_number += 1
	for fx in grid_fx: fx.life -= dt
	grid_fx = grid_fx.filter(func(fx): return fx.life > 0)
	for e in hit_events: e.life -= dt
	hit_events = hit_events.filter(func(e): return e.life > 0)
	for u in units:
		if u.hp <= 0: continue
		for key in ["cooldown", "marked", "guard", "slow", "hurt_recent", "heal_flash", "shield_time", "memory", "rule_flash", "fire_flash"]: u[key] = maxf(0, u[key] - dt)
		if u.shield_time <= 0: u.shield = 0
		for key in u.skill_cds: u.skill_cds[key] = maxf(0, u.skill_cds[key] - dt)
		if u.thorns > 0:
			u.thorns -= dt
			u.thorn_tick -= dt
			if u.thorn_tick <= 0:
				apply_grid_damage(u, 1)
				u.thorn_tick += 2
		if u.moving:
			u.move_left -= dt
			if u.move_left <= 0:
				u.p = center(u.move_to)
				u.moving = false
				u.phase = "待命"
		elif u.phase == "吟唱":
			u.timer -= dt
			if u.timer <= 0: launch(u)
		elif u.phase == "收招":
			u.timer -= dt
			if u.timer <= 0: u.phase = "待命"; u.cooldown = 0.4
	resolve_grid_impacts(dt)
	# Rotate decision order; occupancy reservations prevent overlaps and head-on swaps.
	for offset in range(4):
		var u: Dictionary = units[(tick_number + offset) % 4]
		if u.hp <= 0 or u.moving or u.phase in ["吟唱", "收招"]: continue
		var visible := contacts(u.team)
		if not visible.is_empty(): u.last_cell = cell_of(units[visible[0]].p); u.memory = 5
		if reaction_choice(u, visible): continue
		if not active_choice(u, visible): baseline_grid(u, visible)
	var alive := [0, 0]
	for u in units:
		if u.hp > 0: alive[u.team] += 1
	if alive[0] == 0 or alive[1] == 0: end_round(-1 if alive[0] == alive[1] else (0 if alive[0] > 0 else 1), "小队被消灭")
	elif clock <= 0: end_round(-1, "60秒超时")

func apply_grid_damage(u: Dictionary, amount: float) -> void:
	var absorbed: float = minf(u.shield, amount)
	u.shield -= absorbed
	u.hp = maxf(0, u.hp - amount + absorbed)
	if amount > absorbed: u.hurt_recent = 0.8
	if u.hp <= 0: u.moving = false

func resolve_grid_impacts(dt: float) -> void:
	var damage := [0.0, 0.0, 0.0, 0.0]
	for a in pending:
		a.left -= dt
		if a.left > 0: continue
		for u in units:
			if u.hp <= 0 or u.team == a.team or cell_of(u.p) not in a.cells: continue
			var true_hit: bool = a.skill in ["火矢", "焰返", "蓄能贯穿"]
			var amount: float = a.damage + (1 if a.skill == "强力射击" and u.marked > 0 else 0)
			damage[u.uid] += maxf(0, amount - (1 if u.guard > 0 and not true_hit else 0))
			if a.skill == "标记弹": u.marked = 5
			if a.skill == "压制射击": u.slow = 2.4
			if a.skill == "荆棘":
				if u.thorns <= 0: u.thorn_tick = 2
				u.thorns = 4
			if a.skill not in ["协同追击", "追风"]: hit_events.append({"source": a.source, "team": a.team, "target": u.uid, "life": 0.8})
			hits += 1
		grid_fx.append({"cells": a.cells, "life": 0.3, "team": a.team})
	for u in units:
		if u.hp > 0: apply_grid_damage(u, damage[u.uid])
	pending = pending.filter(func(a): return a.left > 0)

func paint_cells(cells: Array, color: Color, alpha := 0.2) -> void:
	for c in cells:
		var rect := Rect2(ORIGIN + Vector2(c) * CELL + Vector2.ONE * 2, Vector2.ONE * (CELL - 4))
		draw_rect(rect, Color(color, alpha))
		draw_rect(rect, Color(color, minf(1, alpha * 3)), false, 2)

func _draw() -> void:
	for x in range(8):
		for y in range(8):
			var c := Vector2i(x, y)
			var rect := Rect2(ORIGIN + Vector2(c) * CELL, Vector2.ONE * CELL)
			draw_rect(rect, Color("142330") if (x + y) % 2 == 0 else Color("182a38"))
			draw_rect(rect, Color("405360"), false, 1)
			if not ground(c):
				draw_rect(rect.grow(-3), Color("516978"))
				draw_line(rect.position + Vector2(12, 12), rect.end - Vector2(12, 12), Color("78909e"), 2)
	for i in range(8):
		draw_string(font, ORIGIN + Vector2(i * CELL + 34, -5), char(65 + i), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.SLATE_GRAY)
		draw_string(font, ORIGIN + Vector2(-18, i * CELL + 45), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.SLATE_GRAY)
	if show_aim and selected >= 0:
		var u: Dictionary = units[selected]
		var range_cells: Array = []
		for x in range(8):
			for y in range(8):
				var c := Vector2i(x, y)
				if ground(c) and distance(cell_of(u.p), c) <= 3 and not blocked(u.p, center(c)): range_cells.append(c)
		paint_cells(range_cells, Color("d4e4ee"), 0.08)
	if show_aim:
		for u in units:
			if u.hp > 0 and u.phase == "吟唱": paint_cells(u.attack_cells, BLUE if u.team == 0 else RED, 0.20)
		for a in pending: paint_cells(a.cells, BLUE if a.team == 0 else RED, 0.28)
	for fx in grid_fx: paint_cells(fx.cells, GOLD, fx.life * 1.8)
	for a in pending:
		if a.total <= 0: continue
		for c in a.cells:
			var t: float = clampf(1 - a.left / a.total, 0, 1)
			var p: Vector2 = a.origin.lerp(center(c), t)
			if a.skill == "抛射轰击": p.y -= sin(t * PI) * 65
			draw_circle(ORIGIN + p, 4, GOLD)
	for u in units:
		var color: Color = BLUE if u.team == 0 else RED
		var p: Vector2 = u.p
		if u.moving:
			p = u.p.lerp(center(u.move_to), clampf(1 - u.move_left / u.move_total, 0, 1))
			paint_cells([cell_of(u.p)], color, 0.06)
			draw_dashed_line(ORIGIN + u.p, ORIGIN + center(u.move_to), color, 1, 5)
			if show_aim: paint_cells([u.move_to], color, 0.08)
		p += ORIGIN
		if u.hp <= 0:
			draw_line(p - Vector2(8, 8), p + Vector2(8, 8), color.darkened(0.5), 3)
			continue
		draw_circle(p, 23, color)
		draw_line(p, p + Vector2.from_angle(u.angle) * 31, color.lightened(0.4), 4)
		draw_string(font, p + Vector2(-7, 8), str(u.member + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("102033"))
		for pip in range(4): draw_rect(Rect2(p + Vector2(-23 + pip * 12, -34), Vector2(9, 6)), color if pip < u.hp else Color("354450"))
		if u.shield > 0: draw_arc(p, 27, 0, TAU, 24, Color.CYAN, 2)
		if u.guard > 0: draw_arc(p, 30, 0, TAU, 24, GOLD, 3)
		if selected == u.uid: draw_arc(p, 26, 0, TAU, 24, Color.WHITE, 1)
		if u.phase == "吟唱": draw_arc(p, 29, -PI / 2, -PI / 2 + TAU * (1 - u.timer / u.cast_total), 24, GOLD, 3)
		draw_string(font, p + Vector2(-30, 40), u.intent, HORIZONTAL_ALIGNMENT_LEFT, 100, 11, color.lightened(0.3))

func validate_grid() -> void:
	var occupied: Array = []
	var reservations: Array = []
	for u in units:
		if u.hp <= 0: continue
		var c := cell_of(u.p)
		assert(u.p == center(c) and ground(c), "Logical position must be a legal cell center")
		assert(c not in occupied, "Units cannot share a cell")
		occupied.append(c)
		assert(u.hp == floorf(u.hp) and u.hp <= 4)
		if u.moving:
			assert(distance(c, u.move_to) == 1 and ground(u.move_to))
			assert(u.move_to not in reservations, "No duplicate destination reservations")
			reservations.append(u.move_to)
	for c in reservations: assert(c not in occupied, "Reserved destination must not contain another actor")

func run_grid_matches() -> void:
	var rows: Array = []
	for opponent in range(7):
		for side in [false, true]:
			team_presets = [5, opponent]
			blue_attacks = side
			setup_loadouts()
			reset_round()
			for tick in range(3602):
				if finished: break
				simulate(STEP)
				validate_grid()
			assert(finished and shots > 0)
			rows.append({"blue": 5, "red": opponent, "blue_left": side, "winner": winner_team, "shots": shots, "hits": hits, "seconds": ROUND_TIME - clock})
	var file := FileAccess.open("res://reports/grid-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	print("GRID MATCHES PASSED: 14 matches, legal cell centers, exclusive occupancy and reservations, integer health")

func run_grid_tests() -> void:
	reset_round()
	validate_grid()
	assert(not ground(Vector2i(3, 1)) and not ground(Vector2i(4, 6)))
	assert(not start_step(units[0], cell_of(units[0].p) + Vector2i(1, 1)))
	assert(not start_step(units[0], cell_of(units[0].p) + Vector2i(0, 2)))
	for u in units: loadouts[u.uid] = Tactics.build([], [])
	units[0].p = center(Vector2i(1, 3))
	units[1].p = center(Vector2i(3, 3))
	assert(start_step(units[0], Vector2i(2, 3)))
	assert(not start_step(units[1], Vector2i(2, 3)), "Second actor cannot reserve the same tile")
	assert(not start_step(units[1], Vector2i(1, 3)), "Cannot step through the occupied origin")
	var old: Vector2 = units[0].p
	simulate(STEP)
	assert(units[0].p == old, "Animation must not move logical occupancy into a fractional cell")
	var cross := attack_pattern("抛射轰击", Vector2i(1, 3), Vector2i(2, 4))
	assert(cross.size() == 5 and Vector2i(2, 4) in cross and Vector2i(1, 3) not in cross)
	var line := attack_pattern("蓄能贯穿", Vector2i(1, 3), Vector2i(3, 3))
	assert(line == [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)])
	assert(attack_pattern("蓄能贯穿", Vector2i(1, 1), Vector2i(4, 1)) == [Vector2i(2, 1)])
	var cone := attack_pattern("霰弹", Vector2i(1, 3), Vector2i(3, 3))
	assert(Vector2i(2, 3) in cone and Vector2i(3, 3) in cone and Vector2i(1, 4) not in cone)
	# Damage and highlighted tiles share exactly the same cell list.
	reset_round()
	units[2].p = center(Vector2i(2, 4))
	units[3].p = center(Vector2i(1, 3))
	pending.append({"cells": cross, "source": 0, "team": 0, "skill": "抛射轰击", "damage": 1, "left": 0.2, "total": 0.2, "origin": units[0].p})
	resolve_grid_impacts(0.1)
	assert(units[2].hp == 4)
	resolve_grid_impacts(0.11)
	assert(units[2].hp == 3 and units[3].hp == 4)
	# Configured guard must win over basic walking evade.
	reset_round()
	units[0].p = center(Vector2i(1, 3))
	units[2].p = center(Vector2i(3, 3))
	begin_grid_attack(units[2], 0, "点射")
	loadouts[0] = Tactics.build([], [["架枪防御", "无", "无"]])
	assert(reaction_choice(units[0], [2]) and units[0].guard > 0 and not units[0].moving)
	# Configured AP wins over normal shot. Empty AP still fights.
	reset_round()
	units[0].p = center(Vector2i(1, 3))
	units[2].p = center(Vector2i(3, 3))
	loadouts[0] = Tactics.build([["风刃", "无", "无"]], [])
	assert(active_choice(units[0], [2]) and units[0].active_skill == "风刃")
	reset_round()
	for u in units: loadouts[u.uid] = Tactics.build([], [])
	for tick in range(3602):
		if finished: break
		simulate(STEP)
		validate_grid()
	assert(finished and shots > 0 and hits > 0)
	# Playback is presentation only, including moves in progress.
	var snapshots: Array = []
	setup_loadouts()
	for playback in [0.5, 1.0, 2.0]:
		reset_round()
		running = true
		speed = playback
		for frame in range(int(120 / playback)): advance_playback(STEP)
		var state: Array = [shots, hits, snappedf(clock, 0.0001)]
		for u in units: state.append([u.p, u.hp, u.phase, u.move_to, snappedf(u.move_left, 0.0001)])
		snapshots.append(state)
	assert(snapshots[0] == snapshots[1] and snapshots[1] == snapshots[2])
	run_grid_matches()
	print("GRID TESTS PASSED: cardinal one-tile movement, no stacking, shape/impact equality, wall stopping, AP/PP fallback priority, empty rules fight, fixed-step playback")

func grid_description(skill: String) -> String:
	var descriptions := {
		"留空": "基础行为兜底：攻击、逐格接敌、搜寻；遇到预警时尝试走向相邻安全格。",
		"标记弹": "射程3格，锁定1格，1伤害并标记5秒。冷却3秒。",
		"强力射击": "射程3格，锁定1格，2伤害；标记目标额外1伤害。冷却3秒。",
		"压制射击": "射程3格，锁定1格，1伤害并减速2.4秒。冷却3秒。",
		"绕侧": "向敌人侧面移动相邻1格，耗时0.55秒。冷却3秒。",
		"后撤": "远离目标移动相邻1格，耗时0.55秒。冷却3秒。",
		"短冲刺": "向目标移动相邻1格，耗时0.25秒，不穿人或墙。冷却3秒。",
		"侧闪": "被技能格覆盖时，移动到相邻安全格，耗时0.25秒。冷却3.5秒。",
		"架枪防御": "受到攻击预警时，1.2秒内每次非真实伤害减1；收招0.45秒。冷却3.5秒。",
		"掩护队友": "队友受威胁时给予1盾，持续2秒；距离3格且无遮挡。冷却3.5秒。",
		"协同追击": "队友命中后向同一敌人的格子追加1伤害；射程3格，不触发追击链。冷却3.5秒。",
		"风刃": "射程3格，锁定1格，两发各1伤害、间隔0.35秒。冷却3.2秒。",
		"追风": "队友命中后锁定同一敌人格，两发各1伤害；不触发追击链。冷却3.5秒。",
		"火矢": "射程3格，锁定1格，1真实伤害，无视防御、受盾吸收。冷却3.4秒。",
		"焰返": "受到威胁时向攻击者的格子发射1真伤；射程3格。冷却3.5秒。",
		"落岩": "射程3格，蓄力0.8秒后攻击锁定格，2伤害。冷却4.5秒。",
		"震山": "受到威胁时蓄力0.7秒，向攻击者锁定格发射2伤害。冷却3.5秒。",
		"荆棘": "射程3格，命中格附加荆棘：4秒内每2秒1伤害。冷却4.5秒。",
		"回春": "自己或队友刚受伤时治疗1HP；距离3格且无遮挡，不超过4HP。冷却3.5秒。",
		"蓄能贯穿": "蓄力1.1秒，瞬发攻击横向或纵向连续3格，2真伤；穿人不穿墙。冷却5秒。",
		"霰弹": "准备0.55秒后攻击前方扇形：第一排1格、第二排3格，每格1伤害。冷却3.8秒。",
		"抛射轰击": "射程3格，准备0.65秒、飞行0.8秒，打击锁定中心及上下左右五格，每格1伤害。落点不追踪，不伤队友。冷却5.5秒。"
	}
	return descriptions.get(skill, "")

func rebuild_editor() -> void:
	super.rebuild_editor()
	for row in editor_rows:
		var menu: OptionButton = row.menus[0]
		for i in range(menu.item_count): menu.get_popup().set_item_tooltip(i, grid_description(menu.get_item_text(i)))
		menu.tooltip_text = grid_description(menu.get_item_text(menu.selected))
