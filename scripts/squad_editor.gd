extends PanelContainer
## One editor page at a time; active programs and reactive IF rules are distinct.
const Sim = preload("res://scripts/squad_simulation.gd")
var game
var page := 0
var tabs: TabBar
var body: VBoxContainer
var scroll: ScrollContainer
var widgets: Dictionary = {}
var state: Label
var note: Label

func setup(owner_game) -> void:
	game = owner_game
	position = Vector2(938, 20); size = Vector2(680, 790)
	add_theme_stylebox_override("panel", game.panel_style(Color("132130")))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var layout := VBoxContainer.new(); layout.add_theme_constant_override("separation", 12); margin.add_child(layout)
	text(layout, "战术工作台", 23, game.GOLD)
	tabs = TabBar.new()
	for title in ["小队任务", "主动战术", "反应战术", "复盘"]: tabs.add_tab(title)
	tabs.add_theme_font_override("font", game.font)
	tabs.add_theme_font_size_override("font_size", 16)
	tabs.custom_minimum_size.y = 38
	tabs.tab_changed.connect(show_page); layout.add_child(tabs)
	scroll = ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; layout.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12); scroll.add_child(body)
	rebuild()

func text(parent: Node, value: String, font_size := 15, color := Color("d8e2ef")) -> Label:
	var label := Label.new(); label.text = value
	label.add_theme_font_override("font", game.font); label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if parent is HBoxContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

func row(parent: Node) -> HBoxContainer:
	var line := HBoxContainer.new(); line.add_theme_constant_override("separation", 8); parent.add_child(line)
	return line

func picker(parent: Node, values: Array, current: String, width: float, callback: Callable) -> OptionButton:
	var control := OptionButton.new(); control.custom_minimum_size = Vector2(width, 34)
	if width == 0: control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new(); style.bg_color = Color("203447")
	style.set_corner_radius_all(5); style.content_margin_left = 12; style.content_margin_right = 12
	style.content_margin_top = 6; style.content_margin_bottom = 6
	control.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate(); hover.bg_color = Color("2a4258")
	control.add_theme_stylebox_override("hover", hover)
	control.add_theme_stylebox_override("pressed", hover)
	control.fit_to_longest_item = false; control.clip_text = true
	control.add_theme_font_override("font", game.font); control.add_theme_font_size_override("font_size", 14)
	for value in values: control.add_item(value)
	if not values.is_empty(): control.select(maxi(0, values.find(current)))
	control.disabled = game.replaying
	control.item_selected.connect(func(index): callback.call(control.get_item_text(index)))
	parent.add_child(control)
	return control

func button(parent: Node, title: String, callback: Callable) -> Button:
	var control := Button.new(); control.text = title; control.custom_minimum_size.y = 34
	control.add_theme_font_override("font", game.font); control.pressed.connect(callback); parent.add_child(control)
	return control

func card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new(); parent.add_child(panel)
	panel.add_theme_stylebox_override("panel", game.panel_style(Color("1a2b3c")))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 8); margin.add_child(box)
	if not title.is_empty(): text(box, title, 16, game.GOLD)
	return box

func show_page(index: int) -> void:
	page = index; tabs.set_block_signals(true); tabs.set_current_tab(index); tabs.set_block_signals(false); rebuild()

func rebuild() -> void:
	if body == null: return
	for child in body.get_children(): body.remove_child(child); child.queue_free()
	widgets.clear(); state = null; note = null
	game.timeline = null; game.event_picker = null; game.audit_text = null
	var context := row(body)
	if page == 0:
		for i in range(2):
			var squad := i
			var b := button(context, ["A队 · 盾兵＋法师", "B队 · 刺客＋牧师"][i], func(): game.selected = squad; rebuild())
			b.modulate = game.GOLD if game.selected == i else Color.WHITE
	else:
		for uid in range(4):
			var id := uid
			var b := button(context, ["A·盾兵", "A·法师", "B·刺客", "B·牧师"][uid], func():
				game.selected = int(id / 2); game.member_index = id % 2; game.focus_unit = id; rebuild())
			b.modulate = game.BLUE if game.active_uid() == uid else Color.WHITE
	state = text(body, "", 14, game.MUTED)
	if game.replaying: text(body, "历史快照 · 只读；返回现场后可修改战术", 14, game.GOLD)
	match page:
		0: build_tasks()
		1:
			text(body, "行动就绪时执行 · 最多两层 IF", 13, game.MUTED)
			var program: Dictionary = game.settings.programs[game.active_uid()]
			if program.type == "if": build_if(body, program, "", 0)
			else: build_action(body, program, "", "执行", 0)
			build_templates()
		2: build_reactions(); build_templates()
		3: build_review()
	note = text(body, "", 13, game.GREEN)
	refresh_status()

