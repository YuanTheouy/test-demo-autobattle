extends Control
## Drawing coordinates: +X = subject's left, +Y = up, +Z = face/viewer.
## Positive angles: right yaw, downward pitch, right roll.

const INK := Color("343e43")
const BLUE := Color("237caa")
const RED := Color("c75c49")
const GREEN := Color("50846a")
const PURPLE := Color("8b58a2")
const TAU_STEPS := 180
var yaw := 30.0
var pitch := 15.0
var roll := 0.0
var cut := sqrt(5.0) / 3.0
var cap_opacity := 0.22
var latitude := 0.0
var sliced := true
var caps := false
var hidden_lines := false
var grid := false
var axes := false
var side_meridian := true
var face_enabled := true
var nose_enabled := true
var landmarks := false
var secondary_enabled := true
var plane_edges := true
var head_style := 0
var style_buttons: Array[Button] = []
var model_style_signature := -1
var secondary_layer: MeshInstance2D
var secondary_material: ShaderMaterial
var ball_guides := false
var face_projection := 1.0
var chin_width := 0.24
var face_model = preload("res://loomis_model.gd").new()
var model_signature := Vector3(-1, -1, -1)
var model_revision := 0
var sliders: Dictionary = {}
var readouts: Dictionary = {}
var head_basis := Basis.IDENTITY
var inverse_basis := Basis.IDENTITY
var surface_layer: ColorRect
var surface_material: ShaderMaterial
var center := Vector2(475, 450)
var radius := 285.0
var font: Font
var panel: VBoxContainer

func _ready() -> void:
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	font = system_font
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	surface_material = ShaderMaterial.new()
	surface_material.shader = preload("res://head_surface.gdshader")
	surface_layer = ColorRect.new()
	surface_layer.material = surface_material
	surface_layer.show_behind_parent = true
	surface_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface_layer)
	secondary_material = ShaderMaterial.new()
	secondary_material.shader = preload("res://secondary_surface.gdshader")
	secondary_layer = MeshInstance2D.new()
	secondary_layer.material = secondary_material
	secondary_layer.show_behind_parent = true
	add_child(secondary_layer)
	_build_ui()
	_update_head_basis()
	resized.connect(queue_redraw)
	if "--capture" in OS.get_cmdline_user_args():
		_capture()

