extends Node2D
## Small, reviewable player loop; the legacy Init/Loop game is a separate scene.
const Sim = preload("res://scripts/dual_track_simulation.gd")
const BLUE := Color("50bdff")
const RED := Color("ff7583")
const GREEN := Color("71d8af")
const GOLD := Color("efcd84")
const INK := Color("0a1320")
const BEAT_SECONDS := 0.75
const BOARD_ORIGIN := Vector2(152, 232)
const TILE := 144.0
const SPAWNS := [Vector2i(0, 1), Vector2i(1, 0)]
const ENEMIES := [1, 3]
var sim = Sim.new()
var blue_profile := Sim.player_profile()
var enemy_index := 1
var speed := 1.0
var running := false
var step_pending := false
var segment_active := false
var fraction := 0.0
var controls: Dictionary = {}
var font: SystemFont
var comparison: Array = []
var last_events: Array[String] = []
var board_label: Label
var result_label: Label
var status_label: Label
var enemy_label: Label
var clock_label: Label
var play_button: Button
var comparison_label: Label
var track_labels: Dictionary = {}
var saved_result: Dictionary = {}

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Arial"])
	DisplayServer.window_set_title("AutoBattle — 双轨短交锋 / 只改一格")
	build_ui()
	restart()
	run_comparison()
	if "--dual-track-test" in OS.get_cmdline_user_args():
		validate_playback()
		get_tree().quit()
	if "--dual-track-preview" in OS.get_cmdline_user_args():
		set_process(false)
		capture_previews.call_deferred()

func make_label(text: String, pos: Vector2, size := 16, color := Color("ced9e7")) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.modulate = color
	add_child(label)
	return label

