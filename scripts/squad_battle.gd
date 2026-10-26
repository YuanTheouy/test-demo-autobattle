extends Node2D
const Sim = preload("res://scripts/squad_simulation.gd")
const BLUE := Color("65c5ff")
const RED := Color("ff858b")
const GOLD := Color("eac98d")
const GREEN := Color("83dcc0")
const MUTED := Color("8496ac")
var sim = Sim.new()
var settings := Sim.defaults()
var live_sim = sim
var history: Array = []
var replaying := false
var member_index := 0
var posture_picker: OptionButton
var exception_picker: OptionButton
var timeline: HSlider
var event_picker: OptionButton
var event_ids: Array = []
var event_count := -1
var audit_text: RichTextLabel
var font: SystemFont
var running := false
var step_ticks := 0
var speed := 1.0
var accumulator := 0.0
var selected := 0
var labels: Dictionary = {}
var editor: PanelContainer
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
	if "--squad-tactics-demo" in OS.get_cmdline_user_args():
		selected = 1; member_index = 0; focus_unit = 2; editor.show_page(1)
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
	label_at("", "4个小队 · 8名角色 · 战术由流程组合", Vector2(31, 59), 16, MUTED)
	label_at("clock", "", Vector2(33, 102), 18)
	label_at("state", "", Vector2(34, 628), 14, GOLD)
	var log_label := label_at("log", "", Vector2(34, 665), 14, MUTED)
	log_label.size = Vector2(860, 100); log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	play_button = button_at("开始 [空格]", Vector2(33, 780), toggle_play)
	button_at("播放1秒 [N]", Vector2(170, 780), step_second)
	button_at("同局重试 [R]", Vector2(310, 780), restart)
	var speed_button := button_at("速度 ×1", Vector2(450, 780), func():
		speed = 0.5 if speed == 1.0 else (2.0 if speed == 0.5 else 1.0)
		labels.speed_button.text = "速度 ×%s" % speed)
	labels.speed_button = speed_button
	button_at("恢复示范", Vector2(570, 780), func(): settings = Sim.defaults(); restart(); sync_editor())
	button_at("旧原型", Vector2(705, 780), func(): get_tree().change_scene_to_file("res://puzzle_arena.tscn"))
	editor = preload("res://scripts/squad_editor.gd").new(); add_child(editor); editor.setup(self)

func active_uid() -> int:
	return selected * 2 + member_index

func edit_condition(_lane: String, slot: int, col: int, value: String) -> void:
	if replaying: return
	settings.pp[active_uid()][slot][col] = value
	restart()

func move_rule(_lane: String, slot: int) -> void:
	if replaying or slot == 0: return
	var rules: Array = settings.pp[active_uid()]
	var previous: Array = rules[slot - 1]
	rules[slot - 1] = rules[slot]; rules[slot] = previous
	restart(); sync_editor()

var templates: Dictionary = {}
func save_template(path := "user://squad-templates.json") -> void:
	var role: String = sim.units[active_uid()].role
	if FileAccess.file_exists(path):
		var existing = JSON.parse_string(FileAccess.get_file_as_string(path))
		if existing is Dictionary: templates = existing
	templates[role] = {"version": 3, "program": settings.programs[active_uid()].duplicate(true), "pp": settings.pp[active_uid()].duplicate(true)}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(templates))
	if editor.note != null: editor.note.text = "已保存%s的IF/ELSE程序与反应配置。" % role

func load_template(path := "user://squad-templates.json") -> void:
	if replaying: return
	var role: String = sim.units[active_uid()].role
	if FileAccess.file_exists(path):
		var value = JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary: templates = value
	if not templates.has(role):
		if editor.note != null: editor.note.text = "尚未保存%s模板。" % role
		return
	var saved: Dictionary = templates[role]
	if saved.get("version", 0) != 3 or not saved.get("program") is Dictionary or not saved.get("pp") is Array or saved.pp.size() != 2:
		editor.note.text = "旧模板与单条件IF不兼容，未修改当前程序。"; return
	if Sim.clean_program(saved.program, role) != saved.program:
		editor.note.text = "模板流程、深度或技能不兼容，未修改程序。"; return
	for rule in saved.pp:
		if not rule is Array or rule.size() != 2 or rule[0] not in Sim.pp_options(role): return
		for column in [1]:
			if rule[column] not in Sim.conditions_for(rule[0]): return
	settings.programs[active_uid()] = saved.program.duplicate(true)
	settings.pp[active_uid()] = saved.pp.duplicate(true)
	restart(); sync_editor()

