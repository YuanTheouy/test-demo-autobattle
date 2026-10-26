extends Node2D
const Sim = preload("res://scripts/squad_simulation.gd")
const BLUE := Color("65c5ff")
const RED := Color("ff858b")
const GOLD := Color("eac98d")
const GREEN := Color("83dcc0")
const MUTED := Color("8496ac")
var sim = Sim.new()
var settings := Sim.defaults()
var font: SystemFont
var running := false
var step_ticks := 0
var speed := 1.0
var accumulator := 0.0
var selected := 0
var labels: Dictionary = {}
var rules_widgets: Array = []
var squad_buttons: Array = []
var task_picker: OptionButton
var play_button: Button
var refresh_timer := 0.0
var focus_unit := -1

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Arial"])
	DisplayServer.window_set_title("AutoBattle — 小队协同 / 同一战场")
	build_ui()
	restart()
	if "--squad-preview" in OS.get_cmdline_user_args():
		set_process(false)
		capture.call_deferred()
	elif "--squad-ui-test" in OS.get_cmdline_user_args():
		set_process(false)
		validate_ui.call_deferred()

func label_at(key: String, text: String, p: Vector2, size := 16, color := Color("d8e2ef")) -> Label:
	var l := Label.new()
	l.position = p; l.text = text
	l.add_theme_font_override("font", font); l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	add_child(l)
	if not key.is_empty(): labels[key] = l
	return l

