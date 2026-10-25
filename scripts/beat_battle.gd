extends "res://scripts/battle.gd"
## UI adapter: the continuous prototype remains in main.tscn for comparison.
const Beat = preload("res://scripts/beat_simulation.gd")
const BASE_PLAYBACK_RATE := 0.5
const SOLDIER_PRESET := 9
const PLAYER_SKILLS := ["留空", "普通攻击", "接敌", "远敌", "侧闪", "站稳"]
const INIT_SKILLS := ["留空", "站稳", "接敌", "远敌", "普通攻击"]
const PLAYER_PRESETS := [9, 10, 11, 12, 13, 14]
const SIMPLE_CONDITIONS := ["无", "自己HP≤2", "自己处于移动姿态", "敌人处于站立姿态", "敌人处于移动姿态", "敌人处于动作姿态", "敌人处于僵直姿态", "敌人距离≤2格", "敌人距离≥3格"]
const CONDITION_GROUPS := {
	"自身状态": ["自己HP≤2", "自己处于移动姿态"],
	"敌人姿态": ["敌人处于站立姿态", "敌人处于移动姿态", "敌人处于动作姿态", "敌人处于僵直姿态"],
	"敌人距离": ["敌人距离≤2格", "敌人距离≥3格"]
}
const LEGACY_AIM := "沿移动方向预判1格"
# AP priorities from earlier benchmark, now without dodge; fifth demonstrates prediction.
const DUEL_PRESET_NAMES := ["吊射→远敌", "接敌→吊射", "吊射→接敌", "近身远敌→吊射", "预判吊射→接敌"]
const DUEL_PRESET_AP := [
	[["普通攻击", "无", "无"], ["远敌", "无", "无"]],
	[["接敌", "无", "无"], ["普通攻击", "无", "无"]],
	[["普通攻击", "无", "无"], ["接敌", "无", "无"]],
	[["远敌", "敌人距离≤2格", "无"], ["普通攻击", "无", "无"]],
	[["普通攻击", "敌人处于移动姿态", "沿移动方向预判1格"], ["普通攻击", "无", "无"], ["接敌", "无", "无"]]
]
var soldier_hint: Label
var arena_mode_button: Button
var beat_sim = Beat.new()
var presentation = preload("res://scripts/beat_presentation.gd").new()
var settle_visual := 0.0
var animation_preview_caption := ""
var segment_active := false
var steps_remaining := 0
var segment_preview: Dictionary = {}
var editor_zone := "loop"
var init_tab: Button
var loop_tab: Button

func _ready() -> void:
	team_presets = [SOLDIER_PRESET, SOLDIER_PRESET]
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Arial"])
	arena_view = make_arena_view()
	DisplayServer.window_set_title("AutoBattle — 8×8 节拍战斗 / beat-grid-combat")
	reset_walls()
	setup_navigation()
	setup_loadouts()
	setup_ui()
	reset_round()
	if "--beat-init-test" in OS.get_cmdline_user_args():
		preload("res://scripts/beat_init_validation.gd").run(self)
		get_tree().quit()
		return
	if "--beat-test" in OS.get_cmdline_user_args():
		preload("res://scripts/beat_validation.gd").run(self)
		preload("res://scripts/beat_init_validation.gd").run(self)
		get_tree().quit()
		return
	if "--beat-telegraph-preview" in OS.get_cmdline_user_args():
		set_physics_process(false)
		set_process(false)
		capture_telegraph_preview.call_deferred()
		return
	if "--beat-shooting-preview" in OS.get_cmdline_user_args():
		set_physics_process(false)
		set_process(false)
		capture_shooting_preview.call_deferred()
		return
	if "--beat-animation-preview" in OS.get_cmdline_user_args():
		set_physics_process(false)
		set_process(false)
		capture_animation_preview.call_deferred()
		return
	if "--beat-preview" in OS.get_cmdline_user_args():
		started = true
		for tick in range(14):
			simulate(Beat.SECONDS)
			advance_visuals(Beat.SECONDS)
		choose_editor_unit(0)
		set_physics_process(false)
		refresh_ui()
		capture_beat_preview.call_deferred()

func make_arena_view():
	return preload("res://scripts/beat_view.gd").new()

func preset_names() -> Array:
	return Tactics.NAMES + ["普通士兵"] + DUEL_PRESET_NAMES

