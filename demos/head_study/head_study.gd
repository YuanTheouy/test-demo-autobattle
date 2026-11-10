extends Control
## Drawing coordinates: +X = subject's left, +Y = up, +Z = face/viewer.
## Positive angles: right yaw, downward pitch, right roll.

const INK := Color("343e43")
const BLUE := Color("237caa")
const RED := Color("c75c49")
const GREEN := Color("50846a")
const TAU_STEPS := 180
var yaw := 30.0
var pitch := 15.0
var roll := 0.0
var cut := 0.76
var cap_opacity := 0.22
var latitude := 0.0
var sliced := true
var caps := true
var hidden_lines := true
var grid := false
var axes := true
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
	_label("转一转，再画一遍", 27)
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
	_slider("cut", "切面位置 a（球半径 = 1）", 0.45, 0.98, cut, 0.01)
	_slider("cap_opacity", "薄片不透明度（越低越透明）", 0.05, 0.6, cap_opacity, 0.01)
	_slider("latitude", "横线高度 h", -0.65, 0.65, latitude, 0.01)
	_toggle("两侧削平（X = ±a）", "sliced", sliced)
	_toggle("显示切下的薄片", "caps", caps)
	_toggle("背面虚线", "hidden_lines", hidden_lines)
	_toggle("辅助经纬网", "grid", grid)
	_toggle("坐标轴与脸朝向", "axes", axes)
	_label("最少只记这三条", 21)
	_label("竖线：p(t) = (0, sin t, cos t)\n横线：p(t) = (r sin t, h, r cos t)\n切口：p(t) = (±a, ρ sin t, ρ cos t)\nr = √(1 − h²)；ρ = √(1 − a²)", 16)
	_label("把点转好，再投到纸上", 21)
	_label("q = Ry(−yaw) Rx(pitch) Rz(roll) p\n纸上点 = 中心 + s · (qx, −qy)\n右边先算：先 roll，再 pitch，再 yaw。\n角度绕随头转动的局部轴；不是拖动历史。", 15)
	_label("蓝色 = 面部中线　红色 = 横线\n绿色 = 平切口　半透明 = 原位薄片\n实线在前，虚线在后。正交投影，无近大远小。", 15)
	_label("观察：正面十字可呈直线；转头后才露出弧度。切口本来是圆，斜看成椭圆，侧着看会压成线。\n这是球形头壳构造，不是完整的人脸解剖。", 15)

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
		readouts[key].text = "%s   %s" % [title, ("%d°" % value) if step_value == 1 else ("%.2f" % value)]
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
	center = Vector2(drawing_width * 0.5, size.y * 0.49)
	radius = minf(drawing_width / 3.5, size.y * 0.31)
	draw_string(font, Vector2(32, 49), "头部构造 / 十字线与侧切片", HORIZONTAL_ALIGNMENT_LEFT, -1, 29, INK)
	draw_string(font, Vector2(33, 80), "拖动右侧滑条，观察同一条球面曲线如何投影。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
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
	# Surface silhouette, a great circle normal to the viewing direction.
	var inv := inverse_basis
	_curve(func(t: float): return inv * Vector3(cos(t), sin(t), 0), INK, 2.2, true)
	if grid:
		for h in [-0.6, -0.3, 0.3, 0.6]:
			var r := sqrt(1 - h * h)
			_curve(func(t: float): return Vector3(r * sin(t), h, r * cos(t)), Color(0.38, 0.43, 0.44, 0.42), 1)
		for angle in [-60.0, -30.0, 30.0, 60.0]:
			var a := deg_to_rad(angle)
			_curve(func(t: float): return Vector3(sin(a) * cos(t), sin(t), cos(a) * cos(t)), Color(0.38, 0.43, 0.44, 0.42), 1)
	_curve(func(t: float): return Vector3(0, sin(t), cos(t)), BLUE, 3.4)
	var horizontal_radius := sqrt(1 - latitude * latitude)
	_curve(func(t: float): return Vector3(horizontal_radius * sin(t), latitude, horizontal_radius * cos(t)), RED, 3.4)
	if sliced:
		for side in [-1.0, 1.0]:
			_cut_rim(side, Vector3.ZERO, side)
			if caps:
				_cap_silhouette(side, Vector3.ZERO)
	if axes:
		_draw_axes()
	var front := Vector3(0, 0, 1)
	if (head_basis * front).z > 0:
		draw_circle(project_point(front), 5, BLUE)
		draw_string(font, project_point(front) + Vector2(10, -9), "面部正前方", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, BLUE)
	draw_string(font, Vector2(33, size.y - 90), "先画外轮廓 → 找切面椭圆 → 沿球面画十字线", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	draw_string(font, Vector2(33, size.y - 56), "薄片留在原位，透过它看切面；切口半径 ρ = %.2f" % sqrt(1 - cut * cut), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, GREEN)
	draw_string(font, Vector2(33, size.y - 29), "隐藏辅助线后临摹，再打开核对。横线高度可用于研究眉线或眼线。", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)

func _ring_point(x: float, t: float) -> Vector3:
	var r := sqrt(maxf(0, 1 - x * x))
	return Vector3(x, r * sin(t), r * cos(t))

func _curve(point: Callable, color: Color, width: float, _silhouette: bool = false) -> void:
	for i in TAU_STEPS:
		var a: Vector3 = point.call(TAU * i / TAU_STEPS)
		var b: Vector3 = point.call(TAU * (i + 1) / TAU_STEPS)
		var middle: Vector3 = point.call(TAU * (i + 0.5) / TAU_STEPS)
		if sliced and absf(middle.x) > cut:
			continue
		var visible_part := _point_visible(middle)
		if visible_part or (hidden_lines and i % 5 < 2):
			var line_color := color if visible_part else Color(color, 0.23)
			draw_line(project_point(a), project_point(b), line_color, width if visible_part else 1.3, true)

func _cut_rim(side: float, offset: Vector3, _normal_sign: float) -> void:
	for i in TAU_STEPS:
		var a := _ring_point(side * cut, TAU * i / TAU_STEPS)
		var b := _ring_point(side * cut, TAU * (i + 1) / TAU_STEPS)
		var visible_part := _point_visible(_ring_point(side * cut, TAU * (i + 0.5) / TAU_STEPS) + offset)
		if visible_part or (hidden_lines and i % 5 < 2):
			draw_line(project_point(a + offset), project_point(b + offset), GREEN if visible_part else Color(GREEN, 0.23), 2 if visible_part else 1, true)

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
	return q.z >= top - 0.008

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
	var face_tip := project_point(Vector3(0, 0, 1.3))
	draw_line(project_point(Vector3(0, 0, 1)), face_tip, BLUE, 2, true)
	draw_circle(face_tip, 3, BLUE)

func _capture() -> void:
	for pose in [[30, 15, 0], [0, 0, 0], [75, -30, 25], [180, 0, 0]]:
		set_angles(pose[0], pose[1], pose[2])
		for frame in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://preview_%d.png" % pose[0])
	get_tree().quit()