func button(text: String, pos: Vector2, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size.y = 36
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(callback)
	add_child(b)
	return b

func picker(options: Array, pos: Vector2, width: float, callback: Callable) -> OptionButton:
	var p := OptionButton.new()
	p.position = pos
	p.size = Vector2(width, 38)
	p.add_theme_font_override("font", font)
	p.add_theme_font_size_override("font_size", 16)
	for text in options: p.add_item(text)
	p.item_selected.connect(callback)
	add_child(p)
	return p

func build_ui() -> void:
	make_label("AUTOBATTLE / 短交锋", Vector2(36, 22), 27, GOLD)
	make_label("移动与武器同时执行 · 每方3士气 · 最多18拍 · 命中削减士气，棋子不消失", Vector2(36, 66), 15)
	clock_label = make_label("", Vector2(36, 106), 20)
	button("← 返回原型", Vector2(1440, 29), func(): get_tree().change_scene_to_file("res://puzzle_arena.tscn"))
	make_label("遭遇对象", Vector2(45, 161), 15)
	controls.enemy = picker(["警戒枪手", "追击枪手"], Vector2(130, 154), 190, func(i): enemy_index = i; restart())
	enemy_label = make_label("", Vector2(45, 197), 13, Color("a8bace"))
	make_label("站立/移动看腿；收招/击发看武器。移动不取消射击。", Vector2(800, 91), 14, Color("a6b8cd"))
	board_label = make_label("蓝方战术板 · 两条轨道同时运行", Vector2(800, 124), 23, BLUE)
	make_label("每轨1个判断＋最多3个动作；完成当前分支后重新判断。", Vector2(800, 155), 14)
	for lane in ["move", "weapon"]:
		var y := 205.0 if lane == "move" else 407.0
		make_label("移动轨" if lane == "move" else "武器轨", Vector2(800, y - 27), 20, GREEN if lane == "move" else GOLD)
		controls[lane] = []
		controls[lane].append(picker(Sim.CONDITIONS, Vector2(804, y + 38), 190, func(i): edit_cell(lane, 0, Sim.CONDITIONS[i])))
		var actions: Array = Sim.MOVE_ACTIONS if lane == "move" else Sim.WEAPON_ACTIONS
		controls[lane].append(picker(actions, Vector2(1080, y + 5), 150, func(i): edit_cell(lane, 1, actions[i])))
		controls[lane].append(picker(["不续接"] + actions, Vector2(1300, y + 5), 150, func(i): edit_cell(lane, 2, (["不续接"] + actions)[i])))
		controls[lane].append(picker(actions, Vector2(1080, y + 72), 150, func(i): edit_cell(lane, 3, actions[i])))
		make_label("成立", Vector2(1024, y - 8), 14, GREEN)
		make_label("否则", Vector2(1024, y + 58), 14, Color("9faec2"))
		make_label("可选续接", Vector2(1312, y - 17), 12, Color("94a5bc"))
		track_labels[lane] = make_label("", Vector2(804, y + 133), 14)
	button("只改这一格：收招 ↔ 击发", Vector2(800, 591), flip_condition)
	button("恢复原方案", Vector2(1080, 591), restore_profile)
	button("重跑两类敌人对照", Vector2(1240, 591), run_comparison)
	comparison_label = make_label("", Vector2(812, 654), 16)
	make_label("表内数字为 蓝:红剩余士气；是完整重跑结果，不是未来预测。", Vector2(812, 774), 13, Color("97a9bd"))
	play_button = button("播放 [空格]", Vector2(36, 747), toggle_play)
	button("下一拍 [N]", Vector2(175, 747), step_once)
	button("同局重试 [R]", Vector2(310, 747), restart)
	button("速度 1倍", Vector2(465, 747), func():
		speed = 0.5 if speed == 1.0 else (2.0 if speed == 0.5 else 1.0)
		for child in get_children():
			if child is Button and child.text.begins_with("速度 "): child.text = "速度 %s倍" % speed
	)
	button("看这格的影响", Vector2(595, 747), func(): run_comparison(); restart())
	result_label = make_label("", Vector2(46, 683), 17, GOLD)
	status_label = make_label("空格播放；N完整演出一拍再结算；R保留战术与站位重试。", Vector2(36, 797), 14)
	sync_pickers()

func sync_pickers() -> void:
	for lane in ["move", "weapon"]:
		var rule: Dictionary = blue_profile[lane]
		var actions: Array = Sim.MOVE_ACTIONS if lane == "move" else Sim.WEAPON_ACTIONS
		controls[lane][0].select(Sim.CONDITIONS.find(rule.condition))
		controls[lane][0].add_theme_color_override("font_color", GOLD if lane == "weapon" and rule.condition != "敌人收招" else Color("d8e1ed"))
		controls[lane][1].select(actions.find(rule.yes[0]))
		controls[lane][2].select((["不续接"] + actions).find(rule.yes[1] if rule.yes.size() > 1 else "不续接"))
		controls[lane][3].select(actions.find(rule.no[0]))

func edit_cell(lane: String, slot: int, value: String) -> void:
	var rule: Dictionary = blue_profile[lane]
	if slot == 0: rule.condition = value
	elif slot == 1: rule.yes[0] = value
	elif slot == 2:
		rule.yes.resize(1)
		if value != "不续接": rule.yes.append(value)
	else: rule.no[0] = value
	sync_pickers()
	restart()
	run_comparison()

func flip_condition() -> void:
	edit_cell("weapon", 0, "敌人击发" if blue_profile.weapon.condition == "敌人收招" else "敌人收招")

func restore_profile() -> void:
	blue_profile = Sim.player_profile()
	sync_pickers()
	restart()
	run_comparison()

func restart() -> void:
	sim.reset([blue_profile, Sim.enemy_profile(ENEMIES[enemy_index])], SPAWNS)
	running = false
	step_pending = false
	segment_active = false
	fraction = 0.0
	last_events.clear()
	controls.enemy.select(enemy_index)
	enemy_label.text = "红方：距离≥3格时接敌，否则站立；始终吊射。" if enemy_index == 0 else "红方：持续接敌；始终吊射。与警戒枪手仅移动规则不同。"
	refresh_labels()
	queue_redraw()

func toggle_play() -> void:
	if sim.finished: restart()
	running = not running
	step_pending = false
	if running: segment_active = true
	refresh_labels()

func step_once() -> void:
	if sim.finished or step_pending: return
	running = false
	step_pending = true
	segment_active = true
	refresh_labels()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_SPACE: toggle_play()
	elif event.keycode == KEY_N: step_once()
	elif event.keycode == KEY_R: restart()

func _process(delta: float) -> void:
	advance_playback(delta)

func advance_playback(delta: float) -> void:
	if not running and not step_pending: return
	var remaining := delta * speed / BEAT_SECONDS
	while remaining > 0.0000001 and not sim.finished and (running or step_pending):
		var used := minf(remaining, 1.0 - fraction)
		fraction += used
		remaining -= used
		if fraction >= 0.9999999:
			sim.tick()
			fraction = 0.0
			last_events.clear()
			for shot in sim.history[-1].shots:
				last_events.append("%s方吊射%s %s" % ["蓝" if shot.source == 0 else "红", "命中" if shot.hit else "落空", cell_name(shot.cell)])
			if step_pending or sim.finished:
				running = false
				step_pending = false
				segment_active = false
	refresh_labels()
	queue_redraw()

func refresh_labels() -> void:
	var used := 0
	for lane in ["move", "weapon"]: used += 1 + blue_profile[lane].yes.size() + blue_profile[lane].no.size()
	board_label.text = "蓝方战术板 · %d/8格 · 两条轨道同时运行" % used
	clock_label.text = "第 %02d / 18 拍     蓝方士气 %d     红方士气 %d" % [sim.beat, sim.morale[0], sim.morale[1]]
	if segment_active: clock_label.text += "     播放 %02d → %02d" % [sim.beat, sim.beat + 1]
	play_button.text = "暂停 [空格]" if running else ("再看一局 [空格]" if sim.finished else "播放 [空格]")
	if sim.finished:
		result_label.text = "%s · %s（士气 %d:%d）" % [sim.end_reason, "平局" if sim.winner < 0 else ("蓝方占优" if sim.winner == 0 else "红方占优"), sim.morale[0], sim.morale[1]]
		status_label.text = "交锋已结算，双方保留在场。改一格或R同局重试；切换敌人检查这格是否仍然有用。"
	else:
		result_label.text = "第%d拍：%s" % [sim.beat, "；".join(last_events)] if not last_events.is_empty() else "移动2拍；瞄准、击发、后摇各1拍；吊射CD6拍。"
		status_label.text = "当前测试：%s · 只改武器判断，其他动作与出生位置不变。" % blue_profile.weapon.condition
	var u: Dictionary = shown_unit(0)
	for lane in ["move", "weapon"]:
		track_labels[lane].text = "当前：%s  ·  选择时：%s" % [u[lane + "_action"], u[lane + "_test"]]

func shown_unit(uid: int) -> Dictionary:
	return sim.next_segment.units[uid] if segment_active and not sim.next_segment.is_empty() else sim.units[uid]

func run_comparison() -> void:
	comparison.clear()
	for kind in ENEMIES:
		var pair: Array = []
		for timing in ["敌人收招", "敌人击发"]:
			var profile: Dictionary = blue_profile.duplicate(true)
			profile.weapon.condition = timing
			var trial := Sim.new()
			trial.reset([profile, Sim.enemy_profile(kind)], SPAWNS)
			pair.append(trial.run())
		comparison.append(pair)
	comparison_label.text = "只改武器判断        敌人收招         敌人击发\n警戒枪手                   %d:%d                    %d:%d\n追击枪手                   %d:%d                    %d:%d" % [comparison[0][0].morale[0], comparison[0][0].morale[1], comparison[0][1].morale[0], comparison[0][1].morale[1], comparison[1][0].morale[0], comparison[1][0].morale[1], comparison[1][1].morale[0], comparison[1][1].morale[1]]
	comparison_label.tooltip_text = "两列使用当前动作配置，唯一差异是武器判断；所有结果都从相同出生格完整重跑。"

static func cell_name(c: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + c.x), c.y + 1]