func build_tasks() -> void:
	var box := card(body, "小队持续任务")
	text(box, "移动、选路和队形由小队处理，角色按自己的战术选择技能。", 14, game.MUTED)
	text(box, "默认任务")
	game.task_picker = picker(box, Sim.TASKS, game.settings.tasks[game.selected], 450, func(value): edit_setting("tasks", value))
	text(box, "交战姿态")
	game.posture_picker = picker(box, ["贴近交战", "保持距离"], game.settings.postures[game.selected], 450, func(value): edit_setting("postures", value))
	text(box, "例外规则")
	game.exception_picker = picker(box, ["无", "小队HP≤35% → 撤回部署区"], game.settings.exceptions[game.selected], 450, func(value): edit_setting("exceptions", value))

func edit_setting(key: String, value: String) -> void:
	if game.replaying: return
	game.settings[key][game.selected] = value; game.restart()

func field_label(parent: Node, value: String, color: Color = Color("a9bacb"), width := 72.0) -> Label:
	var label := text(parent, value, 14, color)
	label.custom_minimum_size.x = width
	return label

func indent(parent: Node, amount: int) -> VBoxContainer:
	var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left", amount); parent.add_child(margin)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 8); margin.add_child(box)
	return box

func condition_picker(parent: Node, node: Dictionary, path: String) -> void:
	widgets[path + "/condition"] = picker(parent, Sim.CONDITIONS, node.condition, 0, func(value): edit_node(path, "condition", value))
	widgets[path + "/condition"].tooltip_text = "一次只判断一个条件；需要进一步判断时，在分支中加入第二层IF。无表示不加限制。"

func build_if(parent: Node, node: Dictionary, path: String, depth: int) -> void:
	var box := card(parent, "")
	var header := row(box)
	field_label(header, "IF", game.GOLD)
	condition_picker(header, node, path)
	build_action(box, node["then"], child_path(path, "then"), "成立", depth + 1)
	build_action(box, node["else"], child_path(path, "else"), "否则", depth + 1)

func build_action(parent: Node, node: Dictionary, path: String, title: String, depth: int) -> void:
	var line := row(parent)
	field_label(line, title, game.GREEN if title == "成立" else game.MUTED)
	var role: String = game.sim.units[game.active_uid()].role
	var choices: Array = Sim.options(role).duplicate()
	choices.append("WAIT · 等待")
	if depth < 2: choices.append("IF · 判断")
	var current: String = node.skill if node.type == "skill" else ("WAIT · 等待" if node.type == "wait" else "IF · 判断")
	var control := picker(line, choices, current, 0, func(value): change_type(path, value))
	widgets[path + "/action"] = control
	widgets[path + "/type"] = control
	if node.type == "skill": widgets[path + "/skill"] = control
	elif node.type == "if": build_if(indent(parent, 24), node, path, depth)
	else:
		var box := indent(parent, 80)
		var until := row(box)
		field_label(until, "等到", game.MUTED, 52)
		condition_picker(until, node, path)
		text(until, "最多", 13, game.MUTED)
		widgets[path + "/seconds"] = picker(until, ["0.5秒", "1秒", "2秒", "3秒"], str(node.seconds).trim_suffix(".0") + "秒", 85, func(value): edit_node(path, "seconds", value.trim_suffix("秒").to_float()))
		for port in ["then", "timeout"]:
			var exit_name: String = port
			var output := row(box)
			field_label(output, "满足后" if port == "then" else "超时后", game.MUTED, 52)
			widgets[child_path(path, port) + "/skill"] = picker(output, Sim.options(role), node[port].skill, 0, func(value): edit_node(child_path(path, exit_name), "skill", value))
		control.tooltip_text = "保留行动直到条件满足或超时；不会自动续期。"

