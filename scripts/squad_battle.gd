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
var member_buttons: Array = []
var posture_picker: OptionButton
var exception_picker: OptionButton
var timeline: HSlider
var event_picker: OptionButton
var event_ids: Array = []
var event_count := -1
var audit_dialog: AcceptDialog
var audit_text: RichTextLabel
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
	label_at("", "主动战术 / 反应战术 · 有限等待 · 可拖动复盘", Vector2(31, 59), 16, MUTED)
	label_at("clock", "", Vector2(33, 102), 18)
	label_at("state", "", Vector2(34, 624), 14, GOLD)
	label_at("", "复盘时间轴", Vector2(34, 662), 14, MUTED)
	timeline = HSlider.new(); timeline.position = Vector2(145, 650); timeline.size = Vector2(470, 30)
	timeline.step = 1; timeline.max_value = 1
	timeline.value_changed.connect(func(value): browse(int(value)))
	add_child(timeline)
	button_at("返回现场", Vector2(645, 647), return_live)
	label_at("", "关键事件", Vector2(34, 700), 14, MUTED)
	event_picker = picker_at([], Vector2(125, 690), 770)
	event_picker.item_selected.connect(select_event)
	label_at("log", "", Vector2(34, 735), 14, Color("b4c5d9"))
	play_button = button_at("开始 [空格]", Vector2(33, 780), toggle_play)
	button_at("播放1秒 [N]", Vector2(170, 780), step_second)
	button_at("同局重试 [R]", Vector2(310, 780), restart)
	var speed_button := button_at("速度 ×1", Vector2(450, 780), func():
		speed = 0.5 if speed == 1.0 else (2.0 if speed == 0.5 else 1.0)
		labels.speed_button.text = "速度 ×%s" % speed)
	labels.speed_button = speed_button
	button_at("恢复示范", Vector2(570, 780), func(): settings = Sim.defaults(); sync_editor(); restart())
	button_at("旧原型", Vector2(705, 780), func(): get_tree().change_scene_to_file("res://puzzle_arena.tscn"))
	label_at("", "小队任务 / 角色战术", Vector2(958, 24), 24, GOLD)
	label_at("", "修改会重试；复盘只读，点击流程可查看跳过原因。", Vector2(958, 61), 14, MUTED)
	for i in range(2):
		var index := i
		squad_buttons.append(button_at("A · 盾兵＋法师" if i == 0 else "B · 刺客＋牧师", Vector2(958 + i * 300, 100), func(): selected = index; focus_unit = selected * 2 + member_index; sync_editor(); refresh_labels()))
	label_at("", "默认任务", Vector2(960, 151), 15, GREEN)
	task_picker = picker_at(Sim.TASKS, Vector2(1055, 142), 240)
	task_picker.item_selected.connect(func(i): settings.tasks[selected] = Sim.TASKS[i]; restart())
	posture_picker = picker_at(["贴近交战", "保持距离"], Vector2(1320, 142), 250)
	posture_picker.item_selected.connect(func(i): settings.postures[selected] = posture_picker.get_item_text(i); restart())
	label_at("", "例外规则", Vector2(960, 193), 15, GREEN)
	exception_picker = picker_at(["无", "小队HP≤35% → 撤回部署区"], Vector2(1055, 184), 515)
	exception_picker.item_selected.connect(func(i): settings.exceptions[selected] = exception_picker.get_item_text(i); restart())
	label_at("task", "", Vector2(960, 228), 14, MUTED)
	for m in range(2):
		var index := m
		member_buttons.append(button_at("", Vector2(960 + m * 300, 262), func(): member_index = index; focus_unit = selected * 2 + index; sync_editor(); refresh_labels()))
	label_at("member", "", Vector2(960, 313), 19, BLUE)
	label_at("member_state", "", Vector2(960, 341), 14, MUTED)
	label_at("", "主动战术 · 准备就绪时检查", Vector2(960, 376), 17, GOLD)
	label_at("", "技能                         条件一                         条件二（且）", Vector2(1012, 406), 13, MUTED)
	for lane in ["ap", "pp"]:
		var count := 3 if lane == "ap" else 2
		var top := 427.0 if lane == "ap" else 617.0
		for slot in range(count):
			var si := slot; var kind: String = lane
			label_at("", ("AP" if lane == "ap" else "PP") + str(slot + 1), Vector2(960, top + 7 + slot * 39), 14, GOLD if lane == "ap" else GREEN)
			var skill := picker_at([], Vector2(1010, top + slot * 39), 165)
			var c1 := picker_at([], Vector2(1183, top + slot * 39), 185)
			var c2 := picker_at([], Vector2(1375, top + slot * 39), 185)
			skill.item_selected.connect(func(i):
				var rules: Array = settings.rules[active_uid()] if kind == "ap" else settings.pp[active_uid()]
				var value: String = skill.get_item_text(i)
				rules[si][0] = value
				for col in [1, 2]:
					if not Sim.conditions_for(value).has(rules[si][col]): rules[si][col] = "无"
				sync_editor(); restart())
			c1.item_selected.connect(func(i): edit_condition(kind, si, 1, c1.get_item_text(i)))
			c2.item_selected.connect(func(i): edit_condition(kind, si, 2, c2.get_item_text(i)))
			var up := button_at("↑", Vector2(1568, top + slot * 39), func(): move_rule(kind, si))
			up.custom_minimum_size = Vector2(35, 32); up.size = Vector2(35, 32); up.disabled = slot == 0
			rules_widgets.append({"lane": lane, "slot": slot, "skill": skill, "condition": c1, "condition2": c2})
	label_at("pp_header", "", Vector2(960, 563), 17, GREEN)
	label_at("", "技能固有触发时机由引擎处理，无需再写一次条件。", Vector2(960, 589), 13, MUTED)
	var why := label_at("why", "", Vector2(960, 707), 13, GREEN)
	why.size.x = 635; why.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button_at("查看实际判定 / IF流程", Vector2(960, 748), open_audit)
	button_at("保存角色模板", Vector2(1230, 748), save_template)
	button_at("套用已存模板", Vector2(1405, 748), load_template)
	label_at("detail", "等待最多1秒；每人2PP，每8秒恢复1点；每次反应消耗1点。", Vector2(960, 799), 13, MUTED)
	audit_dialog = AcceptDialog.new(); audit_dialog.title = "战术判定 / IF流程（只读）"
	audit_dialog.size = Vector2i(820, 620); add_child(audit_dialog)
	audit_text = RichTextLabel.new(); audit_text.position = Vector2(20, 15); audit_text.size = Vector2(775, 535)
	audit_text.add_theme_font_override("normal_font", font); audit_text.add_theme_font_size_override("normal_font_size", 16)
	audit_dialog.add_child(audit_text)
	var edit_task := audit_dialog.add_button("编辑该友方小队任务", false, "edit_task")
	edit_task.pressed.connect(func():
		var uid := focus_unit if focus_unit >= 0 else active_uid()
		if uid < 4: selected = int(uid / 2); member_index = uid % 2; sync_editor()
		audit_dialog.hide())
	sync_editor()

