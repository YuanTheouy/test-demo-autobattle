extends Node2D

# One world unit = 80 pixels. Navigation uses a finer grid; movement is continuous.
const ORIGIN := Vector2(35, 130)
const SIZE := 640.0
const RADIUS := 24.0
const MAX_HP := 100.0
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
const WALL_LAYOUT := [Rect2(270, 104, 20, 112), Rect2(350, 424, 20, 112)]
const WALL_HP := 300.0
var walls: Array[Rect2] = []
var wall_states: Array[Dictionary] = []
var wall_damage := {}
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
const ActionTimeline = preload("res://scripts/action_timeline.gd")
const ACTIVE_SKILLS = Tactics.ACTIVE
const REACTION_SKILLS = Tactics.REACTIONS
const CONDITIONS = Tactics.CONDITIONS
var loadouts: Array = []
var editor_unit := 0
var editor_rows: Array = []
var rule_count_label: Label
var unit_menu: OptionButton
var roster_buttons: Array = []
var character_label: Label
var reaction_counts := {}
const STEP := 1.0 / ActionTimeline.FPS
var accumulator := 0.0
var team_presets := [7, 8]
var preset_menus: Array = []
var subtitle: Label
var hit_events: Array = []
var shields_pending: Array = []
var heals_pending: Array = []
var impacts: Array = []
var body_impacts: Array = []
var body_pairs: Dictionary = {}
var links: Array = []
var skill_help: Label
var ultimate_aim := -1
var ultimate_cursor := Vector2.ZERO
const ULTIMATE_CHARGE_SECONDS := 12.0
const ULTIMATE_SLOW := 0.15
var drag_offset := Vector2.ZERO
const DEPLOY_GRID := 8
const DEPLOY_CELL_SIZE := SIZE / DEPLOY_GRID
const DEFAULT_DEPLOYMENT := [Vector2i(6, 2), Vector2i(6, 5), Vector2i(1, 2), Vector2i(1, 5)]
var deployment_cells: Array = DEFAULT_DEPLOYMENT.duplicate()
var deployment_drag := -1
var deployment_cursor := Vector2(-1, -1)
var arena_view = preload("res://scripts/arena_view.gd").new()
var logic_frame := 0
var deciding_frame := false
var perceived_bullets: Array = []
var perceived_hazards: Array = []



func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Heiti SC", "Arial"])
	DisplayServer.window_set_title("AutoBattle — 立体竞技场 / pseudo3d-arena")
	reset_walls()
	setup_navigation()
	setup_loadouts()
	setup_ui()
	reset_round()
	if "--lifecycle-test" in OS.get_cmdline_user_args():
		run_lifecycle_tests()
		get_tree().quit()
		return
	if "--lifecycle-preview" in OS.get_cmdline_user_args():
		started = true
		for tick in range(600):
			simulate(STEP)
			var reacting := -1
			for u in units:
				if u.dodge > 0 and u.get("last_cancel", "").contains("取消"): reacting = u.uid
			if reacting >= 0:
				choose_editor_unit(reacting)
				break
		set_physics_process(false)
		refresh_ui()
		capture_lifecycle_preview.call_deferred()
		return
	if "--deployment-test" in OS.get_cmdline_user_args():
		run_deployment_tests()
		get_tree().quit()
		return
	if "--deployment-preview" in OS.get_cmdline_user_args():
		choose_editor_unit(0)
		deployment_cursor = deployment_center(Vector2i(5, 3))
		set_physics_process(false)
		capture_deployment_preview.call_deferred()
		return
	if "--ultimate-debt-test" in OS.get_cmdline_user_args():
		run_ultimate_debt_tests()
		get_tree().quit()
		return
	if "--strategy-view-test" in OS.get_cmdline_user_args():
		run_strategy_view_tests()
		get_tree().quit()
		return
	if "--postmatch-test" in OS.get_cmdline_user_args():
		run_postmatch_tests()
		get_tree().quit()
		return
	if "--resource-test" in OS.get_cmdline_user_args():
		run_resource_tests()
		get_tree().quit()
		return
	if "--ultimate-test" in OS.get_cmdline_user_args():
		run_ultimate_tests()
		get_tree().quit()
		return
	if "--ultimate-barrage-preview" in OS.get_cmdline_user_args():
		started = true
		units[1].ult_charge = 100.0
		begin_ultimate_aim(1)
		ultimate_cursor = units[2].p
		set_physics_process(false)
		refresh_ui()
		capture_preview.call_deferred()
		return
	if "--ultimate-preview" in OS.get_cmdline_user_args():
		started = true
		units[0].ult_charge = 100.0
		units[1].ult_charge = 65.0
		begin_ultimate_aim(0)
		ultimate_cursor = units[2].p
		set_physics_process(false)
		refresh_ui()
		capture_preview.call_deferred()
		return
	if "--wall-test" in OS.get_cmdline_user_args():
		run_wall_tests()
		get_tree().quit()
		return
	if "--wall-preview" in OS.get_cmdline_user_args() or "--wall-broken-preview" in OS.get_cmdline_user_args():
		queue_wall_damage(0, 100)
		queue_wall_damage(1, 300 if "--wall-broken-preview" in OS.get_cmdline_user_args() else 200)
		apply_wall_damage()
		for fx in effects:
			if fx.get("wall_break", false): fx.life = 0.5
		capture_preview.call_deferred()
		return
	if "--view-test" in OS.get_cmdline_user_args():
		run_view_tests()
		get_tree().quit()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view-preview="):
			prepare_view_preview(arg.get_slice("=", 1))
			return
	if "--body-bounce-test" in OS.get_cmdline_user_args():
		run_body_bounce_tests()
		get_tree().quit()
		return
	if "--blast-push-test" in OS.get_cmdline_user_args():
		run_blast_push_tests()
		get_tree().quit()
		return
	if "--position-test" in OS.get_cmdline_user_args():
		run_position_tests()
		get_tree().quit()
		return
	if "--impact-test" in OS.get_cmdline_user_args():
		run_impact_tests()
		get_tree().quit()
		return
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
	if "--position-preview" in OS.get_cmdline_user_args():
		for tick in range(360): simulate(STEP)
		running = false
		capture_preview.call_deferred()

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

func ui_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box := make_box(Color("111a26") if state == "disabled" else Color("202b3b") if state == "normal" else Color("334357"), Color("28364a") if state == "disabled" else Color("46516a") if state == "normal" else GOLD)
			box.content_margin_left = 10
			box.content_margin_right = 20 if type == "OptionButton" else 10
			box.content_margin_top = 4
			box.content_margin_bottom = 4
			theme.set_stylebox(state, type, box)
		theme.set_color("font_color", type, Color("e7e1d5"))
		theme.set_color("font_hover_color", type, Color("fff1ce"))
		theme.set_color("font_disabled_color", type, Color("697c92"))
	theme.set_stylebox("panel", "PopupMenu", make_box(Color("182332"), Color("a58d61")))
	theme.set_stylebox("hover", "PopupMenu", make_box(Color("3d4651"), GOLD))
	theme.set_color("font_color", "PopupMenu", Color("eee7d9"))
	theme.set_font_size("font_size", "PopupMenu", 15)
	return theme

func choose_editor_unit(uid: int) -> void:
	editor_unit = uid
	selected = uid
	unit_menu.select(uid)
	rebuild_editor()

func editor_entries() -> Array:
	var entries: Array = []
	for kind in ["active", "reaction"]:
		var rules: Array = loadouts[editor_unit][kind]
		for slot in range(rules.size()):
			if rules[slot][0] != "留空": entries.append({"kind": kind, "slot": slot, "rule": rules[slot]})
	return entries

func move_rule(kind: String, slot: int, direction: int) -> void:
	var rules: Array = loadouts[editor_unit][kind]
	var other := slot + direction
	if other < 0 or other >= rules.size(): return
	var saved: Array = rules[slot]
	rules[slot] = rules[other]
	rules[other] = saved
	rebuild_editor()
	reset_round()

func move_editor_row(index: int, direction: int) -> void:
	var entries := editor_entries()
	if index >= entries.size(): return
	var entry: Dictionary = entries[index]
	move_rule(entry.kind, entry.slot, direction)

func edit_rule_cell(index: int, column: int, value: String) -> void:
	if index < 0 or index >= Tactics.RULE_LIMIT: return
	var entries := editor_entries()
	if index >= entries.size() and (column != 0 or value == "留空"): return
	var rule: Array = ["留空", "无", "无"] if index >= entries.size() else entries[index].rule.duplicate()
	rule[column] = value
	var old_kind: String = "" if index >= entries.size() else entries[index].kind
	var new_kind: String = Tactics.skill_kind(rule[0])
	if old_kind == new_kind and not old_kind.is_empty():
		loadouts[editor_unit][old_kind][entries[index].slot] = rule
	else:
		if not old_kind.is_empty(): loadouts[editor_unit][old_kind].remove_at(entries[index].slot)
		if not new_kind.is_empty(): loadouts[editor_unit][new_kind].append(rule)
	loadouts[editor_unit] = Tactics.compact(loadouts[editor_unit])
	rebuild_editor()
	reset_round()
	skill_help.text = "%s\n%s" % [rule[0], Tactics.DESCRIPTIONS.get(rule[0], "空槽不执行；可添加任意AP或PP技能。")]

func show_editor_help(index: int) -> void:
	var entries := editor_entries()
	if index >= entries.size():
		skill_help.text = "空槽 · AP / PP 共用12格\n选择技能后自动归类；基础操作也可以加条件、排序或删除。"
		return
	var entry: Dictionary = entries[index]
	var skill: String = entry.rule[0]
	skill_help.text = "%s · %s · 精力 %d\n%s" % ["AP" if entry.kind == "active" else "PP", skill, energy_cost(skill), Tactics.DESCRIPTIONS.get(skill, "")]

func setup_ui() -> void:
	var title := text_label(self, "AUTOBATTLE", 28)
	title.position = Vector2(35, 24)
	title.modulate = Color("e7d7b2")
	subtitle = text_label(self, "", 14)
	subtitle.position = Vector2(36, 68)
	status_label = text_label(self, "", 16)
	status_label.position = Vector2(35, 100)
	for uid in range(2):
		var portrait = preload("res://scripts/ultimate_portrait.gd").new()
		portrait.game = self
		portrait.uid = uid
		portrait.position = Vector2(690 + uid * 112, 25)
		portrait.size = Vector2(100, 105)
		add_child(portrait)
	var root := Control.new()
	root.theme = ui_theme()
	add_child(root)
	var controls := HBoxContainer.new()
	controls.position = Vector2(36, 738)
	controls.add_theme_constant_override("separation", 8)
	root.add_child(controls)
	start_button = add_button(controls, "开始交战 [空格]", toggle_running)
	add_button(controls, "重开 [R]", reset_round)
	var step_button := add_button(controls, "单帧 [N]", step_forward)
	step_button.tooltip_text = "N：前进1逻辑帧（1/60秒）；Shift+N：前进12帧。"
	add_button(controls, "交换出生侧", func(): blue_attacks = not blue_attacks; reset_round())
	var speed_button := add_button(controls, "速度 %s×" % speed, func(): pass)
	speed_button.pressed.connect(func(): speed = 2.0 if speed == 1.0 else (0.5 if speed == 2.0 else 1.0); speed_button.text = "速度 %s×" % speed)
	var check := CheckButton.new()
	check.text = "范围预告"
	check.button_pressed = true
	check.toggled.connect(func(value: bool): show_aim = value)
	controls.add_child(check)
	var backdrop := Panel.new()
	backdrop.position = Vector2(928, 16)
	backdrop.size = Vector2(696, 798)
	backdrop.add_theme_stylebox_override("panel", make_box(Color("141e2d"), Color("8b7958")))
	root.add_child(backdrop)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(942, 26)
	scroll.size = Vector2(670, 778)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = 650
	panel.add_theme_constant_override("separation", 4)
	scroll.add_child(panel)
	var heading := HBoxContainer.new()
	panel.add_child(heading)
	var caption := text_label(heading, "作 战 配 置", 23)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.modulate = GOLD
	add_button(heading, "重置站位", func(): deployment_cells = DEFAULT_DEPLOYMENT.duplicate(); reset_round())
	add_button(heading, "仅基础", func(): loadouts[editor_unit] = Tactics.basics(); rebuild_editor(); reset_round())
	add_button(heading, "清空", func(): loadouts[editor_unit] = Tactics.build([], []); rebuild_editor(); reset_round())
	var presets := HBoxContainer.new()
	panel.add_child(presets)
	for team in range(2):
		var team_label := text_label(presets, "蓝队" if team == 0 else "红队", 13)
		team_label.modulate = BLUE if team == 0 else RED
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(278, 30)
		for name in Tactics.NAMES: picker.add_item(name)
		picker.select(team_presets[team])
		picker.item_selected.connect(func(index: int): apply_preset(team, index))
		presets.add_child(picker)
		preset_menus.append(picker)
	var roster := HBoxContainer.new()
	roster.add_theme_constant_override("separation", 6)
	panel.add_child(roster)
	for uid in range(4):
		var card := Button.new()
		card.custom_minimum_size = Vector2(158, 44)
		card.pressed.connect(func(): choose_editor_unit(uid))
		roster.add_child(card)
		roster_buttons.append(card)
	# Hidden selector preserves the same selection path for battlefield clicks.
	unit_menu = OptionButton.new()
	for name in ["蓝1", "蓝2", "红1", "红2"]: unit_menu.add_item(name)
	unit_menu.item_selected.connect(choose_editor_unit)
	unit_menu.hide()
	panel.add_child(unit_menu)
	character_label = text_label(panel, "", 13)
	rule_count_label = text_label(panel, "", 13)
	rule_count_label.modulate = Color("c8b997")
	var columns := HBoxContainer.new()
	panel.add_child(columns)
	for spec in [["顺序 / 类型", 68], ["技能", 145], ["条件一", 153], ["条件二", 153], ["检查 / 执行", 110]]:
		var label := text_label(columns, spec[0], 11)
		label.custom_minimum_size.x = spec[1]
		label.modulate = Color("8696a9")
	for index in range(Tactics.RULE_LIMIT):
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", make_box(Color("1d2939"), Color("344358")))
		panel.add_child(frame)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		frame.add_child(row)
		var number := text_label(row, "%02d" % (index + 1), 11)
		number.custom_minimum_size.x = 18
		var badge := text_label(row, "—", 12)
		badge.custom_minimum_size.x = 24
		var arrows := VBoxContainer.new()
		arrows.add_theme_constant_override("separation", 0)
		row.add_child(arrows)
		var moves: Array = []
		for direction in [-1, 1]:
			var arrow := Button.new()
			arrow.text = "↑" if direction == -1 else "↓"
			arrow.add_theme_font_size_override("font_size", 9)
			var tiny := StyleBoxEmpty.new()
			for state in ["normal", "hover", "pressed", "disabled"]: arrow.add_theme_stylebox_override(state, tiny)
			arrow.add_theme_color_override("font_disabled_color", Color("45546a"))
			arrow.custom_minimum_size.x = 16
			arrow.tooltip_text = "调整同类规则优先级；修改后重开"
			arrow.pressed.connect(func(): move_editor_row(index, direction))
			arrows.add_child(arrow)
			moves.append(arrow)
		var picks: Array = []
		for column in range(3):
			var menu := OptionButton.new()
			menu.custom_minimum_size = Vector2(143 if column == 0 else 151, 34)
			menu.fit_to_longest_item = false
			menu.clip_text = true
			var options: Array = Tactics.all_skills() if column == 0 else CONDITIONS
			for option in options:
				menu.add_item(option)
				if column == 0:
					menu.get_popup().set_item_tooltip(menu.item_count - 1, Tactics.DESCRIPTIONS.get(option, ""))
			menu.item_selected.connect(func(choice: int): edit_rule_cell(index, column, menu.get_item_text(choice)))
			menu.mouse_entered.connect(func(): show_editor_help(index))
			menu.focus_entered.connect(func(): show_editor_help(index))
			row.add_child(menu)
			picks.append(menu)
		var state := text_label(row, "空槽", 11)
		state.custom_minimum_size.x = 110
		state.clip_text = true
		editor_rows.append({"kind": "", "slot": -1, "menus": picks, "row": row, "frame": frame, "state": state, "badge": badge, "arrows": moves})

	text_label(panel, "─────────────────────────────────────────────", 12).modulate = Color("817052")
	skill_help = text_label(panel, "AP / PP 共用12格\n基础操作同样可编辑；清空所有规则后原地待命。", 12)
	skill_help.custom_minimum_size = Vector2(640, 42)
	skill_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_help.modulate = Color("c8b997")
	info_label = text_label(panel, "", 12)
	info_label.custom_minimum_size.x = 640
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label = text_label(panel, "", 17)
	result_label.modulate = GOLD
	var detail := VBoxContainer.new()
	panel.add_child(detail)
	var disclosure := add_button(panel, "展开战斗记录", func(): detail.visible = not detail.visible)
	panel.move_child(disclosure, detail.get_index())
	log_label = text_label(detail, "", 12)
	detail.hide()
	var foot := text_label(self, "点击机甲或角色卡编辑策略 · 金色行：正在执行 · 修改策略后重开", 13)
	foot.position = Vector2(36, 790)
	foot.modulate = Color("8e9eae")
	rebuild_editor()