func preset_loadouts(index: int) -> Array:
	if index > SOLDIER_PRESET and index <= SOLDIER_PRESET + DUEL_PRESET_NAMES.size():
		var profile := {"active": DUEL_PRESET_AP[index - SOLDIER_PRESET - 1], "reaction": []}
		return [profile.duplicate(true), profile.duplicate(true)]
	if index != SOLDIER_PRESET:
		var pair := super.preset_loadouts(index)
		for profile in pair: profile.reaction = profile.reaction.filter(func(rule): return rule[0] != "侧闪")
		return pair
	var soldier := {
		"active": [["普通攻击", "无", "无"], ["接敌", "无", "无"]],
		"reaction": []
	}
	return [soldier.duplicate(true), soldier.duplicate(true)]

func basic_loadout() -> Dictionary:
	return preset_loadouts(SOLDIER_PRESET)[0]

func setup_loadouts() -> void:
	super.setup_loadouts()
	for loadout in loadouts:
		add_stand_rule(loadout)
		simplify_loadout(loadout)

func reset_walls() -> void:
	walls.assign([Rect2(240, 80, 80, 160), Rect2(320, 400, 80, 160)])
	wall_states.clear()
	wall_damage.clear()
	for index in range(walls.size()): wall_states.append({"id": index, "rect": walls[index], "hp": WALL_HP})

func add_stand_rule(loadout: Dictionary) -> void:
	for rule in loadout.active:
		if rule[0] in Beat.HIGH:
			loadout.active.push_front(["站稳", "自己处于移动姿态", "无"])
			return

func apply_preset(team: int, index: int) -> void:
	if team < preset_menus.size(): preset_menus[team].select(preset_menus[team].get_item_index(index))
	super.apply_preset(team, index)
	for member in range(2): add_stand_rule(loadouts[team * 2 + member])
	rebuild_editor()
	reset_round()

func setup_ui() -> void:
	super.setup_ui()
	for node in find_children("*", "Button", true, false):
		if node.text == "清空":
			for connection in node.pressed.get_connections(): node.pressed.disconnect(connection.callable)
			node.pressed.connect(clear_editor_zone)
			node.tooltip_text = "清空当前编辑区；另一区保留。修改后重开。"
		if node.text == "仅基础": node.tooltip_text = "清空该角色Init，并恢复默认Loop。"
		if node.text == "单帧 [N]":
			node.text = "下一拍 [N]"
			node.tooltip_text = "N完整播放1拍并在交点结算后暂停；Shift+N播放4拍。新基准1倍速每拍0.5秒；0.5倍每拍1秒，2倍每拍0.25秒。"
		if node.text.begins_with("速度 "): node.tooltip_text = "新基准：1倍速每拍0.5秒；0.5倍每拍1秒；2倍每拍0.25秒。"
	for node in get_children():
		if node is Label and node.text == "AUTOBATTLE": node.text = "AUTOBATTLE / BEAT"
	for team in range(preset_menus.size()):
		var picker: OptionButton = preset_menus[team]
		for connection in picker.item_selected.get_connections(): picker.item_selected.disconnect(connection.callable)
		picker.clear()
		for preset_id in PLAYER_PRESETS:
			picker.add_item(preset_names()[preset_id], preset_id)
			if preset_id > SOLDIER_PRESET:
				var lines: Array[String] = []
				for rule in DUEL_PRESET_AP[preset_id - SOLDIER_PRESET - 1]:
					lines.append(skill_label(rule[0]) + ("〔" + rule[1] + "〕" if rule[1] != "无" else "") + ("〔" + rule[2] + "〕" if rule[2] != "无" else ""))
				picker.get_popup().set_item_tooltip(picker.item_count - 1, "AP：" + " → ".join(lines) + "\nPP：空")
		picker.select(picker.get_item_index(team_presets[team]))
		picker.item_selected.connect(func(index): apply_preset(team, picker.get_item_id(index)))
		picker.tooltip_text = "仅展示当前开放的基础配置；切换会重开战斗并保留布阵。"
	update_beat_menus()
	var zones := HBoxContainer.new()
	var panel := rule_count_label.get_parent()
	panel.add_child(zones)
	panel.move_child(zones, rule_count_label.get_index())
	init_tab = add_button(zones, "Init · 开局指令", func(): set_editor_zone("init"))
	loop_tab = add_button(zones, "Loop · 循环策略", func(): set_editor_zone("loop"))
	for button in [init_tab, loop_tab]: button.toggle_mode = true
	init_tab.tooltip_text = "按顺序执行，每项完成后进入下一项，全部完成后进入Loop。无法执行时等待，不跳过。PP在两区均生效。"
	loop_tab.tooltip_text = "沿用原有AP/PP规则：每次决策从上到下检查，执行第一条可用规则。"
	rebuild_editor()
	soldier_hint = text_label(self, "普通士兵对练\n3血 · 单格吊射1伤害\n射程4格 · 射击3拍 · 独立CD6拍\n无大招", 14)
	soldier_hint.position = Vector2(700, 35)
	soldier_hint.modulate = Color("c8b997")
	arena_mode_button = add_button(self, "3×3 自由对战 →", func(): get_tree().change_scene_to_file("res://puzzle_arena.tscn"))
	arena_mode_button.position = Vector2(730, 112)