func active_uid() -> int:
	return selected * 2 + member_index

func edit_condition(lane: String, slot: int, col: int, value: String) -> void:
	var rules: Array = settings.rules[active_uid()] if lane == "ap" else settings.pp[active_uid()]
	rules[slot][col] = value
	restart()

func move_rule(lane: String, slot: int) -> void:
	if slot == 0: return
	var rules: Array = settings.rules[active_uid()] if lane == "ap" else settings.pp[active_uid()]
	var previous: Array = rules[slot - 1]
	rules[slot - 1] = rules[slot]; rules[slot] = previous
	sync_editor(); restart()

var templates: Dictionary = {}
func save_template(path := "user://squad-templates.json") -> void:
	var role: String = ["盾兵", "法师", "刺客", "牧师"][active_uid()]
	if FileAccess.file_exists(path):
		var existing = JSON.parse_string(FileAccess.get_file_as_string(path))
		if existing is Dictionary: templates = existing
	templates[role] = {"rules": settings.rules[active_uid()].duplicate(true), "pp": settings.pp[active_uid()].duplicate(true)}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(templates))
	labels.detail.text = "已保存%s模板；同职业可套用，保存在本机。" % role

func load_template(path := "user://squad-templates.json") -> void:
	var role: String = ["盾兵", "法师", "刺客", "牧师"][active_uid()]
	if FileAccess.file_exists(path):
		var value = JSON.parse_string(FileAccess.get_file_as_string(path))
		if value is Dictionary: templates = value
	if not templates.has(role): labels.detail.text = "尚未保存%s模板。" % role; return
	var saved: Dictionary = templates[role]
	if not saved.has("rules") or not saved.has("pp") or saved.rules.size() != 3 or saved.pp.size() != 2:
		labels.detail.text = "模板格式不兼容，没有修改战术。"; return
	for lane in ["rules", "pp"]:
		for rule in saved[lane]:
			var allowed: Array = Sim.options(role) if lane == "rules" else Sim.pp_options(role)
			if not rule is Array or rule.size() != 3 or not allowed.has(rule[0]):
				labels.detail.text = "模板技能不兼容，没有修改战术。"; return
			for col in [1, 2]:
				if not Sim.conditions_for(rule[0]).has(rule[col]): labels.detail.text = "模板条件不兼容，没有修改战术。"; return
	settings.rules[active_uid()] = templates[role].rules.duplicate(true)
	settings.pp[active_uid()] = templates[role].pp.duplicate(true)
	sync_editor(); restart()