func rebuild_editor() -> void:
	var entries := editor_entries()
	var active_count := 0
	for entry in entries:
		if entry.kind == "active": active_count += 1
	rule_count_label.text = "规则 %d / 12    AP %d · PP %d    /    AP在前 · PP在后 · 各自从上向下检查" % [entries.size(), active_count, entries.size() - active_count]
	for index in range(editor_rows.size()):
		var row: Dictionary = editor_rows[index]
		var occupied := index < entries.size()
		var entry: Dictionary = entries[index] if occupied else {"kind": "", "slot": -1, "rule": ["留空", "无", "无"]}
		row.kind = entry.kind
		row.slot = entry.slot
		var accent := Color("e39989") if row.kind == "active" else (Color("85bfe5") if row.kind == "reaction" else Color("697c92"))
		row.badge.text = "AP" if row.kind == "active" else ("PP" if row.kind == "reaction" else "—")
		row.badge.modulate = accent
		row.arrows[0].disabled = not occupied or entry.slot == 0
		row.arrows[1].disabled = not occupied or entry.slot + 1 >= loadouts[editor_unit][entry.kind].size()
		for column in range(3):
			var menu: OptionButton = row.menus[column]
			if column > 0:
				var allowed: Array = ["无", "优先低血量", "自己HP≤50", "队友HP≤50", "自己精力≥80", "自己精力≥50", "自己精力≤30"] if entry.rule[0] in ["回春", "灵木护佑"] else CONDITIONS
				menu.clear()
				for condition in allowed: menu.add_item(condition)
				if entry.rule[column] not in allowed: entry.rule[column] = "无"
				menu.disabled = not occupied
			var value: String = entry.rule[column]
			for choice in range(menu.item_count):
				if menu.get_item_text(choice) == value: menu.select(choice)
			menu.tooltip_text = value
			if column == 0:
				menu.add_theme_color_override("font_color", accent)
				menu.tooltip_text = Tactics.DESCRIPTIONS.get(value, "空槽；可添加任意AP或PP规则") + "\n精力消耗：%d" % energy_cost(value)

func add_button(parent: Node, title: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = title
	b.custom_minimum_size.y = 34
	b.add_theme_font_override("font", font)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func reset_round() -> void:
	ultimate_aim = -1
	deployment_drag = -1
	deployment_cursor = Vector2(-1, -1)
	reset_walls()
	validate_deployment()
	running = false
	started = false
	finished = false
	clock = ROUND_TIME
	logic_frame = 0
	deciding_frame = false
	perceived_bullets.clear()
	perceived_hazards.clear()
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
			var p: Vector2 = deployment_position(team * 2 + member)
			units.append({"trace_ap": new_rule_trace("未检查"), "trace_pp": new_rule_trace("未检查"), "energy": 100.0, "ult_charge": 0.0, "ult_angle": 0.0, "uid": team * 2 + member, "team": team, "member": member, "attack": attack, "p": p,
				"blast_impulse": Vector2.ZERO, "blast_lock": 0.0, "impulse": Vector2.ZERO, "evade_source": -1, "counter_left": 0.0, "thorns": 0.0, "thorn_tick": 0.0, "hurt_recent": 0.0, "hit_flash": 0.0, "heal_flash": 0.0, "reason": "基础作战就绪", "rule_kind": "", "rule_slot": -1, "slow": 0.0, "shield": 0.0, "shield_time": 0.0, "patrol": 0, "dash_recovery": false, "avoid_left": 0.0, "avoid_dir": Vector2.ZERO, "active_skill": "点射", "rule": "待机", "rule_flash": 0.0, "fire_flash": 0.0, "marked": 0.0, "guard": 0.0, "skill_cds": {}, "action_left": 0.0, "action_goal": p,
				"intent": "待机", "retreat": 0.0, "retreat_cd": 0.0, "hp": MAX_HP, "phase": "移动", "timer": 0.0, "cooldown": 0.0,
				"angle": 0.0 if attack else PI, "target": -1, "path": PackedVector2Array(),
				"repath": 0.0, "goal": p, "dodge": 0.0, "dodge_dir": Vector2.ZERO, "shot_count": 0, "last_seen": Vector2(-1, -1), "memory": 0.0})
	reaction_counts.clear()
	for u in units:
		ActionTimeline.clear(u)
		u.dodge_frames = 0
		u.frame_triggers = 0
		u.frame_branch = "等待决策"
	log_event("蓝：%s / 红：%s" % [Tactics.NAMES[team_presets[0]], Tactics.NAMES[team_presets[1]]])
	refresh_ui()
	queue_redraw()

func toggle_running() -> void:
	deployment_drag = -1
	started = true
	running = not running
	refresh_ui()

func deployment_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / DEPLOY_CELL_SIZE), floori(point.y / DEPLOY_CELL_SIZE))

func deployment_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * DEPLOY_CELL_SIZE

func deployment_position(uid: int) -> Vector2:
	var cell: Vector2i = deployment_cells[uid]
	if blue_attacks: cell.x = DEPLOY_GRID - 1 - cell.x
	return deployment_center(cell)

func validate_deployment() -> void:
	# The asymmetric walls can obstruct a previously valid cell after a side swap.
	var cells: Array[Vector2i] = []
	for uid in range(4): cells.append(deployment_cell(deployment_position(uid)))
	for uid in range(cells.size()):
		if valid_position(deployment_center(cells[uid])): continue
		var nearest := cells[uid]
		var distance := INF
		for x in range(DEPLOY_GRID):
			for y in range(DEPLOY_GRID):
				var candidate := Vector2i(x, y)
				if candidate in cells or not valid_position(deployment_center(candidate)): continue
				var d := Vector2(candidate).distance_squared_to(Vector2(cells[uid]))
				if d < distance:
					distance = d
					nearest = candidate
		cells[uid] = nearest
		if blue_attacks: nearest.x = DEPLOY_GRID - 1 - nearest.x
		deployment_cells[uid] = nearest

func can_deploy(uid: int, cell: Vector2i) -> bool:
	if started or uid < 0 or uid >= units.size(): return false
	if cell.x < 0 or cell.y < 0 or cell.x >= DEPLOY_GRID or cell.y >= DEPLOY_GRID: return false
	var point := deployment_center(cell)
	if not valid_position(point): return false
	for other in units:
		if other.uid != uid and point.distance_to(other.p) < RADIUS * 2 + 2: return false
	return true

func place_unit(uid: int, cell: Vector2i) -> bool:
	if not can_deploy(uid, cell): return false
	var point := deployment_center(cell)
	var saved_cell := cell
	if blue_attacks: saved_cell.x = DEPLOY_GRID - 1 - saved_cell.x
	deployment_cells[uid] = saved_cell
	units[uid].p = point
	units[uid].goal = point
	units[uid].action_goal = point
	units[uid].path = PackedVector2Array()
	return true

func _input(event: InputEvent) -> void:
	# Finish a drag even when the pointer is released over a UI control.
	if deployment_drag < 0: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deployment_drag = -1
		deployment_cursor = Vector2(-1, -1)
		queue_redraw()
		return
	if event is InputEventMouseMotion:
		deployment_cursor = arena_view.unproject(event.position) + drag_offset
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		deployment_cursor = arena_view.unproject(event.position) + drag_offset
		place_unit(deployment_drag, deployment_cell(deployment_cursor))
		deployment_drag = -1
		refresh_ui()
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if ultimate_aim >= 0:
		if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
			ultimate_aim = -1
			queue_redraw()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			confirm_ultimate(arena_view.unproject(get_global_mouse_position()))
			return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE: toggle_running()
		if event.keycode == KEY_R: reset_round()
		if event.keycode == KEY_N: step_forward(12 if event.shift_pressed else 1)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var clicked_unit := -1
			for i in range(units.size()):
				if arena_view.project(arena_view.display_position(units[i]), 25).distance_to(event.position) < 28:
					clicked_unit = i
					break
			if clicked_unit >= 0:
				choose_editor_unit(clicked_unit)
				if not started:
					deployment_drag = clicked_unit
					drag_offset = units[clicked_unit].p - arena_view.unproject(event.position)
					deployment_cursor = units[clicked_unit].p
			elif not started and selected >= 0:
				place_unit(selected, deployment_cell(arena_view.unproject(event.position)))
	if event is InputEventMouseMotion and not started and deployment_drag < 0:
		deployment_cursor = arena_view.unproject(event.position)
	refresh_ui()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if ultimate_aim >= 0:
		if units[ultimate_aim].hp <= 0: ultimate_aim = -1
		else: ultimate_cursor = arena_view.unproject(get_global_mouse_position())
	if "--preview" in OS.get_cmdline_user_args():
		preview_frames += 1
		if preview_frames == 720 or ("--effects-preview" in OS.get_cmdline_user_args() and not blasts.is_empty()) or ("--pattern-preview" in OS.get_cmdline_user_args() and not hazards.is_empty()):
			capture_preview.call_deferred()
	if running: advance_playback(delta)
	refresh_ui()
	queue_redraw()

func advance_playback(delta: float) -> void:
	accumulator += delta * speed * (ULTIMATE_SLOW if ultimate_aim >= 0 else 1.0)
	while accumulator + 0.00000001 >= STEP and running:
		accumulator -= STEP
		simulate(STEP)