func sync_editor() -> void:
	if editor != null: editor.rebuild()

func restart() -> void:
	sim = Sim.new(); sim.reset(settings); live_sim = sim
	history = [sim.snapshot()]; replaying = false; event_count = -1; selected_event = -1
	running = false; step_ticks = 0; accumulator = 0
	sync_editor()
	refresh_labels(); queue_redraw()

func toggle_play() -> void:
	if replaying: return_live()
	if sim.finished: restart()
	running = not running
	step_ticks = 0
	refresh_labels()

func step_second() -> void:
	if replaying: return_live()
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
		for i in range(8):
			if sim.pos(i).distance_to(event.position) < 27:
				focus_unit = i
				if i < 4: selected = int(i / 2); member_index = i % 2; sync_editor()
				else: open_audit()
				refresh_labels(); break

func _process(delta: float) -> void:
	if not replaying and (running or step_ticks > 0) and not sim.finished:
		accumulator += minf(delta, 0.2) * speed
		while accumulator >= Sim.DT and not sim.finished and (running or step_ticks > 0):
			accumulator -= Sim.DT; sim.tick(); history.append(sim.snapshot())
			if not running:
				step_ticks -= 1
				if step_ticks == 0: accumulator = 0
	if sim.finished: running = false; step_ticks = 0
	refresh_timer += delta
	if refresh_timer > 0.1: refresh_labels(); refresh_timer = 0
	queue_redraw()

var selected_event := -1
func browse(index: int, preserve_event := false) -> void:
	if history.is_empty(): return
	if not preserve_event: selected_event = -1
	running = false; step_ticks = 0; accumulator = 0; replaying = true
	index = clampi(index, 0, history.size() - 1)
	sim = Sim.new(); sim.load_view(history[index], live_sim.events)
	sync_editor(); refresh_labels(); queue_redraw()

func return_live() -> void:
	sim = live_sim; replaying = false; running = false; step_ticks = 0; selected_event = -1
	sync_editor(); refresh_labels(); queue_redraw()

func select_event(index: int) -> void:
	if index < 0 or index >= event_ids.size(): return
	selected_event = event_ids[index]
	var event: Dictionary = live_sim.events[selected_event - 1]
	browse(roundi(event.time / Sim.DT), true)
	if event.actor >= 0:
		focus_unit = event.actor
		if event.actor < 4:
			selected = int(event.actor / 2); member_index = event.actor % 2; sync_editor()
	refresh_labels()

func gather_causes(id: int, visited: Array, rows: Array, depth := 0) -> void:
	if id <= 0 or id > sim.events.size() or depth > 8 or visited.has(id): return
	visited.append(id)
	var event: Dictionary = sim.events[id - 1]
	for parent in event.get("causes", [event.parent]): gather_causes(parent, visited, rows, depth + 1)
	rows.append(event)

func causal_lines(id: int) -> Array[String]:
	var rows: Array = []; var lines: Array[String] = []
	gather_causes(id, [], rows)
	rows.sort_custom(func(a, b): return a.id < b.id if is_equal_approx(a.time, b.time) else a.time < b.time)
	for event in rows: lines.append("%.2fs  %s" % [event.time, event.text])
	return lines

func open_audit() -> void:
	running = false; step_ticks = 0
	editor.show_page(3); refresh_labels()