func sync_editor() -> void:
	task_picker.select(Sim.TASKS.find(settings.tasks[selected]))
	posture_picker.select(["贴近交战", "保持距离"].find(settings.postures[selected]))
	exception_picker.select(0 if settings.exceptions[selected] == "无" else 1)
	for i in range(2):
		squad_buttons[i].modulate = GOLD if i == selected else Color.WHITE
		member_buttons[i].text = [["盾兵", "法师"], ["刺客", "牧师"]][selected][i]
		member_buttons[i].modulate = BLUE if i == member_index else Color.WHITE
	var uid := active_uid()
	var role: String = ["盾兵", "法师", "刺客", "牧师"][uid]
	labels.member.text = role
	for w in rules_widgets:
		var choices: Array = Sim.options(role) if w.lane == "ap" else Sim.pp_options(role)
		var rule: Array = settings.rules[uid][w.slot] if w.lane == "ap" else settings.pp[uid][w.slot]
		w.skill.clear()
		for item in choices: w.skill.add_item(item)
		w.skill.select(choices.find(rule[0]))
		for col in [1, 2]:
			var control: OptionButton = w.condition if col == 1 else w.condition2
			control.clear()
			var conditions := Sim.conditions_for(rule[0])
			for item in conditions: control.add_item(item)
			control.select(conditions.find(rule[col]))

func restart() -> void:
	sim = Sim.new(); sim.reset(settings); live_sim = sim
	history = [sim.snapshot()]; replaying = false; event_count = -1; selected_event = -1
	running = false; step_ticks = 0; accumulator = 0
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
		for i in range(4):
			if sim.pos(i).distance_to(event.position) < 27:
				selected = int(i / 2); member_index = i % 2; focus_unit = i; sync_editor(); refresh_labels(); break

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
	refresh_labels(); queue_redraw()