func rebuild_editor() -> void:
	# The legacy editor removes conditions it does not know; preserve beat-only ones.
	for loadout in loadouts: simplify_loadout(loadout)
	for loadout in loadouts:
		if not loadout.has("init"): loadout.init = []
	var saved := loadouts.duplicate(true)
	super.rebuild_editor()
	for uid in range(saved.size()): loadouts[uid] = saved[uid]
	update_beat_menus()
	if rule_count_label != null:
		var profile: Dictionary = loadouts[editor_unit]
		rule_count_label.text = ("Init %d / 12 · 从上到下执行一次，完成后进入Loop" % profile.init.size()) if editor_zone == "init" else ("Loop %d / 12 · AP优先级 / PP插入 · Init共%d项" % [profile.active.size() + profile.reaction.size(), profile.init.size()])
	if init_tab != null:
		init_tab.set_pressed_no_signal(editor_zone == "init")
		loop_tab.set_pressed_no_signal(editor_zone == "loop")
	if editor_zone == "init":
		for row in editor_rows:
			if row.slot >= 0: row.badge.text = "初"

func set_editor_zone(zone: String) -> void:
	editor_zone = zone
	rebuild_editor()
	refresh_ui()

func clear_editor_zone() -> void:
	var profile: Dictionary = loadouts[editor_unit]
	if editor_zone == "init": profile.init = []
	else:
		profile.active = []
		profile.reaction = []
	rebuild_editor()
	reset_round()

func editor_entries() -> Array:
	if editor_zone != "init": return super.editor_entries()
	var entries: Array = []
	for slot in range(loadouts[editor_unit].get("init", []).size()):
		entries.append({"kind": "init", "slot": slot, "rule": loadouts[editor_unit].init[slot]})
	return entries

func small_hp_condition(text: String) -> String:
	return text.replace("HP≤50", "HP≤2").replace("敌人距离≤2米", "敌人距离≤2格").replace("敌人距离≥3米", "敌人距离≥3格")

func conditions_for_skill(skill: String) -> Array:
	if skill == "留空": return ["无"]
	if skill == "站稳": return ["无", "自己HP≤2", "自己处于移动姿态"]
	if skill in Beat.SUPPORT: return ["无", "自己HP≤2"]
	return SIMPLE_CONDITIONS.duplicate()

func simplify_loadout(loadout: Dictionary) -> void:
	for kind in ["active", "reaction"]:
		for rule in loadout[kind]:
			var allowed := conditions_for_skill(rule[0])
			for column in [1, 2]:
				rule[column] = small_hp_condition(rule[column])
				# Existing demos remain replayable; the aim modifier is no longer offered as a condition.
				if rule[column] == LEGACY_AIM and rule[0] in ["普通攻击", "点射"]: continue
				if rule[column] not in allowed: rule[column] = "无"

func update_beat_menus() -> void:
	var entries := editor_entries()
	for index in range(editor_rows.size()):
		var menus: Array = editor_rows[index].menus
		var occupied := index < entries.size()
		var rule: Array = entries[index].rule if occupied else ["留空", "无", "无"]
		for column in range(3):
			var menu: OptionButton = menus[column]
			if column == 0:
				menu.clear()
				for skill in (INIT_SKILLS if editor_zone == "init" else PLAYER_SKILLS):
					menu.add_item(skill_label(skill))
					menu.get_popup().set_item_tooltip(menu.item_count - 1, beat_help(skill))
			else:
				menu.clear()
				menu.add_theme_font_size_override("font_size", 13)
				build_condition_menu(menu, rule[0], rule[column], index, column)
				menu.disabled = not occupied or editor_zone == "init"
			for item in range(menu.item_count):
				if menu.get_item_text(item) == (skill_label(rule[column]) if column == 0 else rule[column]): menu.select(item)
			if column > 0: menu.text = "旧实验：前方1格" if rule[column] == LEGACY_AIM else rule[column]
			menu.tooltip_text = beat_help(rule[0]) if column == 0 else condition_help(rule[column])

