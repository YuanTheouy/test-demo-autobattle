extends CharacterBody3D

const Aero = preload("res://aerodynamics.gd")
const RUN_SPEED := 9.0
const JUMP_SPEED := 5.5

signal crashed
signal landed

var airspeed := 0.0
var heading := 0.0
var pitch := -0.08
var bank := 0.0
var flying := false
var canopy_open := false
var disabled := false
var wind_velocity := Vector3.ZERO
var jump_buffer := 0.0
var ground_grace := 0.0
var jumped := false
var visual: Node3D
var canopy: Node3D
var camera: Camera3D
var spawn_point := Vector3(0, 66, -2)
var control_override := false
var test_pitch := 0.0
var test_turn := 0.0
var test_brake := false
var test_walk := 0.0
var test_strafe := 0.0
var equipment_level := 0
var render_heading := 0.0
var ground_view_heading := 0.0
var sail: MeshInstance3D
var left_leg: Node3D
var right_leg: Node3D
var step_phase := 0.0
var last_impact := 0.0
var first_person := false
var view_pitch := -0.18
var mouse_look_enabled := true
var camera_boom := 7.0

func _ready() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	collision.shape = capsule
	add_child(collision)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(42)
	visual = Node3D.new()
	add_child(visual)
	_build_person()
	_build_canopy()
	camera = Camera3D.new()
	camera.fov = 70
	camera.near = 0.3
	camera.far = 1400
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	reset_at(spawn_point)

func reset_at(point: Vector3) -> void:
	position = point
	spawn_point = point
	heading = 0
	ground_view_heading = 0
	view_pitch = -0.18
	camera_boom = 7.0
	pitch = Aero.TRIM
	bank = 0
	airspeed = 0
	velocity = Vector3.ZERO
	jump_buffer = 0
	ground_grace = 0
	flying = false
	disabled = false
	canopy.visible = canopy_open
	render_heading = heading
	reset_physics_interpolation()
	camera.position = position + Vector3(0, 3.4, 7)
	camera.look_at(position + Vector3(0, 0.5, -3))

func jump() -> void:
	if not disabled:
		jump_buffer = 0.12

func toggle_paraglider() -> void:
	if disabled:
		return
	if canopy_open:
		flying = false
		canopy_open = false
		canopy.visible = false
		if control_override:
			ground_view_heading = heading
	else:
		launch()

func launch() -> void:
	if disabled or canopy_open:
		return
	canopy_open = true
	canopy.visible = true
	if not is_on_floor():
		_begin_glide()

func _begin_glide() -> void:
	# Deploying changes no velocity component. Running/jumping/falling supply energy.
	flying = true
	airspeed = (velocity - wind_velocity).length()
	heading = atan2(velocity.x, -velocity.z) if Vector2(velocity.x, velocity.z).length_squared() > 0.01 else heading
	pitch = Aero.TRIM

func set_equipment(level: int) -> void:
	equipment_level = level
	canopy.scale.x = 1.18 if level > 0 else 1.0
	sail.material_override.albedo_color = Color("73cbbc") if level > 0 else Color("f2bf67")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and mouse_look_enabled and not control_override:
		var motion: Vector2 = event.screen_relative if not event.screen_relative.is_zero_approx() else event.relative
		ground_view_heading += motion.x * 0.0025
		view_pitch = clampf(view_pitch - motion.y * 0.0025, -1.3, 1.3)

func _process(delta: float) -> void:
	visual.visible = not first_person
	canopy.visible = canopy_open
	var walking_speed := Vector2(velocity.x, velocity.z).length() if not flying else 0.0
	step_phase += delta * walking_speed * 1.6
	var stride := sin(step_phase) * 0.65 * clampf(walking_speed / 9, 0, 1)
	left_leg.rotation.x = stride
	right_leg.rotation.x = -stride
	_update_camera(delta)

func _physics_process(delta: float) -> void:
	if disabled:
		return
	ground_grace = 0.10 if is_on_floor() else maxf(0, ground_grace - delta)
	jumped = jump_buffer > 0 and ground_grace > 0
	jump_buffer = maxf(0, jump_buffer - delta)
	if jumped:
		velocity.y = JUMP_SPEED
		jump_buffer = 0
		ground_grace = 0
	if flying:
		_glide(delta)
	else:
		_walk(delta)
	airspeed = (velocity - wind_velocity).length()
	if position.y < -18 or position.length() > 1250:
		_fail()

