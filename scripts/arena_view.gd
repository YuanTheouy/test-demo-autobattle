extends RefCounted
# Presentation only: world collision remains a continuous, flat 640 × 640 arena.
const CENTER := Vector2(465, 205)
const AX := Vector2(0.65, 0.39)
const AY := Vector2(-0.65, 0.39)
var g

func project(p: Vector2, height := 0.0) -> Vector2:
	return CENTER + AX * p.x + AY * p.y - Vector2(0, height)

func unproject(p: Vector2) -> Vector2:
	var q := p - CENTER
	return Vector2((q.x / AX.x + q.y / AX.y) / 2, (q.y / AX.y - q.x / AX.x) / 2)

func polygon(points: Array, color: Color, height := 0.0) -> void:
	var screen := PackedVector2Array()
	for p in points: screen.append(project(p, height))
	g.draw_colored_polygon(screen, color)

func ring(p: Vector2, radius: float, color: Color, width := 1.5, progress := 1.0, height := 0.0) -> void:
	if progress <= 0: return
	var points := PackedVector2Array()
	for i in range(65): points.append(project(p + Vector2.from_angle(-PI / 2 + TAU * progress * i / 64.0) * radius, height))
	g.draw_polyline(points, color, width, true)

func disc(p: Vector2, radius: float, color: Color, height := 0.0) -> void:
	var points: Array = []
	for i in range(64): points.append(p + Vector2.from_angle(TAU * i / 64.0) * radius)
	polygon(points, color, height)

func line(a: Vector2, b: Vector2, color: Color, width := 1.0, height := 0.0) -> void:
	g.draw_line(project(a, height), project(b, height), color, width, true)

func strip(a: Vector2, b: Vector2, radius: float, color: Color, height := 0.0) -> void:
	var n := (b - a).normalized().orthogonal() * radius
	polygon([a - n, b - n, b + n, a + n], color, height)

func box(p: Vector2, size: Vector2, height: float, color: Color, alpha := 1.0) -> void:
	var a := p
	var b := p + Vector2(size.x, 0)
	var c := p + size
	var d := p + Vector2(0, size.y)
	var top := PackedVector2Array([project(a, height), project(b, height), project(c, height), project(d, height)])
	g.draw_colored_polygon(PackedVector2Array([project(b), project(c), project(c, height), project(b, height)]), Color(color.darkened(0.36), alpha))
	g.draw_colored_polygon(PackedVector2Array([project(c), project(d), project(d, height), project(c, height)]), Color(color.darkened(0.57), alpha))
	g.draw_colored_polygon(top, Color(color, alpha))
	top.append(top[0])
	g.draw_polyline(top, Color(color.lightened(0.2), alpha), 1.2, true)