func point(c: Vector2) -> Vector2:
	return BOARD_ORIGIN + (c + Vector2(0.5, 0.5)) * TILE

func visual_cell(u: Dictionary) -> Vector2:
	return (Vector2(u.cell) + Vector2(u.destination)) * 0.5 if u.move_mode == "跨格" else Vector2(u.cell)

func position_of(uid: int) -> Vector2:
	var current: Dictionary = sim.units[uid]
	if not segment_active or sim.next_segment.is_empty(): return point(visual_cell(current))
	return point(visual_cell(current).lerp(visual_cell(sim.next_segment.units[uid]), fraction))

func text_at(text: String, pos: Vector2, size: int, color: Color) -> void:
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	if units_unready(): return
	draw_rect(Rect2(0, 0, 1640, 830), Color("080f19"))
	draw_style_box(panel_style(Color("101d2a")), Rect2(36, 145, 706, 588))
	for y in range(3):
		for x in range(3):
			var rect := Rect2(BOARD_ORIGIN + Vector2(x,y) * TILE, Vector2.ONE * TILE)
			draw_rect(rect, Color("172b3c") if (x+y)%2 == 0 else Color("142536"))
			draw_rect(rect.grow(-1), Color("3b5367"), false, 1.0)
			text_at(cell_name(Vector2i(x,y)), rect.position + Vector2(8, 20), 13, Color("70879a"))
	for lane in ["move", "weapon"]: draw_track(lane)
	draw_style_box(panel_style(Color("132131")), Rect2(793, 639, 803, 162))
	if segment_active and not sim.next_segment.is_empty():
		for uid in range(2):
			var u: Dictionary = sim.next_segment.units[uid]
			if u.weapon_action in ["瞄准", "击发"]:
				var color := BLUE if uid == 0 else RED
				var rect := Rect2(BOARD_ORIGIN + Vector2(u.lock) * TILE, Vector2.ONE * TILE).grow(-7 - uid * 5)
				draw_rect(rect, Color(color, 0.10))
				draw_rect(rect, Color(color, 0.7), false, 3)
				var progress := fraction * 0.5 if u.weapon_action == "瞄准" else 0.5 + fraction * 0.5
				draw_line(rect.position + Vector2(0,rect.size.y), rect.position + Vector2(rect.size.x * progress,rect.size.y), color, 6, true)
	for uid in range(2):
		var u: Dictionary = shown_unit(uid)
		if u.move_mode == "跨格" or u.move_action == "移动第2拍":
			draw_dashed_line(position_of(uid), point(Vector2(u.destination)), Color(GREEN,0.65), 2, 8, true)
			draw_circle(point(Vector2(u.destination)), 9, GREEN, false, 2, true)
	for uid in range(2): draw_bot(uid)
	if segment_active and not sim.next_segment.is_empty():
		for shot in sim.next_segment.shots:
			var color := BLUE if shot.source == 0 else RED
			var start := point(visual_cell(sim.units[shot.source])) - Vector2(0,18)
			var dest := point(Vector2(shot.cell))
			var p := start.lerp(dest, fraction) - Vector2(0, sin(fraction * PI) * 82)
			var tail_t := maxf(0, fraction - 0.1)
			var tail := start.lerp(dest, tail_t) - Vector2(0, sin(tail_t * PI) * 82)
			draw_line(tail,p,Color(color,0.3),12,true)
			draw_line(tail,p,color,4,true)
			draw_circle(p,6,Color("fff1ce"))
	if not segment_active and not sim.history.is_empty():
		for shot in sim.history[-1].shots:
			var color := BLUE if shot.source == 0 else RED
			draw_arc(point(Vector2(shot.cell)), 38, 0, TAU, 32, color, 3, true)
			text_at("命中 -1士气" if shot.hit else "落空", point(Vector2(shot.cell)) + Vector2(-43,62), 14, color)

