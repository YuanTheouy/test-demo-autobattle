extends Node3D

const Glider = preload("res://glider.gd")
const INK = Color("203d49")
const CREAM = Color("fff3d6")
const MAIN_SPAWN := Vector3(6, 65, 24)
var player: CharacterBody3D
var speed_label: Label
var altitude_label: Label
var hint: Label
var objective: Label
var speed_bar: ProgressBar
var state_label: Label
var inventory_label: Label
var equipment_label: Label
var map_view: Control
var islands: Array[Dictionary] = []
var thermals: Array[Dictionary] = []
var inventory := {"wood": 0, "membrane": 0, "plan": 0, "crystal": 0}
var collected: Dictionary = {}
var pickup_meshes: Dictionary = {}
var upgraded := false
var current_island := "camp"
var toast := ""
var toast_timer := 0.0
var region := 1
var gate_flags := [false, false]
var gate_positions := [Vector3(-75, 88, -145), Vector3(65, 170, -550)]
var elapsed := 0.0
var reset_delay := -1.0
var finished := false
var thermal_rings: Array[MeshInstance3D] = []
var wind_volumes: Array[MeshInstance3D] = []
var gate_markers: Array[MeshInstance3D] = []
var previous_position := Vector3.ZERO
var preview_frames := 0
var preview_mode := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_environment()
	_build_world()
	player = Glider.new()
	player.spawn_point = MAIN_SPAWN
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.crashed.connect(_on_crash)
	player.landed.connect(_on_land)
	previous_position = player.position
	_build_ui()
	preview_mode = "--preview" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and not preview_mode and not "--script" in OS.get_cmdline_args():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("_smoke_test")
		get_tree().create_timer(25).timeout.connect(func():
			push_error("Smoke test timed out")
			get_tree().quit(1))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R:
		if event.shift_pressed:
			_set_paused(false)
			get_tree().reload_current_scene()
		else:
			_restart()
	if event.physical_keycode == KEY_E:
		_interact()
	if event.physical_keycode == KEY_M:
		map_view.visible = not map_view.visible
		_set_paused(map_view.visible)
	if event.physical_keycode == KEY_V:
		player.first_person = not player.first_person
	if event.physical_keycode == KEY_SPACE:
		player.jump()
	if event.physical_keycode == KEY_F:
		player.toggle_paraglider()
	if event.physical_keycode == KEY_ESCAPE:
		map_view.visible = false
		_set_paused(not get_tree().paused)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_tree().paused or not player.mouse_look_enabled:
			map_view.visible = false
			_set_paused(false)
		else:
			_interact()

func _set_paused(value: bool) -> void:
	get_tree().paused = value
	player.mouse_look_enabled = not value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if get_tree().paused:
		hint.text = "已暂停 · 点击画面或 Esc 继续；鼠标控制视角，左键 / E 互动，右键空中减速。"
		return
	elapsed += delta
	toast_timer = maxf(0, toast_timer - delta)
	for i in thermal_rings.size():
		var ring := thermal_rings[i]
		var bottom: float = ring.get_meta("bottom")
		var span: float = ring.get_meta("span")
		ring.position.y = bottom + fmod(elapsed * 5 + float(ring.get_meta("phase")), span)
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
	if get_tree().paused:
		return
	player.wind_velocity = sample_wind(player.position)
	region = 2 if player.position.z < -380 else 1
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
	reset_delay = -1
	player.reset_at(MAIN_SPAWN)
	player.wind_velocity = Vector3.ZERO
	current_island = "camp"
	previous_position = player.position

func _on_crash() -> void:
	reset_delay = 1.4

func _on_land() -> void:
	for island in islands:
		var center: Vector3 = island.pos
		if absf(player.position.y - center.y) < 3 and Vector2(player.position.x - center.x, player.position.z - center.z).length() < float(island.radius) + 1:
			current_island = island.id
			return
	if absf(player.position.x + 6) < 5.5 and player.position.z > -11 and player.position.z < 40 and player.position.y > 66 and player.position.y < 87:
		current_island = "camp"
		return
	if absf(player.position.x - 14) < 4.5 and absf(player.position.z - 5) < 4.5 and player.position.y > 83 and player.position.y < 87:
		current_island = "camp"
		return
	current_island = ""