func render(game) -> void:
	g = game
	g.draw_rect(Rect2(20, 145, 890, 645), Color("0b1522"))
	if g.ultimate_aim < 0: g.draw_string(g.font, Vector2(44, 177), "TACTICAL ARENA  /  02", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("688198"))
	# Floating arena plinth, with a true projected surface, not a square board.
	var corners: Array = [Vector2.ZERO, Vector2(640, 0), Vector2(640, 640), Vector2(0, 640)]
	polygon(corners, Color(0, 0, 0, 0.4), -27)
	for edge in [[Vector2(640, 0), Vector2(640, 640)], [Vector2(640, 640), Vector2(0, 640)]]:
		g.draw_colored_polygon(PackedVector2Array([project(edge[0]), project(edge[1]), project(edge[1], -16), project(edge[0], -16)]), Color("172735"))
	polygon(corners, Color("203344"))
	# Large metal panels are decoration, never movement cells.
	for n in range(1, 4):
		line(Vector2(n * 160, 0), Vector2(n * 160, 640), Color("294052"))
		line(Vector2(0, n * 160), Vector2(640, n * 160), Color("294052"))
	ring(Vector2(320, 320), 107, Color("355064"))
	ring(Vector2(320, 320), 113, Color("293f51"))
	for i in range(4): line(corners[i], corners[(i + 1) % 4], Color("7890a1"), 2)
	for n in range(9):
		var t := 40.0 + n * 70
		line(Vector2(t, 8), Vector2(t + 14, 8), Color("63b2cc"), 3)
		line(Vector2(t, 632), Vector2(t + 14, 632), Color("63b2cc"), 3)
	for w in g.walls:
		polygon([w.position, w.position + Vector2(w.size.x, 0), w.end + Vector2(28, 32), w.position + Vector2(28, w.size.y + 32)], Color(0, 0, 0, 0.22))
	ground_effects()
	ultimate_preview()
	var actors: Array = []
	for w in g.wall_states:
		actors.append({"depth": w.rect.get_center().x + w.rect.get_center().y, "wall": w.rect, "state": w})
	for u in g.units:
		disc(u.p + Vector2(7, 7), 27, Color(0, 0, 0, 0.28))
		actors.append({"depth": u.p.x + u.p.y, "unit": u})
	actors.sort_custom(func(a, b): return a.depth < b.depth)
	for actor in actors:
		if actor.has("wall"):
			var w: Rect2 = actor.wall
			var alpha := 1.0
			for u in g.units:
				if u.hp > 0 and Rect2(project(w.position, 60) - Vector2(85, 0), Vector2(150, 150)).has_point(project(u.p, 25)) and u.p.x + u.p.y < actor.depth: alpha = 0.48
			draw_wall(actor.state, alpha)
		else: robot(actor.unit)
	air_effects()
	for u in g.units:
		if u.hp > 0: label(u)
	for fx in g.impacts:
		var age: float = 0.65 - fx.life
		var color := Color("8affbb" if fx.get("healing", false) else "fff2cc", minf(1, fx.life * 4))
		g.draw_string(g.font, project(fx.p, 70 + age * 45) + Vector2(21, 0), ("+%d" if fx.get("healing", false) else "−%d") % fx.amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 23 if fx.amount >= 16 else 17, color)
	g.draw_string(g.font, Vector2(46, 763), "连续移动  /  立体演出 · 平面判定       蓝紫 / 蓝方攻击     橙红 / 红方攻击", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("96adbe"))