func build_condition_menu(menu: OptionButton, skill: String, current: String, row_index: int, column: int) -> void:
	var popup := menu.get_popup()
	for child in popup.get_children():
		if child is PopupMenu:
			popup.remove_child(child)
			child.queue_free()
	var allowed := conditions_for_skill(skill)
	menu.add_item("无")
	for group in CONDITION_GROUPS:
		var values: Array = CONDITION_GROUPS[group].filter(func(value): return value in allowed)
		if values.is_empty(): continue
		var child := PopupMenu.new()
		child.name = "ConditionGroup%d" % popup.get_child_count()
		popup.add_child(child)
		for value in values:
			child.add_radio_check_item(value.trim_prefix("敌人处于") if group == "敌人姿态" else value)
			child.set_item_metadata(child.item_count - 1, value)
			child.set_item_checked(child.item_count - 1, value == current)
			child.set_item_tooltip(child.item_count - 1, condition_help(value))
		child.id_pressed.connect(func(item_id: int):
			edit_rule_cell(row_index, column, child.get_item_metadata(child.get_item_index(item_id)))
		)
		popup.add_submenu_item(group, child.name)

func skill_label(skill: String) -> String:
	if skill == "站稳": return "站立"
	return "吊射" if skill == "普通攻击" else skill

func condition_help(condition: String) -> String:
	match condition:
		"无": return "不添加额外限制。"
		"自己HP≤2": return "自身条件：自己剩余2血或1血时执行。"
		"自己处于移动姿态": return "自身条件：仅在自己是移动姿态时执行。可用于Loop中按需站立，避免无条件站立一直占据第一优先级。"
		"敌人处于站立姿态": return "目标条件：只选择当前处于站立姿态的敌人。"
		"敌人处于移动姿态": return "目标条件：只选择当前有移动方向的敌人，不读取其下一拍动作。"
		"敌人处于动作姿态": return "目标条件：只选择当前处于动作姿态的敌人，例如射击后摇；不等同于站立或移动。"
		"敌人处于僵直姿态": return "目标条件：只选择当前处于僵直姿态的敌人，例如击发、碰撞；普通移动硬直仍归移动姿态。"
		"敌人距离≤2格": return "目标条件：与敌人的曼哈顿距离不超过2格。"
		"敌人距离≥3格": return "目标条件：与敌人的曼哈顿距离至少3格。"
		"沿移动方向预判1格": return "旧实验瞄准修饰（已退出条件选项）：固定瞄前方1格，未按移动剩余拍数预测。仅兼容已有示范；选择其它条件可移除。"
	return condition

func beat_help(skill: String) -> String:
	if skill in ["接敌", "远敌", "后撤"]: return "%s：按地形路径代价选择一个相邻空格，%s。每次只移动一格（2拍）；同向可续走，转向先站立1拍。无内置停止距离，不检查是否已能攻击；是否执行由条件和优先级决定。无可改善距离的一步时检查下条规则。" % [skill, "降低到目标的路径距离" if skill == "接敌" else "增加到目标的路径距离"]
	if skill in ["普通攻击", "点射"]: return "单格吊射：曼哈顿距离≤4格，允许斜向选格、越墙，只命中瞄准时锁定的1格，不追踪目标。条件只筛选执行时机和目标；旧固定一格预判仅兼容已有示范。需站立：非站立先花1拍站立，再瞄准预警1拍 → 目标格结算1拍 → 后摇1拍，结束恢复站立。瞄准可被侧闪取消；击发不可取消；后摇可取消，但侧闪后需重新站立。消耗15精力。独立CD6拍，从开火起算，与后摇重叠；没有公共CD。"
	if skill == "站稳": return "站立：固定耗1拍、不跨格，结束为站立姿态。已经站立也会执行1拍。Init可连续排列用于调整开局时机；Loop无条件放第一项会持续站立。不会中断正在执行的移动或攻击。"
	if skill in Beat.MOVE or skill in ["向左移动", "向右移动", "向上移动", "向下移动"]: return "普通移动2拍一格；同方向可以连续走，换方向前自动站立1拍。移动硬直只能用PP侧闪取消；侧闪1拍一格，结束为有方向的移动姿态，同向可接普通移动，换向先站立1拍。减速时普通移动额外1拍。"
	if skill == "侧闪": return "真实预警触发，1拍跨入安全相邻格，耗20精力。前摇取消退款，后摇取消不退款，释放硬直/碰撞中禁用；无安全格不触发。结束保留侧闪方向的移动姿态，同向接普通移动无需站立；转向或普攻须先站立。"
	if skill == "回春": return "25精力；治疗1血，上限3血。自己或3格内队友刚受伤时触发；冷却32拍，后摇1拍。"
	if skill == "灵木护佑": return "25精力；治疗1血并获得1盾，盾持续8拍。自己或3格内队友刚受伤时触发；冷却36拍，后摇1拍。"
	if skill == "掩护队友": return "25精力；为3格内被威胁的队友提供2盾，持续8拍；护盾取较高值，不累加。冷却24拍，后摇1拍。"
	if skill == "架枪防御": return "10精力；4拍内每次物理直击减伤1，最低0；不减真实伤害、碰撞或持续伤害。冷却20拍，后摇1拍。"
	if skill == "留空": return "删除规则；无隐藏攻击、移动或自动站稳。"
	var actual := "点射" if skill == "普通攻击" else skill
	var hits_per_action: int = Tactics.MAGIC.get(actual, {}).get("hits", 1)
	var extra: String = {
		"标记弹": "标记20拍；强力射击命中已标记目标额外1伤害。",
		"强力射击": "对已标记目标额外1伤害（共3）；本拍新标记下拍生效。",
		"压制射击": "命中减速10拍；普通跨格额外等待1拍，侧闪不受影响。",
		"荆棘": "命中不直接扣血，每8拍造成1持续伤害，共2次；不叠加，无视架枪减伤，护盾可吸收。",
		"霰弹": "覆盖前方4格，每个目标只扣1血。",
		"协同追击": "响应上一拍队友命中，不连锁。", "追风": "响应上一拍队友命中，不连锁。",
	}.get(skill, "")
	if actual in ["火矢", "焰返", "烈焰爆破", "蓄能贯穿", "天穹贯穿"]: extra += "真实伤害：无视架枪减伤，护盾仍可吸收。"
	return "%s：每发%d伤害 × %d发，%d精力；%s。前摇%d拍，释放%d拍，后摇%d拍，独立CD%d拍。%s" % [skill, beat_sim.damage_of(actual), hits_per_action, beat_sim.cost(actual), "需要站稳" if skill in Beat.HIGH else "移动姿态可用", beat_sim.windup(actual), hits_per_action, 2 if actual in Beat.HIGH or actual in ["强力射击", "落岩", "震山"] else 1, ceili(beat_sim.skill_cd(actual) / Beat.SECONDS), extra]