func sample_wind(at: Vector3) -> Vector3:
	var result := 0.0
	for thermal in thermals:
		var center: Vector2 = thermal.center
		var distance := Vector2(at.x, at.z).distance_to(center)
		var radius: float = thermal.radius
		var top: float = thermal.top
		var radial := 1.0 - smoothstep(radius - 12, radius, distance)
		var bottom: float = thermal.bottom
		var fade_start: float = thermal.get("fade_start", top - 28)
		var vertical := (1.0 - smoothstep(fade_start, top, at.y)) * smoothstep(bottom - 8, bottom + 10, at.y)
		result = maxf(result, float(thermal.get("strength", 5.0)) * radial * vertical)
	# Island surfaces shelter the landing area; the wind must not prevent touchdown.
	for island in islands:
		var center: Vector3 = island.pos
		var distance := Vector2(at.x - center.x, at.z - center.z).length()
		result *= smoothstep(float(island.radius) + 2, float(island.radius) + 14, distance)
	return Vector3.UP * result

func interaction_target() -> Dictionary:
	if player.flying or player.disabled or not player.is_on_floor():
		return {}
	_on_land()
	if current_island == "camp":
		return {"pos": Vector3(6, 64, 20), "label": "工作台：左键 / E 制作远行翼（站在桌旁即可）"}
	if current_island == "summit":
		return {"pos": Vector3(18, 176, -615), "label": "信标：左键 / E 点亮"}
	for island in islands:
		if island.id == current_island and island.has("item") and not collected.has(island.id):
			return {"pos": island.pos, "label": "左键 / E 收集%s" % island.item_name}
	return {}

func interaction_distance(target: Dictionary) -> float:
	var at: Vector3 = target.pos
	return Vector2(player.position.x - at.x, player.position.z - at.z).length()

func _interact() -> void:
	var target := interaction_target()
	if target.is_empty():
		return
	if interaction_distance(target) > 4.5:
		_notify("再靠近一些：%s（距离 %.0f 米）。" % [target.label, interaction_distance(target)])
		return
	if current_island == "camp":
		if upgraded:
			_notify("远行翼已装备。按 M 看信标，先借高空风道升到 165 米左右。")
		elif inventory.wood >= 3 and inventory.membrane >= 2 and inventory.plan >= 1:
			inventory.wood -= 3
			inventory.membrane -= 2
			inventory.plan -= 1
			upgraded = true
			player.set_equipment(1)
			_notify("制作完成：轻木远行翼！阻力更小、滑翔距离更长。按 M 查看第二关。")
		else:
			_notify("还需轻木 3、翼膜 2、图纸 1。按 M 查看三座材料岛。")
		return
	if current_island == "summit":
		if not upgraded:
			_notify("先返回营地制作远行翼，完成第一关。")
			return
		finished = true
		_notify("信标已点亮！两关试玩完成。风晶可留作下一阶段的扑翼装备材料。")
		return
	for island in islands:
		if island.id != current_island or not island.has("item") or collected.has(island.id):
			continue
		inventory[island.item] += int(island.amount)
		collected[island.id] = true
		if pickup_meshes.has(island.id):
			pickup_meshes[island.id].queue_free()
		_notify("获得 %s × %d。材料已保留，R 可返回主岛。" % [island.item_name, island.amount])
		return

func _notify(message: String) -> void:
	toast = message
	toast_timer = 6

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
	var rock := _cone(center - Vector3.UP * depth * 0.5, radius * 0.18, radius, depth, Color("776e71"), 9)
	rock.mesh.cap_top = false
	var rim := _cone(center - Vector3.UP * depth * 0.15, radius * 0.76, radius * 1.01, depth * 0.3, Color("b8a08b"), 9)
	rim.mesh.cap_top = false
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