func step_forward(frame_count := 1) -> void:
	running = false
	started = true
	deployment_drag = -1
	accumulator = 0.0
	for tick in range(frame_count):
		simulate(STEP)
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
	logic_frame += 1
	clock -= dt
	shields_pending.clear()
	heals_pending.clear()
	for event in hit_events: event.life -= dt
	hit_events = hit_events.filter(func(event): return event.life > 0)
	for link in links: link.life -= dt
	links = links.filter(func(link): return link.life > 0)
	refresh_boundary_navigation()
	enforce_boundary()
	var visible := [contacts(0), contacts(1)]
	focus_timer -= dt
	update_team_focus(visible)
	# All decisions read the same immutable start-of-step world.
	# New projectiles/telegraphs become perceptible to EVERY actor next frame.
	perceived_bullets = bullets.duplicate(true)
	perceived_hazards = hazards.duplicate(true)
	deciding_frame = true
	var next_units: Array[Dictionary] = []
	for old in units: next_units.append(old.duplicate(true))
	for i in range(units.size()):
		var u: Dictionary = next_units[i]
		u.frame_triggers = 0
		u.frame_branch = "死亡" if u.hp <= 0 else "等待决策"
		if u.hp <= 0: continue
		u.ult_charge = minf(100, u.ult_charge + dt * 100.0 / ULTIMATE_CHARGE_SECONDS)
		for key in u.skill_cds.keys(): u.skill_cds[key] = maxf(0, u.skill_cds[key] - dt)
		u.counter_left = maxf(0, u.counter_left - dt)
		u.cooldown = maxf(0, u.cooldown - dt)
		if not ActionTimeline.busy(u) and u.phase not in ["吟唱", "瞄准", "点射", "收招", "大招蓄力", "回春", "灵木护佑", "掩护队友"]:
			u.energy = minf(100, u.energy + 12.0 * dt)
		u.blast_lock = maxf(0, u.blast_lock - dt)
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
			u.frame_branch = "PP：侧闪"
			advance_dodge(u, dt)
			continue
		if ActionTimeline.busy(u) or u.phase in ["吟唱", "瞄准", "点射", "收招", "大招蓄力"]:
			# Only dodge can cancel a committed action; other PP wait for decision time.
			if try_reaction(u, visible[u.team], false, true):
				u.frame_branch = "PP：侧闪"
				advance_dodge(u, dt)
				continue
			u.frame_branch = ("PP：" if u.rule_kind == "reaction" else "AP：") + u.get("action_stage", u.phase)
			update_attack(u, dt)
			continue
		var can_evade: bool = u.phase not in ["吟唱", "点射", "收招", "架枪防御", "回春", "灵木护佑", "掩护队友"] and not (u.phase == "瞄准" and u.shot_count > 0)
		if can_evade:
			if try_reaction(u, visible[u.team]):
				u.frame_branch = "PP：" + u.intent
				if u.dodge > 0: advance_dodge(u, dt)
				var step_to: Vector2 = u.p.move_toward(u.action_goal, unit_move_speed(u) * dt)
				if u.phase == "规避预警" and movement_is_free(u, step_to): u.p = step_to
				continue

		# Configured movement yields only to higher-priority AP rules.
		if u.intent in ["战斗走位", "战术换位"] and u.action_left > 0:
			var movement_reason: String = u.reason
			if try_active(u, visible[u.team], u.rule_slot if u.rule_kind == "active" else -1): continue
			u.reason = movement_reason
		if u.action_left > 0:
			u.frame_branch = ("PP：" if u.rule_kind == "reaction" else "AP：") + u.intent
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
				ActionTimeline.enter(u, ActionTimeline.RECOVERY, ActionTimeline.frames(0.45))
			continue
		if not try_active(u, visible[u.team]):
			u.phase = "待命"
			u.intent = "待命"
			u.rule_kind = ""
			u.rule_slot = -1
			u.target = -1
			u.reason = "没有满足条件的AP规则；等待恢复或反应事件"
	deciding_frame = false
	for actor in next_units: assert(actor.frame_triggers <= 1, "One bot may select at most one AP/PP per logic frame")
	body_impacts.clear()
	body_pairs.clear()
	for actor in next_units:
		if actor.hp > 0:
			if actor.blast_lock > 0:
				actor.p = units[actor.uid].p.lerp(actor.p, 0.25)
			apply_forced_motion(actor, dt)
	for contact in body_impacts:
		var receiver: Dictionary = next_units[contact.uid]
		receiver.blast_impulse = (receiver.blast_impulse + contact.velocity).limit_length(3150.0)
		receiver.blast_lock = maxf(receiver.blast_lock, 0.12)
	# Reject conflicting movement proposals together, never first-come-first-served.
	var rejected: Array[int] = []
	for i in range(next_units.size()):
		for j in range(i + 1, next_units.size()):
			if next_units[i].hp > 0 and next_units[j].hp > 0 and next_units[i].p.distance_to(next_units[j].p) < RADIUS * 2:
				var normal: Vector2 = (units[i].p - units[j].p).normalized()
				for pair in [[i, normal], [j, -normal]]:
					var actor: Dictionary = next_units[pair[0]]
					var velocity: Vector2 = actor.impulse + actor.blast_impulse
					if velocity.dot(pair[1]) < 0:
						actor.impulse = Vector2.ZERO
						actor.blast_impulse = velocity.bounce(pair[1]) * 0.55
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
	return Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))

func ally_index(u: Dictionary) -> int:
	for i in range(units.size()):
		if units[i].team == u.team and units[i].uid != u.uid and units[i].hp > 0: return i
	return -1

func incoming_pressure(u: Dictionary, visible: Array) -> int:
	var count := 0
	for j in visible:
		var enemy: Dictionary = units[j]
		if enemy.phase in ["吟唱", "瞄准", "点射", "释放硬直"] and enemy.target >= 0 and units[enemy.target].uid == u.uid and not blocked(enemy.p, u.p): count += 1
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
		if ally >= 0 and units[ally].target == j and units[ally].phase in ["吟唱", "瞄准", "点射", "释放硬直"]: candidate -= 35
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
		for local_x in range(32):
			var x: int = local_x if u.attack else 31 - local_x
			for local_y in range(32):
				var y: int = local_y if u.attack else 31 - local_y
				if nav.is_point_solid(Vector2i(x, y)): continue
				var point := Vector2(x * 20 + 10, y * 20 + 10)
				if point.distance_to(enemy) > SHOT_RANGE - 20 or blocked(point, enemy) or not movement_is_free(u, point): continue
				var d: float = position_score(u, target, point)
				for ally in units:
					if ally.uid != u.uid and ally.hp > 0 and point.distance_to(ally.p) < RADIUS * 2 + 12: d += 10000
				if d < score - 0.001: score = d; best = point
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
	var base_speed := ENGAGE_SPEED if u.intent in ["基础接敌", "搜索", "战术换位"] else MOVE_SPEED
	var skill_multiplier := 2.4 if u.intent == "短冲刺" else (1.2 if u.intent in ["绕侧", "后撤"] else 1.0)
	return base_speed * (0.6 if u.slow > 0 else 1.0) * skill_multiplier * energy_speed(u)

func basic_action(u: Dictionary, visible: Array, rule: Array) -> bool:
	var skill: String = rule[0]
	var target := rule_target(u, visible, rule, skill in ["普通攻击", "调整站位"])
	if skill == "普通攻击":
		if target < 0 or not can_use_skill(u, "点射"): return false
		begin_shot(u, target, "点射")
		return true
	if skill == "调整站位":
		if target < 0: return false
		if not prepare_reposition(u, target, [target]) and not prepare_combat_step(u, target):
			u.phase = "保持射位"
			u.intent = "保持射位"
			u.action_left = 0.2
			u.action_goal = u.p
			u.reason = "附近没有安全换位空间，保持射位"
		return true
	if skill == "接敌":
		if visible.is_empty():
			if u.memory <= 0 or not conditions_without_target(u, rule): return false
		elif target < 0: return false
	elif skill == "搜寻":
		if not visible.is_empty() or u.memory > 0 or not conditions_without_target(u, rule): return false
	else: return false
	u.action_goal = choose_goal(u, [target] if target >= 0 else [])
	u.action_left = 2.0 if target >= 0 else 0.8
	u.repath = 0.0
	u.target = target
	u.intent = "战术换位" if target >= 0 else "搜索"
	u.phase = u.intent
	u.reason = "寻找目标的有效射位" if target >= 0 else ("前往最后发现敌人的位置" if u.memory > 0 else "巡查交战区域，寻找敌人")
	return true

func conditions_without_target(u: Dictionary, rule: Array) -> bool:
	for condition in [rule[1], rule[2]]:
		if condition in ["无", "优先队友目标", "优先低血量", "优先最近敌人"]: continue
		if condition not in ["自己HP≤50", "队友HP≤50", "自己精力≥80", "自己精力≥50", "自己精力≤30", "队友正在被瞄准", "自己被两人瞄准"]: return false
		if not passes_condition(u, -1, condition): return false
	return true

# First configured offensive skill defines a stable distance preference, independent of CD.
func preferred_range(u: Dictionary) -> float:
	for rule in loadouts[u.uid].active:
		var skill: String = rule[0]
		if skill == "霰弹": return 125.0
		if skill in ["抛射轰击", "烈焰爆破", "蓄能贯穿"]: return 240.0
		if skill in Tactics.MAGIC or skill in ["标记弹", "强力射击", "压制射击"]: return 190.0
	return 190.0

func position_score(u: Dictionary, target: int, point: Vector2) -> float:
	var enemy: Vector2 = units[target].p
	var score: float = absf(point.distance_to(enemy) - preferred_range(u)) * 2.4 + point.distance_to(u.p) * 0.28
	var ally := ally_index(u)
	if ally >= 0:
		var separation: float = point.distance_to(units[ally].p)
		score += maxf(0, 110.0 - separation) * 1.8
		# One anchor and one flanker avoids both endlessly chasing each other's angle.
		if u.member == 1 and (units[ally].target == target or units[ally].p.distance_to(enemy) < SHOT_RANGE):
			var angle_gap: float = absf((point - enemy).angle_to(units[ally].p - enemy))
			score += maxf(0, deg_to_rad(55) - angle_gap) * 160.0
	return score

func prepare_reposition(u: Dictionary, target: int, visible: Array) -> bool:
	var goal := choose_goal(u, visible)
	if goal.distance_to(u.p) < 45 or position_score(u, target, u.p) - position_score(u, target, goal) < 32: return false
	var old_distance: float = u.p.distance_to(units[target].p)
	u.target = target
	u.action_goal = goal
	u.action_left = clampf(u.p.distance_to(goal) / ENGAGE_SPEED + 0.5, 0.8, 2.4)
	u.repath = 0.0
	u.avoid_left = 0.0
	u.intent = "战术换位"
	u.phase = u.intent
	u.reason = "贴近压迫" if old_distance > preferred_range(u) + 35 else ("拉开射击距离" if old_distance < preferred_range(u) - 35 else "与队友错开角度，争取侧面射位")
	u.reason += "；理想距离 %.1f米，持续前往绿色目标点" % (preferred_range(u) / 80)
	return true

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
		u.action_left = clampf(u.cooldown, 0.3, 0.65)
		u.path = PackedVector2Array()
		u.avoid_left = 0.0
		u.intent = "战斗走位"
		u.phase = u.intent
		u.reason = "公共CD或精力恢复中，侧移保持射线"
		return true
	return false

func recovery_duration(skill: String) -> float:
	if skill in Tactics.LINES: return 1.0
	if skill in ["强力射击", "落岩", "震山"]: return 0.8
	if skill == "短冲刺": return 0.45
	return 0.45

func begin_shot(u: Dictionary, target: int, skill: String) -> void:
	if not can_use_skill(u, skill): return
	u.energy -= energy_cost(skill)
	ActionTimeline.begin(u, float(Tactics.MAGIC.get(skill, {}).get("cast", 0.0)), energy_cost(skill), attack_cooldown(skill))
	u.release_lock_frames = int(Tactics.MAGIC.get(skill, {}).get("release_frames", ActionTimeline.RELEASE_LOCK_FRAMES))
	u.recovery_frames = ActionTimeline.frames(recovery_duration(skill))
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
	u.timer = u.stage_frames * STEP

func attack_cooldown(skill: String) -> float:
	if skill in Tactics.MAGIC: return float(Tactics.MAGIC[skill].cd)
	return float({"点射": 1.5, "标记弹": 5.0, "强力射击": 6.0, "压制射击": 6.0, "协同追击": 5.0}.get(skill, 0.0))

func advance_dodge(u: Dictionary, dt: float) -> void:
	if u.dodge_frames <= 0: u.dodge_frames = ActionTimeline.frames(u.dodge)
	u.phase = "侧闪"
	var next: Vector2 = u.p + u.dodge_dir * DODGE_SPEED * dt
	if movement_is_free(u, next) and not blocked(u.p, next): u.p = next
	u.dodge_frames = maxi(0, u.dodge_frames - 1)
	u.dodge = u.dodge_frames * STEP
	if u.dodge_frames == 0:
		u.phase = "移动"
		u.intent = "重新决策"
		u.action_left = 0.0
		u.repath = 0.0
		u.rule_kind = ""
		u.rule_slot = -1

func cancel_for_dodge(u: Dictionary) -> void:
	var refund := ActionTimeline.refundable(u)
	var cancelled: String = u.active_skill
	var previous: String = u.get("action_stage", "")
	if u.rule_slot >= 0 and not previous.is_empty():
		var trace: Array = u.trace_ap if u.rule_kind == "active" else u.trace_pp
		trace[u.rule_slot] = "前摇取消·退%d" % refund if previous == ActionTimeline.WINDUP else "后摇已取消"
	if previous.is_empty(): previous = u.phase
	if refund > 0:
		u.energy = minf(100.0, u.energy + refund)
		if cancelled in ["天穹贯穿", "星火轰炸"]: u.ult_charge = 100.0
	ActionTimeline.clear(u)
	u.timer = 0.0
	u.shot_count = 0
	u.action_left = 0.0
	u.dash_recovery = false
	u.avoid_left = 0.0
	u.path = PackedVector2Array()
	u.goal = u.p
	u.action_goal = u.p
	u.last_cancel = "%s · %s取消 · 退还%d精力" % [cancelled, previous, refund]
	u.last_cancel_frame = logic_frame
	if not previous.is_empty(): log_event("%s%d · 侧闪：%s" % ["蓝" if u.team == 0 else "红", u.member + 1, u.last_cancel])

func move_unit(u: Dictionary, goal: Vector2, dt: float) -> void:
	if u.intent == "战斗走位":
		var step_to: Vector2 = u.p.move_toward(goal, COMBAT_STEP_SPEED * (0.6 if u.slow > 0 else 1.0) * energy_speed(u) * dt)
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
		if direct_path_free(u, goal):
			u.path = PackedVector2Array([goal])
		elif not nav.is_point_solid(start) and not nav.is_point_solid(end):
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
		var facing: float = (units[u.target].p - u.p).angle() if u.intent == "战术换位" and u.target >= 0 and not blocked(u.p, units[u.target].p) else direction.angle()
		u.angle = rotate_toward(u.angle, facing, dt * 5)
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

func direct_path_free(u: Dictionary, goal: Vector2) -> bool:
	# Do not detour through an arbitrary nav-cell center on an unobstructed floor.
	# Besides smoother movement, this avoids opposite rounding at mirrored cell edges.
	var samples := maxi(1, ceili(u.p.distance_to(goal) / 8.0))
	for sample in range(1, samples + 1):
		if not movement_is_free(u, u.p.lerp(goal, sample / float(samples))): return false
	return true

func add_impulse(u: Dictionary, velocity: Vector2) -> void:
	u.impulse = (u.impulse + velocity).limit_length(260.0)

func beam_push_direction(beam: Dictionary, u: Dictionary) -> Vector2:
	var forward: Vector2 = (beam.end - beam.p).normalized()
	var side := forward.orthogonal()
	var offset: float = (u.p - beam.p).dot(side)
	var sign_value: float = signf(offset) if absf(offset) > 0.1 else (1.0 if u.member == 0 else -1.0)
	return (forward * 0.35 + side * sign_value * 0.94).normalized()