func return_live() -> void:
	sim = live_sim; replaying = false; running = false; step_ticks = 0; selected_event = -1
	refresh_labels(); queue_redraw()

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
	var uid := focus_unit if focus_unit >= 4 else active_uid()
	var u: Dictionary = sim.units[uid]
	var text := "%.2fs  %s  |  %s\n" % [sim.clock, sim.title(uid), "历史复盘（只读）" if replaying else "现场（已暂停）"]
	running = false; step_ticks = 0
	text += "固有要求＋两个额外条件共同决定可执行性；上方失败才向下。\n"
	text += "条件为真但冷却/射程不满足，也会跳过，不代表条件为假。\n\n"
	text += "主动判定（%.2fs）\n" % u.get("check_time", 0.0)
	for row in u.checks:
		text += "↓ AP%d  %s\n" % [row.slot + 1, row.skill]
		if row.has("condition_ok"):
			text += "    条件[%s 且 %s]：%s  | 射程：%s | CD：%.1fs\n" % [row.condition1, row.condition2, "✓" if row.condition_ok else "✗", "✓" if row.range_ok else "✗", row.cooldown]
		text += "    %s %s\n" % ["→ 执行" if row.chosen else ("→ 跳过/继续" if row.has("condition_ok") else "→ 未评估"), row.reason]
	text += "\n反应判定（%.2fs；每个源事件每人最多一次）\n" % u.get("pp_check_time", 0.0)
	var pp_rows: Array = u.pp_checks
	if selected_event > 0 and selected_event <= sim.events.size():
		var event: Dictionary = sim.events[selected_event - 1]
		if event.kind == "PP":
			for decision in live_sim.decisions:
				if decision.kind == "反应" and decision.actor == uid and decision.event == event.parent:
					pp_rows = decision.checks; break
	for row in pp_rows: text += "↓ PP%d %s / %s → %s\n" % [row.slot + 1, row.skill, row.stage, row.reason]
	text += "\n当前状态：%s\n%s\n" % [u.mode, u.why]
	if selected_event > 0:
		text += "\n选中事件的真实来源链：\n" + "\n".join(causal_lines(selected_event))
	else:
		var combos: Array = sim.events.filter(func(e): return e.kind == "连携")
		if not combos.is_empty(): text += "\n最近连携的真实来源链：\n" + "\n".join(causal_lines(combos.back().id))
	audit_text.text = text; audit_dialog.popup_centered()