func button_at(text: String, p: Vector2, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text; b.position = p; b.custom_minimum_size = Vector2(100, 36)
	b.add_theme_font_override("font", font); b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(callback); add_child(b)
	return b

func picker_at(items: Array, p: Vector2, width: float) -> OptionButton:
	var o := OptionButton.new()
	o.position = p; o.size = Vector2(width, 34)
	o.add_theme_font_override("font", font); o.add_theme_font_size_override("font_size", 15)
	for item in items: o.add_item(item)
	add_child(o)
	return o

func build_ui() -> void:
	label_at("", "AUTOBATTLE / 小队协同", Vector2(30, 18), 27, GOLD)
	label_at("", "一个战场 · 小队移动 / 队员战斗 · 固定阵形 · 无逐格移动", Vector2(31, 59), 16, MUTED)
	label_at("clock", "", Vector2(33, 102), 18)
	label_at("", "蓝方：A盾法队 / B突袭队      红方：C守备队 / D雷法队", Vector2(34, 625), 15)
	label_at("state", "", Vector2(34, 653), 15, GOLD)
	label_at("log", "", Vector2(34, 685), 14, Color("b4c5d9"))
	play_button = button_at("开始 [空格]", Vector2(33, 780), toggle_play)
	button_at("播放1秒 [N]", Vector2(170, 780), step_second)
	button_at("同局重试 [R]", Vector2(310, 780), restart)
	var speed_button := button_at("速度 ×1", Vector2(450, 780), func():
		speed = 0.5 if speed == 1.0 else (2.0 if speed == 0.5 else 1.0)
		labels.speed_button.text = "速度 ×%s" % speed)
	labels.speed_button = speed_button
	button_at("恢复示范", Vector2(570, 780), func(): settings = Sim.defaults(); sync_editor(); restart())
	button_at("旧原型", Vector2(705, 780), func(): get_tree().change_scene_to_file("res://puzzle_arena.tscn"))
	label_at("", "小队指令与队员战术", Vector2(958, 24), 24, GOLD)
	label_at("", "修改后从同一局面重试；不在战斗中偷偷改程序。", Vector2(958, 61), 14, MUTED)
	for i in range(2):
		var index := i
		squad_buttons.append(button_at("A · 盾兵＋法师" if i == 0 else "B · 刺客＋牧师", Vector2(958 + i * 300, 100), func(): selected = index; sync_editor()))
	label_at("", "小队任务", Vector2(960, 151), 15, GREEN)
	task_picker = picker_at(Sim.TASKS, Vector2(1062, 142), 260)
	task_picker.item_selected.connect(func(i): settings.tasks[selected] = Sim.TASKS[i]; restart())
	label_at("task", "", Vector2(960, 187), 14)
	for member in range(2):
		var y := 244.0 + member * 208
		label_at("member%d" % member, "", Vector2(960, y - 22), 18, BLUE)
		label_at("member_state%d" % member, "", Vector2(960, y + 4), 13, MUTED)
		for slot in range(2):
			label_at("", "AP%d" % (slot + 1), Vector2(960, y + 37 + slot * 40), 15, GOLD)
			var skill := picker_at([], Vector2(1015, y + 30 + slot * 40), 190)
			var condition := picker_at([], Vector2(1215, y + 30 + slot * 40), 355)
			var mi := member; var si := slot
			skill.item_selected.connect(func(i):
				var uid := selected * 2 + mi
				var value: String = skill.get_item_text(i)
				settings.rules[uid][si][0] = value
				if not Sim.conditions_for(value).has(settings.rules[uid][si][1]): settings.rules[uid][si][1] = "无"
				sync_editor(); restart())
			condition.item_selected.connect(func(i): settings.rules[selected * 2 + mi][si][1] = condition.get_item_text(i); restart())
			rules_widgets.append({"member": member, "slot": slot, "skill": skill, "condition": condition})
		label_at("", "PP", Vector2(960, y + 122), 15, GREEN)
		var pp := picker_at([], Vector2(1015, y + 114), 190)
		var mi := member
		pp.item_selected.connect(func(i): settings.pp[selected * 2 + mi] = pp.get_item_text(i); restart())
		rules_widgets.append({"member": member, "slot": -1, "skill": pp})
		label_at("pp%d" % member, "", Vector2(1215, y + 121), 13, MUTED)
		var why := label_at("why%d" % member, "", Vector2(960, y + 155), 13, GREEN)
		why.size.x = 635
		why.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label_at("", "规则：AP从上到下选可用技能；PP由受击事件触发。", Vector2(960, 650), 14)
	label_at("", "攻击只选射程内目标，不驱使队员离队。\n同距离按固定编号；治疗优先最低血量比例。\n远程均为追踪法术/抛射：发射后命中，不靠走路闪避。", Vector2(960, 678), 14, MUTED)
	label_at("detail", "", Vector2(960, 755), 13, GREEN)
	sync_editor()

func sync_editor() -> void:
	task_picker.select(Sim.TASKS.find(settings.tasks[selected]))
	var base := selected * 2
	for i in range(2): squad_buttons[i].modulate = GOLD if i == selected else Color.WHITE
	for w in rules_widgets:
		var uid: int = base + w.member
		var role: String = ["盾兵", "法师", "刺客", "牧师"][uid]
		var options: Array = Sim.options(role) if w.slot >= 0 else (["留空", "援护"] if uid == 0 else (["留空", "回春"] if uid == 3 else ["留空"]))
		w.skill.clear()
		for item in options: w.skill.add_item(item)
		var value: String = settings.rules[uid][w.slot][0] if w.slot >= 0 else settings.pp[uid]
		w.skill.select(options.find(value))
		if w.slot >= 0:
			var conditions: Array = Sim.conditions_for(value)
			w.condition.clear()
			for item in conditions: w.condition.add_item(item)
			w.condition.select(conditions.find(settings.rules[uid][w.slot][1]))
	for member in range(2):
		var uid := base + member
		labels["member%d" % member].text = ["盾兵 · 牵制 / 援护", "法师 · 火球", "刺客 · 协同突袭 / 突刺", "牧师 · 治疗 / 回春"][uid]
		labels["pp%d" % member].text = "队友受击前：26盾 / CD6秒" if uid == 0 else ("队友受击后：恢复8HP / CD6秒" if uid == 3 else "此角色暂无反应技能")
	labels.detail.text = "牵制6秒＋自身24盾；协同突袭命中牵制目标：14→32伤害。\n火球20 / 突刺14 / 光弹10 / 治疗25；完整数值见README。"

func restart() -> void:
	sim.reset(settings)
	running = false; step_ticks = 0; accumulator = 0
	refresh_labels(); queue_redraw()

func toggle_play() -> void:
	if sim.finished: restart()
	running = not running
	step_ticks = 0
	refresh_labels()

func step_second() -> void:
	running = false
	step_ticks = 20; accumulator = 0
	refresh_labels(); queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_SPACE: toggle_play(); get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R: restart()
	elif event.keycode == KEY_N: step_second()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in range(4):
			if sim.pos(i).distance_to(event.position) < 27:
				selected = int(i / 2); focus_unit = i; sync_editor(); refresh_labels(); break

func _process(delta: float) -> void:
	if (running or step_ticks > 0) and not sim.finished:
		accumulator += minf(delta, 0.2) * speed
		while accumulator >= Sim.DT and not sim.finished and (running or step_ticks > 0):
			accumulator -= Sim.DT; sim.tick()
			if not running:
				step_ticks -= 1
				if step_ticks == 0: accumulator = 0
	if sim.finished: running = false; step_ticks = 0
	refresh_timer += delta
	if refresh_timer > 0.1: refresh_labels(); refresh_timer = 0
	queue_redraw()

func refresh_labels() -> void:
	if sim.units.is_empty(): return
	labels.clock.text = "时间 %04.1fs / 55s     连携 %d 次     %s" % [sim.clock, sim.combo_count, sim.result if sim.finished else ("运行中" if running or step_ticks > 0 else "已暂停")]
	play_button.text = "暂停 [空格]" if running else ("再看一次" if sim.finished else "开始 [空格]")
	labels.state.text = "A：%s    |    B：%s" % [sim.squads[0].reason, sim.squads[1].reason]
	labels.task.text = sim.squads[selected].reason
	for member in range(2):
		var u: Dictionary = sim.units[selected * 2 + member]
		labels["member_state%d" % member].text = "%s  HP %.0f/%.0f  盾%.0f  %s" % [u.mode, u.hp, u.max_hp, u.shield, u.skill if u.mode == "施法" or u.mode == "收招" else ""]
		labels["why%d" % member].text = u.why
		labels["why%d" % member].tooltip_text = u.why
	for w in rules_widgets:
		var u: Dictionary = sim.units[selected * 2 + w.member]
		w.skill.modulate = GOLD if w.slot >= 0 and u.slot == w.slot and u.hp > 0 else (GREEN if w.slot == -1 and u.pp_until > sim.clock else Color.WHITE)
		if w.slot >= 0: w.condition.tooltip_text = u.why
	var significant: Array = sim.events.filter(func(e): return e.kind in ["连携", "牵制", "PP", "阵亡", "结束", "治疗", "任务"])
	var lines: Array[String] = []
	for i in range(maxi(0, significant.size() - 4), significant.size()): lines.append("%04.1f  %s" % [significant[i].time, significant[i].text])
	labels.log.text = "\n".join(lines) if not lines.is_empty() else "观察：A队先接战，B队绕行后利用牵制。可把B队改为支援A队比较。"

func text_at(p: Vector2, text: String, size := 14, color := Color.WHITE) -> void:
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func dashed(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 1: return
	var direction := (b - a) / length
	for i in range(int(length / 14) + 1): draw_line(a + direction * i * 14, a + direction * minf(i * 14 + 7, length), color, 2, true)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1640, 830), Color("0b1420"))
	draw_style_box(panel_style(Color("111f2d")), Rect2(20, 135, 895, 475))
	draw_style_box(panel_style(Color("132130")), Rect2(938, 89, 680, 548))
	if sim.units.is_empty(): return
	# Only ground markings, not a movement grid.
	draw_line(Vector2(62, 390), Vector2(875, 390), Color("213444"), 1)
	text_at(Vector2(70, 175), "我方部署", 13, MUTED)
	text_at(Vector2(730, 175), "敌方阵地", 13, MUTED)
	for r in Sim.WALLS:
		draw_rect(r, Color("3a4858")); draw_rect(r, Color("627487"), false, 2)
	text_at(Vector2(365, 315), "正面通道", 13, MUTED)
	text_at(Vector2(380, 596), "侧路通道", 13, MUTED)
	for s in sim.squads:
		if not sim.alive_squad(s.id): continue
		var color := BLUE if s.team == 0 else RED
		draw_arc(s.pos, 54, 0, TAU, 48, Color(color, 0.18), 1.5, true)
		if s.id < 2:
			var last: Vector2 = s.pos
			for mark in s.route:
				dashed(last, mark, Color(GREEN, 0.4 if selected == s.id else 0.15)); last = mark
			if not s.route.is_empty(): draw_arc(last, 8, 0, TAU, 24, GREEN, 1.5)
		text_at(s.pos + Vector2(-48, 61), s.name, 14, color)
	for u in sim.units:
		if u.hp <= 0:
			var p: Vector2 = sim.pos(u.id)
			draw_line(p - Vector2(8, 8), p + Vector2(8, 8), Color("647080"), 2)
			draw_line(p + Vector2(-8, 8), p + Vector2(8, -8), Color("647080"), 2)
			continue
		var p: Vector2 = sim.pos(u.id)
		var color := BLUE if u.team == 0 else RED
		if u.mode == "施法" and u.target >= 0:
			var t: Vector2 = sim.pos(u.target)
			dashed(p, t, Color(color, 0.3))
			var progress: float = clampf((sim.clock - u.start) / maxf(0.05, u.release - u.start), 0, 1)
			draw_arc(t, 25, -PI / 2, -PI / 2 + TAU * maxf(0.001, progress), 40, Color(color, 0.7), 2, true)
		draw_ellipse_shadow(p)
		draw_circle(p, 20, color)
		draw_circle(p + Vector2(-5, -6), 10, Color(1, 1, 1, 0.13))
		if u.shield > 0: draw_arc(p, 25, 0, TAU, 40, GREEN, 3, true)
		if u.taunt_until > sim.clock:
			text_at(p + Vector2(-13, -39), "牵制", 12, GOLD)
			if u.taunt_source >= 0: dashed(p, sim.pos(u.taunt_source), Color(GOLD, 0.17))
		text_at(p + Vector2(-8, 5), {"盾兵":"盾", "法师":"火", "刺客":"刺", "牧师":"愈", "卫兵":"卫", "弓手":"弓", "雷法":"雷"}[u.role], 16, Color("102232"))
		draw_rect(Rect2(p + Vector2(-22, -30), Vector2(44, 4)), Color("283644"))
		draw_rect(Rect2(p + Vector2(-22, -30), Vector2(44 * u.hp / u.max_hp, 4)), color)
		text_at(p + Vector2(-16, 37), "%.0f" % u.hp, 12, Color("d8e4ef"))
	for e in sim.effects:
		var progress: float = clampf((sim.clock - e.start) / maxf(0.01, e.end - e.start), 0, 1)
		var color := BLUE if e.team == 0 else RED
		if e.kind == "projectile":
			var at: Vector2 = e.a.lerp(sim.pos(e.target), progress) + Vector2(0, -sin(progress * PI) * 42)
			draw_circle(at, 7 if e.skill != "治疗" else 5, GREEN if e.skill == "治疗" else color)
			draw_circle(at, 3, Color.WHITE)
		elif e.kind == "hit":
			draw_arc(e.b, 8 + progress * 27, 0, TAU, 32, Color(color, 1 - progress), 3, true)
			text_at(e.b + Vector2(-14, -43 - progress * 20), "%+.0f" % e.delta if e.delta != 0 else ("牵制" if e.skill == "牵制" else "护盾"), 17, GREEN if e.delta > 0 else GOLD)
		else: draw_line(e.a, e.b, Color(GREEN, 1 - progress), 3, true)
	# Selected member explanations stay on the battlefield rather than an opaque AI label.
	if focus_unit >= 0:
		text_at(Vector2(34, 151), sim.title(focus_unit) + "：" + sim.units[focus_unit].why, 13, GOLD)

