extends "res://scripts/arena_view.gd"
var warnings: Array = []
var occupants: Array = []

func render(game) -> void:
	warnings = preload("res://scripts/beat_telegraph.gd").cells(game.beat_sim, game.presentation.beat_age, game.segment_preview) if game.show_aim else []
	occupants = preload("res://scripts/beat_occupancy.gd").markers(game.units)
	super.render(game)
	if not g.animation_preview_caption.is_empty():
		g.draw_rect(Rect2(35, 151, 420, 30), Color("0b1522"))
		g.draw_string(g.font, Vector2(44, 174), g.animation_preview_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	g.draw_rect(Rect2(35, 705, 865, 28), Color("0b1522"))
	g.draw_string(g.font, Vector2(46, 723), "阵营色四角框：当前格  /  绿色小圆圈：移动目标  /  金色方块：站稳  /  绿箭头：移动", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("b8d1df"))

func draw_occupancy_marker(marker: Dictionary) -> void:
	var color: Color = g.BLUE if marker.team == 0 else g.RED
	var pose_color := Color("f5ce78") if marker.stationary else Color("69e3b3")
	var inset: float = 12.0 + marker.lane * 5.0
	var a := Vector2(marker.cell) * 80 + Vector2.ONE * inset
	var start := project(a + Vector2(0, 80 - 2 * inset), 1)
	var end := project(a + Vector2.ONE * (80 - 2 * inset), 1)
	var normal := (end - start).normalized().orthogonal()
	var width := 2.8 if marker.uid == g.selected else 1.8
	# Open corner brackets identify the current cell, not a future destination.
	var radius: float = 27.0 - marker.lane * 4.0
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			var corner: Vector2 = marker.p + Vector2(sx, sy) * radius
			line(corner, corner - Vector2(sx * 10, 0), Color(color.lightened(0.25), 0.95), width, 2)
			line(corner, corner - Vector2(0, sy * 10), Color(color.lightened(0.25), 0.95), width, 2)
	# Pose is communicated on the near edge; everything stays below actors.
	var from := start if marker.stationary else start.lerp(end, 0.18)
	var to := end if marker.stationary else start.lerp(end, 0.82)
	g.draw_line(from, to, Color("08121d"), width + 3, true)
	g.draw_line(from, to, color.lightened(0.3), width, true)
	var state_icon := start.lerp(end, 0.5) + normal * 4
	if marker.stationary:
		for cap in [start, end]: g.draw_line(cap - normal * 2, cap + normal * 3, color.lightened(0.3), width, true)
		g.draw_rect(Rect2(state_icon - Vector2(2.5, 2.5), Vector2(5, 5)), pose_color)
	elif marker.trend != Vector2i.ZERO:
		var direction := (project(marker.p + Vector2(marker.trend), 1) - project(marker.p, 1)).normalized()
		g.draw_line(state_icon - direction * 4, state_icon + direction * 5, pose_color, 2, true)
		g.draw_line(state_icon + direction * 5, state_icon + direction * 5 - direction.rotated(0.6) * 6, pose_color, 2, true)
		g.draw_line(state_icon + direction * 5, state_icon + direction * 5 - direction.rotated(-0.6) * 6, pose_color, 2, true)
	var body: Vector2 = display_position(g.units[marker.uid])
	if body.distance_to(marker.p) > 10:
		g.draw_dashed_line(project(body, 1), project(marker.p, 1), Color(color.lightened(0.5), 0.6), 1.5, 4.0, true)
	var anchor := project(marker.p, 1)
	var identity_width: float = g.font.get_string_size(marker.identity, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var pose_width: float = g.font.get_string_size(marker.pose_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var total := identity_width + pose_width + 17.0
	var pos := anchor + Vector2(-total / 2, 29 + marker.lane * 18)
	var rect := Rect2(pos + Vector2(0, -12), Vector2(total, 17))
	g.draw_rect(rect, Color(0.035, 0.08, 0.13, 0.8))
	g.draw_string(g.font, pos + Vector2(5, 0), marker.identity, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color.lightened(0.5))
	g.draw_line(pos + Vector2(identity_width + 9, -9), pos + Vector2(identity_width + 9, 2), Color(color, 0.4), 1)
	g.draw_string(g.font, pos + Vector2(identity_width + 13, 0), marker.pose_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, pose_color)

func draw_warning(warning: Dictionary, alpha := 1.0) -> void:
	var color: Color = g.ATTACK_BLUE if warning.team == 0 else g.ATTACK_RED
	var inset := 5.0 if warning.team == 0 else 9.0
	var a := Vector2(warning.cell) * 80.0 + Vector2.ONE * inset
	var b := a + Vector2(80.0 - inset * 2.0, 0)
	var c := a + Vector2.ONE * (80.0 - inset * 2.0)
	var d := a + Vector2(0, 80.0 - inset * 2.0)
	var outline := PackedVector2Array([project(a, 1), project(b, 1), project(c, 1), project(d, 1), project(a, 1)])
	g.draw_polyline(outline, Color(color, alpha * (0.9 if warning.remaining == 0 else 0.35)), 2.0, true)
	# Each segment represents one beat from lock-on through impact. Keep those
	# divisions fixed as time passes so the filled segments show elapsed beats.
	var start := project(d, 2)
	var end := project(c, 2)
	var normal := (end - start).normalized().orthogonal()
	g.draw_line(start, end, Color("111e2b", alpha), 7.0, true)
	g.draw_line(start, end, Color(color, alpha * 0.3), 4.0, true)
	var brightness := 1.0 if warning.remaining <= 1 else 0.75
	if warning.progress > 0:
		g.draw_line(start, start.lerp(end, warning.progress), Color(color.lightened(0.3 if warning.remaining <= 1 else 0.0), alpha * brightness), 4.0, true)
	for fraction in preload("res://scripts/beat_telegraph.gd").divisions(warning.total_beats):
		var mark := start.lerp(end, fraction)
		g.draw_line(mark - normal * 3, mark + normal * 3, Color(0.04, 0.08, 0.13, alpha * 0.8), 1.0, true)
	var text := "落下" if warning.remaining == 0 else "%d拍" % warning.remaining
	var pos := project(g.Beat.center(warning.cell)) + Vector2(-37 if warning.team == 0 else 16, 5)
	g.draw_rect(Rect2(pos + Vector2(-3, -11), Vector2(26, 15)), Color(0.03, 0.07, 0.12, alpha * 0.85))
	g.draw_string(g.font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(color.lightened(0.5), alpha))

func deployment_grid() -> void:
	grid()

func grid() -> void:
	for n in range(1, 8):
		line(Vector2(n * 80, 0), Vector2(n * 80, 640), Color(0.6, 0.8, 0.9, 0.32))
		line(Vector2(0, n * 80), Vector2(640, n * 80), Color(0.6, 0.8, 0.9, 0.32))
	for n in range(8):
		g.draw_string(g.font, project(Vector2((n + 0.5) * 80, 0)) + Vector2(0, -8), String.chr(65 + n), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("aec9d8"))
		g.draw_string(g.font, project(Vector2(0, (n + 0.5) * 80)) + Vector2(-18, 0), str(n + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("aec9d8"))

func paint_cell(cell: Vector2i, color: Color, inset := 3.0) -> void:
	var p := Vector2(cell) * 80 + Vector2.ONE * inset
	var size := 80 - inset * 2
	polygon([p, p + Vector2(size, 0), p + Vector2(size, size), p + Vector2(0, size)], color)

func ground_effects() -> void:
	if g.started: grid()
	for cell in g.beat_sim.blocked_cells: paint_cell(cell, Color(0.9, 0.25, 0.25, 0.12))
	for warning in warnings:
		var color: Color = g.ATTACK_BLUE if warning.team == 0 else g.ATTACK_RED
		paint_cell(warning.cell, Color(color, 0.08))
	for burst in g.presentation.bursts:
		if burst.age < 0: continue
		var color: Color = g.ATTACK_BLUE if burst.team == 0 else g.ATTACK_RED
		paint_cell(g.Beat.cell_of(burst.p), Color(color, 0.5 * (1.0 - burst.age / 0.35)))
	for marker in occupants:
		var color: Color = g.BLUE if marker.team == 0 else g.RED
		paint_cell(marker.cell, Color(color, 0.16 if marker.uid == g.selected else 0.09), 2.0)
	# All board overlays, including warnings and labels, belong below robots/walls.
	for warning in warnings: draw_warning(warning)
	for burst in g.presentation.bursts:
		if burst.age < 0: continue
		if burst.age < 0.18:
			draw_warning({"cell": g.Beat.cell_of(burst.p), "team": burst.team, "progress": 1.0, "remaining": 0, "total_beats": burst.total_beats}, 1.0 - burst.age / 0.18)
	for u in g.units:
		if u.hp <= 0: continue
		var p := display_position(u)
		draw_movement_guide(u)
		if u.uid == g.selected: ring(p, 30, Color.WHITE, 2)
		if u.mode == "碰撞":
			ring(u.p, 36, Color("ffdf84"), 4)
			line(u.p, g.Beat.center(u.return_cell), Color("ffdf84"), 2)
	if not g.started and g.selected >= 0:
		var cell: Vector2i = g.deployment_cell(g.deployment_cursor)
		if cell.x >= 0 and cell.y >= 0 and cell.x < 8 and cell.y < 8:
			paint_cell(cell, Color(0.3, 0.9, 0.6, 0.3) if g.can_deploy(g.selected, cell) else Color(1, 0.3, 0.3, 0.3))
	for marker in occupants: draw_occupancy_marker(marker)

func draw_movement_guide(u: Dictionary) -> void:
	if not g.started: return
	var guide: Dictionary = g.presentation.guide(u)
	if guide.is_empty(): return
	var color := Color("ffdf84") if guide.bounce else Color("69e3b3")
	var origin := project(guide.from, 2)
	var target := project(guide.to, 2)
	var direction := (target - origin).normalized()
	var tip := target - direction * 8
	g.draw_line(origin, tip, Color(color, 0.15), 8.0, true)
	g.draw_dashed_line(origin, tip, Color(color, 0.9), 2.0, 7.0, true)
	g.draw_line(tip, tip - direction.rotated(0.5) * 10, color, 2.0, true)
	g.draw_line(tip, tip - direction.rotated(-0.5) * 10, color, 2.0, true)
	var center: Vector2 = guide.to
	disc(center, 10, Color(color, 0.1), 2)
	ring(center, 10, color, 2.0, 1.0, 2)
	disc(center, 2.5, color, 2)
	# Arrival is already identified by the fixed cell/pose nameplate.
	if Vector2(guide.to).is_equal_approx(u.p) and u.phase in ["跨格", "侧闪跨格", "弹回"]: return
	var caption := "%s · %s" % [g.Beat.name_of(g.Beat.cell_of(guide.to)), guide.text]
	var pos := target + Vector2(22, 27)
	var width: float = g.font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	g.draw_rect(Rect2(pos + Vector2(-3, -11), Vector2(width + 6, 15)), Color(0.03, 0.07, 0.12, 0.9))
	g.draw_string(g.font, pos, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)

func ultimate_preview() -> void:
	if g.ultimate_aim < 0: return
	var u: Dictionary = g.units[g.ultimate_aim]
	for cell in g.beat_sim.coverage(u, g.ultimate_name(u.uid), g.Beat.cell_of(g.ultimate_cursor)):
		paint_cell(cell, Color(1, 0.8, 0.35, 0.5))

func draw_wall(state: Dictionary, alpha: float) -> void:
	box(state.rect.position, state.rect.size, 48, Color("58758b"), alpha)
	g.draw_string(g.font, project(state.rect.get_center(), 61) + Vector2(-24, 0), "固定掩体", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c9d7e1"))

func visual_unit(u: Dictionary) -> Dictionary:
	var visual: Dictionary = g.presentation.visual(u)
	visual.hide_action_label = true
	visual.intent = g.action_state_label(visual)
	return visual

func display_position(u: Dictionary) -> Vector2:
	return g.presentation.position(u)

func robot(u: Dictionary) -> void:
	var shown := visual_unit(u)
	super.robot(shown)
	if shown.hp > 0 and shown.phase == "前摇":
		var track: Dictionary = g.presentation.tracks[u.uid]
		var total: float = maxf(1.0, g.beat_sim.windup(shown.active_skill))
		var remaining: float = shown.left if shown.mode == "前摇" else 0.0
		var progress := clampf((total - remaining - 1.0 + track.age / 0.25) / total, 0.0, 1.0)
		var color: Color = g.BLUE if u.team == 0 else g.RED
		ring(display_position(u), 33, Color(color, 0.35), 2)
		ring(display_position(u), 33, color.lightened(0.5), 3, progress)

func air_effects() -> void:
	for flight in g.presentation.flights:
		var t: float = clampf(flight.age / flight.duration, 0.0, 1.0)
		var color: Color = g.ATTACK_BLUE if flight.team == 0 else g.ATTACK_RED
		if flight.get("beam", false):
			line(flight.from, flight.to, Color(color, (1.0 - t) * 0.3), 14, 28)
			line(flight.from, flight.to, Color(color, 1.0 - t), 4, 28)
			continue
		var p: Vector2 = Vector2(flight.from).lerp(flight.to, t)
		var height := 28.0 + (sin(t * PI) * 100.0 if flight.arc else 0.0)
		var tail_t := maxf(0.0, t - 0.12)
		var tail: Vector2 = Vector2(flight.from).lerp(flight.to, tail_t)
		var tail_h := 28.0 + (sin(tail_t * PI) * 100.0 if flight.arc else 0.0)
		g.draw_line(project(tail, tail_h), project(p, height), Color(color, 0.3), 10, true)
		g.draw_line(project(tail, tail_h), project(p, height), color, 3, true)
		g.draw_circle(project(p, height), 5 if flight.arc else 3, Color("fff5db"))
	for burst in g.presentation.bursts:
		if burst.age < 0: continue
		var t: float = burst.age / 0.35
		var color: Color = g.ATTACK_BLUE if burst.team == 0 else g.ATTACK_RED
		ring(burst.p, 8.0 + t * 40.0, Color(color, 1.0 - t), 3)
		for i in range(6):
			var direction := Vector2.from_angle(i * TAU / 6)
			line(burst.p + direction * t * 25.0, burst.p + direction * (t * 25.0 + 9.0), Color(color, 1.0 - t), 2, sin(t * PI) * 25.0)

func health_capacity() -> int:
	return g.Beat.MAX_HP

func label(u: Dictionary) -> void:
	var visual := visual_unit(u)
	super.label(visual)
	if u.hp > 0:
		var bar := project(visual.p, 57) + Vector2(-31, -8)
		g.draw_rect(Rect2(bar, Vector2(62, 7)), Color("0b1520"))
		var color: Color = g.BLUE if u.team == 0 else g.RED
		for pip in range(health_capacity()):
			g.draw_rect(Rect2(bar + Vector2(1 + pip * 12, 1), Vector2(10, 5)), color if pip < u.hp else Color("304052"))
		if u.shield > 0:
			g.draw_string(g.font, project(visual.p, 57) + Vector2(34, -14), "盾%d" % u.shield, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a5efff"))
		g.draw_string(g.font, project(visual.p, 83) + Vector2(-28, 0), g.action_state_label(u), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e9d69e"))
