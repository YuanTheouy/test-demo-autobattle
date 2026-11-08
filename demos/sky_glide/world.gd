extends Node3D

const Glider = preload("res://glider.gd")
const INK = Color("203d49")
const CREAM = Color("fff3d6")
var player: CharacterBody3D
var speed_label: Label
var altitude_label: Label
var hint: Label
var objective: Label
var speed_bar: ProgressBar
var state_label: Label
var gate_flags := [false, false]
var gate_positions := [Vector3(0, 44, -64), Vector3(-8, 34, -142)]
var thermal_center := Vector3(-8, 0, -208)
var elapsed := 0.0
var reset_delay := -1.0
var finished := false
var thermal_rings: Array[MeshInstance3D] = []
var gate_markers: Array[MeshInstance3D] = []
var previous_position := Vector3.ZERO
var preview_frames := 0
var preview_mode := false

func _ready() -> void:
	_build_environment()
	_build_world()
	player = Glider.new()
	add_child(player)
	player.crashed.connect(_on_crash)
	player.landed.connect(_on_land)
	previous_position = player.position
	_build_ui()
	preview_mode = "--preview" in OS.get_cmdline_user_args()
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_smoke_test")
		get_tree().create_timer(12).timeout.connect(func():
			push_error("Smoke test timed out")
			get_tree().quit(1))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R:
		_restart()
	if event.physical_keycode == KEY_SPACE and not player.flying and not finished:
		player.launch()
	if event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()

func _process(delta: float) -> void:
	elapsed += delta
	for i in thermal_rings.size():
		var ring := thermal_rings[i]
		ring.position.y = 15 + fmod(elapsed * 7 + i * 9.0, 94)
		ring.rotation.y = elapsed * 0.25 + i
	if reset_delay > 0:
		reset_delay -= delta
		if reset_delay <= 0:
			_restart()
	_update_ui()
	if preview_mode:
		preview_frames += 1
		if preview_frames == 12:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://preview.png")
			get_tree().quit()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var horizontal_distance := Vector2(player.position.x - thermal_center.x, player.position.z - thermal_center.z).length()
	player.lift = 19.0 * clampf((32 - horizontal_distance) / 7, 0, 1) if player.position.y < 112 else 0.0
	if player.flying:
		for i in gate_positions.size():
			var target: Vector3 = gate_positions[i]
			if not gate_flags[i] and previous_position.z >= target.z and player.position.z < target.z:
				var ratio := (previous_position.z - target.z) / maxf(0.001, previous_position.z - player.position.z)
				var crossing := previous_position.lerp(player.position, ratio)
				if absf(crossing.x - target.x) < 9.0 and absf(crossing.y - target.y) < 7.0:
					gate_flags[i] = true
					gate_markers[i].material_override.albedo_color = Color("a6efb3")
	previous_position = player.position

func _restart() -> void:
	gate_flags = [false, false]
	for marker in gate_markers:
		marker.material_override.albedo_color = Color("ffe2a1")
	finished = false
	reset_delay = -1
	player.reset_at(Vector3(0, 66, -2))
	previous_position = player.position

func _on_crash() -> void:
	reset_delay = 1.4

func _on_land() -> void:
	if player.position.y > 77 and player.position.z < -265:
		finished = true
	else:
		# A safe intermediate landing is allowed; Space launches again.
		player.airspeed = 22

