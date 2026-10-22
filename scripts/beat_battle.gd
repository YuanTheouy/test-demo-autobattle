extends "res://scripts/battle.gd"
## UI adapter: the continuous prototype remains in main.tscn for comparison.
const Beat = preload("res://scripts/beat_simulation.gd")
const BASE_PLAYBACK_RATE := 0.5
const SOLDIER_PRESET := 9
var soldier_hint: Label
var beat_sim = Beat.new()
var presentation = preload("res://scripts/beat_presentation.gd").new()
var settle_visual := 0.0
var animation_preview_caption := ""

func _ready() -> void:
	team_presets = [SOLDIER_PRESET, SOLDIER_PRESET]
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Arial"])
	arena_view = preload("res://scripts/beat_view.gd").new()
	DisplayServer.window_set_title("AutoBattle — 8×8 节拍战斗 / beat-grid-combat")
	reset_walls()
	setup_navigation()
	setup_loadouts()
	setup_ui()
	reset_round()
	if "--beat-test" in OS.get_cmdline_user_args():
		preload("res://scripts/beat_validation.gd").run(self)
		get_tree().quit()
		return
	if "--beat-telegraph-preview" in OS.get_cmdline_user_args():
		set_physics_process(false)
		set_process(false)
		capture_telegraph_preview.call_deferred()
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

func preset_names() -> Array:
	return Tactics.NAMES + ["普通士兵"]

func preset_loadouts(index: int) -> Array:
	if index != SOLDIER_PRESET: return super.preset_loadouts(index)
	var soldier := {
		"active": [["站稳", "移动姿态", "有射位"], ["普通攻击", "优先队友目标", "无"], ["接敌", "无", "无"], ["站稳", "移动姿态", "无"]],
		"reaction": [["侧闪", "无", "无"]]
	}
	return [soldier.duplicate(true), soldier.duplicate(true)]

func basic_loadout() -> Dictionary:
	return preset_loadouts(SOLDIER_PRESET)[0]

func setup_loadouts() -> void:
	super.setup_loadouts()
	for loadout in loadouts: add_stand_rule(loadout)

func reset_walls() -> void:
	walls.assign([Rect2(240, 80, 80, 160), Rect2(320, 400, 80, 160)])
	wall_states.clear()
	wall_damage.clear()
	for index in range(walls.size()): wall_states.append({"id": index, "rect": walls[index], "hp": WALL_HP})

func add_stand_rule(loadout: Dictionary) -> void:
	for rule in loadout.active:
		if rule[0] in Beat.HIGH:
			loadout.active.push_front(["站稳", "移动姿态", "有射位"])
			return

func apply_preset(team: int, index: int) -> void:
	super.apply_preset(team, index)
	for member in range(2): add_stand_rule(loadouts[team * 2 + member])
	rebuild_editor()
	reset_round()

func setup_ui() -> void:
	super.setup_ui()
	for node in find_children("*", "Button", true, false):
		if node.text == "单帧 [N]":
			node.text = "单拍 [N]"
			node.tooltip_text = "N前进1拍；Shift+N前进4拍。新基准1倍速每拍0.5秒；0.5倍每拍1秒，2倍每拍0.25秒。"
		if node.text.begins_with("速度 "): node.tooltip_text = "新基准：1倍速每拍0.5秒；0.5倍每拍1秒；2倍每拍0.25秒。"
	for node in get_children():
		if node is Label and node.text == "AUTOBATTLE": node.text = "AUTOBATTLE / BEAT"
	update_beat_menus()
	soldier_hint = text_label(self, "普通士兵对练\n5血 · 普攻1伤害\n无大招", 14)
	soldier_hint.position = Vector2(700, 35)
	soldier_hint.modulate = Color("c8b997")

func rebuild_editor() -> void:
	# The legacy editor removes conditions it does not know; preserve beat-only ones.
	for loadout in loadouts:
		for kind in ["active", "reaction"]:
			for rule in loadout[kind]:
				for column in [1, 2]: rule[column] = small_hp_condition(rule[column])
	var saved := loadouts.duplicate(true)
	super.rebuild_editor()
	for uid in range(saved.size()): loadouts[uid] = saved[uid]
	update_beat_menus()

func small_hp_condition(text: String) -> String:
	return text.replace("HP≤50", "HP≤2")

func update_beat_menus() -> void:
	var entries := editor_entries()
	for index in range(editor_rows.size()):
		var menus: Array = editor_rows[index].menus
		for column in range(3):
			var menu: OptionButton = menus[column]
			if column > 0:
				for item in range(menu.item_count): menu.set_item_text(item, small_hp_condition(menu.get_item_text(item)))
			var additions: Array = ["站稳", "向左移动", "向右移动", "向上移动", "向下移动"] if column == 0 else ["站稳姿态", "移动姿态", "有射位"]
			for label in additions:
				var found := false
				for item in range(menu.item_count):
					if menu.get_item_text(item) == label: found = true
				if not found: menu.add_item(label)
			if index < entries.size():
				for item in range(menu.item_count):
					if menu.get_item_text(item) == entries[index].rule[column]: menu.select(item)
			if column == 0:
				for item in range(menu.item_count): menu.get_popup().set_item_tooltip(item, beat_help(menu.get_item_text(item)))
				menu.tooltip_text = beat_help(entries[index].rule[0]) if index < entries.size() else beat_help("留空")
			elif index < entries.size(): menu.tooltip_text = entries[index].rule[column]