func _label(text: String, size_px: int = 17) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	return label

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("e5e7df")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	backdrop.offset_left = -460
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	scroll.offset_left = -435
	scroll.offset_right = -20
	scroll.offset_top = 24
	scroll.offset_bottom = -16
	add_child(scroll)
	panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 9)
	scroll.add_child(panel)
	_label("Loomis · 基本面练习", 27)
	var styles := HBoxContainer.new()
	panel.add_child(styles)
	var style_group := ButtonGroup.new()
	for i in 2:
		var button := Button.new()
		button.text = "男性 · 基本面" if i == 0 else "美少女 · 基本面"
		button.toggle_mode = true
		button.button_group = style_group
		button.button_pressed = i == head_style
		button.pressed.connect(func(): set_head_style(i))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		styles.add_child(button)
		style_buttons.append(button)
	_label("X 左耳方向 · Y 头顶方向 · Z 脸朝向\n正值按人物自己的左右；正面看会左右相反。", 15)
	_slider("yaw", "Yaw  向右甩头", -180, 180, yaw, 1)
	_slider("pitch", "Pitch  低头点头", -90, 90, pitch, 1)
	_slider("roll", "Roll  向右歪头", -90, 90, roll, 1)
	var row := HBoxContainer.new()
	panel.add_child(row)
	for preset in [["正面", 0, 0, 0], ["右转", 55, 0, 0], ["低头", 30, 35, 0], ["仰头歪头", -35, -25, 25]]:
		var button := Button.new()
		button.text = preset[0]
		button.pressed.connect(func(): set_angles(preset[1], preset[2], preset[3]))
		row.add_child(button)
	_toggle("显示面部拼接平面", "face_enabled", face_enabled)
	_toggle("显示平面转折边线", "plane_edges", plane_edges)
	_toggle("显示简单鼻块", "nose_enabled", nose_enabled)
	_toggle("比例线与文字", "landmarks", landmarks)
	var main_panel := panel
	var details_toggle := Button.new()
	details_toggle.text = "展开：球体、切片与比例设置"
	details_toggle.toggle_mode = true
	panel.add_child(details_toggle)
	var details := VBoxContainer.new()
	details.visible = false
	details.add_theme_constant_override("separation", 9)
	panel.add_child(details)
	details_toggle.toggled.connect(details.set_visible)
	panel = details
	_toggle("叠加球面十字线", "ball_guides", ball_guides)
	_slider("chin_width", "下巴半宽 / R", 0.16, 0.38, chin_width, 0.01)
	_slider("face_projection", "面部前伸比例", 0.8, 1.2, face_projection, 0.01)
	_label("你的比例（R = 1）\n发际 +2/3 · 眉骨 0 · 下眼睑 −1/3\n鼻底 −2/3 · 嘴线 −1 · 下巴 −4/3\n侧圆半径 2/3 → 切面 √5/3 ≈ 0.745\n耳朵：侧圆底部向上 2/3。", 16)
	_label("画法：先定眉骨与脸中线；沿中线分出发际、鼻底、下巴。\n画窄正面，再接两侧斜面；从耳下缘连到下颌角，再收向下巴。", 16)
	_slider("cut", "切面位置 a（标准 √5/3）", 0.45, 0.98, cut, 0.0)
	_slider("cap_opacity", "薄片不透明度（越低越透明）", 0.05, 0.6, cap_opacity, 0.01)
	_slider("latitude", "横线高度 h", -0.65, 0.65, latitude, 0.01)
	_toggle("两侧削平（X = ±a）", "sliced", sliced)
	_toggle("显示切下的薄片", "caps", caps)
	_toggle("背面虚线", "hidden_lines", hidden_lines)
	_toggle("耳侧经线（切面处变直）", "side_meridian", side_meridian)
	_toggle("辅助经纬网", "grid", grid)
	_toggle("坐标轴与脸朝向", "axes", axes)
	_label("最少只记这三条", 21)
	_label("竖线：p(t) = (0, sin t, cos t)\n横线：p(t) = (clamp(r sin t, −a, a), h, r cos t)\n切口：p(t) = (±a, ρ sin t, ρ cos t)\nr = √(1 − h²)；ρ = √(1 − a²)\n横线和耳侧经线在切面上都接直线。", 16)
	_label("耳侧经线：p(t) = (x, cos t, 0)\nx = clamp(sin t, −a, a)\n把超出切面的 x 夹回 ±a，圆弧就接上直线。", 16)
	_label("把点转好，再投到纸上", 21)
	_label("q = Ry(−yaw) Rx(pitch) Rz(roll) p\n纸上点 = 中心 + s · (qx, −qy)\n右边先算：先 roll，再 pitch，再 yaw。\n角度绕随头转动的局部轴；不是拖动历史。", 15)
	_label("蓝色 = 面部中线　红色 = 横线\n紫色 = 耳侧经线　绿色 = 平切口\n半透明 = 原位薄片；实线在前，虚线在后。\n正交投影，无近大远小。", 15)
	_label("两个版本都只保留参考图的大面，不加眼睑、嘴唇或细碎次级面。\n男性下颌较方；美少女下巴较窄、眉骨和鼻块较轻。", 15)
	panel = main_panel

func _slider(key: String, title: String, low: float, high: float, initial: float, step_value: float) -> void:
	readouts[key] = _label("", 16)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step_value
	slider.value = initial
	slider.custom_minimum_size.y = 24
	panel.add_child(slider)
	sliders[key] = slider
	var update := func(value: float):
		set(key, value)
		readouts[key].text = "%s   %s" % [title, ("%d°" % value) if step_value == 1 else (("%.3f" % value) if key == "cut" else ("%.2f" % value))]
		_update_head_basis()
	slider.value_changed.connect(update)
	update.call(initial)