func _sign(text: String, at: Vector3, color: Color = CREAM, size: int = 52) -> Label3D:
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
	return label

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
	islands = [
		{"id": "camp", "name": "起风营地 / 工作台", "pos": Vector3(0, 64, 23), "radius": 26.0, "region": 1},
		{"id": "wood", "name": "轻木岛", "pos": Vector3(-42, 58, -68), "radius": 27.0, "region": 1, "item": "wood", "item_name": "轻木", "amount": 3},
		{"id": "membrane", "name": "翼膜岛", "pos": Vector3(48, 62, -94), "radius": 32.0, "region": 1, "item": "membrane", "item_name": "翼膜", "amount": 2},
		{"id": "ruins", "name": "风栖遗迹 / 图纸", "pos": Vector3(0, 78, -180), "radius": 25.0, "region": 1, "item": "plan", "item_name": "远行翼图纸", "amount": 1},
		{"id": "arch", "name": "穿拱练习岛", "pos": Vector3(-75, 76, -145), "radius": 18.0, "region": 1},
		{"id": "entry", "name": "石柱群岛 / 信标", "pos": Vector3(20, 142, -445), "radius": 30.0, "region": 2},
		{"id": "crystal", "name": "风晶岛", "pos": Vector3(-36, 149, -510), "radius": 23.0, "region": 2, "item": "crystal", "item_name": "风晶", "amount": 1},
		{"id": "spire", "name": "高塔岛", "pos": Vector3(65, 158, -550), "radius": 24.0, "region": 2},
		{"id": "summit", "name": "远方信标 / 终点", "pos": Vector3(10, 176, -620), "radius": 28.0, "region": 2},
	]
	thermals = [
		{"center": Vector2(-5, -61), "radius": 46.0, "top": 112.0, "bottom": 12.0, "strength": 7.0},
		{"center": Vector2(0, -130), "radius": 46.0, "top": 122.0, "bottom": 35.0, "strength": 7.0},
		{"center": Vector2(0, -265), "radius": 48.0, "top": 186.0, "bottom": 42.0, "high": true, "strength": 7.0, "fade_start": 140.0},
		{"center": Vector2(18, -529), "radius": 76.0, "top": 214.0, "bottom": 122.0, "strength": 6.0},
	]
	for island in islands:
		var at: Vector3 = island.pos
		var color := Color("95ad76") if island.region == 1 else Color("85b9ae")
		_island(at, island.radius, island.radius * (1.4 if island.region == 1 else 2.5), color)
		_tree(at + Vector3(-island.radius * 0.45, 0, 5), 7 if island.region == 1 else 11)
		_tree(at + Vector3(island.radius * 0.4, 0, 9), 6)
		_sign(island.name, at + Vector3(0, 12, 0), CREAM, 35)
		if island.has("item"):
			var collectible := Node3D.new()
			add_child(collectible)
			pickup_meshes[island.id] = collectible
			var box := BoxMesh.new()
			box.size = Vector3(3, 2, 3)
			_mesh(box, at + Vector3(0, 1.1, 0), Color("d9b76c"), collectible)
			var gem := PrismMesh.new()
			gem.size = Vector3(1.5, 2, 1.5)
			_mesh(gem, at + Vector3(0, 3.2, 0), Color("7de2d0"), collectible)
			_sign("站在箱子旁：E / 左键采集", at + Vector3(0, 6, 0), CREAM, 25).reparent(collectible)
		if island.id in ["entry", "summit"]:
			_beacon(at, 25 if island.id == "entry" else 32)
	# Walkable 26-degree ramp: all launch energy comes from the 20 m height gain.
	var ramp_angle := atan(0.5)
	_box(Vector3(-6, 74 - 0.3 * cos(ramp_angle), 18), Vector3(9, 0.6, sqrt(2000.0)), Color("b58a61"), true).rotation.x = ramp_angle
	_box(Vector3(-6, 83.6, -6), Vector3(9, 0.8, 8), Color("c49a6d"), true)
	_box(Vector3(-6, 73.5, -4), Vector3(2.4, 19, 2.4), Color("86634b"))
	_sign("步行上坡 → 高台助跑 → 空格跳出 → F 展伞", Vector3(-6, 68, 38), CREAM, 24)
	_sign("坡道入口 ← 沿地面走到这里", Vector3(4, 66.5, 41), CREAM, 22)
	_sign("84 m 起飞高台 / 靠下落加速", Vector3(-6, 89, -5), CREAM, 28)
	_box(Vector3(14, 74, 5), Vector3(8, 20, 8), Color("a58d73"), true)
	_box(Vector3(14, 84.15, 5), Vector3(8, 0.3, 8), Color("c6b389"), true)
	_sign("攀爬塔：按住左键抓墙，WASD 攀爬", Vector3(14, 69, 12), CREAM, 24)
	_sign("空格蹬离 / F 展伞", Vector3(14, 88, 5), CREAM, 26)
	_box(Vector3(6, 64.85, 20), Vector3(4, 0.2, 2.2), Color("9b795b"), true)
	for x in [-1.6, 1.6]:
		for z in [-0.7, 0.7]:
			_box(Vector3(6 + x, 64.4, 20 + z), Vector3(0.22, 0.8, 0.22), Color("77553e"))
	_sign("站在桌旁按 E / 左键制作，无需跳上桌", Vector3(6, 67.4, 20), CREAM, 25)
	for x in [-6, 6]:
		_flag(Vector3(x, 64.5, 28), Color("dc845e"))
	for i in gate_positions.size():
		var at: Vector3 = gate_positions[i]
		for side in [-1, 1]:
			_box(at + Vector3(side * 11, -0.5, 0), Vector3(4, 17, 5), Color("c6b99c"), true)
		_box(at + Vector3(0, 9, 0), Vector3(22, 3, 5), Color("ded0ac"), true)
		var torus := TorusMesh.new()
		torus.inner_radius = 5.2
		torus.outer_radius = 5.5
		torus.rings = 32
		torus.ring_segments = 6
		var marker := _mesh(torus, at, Color("ffe2a1"))
		marker.rotation.x = PI / 2
		gate_markers.append(marker)
	for thermal in thermals:
		var center: Vector2 = thermal.center
		var radius: float = thermal.radius
		var bottom: float = thermal.bottom
		var top: float = thermal.top
		var volume := CylinderMesh.new()
		volume.top_radius = radius
		volume.bottom_radius = radius
		volume.height = top - bottom
		volume.radial_segments = 48
		volume.cap_top = false
		volume.cap_bottom = false
		var cylinder := _mesh(volume, Vector3(center.x, (bottom + top) * 0.5, center.y), Color.WHITE)
		var mist := ShaderMaterial.new()
		mist.shader = preload("res://wind_volume.gdshader")
		cylinder.material_override = mist
		cylinder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wind_volumes.append(cylinder)
		for i in 7:
			var angle := TAU * i / 7.0
			var stroke := CylinderMesh.new()
			stroke.top_radius = 0.13
			stroke.bottom_radius = 0.13
			stroke.height = 4
			stroke.radial_segments = 5
			var ring := _mesh(stroke, Vector3(center.x + cos(angle) * radius * 0.63, bottom + i * 12, center.y + sin(angle) * radius * 0.63), Color("92d9c2"))
			ring.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var arrow := CylinderMesh.new()
			arrow.top_radius = 0
			arrow.bottom_radius = 0.75
			arrow.height = 1.5
			arrow.radial_segments = 5
			var head := _mesh(arrow, Vector3(0, 2.7, 0), Color("92d9c2"), ring)
			head.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.set_meta("bottom", bottom)
			ring.set_meta("span", top - bottom)
			ring.set_meta("phase", i * (top - bottom) / 7.0)
			thermal_rings.append(ring)
		_sign("↑ 高空风道" if thermal.get("high", false) else "↑ 上升气流", Vector3(center.x, top + 5, center.y), Color("d9f3c5"), 32)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71023
	for i in 12:
		var x := rng.randf_range(160, 310) * (-1 if i % 2 == 0 else 1)
		var z := rng.randf_range(-720, 50)
		var y := rng.randf_range(-8, 80)
		var radius := rng.randf_range(12, 28)
		_island(Vector3(x, y, z), radius, radius * 1.7, Color("7e9e85"))
		_tree(Vector3(x, y, z), rng.randf_range(8, 16))
	for i in 32:
		var at := Vector3(rng.randf_range(-380, 380), rng.randf_range(-45, -20), rng.randf_range(-780, 120))
		var mesh := SphereMesh.new()
		mesh.radius = rng.randf_range(13, 30)
		mesh.height = mesh.radius * 0.65
		mesh.radial_segments = 7
		mesh.rings = 4
		_mesh(mesh, at, Color("dbe7df"))