func beat_help(skill: String) -> String:
	if skill == "站稳": return "耗1拍，移动姿态恢复站稳；不跨格。高级技能必须先站稳。预设附加有射位条件，可排序、改条件或删除。"
	if skill in Beat.MOVE or skill in ["向左移动", "向右移动", "向上移动", "向下移动"]: return "普通移动2拍一格；同方向可以连续走，换方向前自动站立1拍。移动硬直只能用PP侧闪取消；侧闪1拍一格。减速时普通移动额外1拍。"
	if skill == "侧闪": return "真实预警触发，1拍跨入安全相邻格，耗20精力。前摇取消退款，后摇取消不退款，释放硬直/碰撞中禁用；无安全格不触发。"
	if skill == "回春": return "25精力；治疗1血，上限5血。自己或3格内队友刚受伤时触发；冷却32拍，后摇1拍。"
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
	super.edit_rule_cell(index, column, value)
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
	if running:
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

func advance_playback(delta: float) -> void:
	var remaining := delta * playback_rate()
	while remaining > 0.00000001 and running:
		var slice := minf(remaining, Beat.SECONDS - accumulator)
		advance_visuals(slice)
		accumulator += slice
		remaining -= slice
		if accumulator + 0.00000001 >= Beat.SECONDS:
			accumulator = 0.0
			simulate(Beat.SECONDS)

func playback_rate() -> float:
	return BASE_PLAYBACK_RATE * speed * (ULTIMATE_SLOW if ultimate_aim >= 0 else 1.0)

func step_forward(frame_count := 1) -> void:
	running = false
	started = true
	deployment_drag = -1
	accumulator = 0.0
	for tick in range(4 if frame_count == 12 else frame_count): simulate(Beat.SECONDS)
	settle_visual = 0.65
	refresh_ui()
	queue_redraw()

func simulate(_dt: float) -> void:
	var before: Array = units.duplicate(true)
	var hp_before: Array = []
	for u in beat_sim.units: hp_before.append(u.hp)
	beat_sim.loadouts = loadouts
	beat_sim.tick()
	units.assign(beat_sim.units)
	presentation.begin(before, units, beat_sim)
	logic_frame = beat_sim.beat
	clock = ROUND_TIME - logic_frame * Beat.SECONDS
	shots = beat_sim.shots
	hits = beat_sim.hits
	reaction_counts = beat_sim.activations
	for u in units:
		if u.hp < hp_before[u.uid]: impacts.append({"p": u.p, "life": 0.65, "amount": hp_before[u.uid] - u.hp, "team": u.team})
		elif u.hp > hp_before[u.uid]: impacts.append({"p": u.p, "life": 0.65, "amount": u.hp - hp_before[u.uid], "team": u.team, "healing": true})
	for event in beat_sim.events: log_event(event)
	if beat_sim.finished and not finished:
		end_round(beat_sim.winner, beat_sim.result)
		settle_visual = 0.65

func log_event(message: String) -> void:
	logs.push_front("拍%03d  %s" % [logic_frame, message])
	if logs.size() > 8: logs.resize(8)

func action_state_label(u: Dictionary) -> String:
	if not u.has("pose"): return u.phase
	if u.mode == "移动硬直": return "移动硬直·余%d拍" % u.left
	if u.phase == "转向站立": return "转向站立·1拍"
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
	status_label.text = "第 %03d 拍  ·  %.1f倍速 · 每拍%.2f秒  |  整格位置 · 独立行动" % [logic_frame, speed, Beat.SECONDS / playback_rate()]
	if not started: status_label.text = "开局布阵  ·  8×8 节拍战斗  |  N 单拍 / Shift+N 四拍"
	var u: Dictionary = units[editor_unit]
	character_label.text = "%s%d · %s格 · %s · HP %d/%d · 盾%d" % ["蓝" if u.team == 0 else "红", u.member + 1, Beat.name_of(u.cell), action_state_label(u), u.hp, Beat.MAX_HP, u.shield]
	info_label.text = "所在格 %s · %s · 趋势 %s · 生命%d/%d · 护盾%d\n本拍：%s；规则触发%d次\n%s\n精力 %d/100 · 公共CD剩%d拍\n%s" % [Beat.name_of(u.cell), u.pose, "无" if u.trend == Vector2i.ZERO else direction_name(u.trend), u.hp, Beat.MAX_HP, u.shield, u.frame_branch, u.frame_triggers, u.reason, u.energy, ceili(u.cooldown / Beat.SECONDS), u.last_cancel]
	skill_help.text = ("普通士兵 · 5血 · 普攻1伤害 · 无大招。" if team_presets[u.team] == SOLDIER_PRESET else "5血 · 普攻1 · 重击2 · 大招2–3 · 敌方碰撞各扣1血。") + "\n移动2拍/格；换向先站立1拍；直走不断速。侧闪1拍。"
	for child in get_children():
		if child.get_script() == preload("res://scripts/ultimate_portrait.gd"):
			child.visible = team_presets[0] != SOLDIER_PRESET
	if soldier_hint != null: soldier_hint.visible = team_presets[0] == SOLDIER_PRESET
	for uid in range(roster_buttons.size()):
		var bot: Dictionary = units[uid]
		roster_buttons[uid].text = "%s %d · %s\nHP %d/%d · 盾%d · EN %d" % ["蓝方" if uid < 2 else "红方", uid % 2 + 1, bot.phase if bot.hp > 0 else "倒下", bot.hp, Beat.MAX_HP, bot.shield, bot.energy]
	for row in editor_rows:
		if row.slot >= 0 and u.rule_kind == row.kind and u.rule_slot == row.slot:
			row.state.text = "▶ " + action_state_label(u)

func beat_ultimate_available(uid: int) -> bool:
	var u: Dictionary = units[uid]
	return team_presets[u.team] != SOLDIER_PRESET and started and u.hp > 0 and u.ult_charge >= 100 and u.pose == "站稳" and u.energy >= 70

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