func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _mesh(mesh: Mesh, at: Vector3, color: Color, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(color, color.a < 1)
	parent.add_child(instance)
	return instance

func _box(at: Vector3, size: Vector3, color: Color, solid: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := _mesh(mesh, at, color)
	if solid:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		instance.add_child(body)
	return instance

func _cone(at: Vector3, bottom: float, top: float, height: float, color: Color, segments: int = 7) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = segments
	return _mesh(mesh, at, color)

func _island(center: Vector3, radius: float, depth: float, grass: Color) -> void:
	_cone(center - Vector3.UP * depth * 0.5, radius * 0.18, radius, depth, Color("776e71"), 9)
	_cone(center - Vector3.UP * depth * 0.15, radius * 0.76, radius * 1.01, depth * 0.3, Color("b8a08b"), 9)
	var top := _cone(center - Vector3.UP * 0.55, radius, radius, 1.1, grass, 9)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius * 0.965
	shape.height = 1.1
	collision.shape = shape
	body.add_child(collision)
	top.add_child(body)
	# Colliding taper keeps island undersides physical as well as visible.
	var rock_body := StaticBody3D.new()
	var rock_shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	var vertices := PackedVector3Array()
	for i in 9:
		var angle := TAU * i / 9.0
		vertices.append(center + Vector3(cos(angle) * radius, -1.2, sin(angle) * radius))
		vertices.append(center + Vector3(cos(angle) * radius * 0.18, -depth, sin(angle) * radius * 0.18))
	convex.points = vertices
	rock_shape.shape = convex
	rock_body.add_child(rock_shape)
	add_child(rock_body)

func _tree(at: Vector3, height: float) -> void:
	_cone(at + Vector3.UP * height * 0.35, 0.38, 0.24, height * 0.7, Color("7e6654"))
	_cone(at + Vector3.UP * height * 0.75, height * 0.40, 0.1, height * 0.8, Color("43846d"), 5)
	_cone(at + Vector3.UP * height, height * 0.27, 0.0, height * 0.65, Color("68a17a"), 5)

func _flag(at: Vector3, color: Color) -> void:
	_cone(at + Vector3.UP * 3, 0.11, 0.11, 6, Color("efe2bd"))
	_box(at + Vector3(1.3, 5, 0), Vector3(2.6, 1.1, 0.07), color)

func _sign(text: String, at: Vector3, color: Color = CREAM, size: int = 52) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size
	label.pixel_size = 0.035
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.outline_size = 8
	add_child(label)

func _build_environment() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("508fae")
	sky_material.sky_horizon_color = Color("c9dfd9")
	sky_material.ground_horizon_color = Color("c9dfd9")
	sky_material.ground_bottom_color = Color("6d9fb1")
	sky_material.sky_curve = 0.22
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d8e9ed")
	environment.ambient_light_energy = 0.38
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color("abcbd0")
	environment.fog_density = 0.0015
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -32, 0)
	sun.light_color = Color("ffe1ab")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.0
	sun.directional_shadow_max_distance = 400
	add_child(sun)

func _build_world() -> void:
	_island(Vector3(0, 64, 23), 19, 30, Color("95ad76"))
	_box(Vector3(0, 64.2, 8), Vector3(7, 0.35, 17), Color("b58a61"), true)
	for x in [-4, 4]:
		_flag(Vector3(x, 64.5, 27), Color("dc845e"))
	_tree(Vector3(-10, 64, 26), 8)
	_tree(Vector3(10, 64, 29), 11)
	_tree(Vector3(-6, 64, 34), 6)
	_sign("起风台", Vector3(0, 70, 30))
	for i in gate_positions.size():
		var at: Vector3 = gate_positions[i]
		_island(Vector3(at.x, at.y - 8, at.z), 19, 32, Color("91a775"))
		for side in [-1, 1]:
			_box(at + Vector3(side * 11, -0.5, 0), Vector3(4, 17, 5), Color("c6b99c"), true)
			_box(at + Vector3(side * 10, 6.5, 0), Vector3(5, 4, 5.2), Color("dccbad"), true).rotation.z = side * 0.18
		_box(at + Vector3(0, 9, 0), Vector3(18, 3, 5), Color("ded0ac"), true)
		var torus := TorusMesh.new()
		torus.inner_radius = 5.2
		torus.outer_radius = 5.4
		torus.rings = 32
		torus.ring_segments = 6
		var marker := _mesh(torus, at, Color("ffe2a1"))
		marker.rotation.x = PI / 2
		gate_markers.append(marker)
		_sign("%02d  /  穿越" % (i + 1), at + Vector3(0, 15, 0), CREAM, 38)
		_tree(at + Vector3(15, -8, 4), 7)
	# A broad updraft permits several turns before the climb to the final island.
	for i in 11:
		var torus := TorusMesh.new()
		torus.inner_radius = 30.8
		torus.outer_radius = 31.1
		torus.rings = 24
		torus.ring_segments = 4
		thermal_rings.append(_mesh(torus, Vector3(-8, 15 + i * 8, -208), Color(0.72, 0.94, 0.86, 0.32)))
	for i in 18:
		var angle := i * TAU / 18
		_sign("↑", Vector3(-8 + cos(angle) * 29, 20 + (i % 4) * 18, -208 + sin(angle) * 29), Color("c5efce"), 80)
	_sign("03  /  借风爬升", Vector3(-8, 112, -208), Color("d9f3c5"), 45)
	_island(Vector3(0, 78, -298), 25, 46, Color("a8b77c"))
	_box(Vector3(0, 78.12, -289), Vector3(13, 0.24, 21), Color("d5b778"))
	for x in [-8, 8]:
		_flag(Vector3(x, 78, -281), Color("e4ae55"))
	_tree(Vector3(-14, 78, -306), 13)
	_tree(Vector3(12, 78, -309), 9)
	_tree(Vector3(4, 78, -315), 7)
	_sign("04  /  落在风栖岛", Vector3(0, 91, -297), CREAM, 52)
	# Distant scenery is intentionally outside the compact playable route.
	var rng := RandomNumberGenerator.new()
	rng.seed = 71023
	for i in 18:
		var x := rng.randf_range(90, 310) * (-1 if i % 2 == 0 else 1)
		var z := rng.randf_range(-520, 50)
		var y := rng.randf_range(-8, 72)
		var radius := rng.randf_range(12, 37)
		_island(Vector3(x, y, z), radius, radius * 1.7, Color("7e9e85"))
		_tree(Vector3(x, y, z), rng.randf_range(8, 16))
	for i in 40:
		var at := Vector3(rng.randf_range(-380, 380), rng.randf_range(-45, -20), rng.randf_range(-560, 120))
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(13, 30)
		mesh.height = mesh.radius * 0.65
		mesh.radial_segments = 7
		mesh.rings = 4
		_mesh(mesh, at, Color("dbe7df"))

func _panel(at: Vector2, size: Vector2, color: Color) -> Panel:
	var panel := Panel.new()
	panel.position = at
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", style)
	$HUD.add_child(panel)
	return panel

func _label(text: String, at: Vector2, size: int, color: Color, parent: Node) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _build_ui() -> void:
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	var root := Control.new()
	root.theme = theme
	hud.add_child(root)
	# Panels inherit the shared font through the CanvasLayer's default theme override.
	ThemeDB.fallback_font = font
	var title_panel := _panel(Vector2(28, 26), Vector2(320, 115), Color(0.97, 0.96, 0.89, 0.94))
	_label("FLIGHT STUDY   /   001", Vector2(22, 14), 13, Color("687f80"), title_panel)
	_label("逐 风", Vector2(20, 32), 38, INK, title_panel)
	_label("SKYGLIDE  ·  空岛滑翔实验", Vector2(22, 85), 14, INK, title_panel)
	var route_panel := _panel(Vector2(28, 155), Vector2(320, 116), Color(0.10, 0.20, 0.24, 0.88))
	_label("本次航线", Vector2(20, 13), 13, Color("a7c8c7"), route_panel)
	objective = _label("", Vector2(20, 38), 19, CREAM, route_panel)
	_label("俯冲 → 穿拱 → 借风 → 登岛", Vector2(20, 80), 14, Color("b5d4cf"), route_panel)
	var telemetry := _panel(Vector2(1190, 26), Vector2(222, 192), Color(0.10, 0.20, 0.24, 0.88))
	_label("AIR / 飞行数据", Vector2(18, 12), 13, Color("a7c8c7"), telemetry)
	speed_label = _label("", Vector2(18, 34), 35, CREAM, telemetry)
	speed_bar = ProgressBar.new()
	speed_bar.position = Vector2(20, 91)
	speed_bar.size = Vector2(181, 5)
	speed_bar.max_value = 64
	speed_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("e8b86e")
	speed_bar.add_theme_stylebox_override("fill", fill)
	telemetry.add_child(speed_bar)
	altitude_label = _label("", Vector2(20, 111), 18, CREAM, telemetry)
	state_label = _label("", Vector2(20, 149), 15, Color("b9e6cc"), telemetry)
	var footer := _panel(Vector2(28, 790), Vector2(1384, 82), Color(0.10, 0.20, 0.24, 0.9))
	hint = _label("", Vector2(22, 10), 19, CREAM, footer)
	_label("W / ↑  压低俯冲     S / ↓  拉起爬升     A D / ← →  转向     空格  起飞 / 空中减速     R  重来     Esc  退出", Vector2(22, 48), 15, Color("bdd0ca"), footer)
	_label("+", Vector2(712, 438), 22, Color(1, 0.97, 0.85, 0.6), root)

func _update_ui() -> void:
	speed_label.text = "%02d  m/s" % roundi(player.airspeed if player.flying else 0)
	altitude_label.text = "高度  %03d m" % maxi(0, roundi(player.position.y))
	speed_bar.value = player.airspeed if player.flying else 0
	var count := int(gate_flags[0]) + int(gate_flags[1])
	objective.text = "石拱 %d / 2    →    风栖岛" % count
	if finished:
		hint.text = "成功登岛！石拱 %d / 2  ·  按 R 再飞一次，试着穿过全部石拱。" % count
		state_label.text = "● 已安全抵达"
	elif player.disabled:
		hint.text = "这次没接住风。正在返回起风台……（R 可立即重来）"
		state_label.text = "● 失去平衡"
	elif not player.flying:
		hint.text = "按空格跃出平台。前方第一个石拱比你低，先压低翼面，用高度换速度。"
		state_label.text = "● 等待起飞"
	elif player.lift > 2:
		hint.text = "进入上升气流！空格减速、转向盘旋，升到 95 m 左右再飞向远处的风栖岛。"
		state_label.text = "↑ 上升气流"
	elif player.airspeed < 15:
		hint.text = "速度不足，正在失速下沉！按 W 压低翼面，先把速度找回来。"
		state_label.text = "! 失速下沉"
	elif player.position.z < -240:
		hint.text = "准备着陆：对准岛面，空格减速，轻轻拉平。低于 32 m/s 可安全落地。"
		state_label.text = "● 接近目的地"
	else:
		hint.text = "俯冲蓄速，拉起换高度。穿过两道石拱后，寻找绿色向上的风。"
		state_label.text = "● 自由滑翔"

func _smoke_test() -> void:
	await get_tree().physics_frame
	var dive := 22.0
	var climb := 22.0
	for i in 60:
		dive = Glider.evolve_speed(dive, -0.5, false, 1.0 / 60)
		climb = Glider.evolve_speed(climb, 0.4, false, 1.0 / 60)
	assert(dive > 22, "Diving must gain speed")
	assert(climb < 22, "Climbing must spend speed")
	assert(Glider.evolve_speed(30, 0, true, 0.1) < Glider.evolve_speed(30, 0, false, 0.1), "Air brake must slow down")
	player.control_override = true
	player.launch()
	player.pitch = -0.4
	var start := player.position
	for i in 30:
		await get_tree().physics_frame
	assert(player.position.z < start.z - 5, "Launch must move forward")
	assert(player.position.y < start.y, "Dive must descend")
	assert(not player.disabled, "Launch must clear the platform")
	player.position = Vector3(-8, 45, -208)
	player.pitch = 0
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(player.lift > 15, "Thermal must provide lift")
	assert(player.velocity.y > 0, "Thermal must climb")
	# Exercise real collision landing, crash and restart paths.
	player.position = Vector3(0, 80, -290)
	player.pitch = -0.1
	player.airspeed = 12
	for i in 90:
		await get_tree().physics_frame
		if finished:
			break
	assert(finished, "Destination must accept a slow physical landing")
	_restart()
	player.launch()
	player.position = Vector3(11, 44, -59)
	player.pitch = 0
	player.airspeed = 36
	for i in 20:
		await get_tree().physics_frame
		if player.disabled:
			break
	assert(player.disabled, "Stone arch pillars must collide")
	_restart()
	assert(not player.disabled and not finished and not player.flying, "Restart must clear flight state")
	print("SKYGLIDE PASS: dive, climb, brake, launch, thermal, landing, collision, restart")
	get_tree().quit()