func apply_forced_motion(u: Dictionary, dt: float) -> void:
	# Sustain the push only while an initially hit body still touches the live beam.
	# Damage is resolved once by the hazard, never again by this movement effect.
	for beam in blasts:
		if beam.kind != "beam" or beam.life <= 0 or u.uid not in beam.get("push_targets", []): continue
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(u.p, beam.p, beam.end)
		if nearest.distance_to(u.p) <= RADIUS + beam.radius and not blocked(beam.p, u.p):
			add_impulse(u, beam_push_direction(beam, u) * 1100.0 * dt)
	var steps := maxi(1, int(ceil((u.impulse + u.blast_impulse).length() * dt / 4.0)))
	for step in range(steps):
		var candidate: Vector2 = u.p + (u.impulse + u.blast_impulse) * dt / steps
		var normal := forced_collision_normal(u.p, candidate)
		if not normal.is_zero_approx():
			u.impulse = u.impulse.bounce(normal) * 0.72
			u.blast_impulse = u.blast_impulse.bounce(normal) * 0.72
			continue
		var collided := false
		for other in units:
			if other.uid == u.uid or other.hp <= 0 or candidate.distance_to(other.p) >= RADIUS * 2: continue
			collided = true
			var body_normal: Vector2 = (u.p - other.p).normalized()
			var velocity: Vector2 = u.impulse + u.blast_impulse
			if velocity.dot(body_normal) < 0:
				var key := "%d:%d" % [mini(u.uid, other.uid), maxi(u.uid, other.uid)]
				if not body_pairs.has(key):
					body_pairs[key] = true
					body_impacts.append({"uid": other.uid, "velocity": body_normal * velocity.dot(body_normal) * 0.35})
					effects.append({"p": (u.p + other.p) * 0.5, "life": 0.18, "color": GOLD})
				u.impulse = Vector2.ZERO
				u.blast_impulse = velocity.bounce(body_normal) * 0.55
			break
		if collided: continue
		u.p = candidate
	u.blast_impulse *= exp(-3.5 * dt)
	if u.blast_impulse.length() < 1.0: u.blast_impulse = Vector2.ZERO
	u.impulse *= exp(-6.0 * dt)
	if u.impulse.length() < 1.0: u.impulse = Vector2.ZERO

func forced_collision_normal(origin: Vector2, candidate: Vector2) -> Vector2:
	var bounds := safe_rect().grow(-RADIUS - 1)
	if candidate.x < bounds.position.x: return Vector2.RIGHT
	if candidate.x > bounds.end.x: return Vector2.LEFT
	if candidate.y < bounds.position.y: return Vector2.DOWN
	if candidate.y > bounds.end.y: return Vector2.UP
	for wall in walls:
		var solid := wall.grow(RADIUS + 1)
		if not solid.has_point(candidate): continue
		if origin.x <= solid.position.x: return Vector2.LEFT
		if origin.x >= solid.end.x: return Vector2.RIGHT
		if origin.y <= solid.position.y: return Vector2.UP
		return Vector2.DOWN
	return Vector2.ZERO

func movement_is_free(u: Dictionary, next: Vector2) -> bool:
	if not valid_arena_position(next): return false
	for other in units:
		if other.uid != u.uid and other.hp > 0 and next.distance_to(other.p) < RADIUS * 2: return false
	return true

func update_attack(u: Dictionary, dt: float) -> void:
	# Coarse calls are only used by diagnostics; live simulation always passes STEP.
	for tick in range(ActionTimeline.frames(dt)):
		if not ActionTimeline.busy(u):
			# Compatibility for fixtures that explicitly put a unit in recovery.
			if u.phase == "收招": ActionTimeline.enter(u, ActionTimeline.RECOVERY, ActionTimeline.frames(u.timer))
			else: return
		advance_attack_frame(u)

func enter_attack_recovery(u: Dictionary, seconds: float) -> void:
	ActionTimeline.enter(u, ActionTimeline.RECOVERY, ActionTimeline.frames(seconds))
	u.phase = "收招"

func attack_aligned(u: Dictionary) -> bool:
	if u.active_skill in Tactics.PATTERNS or u.active_skill in ["天穹贯穿", "星火轰炸"]: return true
	if u.target < 0 or units[u.target].hp <= 0: return false
	var target: Dictionary = units[u.target]
	if blocked(u.p, target.p) or u.p.distance_to(target.p) > SHOT_RANGE: return false
	var desired: float = (target.p - u.p).angle()
	u.angle = rotate_toward(u.angle, desired, STEP * 6)
	return absf(angle_difference(u.angle, desired)) <= 0.01

func advance_attack_frame(u: Dictionary) -> void:
	if u.action_stage == ActionTimeline.WINDUP:
		if u.active_skill not in Tactics.PATTERNS and u.active_skill not in ["天穹贯穿", "星火轰炸"] and (u.target < 0 or units[u.target].hp <= 0 or blocked(u.p, units[u.target].p) or u.p.distance_to(units[u.target].p) > SHOT_RANGE):
			enter_attack_recovery(u, 0.15)
			return
		var aligned := attack_aligned(u)
		if ActionTimeline.tick(u) and aligned:
			var burst: int = int(Tactics.MAGIC.get(u.active_skill, {}).get("hits", 1))
			var interval := ActionTimeline.frames(float(Tactics.MAGIC.get(u.active_skill, {}).get("interval", 0.24)))
			ActionTimeline.enter(u, ActionTimeline.RELEASE, u.release_lock_frames + (burst - 1) * interval)
			u.phase = "释放硬直"
		return
	if u.action_stage == ActionTimeline.RELEASE:
		var burst: int = int(Tactics.MAGIC.get(u.active_skill, {}).get("hits", 1))
		var interval := ActionTimeline.frames(float(Tactics.MAGIC.get(u.active_skill, {}).get("interval", 0.24)))
		if u.shot_count < burst and u.release_elapsed >= u.shot_count * interval:
			if not attack_aligned(u):
				if u.target < 0 or units[u.target].hp <= 0 or blocked(u.p, units[u.target].p) or u.p.distance_to(units[u.target].p) > SHOT_RANGE:
					if u.action_committed: finish_spell(u, u.active_skill)
					enter_attack_recovery(u, 0.15)
				return
			if not u.action_committed:
				u.action_committed = true
				if u.action_cd > 0: u.skill_cds[u.active_skill] = u.action_cd
			emit_attack(u)
			u.phase = "释放硬直"
		u.release_elapsed += 1
		if ActionTimeline.tick(u): enter_attack_recovery(u, u.recovery_frames * STEP)
		return
	if u.action_stage == ActionTimeline.RECOVERY:
		if ActionTimeline.tick(u):
			ActionTimeline.clear(u)
			u.phase = "移动"
			u.intent = "重新决策"
			u.rule_kind = ""
			u.rule_slot = -1

func emit_attack(u: Dictionary) -> void:
	if u.active_skill in ["天穹贯穿", "星火轰炸"]:
		emit_ultimate_effects(u)
		u.shot_count = 1
		return
	if u.active_skill in Tactics.PATTERNS:
		release_pattern(u)
		u.shot_count = 1
		return
	var direction := Vector2.from_angle(u.angle)
	var projectile_speed := ROCK_SPEED if u.active_skill in ["落岩", "震山"] else (BASIC_BULLET_SPEED if u.active_skill == "点射" else BULLET_SPEED)
	bullets.append({"p": u.p + direction * (RADIUS + 4), "v": direction * projectile_speed, "team": u.team, "life": SHOT_RANGE / projectile_speed, "true_damage": magic_element(u.active_skill) == "火", "element": magic_element(u.active_skill), "thorns": u.active_skill == "荆棘", "damage": shot_damage(u.active_skill), "source": u.uid, "skill": u.active_skill, "mark": u.active_skill == "标记弹", "heavy": u.active_skill == "强力射击", "slow": u.active_skill == "压制射击"})
	add_impulse(u, -direction * (105.0 if u.active_skill in ["落岩", "震山", "强力射击"] else 55.0))
	shots += 1
	u.shot_count += 1
	u.fire_flash = 0.18
	if u.shot_count >= int(Tactics.MAGIC.get(u.active_skill, {}).get("hits", 1)): finish_spell(u, u.active_skill)

func update_bullets(dt: float) -> void:
	wall_damage.clear()
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
		var wall_hit := first_wall_hit(old, next)
		var victim := -1
		var earliest: float = wall_hit.get("distance", INF)
		for i in range(units.size()):
			var u: Dictionary = units[i]
			if u.hp <= 0 or u.team == b.team: continue
			var segment: Vector2 = next - old
			var length: float = segment.length()
			if length <= 0: continue
			var direction := segment / length
			var offset: Vector2 = old - u.p
			var along: float = offset.dot(direction)
			var discriminant: float = along * along - (offset.length_squared() - RADIUS * RADIUS)
			if discriminant < 0: continue
			var enter: float = maxf(0, -along - sqrt(discriminant))
			if -along + sqrt(discriminant) >= 0 and enter <= length and enter < earliest:
				earliest = enter
				victim = i
		if victim >= 0:
			var u: Dictionary = units[victim]
			damage[victim] += maxf(0, float(b.get("damage", 1.0)) + (6.0 if b.get("heavy", false) and u.marked > 0 else 0.0) - (6.0 if u.guard > 0 and not b.get("true_damage", false) else 0.0))
			add_impulse(u, b.v.normalized() * clampf(65.0 + float(b.get("damage", 1.0)) * 4.0, 70.0, 170.0))
			if b.get("mark", false): marks[victim] = true
			if b.get("slow", false): slows[victim] = true
			if b.get("thorns", false): thorns[victim] = true
			if b.get("skill", "") not in ["协同追击", "追风"]:
				hit_events.append({"source": b.get("source", -1), "team": b.team, "target": victim, "life": 0.8})
			hits += 1
			b.life = -1
			effects.append({"p": u.p, "life": 0.22, "color": Color.WHITE})
		elif not wall_hit.is_empty():
			queue_wall_damage(wall_hit.id, float(b.get("damage", 1.0)))
			b.life = -1
			effects.append({"p": wall_hit.p, "life": 0.22, "color": GOLD})
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
	apply_wall_damage()

func end_round(winner: int, reason: String) -> void:
	if finished: return # Record the result once; simulation keeps running.
	ultimate_aim = -1
	winner_team = winner
	win_reason = reason
	finished = true
	result = ("平局" if winner < 0 else ("蓝方获胜" if winner == 0 else "红方获胜")) + "\n" + reason
	log_event(reason)

func log_event(message: String) -> void:
	logs.push_front("F%05d · %.1fs  %s" % [logic_frame, ROUND_TIME - clock, message])
	if logs.size() > 3: logs.resize(3)

func refresh_ui() -> void:
	status_label.text = "对称歼灭  ·  %04.1f 秒    |    帧 %d · 60Hz" % [maxf(clock, 0), logic_frame]
	if not started: status_label.text = "开局布阵  ·  8×8 站位    |    双方可摆放 · 开战后连续移动"
	start_button.text = "暂停  [空格]" if running else ("继续  [空格]" if started else "开始交战  [空格]")
	result_label.text = result
	log_label.text = "\n".join(logs)
	subtitle.text = "蓝：%s    vs    红：%s  ·  基础作战 + 技能策略" % [Tactics.NAMES[team_presets[0]], Tactics.NAMES[team_presets[1]]]
	var u: Dictionary = units[editor_unit]
	character_label.text = "%s %d   /   HP %d · 精力 %d · %s" % ["蓝方" if u.team == 0 else "红方", u.member + 1, u.hp, u.energy, action_state_label(u) if u.hp > 0 else "已倒下"]
	for uid in range(roster_buttons.size()):
		var bot: Dictionary = units[uid]
		var card: Button = roster_buttons[uid]
		var color := BLUE if uid < 2 else RED
		card.text = "%s %d   ·   %s\nHP %d   /   EN %d" % ["蓝方" if uid < 2 else "红方", uid % 2 + 1, bot.phase if bot.hp > 0 else "倒下", bot.hp, bot.energy]
		card.add_theme_color_override("font_color", color)
		card.add_theme_stylebox_override("normal", make_box(Color("304052") if uid == editor_unit else Color("1a2534"), GOLD if uid == editor_unit else Color("39465a")))
	info_label.text = "%s%d · HP %d · %s\n%s\n标记 %.1fs / 减速 %.1fs / 荆棘 %.1fs / 护盾 %d" % ["蓝" if u.team == 0 else "红", u.member + 1, u.hp, u.phase if u.hp > 0 else "已倒下", u.reason, u.marked, u.slow, u.thorns, u.shield]
	info_label.text += "\n精力 %d/100 · 公共施法CD %.1fs · 移速 %d%%" % [u.energy, u.cooldown, energy_speed(u) * 100]
	info_label.text += "\n逻辑帧 %d · 本帧 %s · 触发 %d 次" % [logic_frame, u.frame_branch, u.frame_triggers]
	if u.has("last_cancel"): info_label.text += "\n上次取消（帧%d）：%s" % [u.last_cancel_frame, u.last_cancel]
	for rule in loadouts[editor_unit].reaction:
		if rule[0] == "侧闪":
			var remaining := float(u.skill_cds.get("侧闪", 0.0))
			info_label.text += "\n侧闪：" + ("冷却 %.1f秒" % remaining if remaining > 0 else "就绪（前摇退款取消 / 后摇取消 / 释放硬直禁用）")
			break
	for row in editor_rows:
		var occupied: bool = row.slot >= 0
		var active: bool = occupied and rule_is_executing(u, row.kind, row.slot)
		var trace: Array = u.trace_ap if row.kind == "active" else u.trace_pp
		row.state.text = ("▶ " + action_state_label(u)) if active else (trace[row.slot] if occupied else "空槽")
		row.state.tooltip_text = u.reason if active else ("上次实际检查：" + trace[row.slot] if occupied else "添加技能后自动归入AP或PP")
		row.frame.add_theme_stylebox_override("panel", make_box(Color("453b29") if active else Color("1d2939") if occupied else Color("111a26"), GOLD if active else Color("344358") if occupied else Color("28364a")))
		row.state.modulate = GOLD if active else Color("91a1b0")

func action_state_label(u: Dictionary) -> String:
	if u.dodge > 0: return "侧闪 %df" % u.dodge_frames
	if u.get("action_stage", "") == ActionTimeline.WINDUP and u.stage_frames == 0: return "前摇·转向"
	if ActionTimeline.busy(u): return "%s %df" % [u.action_stage, u.stage_frames]
	return u.phase