func _beacon(at: Vector3, height: float) -> void:
	_cone(at + Vector3(8, height * 0.5, 5), 1.1, 0.7, height, Color("c7bd99"))
	var gem := PrismMesh.new()
	gem.size = Vector3(4, 7, 4)
	var tip := _mesh(gem, at + Vector3(8, height + 2, 5), Color("f7cc78"))
	tip.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var beam := _cone(at + Vector3(8, height + 24, 5), 0.32, 0.32, 40, Color("f7cc78"))
	beam.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	ThemeDB.fallback_font = font
	var title_panel := _panel(Vector2(28, 26), Vector2(365, 112), Color(0.97, 0.96, 0.89, 0.94))
	_label("SKYGLIDE   /   TWO ISLAND WORLDS", Vector2(22, 13), 13, Color("687f80"), title_panel)
	_label("逐 风", Vector2(20, 30), 36, INK, title_panel)
	equipment_label = _label("", Vector2(22, 82), 14, INK, title_panel)
	var route_panel := _panel(Vector2(28, 151), Vector2(365, 153), Color(0.10, 0.20, 0.24, 0.92))
	objective = _label("", Vector2(20, 14), 19, CREAM, route_panel)
	inventory_label = _label("", Vector2(20, 51), 16, Color("c9dfca"), route_panel)
	_label("M 航图   ·   E 搜集 / 制作 / 点亮信标", Vector2(20, 116), 14, Color("b5d4cf"), route_panel)
	var telemetry := _panel(Vector2(1190, 26), Vector2(222, 192), Color(0.10, 0.20, 0.24, 0.9))
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
	var footer := _panel(Vector2(28, 790), Vector2(1384, 82), Color(0.10, 0.20, 0.24, 0.93))
	hint = _label("", Vector2(22, 10), 18, CREAM, footer)
	_label("鼠标转镜头 · WASD / 空格跳   |   贴墙按住左键攀爬 · 空格蹬离   |   F 展收伞 · 空中 AD / WS 控伞 · 右键减速 · E 互动 · R 回主岛", Vector2(22, 48), 14, Color("bdd0ca"), footer)
	var reticle := _label("＋", Vector2(710, 435), 22, CREAM, hud)
	reticle.add_theme_color_override("font_shadow_color", INK)
	reticle.add_theme_constant_override("shadow_offset_x", 1)
	reticle.add_theme_constant_override("shadow_offset_y", 1)
	map_view = preload("res://flight_map.gd").new()
	map_view.world = self
	hud.add_child(map_view)

