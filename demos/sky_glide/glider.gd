extends CharacterBody3D

signal crashed
signal landed

var airspeed := 22.0
var heading := 0.0
var pitch := -0.08
var bank := 0.0
var flying := false
var disabled := false
var lift := 0.0
var visual: Node3D
var camera: Camera3D
var spawn_point := Vector3(0, 66, -2)
var control_override := false
var test_pitch := 0.0
var test_turn := 0.0
var test_brake := false
var launch_lift := 0.0

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	shape.shape = sphere
	add_child(shape)
	visual = Node3D.new()
	add_child(visual)
	_build_glider()
	camera = Camera3D.new()
	camera.fov = 72
	camera.far = 1800
	camera.top_level = true
	add_child(camera)
	reset_at(spawn_point)

func reset_at(point: Vector3) -> void:
	position = point
	spawn_point = point
	heading = 0
	pitch = -0.08
	bank = 0
	airspeed = 22
	velocity = Vector3.ZERO
	launch_lift = 0
	flying = false
	disabled = false
	camera.position = position + Vector3(0, 4, 12)
	camera.look_at(position + Vector3(0, 0, -12))

func launch() -> void:
	if not disabled and not flying:
		flying = true
		launch_lift = 6
		pitch = -0.08

func _physics_process(delta: float) -> void:
	if disabled:
		_update_camera(delta)
		return
	if not flying:
		_update_camera(delta)
		return
	var pitch_input := test_pitch if control_override else float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var turn_input := test_turn if control_override else float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var braking := test_brake if control_override else Input.is_physical_key_pressed(KEY_SPACE)
	pitch = clampf(pitch + pitch_input * delta * 0.72, -1.0, 0.67)
	bank = lerpf(bank, -turn_input * 0.65, 4.5 * delta)
	heading += turn_input * delta * 0.85 * clampf(25.0 / airspeed, 0.55, 1.35)
	airspeed = evolve_speed(airspeed, pitch, braking, delta)
	var forward := Vector3(sin(heading) * cos(pitch), sin(pitch), -cos(heading) * cos(pitch))
	var stall_sink := maxf(0, 15 - airspeed) * 0.85
	velocity = forward * airspeed + Vector3.UP * (lift + launch_lift - 1.2 - stall_sink)
	launch_lift = maxf(0, launch_lift - delta * 5)
	if braking:
		velocity.y -= 1.6
	move_and_slide()
	visual.rotation = Vector3(pitch, -heading, bank)
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		if hit.get_normal().y > 0.65 and airspeed < 32 and pitch > -0.30:
			flying = false
			velocity = Vector3.ZERO
			landed.emit()
			break
		else:
			_fail()
			break
	if position.y < -18 or position.length() > 950:
		_fail()
	_update_camera(delta)

static func evolve_speed(speed: float, nose_pitch: float, braking: bool, delta: float) -> float:
	var acceleration := -sin(nose_pitch) * 21.0 - 0.012 * (speed * speed - 324)
	if braking:
		acceleration -= 16
	return clampf(speed + acceleration * delta, 8, 64)

func _fail() -> void:
	if not disabled:
		disabled = true
		crashed.emit()

func _update_camera(delta: float) -> void:
	var behind := Vector3(-sin(heading), 0, cos(heading))
	var desired := position + behind * (11 + airspeed * 0.055) + Vector3.UP * 4.0
	camera.position = camera.position.lerp(desired, 1 - exp(-5 * delta))
	var look_point := position + Vector3(sin(heading), 0, -cos(heading)) * 11 + Vector3.UP * 0.8
	camera.look_at(look_point)
	camera.fov = lerpf(camera.fov, 70 + maxf(0, airspeed - 20) * 0.48, delta * 2)

func _mesh(mesh: Mesh, color: Color, at: Vector3, scale_value: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	instance.material_override = material
	instance.position = at
	instance.scale = scale_value
	visual.add_child(instance)
	return instance

func _build_glider() -> void:
	var wing := ArrayMesh.new()
	var points := PackedVector3Array([
		Vector3(-4.6, 0.4, 0.9), Vector3(0, 0.65, -1.4), Vector3(-0.4, 0.25, 1.1),
		Vector3(0.4, 0.25, 1.1), Vector3(0, 0.65, -1.4), Vector3(4.6, 0.4, 0.9)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	wing.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var sail := _mesh(wing, Color("f2bf67"), Vector3.ZERO)
	sail.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bar := BoxMesh.new()
	bar.size = Vector3(9, 0.10, 0.10)
	_mesh(bar, Color("67483e"), Vector3(0, 0.38, 0.8))
	var keel := BoxMesh.new()
	keel.size = Vector3(0.12, 0.12, 3)
	_mesh(keel, Color("67483e"), Vector3(0, 0.4, 0))
	var body := CapsuleMesh.new()
	body.radius = 0.25
	body.height = 1.15
	_mesh(body, Color("284f59"), Vector3(0, -0.35, 0)).rotation.x = PI / 2
	var head := SphereMesh.new()
	head.radius = 0.28
	head.height = 0.56
	head.radial_segments = 8
	head.rings = 4
	_mesh(head, Color("df926b"), Vector3(0, -0.25, -0.7))
