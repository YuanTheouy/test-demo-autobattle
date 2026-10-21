extends Node2D

# One world unit = 80 pixels. Navigation uses a finer grid; movement is continuous.
const ORIGIN := Vector2(35, 130)
const SIZE := 640.0
const RADIUS := 24.0
const MAX_HP := 50.0
const MOVE_SPEED := 87.0
const ENGAGE_SPEED := 126.0
const COMBAT_STEP_SPEED := 48.0
const DODGE_SPEED := 240.0
const DODGE_DISTANCE := 80.0
const SHOT_RANGE := 270.0
const SIGHT_RANGE := 410.0
const BULLET_SPEED := 1400.0
const BASIC_BULLET_SPEED := 1300.0
const ROCK_SPEED := 360.0
const SHOTGUN_SPEED := 340.0
const ROUND_TIME := 60.0
const SHRINK_START := 18.0
const SHRINK_END := 42.0
const MAX_INSET := 145.0
const BLUE := Color("52b6ff")
const RED := Color("ff697d")
const GOLD := Color("f5ce78")
const MOVE_HINT := Color("69e3b3")
const ATTACK_BLUE := Color("9599ff")
const ATTACK_RED := Color("ff825e")
const BLAST_RADIUS := 64.0
const BLAST_CAST := 0.25
const BLAST_FLIGHT := 0.65
var walls: Array[Rect2] = [Rect2(248, 104, 64, 112), Rect2(328, 424, 64, 112)]
var tactics := [0, 1]
var team_focus := [-1, -1]
var focus_timer := 0.0
var red_menu: OptionButton
var shrink_announced := false
var navigation_border := -999
var units: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var hazards: Array[Dictionary] = []
var blasts: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var nav := AStarGrid2D.new()
var font: SystemFont
var running := false
var started := false
var finished := false
var blue_attacks := false # Demonstration starts blue on right; button swaps physical sides.
var clock := ROUND_TIME
var speed := 1.0
var show_aim := true
var selected := -1
var logs: Array[String] = []
var result := ""
var winner_team := -1
var win_reason := ""
var strategy := 0
var start_button: Button
var strategy_menu: OptionButton
var status_label: Label
var info_label: Label
var log_label: Label
var result_label: Label
var hits := 0
var shots := 0
var preview_frames := 0
const Tactics = preload("res://scripts/tactics.gd")
const ACTIVE_SKILLS = Tactics.ACTIVE
const REACTION_SKILLS = Tactics.REACTIONS
const CONDITIONS = Tactics.CONDITIONS
var loadouts: Array = []
var editor_unit := 0
var editor_rows: Array = []
var unit_menu: OptionButton
var reaction_counts := {}
const STEP := 1.0 / 60.0
var accumulator := 0.0
var team_presets := [7, 8]
var preset_menus: Array = []
var subtitle: Label
var hit_events: Array = []
var shields_pending: Array = []
var heals_pending: Array = []
var impacts: Array = []
var links: Array = []
var skill_help: Label



func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Heiti SC", "Arial"])
	DisplayServer.window_set_title("AutoBattle — 即时竞技场 / realtime-arena")
	setup_navigation()
	setup_loadouts()
	setup_ui()
	reset_round()
	if "--expansion-test" in OS.get_cmdline_user_args():
		run_expansion_tests()
		get_tree().quit()
		return
	if "--defense-test" in OS.get_cmdline_user_args():
		run_defense_tests()
		get_tree().quit()
		return
	if "--tempo-test" in OS.get_cmdline_user_args():
		run_tempo_tests()
		get_tree().quit()
		return
	if "--arena-test" in OS.get_cmdline_user_args():
		run_arena_tests()
		get_tree().quit()
		return
	if "--blast-test" in OS.get_cmdline_user_args():
		run_blast_tests()
		get_tree().quit()
		return
	if "--evasion-test" in OS.get_cmdline_user_args():
		run_evasion_tests()
		get_tree().quit()
		return
	if "--pattern-test" in OS.get_cmdline_user_args():
		run_pattern_tests()
		get_tree().quit()
		return
	if "--readability-test" in OS.get_cmdline_user_args():
		run_readability_tests()
		get_tree().quit()
		return
	if "--magic-test" in OS.get_cmdline_user_args():
		run_magic_tests()
		get_tree().quit()
		return
	if "--content-test" in OS.get_cmdline_user_args():
		run_content_tests()
		get_tree().quit()
		return
	if "--movement-test" in OS.get_cmdline_user_args():
		run_movement_tests()
		get_tree().quit()
		return
	if "--rules-test" in OS.get_cmdline_user_args():
		run_rules_tests()
		get_tree().quit()
		return
	if "--team-test" in OS.get_cmdline_user_args():
		run_team_tests()
		get_tree().quit()
		return
	if "--boundary-test" in OS.get_cmdline_user_args():
		run_boundary_tests()
		get_tree().quit()
		return
	if "--aim-test" in OS.get_cmdline_user_args():
		run_aim_tests()
		get_tree().quit()
		return
	if "--batch-test" in OS.get_cmdline_user_args():
		run_batch_tests()
		return
	if "--smoke-test" in OS.get_cmdline_user_args():
		run_smoke_tests()
	if "--preview" in OS.get_cmdline_user_args() or "--demo" in OS.get_cmdline_user_args():
		running = true
		started = true

func setup_navigation() -> void:
	nav.region = Rect2i(0, 0, 32, 32)
	nav.cell_size = Vector2(20, 20)
	nav.offset = Vector2(10, 10)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for x in range(32):
		for y in range(32):
			var p := Vector2(x * 20 + 10, y * 20 + 10)
			if not valid_position(p):
				nav.set_point_solid(Vector2i(x, y))

func text_label(parent: Node, text: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("dbe5ee"))
	parent.add_child(l)
	return l

func setup_loadouts() -> void:
	loadouts = Tactics.preset(team_presets[0]) + Tactics.preset(team_presets[1])

func apply_preset(team: int, index: int) -> void:
	team_presets[team] = index
	var pair := Tactics.preset(index)
	for member in range(2): loadouts[team * 2 + member] = pair[member]
	rebuild_editor()
	reset_round()

func setup_ui() -> void:
	var title := text_label(self, "AUTOBATTLE  /  即时小队对战", 27)
	title.position = Vector2(35, 25)
	subtitle = text_label(self, "", 15)
	subtitle.position = Vector2(36, 68)
	status_label = text_label(self, "", 17)
	status_label.position = Vector2(35, 101)
	var panel := VBoxContainer.new()
	panel.position = Vector2(705, 22)
	panel.size = Vector2(660, 790)
	panel.add_theme_constant_override("separation", 5)
	add_child(panel)
	text_label(panel, "小队策略 · 四主动 / 四反应", 23)
	var controls := HBoxContainer.new()
	panel.add_child(controls)
	start_button = add_button(controls, "开始交战 [空格]", toggle_running)
	add_button(controls, "同配置重开 [R]", reset_round)
	add_button(controls, "当前角色清空策略", func(): loadouts[editor_unit] = Tactics.build([], []); rebuild_editor(); reset_round())
	var playback := HBoxContainer.new()
	panel.add_child(playback)
	add_button(playback, "步进0.2秒 [N]", step_forward)
	add_button(playback, "交换出生侧", func(): blue_attacks = not blue_attacks; reset_round())
	var speed_button := add_button(playback, "速度：%s×" % speed, func(): pass)
	speed_button.pressed.connect(func(): speed = 2.0 if speed == 1.0 else (0.5 if speed == 2.0 else 1.0); speed_button.text = "速度：%s×" % speed)
	var check := CheckButton.new()
	check.text = "技能范围"
	check.button_pressed = true
	check.add_theme_font_override("font", font)
	check.toggled.connect(func(value: bool): show_aim = value)
	playback.add_child(check)
	var presets := HBoxContainer.new()
	panel.add_child(presets)
	for team in range(2):
		text_label(presets, "蓝队" if team == 0 else "红队", 14)
		var picker := OptionButton.new()
		picker.add_theme_font_override("font", font)
		picker.custom_minimum_size.x = 235
		for name in Tactics.NAMES: picker.add_item(name)
		picker.select(team_presets[team])
		picker.item_selected.connect(func(index: int): apply_preset(team, index))
		presets.add_child(picker)
		preset_menus.append(picker)
	unit_menu = OptionButton.new()
	unit_menu.add_theme_font_override("font", font)
	for name in ["蓝1", "蓝2", "红1", "红2"]: unit_menu.add_item(name)
	unit_menu.item_selected.connect(func(i: int): editor_unit = i; selected = i; rebuild_editor())
	panel.add_child(unit_menu)
	text_label(panel, "技能                         条件一                              条件二", 14)
	text_label(panel, "空槽也会搜敌与点射；策略优先，修改后重开。悬停查看技能。", 14)
	for kind in ["active", "reaction"]:
		text_label(panel, "主动 · 空闲时检查；动作结束后再选" if kind == "active" else "反应 · 出手前可闪避；开火、吟唱与收招不能取消", 16)
		for slot in range(4):
			var row := HBoxContainer.new()
			panel.add_child(row)
			text_label(row, str(slot + 1), 15)
			var picks: Array = []
			for column in range(3):
				var menu := OptionButton.new()
				menu.add_theme_font_override("font", font)
				menu.add_theme_font_size_override("font_size", 14)
				menu.custom_minimum_size = Vector2(143 if column == 0 else 220, 30)
				var options: Array = (ACTIVE_SKILLS if kind == "active" else REACTION_SKILLS) if column == 0 else CONDITIONS
				for option in options:
					menu.add_item(option)
					if column == 0: menu.get_popup().set_item_tooltip(menu.item_count - 1, Tactics.DESCRIPTIONS[option])
				menu.item_selected.connect(func(index: int): loadouts[editor_unit][kind][slot][column] = menu.get_item_text(index); rebuild_editor(); reset_round())
				row.add_child(menu)
				picks.append(menu)
			editor_rows.append({"kind": kind, "slot": slot, "menus": picks, "row": row})
	skill_help = text_label(panel, "蓝紫：蓝方攻击 · 橙红：红方攻击 · 绿线：移动\n落点锁定 → 外环补满 → 爆炸；按实际圆形范围命中", 13)
	info_label = text_label(panel, "", 14)
	info_label.custom_minimum_size = Vector2(650, 70)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label = text_label(panel, "", 18)
	log_label = text_label(panel, "", 13)
	var foot := text_label(self, "消灭对方获胜 · 18秒起硬边界收缩 · 60秒超时平局 · 点击圆点编辑", 14)
	foot.position = Vector2(35, 789)
	rebuild_editor()

func rebuild_editor() -> void:
	for row in editor_rows:
		for column in range(3):
			var menu: OptionButton = row.menus[column]
			if column > 0:
				var allowed: Array = ["无", "优先低血量", "自己HP≤25", "队友HP≤25"] if loadouts[editor_unit][row.kind][row.slot][0] in ["回春", "灵木护佑"] else CONDITIONS
				menu.clear()
				for condition in allowed: menu.add_item(condition)
				if loadouts[editor_unit][row.kind][row.slot][column] not in allowed:
					loadouts[editor_unit][row.kind][row.slot][column] = "无"
			var value: String = loadouts[editor_unit][row.kind][row.slot][column]
			for index in range(menu.item_count):
				if menu.get_item_text(index) == value: menu.select(index)
			if column == 0: menu.tooltip_text = Tactics.DESCRIPTIONS.get(value, "")