func audit_description() -> String:
	var uid := focus_unit if focus_unit >= 4 else active_uid()
	var u: Dictionary = sim.units[uid]
	var text := "%.2fs  %s  |  %s\n\n" % [sim.clock, sim.title(uid), "历史复盘（只读）" if replaying else "现场（已暂停）"]
	text += "主动分支（%.2fs）：\n" % u.get("check_time", 0.0)
	for check in u.checks:
		if check.kind == "IF":
			text += "%s\nIF [%s] → %s\n" % [Sim.path_label(check.path), check.condition, check.branch]
		elif check.kind == "WAIT":
			text += "WAIT [%s] → %s；%s\n" % [check.condition, check.branch, check.reason]
		else: text += "%s → %s：%s\n" % [Sim.path_label(check.path), check.skill, check.reason]
	text += "\n反应IF（%.2fs）：\n" % u.get("pp_check_time", 0.0)
	var pp_rows: Array = u.pp_checks
	if selected_event > 0 and selected_event <= sim.events.size():
		var event: Dictionary = sim.events[selected_event - 1]
		if event.kind == "PP":
			for decision in live_sim.decisions:
				if decision.kind == "反应" and decision.actor == uid and decision.event == event.parent: pp_rows = decision.checks; break
	for check in pp_rows: text += "PP%d %s / %s → %s\n" % [check.slot + 1, check.skill, check.stage, check.reason]
	text += "\n当前：%s\n%s\n" % [u.mode, u.why]
	if selected_event > 0: text += "\n真实来源链：\n" + "\n".join(causal_lines(selected_event))
	return text

func refresh_labels() -> void:
	if sim.units.is_empty(): return
	labels.clock.text = "时间 %04.2fs / 55s    状态协作 %d 次    %s" % [sim.clock, sim.combo_count, "历史复盘" if replaying else (sim.result if sim.finished else ("运行中" if running or step_ticks > 0 else "已暂停"))]
	play_button.text = "返回现场播放" if replaying else ("暂停 [空格]" if running else ("再看一次" if sim.finished else "开始 [空格]"))
	labels.state.text = "A：%s | B：%s" % [sim.squads[0].reason, sim.squads[1].reason]
	if timeline != null:
		timeline.set_block_signals(true)
		timeline.max_value = maxi(1, history.size() - 1); timeline.set_value_no_signal(sim.steps)
		timeline.set_block_signals(false)
	if event_picker != null and event_count != live_sim.events.size():
		event_count = live_sim.events.size(); event_picker.clear(); event_ids.clear()
		for event in live_sim.events:
			if event.kind in ["AP", "连携", "PP", "等待", "等待结束", "阵亡", "任务", "结束"]:
				event_ids.append(event.id); event_picker.add_item("%05.2fs %s" % [event.time, event.text])
	if event_picker != null and selected_event > 0 and event_ids.has(selected_event): event_picker.select(event_ids.find(selected_event))
	var significant: Array = sim.events.filter(func(e): return e.kind in ["连携", "牵制", "PP", "阵亡", "结束", "等待", "等待结束"])
	var lines: Array[String] = []
	for i in range(maxi(0, significant.size() - 3), significant.size()): lines.append("%05.2f  %s" % [significant[i].time, significant[i].text])
	labels.log.text = "\n".join(lines) if not lines.is_empty() else "选择右侧页面编辑任务、主动流程或反应规则。\n战后进入复盘，沿真实分支查看原因。"
	if editor != null: editor.refresh_status()

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
		text_at(Vector2(34, 151), sim.title(focus_unit) + " · " + sim.units[focus_unit].mode, 13, GOLD)

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
	for page in range(4):
		selected = 1; member_index = 0; focus_unit = 2
		if page == 3:
			while not sim.finished: sim.tick(); history.append(sim.snapshot())
		editor.show_page(page); refresh_labels(); queue_redraw()
		if page == 3:
			for index in event_ids.size():
				if live_sim.events[event_ids[index] - 1].kind == "连携": select_event(index); break
		await get_tree().process_frame; await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://reports/squad-page-%d.png" % page)
	settings = Sim.defaults()
	settings.programs[2]["else"] = Sim.branch("友军正在施法", Sim.wait_action(), Sim.action("突刺"))
	restart(); editor.show_page(1)
	await get_tree().process_frame; await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://reports/squad-nested-if.png")
	get_tree().quit()

func validate_ui() -> void:
	await preload("res://scripts/squad_ui_validation.gd").run(self)
	get_tree().quit()