func edit_rule_cell(index: int, column: int, value: String) -> void:
	if index < 0 or index >= Tactics.RULE_LIMIT: return
	var entries := editor_entries()
	if column == 0:
		if value == "吊射": value = "普通攻击"
		if value == "站立": value = "站稳"
		if value not in (INIT_SKILLS if editor_zone == "init" else PLAYER_SKILLS): return
	else:
		if editor_zone == "init" or index >= entries.size() or value not in conditions_for_skill(entries[index].rule[0]): return
	if index >= entries.size() and (column != 0 or value == "留空"): return
	var rule: Array = ["留空", "无", "无"] if index >= entries.size() else entries[index].rule.duplicate()
	rule[column] = value
	var profile: Dictionary = loadouts[editor_unit]
	if editor_zone == "init":
		if index < entries.size(): profile.init.remove_at(index)
		if value != "留空": profile.init.insert(index, rule)
	else:
		var old_kind: String = "" if index >= entries.size() else entries[index].kind
		var new_kind: String = Tactics.skill_kind(rule[0])
		if old_kind == new_kind and not old_kind.is_empty(): profile[old_kind][entries[index].slot] = rule
		else:
			if not old_kind.is_empty(): profile[old_kind].remove_at(entries[index].slot)
			if not new_kind.is_empty(): profile[new_kind].append(rule)
	rebuild_editor()
	reset_round()
	skill_help.text = beat_help(value) if column == 0 else "条件：" + small_hp_condition(value)

func show_editor_help(index: int) -> void:
	var entries := editor_entries()
	if index < entries.size(): skill_help.text = beat_help(entries[index].rule[0])

func reset_round() -> void:
	super.reset_round()
	beat_sim.reset(units, loadouts, walls)
	units.assign(beat_sim.units)
	presentation.reset(units)
	settle_visual = 0.0
	segment_active = false
	steps_remaining = 0
	segment_preview.clear()
	refresh_ui()

func place_unit(uid: int, cell: Vector2i) -> bool:
	if not super.place_unit(uid, cell): return false
	units[uid].cell = cell
	units[uid].pose = "站稳"
	units[uid].trend = Vector2i.ZERO
	beat_sim.units[uid] = units[uid]
	presentation.reset(units)
	return true

func _process(delta: float) -> void:
	if running or steps_remaining > 0:
		settle_visual = 0.0
		advance_playback(delta)
	elif settle_visual > 0:
		var dt := minf(delta * BASE_PLAYBACK_RATE * speed, settle_visual)
		advance_visuals(dt)
		settle_visual -= dt
	queue_redraw()

func _physics_process(_delta: float) -> void:
	# Combat and its animation share the render clock; this loop only updates UI.
	if ultimate_aim >= 0:
		if units[ultimate_aim].hp <= 0: ultimate_aim = -1
		else: ultimate_cursor = arena_view.unproject(get_global_mouse_position())
	refresh_ui()