func add_button(parent: Node, title: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size.y = 34
	b.add_theme_font_override("font", font)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func reset_round() -> void:
	running = false
	started = false
	finished = false
	clock = ROUND_TIME
	accumulator = 0.0
	hit_events.clear()
	shields_pending.clear()
	heals_pending.clear()
	impacts.clear()
	links.clear()
	navigation_border = -999
	refresh_boundary_navigation()
	shrink_announced = false
	team_focus = [-1, -1]
	focus_timer = 0.0
	result = ""
	winner_team = -1
	win_reason = ""
	selected = -1
	shots = 0
	hits = 0
	bullets.clear()
	hazards.clear()
	blasts.clear()
	effects.clear()
	logs.clear()
	units.clear()
	for team in range(2):
		var attack: bool = (team == 0) == blue_attacks
		for member in range(2):
			var p: Vector2 = Vector2(120, 200 + member * 240) if attack else Vector2(520, 200 + member * 240)
			units.append({"uid": team * 2 + member, "team": team, "member": member, "attack": attack, "p": p,
				"evade_source": -1, "counter_left": 0.0, "thorns": 0.0, "thorn_tick": 0.0, "hurt_recent": 0.0, "hit_flash": 0.0, "heal_flash": 0.0, "reason": "基础作战就绪", "rule_kind": "", "rule_slot": -1, "slow": 0.0, "shield": 0.0, "shield_time": 0.0, "patrol": 0, "dash_recovery": false, "avoid_left": 0.0, "avoid_dir": Vector2.ZERO, "active_skill": "点射", "rule": "待机", "rule_flash": 0.0, "fire_flash": 0.0, "marked": 0.0, "guard": 0.0, "skill_cds": {}, "action_left": 0.0, "action_goal": p,
				"intent": "待机", "retreat": 0.0, "retreat_cd": 0.0, "hp": MAX_HP, "phase": "移动", "timer": 0.0, "cooldown": 0.0,
				"angle": 0.0 if attack else PI, "target": -1, "path": PackedVector2Array(),
				"repath": 0.0, "goal": p, "dodge": 0.0, "dodge_dir": Vector2.ZERO, "shot_count": 0, "last_seen": Vector2(-1, -1), "memory": 0.0})
	reaction_counts.clear()
	log_event("蓝：%s / 红：%s" % [Tactics.NAMES[team_presets[0]], Tactics.NAMES[team_presets[1]]])
	refresh_ui()
	queue_redraw()

func toggle_running() -> void:
	if finished:
		reset_round()
	started = true
	running = not running
	refresh_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: toggle_running()
		if event.keycode == KEY_R: reset_round()
		if event.keycode == KEY_N: step_forward()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			selected = -1
			for i in range(units.size()):
				if units[i].p.distance_to(get_global_mouse_position() - ORIGIN) < 19:
					selected = i
					editor_unit = units[i].uid
					unit_menu.select(editor_unit)
					rebuild_editor()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not started and selected >= 0 and units[selected].team == 0:
			var p := get_global_mouse_position() - ORIGIN
			var correct_zone: bool = p.x < 125 if units[selected].attack else p.x > 515
			var free := true
			for i in range(units.size()):
				if i != selected and p.distance_to(units[i].p) < RADIUS * 2 + 2: free = false
			if correct_zone and free and valid_position(p): units[selected].p = p
	refresh_ui()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if "--preview" in OS.get_cmdline_user_args():
		preview_frames += 1
		if preview_frames == 720 or ("--effects-preview" in OS.get_cmdline_user_args() and not blasts.is_empty()) or ("--pattern-preview" in OS.get_cmdline_user_args() and not hazards.is_empty()):
			capture_preview.call_deferred()
	if running: advance_playback(delta)
	refresh_ui()
	queue_redraw()

func advance_playback(delta: float) -> void:
	accumulator += delta * speed
	while accumulator + 0.00000001 >= STEP and running:
		accumulator -= STEP
		simulate(STEP)

func step_forward() -> void:
	if finished: return
	running = false
	started = true
	accumulator = 0.0
	for tick in range(12):
		if not finished: simulate(STEP)
	refresh_ui()
	queue_redraw()

func valid_position(p: Vector2) -> bool:
	if p.x < RADIUS or p.y < RADIUS or p.x > SIZE - RADIUS or p.y > SIZE - RADIUS: return false
	for wall in walls:
		if wall.grow(RADIUS + 1).has_point(p): return false
	return true

func valid_arena_position(p: Vector2) -> bool:
	var bounds := safe_rect().grow(-RADIUS - 1)
	return p.x >= bounds.position.x and p.y >= bounds.position.y and p.x <= bounds.end.x and p.y <= bounds.end.y and valid_position(p)

func refresh_boundary_navigation() -> void:
	var border := int(ceil((safe_rect().position.x + RADIUS + 1 - 10) / 20.0))
	if border == navigation_border: return
	navigation_border = border
	for x in range(32):
		for y in range(32):
			nav.set_point_solid(Vector2i(x, y), not valid_arena_position(Vector2(x * 20 + 10, y * 20 + 10)))
	for u in units:
		u.repath = 0.0
		u.path = PackedVector2Array()

func enforce_boundary() -> void:
	var bounds := safe_rect().grow(-RADIUS - 1)
	for u in units:
		if valid_arena_position(u.p): continue
		var corrected: Vector2 = u.p.clamp(bounds.position, bounds.end)
		# A shrinking edge may intersect cover: relocate to the nearest legal cell.
		if not valid_arena_position(corrected):
			var best := Vector2(320, 320)
			var best_distance := INF
			for x in range(32):
				for y in range(32):
					var p := Vector2(x * 20 + 10, y * 20 + 10)
					if not valid_arena_position(p): continue
					var distance := p.distance_squared_to(corrected)
					if distance < best_distance: best_distance = distance; best = p
			corrected = best
		u.p = corrected
		u.repath = 0.0
		u.path = PackedVector2Array()
		u.dodge = 0.0

func blocked(a: Vector2, b: Vector2) -> bool:
	for wall in walls:
		if wall.has_point(a) or wall.has_point(b): return true
		var corners := [wall.position, Vector2(wall.end.x, wall.position.y), wall.end, Vector2(wall.position.x, wall.end.y)]
		for i in range(4):
			if Geometry2D.segment_intersects_segment(a, b, corners[i], corners[(i + 1) % 4]) != null: return true
	return false

func contacts(team: int) -> Array[int]:
	var found: Array[int] = []
	for i in range(units.size()):
		var enemy: Dictionary = units[i]
		if enemy.team == team or enemy.hp <= 0: continue
		for ally in units:
			if ally.team == team and ally.hp > 0 and ally.p.distance_to(enemy.p) <= SIGHT_RANGE and not blocked(ally.p, enemy.p):
				found.append(i)
				break
	return found

func simulate(dt: float) -> void:
	clock -= dt
	shields_pending.clear()
	heals_pending.clear()
	for event in hit_events: event.life -= dt
	hit_events = hit_events.filter(func(event): return event.life > 0)
	for link in links: link.life -= dt
	links = links.filter(func(link): return link.life > 0)
	refresh_boundary_navigation()
	enforce_boundary()
	if not shrink_announced and ROUND_TIME - clock >= SHRINK_START:
		shrink_announced = true
		log_event("边界开始收缩，枪兵随边界向内移动")
	var visible := [contacts(0), contacts(1)]
	focus_timer -= dt
	update_team_focus(visible)
	# All decisions read the same immutable start-of-step world.
	var next_units: Array[Dictionary] = []
	for old in units: next_units.append(old.duplicate(true))
	for i in range(units.size()):
		var u: Dictionary = next_units[i]
		if u.hp <= 0: continue
		for key in u.skill_cds.keys(): u.skill_cds[key] = maxf(0, u.skill_cds[key] - dt)
		u.counter_left = maxf(0, u.counter_left - dt)
		u.cooldown = maxf(0, u.cooldown - dt)
		u.marked = maxf(0, u.marked - dt)
		u.guard = maxf(0, u.guard - dt)
		u.slow = maxf(0, u.slow - dt)
		u.hurt_recent = maxf(0, u.hurt_recent - dt)
		u.hit_flash = maxf(0, u.hit_flash - dt)
		u.heal_flash = maxf(0, u.heal_flash - dt)
		u.shield_time = maxf(0, u.shield_time - dt)
		if u.shield_time <= 0: u.shield = 0.0
		u.memory = maxf(0, u.memory - dt)
		var seen := rule_target(u, visible[u.team], ["", "优先最近敌人", "无"], false)
		if seen >= 0:
			u.last_seen = units[seen].p
			u.memory = 5.0
		u.rule_flash = maxf(0, u.rule_flash - dt)
		u.fire_flash = maxf(0, u.fire_flash - dt)
		u.repath -= dt
		if u.dodge > 0:
			u.dodge = maxf(0, u.dodge - dt)
			u.phase = "侧闪"
			var next: Vector2 = u.p + u.dodge_dir * DODGE_SPEED * dt
			if movement_is_free(u, next) and not blocked(u.p, next): u.p = next
			if u.dodge <= 0:
				u.phase = "移动"
				u.action_left = 0.0
				u.repath = 0.0
			continue
		var can_evade: bool = u.phase not in ["吟唱", "点射", "收招", "架枪防御", "回春", "灵木护佑", "掩护队友"] and not (u.phase == "瞄准" and u.shot_count > 0)
		if can_evade:
			if try_reaction(u, visible[u.team]): continue
			if prepare_tactical_escape(u, visible[u.team]):
				var step_to: Vector2 = u.p.move_toward(u.action_goal, unit_move_speed(u) * dt)
				if u.phase == "规避预警" and movement_is_free(u, step_to): u.p = step_to
				continue

		if u.phase in ["吟唱", "瞄准", "点射", "收招"]:
			update_attack(u, dt)
			continue
		# Baseline footwork yields every tick to player AP and to a ready weapon.
		if u.intent == "战斗走位" and u.action_left > 0:
			if try_active(u, visible[u.team]): continue
			if u.cooldown <= 0: u.action_left = 0.0
		if u.action_left > 0:
			u.action_left = maxf(0, u.action_left - dt)
			if u.intent not in ["架枪防御", "掩护队友", "回春", "灵木护佑"]:
				move_unit(u, u.action_goal, dt)
				if u.p.distance_to(u.action_goal) < 8:
					u.action_left = 0.0
					u.phase = "已到位"
			if u.action_left <= 0 and u.dash_recovery:
				u.dash_recovery = false
				u.phase = "收招"
				u.timer = 0.45
			continue
		if not try_active(u, visible[u.team]): baseline_action(u, visible[u.team])
	# Reject conflicting movement proposals together, never first-come-first-served.
	var rejected: Array[int] = []
	for i in range(next_units.size()):
		for j in range(i + 1, next_units.size()):
			if next_units[i].hp > 0 and next_units[j].hp > 0 and next_units[i].p.distance_to(next_units[j].p) < RADIUS * 2:
				rejected.append(i); rejected.append(j)
	for i in rejected:
		next_units[i].p = units[i].p
		next_units[i].phase = "让行" if next_units[i].action_left > 0 else next_units[i].phase
	units = next_units
	for grant in shields_pending:
		for u in units:
			if u.uid == grant.uid:
				u.shield = maxf(u.shield, grant.get("amount", 10.0))
				u.shield_time = 2.0
	for grant in heals_pending:
		for u in units:
			if u.uid == grant.uid and u.hp > 0:
				var restored: float = minf(MAX_HP - u.hp, grant.get("amount", 12.0))
				u.hp += restored
				if restored > 0: impacts.append({"p": u.p, "life": 0.65, "amount": restored, "team": u.team, "healing": true})
				u.heal_flash = 0.8
	update_bullets(dt)
	var alive := [0, 0]
	for u in units:
		if u.hp > 0: assert(valid_arena_position(u.p), "Unit crossed hard arena boundary")
		if u.hp > 0: alive[u.team] += 1
	if alive[0] == 0 and alive[1] == 0: end_round(-1, "双方同时全灭")
	elif alive[0] == 0: end_round(1, "对方枪兵全部倒下")
	elif alive[1] == 0: end_round(0, "对方枪兵全部倒下")
	elif clock <= 0: end_round(-1, "时限结束，双方仍有存活枪兵")
	for fx in effects: fx.life -= dt
	effects = effects.filter(func(fx: Dictionary): return fx.life > 0)

func safe_rect() -> Rect2:
	var inset := MAX_INSET * clampf((ROUND_TIME - clock - SHRINK_START) / (SHRINK_END - SHRINK_START), 0, 1)
	return Rect2(Vector2(inset, inset), Vector2(SIZE - inset * 2, SIZE - inset * 2))

func ally_index(u: Dictionary) -> int:
	for i in range(units.size()):
		if units[i].team == u.team and units[i].uid != u.uid and units[i].hp > 0: return i
	return -1

func incoming_pressure(u: Dictionary, visible: Array) -> int:
	var count := 0
	for j in visible:
		var enemy: Dictionary = units[j]
		if enemy.phase in ["吟唱", "瞄准", "点射"] and enemy.target >= 0 and units[enemy.target].uid == u.uid and not blocked(enemy.p, u.p): count += 1
	return count

func update_team_focus(visible: Array) -> void:
	for team in range(2):
		if focus_timer > 0 and team_focus[team] in visible[team] and units[team_focus[team]].hp > 0: continue
		var best := -1
		var best_score := INF
		for j in visible[team]:
			var enemy: Dictionary = units[j]
			var score: float = enemy.hp * 0.7
			for ally in units:
				if ally.team != team or ally.hp <= 0: continue
				score += ally.p.distance_to(enemy.p)
				if blocked(ally.p, enemy.p): score += 95

			if score < best_score or (is_equal_approx(score, best_score) and (best < 0 or enemy.uid < units[best].uid)):
				best_score = score
				best = j
		team_focus[team] = best
	if focus_timer <= 0: focus_timer = 0.8

func choose_target(u: Dictionary, visible: Array) -> int:
	var best := -1
	var score := INF
	var ally := ally_index(u)
	for j in visible:
		var enemy: Dictionary = units[j]
		if blocked(u.p, enemy.p) or u.p.distance_to(enemy.p) > SHOT_RANGE: continue
		var candidate: float = u.p.distance_to(enemy.p)
		if j == team_focus[u.team]: candidate -= 110
		if ally >= 0 and units[ally].target == j and units[ally].phase in ["吟唱", "瞄准", "点射"]: candidate -= 35
		if tactics[u.team] != 0 and ally >= 0 and enemy.target == ally and (units[ally].hp < MAX_HP * 0.5 or units[ally].retreat > 0): candidate -= 160
		if candidate < score or (is_equal_approx(candidate, score) and (best < 0 or enemy.uid < units[best].uid)):
			score = candidate
			best = j
	return best

func choose_goal(u: Dictionary, visible: Array) -> Vector2:
	var target := rule_target(u, visible, ["", "优先最近敌人", "无"], false)
	if target >= 0:
		var enemy: Vector2 = units[target].p
		var best: Vector2 = u.p
		var score := INF
		for x in range(32):
			for y in range(32):
				if nav.is_point_solid(Vector2i(x, y)): continue
				var point := Vector2(x * 20 + 10, y * 20 + 10)
				if point.distance_to(enemy) > SHOT_RANGE - 20 or blocked(point, enemy): continue
				var d: float = point.distance_squared_to(u.p)
				for ally in units:
					if ally.uid != u.uid and ally.hp > 0 and point.distance_to(ally.p) < RADIUS * 2 + 12: d += 10000
				if d < score: score = d; best = point
		if score < INF: return best
	if u.memory > 0 and u.p.distance_to(u.last_seen) > 35:
		return nearest_legal_goal(u.last_seen)
	var checkpoints := [Vector2(320, 320), Vector2(220, 100), Vector2(420, 100), Vector2(420, 540), Vector2(220, 540)]
	var index: int = (u.patrol + u.member * 2) % checkpoints.size()
	var destination := nearest_legal_goal(checkpoints[index])
	if u.p.distance_to(destination) < 25:
		u.patrol += 1
		destination = nearest_legal_goal(checkpoints[(u.patrol + u.member * 2) % checkpoints.size()])
	return destination

func unit_move_speed(u: Dictionary) -> float:
	var base_speed := ENGAGE_SPEED if u.intent in ["基础接敌", "搜索"] else MOVE_SPEED
	var skill_multiplier := 2.4 if u.intent == "短冲刺" else (1.2 if u.intent in ["绕侧", "后撤"] else 1.0)
	return base_speed * (0.6 if u.slow > 0 else 1.0) * skill_multiplier

func baseline_action(u: Dictionary, visible: Array) -> void:
	u.rule_kind = ""
	u.rule_slot = -1
	u.rule_flash = 0.0
	var target := rule_target(u, visible, ["", "优先最近敌人", "无"], true)
	if target >= 0:
		if u.cooldown <= 0:
			begin_shot(u, target, "点射")
			u.intent = "基础点射"
			u.rule = "基础点射"
			u.reason += "；执行普通点射"
		else:
			if not prepare_combat_step(u, target):
				u.phase = "保持射位"
				u.intent = "基础作战"
				u.reason = "保持射线；附近没有安全的小幅走位空间"
		return
	u.action_goal = choose_goal(u, visible)
	u.action_left = 0.35
	u.repath = 0.0
	u.intent = "基础接敌" if not visible.is_empty() else "搜索"
	u.phase = u.intent
	u.reason = "目标被遮挡或超出射程，寻找射位" if not visible.is_empty() else ("前往最后发现敌人的位置" if u.memory > 0 else "巡查交战区域，寻找敌人")

# Small deterministic lateral steps, preserving line of sight and firing distance.
# This is low-priority footwork, not a dodge or an uninterruptible movement skill.
func prepare_combat_step(u: Dictionary, target: int) -> bool:
	var enemy: Vector2 = units[target].p
	var toward: Vector2 = (enemy - u.p).normalized()
	var side: Vector2 = toward.orthogonal() * (1 if u.member == 0 else -1)
	for sign_value in [1.0, -1.0]:
		var direction: Vector2 = side * sign_value
		if u.p.distance_to(enemy) > SHOT_RANGE - 30: direction = (direction + toward * 0.5).normalized()
		if u.p.distance_to(enemy) < 130: direction = (direction - toward * 0.5).normalized()
		var goal: Vector2 = u.p + direction * 32
		if not movement_is_free(u, goal) or blocked(u.p, goal): continue
		if blocked(goal, enemy) or goal.distance_to(enemy) > SHOT_RANGE: continue
		var clear := true
		for fraction in [0.25, 0.5, 0.75]:
			if not movement_is_free(u, u.p.lerp(goal, fraction)): clear = false
		if not clear: continue
		u.target = target
		u.action_goal = goal
		u.action_left = minf(u.cooldown, 0.65)
		u.path = PackedVector2Array()
		u.avoid_left = 0.0
		u.intent = "战斗走位"
		u.phase = u.intent
		u.reason = "武器恢复中，侧移保持射线；玩家技能可立即接管"
		return true
	return false

func recovery_duration(skill: String) -> float:
	if skill in Tactics.LINES: return 1.0
	if skill in ["强力射击", "落岩", "震山"]: return 0.8
	if skill == "短冲刺": return 0.45
	return 0.45

func begin_shot(u: Dictionary, target: int, skill: String) -> void:
	u.target = target
	u.active_skill = skill
	u.action_left = 0.0
	u.avoid_left = 0.0
	u.phase = "瞄准"
	u.timer = float(Tactics.MAGIC.get(skill, {}).get("cast", 0.0))
	if u.timer > 0: u.phase = "吟唱"
	u.shot_count = 0
	if skill in Tactics.PATTERNS:
		u.angle = (units[target].p - u.p).angle()
		u.lock_angle = u.angle
		u.lock_point = units[target].p

func move_unit(u: Dictionary, goal: Vector2, dt: float) -> void:
	if u.intent == "战斗走位":
		var step_to: Vector2 = u.p.move_toward(goal, COMBAT_STEP_SPEED * (0.6 if u.slow > 0 else 1.0) * dt)
		if movement_is_free(u, step_to) and not blocked(u.p, step_to): u.p = step_to
		else: u.action_left = 0.0
		if u.target >= 0:
			u.angle = rotate_toward(u.angle, (units[u.target].p - u.p).angle(), dt * 6)
		return
	if u.avoid_left > 0:
		u.avoid_left = maxf(0, u.avoid_left - dt)
		var candidate: Vector2 = u.p + u.avoid_dir * unit_move_speed(u) * dt
		if movement_is_free(u, candidate):
			u.p = candidate
			u.phase = "绕行"
			u.repath = 0.0
			return
		u.avoid_left = 0.0
	if u.repath <= 0 or u.goal.distance_to(goal) > 20:
		u.goal = goal
		u.repath = 0.45
		var start := Vector2i(clampi(int(u.p.x / 20), 0, 31), clampi(int(u.p.y / 20), 0, 31))
		var end := Vector2i(clampi(int(goal.x / 20), 0, 31), clampi(int(goal.y / 20), 0, 31))
		# Continuous positions can be legal while their quantized navigation cell is solid.
		if nav.is_point_solid(start):
			var entry := nearest_legal_goal(u.p)
			start = Vector2i(int(entry.x / 20), int(entry.y / 20))
		if not nav.is_point_solid(start) and not nav.is_point_solid(end):
			u.path = nav.get_point_path(start, end)
		else: u.path = PackedVector2Array()
	var path: PackedVector2Array = u.path
	while path.size() > 0 and u.p.distance_to(path[0]) < 7: path.remove_at(0)
	u.path = path
	if path.is_empty():
		u.phase = "已到位" if u.p.distance_to(goal) < 8 else "寻路失败"
		return
	var direction: Vector2 = (path[0] - u.p).normalized()
	var separation := Vector2.ZERO
	for other in units:
		if other.uid == u.uid or other.hp <= 0: continue
		var diff: Vector2 = u.p - other.p
		if diff.length() < RADIUS * 2 + 16 and diff.length() > 0.01: separation += diff.normalized() * (RADIUS * 2 + 16 - diff.length()) / 24.0
	direction = (direction + separation).normalized()
	# Navigation ignores moving bodies. Locally sidestep them instead of repeatedly
	# proposing the same blocked move. Both actors still obey collision/boundary checks.
	var next: Vector2 = u.p + direction * unit_move_speed(u) * dt
	if movement_is_free(u, next) and movement_is_free(u, u.p + direction * 12):
		u.p = next
		u.phase = u.intent
		u.angle = rotate_toward(u.angle, direction.angle(), dt * 5)
		return
	for angle in [PI / 2, -PI / 2, PI / 3, -PI / 3, PI * 2 / 3, -PI * 2 / 3]:
		var detour: Vector2 = direction.rotated(angle)
		var candidate: Vector2 = u.p + detour * unit_move_speed(u) * dt
		if not movement_is_free(u, candidate): continue
		if not movement_is_free(u, u.p + detour * 12): continue
		u.p = candidate
		u.avoid_left = 0.35
		u.avoid_dir = detour
		u.phase = "绕行"
		u.angle = rotate_toward(u.angle, detour.angle(), dt * 5)
		return
	u.phase = "让行"

func movement_is_free(u: Dictionary, next: Vector2) -> bool:
	if not valid_arena_position(next): return false
	for other in units:
		if other.uid != u.uid and other.hp > 0 and next.distance_to(other.p) < RADIUS * 2: return false
	return true

func update_attack(u: Dictionary, dt: float) -> void:
	u.timer -= dt
	if u.phase == "吟唱" and u.active_skill in Tactics.PATTERNS:
		if u.timer > 0: return
		release_pattern(u)
		u.phase = "收招"
		u.timer = recovery_duration(u.active_skill)
		return
	if u.phase == "吟唱":
		if u.target < 0 or units[u.target].hp <= 0:
			u.phase = "收招"
			u.timer = 0.15
			return
		u.angle = rotate_toward(u.angle, (units[u.target].p - u.p).angle(), dt * 6)
		if u.timer > 0: return
		u.phase = "瞄准"
	if u.phase == "瞄准" or u.phase == "点射":
		var target: Dictionary = units[u.target]
		if target.hp <= 0 or blocked(u.p, target.p) or u.p.distance_to(target.p) > SHOT_RANGE:
			u.phase = "收招"
			u.timer = 0.15
			return
		var desired: float = (target.p - u.p).angle()
		u.angle = rotate_toward(u.angle, desired, dt * 6)
		# Alignment, not a countdown, authorizes every bullet, including burst follow-ups.
		if absf(angle_difference(u.angle, desired)) > 0.01:
			u.phase = "瞄准"
			return
		if u.timer > 0: return
		var direction := Vector2.from_angle(u.angle)
		var projectile_speed := ROCK_SPEED if u.active_skill in ["落岩", "震山"] else (BASIC_BULLET_SPEED if u.active_skill == "点射" else BULLET_SPEED)
		bullets.append({"p": u.p + direction * (RADIUS + 4), "v": direction * projectile_speed, "team": u.team, "life": SHOT_RANGE / projectile_speed, "true_damage": magic_element(u.active_skill) == "火", "element": magic_element(u.active_skill), "thorns": u.active_skill == "荆棘", "damage": shot_damage(u.active_skill), "source": u.uid, "skill": u.active_skill, "mark": u.active_skill == "标记弹", "heavy": u.active_skill == "强力射击", "slow": u.active_skill == "压制射击"})
		shots += 1
		u.shot_count += 1
		u.fire_flash = 0.18
		u.phase = "点射"
		u.timer = float(Tactics.MAGIC.get(u.active_skill, {}).get("interval", 0.24))
		if u.shot_count >= int(Tactics.MAGIC.get(u.active_skill, {}).get("hits", 1)):
			u.phase = "收招"
			u.timer = recovery_duration(u.active_skill)
	elif u.phase == "收招" and u.timer <= 0:
		u.phase = "移动"
		u.cooldown = 1.35

func update_bullets(dt: float) -> void:
	for fx in impacts: fx.life -= dt
	impacts = impacts.filter(func(fx): return fx.life > 0)
	var damage := [0.0, 0.0, 0.0, 0.0]
	resolve_hazards(dt, damage)
	var marks := [false, false, false, false]
	var slows := [false, false, false, false]
	var thorns := [false, false, false, false]
	for i in range(units.size()):
		var u: Dictionary = units[i]
		if u.hp <= 0 or u.thorns <= 0: continue
		u.thorns = maxf(0, u.thorns - dt)
		u.thorn_tick -= dt
		if u.thorn_tick <= 0.000001:
			damage[i] += 5.0
			u.thorn_tick += 2.0
			effects.append({"p": u.p, "life": 0.22, "color": Tactics.ELEMENT_COLORS["林"]})
	for b in bullets:
		var old: Vector2 = b.p
		var next: Vector2 = old + b.v * dt
		b.life -= dt
		if blocked(old, next):
			b.life = -1
			effects.append({"p": old, "life": 0.18, "color": GOLD})
		else:
			var victim := -1
			var earliest := INF
			for i in range(units.size()):
				var u: Dictionary = units[i]
				if u.hp <= 0 or u.team == b.team: continue
				var near := Geometry2D.get_closest_point_to_segment(u.p, old, next)
				if near.distance_to(u.p) <= RADIUS and old.distance_to(near) < earliest:
					earliest = old.distance_to(near); victim = i
			if victim >= 0:
				var u: Dictionary = units[victim]
				damage[victim] += maxf(0, float(b.get("damage", 1.0)) + (6.0 if b.get("heavy", false) and u.marked > 0 else 0.0) - (6.0 if u.guard > 0 and not b.get("true_damage", false) else 0.0))
				if b.get("mark", false): marks[victim] = true
				if b.get("slow", false): slows[victim] = true
				if b.get("thorns", false): thorns[victim] = true
				if b.get("skill", "") not in ["协同追击", "追风"]:
					hit_events.append({"source": b.get("source", -1), "team": b.team, "target": victim, "life": 0.8})
				hits += 1
				b.life = -1
				effects.append({"p": u.p, "life": 0.22, "color": Color.WHITE})
		b.p = next
	for i in range(units.size()):
		var u: Dictionary = units[i]
		if u.hp > 0:
			var absorbed: float = minf(u.shield, damage[i])
			u.shield -= absorbed
			u.hp = maxf(0, u.hp - damage[i] + absorbed)
			if damage[i] > absorbed:
				u.hurt_recent = 0.8
				u.hit_flash = 0.22
				impacts.append({"p": u.p, "life": 0.65, "amount": damage[i] - absorbed, "team": u.team})
			if marks[i]: u.marked = 5.0
			if slows[i]: u.slow = 2.4
			if thorns[i]:
				if u.thorns <= 0: u.thorn_tick = 2.0
				u.thorns = 4.0
			if u.hp <= 0: log_event("%s%d 倒下" % ["蓝" if u.team == 0 else "红", u.member + 1])
	bullets = bullets.filter(func(b: Dictionary): return b.life > 0)

func end_round(winner: int, reason: String) -> void:
	winner_team = winner
	win_reason = reason
	finished = true
	running = false
	result = ("平局" if winner < 0 else ("蓝方获胜" if winner == 0 else "红方获胜")) + "\n" + reason
	log_event(reason)

func log_event(message: String) -> void:
	logs.push_front("%02d秒  %s" % [int(ROUND_TIME - clock), message])
	if logs.size() > 3: logs.resize(3)

func refresh_ui() -> void:
	status_label.text = "对称歼灭  ·  %04.1f 秒    |    %s" % [maxf(clock, 0), "边缘收缩中" if ROUND_TIME - clock >= SHRINK_START else "%.0f 秒后缩圈" % (SHRINK_START - (ROUND_TIME - clock))]
	start_button.text = "暂停  [空格]" if running else ("重新开始  [空格]" if finished else ("继续  [空格]" if started else "开始交战  [空格]"))
	result_label.text = result
	log_label.text = "\n".join(logs)
	subtitle.text = "蓝：%s    vs    红：%s  ·  基础作战 + 技能策略" % [Tactics.NAMES[team_presets[0]], Tactics.NAMES[team_presets[1]]]
	var u: Dictionary = units[editor_unit]
	info_label.text = "%s%d · HP %d · %s\n%s\n标记 %.1fs / 减速 %.1fs / 荆棘 %.1fs / 护盾 %d" % ["蓝" if u.team == 0 else "红", u.member + 1, u.hp, u.phase if u.hp > 0 else "已倒下", u.reason, u.marked, u.slow, u.thorns, u.shield]
	for rule in loadouts[editor_unit].reaction:
		if rule[0] == "侧闪":
			var remaining := float(u.skill_cds.get("侧闪", 0.0))
			info_label.text += "\n侧闪：" + ("冷却 %.1f秒" % remaining if remaining > 0 else "就绪（开火、吟唱与收招中不能发动）")
			break
	for row in editor_rows:
		var active: bool = u.hp > 0 and u.rule_flash > 0 and row.kind == u.rule_kind and row.slot == u.rule_slot
		row.row.modulate = Color(1.0, 0.87, 0.4) if active else Color.WHITE

func _draw() -> void:
	draw_style_box(make_box(Color("101d2a"), Color("314657")), Rect2(ORIGIN, Vector2(SIZE, SIZE)))
	draw_arc(ORIGIN + Vector2(SIZE / 2, SIZE / 2), 95, 0, TAU, 96, Color(0.3, 0.5, 0.55, 0.12), 1)
	var safe := safe_rect()
	var inset := safe.position.x
	var danger := Color(0.95, 0.25, 0.28, 0.18)
	draw_rect(Rect2(ORIGIN, Vector2(SIZE, inset)), danger)
	draw_rect(Rect2(ORIGIN + Vector2(0, SIZE - inset), Vector2(SIZE, inset)), danger)
	draw_rect(Rect2(ORIGIN + Vector2(0, inset), Vector2(inset, SIZE - inset * 2)), danger)
	draw_rect(Rect2(ORIGIN + Vector2(SIZE - inset, inset), Vector2(inset, SIZE - inset * 2)), danger)
	if inset > 0: draw_rect(Rect2(ORIGIN + safe.position, safe.size), RED, false, 2)
	if clock > ROUND_TIME - SHRINK_START:
		draw_rect(Rect2(ORIGIN, Vector2(SIZE, SIZE)), Color(GOLD, 0.25), false, 1)
	for wall in walls:
		draw_rect(Rect2(wall.position + ORIGIN + Vector2(4, 5), wall.size), Color(0, 0, 0, 0.35))
		draw_style_box(make_box(Color("354858"), Color("6b8292")), Rect2(wall.position + ORIGIN, wall.size))
	draw_patterns()
	for i in range(units.size()):
		var u: Dictionary = units[i]
		var p: Vector2 = u.p + ORIGIN
		var color: Color = BLUE if u.team == 0 else RED
		var attack_color: Color = ATTACK_BLUE if u.team == 0 else ATTACK_RED
		if u.hp <= 0:
			draw_line(p - Vector2(7, 7), p + Vector2(7, 7), color.darkened(0.6), 3)
			draw_line(p + Vector2(-7, 7), p + Vector2(7, -7), color.darkened(0.6), 3)
			continue
		if show_aim and u.active_skill not in Tactics.PATTERNS and u.phase in ["吟唱", "瞄准", "锁定", "点射"]:
			var direction := Vector2.from_angle(u.angle)
			var cone := PackedVector2Array([p, p + direction.rotated(-0.045) * SHOT_RANGE, p + direction.rotated(0.045) * SHOT_RANGE])
			draw_colored_polygon(cone, Color(attack_color, 0.06))
			draw_line(p, p + direction * SHOT_RANGE, Color(attack_color, 0.65 if u.phase != "瞄准" else 0.18), 1.5)
		if selected == i: draw_arc(p, RADIUS + 5, 0, TAU, 40, Color.WHITE, 2)
		draw_circle(p + Vector2(2, 3), RADIUS + 2, Color(0, 0, 0, 0.4))
		if u.marked > 0:
			draw_arc(p, RADIUS + 3, 0, TAU, 32, GOLD, 2)
			draw_string(font, p + Vector2(-15, -55), "标记", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD)
		if u.slow > 0:
			draw_arc(p, RADIUS + 6, 0, TAU, 32, Color("c291ff"), 2)
			draw_string(font, p + Vector2(-12, -68), "减速", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c291ff"))
		if u.shield > 0:
			draw_arc(p, RADIUS + 9, 0, TAU, 32, Color.CYAN, 3)
			draw_rect(Rect2(p + Vector2(-28, -51), Vector2(56 * clampf(u.shield / 10.0, 0, 1), 3)), Color.CYAN)
		if u.thorns > 0:
			draw_arc(p, RADIUS + 12, 0, TAU, 12, Tactics.ELEMENT_COLORS["林"], 2)
			draw_string(font, p + Vector2(-12, -80), "荆棘", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Tactics.ELEMENT_COLORS["林"])
		if u.heal_flash > 0:
			var green: Color = Tactics.ELEMENT_COLORS["林"]
			draw_line(p + Vector2(-6, -36), p + Vector2(6, -36), green, 3)
			draw_line(p + Vector2(0, -42), p + Vector2(0, -30), green, 3)
		if u.phase == "吟唱":
			draw_arc(p, RADIUS + 5, -PI / 2, -PI / 2 + TAU * (1.0 - clampf(u.timer / float(Tactics.MAGIC.get(u.active_skill, {}).get("cast", 0.6)), 0, 1)), 32, Tactics.ELEMENT_COLORS["山"], 3)
		if u.guard > 0: draw_circle(p, RADIUS + 8, Color(0.4, 0.9, 1.0, 0.22))
		draw_circle(p, RADIUS, color.lerp(Color.WHITE, u.hit_flash / 0.22 * 0.75))
		var direction := Vector2.from_angle(u.angle)
		var recoil: float = 6.0 * u.fire_flash / 0.18
		draw_line(p - direction * recoil, p + direction * (RADIUS + 8 - recoil), color.lightened(0.35), 4)
		if u.fire_flash > 0:
			draw_circle(p + direction * (RADIUS + 12), (8 if u.active_skill == "强力射击" else 5) * u.fire_flash / 0.18, GOLD)
		if u.phase == "收招":
			var duration := recovery_duration(u.active_skill)
			draw_arc(p, RADIUS + 3, -PI / 2, -PI / 2 + TAU * clampf(u.timer / duration, 0, 1), 32, Color(color, 0.65), 2)
		draw_move_path(u)
		draw_rect(Rect2(p + Vector2(-27, -37), Vector2(54, 7)), Color("273440"))
		draw_rect(Rect2(p + Vector2(-27, -37), Vector2(54 * u.hp / MAX_HP, 7)), color)
		draw_string(font, p + Vector2(-22, -41), "%d/%d" % [u.hp, MAX_HP], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		draw_string(font, p + Vector2(-7, 8), str(u.member + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("102033"))
		var action_text: String = u.rule if u.rule_flash > 0 else u.intent
		var label_width: float = maxf(48, font.get_string_size(action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
		var label_x: float = -label_width - 18 if u.member == 0 else 18
		draw_rect(Rect2(p + Vector2(label_x - 3, 44), Vector2(label_width + 6, 34)), Color(0.04, 0.08, 0.12, 0.8))
		draw_string(font, p + Vector2(label_x, 57), action_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color.lightened(0.2))
		draw_string(font, p + Vector2(label_x, 72), "开火" if u.fire_flash > 0 else u.phase, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("dbe5ee"))
	if false:
		for team in range(2):
			var focus: int = team_focus[team]
			if focus < 0 or units[focus].hp <= 0: continue
			var color: Color = BLUE if team == 0 else RED
			var p: Vector2 = units[focus].p + ORIGIN
			draw_arc(p, 21 + team * 3, 0, TAU, 32, Color(color, 0.7), 1.5)
			draw_string(font, p + Vector2(-24, -34 - team * 15), "蓝方集火" if team == 0 else "红方集火", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
	for link in links:
		draw_dashed_line(ORIGIN + link.a, ORIGIN + link.b, Color(link.color, minf(1, link.life * 2)), 3, 7)
	for b in bullets:
		var shot_color: Color = ATTACK_BLUE if b.team == 0 else ATTACK_RED
		var center: Vector2 = b.p + ORIGIN
		var direction: Vector2 = b.v.normalized()
		var element: String = b.get("element", "")
		var trail := 34.0 if element != "" else 22.0
		draw_line(center, center - direction * trail, Color(shot_color, 0.22), 12)
		draw_line(center, center - direction * trail, shot_color, 3)
		if element == "风":
			var heading: float = direction.angle()
			draw_arc(center, 9, heading - 1.2, heading + 1.2, 12, shot_color.lightened(0.4), 3)
		elif element == "山":
			var rock := PackedVector2Array()
			for n in range(6): rock.append(center + Vector2.from_angle(n * TAU / 6) * (9 if n % 2 == 0 else 7))
			draw_colored_polygon(rock, shot_color)
		elif element == "林":
			draw_arc(center, 7, 0, TAU, 5, Color("70e598"), 3)
		else:
			draw_circle(center, 6 if element == "火" else 3, shot_color)
			draw_circle(center, 2.5, Color.WHITE)
	for fx in impacts:
		var age: float = 0.65 - fx.life
		var center: Vector2 = ORIGIN + fx.p
		var color := Color("70e598" if fx.get("healing", false) else "fff0bf", minf(1.0, fx.life * 3))
		draw_string(font, center + Vector2(22, -12 - age * 50), ("+%d" if fx.get("healing", false) else "-%d") % fx.amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 20 if fx.amount >= 16 else 15, color)
		if age < 0.22 and not fx.get("healing", false):
			for n in range(8):
				var direction := Vector2.from_angle(n * TAU / 8 + 0.3)
				draw_line(center + direction * (RADIUS + age * 75), center + direction * (RADIUS + age * 75 + 9), color, 2)
	for fx in effects:
		draw_arc(fx.p + ORIGIN, 5 + (0.22 - fx.life) * 35, 0, TAU, 16, Color(fx.color, minf(1, fx.life * 5)), 2)
	if not started:
		draw_rect(Rect2(ORIGIN + Vector2(0 if blue_attacks else 515, 0), Vector2(125, SIZE)), Color(BLUE, 0.04))

func make_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	return box

func run_smoke_tests() -> void:
	assert(blocked(Vector2(200, 170), Vector2(370, 170)))
	assert(not valid_position(Vector2(310, 150)))
	run_batch_tests()

func capture_preview() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://preview.png")
	get_tree().quit()

func run_batch_tests() -> void:
	var samples := 3
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="): samples = maxi(1, int(arg.get_slice("=", 1)))
	var results: Array = []
	var wins := [0, 0, 0]
	for sample in range(samples):
		for swapped in [false, true]:
			blue_attacks = not swapped
			reset_round()
			var rng := RandomNumberGenerator.new()
			rng.seed = 20261020 + sample
			for u in units: u.p += Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
			for tick in range(3602):
				if finished: break
				simulate(1.0 / 60)
			assert(finished)
			wins[2 if winner_team < 0 else winner_team] += 1
			results.append({"seed": 20261020 + sample, "swapped": swapped, "winner": winner_team, "seconds": ROUND_TIME - clock, "shots": shots, "hits": hits})
	var file := FileAccess.open("res://reports/rules-batch.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"configuration": loadouts, "blue_red_draw": wins, "matches": results}, "\t"))
	print("RULES BATCH blue/red/draw: ", wins)
	get_tree().quit()

func run_aim_tests() -> void:
	for team in range(2):
		reset_round()
		var shooter: Dictionary = units[team * 2]
		shooter.p = Vector2(50, 50)
		shooter.target = (1 - team) * 2
		units[shooter.target].p = Vector2(200, 50)
		shooter.angle = PI
		shooter.phase = "瞄准"
		shooter.timer = -100.0
		for tick in range(25): update_attack(shooter, 1.0 / 60)
		assert(shots == 0, "Timer expiry must never authorize an unaligned shot")
		for tick in range(10): update_attack(shooter, 1.0 / 60)
		assert(shots > 0, "Aligned gun must fire")
		assert(absf(bullets[0].v.angle()) < 0.01)
		# Follow-up burst bullets must also check direction and cover.
		var before := shots
		units[shooter.target].p = Vector2(50, 200)
		shooter.timer = 0
		update_attack(shooter, 1.0 / 60)
		assert(shots == before, "Moving target must be reacquired")
		shooter.p = Vector2(250, 170)
		units[shooter.target].p = Vector2(380, 170)
		shooter.phase = "瞄准"
		shooter.angle = 0
		update_attack(shooter, 1.0 / 60)
		assert(shots == before, "Cover must prevent firing")
		shooter.p = Vector2(50, 50)
		units[shooter.target].p = Vector2(200, 50)
		shooter.phase = "瞄准"
		shooter.timer = 0
		shooter.shot_count = 0
		update_attack(shooter, 1.0 / 60)
		assert(shots == before + 1, "Already aligned: fire without extra delay")
	print("AIM TESTS PASSED: both teams, turning, immediate fire, burst tracking, cover")

func run_boundary_tests() -> void:
	reset_round()
	# Deliberately press outward against all four sides, including while firing.
	for elapsed in [0.0, 18.0, 25.0, 42.0, 59.0]:
		clock = ROUND_TIME - elapsed
		var rect := safe_rect().grow(-RADIUS - 1)
		var points := [Vector2(rect.position.x, 320), Vector2(rect.end.x, 320), Vector2(320, rect.position.y), Vector2(320, rect.end.y)]
		var directions := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
		for i in range(4):
			units[i].p = points[i]
			units[i].dodge = 1.0
			units[i].dodge_dir = directions[i]
			units[i].hp = MAX_HP
		simulate(1.0 / 60)
		for u in units: assert(valid_arena_position(u.p), "Outward dodge crossed boundary")
	# Let the boundary advance through stationary units, including cover-adjacent points.
	reset_round()
	for u in units: u.p = Vector2(310, 30 + u.member * 580)
	for tick in range(2700):
		clock = ROUND_TIME - tick / 60.0
		refresh_boundary_navigation()
		enforce_boundary()
		for u in units: assert(valid_arena_position(u.p), "Shrinking border left a unit outside")
	print("BOUNDARY TESTS PASSED: four edges, outward dodges, continuous shrinking, cover intersections")

func run_team_tests() -> void:
	reset_round()
	units[0].p = Vector2(100, 290)
	units[1].p = Vector2(100, 350)
	units[2].p = Vector2(270, 290)
	units[3].p = Vector2(260, 350)
	var visible := [contacts(0), contacts(1)]
	update_team_focus(visible)
	assert(choose_target(units[0], visible[0]) == choose_target(units[1], visible[0]), "Both allies must favor the reachable common focus")
	units[0].hp = 30
	units[0].retreat = 1
	units[2].target = 0
	units[2].phase = "瞄准"
	tactics[0] = 1
	assert(choose_target(units[1], visible[0]) == 2, "Support must prioritize the ally's attacker")
	units[3].target = 0
	units[3].phase = "点射"
	assert(incoming_pressure(units[0], visible[0]) == 2)
	units[2].p = Vector2(380, 170)
	units[1].p = Vector2(250, 170)
	assert(choose_target(units[1], [2]) == -1, "Shared focus must not authorize shots through cover")
	print("TEAM TESTS PASSED: common target, covering wounded ally, focus pressure, occlusion")

func passes_condition(u: Dictionary, target: int, condition: String) -> bool:
	match condition:
		"敌人距离≥3米": return target >= 0 and u.p.distance_to(units[target].p) >= 240
		"敌人正在攻击队友":
			var ally := ally_index(u)
			return target >= 0 and ally >= 0 and units[target].target == ally and units[target].phase in ["吟唱", "瞄准", "点射"]
		"队友正在被瞄准":
			var ally := ally_index(u)
			return ally >= 0 and incoming_pressure(units[ally], contacts(u.team)) > 0
		"自己被两人瞄准": return incoming_pressure(u, contacts(u.team)) >= 2
		"自己HP≤25": return u.hp <= MAX_HP * 0.5
		"队友HP≤25":
			var ally := ally_index(u)
			return ally >= 0 and units[ally].hp <= MAX_HP * 0.5
		"仅已标记敌人": return target >= 0 and units[target].marked > 0
		"仅未标记敌人": return target >= 0 and units[target].marked <= 0
		"敌人正在收招": return target >= 0 and units[target].phase == "收招"
		"敌人距离≤2米": return target >= 0 and u.p.distance_to(units[target].p) <= 160
	return true

func rule_target(u: Dictionary, visible: Array, rule: Array, shooting: bool) -> int:
	var candidates: Array = []
	for index in visible:
		if shooting and (blocked(u.p, units[index].p) or u.p.distance_to(units[index].p) > SHOT_RANGE): continue
		if passes_condition(u, index, rule[1]) and passes_condition(u, index, rule[2]): candidates.append(index)
	# Preferences narrow only when a preferred candidate exists; never turn into hard gates.
	for condition in [rule[1], rule[2]]:
		if candidates.is_empty(): break
		if condition == "优先队友目标":
			var ally := ally_index(u)
			if ally >= 0 and units[ally].target in candidates and units[ally].phase in ["吟唱", "瞄准", "点射", "收招"]:
				candidates = [units[ally].target]
		elif condition == "优先最近敌人":
			var nearest: float = INF
			for index in candidates: nearest = minf(nearest, u.p.distance_squared_to(units[index].p))
			candidates = candidates.filter(func(index): return u.p.distance_squared_to(units[index].p) <= nearest + 0.01)
		elif condition == "优先低血量":
			var lowest := 101.0
			for index in candidates: lowest = minf(lowest, units[index].hp)
			candidates = candidates.filter(func(index): return units[index].hp <= lowest)
	var best := -1
	var distance := INF
	for index in candidates:
		var d: float = u.p.distance_squared_to(units[index].p)
		if d < distance: best = index; distance = d
	return best

func record_rule(u: Dictionary, kind: String, slot: int, skill: String) -> void:
	u.rule = "%s%d %s" % [kind, slot + 1, skill]
	u.rule_kind = "active" if kind == "主动" else "reaction"
	u.rule_slot = slot
	u.reason = "命中%s规则%d：%s" % [kind, slot + 1, skill]
	u.rule_flash = 1.4
	u.intent = skill
	var key := "%d:%s" % [u.uid, skill]
	reaction_counts[key] = int(reaction_counts.get(key, 0)) + 1
	if skill != "接敌" and skill != "点射":
		log_event("%s%d · %s" % ["蓝" if u.team == 0 else "红", u.member + 1, u.rule])

func nearest_legal_goal(goal: Vector2) -> Vector2:
	var best := Vector2(320, 320)
	var distance := INF
	for x in range(32):
		for y in range(32):
			if nav.is_point_solid(Vector2i(x, y)): continue
			var point := Vector2(x * 20 + 10, y * 20 + 10)
			var d := point.distance_squared_to(goal)
			if d < distance: best = point; distance = d
	return best

func magic_element(skill: String) -> String:
	return Tactics.MAGIC.get(skill, {}).get("element", "")

func shot_damage(skill: String) -> float:
	if skill in Tactics.MAGIC: return Tactics.MAGIC[skill].damage
	return {"点射": 7.0, "标记弹": 8.0, "强力射击": 18.0, "压制射击": 7.0, "协同追击": 8.0}.get(skill, 1.0)

func try_active(u: Dictionary, visible: Array) -> bool:
	var rows: Array = loadouts[u.uid].active
	u.reason = "没有配置主动策略"
	var first_skip := ""
	for slot in range(rows.size()):
		var rule: Array = rows[slot]
		var skill: String = rule[0]
		if skill == "留空": continue
		if float(u.skill_cds.get(skill, 0.0)) > 0:
			if first_skip.is_empty(): first_skip = "%s冷却中" % skill
			continue
		var shooting := skill in Tactics.MAGIC or skill in ["标记弹", "强力射击", "压制射击"]
		if shooting and u.cooldown > 0:
			if first_skip.is_empty(): first_skip = "武器正在恢复"
			continue
		var target := rule_target(u, visible, rule, shooting)
		if target < 0:
			if first_skip.is_empty(): first_skip = "%s暂无符合条件的可用目标" % skill
			continue
		if skill == "短冲刺" and u.p.distance_to(units[target].p) < 140: continue
		if shooting:
			begin_shot(u, target, skill)
			u.skill_cds[skill] = Tactics.MAGIC[skill].cd if skill in Tactics.MAGIC else {"标记弹": 5.0, "强力射击": 6.0, "压制射击": 6.0}[skill]
		else:
			var away: Vector2 = (u.p - units[target].p).normalized()
			var goal: Vector2 = u.p
			if skill == "绕侧": goal += away.orthogonal() * (95 if u.member == 0 else -95)
			elif skill == "后撤": goal += away * 100
			elif skill == "短冲刺": goal -= away * minf(90, u.p.distance_to(units[target].p) - 120)
			u.action_goal = nearest_legal_goal(goal)
			if u.p.distance_to(u.action_goal) < 15: continue
			u.action_left = 0.5 if skill == "短冲刺" else 1.0
			u.dash_recovery = skill == "短冲刺"
			u.skill_cds[skill] = 4.0
			u.target = target
			u.active_skill = skill
			u.avoid_left = 0.0
			u.repath = 0.0
			u.phase = skill
		record_rule(u, "主动", slot, skill)
		return true
	if not first_skip.is_empty(): u.reason = first_skip
	return false

func threats_to(u: Dictionary, visible: Array) -> Array:
	var threats: Array = []
	for index in visible:
		var enemy: Dictionary = units[index]
		if enemy.active_skill in Tactics.PATTERNS and enemy.phase == "吟唱": continue
		if enemy.phase not in ["吟唱", "瞄准", "点射"] or enemy.target < 0: continue
		if units[enemy.target].uid != u.uid or blocked(enemy.p, u.p): continue
		if enemy.p.distance_to(u.p) <= SHOT_RANGE: threats.append(index)
	# A projectile remains a threat after its shooter has entered recovery.
	for b in bullets:
		if b.team == u.team or b.life <= 0: continue
		var near := Geometry2D.get_closest_point_to_segment(u.p, b.p, b.p + b.v * minf(0.55, b.life))
		if near.distance_to(u.p) > RADIUS + 4 or blocked(b.p, u.p): continue
		for index in visible:
			if units[index].uid == b.get("source", -1) and index not in threats: threats.append(index)
	for h in hazards:
		if h.team == u.team or h.kind != "area" or u.p.distance_to(h.p) > h.radius + RADIUS: continue
		for index in visible:
			if units[index].uid == h.source and index not in threats: threats.append(index)
	for d in perceived_dangers(u, visible):
		if danger_contains(d, u.p) and d.source in visible and d.source not in threats: threats.append(d.source)
	return threats

func dodge_path_free(u: Dictionary, direction: Vector2) -> bool:
	for distance in [20.0, 40.0, 60.0, 80.0]:
		if not movement_is_free(u, u.p + direction * distance): return false
	return true

func try_reaction(u: Dictionary, visible: Array, defensive_only := false) -> bool:
	var threats := threats_to(u, visible)
	var ally := ally_index(u)
	var rows: Array = loadouts[u.uid].reaction
	for slot in range(rows.size()):
		var rule: Array = rows[slot]
		var skill: String = rule[0]
		if skill == "留空" or float(u.skill_cds.get(skill, 0.0)) > 0: continue
		if skill in ["协同追击", "追风", "焰返", "震山"] and u.cooldown > 0: continue
		if defensive_only and skill not in ["侧闪", "架枪防御"]: continue
		if skill in ["回春", "灵木护佑"]:
			var recipient := heal_target(u, rule)
			if recipient < 0: continue
			heals_pending.append({"uid": units[recipient].uid, "amount": 8.0 if skill == "灵木护佑" else 12.0})
			if skill == "灵木护佑": shields_pending.append({"uid": units[recipient].uid, "amount": 8.0})
			links.append({"a": u.p, "b": units[recipient].p, "life": 0.7, "color": Tactics.ELEMENT_COLORS["林"]})
			u.action_left = 0.5
			u.action_goal = u.p
			u.phase = skill
			u.skill_cds[skill] = 9.0 if skill == "灵木护佑" else 8.0
			u.avoid_left = 0.0
			u.dash_recovery = false
			record_rule(u, "反应", slot, skill)
			return true
		var candidates: Array = threats
		if skill == "掩护队友":
			if ally < 0 or u.p.distance_to(units[ally].p) > 240 or blocked(u.p, units[ally].p): continue
			if units[ally].shield > 0: continue
			candidates = threats_to(units[ally], visible)
		elif skill in ["协同追击", "追风"]:
			candidates = []
			for event in hit_events:
				if event.team == u.team and event.source != u.uid and event.source >= 0 and units[event.target].hp > 0 and event.target in visible:
					if event.target not in candidates: candidates.append(event.target)
		var target := rule_target(u, candidates, rule, skill in ["协同追击", "追风", "焰返", "震山"])
		if target < 0: continue
		if skill == "侧闪":
			var dangers := perceived_dangers(u, visible)
			var choice := escape_destination(u, dangers, DODGE_SPEED, true)
			# Dodge a committed trajectory or published telegraph, not mere targeting.
			if choice.is_empty(): continue
			var lateral: Vector2 = (choice.point - u.p).normalized()
			u.evade_source = choice.source
			u.counter_left = 3.0
			u.dodge = DODGE_DISTANCE / DODGE_SPEED
			u.dodge_dir = lateral
			u.phase = "侧闪"
			u.skill_cds[skill] = 2.8
		elif skill == "架枪防御":
			u.guard = 0.8
			u.phase = skill
			u.action_left = 0.6
			u.action_goal = u.p
			u.skill_cds[skill] = 5.0
		elif skill == "掩护队友":
			shields_pending.append({"uid": units[ally].uid})
			links.append({"a": u.p, "b": units[ally].p, "life": 0.65, "color": Color.CYAN})
			u.phase = skill
			u.action_left = 0.35
			u.action_goal = u.p
			u.skill_cds[skill] = 6.0
		elif skill in ["协同追击", "追风"]:
			begin_shot(u, target, skill)
			u.skill_cds[skill] = 6.0 if skill == "追风" else 5.0
			if ally >= 0: links.append({"a": units[ally].p, "b": u.p, "life": 0.65, "color": Color("76f0a9")})
		elif skill in ["焰返", "震山"]:
			begin_shot(u, target, skill)
			u.skill_cds[skill] = Tactics.MAGIC[skill].cd
		# Reactions replace a movement action; never resume its stale destination.
		if skill == "侧闪": u.action_left = 0.0
		u.avoid_left = 0.0
		u.dash_recovery = false
		record_rule(u, "反应", slot, skill)
		return true
	return false

func run_rules_tests() -> void:
	team_presets = [0, 1]
	setup_loadouts()
	# Exercise the actual editor callback, including closure binding and reset.
	editor_unit = 2
	var edit: OptionButton = editor_rows[1].menus[0]
	edit.item_selected.emit(ACTIVE_SKILLS.find("标记弹"))
	assert(loadouts[2].active[1][0] == "标记弹")
	assert(loadouts[0].active[1][0] == "强力射击")
	setup_loadouts()
	editor_unit = 0
	rebuild_editor()
	reset_round()
	units[0].p = Vector2(100, 300)
	units[1].p = Vector2(100, 350)
	units[2].p = Vector2(230, 300)
	units[3].p = Vector2(240, 350)
	assert(rule_target(units[0], [2, 3], ["点射", "仅已标记敌人", "无"], true) == -1)
	assert(rule_target(units[0], [2, 3], ["点射", "优先队友目标", "无"], true) >= 0)
	units[3].marked = 2.0
	assert(rule_target(units[0], [2, 3], ["点射", "仅已标记敌人", "无"], true) == 3)
	units[2].phase = "瞄准"
	units[2].target = 0
	loadouts[0].reaction = [["侧闪", "无", "无"]]
	assert(not try_reaction(units[0], [2, 3]), "Targeting alone must not spend dodge")
	bullets.append({"p": Vector2(220, 300), "v": Vector2(-360, 0), "life": 1.0, "team": 1, "source": 2, "damage": 1.0})
	assert(try_reaction(units[0], [2, 3]))
	assert(units[0].dodge > 0)
	assert(not try_reaction(units[0], [2, 3]), "Cooldown must prevent repeated dodge; guard HP gate must reject")
	loadouts[0].active = [["留空", "无", "无"]]
	assert(not try_active(units[0], [2, 3]), "Empty strategy has no special action")
	units[0].dodge = 0
	baseline_action(units[0], [2, 3])
	assert(units[0].active_skill == "点射" and units[0].phase == "瞄准", "Empty rules still perform baseline attacks")
	setup_loadouts()
	var results: Array = []
	for swapped in [false, true]:
		blue_attacks = not swapped
		reset_round()
		for tick in range(3602):
			if finished: break
			simulate(1.0 / 60)
		assert(finished)
		results.append({"swapped": swapped, "winner": winner_team, "elapsed": ROUND_TIME - clock, "shots": shots, "hits": hits, "skills": reaction_counts.duplicate()})
		assert(shots > 0 and hits > 0)
	print("RULES TESTS PASSED: filters, preference fallback, cooldown, empty rules, two full matches")
	print(JSON.stringify(results))
	var file := FileAccess.open("res://reports/rules-demo.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))

func run_movement_tests() -> void:
	# Captured positions from the half-speed demonstration at 14 seconds.
	# Test without enemies/attacks: the pair must free itself through movement alone.
	for step in [1.0 / 120, 1.0 / 60]:
		reset_round()
		units[0].p = Vector2(210, 310)
		units[1].p = Vector2(290, 310)
		units[2].hp = 0
		units[3].hp = 0
		var goals := [Vector2(390, 310), Vector2(130, 310)]
		var traveled := [0.0, 0.0]
		for tick in range(int(6.0 / step)):
			var proposals: Array = []
			for index in range(2):
				var u: Dictionary = units[index].duplicate(true)
				u.intent = "接敌"
				u.repath -= step
				move_unit(u, goals[index], step)
				proposals.append(u)
			if proposals[0].p.distance_to(proposals[1].p) >= RADIUS * 2:
				for index in range(2):
					traveled[index] += proposals[index].p.distance_to(units[index].p)
					units[index] = proposals[index]
			for index in range(2): assert(valid_arena_position(units[index].p))
		assert(units[0].p.distance_to(goals[0]) < 8, "First ally must pass its teammate without being attacked")
		assert(units[1].p.distance_to(goals[1]) < 8, "Second ally must pass its teammate without being attacked")
		print("MOVEMENT step=", step, " traveled=", traveled, " destinations reached")
	print("MOVEMENT TESTS PASSED: screenshot crossing, no enemy trigger, no overlap or boundary escape")

func run_content_tests() -> void:
	team_presets = [0, 1]
	setup_loadouts()
	# Preset picker and editor use the actual UI callbacks.
	preset_menus[0].item_selected.emit(2)
	assert(loadouts[0].reaction[0][0] == "架枪防御")
	assert(loadouts[2].active[0][0] == "后撤")
	team_presets = [0, 1]
	setup_loadouts()
	reset_round()
	for i in range(4): loadouts[i] = Tactics.build([], [])
	for tick in range(3602):
		if finished: break
		simulate(STEP)
	assert(finished and shots > 0 and hits > 0, "Empty strategies must search and fight unaided")
	print("BASELINE: empty slots completed a match, shots=", shots)

	# Only observed last position feeds searching, never an invisible live enemy position.
	reset_round()
	units[0].p = Vector2(100, 300)
	units[0].last_seen = Vector2(230, 310)
	units[0].memory = 3.0
	assert(choose_goal(units[0], []).distance_to(Vector2(230, 310)) < 15)

	# Protection is scoped to an attacked ally in range and with line of sight.
	for i in range(4): loadouts[i] = Tactics.build([], [])
	units[0].p = Vector2(100, 300)
	units[1].p = Vector2(130, 340)
	units[2].p = Vector2(230, 340)
	units[3].hp = 0
	units[2].phase = "瞄准"
	units[2].target = 1
	loadouts[0].reaction[0] = ["掩护队友", "无", "无"]
	simulate(STEP)
	assert(units[1].shield == 10 and units[0].skill_cds.has("掩护队友"))
	units[0].skill_cds.clear()
	units[0].p = Vector2(100, 50)
	assert(not try_reaction(units[0], [2]), "Shield cannot act outside support range")

	# Slow is applied on actual impact; shield absorbs damage before health.
	reset_round()
	units[0].p = Vector2(100, 300)
	units[1].p = Vector2(100, 400)
	units[2].p = Vector2(200, 300)
	units[3].p = Vector2(200, 400)
	units[2].shield = 1
	units[2].shield_time = 2
	bullets.append({"p": Vector2(185, 300), "v": Vector2(410, 0), "life": 1.0, "team": 0, "source": 0, "damage": 1.0, "slow": true, "skill": "压制射击"})
	update_bullets(STEP)
	assert(units[2].hp == MAX_HP and units[2].shield == 0 and units[2].slow > 2)
	assert(unit_move_speed(units[2]) < MOVE_SPEED)
	loadouts[1].reaction = [["协同追击", "无", "无"]]
	assert(try_reaction(units[1], [2, 3]))
	assert(units[1].active_skill == "协同追击" and units[1].target == 2)
	hit_events.clear()
	bullets.clear()
	bullets.append({"p": Vector2(185, 300), "v": Vector2(410, 0), "life": 1.0, "team": 0, "source": 1, "damage": 1.0, "skill": "协同追击"})
	update_bullets(STEP)
	assert(hit_events.is_empty(), "Follow-up impacts must not create new follow-up triggers")

	# All playback speeds advance the same fixed simulation steps.
	setup_loadouts()
	var snapshots: Array = []
	for playback_speed in [0.5, 1.0, 2.0]:
		reset_round()
		running = true
		speed = playback_speed
		for frame in range(int(120 / playback_speed)): advance_playback(STEP)
		var state: Array = [shots, hits, snappedf(clock, 0.0001)]
		for u in units: state.append([u.p, u.hp, u.phase])
		snapshots.append(state)
	assert(snapshots[0] == snapshots[1] and snapshots[1] == snapshots[2], "Playback speed must not change combat")
	reset_round()
	step_forward()
	assert(not running and is_equal_approx(clock, ROUND_TIME - 0.2))

	var results: Array = []
	var counts := {}
	for blue in range(3):
		for red in range(3):
			for side in [true, false]:
				team_presets = [blue, red]
				setup_loadouts()
				blue_attacks = side
				reset_round()
				for tick in range(3602):
					if finished: break
					simulate(STEP)
				assert(finished and shots > 0)
				for key in reaction_counts:
					var skill: String = key.get_slice(":", 1)
					counts[skill] = int(counts.get(skill, 0)) + reaction_counts[key]
				results.append({"blue": Tactics.NAMES[blue], "red": Tactics.NAMES[red], "blue_left": side, "winner": winner_team, "seconds": ROUND_TIME - clock, "shots": shots})
	reset_round()
	units[0].p = Vector2(140, 320)
	units[2].p = Vector2(260, 320)
	loadouts[0] = Tactics.build([["后撤", "敌人距离≤2米", "无"]], [])
	assert(try_active(units[0], [2]) and units[0].intent == "后撤")
	var file := FileAccess.open("res://reports/content-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": ["empty rules fight", "last-seen search", "shield scope", "shield absorption", "slow impact", "follow-up no chain", "fixed-step playback", "single step"], "skill_activations": counts, "matches": results}, "\t"))
	print("CONTENT TESTS PASSED: baseline, support, slow, follow-up, playback, 18 preset matches")
	print("ACTIVATIONS: ", counts)

func heal_target(u: Dictionary, rule: Array) -> int:
	for condition in [rule[1], rule[2]]:
		if condition not in ["无", "优先低血量", "自己HP≤25", "队友HP≤25"]: return -1
		if not passes_condition(u, -1, condition): return -1
	var best := -1
	for index in range(units.size()):
		var ally: Dictionary = units[index]
		if ally.team != u.team or ally.hp <= 0 or ally.hp >= MAX_HP or ally.hurt_recent <= 0: continue
		if u.p.distance_to(ally.p) > 240 or blocked(u.p, ally.p): continue
		if best < 0 or ally.hp < units[best].hp: best = index
	return best

func run_magic_tests() -> void:
	# Wind really emits two separate projectiles; mountain remains a single hit.
	for skill in ["风刃", "落岩"]:
		reset_round()
		units[0].p = Vector2(100, 300)
		units[2].p = Vector2(200, 300)
		units[0].angle = 0
		begin_shot(units[0], 2, skill)
		if skill == "落岩":
			update_attack(units[0], 0.2)
			assert(shots == 0 and units[0].phase == "吟唱")
		for tick in range(180): update_attack(units[0], STEP)
		assert(shots == (2 if skill == "风刃" else 1))
		assert(bullets[0].damage == (6.0 if skill == "风刃" else 20.0))
	# Fire bypasses defense reduction, but not cover or a real shield.
	for true_damage in [false, true]:
		reset_round()
		units[2].p = Vector2(200, 300)
		units[2].guard = 1.0
		units[2].shield = 1.0
		bullets.append({"p": Vector2(185, 300), "v": Vector2(410, 0), "life": 1.0, "team": 0, "source": 0, "damage": 2.0, "true_damage": true_damage})
		update_bullets(STEP)
		assert(is_equal_approx(units[2].hp, MAX_HP - 1 if true_damage else MAX_HP))
	reset_round()
	units[2].p = Vector2(320, 200)
	bullets.append({"p": Vector2(280, 200), "v": Vector2(410, 0), "life": 1.0, "team": 0, "source": 0, "damage": 2.0, "true_damage": true})
	update_bullets(0.1)
	assert(units[2].hp == MAX_HP, "Fire may bypass armor, never cover")
	# Forest applies exactly two periodic ticks without needing new projectiles.
	reset_round()
	units[2].thorns = 4.0
	units[2].thorn_tick = 2.0
	for tick in range(300): update_bullets(STEP)
	assert(units[2].hp == MAX_HP - 10 and units[2].thorns == 0)
	for i in range(4): loadouts[i] = Tactics.build([], [])
	units[0].p = Vector2(100, 300)
	units[1].p = Vector2(100, 380)
	units[1].hp = 2
	units[1].hurt_recent = 0.8
	loadouts[0].reaction[0] = ["回春", "优先低血量", "无"]
	simulate(STEP)
	assert(units[1].hp == 14 and units[1].heal_flash > 0)
	units[0].skill_cds.clear()
	units[1].p = Vector2(500, 300)
	assert(heal_target(units[0], loadouts[0].reaction[0]) == -1)
	# Wind follow-up does not feed another follow-up chain.
	reset_round()
	units[2].p = Vector2(200, 300)
	bullets.append({"p": Vector2(185, 300), "v": Vector2(410, 0), "life": 1.0, "team": 0, "source": 0, "damage": 1.0, "skill": "追风"})
	update_bullets(STEP)
	assert(hit_events.is_empty())
	var counts := {}
	var results: Array = []
	for magic_team in [3, 4]:
		for opponent in range(5):
			for side in [true, false]:
				team_presets = [magic_team, opponent]
				setup_loadouts()
				blue_attacks = side
				reset_round()
				for tick in range(3602):
					if finished: break
					simulate(STEP)
				assert(finished and shots > 0)
				for key in reaction_counts:
					var skill: String = key.get_slice(":", 1)
					counts[skill] = int(counts.get(skill, 0)) + reaction_counts[key]
				results.append({"blue": Tactics.NAMES[magic_team], "red": Tactics.NAMES[opponent], "blue_left": side, "winner": winner_team, "seconds": ROUND_TIME - clock})
	for skill in ["风刃", "追风", "火矢", "焰返", "落岩", "震山", "荆棘", "回春"]:
		assert(int(counts.get(skill, 0)) > 0, "Magic never triggered: " + skill)
	var file := FileAccess.open("res://reports/magic-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": ["wind multi-hit", "mountain cast and single hit", "fire bypass defense not shields/cover", "forest two periodic ticks", "heal and range", "wind follow-up no chain"], "activations": counts, "matches": results}, "\t"))
	print("MAGIC TESTS PASSED: four elements, eight skills, 20 complete matches")
	print(counts)

func run_readability_tests() -> void:
	for wall in walls:
		assert(wall.size.x > 0 and wall.size.y > 0)
		assert(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)).encloses(wall))
	assert(RADIUS * 2 == 48)
	# Identical incoming bullet hits a stationary unit but misses a side-stepping unit.
	var health: Array = []
	for evade in [false, true]:
		reset_round()
		for i in range(4): loadouts[i] = Tactics.build([], [])
		units[0].p = Vector2(140, 320)
		units[1].hp = 0
		units[2].p = Vector2(380, 320)
		units[3].hp = 0
		units[0].phase = "瞄准"
		units[0].target = 2
		units[0].angle = PI
		units[2].phase = "收招"
		units[2].timer = 10
		if evade: loadouts[0].reaction[0] = ["侧闪", "无", "无"]
		bullets.append({"p": Vector2(320, 320), "v": Vector2(-280, 0), "life": 1.0, "team": 1, "source": 2, "damage": 1.0})
		if evade:
			simulate(STEP)
			assert(units[0].phase == "侧闪", "Incoming bullet can cancel pre-shot aiming")
		for tick in range(45):
			if evade and units[0].dodge > 0:
				units[0].p += units[0].dodge_dir * DODGE_SPEED * STEP
				units[0].dodge -= STEP
			update_bullets(STEP)
		health.append(units[0].hp)
	assert(health == [MAX_HP - 1, MAX_HP], "Dodge must avoid actual projectile, not just animate")
	var rows: Array = []
	for preset in range(5):
		team_presets = [3, preset]
		setup_loadouts()
		for side in [false, true]:
			blue_attacks = side
			reset_round()
			for tick in range(3602):
				if finished: break
				simulate(STEP)
				for u in units:
					assert(u.hp >= 0 and u.hp <= MAX_HP and u.hp == floorf(u.hp))
					if u.hp > 0: assert(valid_arena_position(u.p))
			assert(finished and shots > 0)
			rows.append({"opponent": preset, "blue_left": side, "winner": winner_team, "seconds": ROUND_TIME - clock, "skills": reaction_counts.duplicate()})
	var file := FileAccess.open("res://reports/readability-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	print("READABILITY PASSED: continuous arena walls, 48px bodies, integer HP, actual dodge, ten matches and boundaries")

# Telegraph geometry and hit geometry share these helpers. No random scatter.
func beam_end(p: Vector2, angle: float) -> Vector2:
	var direction := Vector2.from_angle(angle)
	for distance in range(1, int(SHOT_RANGE) + 1):
		var point := p + direction * distance
		if blocked(p, point): return p + direction * (distance - 1)
	return p + direction * SHOT_RANGE

func mortar_points(center: Vector2) -> Array:
	# One readable locked landing zone; no random scatter or target tracking.
	return [center.clamp(Vector2.ONE * BLAST_RADIUS, Vector2.ONE * (SIZE - BLAST_RADIUS))]

func blast_progress(remaining: float) -> float:
	return clampf(1.0 - remaining / (BLAST_CAST + BLAST_FLIGHT), 0, 1)

func pattern_radius(skill: String) -> float:
	if skill == "烈焰爆破": return 80.0
	if skill == "裂地冲击": return 20.0
	return 7.0 if skill == "蓄能贯穿" else BLAST_RADIUS

func area_total_time(skill: String) -> float:
	return float(Tactics.MAGIC[skill].cast) + BLAST_FLIGHT

func release_pattern(u: Dictionary) -> void:
	u.fire_flash = 0.18
	shots += 1
	var skill: String = u.active_skill
	var data: Dictionary = Tactics.MAGIC[skill]
	if skill in Tactics.LINES:
		hazards.append({"kind": "beam", "skill": skill, "p": u.p, "end": beam_end(u.p, u.lock_angle), "team": u.team, "source": u.uid, "left": 0.0, "damage": data.damage, "radius": pattern_radius(skill), "true_damage": data.element == "火"})
	elif skill in Tactics.AREAS:
		for point in mortar_points(u.lock_point):
			hazards.append({"kind": "area", "skill": skill, "p": point, "origin": u.p, "team": u.team, "source": u.uid, "left": BLAST_FLIGHT, "damage": data.damage, "radius": pattern_radius(skill), "true_damage": data.element == "火"})
	else:
		for angle in [-0.36, -0.18, 0.0, 0.18, 0.36]:
			var direction := Vector2.from_angle(u.lock_angle + angle)
			bullets.append({"p": u.p + direction * (RADIUS + 4), "v": direction * SHOTGUN_SPEED, "life": 200.0 / SHOTGUN_SPEED, "team": u.team, "source": u.uid, "skill": skill, "element": "风", "damage": data.damage})

# Overhead blasts use the full displayed disk, including when their center is on cover.
func area_overlaps_body(center: Vector2, radius: float, point: Vector2, margin := 0.0) -> bool:
	return center.distance_squared_to(point) <= pow(radius + RADIUS + margin, 2)

func resolve_hazards(dt: float, damage: Array) -> void:
	for fx in blasts: fx.life -= dt
	blasts = blasts.filter(func(fx): return fx.life > 0)
	for h in hazards:
		h.left -= dt
		if h.left > 0: continue
		for i in range(units.size()):
			var u: Dictionary = units[i]
			if u.hp <= 0 or u.team == h.team: continue
			var contact: bool = false
			if h.kind == "beam":
				contact = Geometry2D.get_closest_point_to_segment(u.p, h.p, h.end).distance_to(u.p) <= RADIUS + h.radius and not blocked(h.p, u.p)
			else:
				contact = area_overlaps_body(h.p, h.radius, u.p)
			if contact:
				damage[i] += maxf(0, h.damage - (6 if u.guard > 0 and not h.get("true_damage", h.kind == "beam") else 0))
				hits += 1
				hit_events.append({"source": h.source, "team": h.team, "target": i, "life": 0.8})
		var fx: Dictionary = h.duplicate()
		fx.life = 0.3
		blasts.append(fx)
	hazards = hazards.filter(func(h): return h.left > 0)

func draw_landing(point: Vector2, color: Color, progress: float, radius := BLAST_RADIUS, total := BLAST_CAST + BLAST_FLIGHT) -> void:
	var p := ORIGIN + point
	var value := clampf(progress, 0, 1)
	draw_circle(p, radius, Color(color, 0.05 + value * 0.07))
	# The thin full circle is the actual damage boundary; the thick arc is the timer.
	draw_arc(p, radius, 0, TAU, 96, Color(color, 0.25), 1.5)
	if value > 0:
		draw_arc(p, radius, -PI / 2, -PI / 2 + TAU * value, 96, color, 3.5)
		var tip := p + Vector2.from_angle(-PI / 2 + TAU * value) * radius
		draw_circle(tip, 4, color.lightened(0.3))
	draw_line(p - Vector2(5, 0), p + Vector2(5, 0), Color(color, 0.65), 1)
	draw_line(p - Vector2(0, 5), p + Vector2(0, 5), Color(color, 0.65), 1)
	draw_string(font, p + Vector2(-14, radius + 17), "%.1fs" % ((1 - value) * total), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)

func draw_patterns() -> void:
	if show_aim:
		for u in units:
			if u.hp <= 0 or u.phase != "吟唱": continue
			var color: Color = ATTACK_BLUE if u.team == 0 else ATTACK_RED
			if u.active_skill in Tactics.LINES:
				var end := beam_end(u.p, u.lock_angle)
				draw_line(ORIGIN + u.p, ORIGIN + end, Color(color, 0.18), pattern_radius(u.active_skill) * 2)
				draw_dashed_line(ORIGIN + u.p, ORIGIN + end, color, 1.5, 7)
			elif u.active_skill == "霰弹":
				var polygon := PackedVector2Array([ORIGIN + u.p])
				for step in range(13): polygon.append(ORIGIN + u.p + Vector2.from_angle(u.lock_angle - 0.36 + step * 0.06) * 228)
				draw_colored_polygon(polygon, Color(color, 0.12))
				for angle in [-0.36, -0.18, 0.0, 0.18, 0.36]: draw_dashed_line(ORIGIN + u.p, ORIGIN + u.p + Vector2.from_angle(u.lock_angle + angle) * 228, Color(color, 0.5), 1, 6)
			elif u.active_skill in Tactics.AREAS:
				for point in mortar_points(u.lock_point): draw_landing(point, color, 1.0 - (u.timer + BLAST_FLIGHT) / area_total_time(u.active_skill), pattern_radius(u.active_skill), area_total_time(u.active_skill))
		for h in hazards:
			if h.kind != "area": continue
			var color: Color = ATTACK_BLUE if h.team == 0 else ATTACK_RED
			draw_landing(h.p, color, 1.0 - h.left / area_total_time(h.get("skill", "抛射轰击")), h.radius, area_total_time(h.get("skill", "抛射轰击")))
	for h in hazards:
		if h.kind != "area": continue
		var t: float = clampf(1.0 - h.left / BLAST_FLIGHT, 0, 1)
		var shell: Vector2 = h.get("origin", h.p).lerp(h.p, t) + Vector2(0, -80 * sin(t * PI))
		draw_circle(ORIGIN + shell, 5, ATTACK_BLUE if h.team == 0 else ATTACK_RED)
	for fx in blasts:
		var color := Color(ATTACK_BLUE if fx.team == 0 else ATTACK_RED, fx.life / 0.3)
		if fx.kind == "beam":
			draw_line(ORIGIN + fx.p, ORIGIN + fx.end, Color(color, color.a * 0.25), fx.radius * 4)
			draw_line(ORIGIN + fx.p, ORIGIN + fx.end, color, fx.radius * 2 * fx.life / 0.3)
			draw_line(ORIGIN + fx.p, ORIGIN + fx.end, Color(Color.WHITE, color.a), 3)
			if fx.get("skill", "") == "裂地冲击":
				for n in range(1, 9):
					var point: Vector2 = ORIGIN + fx.p.lerp(fx.end, n / 9.0)
					draw_circle(point, 5 + (n % 3) * 3, Color("d8b08a", color.a))
		else:
			draw_circle(ORIGIN + fx.p, fx.radius, Color(color, fx.life * 0.6))
			draw_arc(ORIGIN + fx.p, fx.radius, 0, TAU, 96, color, 3)
			draw_arc(ORIGIN + fx.p, fx.radius * (1 - fx.life / 0.3), 0, TAU, 32, color, 3)

		if fx.kind == "area":
			if fx.get("skill", "") == "烈焰爆破":
				for n in range(6):
					var petal: Vector2 = ORIGIN + fx.p + Vector2.from_angle(n * TAU / 6) * fx.radius * 0.35
					draw_arc(petal, fx.radius * 0.35 * fx.life / 0.3, 0, TAU, 16, Color("fff0bf", color.a * 0.65), 3)
			for n in range(12):
				var direction := Vector2.from_angle(n * TAU / 12)
				var tip: Vector2 = ORIGIN + fx.p + direction * fx.radius * (1.0 - fx.life / 0.3)
				draw_line(tip, tip - direction * 14, color.lightened(0.3), 3)

func pattern_fixture() -> void:
	reset_round()
	for i in range(4): loadouts[i] = Tactics.build([], [])
	units[0].p = Vector2(100, 320)
	units[1].hp = 0
	units[2].p = Vector2(250, 320)
	units[3].hp = 0
	units[0].angle = 0

func run_pattern_tests() -> void:
	pattern_fixture()
	begin_shot(units[0], 2, "蓄能贯穿")
	update_attack(units[0], 0.5)
	assert(hazards.is_empty() and shots == 0)
	units[2].p.y += 80
	update_attack(units[0], 0.61)
	update_bullets(STEP)
	assert(units[2].hp == MAX_HP and bullets.is_empty(), "Locked beam must miss lateral escape; no traveling bullet")
	pattern_fixture()
	begin_shot(units[0], 2, "蓄能贯穿")
	update_attack(units[0], 1.11)
	update_bullets(STEP)
	assert(units[2].hp == MAX_HP - 22)
	assert(beam_end(Vector2(180, 160), 0).x <= walls[0].position.x + 1, "Beam stops at cover")
	pattern_fixture()
	begin_shot(units[0], 2, "霰弹")
	update_attack(units[0], 0.46)
	assert(bullets.size() == 5 and units[2].hp == MAX_HP)
	assert(bullets[0].v != bullets[4].v)
	for tick in range(60): update_bullets(STEP)
	assert(units[2].hp < MAX_HP and bullets.is_empty())
	pattern_fixture()
	begin_shot(units[0], 2, "抛射轰击")
	var points := mortar_points(units[0].lock_point)
	update_attack(units[0], BLAST_CAST + 0.01)
	assert(hazards.size() == 1)
	units[2].p = points[0]
	update_bullets(BLAST_FLIGHT - 0.01)
	assert(units[2].hp == MAX_HP)
	update_bullets(0.02)
	assert(units[2].hp == MAX_HP - 18 and hazards.is_empty())
	var results: Array = []
	for blue in [5, 6]:
		for red in range(7):
			team_presets = [blue, red]
			setup_loadouts()
			reset_round()
			for tick in range(3602):
				if finished: break
				simulate(STEP)
				for u in units:
					assert(u.hp == floorf(u.hp) and u.hp >= 0 and u.hp <= MAX_HP)
			assert(finished and shots > 0)
			results.append({"blue": blue, "red": red, "winner": winner_team, "seconds": ROUND_TIME - clock, "skills": reaction_counts.duplicate()})
	var file := FileAccess.open("res://reports/pattern-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	print("PATTERN TESTS PASSED: locked instant beam/cover, five traveling pellets, delayed fixed blast circles, 14 matches")

# Perception reads visible casts and published impact zones, never future decisions.
func perceived_dangers(u: Dictionary, visible: Array) -> Array:
	var dangers: Array = []
	for index in visible:
		var enemy: Dictionary = units[index]
		if enemy.hp <= 0 or enemy.phase != "吟唱": continue
		var skill: String = enemy.active_skill
		var cast: float = Tactics.MAGIC.get(skill, {}).get("cast", 0.0)
		if cast - enemy.timer < 0.12: continue # Small, deterministic observation delay.
		if skill in Tactics.LINES:
			dangers.append({"kind": "line", "p": enemy.p, "end": beam_end(enemy.p, enemy.lock_angle), "radius": pattern_radius(skill), "eta": enemy.timer, "source": index, "walk_evade": true})
		elif skill == "霰弹":
			for angle in [-0.36, -0.18, 0.0, 0.18, 0.36]:
				var direction := Vector2.from_angle(enemy.lock_angle + angle)
				dangers.append({"kind": "line", "p": enemy.p, "end": enemy.p + direction * 228, "radius": 0.0, "eta": enemy.timer + maxf(0, enemy.p.distance_to(u.p) - RADIUS) / SHOTGUN_SPEED, "source": index})
		elif skill in Tactics.AREAS:
			for point in mortar_points(enemy.lock_point): dangers.append({"kind": "area", "p": point, "radius": pattern_radius(skill), "eta": enemy.timer + BLAST_FLIGHT, "source": index})
	for h in hazards:
		if h.kind == "area" and h.team != u.team:
			dangers.append({"kind": "area", "p": h.p, "radius": h.radius, "eta": h.left, "source": h.source})
	for b in bullets:
		if b.team == u.team or b.life <= 0 or blocked(b.p, u.p): continue
		var direction: Vector2 = b.v.normalized()
		if (u.p - b.p).dot(direction) < -RADIUS: continue
		var source: int = b.get("source", -1)
		if source not in visible: continue
		dangers.append({"kind": "line", "p": b.p, "end": b.p + b.v * minf(b.life, 0.7), "radius": 0.0, "eta": maxf(0.02, ((u.p - b.p).dot(direction) - RADIUS) / b.v.length()), "source": source})
	return dangers

func danger_contains(d: Dictionary, point: Vector2, margin := 6.0) -> bool:
	if d.kind == "area": return area_overlaps_body(d.p, d.radius, point, margin)
	return Geometry2D.get_closest_point_to_segment(point, d.p, d.end).distance_to(point) < d.radius + RADIUS + margin and not blocked(d.p, point)

func escape_destination(u: Dictionary, dangers: Array, move_speed: float, fixed_distance := false) -> Dictionary:
	var relevant: Array = dangers.filter(func(d): return danger_contains(d, u.p))
	if relevant.is_empty(): return {}
	var best := {}
	var best_score := INF
	var distances: Array = [DODGE_DISTANCE] if fixed_distance else [40.0, 60.0, 80.0, 100.0, 120.0, 140.0]
	for distance in distances:
		for i in range(24):
			var direction := Vector2.from_angle(i * TAU / 24)
			var point: Vector2 = u.p + direction * distance
			var safe := true
			for segment in range(1, int(distance / 8) + 1):
				if not movement_is_free(u, u.p + direction * minf(distance, segment * 8)): safe = false; break
			if not safe or not movement_is_free(u, point): continue
			for d in dangers:
				# Test where this movement will actually be when each attack arrives.
				var at_impact: Vector2 = u.p.move_toward(point, move_speed * maxf(0, d.eta - 0.04))
				if danger_contains(d, point) or danger_contains(d, at_impact): safe = false; break
			if not safe: continue
			var score: float = distance
			var source: int = relevant[0].source
			if source >= 0 and units[source].hp > 0:
				if blocked(point, units[source].p) or point.distance_to(units[source].p) > SHOT_RANGE: score += 30
			# Prefer the existing side to avoid reversing course on adjacent frames.
			if u.intent == "规避预警": score += point.distance_to(u.action_goal) * 0.2
			if score < best_score:
				best_score = score
				best = {"point": point, "source": source}
	return best

func prepare_tactical_escape(u: Dictionary, visible: Array) -> bool:
	var dangers := perceived_dangers(u, visible)
	var threatened := false
	for d in dangers:
		if (d.kind == "area" or d.get("walk_evade", false)) and danger_contains(d, u.p): threatened = true; break
	if not threatened:
		if u.intent == "规避预警": u.action_left = 0; u.phase = "移动"
		return false
	var choice := escape_destination(u, dangers, MOVE_SPEED * (0.6 if u.slow > 0 else 1.0))
	if choice.is_empty(): return false
	if u.intent != "规避预警":
		var key := "%d:规避预警" % u.uid
		reaction_counts[key] = int(reaction_counts.get(key, 0)) + 1
	u.action_goal = choice.point
	u.action_left = 0.0
	u.intent = "规避预警"
	u.rule_kind = ""
	u.rule_slot = -1
	u.rule_flash = 0
	u.phase = u.intent
	u.avoid_left = 0
	u.evade_source = choice.source
	u.counter_left = 3.0
	u.reason = "提前离开长蓄力或落点预警；普通弹道交给侧闪技能"
	return true

func counter_after_escape(u: Dictionary, visible: Array) -> bool:
	var source: int = u.evade_source
	if u.counter_left <= 0 or source < 0 or source not in visible or units[source].hp <= 0: return false
	var enemy: Dictionary = units[source]
	if enemy.phase == "吟唱":
		u.phase = "观察蓄力"
		u.intent = "等待反打"
		u.reason = "已离开预警范围，等对手出招"
		u.action_left = 0
		return true
	if enemy.phase != "收招" or u.cooldown > 0 or blocked(u.p, enemy.p) or u.p.distance_to(enemy.p) > SHOT_RANGE: return false
	# Do not reset weapon cooldown or grant free shots: normal aim and ballistics apply.
	begin_shot(u, source, "点射")
	u.intent = "收招反打"
	u.rule = "基础·收招反打"
	u.reason = "躲开攻击后，射击仍在收招的攻击者"
	u.counter_left = 0
	var key := "%d:收招反打" % u.uid
	reaction_counts[key] = int(reaction_counts.get(key, 0)) + 1
	log_event("%s%d 躲招后反打" % ["蓝" if u.team == 0 else "红", u.member + 1])
	return true

func run_evasion_tests() -> void:
	# No PP slots: baseline must leave the locked beam and punish its recovery.
	pattern_fixture()
	units[0].angle = 0
	units[2].angle = PI
	units[0].cooldown = 0.25
	begin_shot(units[2], 0, "蓄能贯穿")
	var escaped := false
	var countered := false
	var landed_in_recovery := false
	for tick in range(115):
		simulate(STEP)
		escaped = escaped or units[0].intent == "规避预警"
		countered = countered or units[0].intent == "收招反打"
		landed_in_recovery = landed_in_recovery or (units[2].hp < MAX_HP and units[2].phase == "收招")
	print("duel ", escaped, " ", countered, " ", landed_in_recovery, " hp ", units[0].hp, " enemy ", units[2].hp, " phase ", units[0].phase)
	assert(escaped and not countered and units[0].hp == MAX_HP, "Baseline dodges without injecting automatic counter rules")
	# Already outside the beam should not move merely because it was targeted.
	pattern_fixture()
	begin_shot(units[2], 0, "蓄能贯穿")
	units[2].timer = 0.8
	units[0].p.y += 90
	assert(not prepare_tactical_escape(units[0], [2]))
	# Two simultaneous landing zones: don't dodge from one into the other.
	pattern_fixture()
	units[2].phase = "收招"
	units[2].timer = 10
	for point in [Vector2(100, 320), Vector2(100, 390)]:
		hazards.append({"kind": "area", "p": point, "radius": 40.0, "team": 1, "source": 2, "left": 1.3, "damage": 1.0})
	var choice := escape_destination(units[0], perceived_dangers(units[0], [2]), MOVE_SPEED)
	assert(not choice.is_empty())
	for d in perceived_dangers(units[0], [2]): assert(not danger_contains(d, choice.point))
	for tick in range(85): simulate(STEP)
	assert(units[0].hp == MAX_HP, "Walking baseline must escape overlapping telegraphs")
	# An attack already in recovery cannot cancel for a free evade.
	pattern_fixture()
	units[0].phase = "收招"
	units[0].timer = 1
	units[2].phase = "收招"
	units[2].timer = 10
	hazards.append({"kind": "area", "p": units[0].p, "radius": 40.0, "team": 1, "source": 2, "left": 0.1, "damage": 1.0})
	for tick in range(10): simulate(STEP)
	assert(units[0].hp == (MAX_HP - 1) and units[0].phase == "收招")
	print("EVASION PASSED: baseline dodge, no automatic counter priority, no false alarm, overlapping zones, action commitment")

func run_blast_tests() -> void:
	# Screenshot-like case: impact center inside the upper wall, body outside its corner.
	pattern_fixture()
	var center: Vector2 = walls[0].end - Vector2(10, 6)
	units[2].p = walls[0].end + Vector2(20, 30)
	assert(valid_position(units[2].p) and blocked(center, units[2].p))
	assert(area_overlaps_body(center, 40, units[2].p))
	var blast := {"kind": "area", "p": center, "radius": 40.0, "team": 0, "source": 0, "left": 0.1, "damage": 1.0}
	assert(danger_contains(blast, units[2].p, 0))
	hazards.append(blast)
	update_bullets(0.05)
	assert(units[2].hp == MAX_HP, "Warning does not deal damage")
	update_bullets(0.06)
	assert(units[2].hp == (MAX_HP - 1), "Wall-centered explosion must hit the overlapping body")
	update_bullets(0.1)
	assert(units[2].hp == (MAX_HP - 1), "Lingering explosion effect must not deal repeated damage")
	for offset in [63.0, 64.0, 64.1]:
		pattern_fixture()
		units[2].p = Vector2(100 + offset, 320)
		hazards.append({"kind": "area", "p": Vector2(100, 320), "radius": 40.0, "team": 0, "source": 0, "left": 0.0, "damage": 1.0})
		update_bullets(STEP)
		assert(units[2].hp == (MAX_HP - 1 if offset <= 64 else MAX_HP))
		assert(units[0].hp == MAX_HP, "No friendly fire")
	for defense in ["shield", "guard"]:
		pattern_fixture()
		units[2][defense] = 1.0
		hazards.append({"kind": "area", "p": units[2].p, "radius": 40.0, "team": 0, "source": 0, "left": 0.0, "damage": 1.0})
		update_bullets(STEP)
		assert(units[2].hp == MAX_HP, "Shield and guard still absorb a one-point hit")
	assert(beam_end(Vector2(180, 160), 0).x <= walls[0].position.x + 1)
	print("BLAST PASSED: wall-centered repro, body edge/tangent/outside, warning vs impact, single damage tick, AI geometry, friendly fire, defense, beam cover")

func run_arena_tests() -> void:
	assert(blast_progress(BLAST_CAST + BLAST_FLIGHT) == 0)
	assert(blast_progress(0) == 1)
	assert(is_equal_approx(blast_progress(BLAST_FLIGHT), BLAST_CAST / (BLAST_CAST + BLAST_FLIGHT)))
	# Locked landing point and one continuous clock spanning cast and flight.
	for dodge_target in [false, true]:
		pattern_fixture()
		begin_shot(units[0], 2, "抛射轰击")
		var locked: Vector2 = units[0].lock_point
		update_attack(units[0], BLAST_CAST - 0.01)
		assert(hazards.is_empty() and shots == 0)
		update_attack(units[0], 0.02)
		assert(hazards.size() == 1 and hazards[0].p == locked and hazards[0].radius == BLAST_RADIUS)
		if dodge_target: units[2].p = locked + Vector2(BLAST_RADIUS + RADIUS + 1, 0)
		update_bullets(BLAST_FLIGHT - 0.01)
		assert(units[2].hp == MAX_HP)
		update_bullets(0.02)
		assert(units[2].hp == (MAX_HP if dodge_target else MAX_HP - 18))
		assert(blasts.size() == 1 and blasts[0].radius == BLAST_RADIUS)
	# A configured PP may choose offense instead of baseline movement.
	pattern_fixture()
	begin_shot(units[2], 0, "蓄能贯穿")
	units[2].timer = 0.8
	loadouts[0] = Tactics.build([], [["焰返", "无", "无"]])
	var before: Vector2 = units[0].p
	simulate(STEP)
	assert(units[0].active_skill == "焰返" and units[0].p == before)
	# Empty PP still performs basic continuous walking, not tile hops.
	pattern_fixture()
	begin_shot(units[2], 0, "蓄能贯穿")
	units[2].timer = 0.8
	units[0].cooldown = 0.25
	before = units[0].p
	simulate(STEP)
	assert(units[0].intent == "规避预警" and units[0].p.distance_to(before) > 0 and units[0].p.distance_to(before) < 3)
	var rows: Array = []
	for opponent in range(Tactics.NAMES.size()):
		for side in [false, true]:
			team_presets = [7, opponent]
			setup_loadouts()
			blue_attacks = side
			reset_round()
			for tick in range(3602):
				if finished: break
				simulate(STEP)
				for u in units:
					assert(u.hp >= 0 and u.hp <= MAX_HP and u.hp == floorf(u.hp))
					if u.hp > 0: assert(valid_arena_position(u.p))
			assert(finished and shots > 0)
			rows.append({"blue": 7, "red": opponent, "blue_left": side, "winner": winner_team, "seconds": ROUND_TIME - clock, "skills": reaction_counts.duplicate()})
	var file := FileAccess.open("res://reports/arena-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	print("ARENA PASSED: continuous movement, locked single circle, continuous cast/flight ring, exact impact time/radius, PP before baseline, 18 matches")

func draw_move_path(u: Dictionary) -> void:
	if u.dodge <= 0 and u.action_left <= 0 and u.intent != "规避预警": return
	var destination: Vector2 = u.p + u.dodge_dir * DODGE_SPEED * u.dodge if u.dodge > 0 else u.action_goal
	if u.p.distance_to(destination) <= 10: return
	var points: Array = [u.p]
	if u.dodge <= 0 and u.intent != "规避预警":
		for point in u.path: points.append(point)
	points.append(destination)
	for i in range(1, points.size()): draw_dashed_line(ORIGIN + points[i - 1], ORIGIN + points[i], Color(MOVE_HINT, 0.7), 2, 7)
	var end: Vector2 = ORIGIN + destination
	draw_arc(end, 10, 0, TAU, 28, MOVE_HINT, 2)
	draw_circle(end, 3, MOVE_HINT)
	var direction: Vector2 = (destination - u.p).normalized()
	var arrow := end - direction * 16
	draw_line(arrow, arrow - direction.rotated(0.55) * 9, MOVE_HINT, 2)
	draw_line(arrow, arrow - direction.rotated(-0.55) * 9, MOVE_HINT, 2)

func run_tempo_tests() -> void:
	pattern_fixture()
	units[0].intent = "基础接敌"
	assert(is_equal_approx(unit_move_speed(units[0]), ENGAGE_SPEED))
	units[0].intent = "规避预警"
	assert(is_equal_approx(unit_move_speed(units[0]), MOVE_SPEED))
	assert(ENGAGE_SPEED > MOVE_SPEED and MOVE_SPEED > COMBAT_STEP_SPEED)
	pattern_fixture()
	units[2].phase = "收招"
	units[2].timer = 100.0
	units[0].cooldown = 0.55
	var origin: Vector2 = units[0].p
	for tick in range(15): simulate(STEP)
	assert(units[0].intent == "战斗走位")
	assert(units[0].p.distance_to(origin) > 5 and units[0].p.distance_to(origin) < 16)
	assert(not blocked(units[0].p, units[2].p))
	assert(absf(angle_difference(units[0].angle, (units[2].p - units[0].p).angle())) < 0.1)
	units[0].cooldown = 0.0
	simulate(STEP)
	assert(units[0].active_skill == "点射" and units[0].phase == "瞄准", "Ready weapon must not wait for footwork to finish")
	# Player movement AP can also take over the low-priority baseline step immediately.
	pattern_fixture()
	units[0].cooldown = 0.5
	assert(prepare_combat_step(units[0], 2))
	units[2].phase = "收招"
	units[2].timer = 100.0
	loadouts[0] = Tactics.build([["后撤", "无", "无"]], [])
	simulate(STEP)
	assert(units[0].intent == "后撤" and units[0].rule_slot == 0)
	# Near cover, every accepted step remains legal along the entire segment.
	for position in [Vector2(210, 270), Vector2(290, 320), Vector2(100, 300)]:
		pattern_fixture()
		units[0].p = position
		units[0].cooldown = 0.55
		if prepare_combat_step(units[0], 2):
			for tick in range(30):
				move_unit(units[0], units[0].action_goal, STEP)
				assert(valid_arena_position(units[0].p))
	# Charged laser retains commitment; ordinary shotgun releases substantially sooner.
	pattern_fixture()
	begin_shot(units[0], 2, "蓄能贯穿")
	update_attack(units[0], 0.5)
	assert(units[0].phase == "吟唱" and shots == 0)
	pattern_fixture()
	begin_shot(units[0], 2, "霰弹")
	update_attack(units[0], 0.24)
	assert(shots == 0)
	update_attack(units[0], 0.02)
	assert(bullets.size() == 5 and units[0].phase == "收招")
	update_attack(units[0], 0.46)
	assert(units[0].phase == "移动" and is_equal_approx(units[0].cooldown, 1.35))
	print("TEMPO PASSED: continuous aimed footwork, ready attack and player AP preempt, cover safety, fast shotgun, committed laser")

func run_defense_tests() -> void:
	# A plain shot catches full-speed lateral running at common combat ranges.
	for distance in [150.0, 200.0, 260.0]:
		for move_speed in [COMBAT_STEP_SPEED, ENGAGE_SPEED]:
			pattern_fixture()
			units[2].p = Vector2(100 + distance, 320)
			begin_shot(units[0], 2, "点射")
			update_attack(units[0], STEP)
			assert(not prepare_tactical_escape(units[2], [0]))
			for tick in range(24):
				units[2].p.y += move_speed * STEP
				update_bullets(STEP)
			assert(units[2].hp == MAX_HP - 7, "Full-speed ordinary movement must be hit by a basic shot")
	# Dodge remains useful against slower heavy projectiles; it is not an invulnerability skill.
	pattern_fixture()
	begin_shot(units[0], 2, "落岩")
	update_attack(units[0], 0.36)
	loadouts[2] = Tactics.build([], [["侧闪", "无", "无"]])
	assert(try_reaction(units[2], [0]))
	for tick in range(36):
		if units[2].dodge > 0:
			units[2].p += units[2].dodge_dir * DODGE_SPEED * STEP
			units[2].dodge -= STEP
		update_bullets(STEP)
	assert(units[2].hp == MAX_HP)
	bullets.append({"p": units[2].p - Vector2(120, 0), "v": Vector2(ROCK_SPEED, 0), "life": 1.0, "team": 0, "source": 0, "damage": 20.0})
	assert(not try_reaction(units[2], [0]), "Cooldown prevents another dodge")
	pattern_fixture()
	loadouts[2] = Tactics.build([], [["侧闪", "无", "无"]])
	begin_shot(units[0], 2, "点射")
	assert(not try_reaction(units[2], [0]))
	pattern_fixture()
	begin_shot(units[0], 2, "蓄能贯穿")
	units[0].timer = 0.8
	assert(prepare_tactical_escape(units[2], [0]))
	print("DEFENSE PASSED: basic shots hit slow and full-speed motion at three ranges; dodge avoids rock with cooldown; aim alone does not trigger; long cast allows walking")

func run_expansion_tests() -> void:
	run_defense_tests()
	for skill in Tactics.MAGIC:
		pattern_fixture()
		begin_shot(units[0], 2, skill)
		var total := 0.0
		for tick in range(150):
			update_attack(units[0], STEP)
			for b in bullets: total += b.damage
			bullets.clear()
			for h in hazards: total += h.damage
			hazards.clear()
		var count: int = 5 if skill == "霰弹" else Tactics.MAGIC[skill].hits
		assert(is_equal_approx(total, Tactics.MAGIC[skill].damage * count), "Wrong emitted damage: " + skill)
	# New line/area skills share telegraph and collision dimensions; fire bypasses guard.
	for skill in ["烈焰爆破", "裂地冲击"]:
		pattern_fixture()
		units[2].guard = 2.0
		begin_shot(units[0], 2, skill)
		update_attack(units[0], Tactics.MAGIC[skill].cast + 0.01)
		assert(hazards.size() == 1 and hazards[0].radius == pattern_radius(skill))
		update_bullets(BLAST_FLIGHT + 0.01)
		assert(units[2].hp == 32)
	# Forest support heals and shields the wounded ally, respects scope and cooldown.
	pattern_fixture()
	units[1].hp = 20
	units[1].p = Vector2(150, 320)
	units[1].hurt_recent = 0.5
	units[2].phase = "收招"
	units[2].timer = 10
	loadouts[0] = Tactics.build([], [["灵木护佑", "优先低血量", "无"]])
	simulate(STEP)
	assert(units[1].hp == 28 and units[1].shield == 8)
	assert(units[0].skill_cds["灵木护佑"] > 8)
	# Guard reduces ordinary damage by 6; a shield absorbs true damage as well.
	for true_damage in [false, true]:
		pattern_fixture()
		units[2].guard = 1
		units[2].shield = 8
		bullets.append({"p": units[2].p - Vector2(5, 0), "v": Vector2(100, 0), "life": 1.0, "team": 0, "source": 0, "damage": 18.0, "true_damage": true_damage})
		update_bullets(STEP)
		assert(units[2].hp == (40 if true_damage else 46))
	# A basic attack cannot repeat faster than recovery + weapon pause.
	pattern_fixture()
	begin_shot(units[0], 2, "点射")
	update_attack(units[0], STEP)
	assert(units[0].timer == 0.45)
	update_attack(units[0], 0.46)
	assert(is_equal_approx(units[0].cooldown, 1.35))
	print("EXPANSION PASSED: all 13 attacks emitted intended damage, new patterns/guard, heal+shield, true damage, basic cadence, 50HP")