func units_unready() -> bool:
	return font == null or sim.units.size() != 2

func panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("35485e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	return style

func draw_track(lane: String) -> void:
	var y := 205.0 if lane == "move" else 407.0
	draw_style_box(panel_style(Color("142133")), Rect2(790,y - 35,806,196))
	var color := GREEN if lane == "move" else GOLD
	draw_line(Vector2(997,y+57),Vector2(1020,y+57),color,2,true)
	draw_line(Vector2(1020,y+24),Vector2(1020,y+91),color,2,true)
	for yy in [y+24,y+91]:
		draw_line(Vector2(1020,yy),Vector2(1074,yy),color,2,true)
		draw_line(Vector2(1074,yy),Vector2(1066,yy-5),color,2,true)
		draw_line(Vector2(1074,yy),Vector2(1066,yy+5),color,2,true)
	draw_line(Vector2(1237,y+24),Vector2(1294,y+24),color,2,true)
	var return_color := Color(color,0.25)
	draw_polyline(PackedVector2Array([Vector2(1460,y+24),Vector2(1510,y+24),Vector2(1510,y+121),Vector2(900,y+121),Vector2(900,y+82)]),return_color,1.5,true)
	draw_line(Vector2(1238,y+91),Vector2(1510,y+91),return_color,1.5,true)
	text_at("完整执行后重查",Vector2(1360,y+116),12,Color("8f9db1"))
	var u: Dictionary = shown_unit(0)
	var action: String = u[lane+"_action"]
	if not segment_active and sim.beat == 0: return
	if "冷却" in action or "无路" in action: return
	var branch: String = u[lane+"_branch"]
	var slot: int = u.get(lane+"_running_slot",0)
	var rect := Rect2(1076,y+(1 if branch == "yes" else 68),158,46)
	if branch == "yes" and slot == 1: rect.position.x = 1296
	var highlight := panel_style(Color(color,0.25))
	highlight.border_color = color
	highlight.set_border_width_all(2)
	draw_style_box(highlight,rect)

func draw_bot(uid: int) -> void:
	var p := position_of(uid)
	var color := BLUE if uid == 0 else RED
	var u: Dictionary = shown_unit(uid)
	draw_circle(p + Vector2(0,13),31,Color(0,0,0,0.3))
	draw_circle(p,28,color.darkened(0.35))
	draw_circle(p-Vector2(0,5),25,color)
	var target := point(Vector2(u.lock)) if u.weapon_action in ["瞄准","击发","后摇"] else position_of(1-uid)
	var dir := (target-p).normalized()
	draw_line(p-Vector2(0,5),p-Vector2(0,5)+dir*36,Color("d5e5eb"),7,true)
	text_at("蓝" if uid == 0 else "红",p+Vector2(-8,2),18,INK)
	for pip in range(3): draw_rect(Rect2(p+Vector2(-29+pip*20,-51),Vector2(17,6)),color if pip < sim.morale[uid] else Color("344455"))
	text_at("移动："+u.move_action,p+Vector2(-53,53),12,GREEN)
	text_at("武器："+u.weapon_action,p+Vector2(-53,70),12,GOLD)

func validate_playback() -> void:
	restore_profile()
	assert(comparison[0][0].morale == [3,3] and comparison[0][1].morale == [3,1])
	assert(comparison[1][0].morale == [3,2] and comparison[1][1].morale == [3,3])
	for enemy_id in range(2):
		controls.enemy.item_selected.emit(enemy_id)
		for timing in ["敌人收招", "敌人击发"]:
			controls.weapon[0].item_selected.emit(Sim.CONDITIONS.find(timing))
			var expected: Dictionary = comparison[enemy_id][0 if timing == "敌人收招" else 1]
			for endpoint in range(1,19):
				step_once()
				advance_playback(BEAT_SECONDS)
			assert(sim.finished and sim.history == expected.history, "All four displayed outcomes must match full UI playback")
	controls.enemy.item_selected.emit(1)
	restore_profile()
	var baseline: Dictionary = blue_profile.duplicate(true)
	controls.weapon[0].item_selected.emit(Sim.CONDITIONS.find("敌人击发"))
	assert(blue_profile.move == baseline.move and blue_profile.weapon.yes == baseline.weapon.yes and blue_profile.weapon.no == baseline.weapon.no)
	assert(blue_profile.weapon.condition == "敌人击发")
	restore_profile()
	for endpoint in range(1,19):
		step_once()
		var old: Array = sim.units.duplicate(true)
		var hp: Array = sim.morale.duplicate()
		advance_playback(BEAT_SECONDS*0.5)
		assert(sim.beat == endpoint-1 and sim.units == old and sim.morale == hp)
		advance_playback(BEAT_SECONDS*0.5)
		assert(sim.beat == endpoint and not step_pending and not segment_active)
	assert(sim.finished and sim.morale == [3,2] and sim.winner == 0)
	var settled: Array = sim.history.duplicate(true)
	advance_playback(100)
	assert(sim.history == settled)
	for rate in [0.5,1.0,2.0]:
		restart()
		speed = rate
		toggle_play()
		advance_playback(100)
		assert(sim.history == settled and not running)
	speed = 1.0
	restart()
	var report := {"checks":["parallel move/weapon tracks", "all four comparison cells verified through actual UI playback", "one actual dropdown edit changes only weapon condition", "same initial-state reversal across two enemies", "animation completes before cells/morale/beat settle", "18-beat stop; no post-result simulation", "0.5/1/2x deterministic playback"], "comparison":comparison.map(func(pair): return pair.map(func(r): return {"morale":r.morale,"winner":r.winner,"hits":r.hits,"concurrent":r.concurrent}))}
	var f := FileAccess.open("res://reports/dual-track-playback.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	print("DUAL TRACK UI PASSED: single-cell edit, full 18-beat animated settlement, parallel tracks, speed independence and final stop")

func capture_previews() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/dual-track-start.png")
	for endpoint in range(1,19):
		step_once()
		advance_playback(BEAT_SECONDS*0.5)
		await RenderingServer.frame_post_draw
		if endpoint == 12: get_viewport().get_texture().get_image().save_png("res://reports/dual-track-moving-shot.png")
		advance_playback(BEAT_SECONDS*0.5)
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reports/dual-track-result.png")
	get_tree().quit()