func _toggle(title: String, key: String, initial: bool) -> void:
	var check := CheckBox.new()
	check.text = title
	check.button_pressed = initial
	check.add_theme_color_override("font_color", INK)
	check.add_theme_color_override("font_pressed_color", INK)
	check.add_theme_color_override("font_hover_color", INK)
	check.add_theme_color_override("font_hover_pressed_color", INK)
	check.toggled.connect(func(value: bool): set(key, value); queue_redraw())
	panel.add_child(check)

func set_angles(y: float, p: float, r: float) -> void:
	sliders.yaw.value = y
	sliders.pitch.value = p
	sliders.roll.value = r

func set_head_style(index: int) -> void:
	head_style = clampi(index, 0, 1)
	sliders.chin_width.value = 0.24 if head_style == 0 else 0.16
	for i in style_buttons.size():
		style_buttons[i].button_pressed = i == head_style
	queue_redraw()

func _update_head_basis() -> void:
	head_basis = Basis(Vector3.UP, deg_to_rad(-yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.BACK, deg_to_rad(roll))
	inverse_basis = head_basis.transposed()
	queue_redraw()

func project_point(p: Vector3) -> Vector2:
	var q := head_basis * p
	return center + radius * Vector2(q.x, -q.y)

func _draw() -> void:
	if font == null:
		return
	var drawing_width := size.x - 460
	center = Vector2(drawing_width * 0.49, size.y * (0.43 if face_enabled else 0.49))
	radius = minf(drawing_width / 3.8, size.y * (0.245 if face_enabled else 0.31))
	_sync_face_model()
	draw_string(font, Vector2(32, 49), "%s / 基本面练习" % ("男性" if head_style == 0 else "美少女"), HORIZONTAL_ALIGNMENT_LEFT, -1, 27, INK)
	draw_string(font, Vector2(33, 80), "只看少量大面与转折；拖动右侧滑条观察。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
	# One GPU rectangle replaces rebuilding/sorting thousands of CPU triangles.
	surface_layer.size = Vector2(drawing_width, size.y)
	surface_material.set_shader_parameter("canvas_size", surface_layer.size)
	surface_material.set_shader_parameter("center", center)
	surface_material.set_shader_parameter("radius", radius)
	surface_material.set_shader_parameter("head_basis", head_basis)
	surface_material.set_shader_parameter("cut", cut)
	surface_material.set_shader_parameter("cap_opacity", cap_opacity)
	surface_material.set_shader_parameter("sliced", sliced)
	surface_material.set_shader_parameter("caps", caps)
	surface_material.set_shader_parameter("face_enabled", face_enabled)
	surface_material.set_shader_parameter("nose_enabled", nose_enabled)
	surface_material.set_shader_parameter("secondary_enabled", secondary_enabled)
	_update_secondary_surface()
	# Surface silhouette, a great circle normal to the viewing direction.
	var inv := inverse_basis
	_curve(func(t: float): return inv * Vector3(cos(t), sin(t), 0), INK, 2.2, true)
	if grid:
		for h in [-0.6, -0.3, 0.3, 0.6]:
			_curve(func(t: float): return _horizontal_point(t, h), Color(0.38, 0.43, 0.44, 0.42), 1, false, _horizontal_joints(h))
		for angle in [-60.0, -30.0, 30.0, 60.0]:
			var a := deg_to_rad(angle)
			_curve(func(t: float): return Vector3(sin(a) * cos(t), sin(t), cos(a) * cos(t)), Color(0.38, 0.43, 0.44, 0.42), 1)
	if not face_enabled or ball_guides:
		_curve(func(t: float): return Vector3(0, sin(t), cos(t)), BLUE, 3.4)
	if side_meridian and (not face_enabled or ball_guides):
		var joints: Array[float] = []
		if sliced:
			var angle := asin(cut)
			joints = [angle, PI - angle, PI + angle, TAU - angle]
		_curve(_side_meridian_point, PURPLE, 3.0, false, joints)
	if not face_enabled or ball_guides:
		_curve(func(t: float): return _horizontal_point(t, latitude), RED, 3.4, false, _horizontal_joints(latitude))
	if sliced:
		for side in [-1.0, 1.0]:
			_cut_rim(side, Vector3.ZERO, side)
			if caps:
				_cap_silhouette(side, Vector3.ZERO)
	if axes:
		_draw_axes()
	if face_enabled:
		_draw_face()
	var front := Vector3(0, 0, 1)
	if not face_enabled and (head_basis * front).z > 0:
		draw_circle(project_point(front), 5, BLUE)
		draw_string(font, project_point(front) + Vector2(10, -9), "面部正前方", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, BLUE)
	draw_string(font, Vector2(33, size.y - 90), "球壳 → 眉骨与三庭 → 面部折面 → 耳下缘接下颌", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	if face_enabled:
		draw_string(font, Vector2(33, size.y - 56), "只保留基本面；不画眼睑、嘴唇和细碎次级面。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
		draw_string(font, Vector2(33, size.y - 29), "顶部切换男性 / 美少女；切换时保持当前角度。", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	else:
		draw_string(font, Vector2(33, size.y - 56), "切口半径 ρ = %.2f；可展开设置显示半透明薄片。" % sqrt(1 - cut * cut), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, GREEN)

func _ring_point(x: float, t: float) -> Vector3:
	var r := sqrt(maxf(0, 1 - x * x))
	return Vector3(x, r * sin(t), r * cos(t))

func _side_meridian_point(t: float) -> Vector3:
	# Intersection of Z=0 with the sliced head: circular arcs joined by chords.
	return Vector3(clampf(sin(t), -cut, cut) if sliced else sin(t), cos(t), 0)

func _horizontal_point(t: float, h: float) -> Vector3:
	var r := sqrt(1 - h * h)
	var x := r * sin(t)
	return Vector3(clampf(x, -cut, cut) if sliced else x, h, r * cos(t))

func _horizontal_joints(h: float) -> Array[float]:
	var r := sqrt(1 - h * h)
	if not sliced or r <= cut:
		return []
	var angle := asin(cut / r)
	return [angle, PI - angle, PI + angle, TAU - angle]

func _curve(point: Callable, color: Color, width: float, _silhouette: bool = false, extra_samples: Array[float] = []) -> void:
	var samples: Array[float] = []
	var front_segments := PackedVector2Array()
	var back_segments := PackedVector2Array()
	for i in TAU_STEPS + 1:
		samples.append(TAU * i / TAU_STEPS)
	samples.append_array(extra_samples)
	if not extra_samples.is_empty():
		samples.sort()
	for i in samples.size() - 1:
		var a: Vector3 = point.call(samples[i])
		var b: Vector3 = point.call(samples[i + 1])
		var middle: Vector3 = point.call((samples[i] + samples[i + 1]) * 0.5)
		if _silhouette and face_enabled and middle.y < 2.0 / 3.0 and middle.z > 0.0001:
			continue
		if sliced and absf(middle.x) > cut:
			continue
		var visible_part := _point_visible(middle)
		if visible_part:
			front_segments.append(project_point(a))
			front_segments.append(project_point(b))
		elif hidden_lines and i % 5 < 2:
			back_segments.append(project_point(a))
			back_segments.append(project_point(b))
	if not back_segments.is_empty():
		draw_multiline(back_segments, Color(color, 0.23), 1.3, true)
	if not front_segments.is_empty():
		draw_multiline(front_segments, color, width, true)

func _cut_rim(side: float, offset: Vector3, _normal_sign: float) -> void:
	for i in TAU_STEPS:
		var a := _ring_point(side * cut, TAU * i / TAU_STEPS)
		var b := _ring_point(side * cut, TAU * (i + 1) / TAU_STEPS)
		var middle := _ring_point(side * cut, TAU * (i + 0.5) / TAU_STEPS)
		if face_enabled and not ball_guides and middle.y < 2.0 / 3.0 and middle.z > 0.0001:
			continue
		var visible_part := _point_visible(_ring_point(side * cut, TAU * (i + 0.5) / TAU_STEPS) + offset)
		if visible_part or (hidden_lines and i % 5 < 2):
			var rim_color := Color("696d66") if face_enabled else GREEN
			draw_line(project_point(a + offset), project_point(b + offset), rim_color if visible_part else Color(rim_color, 0.23), 1.6 if visible_part else 1, true)

func _cap_silhouette(side: float, offset: Vector3) -> void:
	var inv := inverse_basis
	for i in TAU_STEPS:
		var a := inv * Vector3(cos(TAU * i / TAU_STEPS), sin(TAU * i / TAU_STEPS), 0)
		var b := inv * Vector3(cos(TAU * (i + 1) / TAU_STEPS), sin(TAU * (i + 1) / TAU_STEPS), 0)
		if side * ((a.x + b.x) * 0.5) >= cut:
			var midpoint := inv * Vector3(cos(TAU * (i + 0.5) / TAU_STEPS), sin(TAU * (i + 0.5) / TAU_STEPS), 0)
			var visible_part := _point_visible(midpoint + offset)
			if visible_part or (hidden_lines and i % 5 < 2):
				draw_line(project_point(a + offset), project_point(b + offset), Color(INK, cap_opacity + 0.15) if visible_part else Color(INK, 0.1), 1.7 if visible_part else 1, true)

func _point_visible(p: Vector3) -> bool:
	# Compare against the closest ray/solid intersection, including the flat cuts.
	var q := head_basis * p
	var top := -INF
	if not sliced:
		top = _solid_depth(q, -1, 1, Vector3.ZERO)
	else:
		top = _solid_depth(q, -cut, cut, Vector3.ZERO)
		# Transparent caps do not hide the construction lines on the retained head.
	if face_enabled:
		if secondary_enabled:
			var origin := inverse_basis * Vector3(q.x, q.y, 4)
			var direction := inverse_basis * Vector3.FORWARD
			var hit: Dictionary = face_model.secondary_bvh.intersect_ray(origin, direction)
			if not hit.is_empty():
				top = maxf(top, (head_basis * hit.position).z)
			if nose_enabled:
				hit = face_model.secondary_nose_bvh.intersect_ray(origin, direction)
				if not hit.is_empty():
					top = maxf(top, (head_basis * hit.position).z)
		else:
			top = maxf(top, _face_depth(q, face_model.planes))
			if nose_enabled:
				top = maxf(top, _face_depth(q, face_model.nose_planes))
	return q.z >= top - 0.008

func _face_depth(q: Vector3, bounds: Array[Plane]) -> float:
	var origin := inverse_basis * Vector3(q.x, q.y, 4)
	var direction := inverse_basis * Vector3.FORWARD
	var hit := Geometry3D.segment_intersects_convex(origin, origin + direction * 8, bounds)
	return (head_basis * hit[0]).z if not hit.is_empty() else -INF

func _sync_face_model() -> void:
	var signature := Vector3(cut, chin_width, face_projection)
	if signature.is_equal_approx(model_signature) and model_style_signature == head_style:
		return
	face_model.build(cut, chin_width, face_projection, head_style)
	model_signature = signature
	model_style_signature = head_style
	model_revision += 1
	for entry in [["face", face_model.planes, 16], ["nose", face_model.nose_planes, 8]]:
		var packed := PackedVector4Array()
		for plane in entry[1]:
			packed.append(Vector4(plane.normal.x, plane.normal.y, plane.normal.z, plane.d))
		var count := packed.size()
		while packed.size() < entry[2]:
			packed.append(Vector4.ZERO)
		surface_material.set_shader_parameter(entry[0] + "_planes", packed)
		surface_material.set_shader_parameter(entry[0] + "_count", count)

func _model_line(a: Vector3, b: Vector3, color: Color, width: float, steps: int = 10) -> void:
	var front := PackedVector2Array()
	var back := PackedVector2Array()
	for i in steps:
		var midpoint := a.lerp(b, (i + 0.5) / steps)
		if _point_visible(midpoint):
			front.append(project_point(a.lerp(b, float(i) / steps)))
			front.append(project_point(a.lerp(b, float(i + 1) / steps)))
		elif hidden_lines and i % 4 < 2:
			back.append(project_point(a.lerp(b, float(i) / steps)))
			back.append(project_point(a.lerp(b, float(i + 1) / steps)))
	if not back.is_empty():
		draw_multiline(back, Color(color, 0.16), 1, true)
	if not front.is_empty():
		draw_multiline(front, color, width, true)

func _draw_face() -> void:
	var edges: Array = face_model.secondary_edges if secondary_enabled else face_model.edges
	if plane_edges:
		for edge in edges:
			if edge.size() > 2 and edge[2] == 1 and not nose_enabled:
				continue
			_model_line(edge[0], edge[1], Color(0.24, 0.26, 0.27, 0.72), 1.5, 8)
	if nose_enabled and not secondary_enabled:
		for edge in face_model.nose_edges:
			_model_line(edge[0], edge[1], INK, 1.8, 6)
	var levels := [[2.0 / 3.0, "发际 +2/3R", GREEN], [0.0, "眉骨 0", RED], [-1.0 / 3.0, "下眼睑 −1/3R", BLUE], [-2.0 / 3.0, "鼻底 −2/3R", GREEN], [-1.0, "嘴线 −R", PURPLE], [-4.0 / 3.0, "下巴 −4/3R", INK]]
	var ys := [2.0 / 3.0, 0.0, -2.0 / 3.0, -1.0, -4.0 / 3.0]
	for i in ys.size() - 1:
		if not secondary_enabled or landmarks:
			_model_line(_face_front(ys[i]), _face_front(ys[i + 1]), BLUE, 2.0)
	if landmarks:
		for level in levels:
			var ring: Array[Vector3] = face_model.secondary_section(level[0]) if secondary_enabled else face_model.section(level[0])
			for i in ring.size():
				_model_line(ring[i], ring[(i + 1) % ring.size()], level[2], 2.4, 8)
			var anchor: Vector3 = _face_front(level[0])
			if (head_basis * Vector3.BACK).z > -0.2:
				var label_x := size.x - 675
				var y := project_point(anchor).y
				draw_line(project_point(anchor) + Vector2(8, 0), Vector2(label_x - 8, y), Color(level[2], 0.35), 1, true)
				draw_string(font, Vector2(label_x, y - 5), level[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, level[2])
	var rho := sqrt(1 - cut * cut)
	for side in [-1.0, 1.0]:
		var ear := [Vector2(-0.06, -rho + 2.0 / 3.0), Vector2(0.10, -rho + 2.0 / 3.0), Vector2(0.15, -rho + 0.49), Vector2(0.10, -rho), Vector2(-0.06, -rho + 0.05)]
		for i in ear.size():
			var a := Vector3(side * (cut + 0.012), ear[i].y, ear[i].x)
			var b := Vector3(side * (cut + 0.012), ear[(i + 1) % ear.size()].y, ear[(i + 1) % ear.size()].x)
			_model_line(a, b, PURPLE if landmarks else Color("615f59"), 2.0, 1)
		var ear_bottom := Vector3(side * cut, -rho, 0)
		var jaw_y := lerpf(-rho, -4.0 / 3.0, 0.28)
		var corner := Vector3(side * lerpf(cut, chin_width, 0.28), jaw_y, 0.10)
		var chin := Vector3(side * chin_width, -4.0 / 3.0, 0.68 * face_projection)
		if not secondary_enabled:
			_model_line(ear_bottom, corner, INK, 3.0)
			_model_line(corner, chin, INK, 3.0)
	if secondary_enabled and not landmarks:
		for i in 28:
			if i % 2 == 0:
				continue
			var y0 := lerpf(2.0 / 3.0, -4.0 / 3.0, float(i) / 28)
			var y1 := lerpf(2.0 / 3.0, -4.0 / 3.0, float(i + 1) / 28)
			_model_line(_face_front(y0), _face_front(y1), Color(INK, 0.30), 1.0, 2)

func _face_front(y: float) -> Vector3:
	return face_model.secondary_front(y) if secondary_enabled else face_model.front(y)

func _update_secondary_surface() -> void:
	secondary_layer.visible = face_enabled and secondary_enabled
	if not secondary_layer.visible:
		return
	for entry in [["center", center], ["radius", radius], ["inverse_basis", inverse_basis], ["cut", cut], ["sliced", sliced], ["caps", caps], ["cap_opacity", cap_opacity]]:
		secondary_material.set_shader_parameter(entry[0], entry[1])
	var triangles: Array = []
	for tri in face_model.secondary_triangles:
		if tri[4] == 1 and not nose_enabled:
			continue
		var normal: Vector3 = head_basis * tri[3]
		# Keep back-facing triangles for the back of the closed facial shell too.
		var depth: float = (head_basis * ((tri[0] + tri[1] + tri[2]) / 3)).z
		triangles.append([depth, tri, normal])
	triangles.sort_custom(func(a: Array, b: Array): return a[0] < b[0])
	var positions := PackedVector2Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var light := Vector3(-0.55, 0.65, 0.8).normalized()
	for item in triangles:
		var tri: Array = item[1]
		var normal: Vector3 = item[2]
		var brightness := maxf(0, normal.dot(light))
		var shade := Color("8e999a").lerp(Color("f3e6cc"), brightness * 0.94)
		if tri[4] == 1:
			shade = shade.lerp(Color("ddc6a7"), 0.12)
		for i in 3:
			positions.append(project_point(tri[i]))
			colors.append(shade)
			uv.append(Vector2((head_basis * tri[i]).z, 0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	secondary_layer.mesh = mesh

func _solid_depth(q: Vector3, low: float, high: float, offset: Vector3) -> float:
	var inv := inverse_basis
	var origin := inv * Vector3(q.x, q.y, 0) - offset
	var direction := inv * Vector3.BACK
	var b := origin.dot(direction)
	var discriminant := b * b - origin.length_squared() + 1
	if discriminant < -0.00001:
		return -INF
	var root := sqrt(maxf(0, discriminant))
	var near_z := -b - root
	var far_z := -b + root
	if absf(direction.x) < 0.00001:
		if origin.x < low - 0.00001 or origin.x > high + 0.00001:
			return -INF
	else:
		var z0 := (low - origin.x) / direction.x
		var z1 := (high - origin.x) / direction.x
		near_z = maxf(near_z, minf(z0, z1))
		far_z = minf(far_z, maxf(z0, z1))
	if near_z > far_z + 0.00001:
		return -INF
	if face_enabled:
		return maxf(_clipped_skull_depth(near_z, far_z, origin, direction, Vector3.DOWN, -2.0 / 3.0), _clipped_skull_depth(near_z, far_z, origin, direction, Vector3.BACK, 0))
	return far_z

func _clipped_skull_depth(near_z: float, far_z: float, origin: Vector3, direction: Vector3, normal: Vector3, d: float) -> float:
	var denom := normal.dot(direction)
	var remaining := d - normal.dot(origin)
	if absf(denom) < 0.00001:
		if remaining < -0.00001:
			return -INF
	elif denom > 0:
		far_z = minf(far_z, remaining / denom)
	else:
		near_z = maxf(near_z, remaining / denom)
	return far_z if near_z <= far_z + 0.00001 else -INF

func _draw_axes() -> void:
	var origin := Vector2(106, size.y - 225)
	for entry in [[Vector3.RIGHT, "X 左耳", RED], [Vector3.UP, "Y 头顶", GREEN], [Vector3.BACK, "Z 脸朝向", BLUE]]:
		var direction: Vector3 = head_basis * entry[0]
		var delta := Vector2(direction.x, -direction.y) * 68
		var tip := origin + delta
		draw_line(origin, tip, entry[2], 2.5, true)
		if delta.length() > 5:
			var back := delta.normalized() * -9
			draw_line(tip, tip + back.rotated(0.45), entry[2], 2, true)
			draw_line(tip, tip + back.rotated(-0.45), entry[2], 2, true)
		draw_string(font, tip + Vector2(6, -7), entry[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, entry[2])
	if face_enabled:
		return
	var face_tip := project_point(Vector3(0, 0, 1.3))
	draw_line(project_point(Vector3(0, 0, 1)), face_tip, BLUE, 2, true)
	draw_circle(face_tip, 3, BLUE)

func _capture() -> void:
	for style in 2:
		set_head_style(style)
		for pose in [[30, 15, 0], [0, 0, 0], [75, -30, 25], [180, 0, 0]]:
			set_angles(pose[0], pose[1], pose[2])
			for frame in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://preview_%s_%d.png" % ["male" if style == 0 else "girl", pose[0]])
	get_tree().quit()