func draw_ellipse_shadow(p: Vector2) -> void:
	draw_set_transform(p + Vector2(0, 13), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 24, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO)

func panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color; style.corner_radius_top_left = 12; style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12; style.corner_radius_bottom_right = 12
	return style

func capture() -> void:
	for time in [0.0, 7.0, 15.0, 24.0]:
		while sim.clock < time and not sim.finished: sim.tick()
		refresh_labels(); queue_redraw()
		await get_tree().process_frame; await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://reports/squad-%02d.png" % int(time))
	get_tree().quit()

func validate_ui() -> void:
	assert(not running and sim.clock == 0)
	selected = 1; sync_editor()
	task_picker.select(2); task_picker.item_selected.emit(2)
	assert(settings.tasks[1] == "支援A队" and sim.config.tasks[1] == "支援A队")
	var first: Dictionary = rules_widgets[0]
	first.skill.select(0); first.skill.item_selected.emit(0)
	assert(settings.rules[2][0][0] == "留空" and sim.units[2].rules[0][0] == "留空")
	step_second()
	assert(sim.clock == 0, "step must not publish its future result")
	for frame in range(61): _process(1.0 / 60.0)
	assert(is_equal_approx(sim.clock, 1.0) and step_ticks == 0)
	restart(); assert(sim.clock == 0 and settings.rules[2][0][0] == "留空")
	settings = Sim.defaults(); sync_editor(); restart()
	var baseline := Sim.new()
	baseline.reset(settings)
	while not baseline.finished: baseline.tick()
	for rate in [0.5, 1.0, 2.0]:
		restart(); speed = rate; running = true
		for frame in range(12000):
			_process(1.0 / 60.0)
			if sim.finished: break
		assert(sim.summary() == baseline.summary(), "playback speed must not alter outcome")
	var report := FileAccess.open("res://reports/squad-ui-validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": true, "checks": ["real task picker", "real AP picker", "preserved configuration on retry", "one second playback before pause", "0.5/1/2 speed histories identical"], "default_result": sim.result, "time": sim.clock, "combos": sim.combo_count}, "\t"))
	print("SQUAD UI PASS: real task and rule controls, reset and stepping")
	get_tree().quit()