func child_path(path: String, key: String) -> String:
	return key if path.is_empty() else path + "." + key

func at_path(path: String) -> Dictionary:
	var node: Dictionary = game.settings.programs[game.active_uid()]
	if not path.is_empty():
		for key in path.split("."): node = node[key]
	return node

func edit_node(path: String, key: String, value) -> void:
	if game.replaying: return
	at_path(path)[key] = value; game.restart()

func change_type(path: String, value: String) -> void:
	if game.replaying: return
	var skill: String = Sim.options(game.sim.units[game.active_uid()].role)[1]
	var node: Dictionary = Sim.action(value)
	if value == "WAIT · 等待": node = Sim.wait_action("目标被牵制", 1.0, skill, skill)
	elif value == "IF · 判断": node = Sim.branch("无", Sim.action(skill), Sim.action(skill))
	if path.is_empty(): game.settings.programs[game.active_uid()] = node
	else:
		var parts := path.rsplit(".", true, 1)
		if parts.size() == 1: game.settings.programs[game.active_uid()][parts[0]] = node
		else: at_path(parts[0])[parts[1]] = node
	game.restart(); rebuild()

func build_reactions() -> void:
	text(body, "事件触发时检查 · 从上到下选择一次响应", 13, game.MUTED)
	var uid: int = game.active_uid()
	var role: String = game.sim.units[uid].role
	for slot in range(2):
		var index := slot
		var rule: Array = game.settings.pp[uid][slot]
		var box := card(body, "反应 %d" % (slot + 1))
		var line := row(box); field_label(line, "IF", game.GOLD)
		widgets["pp%d/condition1" % slot] = picker(line, Sim.conditions_for(rule[0]), rule[1], 0, func(value): game.edit_condition("pp", index, 1, value))
		var output := row(box); field_label(output, "响应", game.GREEN)
		widgets["pp%d/skill" % slot] = picker(output, Sim.pp_options(role), rule[0], 0, func(value):
			if game.replaying: return
			rule[0] = value
			if rule[1] not in Sim.conditions_for(value): rule[1] = "无"
			game.restart(); rebuild())
		if slot > 0: button(output, "上移", func(): game.move_rule("pp", index))
		text(box, "触发：" + str(Sim.PP_SKILLS.get(rule[0], {}).get("stage", "未配置")), 12, game.MUTED)

func build_templates() -> void:
	var line := row(body)
	button(line, "保存模板", game.save_template)
	var load_button := button(line, "读取模板", game.load_template); load_button.disabled = game.replaying

func build_review() -> void:
	text(body, "暂停并查看历史状态；编辑配置不会发生在历史里。", 14, game.MUTED)
	game.timeline = HSlider.new(); game.timeline.custom_minimum_size = Vector2(550, 30); body.add_child(game.timeline)
	game.timeline.step = 1; game.timeline.max_value = maxi(1, game.history.size() - 1)
	game.timeline.value_changed.connect(func(value): game.browse(int(value)))
	button(body, "返回现场（暂停）", game.return_live)
	game.event_picker = picker(body, [], "", 560, func(_value): game.select_event(game.event_picker.selected))
	game.event_picker.disabled = false; game.event_count = -1
	game.audit_text = RichTextLabel.new(); game.audit_text.custom_minimum_size = Vector2(550, 410)
	game.audit_text.fit_content = true
	game.audit_text.add_theme_font_override("normal_font", game.font); game.audit_text.add_theme_font_size_override("normal_font_size", 15)
	body.add_child(game.audit_text)

func refresh_status() -> void:
	if game.sim.units.is_empty() or state == null: return
	var uid: int = game.focus_unit if page == 3 and game.focus_unit >= 4 else game.active_uid()
	var u: Dictionary = game.sim.units[uid]
	state.text = "%s  ·  %s  ·  HP %.0f/%.0f  ·  PP %d/2" % [game.sim.title(u.id), u.mode, u.hp, u.max_hp, u.pp_points]
	if page == 0: state.text = game.sim.squads[game.selected].reason
	if page == 3 and game.audit_text != null: game.audit_text.text = game.audit_description()
	if note != null: note.text = (u.why if u.why != "尚未选择技能" else "") if page != 0 else "修改当前小队任务会重试战斗；其它小队与角色程序保留。"