func _update_ui() -> void:
	speed_label.text = "%02d  m/s" % roundi(player.airspeed if player.flying else 0)
	altitude_label.text = "高度  %03d m" % maxi(0, roundi(player.position.y))
	speed_bar.value = player.airspeed if player.flying else 0
	equipment_label.text = "已装备：轻木远行翼 / II" if upgraded else "已装备：木皮滑翔翼 / I"
	objective.text = "02  石柱群岛 · 点亮信标" if upgraded else "01  草海群岛 · 制作远行翼"
	inventory_label.text = "风晶 %d   ·   最远信标 176 m" % inventory.crystal if upgraded else "轻木 %d / 3    翼膜 %d / 2\n图纸 %d / 1" % [inventory.wood, inventory.membrane, inventory.plan]
	if finished:
		hint.text = "两关完成！你已经从木皮滑翔翼升级到远行翼，抵达并点亮了高空信标。"
		state_label.text = "● 信标已点亮"
	elif player.disabled:
		hint.text = "坠入云海，正在返回主岛。材料和装备保留。"
		state_label.text = "● 失去平衡"
	elif player.climber.active:
		hint.text = "攀爬中：按住左键，W S 上下、A D 横移；空格蹬离；F 开伞滑翔。到边缘会翻上平台。"
		state_label.text = "● 攀爬 / 翻越"
	elif toast_timer > 0:
		hint.text = toast
		state_label.text = "● 飞行中" if player.flying else "● 已落地"
	elif not player.flying:
		var target := interaction_target()
		if not player.is_on_floor():
			hint.text = "人物在空中：按 F 展开滑翔伞；触地后自动站稳，不会因为落地而重开。"
			state_label.text = "● 跳跃 / 下落"
		elif not target.is_empty():
			var distance := interaction_distance(target)
			hint.text = target.label + "  ·  起飞请走左侧坡道上高台，助跑、空格跳出、F 展伞。" if distance <= 4.5 else "靠近目标（%.0f 米）后按 E / 左键即可，无需跳上桌或箱子。" % distance
			state_label.text = "● 徒步探索"
		else:
			hint.text = "F 只展开或收起伞，不提供推力。沿坡道上高台，W 助跑、空格跳出，靠下落加速。" if not player.canopy_open else "伞已展开，站立不会起飞。W 助跑、空格跳出高处，速度来自跑动和下落。"
			state_label.text = "● 徒步探索"
	elif not upgraded and player.position.z < -215 and player.position.z > -380:
		hint.text = "前方海峡很长。先回营地制作阻力更低、滑翔比更好的远行翼，再规划远渡。"
		state_label.text = "● 需要远行翼"
	elif player.wind_velocity.y > 0.5:
		hint.text = "借风爬升：空格减速、转向盘旋。风道顶部升力逐渐减弱；高度够了就飞向下一岛。"
		state_label.text = "↑ 上升气流"
	else:
		hint.text = "远行翼已就绪：M 找信标，经高空风道升到约 165 m，再向石柱群岛远渡。" if upgraded else "对准岛面降落后可继续徒步。伞的开合只由 F 控制；走到材料旁按 E 采集。"
		state_label.text = "● 自由滑翔"

func _smoke_test() -> void:
	await preload("res://regression.gd").new().run(self)