func _draw() -> void:
	arena_view.render(self)

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
		var target := (1 - team) * 2
		units[target].p = Vector2(200, 50)
		begin_shot(shooter, target, "点射")
		shooter.angle = PI
		for tick in range(25): update_attack(shooter, 1.0 / 60)
		assert(shots == 0, "Timer expiry must never authorize an unaligned shot")
		for tick in range(10): update_attack(shooter, 1.0 / 60)
		assert(shots > 0, "Aligned gun must fire")
		assert(absf(bullets[0].v.angle()) < 0.01)
	pattern_fixture()
	begin_shot(units[0], 2, "风刃")
	update_attack(units[0], STEP * 2)
	assert(shots == 1)
	units[2].p = Vector2(100, 470)
	update_attack(units[0], STEP * 14)
	assert(shots == 1, "Burst follow-up must reacquire its moving target")
	update_attack(units[0], STEP * 20)
	assert(shots == 2)
	pattern_fixture()
	units[0].p = Vector2(250, 170)
	units[2].p = Vector2(380, 170)
	begin_shot(units[0], 2, "点射")
	update_attack(units[0], STEP * 2)
	assert(shots == 0 and units[0].phase == "收招", "Cover prevents emission and ends the invalid action")
	pattern_fixture()
	begin_shot(units[0], 2, "点射")
	update_attack(units[0], STEP)
	assert(shots == 0 and units[0].action_stage == ActionTimeline.RELEASE)
	update_attack(units[0], STEP)
	assert(shots == 1, "Aligned gun emits on the first release frame")
	print("AIM TESTS PASSED: both teams, turning, explicit release frame, burst tracking, cover abort")

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
		"自己精力≥80": return u.energy >= 80
		"自己精力≥50": return u.energy >= 50
		"自己精力≤30": return u.energy <= 30
		"敌人距离≥3米": return target >= 0 and u.p.distance_to(units[target].p) >= 240
		"敌人正在攻击队友":
			var ally := ally_index(u)
			return target >= 0 and ally >= 0 and units[target].target == ally and units[target].phase in ["吟唱", "瞄准", "点射", "释放硬直"]
		"队友正在被瞄准":
			var ally := ally_index(u)
			return ally >= 0 and incoming_pressure(units[ally], contacts(u.team)) > 0
		"自己被两人瞄准": return incoming_pressure(u, contacts(u.team)) >= 2
		"自己HP≤50": return u.hp <= MAX_HP * 0.5
		"队友HP≤50":
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
			if ally >= 0 and units[ally].target in candidates and units[ally].phase in ["吟唱", "瞄准", "点射", "释放硬直", "收招"]:
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
	if deciding_frame:
		u.frame_triggers += 1
		u.frame_branch = ("AP：" if kind == "主动" else "PP：") + skill
	if kind == "主动":
		u.trace_ap[slot] = "已选中（上次检查）"
	else:
		u.trace_pp[slot] = "已选中（上次检查）"
	var display_slot := slot + 1
	if kind == "反应":
		for rule in loadouts[u.uid].active:
			if rule[0] != "留空": display_slot += 1
	u.rule = "%s%d %s" % [kind, display_slot, skill]
	u.rule_kind = "active" if kind == "主动" else "reaction"
	u.rule_slot = slot
	u.reason = "命中%s规则%d：%s" % [kind, display_slot, skill]
	u.rule_flash = 1.4
	u.intent = skill
	var key := "%d:%s" % [u.uid, skill]
	reaction_counts[key] = int(reaction_counts.get(key, 0)) + 1
	if skill not in Tactics.BASIC_ACTIVE and skill not in Tactics.BASIC_REACTIONS and skill != "点射":
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

func new_rule_trace(message: String) -> Array:
	var trace: Array = []
	trace.resize(Tactics.RULE_LIMIT)
	trace.fill(message)
	return trace

func try_active(u: Dictionary, visible: Array, before_slot := -1) -> bool:
	var rows: Array = loadouts[u.uid].active
	u.trace_ap = new_rule_trace("未检查（上方优先）")
	u.reason = "没有配置主动策略"
	var first_skip := ""
	for slot in range(rows.size() if before_slot < 0 else mini(before_slot, rows.size())):
		var rule: Array = rows[slot]
		var skill: String = rule[0]
		u.trace_ap[slot] = "留空" if skill == "留空" else "无符合条件的目标"
		if skill == "留空": continue
		if skill in Tactics.BASIC_ACTIVE:
			if basic_action(u, visible, rule):
				var intent: String = u.intent
				var reason: String = u.reason
				record_rule(u, "主动", slot, skill)
				u.intent = intent
				u.reason += "；" + reason
				return true
			u.trace_ap[slot] = "无合法射位" if skill == "普通攻击" else "情境/条件未满足"
			if skill == "普通攻击" and rule_target(u, visible, rule, true) >= 0:
				u.trace_ap[slot] = "精力不足" if u.energy < 15 else ("公共CD中" if u.cooldown > 0 else "技能CD中")
			continue
		if float(u.skill_cds.get(skill, 0.0)) > 0:
			u.trace_ap[slot] = "技能CD中"
			if first_skip.is_empty(): first_skip = "%s冷却中" % skill
			continue
		var shooting := skill in Tactics.MAGIC or skill in ["标记弹", "强力射击", "压制射击"]
		if not can_use_skill(u, skill):
			u.trace_ap[slot] = "精力不足" if u.energy < energy_cost(skill) else "公共CD中"
			if first_skip.is_empty(): first_skip = "精力不足" if u.energy < energy_cost(skill) else "公共施法CD中"
			continue
		var target := rule_target(u, visible, rule, shooting)
		if target < 0:
			if first_skip.is_empty(): first_skip = "%s暂无符合条件的可用目标" % skill
			continue
		if skill == "短冲刺" and u.p.distance_to(units[target].p) < 140:
			u.trace_ap[slot] = "距离已足够近"
			continue
		if shooting:
			begin_shot(u, target, skill)
		else:
			var away: Vector2 = (u.p - units[target].p).normalized()
			var goal: Vector2 = u.p
			if skill == "绕侧": goal += away.orthogonal() * (95 if u.member == 0 else -95)
			elif skill == "后撤": goal += away * 100
			elif skill == "短冲刺": goal -= away * minf(90, u.p.distance_to(units[target].p) - 120)
			u.action_goal = nearest_legal_goal(goal)
			if u.p.distance_to(u.action_goal) < 15:
				u.trace_ap[slot] = "没有有效移动目的地"
				continue
			u.energy -= energy_cost(skill)
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
		if enemy.phase not in ["吟唱", "瞄准", "点射", "释放硬直"] or enemy.target < 0: continue
		if units[enemy.target].uid != u.uid or blocked(enemy.p, u.p): continue
		if enemy.p.distance_to(u.p) <= SHOT_RANGE: threats.append(index)
	# A projectile remains a threat after its shooter has entered recovery.
	for b in perceived_bullets if deciding_frame else bullets:
		if b.team == u.team or b.life <= 0: continue
		var near := Geometry2D.get_closest_point_to_segment(u.p, b.p, b.p + b.v * minf(0.55, b.life))
		if near.distance_to(u.p) > RADIUS + 4 or blocked(b.p, u.p): continue
		for index in visible:
			if units[index].uid == b.get("source", -1) and index not in threats: threats.append(index)
	for h in perceived_hazards if deciding_frame else hazards:
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

func try_reaction(u: Dictionary, visible: Array, defensive_only := false, dodge_only := false) -> bool:
	var threats := threats_to(u, visible)
	var ally := ally_index(u)
	var rows: Array = loadouts[u.uid].reaction
	u.trace_pp = new_rule_trace("未检查（上方优先）")
	for slot in range(rows.size()):
		var rule: Array = rows[slot]
		var skill: String = rule[0]
		if dodge_only and skill != "侧闪":
			u.trace_pp[slot] = "当前动作仅允许侧闪插入"
			continue
		if skill == "侧闪" and (not ActionTimeline.can_dodge(u) or u.dodge > 0):
			u.trace_pp[slot] = "释放硬直中，不能侧闪" if u.dodge <= 0 else "正在侧闪"
			continue
		if skill == "留空":
			u.trace_pp[slot] = "留空"
			continue
		if float(u.skill_cds.get(skill, 0.0)) > 0:
			u.trace_pp[slot] = "技能CD中"
			continue
		if skill == "步行避险":
			var candidates: Array = []
			for danger in perceived_dangers(u, visible):
				if danger.source in visible and danger_contains(danger, u.p) and (danger.kind == "area" or danger.get("walk_evade", false)):
					if danger.source not in candidates: candidates.append(danger.source)
			if rule_target(u, candidates, rule, false) < 0 or not prepare_tactical_escape(u, candidates):
				u.trace_pp[slot] = "无符合条件的安全避险路径"
				continue
			record_rule(u, "反应", slot, skill)
			u.intent = "规避预警"
			return true
		var available_energy: float = u.energy + (ActionTimeline.refundable(u) if skill == "侧闪" else 0.0)
		var usable: bool = available_energy >= energy_cost(skill) and (not uses_public_cd(skill) or u.cooldown <= 0)
		if not usable:
			u.trace_pp[slot] = "精力不足" if u.energy < energy_cost(skill) else "公共CD中"
			continue
		u.trace_pp[slot] = "事件/条件未满足"
		if defensive_only and skill not in ["侧闪", "架枪防御", "步行避险"]: continue
		if skill in ["回春", "灵木护佑"]:
			var recipient := heal_target(u, rule)
			if recipient < 0: continue
			u.energy -= energy_cost(skill)
			finish_spell(u, skill)
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
			if choice.is_empty():
				u.trace_pp[slot] = "无可用闪避路径/窗口"
				continue
			var lateral: Vector2 = (choice.point - u.p).normalized()
			cancel_for_dodge(u)
			u.evade_source = choice.source
			u.counter_left = 3.0
			u.dodge_frames = ActionTimeline.frames(DODGE_DISTANCE / DODGE_SPEED)
			u.dodge = u.dodge_frames * STEP
			u.dodge_dir = lateral
			u.phase = "侧闪"
			u.active_skill = "侧闪"
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
			if ally >= 0: links.append({"a": units[ally].p, "b": u.p, "life": 0.65, "color": Color("76f0a9")})
		elif skill in ["焰返", "震山"]:
			begin_shot(u, target, skill)
		if skill in ["侧闪", "架枪防御", "掩护队友"]:
			u.energy -= energy_cost(skill)
			if skill == "掩护队友": finish_spell(u, skill)
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
	rebuild_editor()
	edit.item_selected.emit(Tactics.all_skills().find("标记弹"))
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
	loadouts[0] = Tactics.basics()
	assert(try_active(units[0], [2, 3]))
	assert(units[0].active_skill == "点射" and units[0].phase == "瞄准", "Editable basic attack performs ordinary shots")
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
	assert(finished and shots == 0 and hits == 0, "No hidden attacks or movement after all rules are removed")
	reset_round()
	for i in range(4): loadouts[i] = Tactics.basics()
	for tick in range(3602):
		if finished: break
		simulate(STEP)
	assert(finished and shots > 0 and hits > 0, "Editable basic rules search, engage and fight")
	print("BASIC RULES: editable rules completed a match, shots=", shots)

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
	loadouts[0].reaction.append(["掩护队友", "无", "无"])
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
	assert(not running and logic_frame == 1 and is_equal_approx(clock, ROUND_TIME - STEP))
	step_forward(12)
	assert(logic_frame == 13 and is_equal_approx(clock, ROUND_TIME - STEP * 13))

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
		if condition not in ["无", "优先低血量", "自己HP≤50", "队友HP≤50", "自己精力≥80", "自己精力≥50", "自己精力≤30"]: return -1
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
	loadouts[0].reaction.append(["回春", "优先低血量", "无"])
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
		if evade: loadouts[0].reaction.append(["侧闪", "无", "无"])
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
	if skill == "星火轰炸": return 0.95
	return float(Tactics.MAGIC[skill].cast) + BLAST_FLIGHT

func release_pattern(u: Dictionary) -> void:
	finish_spell(u, u.active_skill)
	u.fire_flash = 0.18
	shots += 1
	var skill: String = u.active_skill
	var data: Dictionary = Tactics.MAGIC[skill]
	if skill in Tactics.AREAS:
		u.blast_impulse = (u.blast_impulse - Vector2.from_angle(u.lock_angle) * 140.0).limit_length(3150.0)
		u.blast_lock = 0.22
	else:
		add_impulse(u, -Vector2.from_angle(u.lock_angle) * (115.0 if skill in Tactics.LINES else 80.0))
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
		# Accumulate environment damage; destruction is applied after this simulation tick.
		if h.kind == "beam":
			var direction: Vector2 = (h.end - h.p).normalized()
			var hit := first_wall_hit(h.p, h.end + direction * 2)
			if not hit.is_empty(): queue_wall_damage(hit.id, h.damage)
		else:
			for w in wall_states:
				if w.hp > 0 and h.p.distance_to(h.p.clamp(w.rect.position, w.rect.end)) <= h.radius:
					queue_wall_damage(w.id, h.damage)
		h.push_targets = []
		for i in range(units.size()):
			var u: Dictionary = units[i]
			if u.hp <= 0 or u.team == h.team: continue
			var contact: bool = false
			if h.kind == "beam":
				contact = Geometry2D.get_closest_point_to_segment(u.p, h.p, h.end).distance_to(u.p) <= RADIUS + h.radius and not blocked(h.p, u.p)
			else:
				contact = area_overlaps_body(h.p, h.radius, u.p)
			if contact:
				h.push_targets.append(u.uid)
				if h.kind == "beam":
					add_impulse(u, beam_push_direction(h, u) * 120.0)
				else:
					var away: Vector2 = (u.p - h.p).normalized()
					if away.is_zero_approx(): away = Vector2.from_angle(u.angle + PI)
					u.blast_impulse = (u.blast_impulse + away * (380.0 if h.get("skill", "") == "烈焰爆破" else 320.0)).limit_length(650.0)
				u.blast_lock = 0.22
				damage[i] += maxf(0, h.damage - (6 if u.guard > 0 and not h.get("true_damage", h.kind == "beam") else 0))
				hits += 1
				hit_events.append({"source": h.source, "team": h.team, "target": i, "life": 0.8})
		var fx: Dictionary = h.duplicate()
		fx.duration = 0.55 if h.kind == "beam" else 0.3
		fx.life = fx.duration
		blasts.append(fx)
	hazards = hazards.filter(func(h): return h.left > 0)

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
		if enemy.hp <= 0 or (enemy.phase != "吟唱" and not (enemy.get("action_stage", "") == ActionTimeline.RELEASE and not enemy.get("action_committed", false))): continue
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
	for h in perceived_hazards if deciding_frame else hazards:
		if h.kind == "area" and h.team != u.team:
			dangers.append({"kind": "area", "p": h.p, "radius": h.radius, "eta": h.left, "source": h.source})
	for b in perceived_bullets if deciding_frame else bullets:
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
			# Rotate candidate order with the actor, so mirrored actors break ties alike.
			var direction := Vector2.from_angle(u.angle + i * TAU / 24)
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
			if score < best_score - 0.000001:
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
	if choice.is_empty():
		return false
	if u.intent != "规避预警":
		var key := "%d:规避预警" % u.uid
		reaction_counts[key] = int(reaction_counts.get(key, 0)) + 1
	u.action_goal = choice.point
	u.action_left = 0.0
	u.intent = "规避预警"
	u.rule_kind = ""
	u.rule_slot = 0
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
	if enemy.phase != "收招" or not can_use_skill(u, "点射") or blocked(u.p, enemy.p) or u.p.distance_to(enemy.p) > SHOT_RANGE: return false
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
	# Explicit walking PP must leave a locked beam, without injecting counterattacks.
	pattern_fixture()
	loadouts[0] = {"active": [], "reaction": [["步行避险", "无", "无"]]}
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
	assert(escaped and not countered and units[0].hp == MAX_HP, "Configured walking PP dodges without injecting counter rules")
	# Already outside the beam should not move merely because it was targeted.
	pattern_fixture()
	loadouts[0] = {"active": [], "reaction": [["步行避险", "无", "无"]]}
	begin_shot(units[2], 0, "蓄能贯穿")
	units[2].timer = 0.8
	units[0].p.y += 90
	assert(not prepare_tactical_escape(units[0], [2]))
	# Two simultaneous landing zones: isolate walking from attack recoil into a zone.
	pattern_fixture()
	loadouts[0] = {"active": [], "reaction": [["步行避险", "无", "无"]]}
	units[0].cooldown = 2.0
	units[2].phase = "收招"
	units[2].timer = 10
	for point in [Vector2(100, 320), Vector2(100, 390)]:
		hazards.append({"kind": "area", "p": point, "radius": 40.0, "team": 1, "source": 2, "left": 1.3, "damage": 1.0})
	var choice := escape_destination(units[0], perceived_dangers(units[0], [2]), MOVE_SPEED)
	assert(not choice.is_empty())
	for d in perceived_dangers(units[0], [2]): assert(not danger_contains(d, choice.point))
	for tick in range(85): simulate(STEP)
	assert(units[0].hp == MAX_HP, "Configured walking PP escapes overlapping telegraphs")
	# An attack already in recovery cannot cancel for a free evade.
	pattern_fixture()
	loadouts[0] = {"active": [], "reaction": [["步行避险", "无", "无"]]}
	units[0].phase = "收招"
	units[0].timer = 1
	units[2].phase = "收招"
	units[2].timer = 10
	hazards.append({"kind": "area", "p": units[0].p, "radius": 40.0, "team": 1, "source": 2, "left": 0.1, "damage": 1.0})
	for tick in range(10): simulate(STEP)
	assert(units[0].hp == (MAX_HP - 1) and units[0].phase == "收招")
	print("EVASION PASSED: configured walking PP, no automatic counter priority, no false alarm, overlapping zones, action commitment")

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
	# Configured walking PP moves continuously, with no hidden fallback.
	pattern_fixture()
	begin_shot(units[2], 0, "蓄能贯穿")
	units[2].timer = 0.8
	units[0].cooldown = 0.25
	loadouts[0] = {"active": [], "reaction": [["步行避险", "无", "无"]]}
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