func landing(p: Vector2, radius: float, color: Color, progress: float, total: float) -> void:
	disc(p, radius, Color(color, 0.1))
	ring(p, radius, Color(color, 0.45))
	ring(p, radius, color, 3.5, clampf(progress, 0, 1))
	line(p - Vector2(7, 0), p + Vector2(7, 0), color)
	line(p - Vector2(0, 7), p + Vector2(0, 7), color)
	g.draw_string(g.font, project(p) + Vector2(-13, 8), "%.1f" % maxf(0, (1 - progress) * total), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

func ground_effects() -> void:
	for u in g.units:
		if u.hp <= 0: continue
		var color: Color = g.ATTACK_BLUE if u.team == 0 else g.ATTACK_RED
		if u.uid == g.selected: ring(u.p, 32, Color.WHITE, 2)
		if u.dodge > 0 or u.action_left > 0 or u.intent == "规避预警":
			var dest: Vector2 = u.p + u.dodge_dir * g.DODGE_SPEED * u.dodge if u.dodge > 0 else u.action_goal
			if u.p.distance_to(dest) > 10:
				var path: Array = [u.p]
				if u.dodge <= 0 and u.intent != "规避预警":
					for p in u.path: path.append(p)
				path.append(dest)
				for i in range(1, path.size()): g.draw_dashed_line(project(path[i - 1]), project(path[i]), Color(g.MOVE_HINT, 0.55), 1.5, 7, true)
				ring(dest, 10, g.MOVE_HINT)
				var direction: Vector2 = (dest - u.p).normalized()
				line(dest - direction * 14, dest - direction * 14 - direction.rotated(0.5) * 10, g.MOVE_HINT, 2)
				line(dest - direction * 14, dest - direction * 14 - direction.rotated(-0.5) * 10, g.MOVE_HINT, 2)
		if not g.show_aim: continue
		if u.phase == "吟唱":
			if u.active_skill in g.Tactics.AREAS:
				for p in g.mortar_points(u.lock_point): landing(p, g.pattern_radius(u.active_skill), color, 1 - (u.timer + g.BLAST_FLIGHT) / g.area_total_time(u.active_skill), g.area_total_time(u.active_skill))
			elif u.active_skill in g.Tactics.LINES:
				var end: Vector2 = g.beam_end(u.p, u.lock_angle)
				strip(u.p, end, g.pattern_radius(u.active_skill), Color(color, 0.16))
				g.draw_dashed_line(project(u.p), project(end), color, 1.5, 8, true)
			elif u.active_skill == "霰弹":
				var fan: Array = [u.p]
				for i in range(13): fan.append(u.p + Vector2.from_angle(u.lock_angle - 0.36 + i * 0.06) * 228)
				polygon(fan, Color(color, 0.14))
		elif u.phase in ["瞄准", "锁定"]:
			line(u.p, u.p + Vector2.from_angle(u.angle) * g.SHOT_RANGE, Color(color, 0.3), 1)
	for h in g.hazards:
		if h.kind == "area" and g.show_aim:
			var color: Color = g.ATTACK_BLUE if h.team == 0 else g.ATTACK_RED
			landing(h.p, h.radius, color, 1 - h.left / g.area_total_time(h.get("skill", "抛射轰击")), g.area_total_time(h.get("skill", "抛射轰击")))
	for fx in g.blasts:
		var life: float = clampf(fx.life / fx.get("duration", 0.3), 0, 1)
		var color := Color(g.ATTACK_BLUE if fx.team == 0 else g.ATTACK_RED, life)
		if fx.kind == "area":
			disc(fx.p, fx.radius, Color(color, life * 0.22))
			ring(fx.p, fx.radius, Color(color, life * 0.5), 2)
			ring(fx.p, fx.radius * (1 - life), color, 4)
		else: strip(fx.p, fx.end, fx.radius, Color(color, life * 0.23))

func robot(u: Dictionary) -> void:
	var p: Vector2 = u.p
	var color: Color = g.BLUE if u.team == 0 else g.RED
	if u.hp <= 0:
		box(p - Vector2(16, 16), Vector2(32, 32), 8, Color("364451"))
		line(p - Vector2(12, 0), p + Vector2(12, 0), color.darkened(0.5), 3, 9)
		return
	var dir := Vector2.from_angle(u.angle)
	var side := dir.orthogonal()
	var motion: float = 1.0 if u.action_left > 0 or u.dodge > 0 else 0.0
	var bob: float = sin((60 - g.clock) * 18 + u.uid) * motion * 1.5
	var hop: float = minf(16, u.blast_impulse.length() * 0.012)
	var h := 19.0 + bob + hop
	if u.dodge > 0:
		for i in range(1, 4):
			var ghost: Vector2 = p - u.dodge_dir * i * 13
			disc(ghost, 21, Color(color, 0.14 / i), h)
	for s in [-1, 1]:
		var foot: Vector2 = p + side * s * 17
		g.draw_line(project(foot - dir * 13, 5 + hop), project(foot + dir * 13, 5 + hop), Color("101d2c"), 13, true)
		g.draw_line(project(foot - dir * 10, 10 + hop), project(foot + dir * 10, 10 + hop), color.darkened(0.5), 7, true)
	disc(p, 24, color.darkened(0.63), h - 6)
	g.draw_line(project(p, h - 6), project(p, h), color.darkened(0.5), 31)
	disc(p, 24, color.darkened(0.15), h)
	ring(p, 24, color.lightened(0.2), 1.5, 1, h)
	var body := project(p, h + 8)
	g.draw_circle(body, 15, color.darkened(0.36))
	g.draw_circle(body - Vector2(2, 3), 13, color.lerp(Color.WHITE, minf(0.85, u.hit_flash * 4)))
	var recoil: float = 7 * u.fire_flash / 0.18
	var muzzle: Vector2 = p + dir * (34 - recoil)
	g.draw_line(project(p - dir * recoil, h + 10), project(muzzle, h + 10), Color("17232e"), 10, true)
	g.draw_line(project(p - dir * recoil, h + 13), project(muzzle, h + 13), color.lightened(0.6), 5, true)
	g.draw_circle(body - Vector2(4, 6), 3, Color("e9fcff"))
	if u.fire_flash > 0:
		var spark := project(muzzle + dir * 6, h + 12)
		g.draw_circle(spark, 13 * u.fire_flash / 0.18, Color(color, 0.3))
		g.draw_circle(spark, 5, Color("fff5d5"))
	if u.shield > 0 or u.guard > 0:
		g.draw_circle(body, 31, Color(0.4, 0.9, 1, 0.08))
		g.draw_arc(body, 31, 0, TAU, 48, Color(0.5, 0.9, 1, 0.7), 1.5, true)
	if u.marked > 0: ring(p, 29, g.GOLD, 2)
	if u.thorns > 0: ring(p, 31, Color("70e598"), 2)
	if u.slow > 0: ring(p, 34, Color("c291ff"), 2)
	if u.heal_flash > 0:
		g.draw_line(body + Vector2(-7, -25), body + Vector2(7, -25), Color("8affbb"), 3)
		g.draw_line(body + Vector2(0, -32), body + Vector2(0, -18), Color("8affbb"), 3)
		for i in range(5):
			var leaf := project(p + Vector2.from_angle(i * TAU / 5 + g.clock) * 26, 8 + (1 - u.heal_flash / 0.5) * 35)
			g.draw_line(leaf - Vector2(3, 3), leaf + Vector2(3, 3), Color("8affbb"), 3, true)
	if u.phase in ["吟唱", "大招蓄力"]:
		var progress: float = 1 - clampf(u.timer / (0.3 if u.phase == "大招蓄力" else float(g.Tactics.MAGIC.get(u.active_skill, {}).get("cast", 0.6))), 0, 1)
		ring(p, 32, Color(color, 0.3), 1.5)
		ring(p, 32, color.lightened(0.4), 3, progress)
		for i in range(4):
			var orb := p + Vector2.from_angle((60 - g.clock) * 4 + i * TAU / 4) * 27
			g.draw_circle(project(orb, 15 + progress * 18), 2 + progress * 2, color.lightened(0.6))

func label(u: Dictionary) -> void:
	var p := project(u.p, 57)
	var color: Color = g.BLUE if u.team == 0 else g.RED
	g.draw_rect(Rect2(p + Vector2(-31, -8), Vector2(62, 7)), Color("0b1520"))
	g.draw_rect(Rect2(p + Vector2(-30, -7), Vector2(60 * u.hp / g.MAX_HP, 5)), color)
	g.draw_rect(Rect2(p + Vector2(-30, 1), Vector2(60, 4)), Color("17232b"))
	g.draw_rect(Rect2(p + Vector2(-30, 1), Vector2(60 * u.energy / 100, 4)), Color("72e5b4"))
	if u.cooldown > 0:
		g.draw_string(g.font, p + Vector2(34, 4), "CD %.1f" % u.cooldown, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f5ce78"))
	g.draw_string(g.font, p + Vector2(-30, -14), "%s%d   %d" % ["蓝" if u.team == 0 else "红", u.member + 1, u.hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	var text: String = u.active_skill if u.phase in ["吟唱", "大招蓄力", "点射", "锁定", "瞄准"] else u.intent
	if u.phase == "收招": text = "收招"
	var w: float = g.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var below := project(u.p) + Vector2(-w / 2, 28)
	g.draw_rect(Rect2(below + Vector2(-4, -13), Vector2(w + 8, 18)), Color(0.03, 0.07, 0.1, 0.82))
	g.draw_string(g.font, below, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color.lightened(0.3))

func air_effects() -> void:
	for link in g.links: g.draw_dashed_line(project(link.a, 25), project(link.b, 25), Color(link.color, minf(1, link.life * 2)), 2, 6, true)
	for b in g.bullets:
		var color: Color = g.ATTACK_BLUE if b.team == 0 else g.ATTACK_RED
		var dir: Vector2 = b.v.normalized()
		var p := project(b.p, 29)
		var tail := project(b.p - dir * 32, 29)
		g.draw_line(tail, p, Color(color, 0.14), 14, true)
		g.draw_line(tail, p, color, 4, true)
		var element: String = b.get("element", "")
		if element == "风":
			var a: float = (p - tail).angle()
			g.draw_arc(p, 11, a - 1.3, a + 1.3, 12, color.lightened(0.5), 3, true)
		elif element == "山":
			g.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, -9), p + Vector2(7, -5), p + Vector2(9, 6), p + Vector2(-5, 9)]), color)
			g.draw_line(p - Vector2(5, 6), p + Vector2(4, 1), Color("fff0d4"), 2, true)
		else: g.draw_circle(p, 4 if element == "火" else 2.5, Color.WHITE)
	for h in g.hazards:
		if h.kind != "area": continue
		var t: float = clampf(1 - h.left / g.BLAST_FLIGHT, 0, 1)
		var origin: Vector2 = h.get("origin", h.p)
		var pos: Vector2 = origin.lerp(h.p, t)
		var z := 28 * (1 - t) + 120 * sin(t * PI)
		var color: Color = g.ATTACK_BLUE if h.team == 0 else g.ATTACK_RED
		disc(pos, 9, Color(0, 0, 0, 0.3))
		for i in range(5, 0, -1):
			var before := maxf(0, t - i * 0.025)
			var trail := project(origin.lerp(h.p, before), 28 * (1 - before) + 120 * sin(before * PI))
			g.draw_circle(trail, 5 - i * 0.5, Color(color, 0.45 - i * 0.06))
		g.draw_circle(project(pos, z), 8, color)
		g.draw_circle(project(pos, z) - Vector2(2, 2), 4, Color("fff5db"))
	for fx in g.blasts:
		var life: float = clampf(fx.life / fx.get("duration", 0.3), 0, 1)
		var age := 1 - life
		var color := Color(g.ATTACK_BLUE if fx.team == 0 else g.ATTACK_RED, life)
		if fx.kind == "beam":
			if fx.get("skill", "") == "裂地冲击":
				for i in range(1, 10):
					var p: Vector2 = fx.p.lerp(fx.end, i / 10.0)
					var base := project(p)
					var peak := project(p, (22 + i % 3 * 9) * life)
					g.draw_colored_polygon(PackedVector2Array([base + Vector2(-12, 1), peak, base + Vector2(12, 1)]), color)
					g.draw_line(peak, base + Vector2(3, 0), Color(1, 0.9, 0.7, life), 2, true)
			else:
				line(fx.p, fx.end, Color(color, life * 0.15), fx.radius * 4, 29)
				line(fx.p, fx.end, color, fx.radius * 1.4, 29)
				line(fx.p, fx.end, Color(1, 1, 1, life), 4, 29)
		else:
			for i in range(12):
				var dir := Vector2.from_angle(i * TAU / 12 + 0.2)
				var p: Vector2 = fx.p + dir * fx.radius * age * 0.9
				var z := sin(age * PI) * (32 + i % 3 * 13)
				g.draw_line(project(p - dir * 9, z - 7), project(p, z), color, 3, true)
			if fx.get("skill", "") in ["烈焰爆破", "星火轰炸"]:
				for i in range(6):
					var p: Vector2 = fx.p + Vector2.from_angle(i * TAU / 6) * fx.radius * 0.3 * age
					var tip := project(p, 65 * age)
					g.draw_circle(tip, 19 * life, Color(color, life * 0.35))
					g.draw_circle(tip, 8 * life, Color(1, 0.9, 0.7, life * 0.8))
	for fx in g.effects:
		if fx.get("wall_break", false):
			var progress: float = 1 - fx.life / 0.8
			for i in range(16):
				var direction := Vector2.from_angle(i * TAU / 16 + 0.3)
				var point := project(fx.p + direction * progress * (32 + i % 4 * 9), 8 + sin(progress * PI) * (22 + i % 3 * 12))
				g.draw_rect(Rect2(point - Vector2(3, 3), Vector2(6, 6)), Color(0.65, 0.77, 0.83, 1 - progress))
			ring(fx.p, 15 + progress * 65, Color(0.7, 0.8, 0.85, (1 - progress) * 0.45), 3)
			continue
		var life: float = minf(1, fx.life * 5)
		var p := project(fx.p, 22)
		for i in range(6):
			var dir := Vector2.from_angle(i * TAU / 6)
			g.draw_line(p + dir * (1 - life) * 18, p + dir * ((1 - life) * 18 + 5), Color(fx.color, life), 1.5, true)