func advance_visuals(delta: float) -> void:
	presentation.advance(delta)
	for impact in impacts: impact.life -= delta
	impacts = impacts.filter(func(e): return e.life > 0)

func begin_segment() -> void:
	beat_sim.loadouts = loadouts
	segment_preview = beat_sim.preview_segment()
	presentation.begin(units, segment_preview.units, beat_sim, segment_preview)
	segment_active = true

func advance_playback(delta: float) -> void:
	var remaining := delta * playback_rate()
	while remaining > 0.00000001 and (running or steps_remaining > 0):
		if not segment_active: begin_segment()
		var slice := minf(remaining, Beat.SECONDS - accumulator)
		advance_visuals(slice)
		accumulator += slice
		remaining -= slice
		if accumulator + 0.00000001 >= Beat.SECONDS:
			accumulator = 0.0
			simulate(Beat.SECONDS, false)
			segment_active = false
			segment_preview.clear()
			if steps_remaining > 0: steps_remaining -= 1
	refresh_ui()

func playback_rate() -> float:
	return BASE_PLAYBACK_RATE * speed * (ULTIMATE_SLOW if ultimate_aim >= 0 else 1.0)

func toggle_running() -> void:
	steps_remaining = 0
	super.toggle_running()

func step_forward(frame_count := 1) -> void:
	if steps_remaining > 0: return # Repeated presses cannot silently queue extra beats.
	running = false
	started = true
	deployment_drag = -1
	steps_remaining = 4 if frame_count == 12 else frame_count
	settle_visual = 0.0
	if not segment_active: begin_segment()
	refresh_ui()
	queue_redraw()

func simulate(_dt: float, animate_after := true) -> void:
	# Headless checks may step instantly; live playback commits only after animation.
	var before: Array = units.duplicate(true)
	var hp_before: Array = []
	for u in beat_sim.units: hp_before.append(u.hp)
	beat_sim.loadouts = loadouts
	beat_sim.tick()
	units.assign(beat_sim.units)
	if animate_after: presentation.begin(before, units, beat_sim)
	else: presentation.finish_segment(before, units)
	logic_frame = beat_sim.beat
	clock = ROUND_TIME - logic_frame * Beat.SECONDS
	shots = beat_sim.shots
	hits = beat_sim.hits
	reaction_counts = beat_sim.activations
	for u in units:
		if u.hp < hp_before[u.uid]: impacts.append({"p": u.p, "life": 0.65, "amount": hp_before[u.uid] - u.hp, "team": u.team})
		elif u.hp > hp_before[u.uid]: impacts.append({"p": u.p, "life": 0.65, "amount": u.hp - hp_before[u.uid], "team": u.team, "healing": true})
	for event in beat_sim.events: log_event(event)
	if beat_sim.finished and not finished: end_round(beat_sim.winner, beat_sim.result)

func log_event(message: String) -> void:
	logs.push_front("拍%03d  %s" % [logic_frame, message])
	if logs.size() > 8: logs.resize(8)

func rule_is_executing(u: Dictionary, kind: String, slot: int) -> bool:
	if kind == "init": return u.hp > 0 and u.get("init_active", false) and u.rule_kind == "init" and u.rule_slot == slot
	return super.rule_is_executing(u, kind, slot)

func action_state_label(u: Dictionary) -> String:
	if not u.has("pose"): return u.phase
	if u.mode == "移动硬直": return "移动硬直·余%d拍" % u.left
	if u.phase == "转向站立": return "转向站立·1拍"
	if u.phase == "射击站立": return "射击前站立·1拍"
	if u.active_skill == "点射":
		if u.phase == "前摇": return "瞄准完成"
		if u.phase == "释放硬直": return "射击·目标格结算"
		if u.frame_branch.ends_with("后摇") and u.phase == "站稳": return "后摇结束·站立"
	if u.mode == "碰撞": return "碰撞·待弹回"
	if u.mode == "释放硬直": return "待释放%d拍" % u.left
	if not u.mode.is_empty(): return "%s余%d拍" % [u.mode, u.left]
	return "站稳" if u.pose == "站稳" else "移动·" + direction_name(u.trend)

func direction_name(direction: Vector2i) -> String:
	if direction.x > 0: return "右"
	if direction.x < 0: return "左"
	if direction.y > 0: return "下"
	return "上"