func run_tempo_tests() -> void:
	pattern_fixture()
	units[0].intent = "基础接敌"
	assert(is_equal_approx(unit_move_speed(units[0]), ENGAGE_SPEED))
	units[0].intent = "规避预警"
	assert(is_equal_approx(unit_move_speed(units[0]), MOVE_SPEED))
	assert(ENGAGE_SPEED > MOVE_SPEED and MOVE_SPEED > COMBAT_STEP_SPEED)
	pattern_fixture()
	units[2].p = Vector2(290, 320) # Already at ideal range: test small footwork, not relocation.
	units[2].phase = "收招"
	units[2].timer = 100.0
	units[0].cooldown = 0.55
	loadouts[0] = Tactics.basics()
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
	assert(units[0].phase == "移动" and is_equal_approx(units[0].cooldown, 2.3))
	print("TEMPO PASSED: continuous aimed footwork, ready attack and player AP preempt, cover safety, fast shotgun, committed laser")

func run_defense_tests() -> void:
	# A plain shot catches full-speed lateral running at common combat ranges.
	for distance in [150.0, 200.0, 260.0]:
		for move_speed in [COMBAT_STEP_SPEED, ENGAGE_SPEED]:
			pattern_fixture()
			units[2].p = Vector2(100 + distance, 320)
			begin_shot(units[0], 2, "点射")
			update_attack(units[0], STEP * 2)
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
		assert(units[2].hp == MAX_HP - 18)
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
		assert(units[2].hp == (MAX_HP - 10 if true_damage else MAX_HP - 4))
	# A basic attack cannot repeat faster than recovery + weapon pause.
	pattern_fixture()
	begin_shot(units[0], 2, "点射")
	update_attack(units[0], STEP * 3)
	assert(units[0].timer == 0.45)
	update_attack(units[0], 0.46)
	assert(is_equal_approx(units[0].cooldown, 1.8))
	print("EXPANSION PASSED: all 13 attacks emitted intended damage, new patterns/guard, heal+shield, true damage, basic cadence, 100HP")

func run_impact_tests() -> void:
	pattern_fixture()
	var start: Vector2 = units[0].p
	begin_shot(units[0], 2, "点射")
	update_attack(units[0], STEP * 3)
	for tick in range(20): apply_forced_motion(units[0], STEP)
	assert(units[0].p.x < start.x - 5 and units[0].p.x > start.x - 15)
	assert(units[0].phase == "收招", "Recoil must not cancel the action")
	for offset in [-8.0, 8.0]:
		pattern_fixture()
		units[2].p.y += offset
		start = units[2].p
		begin_shot(units[0], 2, "蓄能贯穿")
		units[0].lock_angle = 0.0
		update_attack(units[0], 1.11)
		update_bullets(STEP)
		assert(units[2].hp == MAX_HP - 22)
		var left_beam := false
		var speed_at_exit := 0.0
		for tick in range(90):
			apply_forced_motion(units[2], STEP)
			if absf(units[2].p.y - 320) > RADIUS + 7 and not left_beam:
				left_beam = true
				speed_at_exit = units[2].impulse.length()
			update_bullets(STEP)
		assert(left_beam and speed_at_exit > 20)
		assert(units[2].p.x > start.x + 5)
		assert((units[2].p.y - start.y) * offset > 0, "Push toward nearest side of beam")
		assert(units[2].impulse.length() < 2 and units[2].hp == MAX_HP - 22)
	# Wall, border and another body stop forced movement without overlap.
	for position in [Vector2(210, 160), Vector2(600, 320), Vector2(190, 320)]:
		pattern_fixture()
		units[0].p = position
		add_impulse(units[0], Vector2(260, 0))
		for tick in range(60):
			apply_forced_motion(units[0], STEP)
			assert(valid_arena_position(units[0].p))
			assert(units[0].p.distance_to(units[2].p) >= RADIUS * 2)
	print("IMPACT PASSED: physical recoil without action cancel; laser forward+nearest-side push, exit then decay, single damage; walls/borders/bodies")

func run_position_tests() -> void:
	pattern_fixture()
	units[0].p = Vector2(100, 320)
	units[2].p = Vector2(300, 320)
	loadouts[0] = Tactics.build([["霰弹", "无", "无"]], [])
	var close_goal := choose_goal(units[0], [2])
	loadouts[0] = Tactics.build([["抛射轰击", "无", "无"]], [])
	var far_goal := choose_goal(units[0], [2])
	assert(close_goal.distance_to(units[2].p) < 150)
	assert(far_goal.distance_to(units[2].p) > 210)
	assert(close_goal.distance_to(far_goal) > 60)
	# The second teammate deliberately opens a different attack angle.
	units[0].p = Vector2(100, 320)
	units[0].target = 2
	units[1].hp = MAX_HP
	units[1].p = Vector2(100, 380)
	var flank := choose_goal(units[1], [2])
	var before_angle: float = absf((units[1].p - units[2].p).angle_to(units[0].p - units[2].p))
	var after_angle: float = absf((flank - units[2].p).angle_to(units[0].p - units[2].p))
	assert(after_angle > before_angle + 0.2)
	assert(flank.distance_to(units[1].p) > 45)
	# Destination persists across normal updates; player AP can still take over.
	assert(prepare_reposition(units[1], 2, [2]))
	var goal: Vector2 = units[1].action_goal
	units[0].phase = "收招"; units[0].timer = 10
	units[2].phase = "收招"; units[2].timer = 10
	units[1].cooldown = 1.0
	for tick in range(12): simulate(STEP)
	assert(units[1].action_goal == goal and units[1].intent == "战术换位")
	loadouts[1] = Tactics.build([["后撤", "无", "无"]], [])
	simulate(STEP)
	assert(units[1].intent == "后撤")
	print("POSITION PASSED: close vs ranged goals, teammate opens angle, persistent destination, player AP preemption")

func run_blast_push_tests() -> void:
	for skill in Tactics.AREAS:
		pattern_fixture()
		units[2].p = Vector2(280, 320)
		hazards.append({"kind": "area", "skill": skill, "p": units[2].p - Vector2(20, 0), "origin": units[0].p, "radius": pattern_radius(skill), "left": 0.0, "damage": 18.0, "team": 0, "source": 0})
		update_bullets(STEP)
		assert(is_equal_approx(units[2].blast_impulse.length(), 380.0 if skill == "烈焰爆破" else 320.0))
		var path_length := 0.0
		for tick in range(120):
			var before: Vector2 = units[2].p
			apply_forced_motion(units[2], STEP)
			path_length += before.distance_to(units[2].p)
			assert(valid_arena_position(units[2].p))
		assert(path_length > 75 and path_length < 120 and units[2].hp == MAX_HP - 18)
		pattern_fixture()
		begin_shot(units[0], 2, skill)
		update_attack(units[0], Tactics.MAGIC[skill].cast + 0.01)
		assert(is_equal_approx(units[0].blast_impulse.length(), 140.0))
	# Wall faces reflect their normal component, keeping the tangent component.
	pattern_fixture()
	units[0].p = Vector2(240, 160)
	units[0].blast_impulse = Vector2(3400, 100)
	apply_forced_motion(units[0], STEP)
	assert(units[0].blast_impulse.x < 0 and units[0].blast_impulse.y > 0)
	assert(valid_arena_position(units[0].p))
	pattern_fixture()
	units[0].p = Vector2(600, 320)
	units[0].blast_impulse = Vector2(3400, 0)
	apply_forced_motion(units[0], STEP)
	assert(units[0].blast_impulse.x < 0 and valid_arena_position(units[0].p))
	for elapsed in [0, 20, 40, 59]:
		clock = ROUND_TIME - elapsed
		assert(safe_rect() == Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)))
	assert(walls[0].size.x <= 64.0 / 3)
	print("BLAST PUSH PASSED: reduced victim impulse and caster recoil, swept wall/border bounce, tangential motion, no shrinking, thin walls")

func run_body_bounce_tests() -> void:
	for ally in [false, true]:
		pattern_fixture()
		units[0].p = Vector2(180, 320)
		units[2].p = Vector2(240, 320)
		if ally: units[2].team = 0
		for u in units:
			u.phase = "收招"; u.timer = 10
		units[0].blast_impulse = Vector2(900, 0)
		var bounced := false
		var transferred := false
		for tick in range(20):
			simulate(STEP)
			bounced = bounced or units[0].blast_impulse.x < 0
			transferred = transferred or units[2].blast_impulse.x > 0
			assert(units[0].p.distance_to(units[2].p) >= RADIUS * 2)
		assert(bounced and transferred and units[2].p.x > 250)
		assert(units[0].hp == MAX_HP and units[2].hp == MAX_HP, "Body collision does not add damage")
	# High-speed head-on proposals must rebound without crossing or overlapping.
	pattern_fixture()
	units[0].p = Vector2(180, 320); units[2].p = Vector2(260, 320)
	for u in units:
		u.phase = "收招"; u.timer = 10
	units[0].blast_impulse = Vector2(1800, 0)
	units[2].blast_impulse = Vector2(-1800, 0)
	var head_on_bounced := false
	for tick in range(20):
		simulate(STEP)
		head_on_bounced = head_on_bounced or (units[0].blast_impulse.x < 0 and units[2].blast_impulse.x > 0)
		assert(units[0].p.x < units[2].p.x and units[0].p.distance_to(units[2].p) >= RADIUS * 2)
	assert(head_on_bounced)
	print("BODY BOUNCE PASSED: ally/enemy rebound, receiver displacement, head-on high speed, no overlap/crossing/extra damage")


func capture_deployment_preview() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/deployment-preview.png")
	get_tree().quit()

func capture_lifecycle_preview() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/lifecycle-preview.png")
	get_tree().quit()

func run_lifecycle_tests() -> void:
	preload("res://scripts/lifecycle_validation.gd").run(self)

func run_deployment_tests() -> void:
	blue_attacks = false
	deployment_cells = DEFAULT_DEPLOYMENT.duplicate()
	reset_round()
	# All 64 centers survive the 2.5D projection/inverse projection.
	for x in range(DEPLOY_GRID):
		for y in range(DEPLOY_GRID):
			var cell := Vector2i(x, y)
			assert(deployment_cell(arena_view.unproject(arena_view.project(deployment_center(cell)))) == cell)
	var original: Array = deployment_cells.duplicate()
	assert(not place_unit(0, Vector2i(-1, 0)))
	assert(not place_unit(0, Vector2i(8, 0)))
	assert(not place_unit(0, Vector2i(0, 8)))
	assert(not place_unit(0, Vector2i(3, 1)), "Wall/body overlap must reject placement")
	assert(not place_unit(0, Vector2i(1, 2)), "Occupied cell must reject placement")
	assert(deployment_cells == original)
	# Both teams may be placed; rejected attempts never change the last valid position.
	assert(place_unit(0, Vector2i(0, 0)))
	assert(place_unit(2, Vector2i(7, 7)))
	var placed: Vector2 = units[0].p
	assert(not place_unit(0, Vector2i(7, 7)))
	assert(units[0].p == placed)
	reset_round()
	assert(units[0].p == placed)
	assert(units[2].p == deployment_center(Vector2i(7, 7)))
	# The normal strategy-edit and preset flows reset the round but retain deployment.
	choose_editor_unit(0)
	edit_rule_cell(0, 1, "无")
	assert(units[0].p == placed)
	apply_preset(1, 0)
	assert(units[0].p == placed)
	blue_attacks = true
	reset_round()
	assert(units[0].p == Vector2(SIZE - placed.x, placed.y))
	assert(place_unit(0, Vector2i(4, 3)))
	reset_round()
	assert(units[0].p == deployment_center(Vector2i(4, 3)))
	blue_attacks = false
	reset_round()
	assert(units[0].p == deployment_center(Vector2i(3, 3)))
	# Starting, and then pausing, must lock placement; simulation remains continuous.
	toggle_running()
	assert(not place_unit(0, Vector2i(0, 0)))
	for tick in range(12): simulate(STEP)
	var moved_off_grid := false
	for u in units:
		if u.p.distance_to(deployment_center(deployment_cell(u.p))) > 0.01: moved_off_grid = true
	assert(moved_off_grid, "Combat movement must not snap to deployment cells")
	toggle_running()
	assert(not place_unit(0, Vector2i(0, 0)))
	reset_round()
	assert(place_unit(0, Vector2i(0, 0)))
	deployment_cells = DEFAULT_DEPLOYMENT.duplicate()
	reset_round()
	assert(units[0].p == Vector2(520, 200))
	# Exercise mouse event handlers at the raised model, not only placement helpers.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = arena_view.project(units[0].p, 25)
	_unhandled_input(press)
	assert(deployment_drag == 0)
	var motion := InputEventMouseMotion.new()
	motion.position = arena_view.project(deployment_center(Vector2i(5, 3)), 25)
	_input(motion)
	assert(deployment_cell(deployment_cursor) == Vector2i(5, 3))
	assert(units[0].p == Vector2(520, 200), "Drag preview must not commit early")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	_input(release)
	assert(deployment_drag == -1 and units[0].p == deployment_center(Vector2i(5, 3)))
	press.position = arena_view.project(deployment_center(Vector2i(0, 0)))
	_unhandled_input(press)
	assert(units[0].p == deployment_center(Vector2i(0, 0)), "Click-to-place must use ground coordinates")
	press.position = arena_view.project(units[0].p, 25)
	_unhandled_input(press)
	var cancel := InputEventKey.new()
	cancel.pressed = true
	cancel.keycode = KEY_ESCAPE
	_input(cancel)
	assert(deployment_drag == -1)
	_input(release)
	assert(units[0].p == deployment_center(Vector2i(0, 0)))
	assert(place_unit(0, Vector2i(4, 1)))
	blue_attacks = true
	reset_round()
	for u in units: assert(valid_position(u.p), "Mirrored placement must resolve wall obstruction")
	print("DEPLOYMENT PASSED: 64 projected cells, bounds/walls/occupancy, both teams, restart/edit/preset persistence, mirrored sides, combat lock and continuous movement")