func _walk(delta: float) -> void:
	var forward_input := float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
	var side_input := float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	if control_override:
		ground_view_heading += test_turn * delta * 1.8
		forward_input = test_walk
		side_input = test_strafe
		if absf(test_walk) + absf(test_strafe) < 0.01:
			heading = ground_view_heading
	var forward := Vector3(sin(ground_view_heading), 0, -cos(ground_view_heading))
	var right := Vector3(cos(ground_view_heading), 0, sin(ground_view_heading))
	var direction := (forward * forward_input + right * side_input).limit_length()
	var was_on_floor := is_on_floor()
	if was_on_floor and not jumped:
		var normal := get_floor_normal()
		var tangent := direction.slide(normal).normalized() * direction.length()
		var ground_velocity := velocity.slide(normal)
		ground_velocity = ground_velocity.move_toward(tangent * RUN_SPEED, delta * 45)
		velocity = ground_velocity + Vector3.DOWN * Aero.GRAVITY * delta
		if _try_step(Vector3(tangent.x, 0, tangent.z) * RUN_SPEED * delta):
			velocity.x = tangent.x * RUN_SPEED
			velocity.z = tangent.z * RUN_SPEED
	else:
		# Closed canopy: ballistic motion plus body drag, with no airborne motor.
		var relative := velocity - wind_velocity
		velocity += (Vector3.DOWN * Aero.GRAVITY - relative * relative.length() * 0.003) * delta
	if direction.length_squared() > 0.01 and was_on_floor:
		heading = lerp_angle(heading, atan2(direction.x, -direction.z), minf(1, delta * 16))
	move_and_slide()
	if was_on_floor and not jumped and not is_on_floor():
		apply_floor_snap()
	visual.rotation = Vector3(0, -heading, 0)
	canopy.rotation = Vector3(0, -heading, 0)
	if is_on_floor() and not was_on_floor:
		landed.emit()
	if canopy_open and not is_on_floor() and (jumped or ground_grace <= 0):
		_begin_glide()

func _try_step(horizontal_motion: Vector3) -> bool:
	if horizontal_motion.length_squared() < 0.000001:
		return false
	var wall := KinematicCollision3D.new()
	if not test_move(global_transform, horizontal_motion, wall) or wall.get_normal().y > 0.5:
		return false
	var raised := global_transform
	if test_move(raised, Vector3.UP * 0.32):
		return false
	raised.origin.y += 0.32
	if test_move(raised, horizontal_motion):
		return false
	raised.origin += horizontal_motion
	var support := KinematicCollision3D.new()
	if test_move(raised, Vector3.DOWN * 0.38, support) and support.get_normal().y > 0.72:
		var height := raised.origin.y + support.get_travel().y - global_position.y
		if height > 0.005 and height <= 0.32:
			global_position.y += height + 0.005
			return true
	return false