func refresh_ui() -> void:
	super.refresh_ui()
	if units.is_empty() or not units[0].has("pose"): return
	status_label.text = "第 %03d 拍  ·  %.1f倍速 · 每拍%.2f秒  |  同步回合 · 整格判定" % [logic_frame, speed, Beat.SECONDS / playback_rate()]
	if segment_active: status_label.text = "第 %03d → %03d 拍 · 播放中 %.0f%% · 到交点才结算" % [logic_frame, logic_frame + 1, accumulator / Beat.SECONDS * 100]
	if not started: status_label.text = "开局布阵  ·  8×8 节拍战斗  |  N 单拍 / Shift+N 四拍"
	var u: Dictionary = units[editor_unit]
	character_label.text = "%s%d · %s格 · %s · %s · HP %d/%d · 盾%d" % ["蓝" if u.team == 0 else "红", u.member + 1, Beat.name_of(u.cell), Beat.posture_label(u), action_state_label(u), u.hp, Beat.MAX_HP, u.shield]
	var upcoming_action := "未选定"
	if not beat_sim.next_segment.is_empty():
		var upcoming: Dictionary = beat_sim.next_segment.units[u.uid]
		upcoming_action = upcoming.phase if upcoming.hp > 0 else "无（已倒下）"
	info_label.text = "所在格 %s · 端点姿态：%s · 生命%d/%d · 精力%d/100\n刚完成：%s → 下一拍：%s\n%s\n%s" % [Beat.name_of(u.cell), Beat.posture_label(u), u.hp, Beat.MAX_HP, u.energy, action_state_label(u), upcoming_action, u.reason, u.last_cancel]

	skill_help.text = ("普通士兵 · 3血 · 普攻1伤害 · 无大招。" if team_presets[u.team] >= SOLDIER_PRESET else "3血 · 普攻1 · 重击2 · 大招2–3 · 敌方碰撞各扣1血。") + "\n移动2拍/格；换向先站立1拍；直走不断速。"
	for child in get_children():
		if child.get_script() == preload("res://scripts/ultimate_portrait.gd"):
			child.visible = team_presets[0] < SOLDIER_PRESET
	if soldier_hint != null: soldier_hint.visible = team_presets[0] >= SOLDIER_PRESET
	for uid in range(roster_buttons.size()):
		var bot: Dictionary = units[uid]
		roster_buttons[uid].text = "%s %d · %s\nHP %d/%d · 盾%d · EN %d" % ["蓝方" if uid < 2 else "红方", uid % 2 + 1, bot.phase if bot.hp > 0 else "倒下", bot.hp, Beat.MAX_HP, bot.shield, bot.energy]
	for row in editor_rows:
		if editor_zone == "init" and row.slot >= 0:
			row.state.text = str(u.get("trace_init", [])[row.slot]) if u.has("trace_init") else "未执行"
			row.state.tooltip_text = "顺序执行；无法执行时等待，PP取消后重试本项。"
		if row.slot >= 0 and rule_is_executing(u, row.kind, row.slot):
			row.state.text = "▶ " + action_state_label(u)
	var init_count: int = loadouts[editor_unit].get("init", []).size()
	info_label.text += "\n执行区域：" + ("Init %d/%d" % [u.get("init_index", 0) + 1, init_count] if u.get("init_index", 0) < init_count else "Loop")
	if init_tab != null:
		init_tab.text = "Init · 开局指令 %d/%d" % [u.get("init_index", 0), init_count]
		loop_tab.text = "Loop · 循环策略" + (" ◀" if started and u.get("init_index", 0) >= init_count else "")

func beat_ultimate_available(uid: int) -> bool:
	var u: Dictionary = units[uid]
	return team_presets[u.team] < SOLDIER_PRESET and started and u.hp > 0 and u.ult_charge >= 100 and u.pose == "站稳" and u.energy >= 70

func beat_ultimate_tooltip(uid: int) -> String:
	return ultimate_name(uid) + "：%d伤害，站稳、70精力、充能满后可瞄准，下一合法节拍起手。按整数格预览，前摇侧闪取消会退还精力和充能。" % beat_sim.damage_of(ultimate_name(uid))

func begin_ultimate_aim(uid: int) -> void:
	if not beat_ultimate_available(uid): return
	ultimate_aim = -1 if ultimate_aim == uid else uid
	ultimate_cursor = units[uid].p + Vector2(160, 0)
	queue_redraw()

func confirm_ultimate(point: Vector2) -> bool:
	if ultimate_aim < 0 or not beat_sim.legal(Beat.cell_of(point)): return false
	var uid := ultimate_aim
	if not beat_ultimate_available(uid): ultimate_aim = -1; return false
	beat_sim.manual[uid] = Beat.cell_of(point)
	ultimate_aim = -1
	log_event("大招已指定格子，将在下一合法决策拍开始")
	return true

func capture_beat_preview() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/beat-preview.png")
	get_tree().quit()