func run_view_tests() -> void:
	for x in range(0, 641, 40):
		for y in range(0, 641, 40):
			var p := Vector2(x, y)
			assert(arena_view.unproject(arena_view.project(p)).distance_to(p) < 0.001)
			assert(arena_view.project(p, 48).is_equal_approx(arena_view.project(p) - Vector2(0, 48)))
	for radius in [24.0, 64.0, 80.0]:
		for n in range(64):
			var center := Vector2(320, 320)
			var point: Vector2 = center + Vector2.from_angle(n * TAU / 64.0) * radius
			assert(absf(arena_view.unproject(arena_view.project(point)).distance_to(center) - radius) < 0.001)
	# Dragging the raised model must preserve the initial cursor-to-foot offset.
	var unit_position := Vector2(550, 300)
	var cursor: Vector2 = arena_view.project(unit_position, 25)
	var offset: Vector2 = unit_position - arena_view.unproject(cursor)
	assert((arena_view.unproject(cursor) + offset).distance_to(unit_position) < 0.001)
	print("VIEW PASSED: 289 projection round trips, elevation, damage-circle projection, deployment drag offset")

func prepare_view_preview(kind: String) -> void:
	if kind == "laser":
		team_presets = [5, 8]
		setup_loadouts()
		reset_round()
	for team in range(2): preset_menus[team].select(team_presets[team])
	rebuild_editor()
	started = true
	var found := false
	for tick in range(3600):
		simulate(STEP)
		if kind == "air" and not hazards.is_empty():
			for advance in range(12): simulate(STEP)
			found = true
		elif kind in ["blast", "laser", "earth"]:
			for fx in blasts:
				if (kind == "blast" and fx.kind == "area") or (kind == "laser" and fx.get("skill", "") == "蓄能贯穿") or (kind == "earth" and fx.get("skill", "") == "裂地冲击"):
					found = true
		if found or finished: break
	assert(found, "Requested preview effect did not occur")
	if kind in ["blast", "earth"]:
		for tick in range(5): simulate(STEP)
	running = false
	refresh_ui()
	queue_redraw()
	capture_preview.call_deferred()


func reset_walls() -> void:
	walls.assign(WALL_LAYOUT)
	wall_states.clear()
	wall_damage.clear()
	for i in range(WALL_LAYOUT.size()):
		wall_states.append({"id": i, "rect": WALL_LAYOUT[i], "hp": WALL_HP})

func first_wall_hit(a: Vector2, b: Vector2) -> Dictionary:
	var hit := {}
	var nearest := INF
	for w in wall_states:
		if w.hp <= 0: continue
		var rect: Rect2 = w.rect
		if rect.has_point(a): return {"id": w.id, "p": a, "distance": 0.0}
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for n in range(4):
			var point = Geometry2D.segment_intersects_segment(a, b, corners[n], corners[(n + 1) % 4])
			if point != null and a.distance_to(point) < nearest:
				nearest = a.distance_to(point)
				hit = {"id": w.id, "p": point, "distance": nearest}
	return hit

func queue_wall_damage(id: int, amount: float) -> void:
	wall_damage[id] = float(wall_damage.get(id, 0.0)) + maxf(0, amount)

func apply_wall_damage() -> void:
	var destroyed := false
	for id in wall_damage:
		var w: Dictionary = wall_states[id]
		if w.hp <= 0: continue
		w.hp = maxf(0, w.hp - wall_damage[id])
		if w.hp <= 0:
			walls.erase(w.rect)
			destroyed = true
			effects.append({"p": w.rect.get_center(), "life": 0.8, "color": GOLD, "wall_break": true})
			log_event("掩体%d 被摧毁，通路已打开" % (id + 1))
	wall_damage.clear()
	if destroyed:
		navigation_border = -999
		refresh_boundary_navigation()

func run_wall_tests() -> void:
	reset_round()
	assert(wall_states.size() == 2 and wall_states[0].hp == 300)
	assert(blocked(Vector2(240, 160), Vector2(320, 160)))
	queue_wall_damage(0, 100)
	apply_wall_damage()
	assert(wall_states[0].hp == 200 and walls.size() == 2)
	queue_wall_damage(0, 100)
	apply_wall_damage()
	assert(wall_states[0].hp == 100)
	queue_wall_damage(0, 100)
	apply_wall_damage()
	assert(wall_states[0].hp == 0 and walls.size() == 1)
	assert(not blocked(Vector2(240, 160), Vector2(320, 160)))
	assert(valid_position(Vector2(280, 160)))
	assert(not nav.is_point_solid(Vector2i(13, 7)))
	reset_round()
	assert(wall_states[0].hp == 300 and walls.size() == 2)
	# A projectile must stop at the wall, including the shot that breaks it.
	units[0].p = Vector2(220, 160)
	units[2].p = Vector2(340, 160)
	units[1].hp = 0
	units[3].hp = 0
	wall_states[0].hp = 7
	bullets.append({"p": Vector2(240, 160), "v": Vector2(1300, 0), "life": 1.0, "team": 0, "damage": 7.0})
	update_bullets(0.1)
	assert(wall_states[0].hp == 0 and units[2].hp == MAX_HP and bullets.is_empty())
	bullets.append({"p": Vector2(240, 160), "v": Vector2(1300, 0), "life": 1.0, "team": 0, "damage": 7.0})
	update_bullets(0.1)
	assert(units[2].hp == MAX_HP - 7)
	reset_round()
	hazards.append({"kind": "beam", "p": Vector2(240, 160), "end": beam_end(Vector2(240, 160), 0), "left": 0.0, "damage": 22.0, "radius": 7.0, "team": 0, "source": 0})
	update_bullets(STEP)
	assert(wall_states[0].hp == 278)
	update_bullets(STEP)
	assert(wall_states[0].hp == 278, "Beam visual must not deal repeated wall damage")
	hazards.append({"kind": "area", "p": Vector2(270, 160), "left": 0.0, "damage": 18.0, "radius": 64.0, "team": 0, "source": 0})
	update_bullets(STEP)
	assert(wall_states[0].hp == 260 and wall_states[1].hp == 300)
	reset_round()
	units[0].p = Vector2(180, 160)
	units[2].p = Vector2(235, 160)
	units[1].hp = 0
	units[3].hp = 0
	bullets.append({"p": Vector2(200, 160), "v": Vector2(1300, 0), "life": 1.0, "team": 0, "damage": 7.0})
	update_bullets(0.1)
	assert(units[2].hp == MAX_HP - 7 and wall_states[0].hp == 300, "A body before the wall intercepts the bullet first")
	print("WALL PASSED: 300/200/100/0 stages, projectile blocking and break shot, beam once, area damage, collision/navigation opening, reset")


func ultimate_name(uid: int) -> String:
	return "天穹贯穿" if uid % 2 == 0 else "星火轰炸"

func begin_ultimate_aim(uid: int) -> void:
	if uid < 0 or uid >= 2 or not started: return
	var u: Dictionary = units[uid]
	if u.hp <= 0 or u.ult_charge < 100 or u.phase == "大招蓄力": return
	ultimate_aim = -1 if ultimate_aim == uid else uid
	ultimate_cursor = u.p + Vector2.from_angle(u.angle) * 250
	queue_redraw()

func ultimate_geometry(u: Dictionary, angle: float) -> Dictionary:
	var direction := Vector2.from_angle(angle)
	if u.member == 0:
		var end: Vector2 = u.p + direction * 500
		# Clip the long beam to arena bounds and the nearest intact wall.
		for distance in range(1, 501):
			var point: Vector2 = u.p + direction * distance
			if not Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)).has_point(point):
				end = u.p + direction * (distance - 1)
				break
		var hit := first_wall_hit(u.p, end)
		if not hit.is_empty(): end = hit.p - direction * 0.1
		return {"end": end, "radius": 18.0}
	var points: Array[Vector2] = []
	for distance in [120.0, 220.0, 320.0]:
		var point: Vector2 = (u.p + direction * distance).clamp(Vector2.ONE * 60, Vector2.ONE * (SIZE - 60))
		# At the edge, don't stack multiple shells onto the same clamped spot.
		if points.is_empty() or points[-1].distance_to(point) >= 55: points.append(point)
	return {"points": points, "radius": 60.0}

func confirm_ultimate(point: Vector2) -> bool:
	if ultimate_aim < 0: return false
	var u: Dictionary = units[ultimate_aim]
	if u.hp <= 0 or u.ult_charge < 100:
		ultimate_aim = -1
		return false
	if not Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)).has_point(point) or point.distance_to(u.p) < 12: return false
	u.ult_angle = (point - u.p).angle()
	ultimate_aim = -1
	start_ultimate(u)
	return true

func start_ultimate(u: Dictionary) -> void:
	u.energy -= energy_cost(ultimate_name(u.uid))
	ActionTimeline.begin(u, 0.3, energy_cost(ultimate_name(u.uid)), 0.0)
	u.release_lock_frames = ActionTimeline.RELEASE_LOCK_FRAMES
	u.recovery_frames = ActionTimeline.frames(0.8)
	u.ult_charge = 0.0
	u.angle = u.ult_angle
	u.phase = "大招蓄力"
	u.timer = 0.3
	u.shot_count = 0
	u.active_skill = ultimate_name(u.uid)
	u.action_left = 0.0
	u.dodge = 0.0
	u.dodge_frames = 0
	u.avoid_left = 0.0
	u.path = PackedVector2Array()
	u.intent = u.active_skill
	u.reason = "指挥官手动释放：" + u.active_skill
	u.rule = "手动大招"
	u.rule_flash = 1.2
	u.rule_kind = "ultimate"
	u.rule_slot = -1
	log_event("蓝%d · 大招 %s" % [u.member + 1, u.active_skill])

func release_ultimate(u: Dictionary) -> void:
	u.action_committed = true
	u.shot_count = 1
	emit_ultimate_effects(u)
	enter_attack_recovery(u, 0.8)

func emit_ultimate_effects(u: Dictionary) -> void:
	finish_spell(u, ultimate_name(u.uid))
	var shape := ultimate_geometry(u, u.ult_angle)
	if u.member == 0:
		hazards.append({"kind": "beam", "skill": "天穹贯穿", "p": u.p, "end": shape.end, "radius": shape.radius, "damage": 45.0, "true_damage": true, "left": 0.0, "team": u.team, "source": u.uid})
		add_impulse(u, -Vector2.from_angle(u.ult_angle) * 160)
	else:
		for point in shape.points:
			hazards.append({"kind": "area", "skill": "星火轰炸", "p": point, "origin": u.p, "radius": shape.radius, "damage": 22.0, "true_damage": false, "left": BLAST_FLIGHT, "team": u.team, "source": u.uid})
		add_impulse(u, -Vector2.from_angle(u.ult_angle) * 110)
	u.fire_flash = 0.18
	u.phase = "收招"
	u.timer = 0.8
	shots += 1

func run_ultimate_tests() -> void:
	reset_round()
	started = true
	begin_ultimate_aim(0)
	assert(ultimate_aim == -1)
	units[0].ult_charge = 100.0
	begin_ultimate_aim(0)
	assert(ultimate_aim == 0)
	assert(not confirm_ultimate(Vector2(-10, -10)) and units[0].ult_charge == 100)
	begin_ultimate_aim(0)
	assert(ultimate_aim == -1 and units[0].ult_charge == 100)
	units[0].p = Vector2(100, 320)
	units[2].p = Vector2(300, 320)
	units[1].hp = 0
	units[3].hp = 0
	for uid in range(4): loadouts[uid] = Tactics.build([], [])
	begin_ultimate_aim(0)
	assert(confirm_ultimate(Vector2(500, 320)))
	assert(ultimate_aim == -1 and units[0].ult_charge == 0 and units[0].phase == "大招蓄力")
	for tick in range(20): simulate(STEP)
	assert(units[2].hp == MAX_HP - 45)
	assert(units[0].phase == "收招")
	reset_round()
	started = true
	running = true
	speed = 2.0
	units[0].ult_charge = 100
	begin_ultimate_aim(0)
	var before := clock
	advance_playback(0.5)
	assert(absf(before - clock - 0.15) < 0.001 and speed == 2.0)
	ultimate_aim = -1
	before = clock
	advance_playback(0.5)
	assert(absf(before - clock - 1.0) < 0.001)
	reset_round()
	started = true
	units[1].ult_charge = 100
	units[1].p = Vector2(100, 320)
	begin_ultimate_aim(1)
	assert(confirm_ultimate(Vector2(600, 320)))
	release_ultimate(units[1])
	assert(hazards.size() == 3 and hazards[0].damage == 22)
	units[1].hp = 0
	units[1].ult_charge = 100
	begin_ultimate_aim(1)
	assert(ultimate_aim == -1)
	reset_round()
	assert(ultimate_aim == -1 and units[0].ult_charge == 0)
	for u in units:
		u.phase = "收招"
		u.timer = 100.0
	for tick in range(720): simulate(STEP)
	assert(units[0].ult_charge >= 99.99 and units[1].ult_charge >= 99.99)
	reset_round()
	units[0].p = Vector2(220, 160)
	units[0].ult_angle = 0.0
	units[2].p = Vector2(350, 160)
	release_ultimate(units[0])
	update_bullets(STEP)
	assert(wall_states[0].hp == 255 and units[2].hp == MAX_HP)
	reset_round()
	units[1].p = Vector2(100, 320)
	units[1].ult_angle = 0.0
	units[2].p = Vector2(220, 320)
	release_ultimate(units[1])
	update_bullets(BLAST_FLIGHT + 0.01)
	assert(units[2].hp == MAX_HP - 22)
	print("ULTIMATE PASSED: charge gate, cancel, invalid click, manual direction, cast and beam damage, slow motion and speed restore, barrage, death/reset")