func _glide(delta: float) -> void:
	var pitch_input := test_pitch if control_override else float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var turn_input := test_turn if control_override else float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var brake := float(test_brake if control_override else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	# Camera look never commands the wing. Input changes incidence and bank only.
	pitch = move_toward(pitch, Aero.TRIM + pitch_input * 0.22 + brake * 0.04, delta * 0.9)
	bank = move_toward(bank, turn_input * 0.60, delta * 1.6)
	velocity = Aero.integrate(velocity, wind_velocity, heading, pitch, bank, brake, equipment_level, delta)
	# The wing follows its actual horizontal airflow, rather than rotating velocity.
	var horizontal := Vector2(velocity.x - wind_velocity.x, velocity.z - wind_velocity.z)
	if horizontal.length_squared() > 0.0001:
		heading = lerp_angle(heading, atan2(horizontal.x, -horizontal.y), 1 - exp(-8.0 * delta))
	last_impact = velocity.length()
	move_and_slide()
	visual.rotation = Vector3(0, -heading, -bank * 0.20)
	canopy.rotation = Vector3(pitch, -heading, -bank)
	if is_on_floor():
		_touch_down()

func _touch_down() -> void:
	flying = false
	bank = 0
	# Collision resolves the normal; ground friction dissipates tangential momentum.
	velocity = velocity.slide(get_floor_normal())
	canopy.rotation = Vector3(0, -heading, 0)
	visual.rotation = Vector3(0, -heading, 0)
	landed.emit()

func _fail() -> void:
	if not disabled:
		disabled = true
		crashed.emit()

func _update_camera(delta: float) -> void:
	var at := get_global_transform_interpolated().origin
	if first_person:
		camera.position = at + Vector3.UP * 0.65
		camera.rotation = Vector3(view_pitch, -ground_view_heading, 0)
		camera.fov = 70
		return
	render_heading = ground_view_heading
	var distance := 8.5
	camera_boom = lerpf(camera_boom, distance, 1 - exp(-5 * delta))
	var orbit := Vector3(-sin(render_heading) * cos(view_pitch), -sin(view_pitch), cos(render_heading) * cos(view_pitch))
	var target := at + Vector3.UP * 1.0
	var desired := target + orbit * camera_boom
	var query := PhysicsRayQueryParameters3D.create(target, desired)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	camera.position = hit.position + hit.normal * 0.25 if not hit.is_empty() else desired
	camera.look_at(target)
	camera.fov = 70

func _mesh(mesh: Mesh, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance

func _part(size: Vector3, at: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, color, at, parent)

func _build_person() -> void:
	_part(Vector3(0.65, 0.72, 0.40), Vector3(0, 0.1, 0), Color("315d64"), visual)
	_part(Vector3(0.44, 0.57, 0.24), Vector3(0, 0.12, 0.30), Color("9b7551"), visual)
	var head := SphereMesh.new()
	head.radius = 0.27
	head.height = 0.54
	head.radial_segments = 8
	head.rings = 4
	_mesh(head, Color("dfaa83"), Vector3(0, 0.70, 0), visual)
	_part(Vector3(0.52, 0.16, 0.49), Vector3(0, 0.91, 0.02), Color("594739"), visual)
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.18, -0.27, 0)
		visual.add_child(leg)
		_part(Vector3(0.24, 0.54, 0.25), Vector3(0, -0.27, 0), Color("504c42"), leg)
		_part(Vector3(0.26, 0.16, 0.41), Vector3(0, -0.53, -0.06), Color("674b39"), leg)
		var arm := _part(Vector3(0.18, 0.64, 0.22), Vector3(side * 0.44, 0.05, 0), Color("dfaa83"), visual)
		arm.rotation.z = side * 0.10
		if side == -1:
			left_leg = leg
		else:
			right_leg = leg

func _build_canopy() -> void:
	canopy = Node3D.new()
	add_child(canopy)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in 10:
		var x1 := -5.0 + i
		var x2 := x1 + 1
		var y1 := 4.5 - x1 * x1 * 0.045
		var y2 := 4.5 - x2 * x2 * 0.045
		var points := [Vector3(x1, y1, -1.0), Vector3(x2, y2, -1.0), Vector3(x1, y1 - 0.35, 1.4), Vector3(x2, y2, -1.0), Vector3(x2, y2 - 0.35, 1.4), Vector3(x1, y1 - 0.35, 1.4)]
		for point in points:
			vertices.append(point)
			normals.append(Vector3.UP)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	sail = _mesh(mesh, Color("f2bf67"), Vector3.ZERO, canopy)
	sail.material_override.cull_mode = BaseMaterial3D.CULL_DISABLED
	sail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1, 1]:
		for z in [-0.8, 1.1]:
			var start := Vector3(side * 0.32, 0.2, 0)
			var end := Vector3(side * 3.7, 3.75, z)
			var cord := CylinderMesh.new()
			cord.top_radius = 0.018
			cord.bottom_radius = 0.018
			cord.height = start.distance_to(end)
			cord.radial_segments = 4
			var line := _mesh(cord, Color("6d6552"), (start + end) * 0.5, canopy)
			line.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