func capture_animation_preview() -> void:
	var sheet := Image.create(1780, 1770, false, Image.FORMAT_RGBA8)
	for row in range(6):
		beat_sim = preload("res://scripts/beat_validation.gd").fixture(self)
		if row == 5:
			beat_sim.loadouts[0].reaction = [["侧闪", "无", "无"]]
			preload("res://scripts/beat_validation.gd").warning(beat_sim, beat_sim.units[0].cell, 1)
		else: beat_sim.loadouts[0].active = [["向右移动", "无", "无"]]
		loadouts = beat_sim.loadouts
		units.assign(beat_sim.units)
		presentation.reset(units)
		started = true
		var prior := 0 if row in [0, 5] else (1 if row == 1 else 2)
		for tick in range(prior):
			simulate(Beat.SECONDS)
			advance_visuals(Beat.SECONDS)
		if row in [3, 4]: loadouts[0].active = [["向上移动", "无", "无"]]
		if row == 4:
			simulate(Beat.SECONDS)
			advance_visuals(Beat.SECONDS)
		simulate(Beat.SECONDS)
		for column in range(4):
			if column > 0: advance_visuals(Beat.SECONDS / 3.0)
			animation_preview_caption = "%s / %.0f ms" % [["普通移动·第1拍", "普通移动·第2拍", "同向续走·不断速", "转向前站立·减速到格心", "转向后起步", "PP侧闪·1拍一格"][row], column * Beat.SECONDS / 3.0 * 1000.0]
			queue_redraw()
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image().get_region(Rect2i(20, 145, 890, 590))
			frame.resize(445, 295, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(frame, Rect2i(0, 0, 445, 295), Vector2i(column * 445, row * 295))
	sheet.save_png("res://reports/beat-animation-preview.png")
	get_tree().quit()

func capture_shooting_preview() -> void:
	var sheet := Image.create(1780, 885, false, Image.FORMAT_RGBA8)
	beat_sim = preload("res://scripts/beat_validation.gd").fixture(self)
	beat_sim.units[2].cell = Vector2i(4, 3)
	beat_sim.units[2].p = Beat.center(Vector2i(4, 3))
	beat_sim.units[2].hp = 1
	beat_sim.loadouts[0].active = [["普通攻击", "无", "无"]]
	loadouts = beat_sim.loadouts
	units.assign(beat_sim.units)
	presentation.reset(units)
	started = true
	for row in range(3):
		step_forward()
		for column in range(4):
			if column > 0: advance_playback(Beat.SECONDS / 3.0 / playback_rate())
			animation_preview_caption = "%s / %.0f ms" % [["第1拍·瞄准预警", "第2拍·弹道到达才结算", "第3拍·后摇结束站立"][row], column * Beat.SECONDS / 3.0 * 1000.0] + " / HP %d / 已结算%d拍" % [units[2].hp, logic_frame]
			queue_redraw()
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image().get_region(Rect2i(20, 145, 890, 590))
			frame.resize(445, 295, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(frame, Rect2i(0, 0, 445, 295), Vector2i(column * 445, row * 295))
	sheet.save_png("res://reports/beat-shooting-preview.png")
	get_tree().quit()

func capture_telegraph_preview() -> void:
	var sheet := Image.create(1780, 590, false, Image.FORMAT_RGBA8)
	for row in range(2):
		beat_sim = preload("res://scripts/beat_telegraph_validation.gd").fixture(self)
		loadouts = beat_sim.loadouts
		units.assign(beat_sim.units)
		presentation.reset(units)
		started = true
		var skill := "蓄能贯穿" if row == 0 else "烈焰爆破"
		loadouts[0].active = [[skill, "无", "无"]]
		simulate(Beat.SECONDS)
		loadouts[0].active.clear()
		for column in range(4):
			var target: int = [1, 2, 3, 4][column] if row == 0 else [1, 2, 4, 5][column]
			while logic_frame < target:
				advance_visuals(Beat.SECONDS - presentation.beat_age)
				simulate(Beat.SECONDS)
			if column < 3: advance_visuals(Beat.SECONDS / 2)
			var incoming := preload("res://scripts/beat_telegraph.gd").cells(beat_sim, presentation.beat_age)
			animation_preview_caption = "%s / 剩%d拍 / %.0f%%" % [skill, incoming[0].remaining, incoming[0].progress * 100.0] if not incoming.is_empty() else skill + " / 落下"
			queue_redraw()
			await RenderingServer.frame_post_draw
			var frame := get_viewport().get_texture().get_image().get_region(Rect2i(20, 145, 890, 590))
			frame.resize(445, 295, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(frame, Rect2i(0, 0, 445, 295), Vector2i(column * 445, row * 295))
	sheet.save_png("res://reports/beat-telegraph-preview.png")
	get_tree().quit()