func draw_wall(state: Dictionary, alpha: float) -> void:
	var w: Rect2 = state.rect
	if state.hp <= 0:
		for i in range(10):
			var p := w.position + Vector2(3 + (i * 13) % 24, i * w.size.y / 10)
			box(p, Vector2(7 + i % 3, 9), 3 + i % 4, Color("455563"), 0.65)
		return
	box(w.position, w.size, 48, Color("58758b"), alpha)
	line(w.position + Vector2(5, 8), w.position + Vector2(5, w.size.y - 8), Color(0.6, 0.85, 1, alpha), 2, 49)
	if state.hp <= 200:
		# Cracks are attached to the visible wall face, not to screen-space ground.
		var count := 4 if state.hp <= 100 else 2
		for i in range(count):
			var base := w.position + Vector2(w.size.x, 16 + i * 25)
			var points := PackedVector2Array([project(base, 48), project(base + Vector2(0, 7), 36), project(base + Vector2(0, -3), 26), project(base + Vector2(0, 10), 14), project(base + Vector2(0, 6), 2)])
			g.draw_polyline(points, Color(0.06, 0.1, 0.14, alpha), 3 if state.hp <= 100 else 1.8, true)
			g.draw_line(points[2], project(base + Vector2(0, -12), 17), Color(0.08, 0.13, 0.18, alpha), 2, true)
			line(base, base - Vector2(w.size.x, 7), Color(0.08, 0.13, 0.18, alpha), 2, 48)
	var p := project(w.get_center(), 66)
	g.draw_rect(Rect2(p + Vector2(-26, -5), Vector2(52, 5)), Color("16232d"))
	g.draw_rect(Rect2(p + Vector2(-25, -4), Vector2(50 * state.hp / g.WALL_HP, 3)), Color("e6b76b") if state.hp <= 100 else Color("89acbe"))
	g.draw_string(g.font, p + Vector2(-27, -10), "掩体 %d" % state.hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c9d7e1"))


func ultimate_preview() -> void:
	for u in g.units:
		if u.hp <= 0: continue
		var aiming: bool = g.ultimate_aim == u.uid
		if not aiming and not u.ult_pending and u.phase != "大招蓄力": continue
		var angle: float = (g.ultimate_cursor - u.p).angle() if aiming else u.ult_angle
		var shape: Dictionary = g.ultimate_geometry(u, angle)
		var color: Color = g.ATTACK_BLUE
		ring(u.p, 35, Color("ffe7a0"), 2)
		if u.member == 0:
			strip(u.p, shape.end, shape.radius, Color(color, 0.23))
			var side: Vector2 = Vector2.from_angle(angle).orthogonal() * shape.radius
			line(u.p + side, shape.end + side, color, 2)
			line(u.p - side, shape.end - side, color, 2)
			line(u.p, shape.end, Color("e2deff"), 1.5)
			ring(shape.end, 9, color, 2)
		else:
			for point in shape.points:
				if aiming or u.ult_pending:
					disc(point, shape.radius, Color(color, 0.12))
					ring(point, shape.radius, color, 2)
					line(point - Vector2(7, 0), point + Vector2(7, 0), color)
					line(point - Vector2(0, 7), point + Vector2(0, 7), color)
				else: landing(point, shape.radius, color, (0.3 - u.timer) / 0.95, 0.95)
		if aiming:
			g.draw_rect(Rect2(185, 155, 560, 34), Color(0.04, 0.08, 0.13, 0.95))
			g.draw_string(g.font, Vector2(199, 177), "%s · %s · 右键/Esc取消" % [g.ultimate_name(u.uid), ("左键排队（恢复精力）" if u.energy < 70 else ("左键排队（CD %.1fs）" % u.cooldown if u.cooldown > 0 else ("左键排队（等收招）" if u.phase in ["吟唱", "瞄准", "点射", "收招", "大招蓄力"] else "左键释放")))], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffe7a0"))