func refresh_labels() -> void:
	if sim.units.is_empty(): return
	labels.clock.text = "时间 %04.2fs / 55s    连携 %d 次    %s" % [sim.clock, sim.combo_count, "历史复盘" if replaying else (sim.result if sim.finished else ("运行中" if running or step_ticks > 0 else "已暂停"))]
	play_button.text = "返回现场播放" if replaying else ("暂停 [空格]" if running else ("再看一次" if sim.finished else "开始 [空格]"))
	labels.state.text = "A：%s | B：%s" % [sim.squads[0].reason, sim.squads[1].reason]
	labels.task.text = sim.squads[selected].reason
	var u: Dictionary = sim.units[active_uid()]
	labels.member_state.text = "%s  HP %.0f/%.0f  盾%.0f  %s" % [u.mode, u.hp, u.max_hp, u.shield, u.skill if u.mode in ["施法", "收招", "等待"] else ""]
	labels.pp_header.text = "反应战术 · PP %d/2 · %.1fs后恢复1点" % [u.pp_points, maxf(0, u.pp_next - sim.clock)]
	labels.why.text = u.why; labels.why.tooltip_text = u.why
	for w in rules_widgets:
		var active: bool = (u.slot == w.slot and u.mode in ["施法", "收招", "等待"]) if w.lane == "ap" else (u.pp_slot == w.slot and u.pp_until > sim.clock)
		w.skill.modulate = (GOLD if w.lane == "ap" else GREEN) if active and u.hp > 0 else Color.WHITE
		w.condition.tooltip_text = u.why
	timeline.set_block_signals(true)
	timeline.max_value = maxi(1, history.size() - 1)
	timeline.set_value_no_signal(sim.steps)
	timeline.set_block_signals(false)
	if event_count != live_sim.events.size():
		event_count = live_sim.events.size(); event_picker.clear(); event_ids.clear()
		for event in live_sim.events:
			if event.kind in ["AP", "连携", "PP", "等待", "等待结束", "阵亡", "任务", "结束"]:
				event_ids.append(event.id); event_picker.add_item("%05.2fs %s" % [event.time, event.text])
		if not event_ids.is_empty(): event_picker.select(event_ids.size() - 1)
	if selected_event > 0 and event_ids.has(selected_event): event_picker.select(event_ids.find(selected_event))
	elif replaying:
		var closest := -1
		for i in event_ids.size():
			if live_sim.events[event_ids[i] - 1].time <= sim.clock: closest = i
		if closest >= 0: event_picker.select(closest)
	var significant: Array = sim.events.filter(func(e): return e.kind in ["连携", "牵制", "PP", "阵亡", "结束", "等待", "等待结束"])
	var lines: Array[String] = []
	for i in range(maxi(0, significant.size() - 2), significant.size()): lines.append("%05.2f  %s" % [significant[i].time, significant[i].text])
	labels.log.text = "\n".join(lines) if not lines.is_empty() else "运行后拖动时间轴复盘；选择关键事件，再查看实际判定。"

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
	draw_style_box(panel_style(Color("132130")), Rect2(938, 89, 680, 648))
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
		while sim.clock < time and not sim.finished: sim.tick(); history.append(sim.snapshot())
		refresh_labels(); queue_redraw()
		await get_tree().process_frame; await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://reports/squad-%02d.png" % int(time))
	selected = 1; member_index = 0; focus_unit = 2; sync_editor()
	var waits: Array = live_sim.events.filter(func(e): return e.kind == "等待")
	if not waits.is_empty(): browse(roundi(waits[0].time / Sim.DT))
	refresh_labels(); queue_redraw()
	await get_tree().process_frame; await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://reports/squad-wait.png")
	open_audit()
	await get_tree().process_frame; await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://reports/squad-audit.png")
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
	var second_condition: OptionButton = rules_widgets[0].condition2
	var condition_index := Sim.conditions_for("协同突袭").find("目标正在施法")
	second_condition.select(condition_index); second_condition.item_selected.emit(condition_index)
	assert(settings.rules[2][0][2] == "目标正在施法" and sim.units[2].rules[0][2] == "目标正在施法")
	move_rule("ap", 1)
	assert(settings.rules[2][0][0] == "等待牵制" and settings.rules[2][1][0] == "协同突袭")
	selected = 0; sync_editor()
	var pp_condition: OptionButton = rules_widgets[3].condition
	var preserve := Sim.conditions_for("援护").find("保留1PP")
	pp_condition.select(preserve); pp_condition.item_selected.emit(preserve)
	assert(settings.pp[0][0][1] == "保留1PP" and sim.units[0].pp_rules[0][0] == "援护")
	posture_picker.item_selected.emit(1)
	assert(settings.postures[0] == "保持距离" and sim.squads[0].posture == "保持距离")
	exception_picker.item_selected.emit(1)
	assert(sim.squads[0].exception != "无")
	var test_path := "user://_squad-template-test.json"
	var original: Array = settings.rules[0].duplicate(true)
	save_template(test_path)
	settings.rules[0][0][0] = "留空"
	load_template(test_path)
	assert(settings.rules[0] == original)
	selected = 1; sync_editor(); save_template(test_path)
	assert(templates.has("盾兵") and templates.has("刺客"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path)); templates.clear()
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
	var final_state: Dictionary = live_sim.summary()
	timeline.value_changed.emit(200)
	assert(replaying and is_equal_approx(sim.clock, 10.0))
	assert(sim.units == history[200].units)
	_process(0.1)
	assert(sim.clock == 10.0 and live_sim.summary() == final_state, "browsing must neither advance history nor modify live result")
	var combo_index := -1
	for i in event_ids.size():
		if live_sim.events[event_ids[i] - 1].kind == "连携": combo_index = i; break
	assert(combo_index >= 0)
	event_picker.item_selected.emit(combo_index)
	assert(selected == 1 and member_index == 0)
	assert("牵制" in "\n".join(causal_lines(selected_event)))
	open_audit()
	assert("条件" in audit_text.text and "真实来源链" in audit_text.text)
	audit_dialog.hide()
	return_live()
	assert(not replaying and sim == live_sim and sim.summary() == final_state)
	var report := FileAccess.open("res://reports/squad-ui-validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": true, "checks": ["real task picker", "real AP picker", "real second condition", "priority reorder", "real PP condition", "real posture and exception controls", "template save/load retains other roles", "preserved configuration on retry", "one second playback before pause", "0.5/1/2 speed histories identical", "actual timeline navigation", "historical state isolation", "event actor navigation", "causal audit", "return to unchanged live result"], "default_result": sim.result, "time": sim.clock, "combos": sim.combo_count}, "\t"))
	print("SQUAD UI PASS: real task and rule controls, reset and stepping")
	get_tree().quit()