func energy_cost(skill: String) -> float:
	if skill in ["天穹贯穿", "星火轰炸"]: return 70.0
	if skill in ["蓄能贯穿", "抛射轰击", "烈焰爆破", "裂地冲击"]: return 45.0
	if skill in ["绕侧", "后撤", "留空", "调整站位", "接敌", "搜寻", "步行避险"]: return 0.0
	if skill in ["短冲刺", "侧闪"]: return 20.0
	if skill == "架枪防御": return 10.0
	if skill in ["点射", "普通攻击"]: return 15.0
	return 25.0

func uses_public_cd(skill: String) -> bool:
	return skill not in ["绕侧", "后撤", "短冲刺", "侧闪", "架枪防御", "留空", "调整站位", "接敌", "搜寻", "步行避险"]

func can_use_skill(u: Dictionary, skill: String) -> bool:
	return (energy_cost(skill) == 0 or u.energy + 0.00001 >= energy_cost(skill)) and float(u.skill_cds.get(skill, 0)) <= 0 and (not uses_public_cd(skill) or u.cooldown <= 0)

func finish_spell(u: Dictionary, skill: String) -> void:
	var duration := 1.8 if skill == "点射" else (4.0 if skill in ["天穹贯穿", "星火轰炸"] else (3.0 if energy_cost(skill) >= 45 else 2.3))
	u.cooldown = maxf(u.cooldown, duration)

func energy_speed(u: Dictionary) -> float:
	return lerpf(0.55, 1.0, clampf(u.energy / 100.0, 0, 1))

func run_resource_tests() -> void:
	pattern_fixture()
	begin_shot(units[0], 2, "风刃")
	assert(units[0].energy == 75)
	update_attack(units[0], STEP * 2)
	assert(units[0].cooldown == 0 and units[0].shot_count == 1)
	update_attack(units[0], STEP * 14)
	assert(units[0].cooldown == 2.3 and units[0].phase == "释放硬直")
	update_attack(units[0], STEP)
	assert(units[0].cooldown == 2.3 and units[0].phase == "收招")
	assert(not can_use_skill(units[0], "火矢") and not can_use_skill(units[0], "追风") and not can_use_skill(units[0], "点射"))
	assert(can_use_skill(units[0], "侧闪") and can_use_skill(units[0], "后撤"))
	units[0].cooldown = 0
	units[0].energy = 10
	assert(not can_use_skill(units[0], "点射"))
	ActionTimeline.clear(units[0])
	units[0].phase = "保持射位"
	units[0].action_left = 2
	units[0].intent = "架枪防御"
	simulate(STEP)
	assert(units[0].energy > 10 and units[0].energy < 11)
	units[0].energy = 0
	assert(is_equal_approx(energy_speed(units[0]), 0.55))
	units[0].energy = 100
	assert(is_equal_approx(energy_speed(units[0]), 1.0))
	pattern_fixture()
	begin_shot(units[0], 2, "蓄能贯穿")
	assert(units[0].energy == 55 and units[0].cooldown == 0)
	update_attack(units[0], 1.11)
	assert(units[0].cooldown == 3.0)
	update_attack(units[0], 1.01)
	assert(units[0].cooldown == 3.0, "Finishing recovery must not reset GCD")
	reset_round()
	assert(units[0].energy == 100 and units[0].cooldown == 0)
	pattern_fixture()
	units[0].energy = 40
	loadouts[0] = Tactics.build([["蓄能贯穿", "无", "无"], ["火矢", "无", "无"]], [])
	assert(try_active(units[0], [2]) and units[0].active_skill == "火矢" and units[0].energy == 15)
	units[0].phase = "吟唱"
	units[0].timer = 1
	var energy_before: float = units[0].energy
	simulate(STEP)
	assert(units[0].energy == energy_before, "No regeneration during casting")
	reset_round()
	started = true
	units[0].ult_charge = 100
	units[0].energy = 69
	begin_ultimate_aim(0)
	assert(confirm_ultimate(Vector2(300, 300)) and units[0].energy == -1 and units[0].ult_charge == 0)
	release_ultimate(units[0])
	assert(units[0].cooldown == 4)
	reset_round()
	units[1].hp = 50
	units[1].hurt_recent = 1
	units[1].p = units[0].p + Vector2(60, 0)
	assert(heal_target(units[0], ["回春", "自己精力≥80", "无"]) == 1)
	units[0].energy = 70
	assert(heal_target(units[0], ["回春", "自己精力≥80", "无"]) == -1)
	print("RESOURCE PASSED: one cost per burst, GCD after final emission, AP/PP gate, recovery movement, regeneration, speed floor, long cast, reset")


func run_postmatch_tests() -> void:
	reset_round()
	started = true
	running = true
	units[2].hp = 0
	units[3].hp = 0
	units[0].energy = 0
	units[0].cooldown = 2
	effects.append({"p": units[0].p, "life": 0.5, "color": GOLD})
	simulate(STEP)
	assert(finished and running and winner_team == 0)
	var saved_result := result
	for tick in range(60): simulate(STEP)
	assert(effects.is_empty() and units[0].energy > 0 and units[0].cooldown < 1.1)
	assert(result == saved_result)
	toggle_running()
	assert(not running and finished)
	toggle_running()
	assert(running and finished and result == saved_result)
	step_forward()
	assert(not running and finished)
	end_round(1, "late damage must not replace the result")
	assert(winner_team == 0 and result == saved_result)
	reset_round()
	assert(not finished and units[2].hp == MAX_HP)
	print("POSTMATCH PASSED: result recorded once, simulation/effects/resource recovery continue, pause/resume/step work, R reset remains separate")


func rule_is_executing(u: Dictionary, kind: String, slot: int) -> bool:
	return u.hp > 0 and u.rule_kind == kind and u.rule_slot == slot and u.phase != "移动"


func run_strategy_view_tests() -> void:
	pattern_fixture()
	loadouts[0] = Tactics.build([["落岩", "无", "无"], ["火矢", "无", "无"]], [])
	units[0].skill_cds["落岩"] = 3.0
	assert(try_active(units[0], [2]))
	assert(units[0].trace_ap[0] == "技能CD中" and units[0].trace_ap[2] == "未检查（上方优先）")
	units[0].rule_flash = 0
	units[0].phase = "收招"
	assert(rule_is_executing(units[0], "active", 1))
	assert(editor_rows.size() == 12)
	# Change AP to PP through the actual menu callback: conditions travel with it.
	choose_editor_unit(0)
	edit_rule_cell(0, 1, "自己HP≤50")
	var skill_menu: OptionButton = editor_rows[0].menus[0]
	skill_menu.item_selected.emit(Tactics.all_skills().find("架枪防御"))
	assert(loadouts[0].active.size() == 1 and loadouts[0].reaction.size() == 1)
	assert(loadouts[0].active[0][0] == "火矢" and loadouts[0].reaction[0] == ["架枪防御", "自己HP≤50", "无"])
	assert(editor_rows[0].kind == "active" and editor_rows[1].kind == "reaction")
	# Empty slot accepts either type, with no AP/PP quota, capped at twelve total.
	edit_rule_cell(2, 0, "普通攻击")
	assert(loadouts[0].active[1][0] == "普通攻击" and editor_rows[2].kind == "reaction")
	edit_rule_cell(2, 0, "火矢")
	assert(loadouts[0].reaction.is_empty() and loadouts[0].active.size() == 3)
	while editor_entries().size() < 12: edit_rule_cell(editor_entries().size(), 0, "火矢")
	assert(editor_entries().size() == 12 and loadouts[0].active.size() == 12)
	edit_rule_cell(12, 0, "火矢")
	assert(editor_entries().size() == 12)
	for row in editor_rows: assert(row.kind == "active")
	# All twelve slots may also be PP, and can switch type in place at capacity.
	for i in range(12): edit_rule_cell(0, 0, "架枪防御")
	assert(loadouts[0].active.is_empty() and loadouts[0].reaction.size() == 12)
	edit_rule_cell(11, 0, "普通攻击")
	assert(editor_rows[0].kind == "active" and editor_entries().size() == 12)
	edit_rule_cell(0, 0, "留空")
	assert(editor_entries().size() == 11 and editor_rows[11].slot == -1)
	# Reordering changes actual priority and preserves the other category.
	loadouts[0] = Tactics.basics()
	rebuild_editor()
	var original: Dictionary = loadouts[0].duplicate(true)
	move_rule("active", 0, 1)
	assert(loadouts[0].active[0] == original.active[1] and loadouts[0].reaction == original.reaction)
	move_rule("active", 1, -1)
	assert(loadouts[0] == original)
	move_rule("active", 0, -1)
	assert(loadouts[0] == original)
	# Basic actions obey the exact same priority/conditions as other AP.
	pattern_fixture()
	loadouts[0] = Tactics.basics()
	units[0].cooldown = 2
	assert(try_active(units[0], [2]) and rule_is_executing(units[0], "active", 1))
	assert(units[0].trace_ap[0] == "公共CD中")
	units[0].cooldown = 0
	assert(try_active(units[0], [2]) and rule_is_executing(units[0], "active", 0))
	units[0].cooldown = 0
	units[0].skill_cds.clear()
	loadouts[0].active[0][1] = "自己HP≤50"
	assert(try_active(units[0], [2]) and units[0].rule_slot == 1)
	loadouts[0] = {"active": [["搜寻", "自己精力≤30", "无"]], "reaction": []}
	units[0].memory = 0
	assert(not try_active(units[0], []))
	units[0].energy = 10
	assert(try_active(units[0], []) and units[0].phase == "搜索")
	loadouts[0].active[0][1] = "敌人距离≤2米"
	assert(not try_active(units[0], []), "Target conditions cannot pass when searching without a target")
	pattern_fixture()
	loadouts[0] = {"active": [], "reaction": []}
	for i in range(11): loadouts[0].active.append(["火矢", "自己HP≤50", "无"])
	loadouts[0].active.append(["普通攻击", "无", "无"])
	assert(try_active(units[0], [2]) and units[0].rule_slot == 11)
	pattern_fixture()
	loadouts[0] = {"active": [], "reaction": []}
	for i in range(11): loadouts[0].reaction.append(["架枪防御", "自己HP≤50", "无"])
	loadouts[0].reaction.append(["架枪防御", "无", "无"])
	units[2].target = 0
	units[2].phase = "瞄准"
	assert(try_reaction(units[0], [2]) and units[0].rule_slot == 11)
	# Clearing everything truly disables autonomous voluntary actions.
	reset_round()
	for uid in range(4): loadouts[uid] = {"active": [], "reaction": []}
	var positions: Array = []
	for u in units: positions.append(u.p)
	for tick in range(120): simulate(STEP)
	assert(shots == 0)
	for uid in range(4): assert(units[uid].p == positions[uid] and units[uid].phase == "待命")
	# PP walking evasion must be configured and must satisfy both conditions.
	pattern_fixture()
	var bot: Dictionary = units[2]
	hazards.append({"kind": "area", "p": bot.p, "radius": 64.0, "team": 0, "source": 0, "left": 1.5, "origin": units[0].p, "damage": 18.0, "skill": "抛射轰击"})
	loadouts[2] = {"active": [], "reaction": []}
	assert(not try_reaction(bot, [0]))
	loadouts[2].reaction = [["步行避险", "自己HP≤50", "无"]]
	assert(not try_reaction(bot, [0]))
	bot.hp = 40
	assert(try_reaction(bot, [0]) and rule_is_executing(bot, "reaction", 0))
	choose_editor_unit(3)
	refresh_ui()
	assert(editor_unit == 3 and selected == 3 and roster_buttons.size() == 4)
	print("STRATEGY VIEW PASSED: 12 shared slots, automatic AP/PP grouping, type changes at capacity, conditions preserved, real priority swaps, editable basic AP/PP, no hidden fallback, persistent highlight and roster")

func run_ultimate_debt_tests() -> void:
	for starting_energy in [30.0, 0.0, -20.0]:
		reset_round()
		started = true
		finished = true
		units[0].energy = starting_energy
		units[0].ult_charge = 100
		units[0].cooldown = 3
		units[0].phase = "收招"
		units[0].timer = 1
		begin_ultimate_aim(0)
		assert(confirm_ultimate(Vector2(300, 300)))
		assert(units[0].energy == starting_energy - 70 and units[0].ult_charge == 0)
		assert(units[0].phase == "大招蓄力" and ultimate_aim == -1)
		assert(is_equal_approx(energy_speed(units[0]), 0.55))
		assert(can_use_skill(units[0], "后撤") and not can_use_skill(units[0], "点射"))
		for i in [1, 2, 3]: units[i].hp = 0
		for tick in range(70): simulate(STEP)
		assert(shots == 1)
		var debt: float = units[0].energy
		for tick in range(60): simulate(STEP)
		assert(absf(units[0].energy - debt - 12.0) < 0.01)
	reset_round()
	started = true
	units[0].ult_charge = 100
	units[0].energy = 30
	begin_ultimate_aim(0)
	assert(not confirm_ultimate(Vector2(-1, -1)))
	begin_ultimate_aim(0)
	assert(ultimate_aim == -1 and units[0].energy == 30 and units[0].ult_charge == 100)
	print("ULTIMATE DEBT PASSED: immediate cast during GCD/recovery, 30 -> -40, zero/negative energy, post-match use, debt regeneration, free movement, invalid click/cancel")
