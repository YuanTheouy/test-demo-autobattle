extends "res://locomotion.gd"

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
var last_ground_normal := Vector3.UP
var climber: RefCounted
var canopy_fill := 0.0
var test_climb := false
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
var left_arm: Node3D
var right_arm: Node3D
var step_phase := 0.0
var last_impact := 0.0
var first_person := false
var view_pitch := -0.18
var mouse_look_enabled := true
var camera_boom := 7.0
var camera_anchor_y := 0.0
var camera_probe: SphereShape3D

func _ready() -> void:
	var collision := CollisionShape3D.new()
	collision.name = "Collider"
	var body_shape := CylinderShape3D.new()
	body_shape.radius = 0.38
	body_shape.height = 1.8
	body_shape.margin = 0.001
	collision.shape = body_shape
	add_child(collision)
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(46)
	floor_constant_speed = true
	floor_stop_on_slope = true
	safe_margin = 0.001
	max_slides = 6
	visual = Node3D.new()
	add_child(visual)
	_build_person()
	_build_canopy()
	climber = preload("res://climbing.gd").new(self)
	camera = Camera3D.new()
	camera.fov = 70
	camera.near = 0.3
	camera.far = 1400
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera_probe = SphereShape3D.new()
	camera_probe.radius = 0.3
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
	last_ground_normal = Vector3.UP
	reset_support()
	climber.reset()
	canopy_fill = 1.0 if canopy_open else 0.0
	flying = false
	disabled = false
	canopy.visible = canopy_open
	render_heading = heading
	reset_physics_interpolation()
	camera.position = position + Vector3(0, 3.4, 7)
	camera_anchor_y = position.y + 1.0
	camera.look_at(position + Vector3(0, 0.5, -3))

func jump() -> void:
	if not disabled:
		jump_buffer = 0.12

func toggle_paraglider() -> void:
	if disabled:
		return
	if climber.active:
		climber.release()
	if canopy_open:
		flying = false
		canopy_open = false
		canopy_fill = 0
		canopy.visible = false
		if control_override:
			ground_view_heading = heading
	else:
		launch()

func launch() -> void:
	if disabled or canopy_open:
		return
	canopy_open = true
	canopy_fill = 0
	canopy.visible = true
	if not is_supported():
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
	canopy.scale = Vector3((1.18 if equipment_level > 0 else 1.0) * lerpf(0.82, 1, canopy_fill), lerpf(0.65, 1, canopy_fill), lerpf(0.65, 1, canopy_fill))
	var walking_speed := Vector2(velocity.x, velocity.z).length() if not flying else 0.0
	step_phase += delta * walking_speed * 1.6
	var stride := sin(step_phase) * 0.65 * clampf(walking_speed / 9, 0, 1)
	if climber.active:
		step_phase += delta * 5
		stride = sin(step_phase) * 0.45
	left_leg.rotation.x = stride
	right_leg.rotation.x = -stride
	var arm_pose := 1.5 if climber.active else (2.4 if flying else 0.0)
	left_arm.rotation.x = lerpf(left_arm.rotation.x, arm_pose - stride, minf(1, delta * 12))
	right_arm.rotation.x = lerpf(right_arm.rotation.x, arm_pose + stride, minf(1, delta * 12))
	left_arm.position.y = lerpf(left_arm.position.y, 0.35 if climber.active or flying else 0.05, minf(1, delta * 12))
	right_arm.position.y = left_arm.position.y
	_update_camera(delta)

func _physics_process(delta: float) -> void:
	if disabled:
		return
	canopy_fill = move_toward(canopy_fill, 1.0 if canopy_open else 0.0, delta / 0.22)
	if is_supported():
		last_ground_normal = get_floor_normal() if is_on_floor() else support_normal
	ground_grace = 0.10 if is_supported() else maxf(0, ground_grace - delta)
	var climb_wish := Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
	if control_override:
		climb_wish = Vector2(test_strafe, test_walk)
	var grab := test_climb if control_override else Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if climber.tick(delta, climb_wish, grab, jump_buffer > 0):
		jump_buffer = maxf(0, jump_buffer - delta)
		airspeed = (velocity - wind_velocity).length()
		if position.y < -18:
			_fail()
		return
	jumped = jump_buffer > 0 and ground_grace > 0
	jump_buffer = maxf(0, jump_buffer - delta)
	if jumped:
		# A vertical jump retains slope momentum without kicking backward uphill.
		velocity = velocity.slide(last_ground_normal) + Vector3.UP * JUMP_SPEED
		jump_buffer = 0
		ground_grace = 0
		grounded = false
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
	var direction := camera_relative_input(Vector2(side_input, forward_input), ground_view_heading)
	var was_on_floor := is_supported()
	if was_on_floor and not jumped:
		walk_velocity(direction, RUN_SPEED, Aero.GRAVITY, delta)
	else:
		airborne_velocity(direction, wind_velocity, Aero.GRAVITY, delta)
	if direction.length_squared() > 0.01 and was_on_floor:
		heading = lerp_angle(heading, atan2(direction.x, -direction.z), minf(1, delta * 16))
	move_and_stair_step(was_on_floor and not jumped)
	visual.rotation = Vector3(0, -heading, 0)
	canopy.rotation = Vector3(0, -heading, 0)
	if is_supported() and not was_on_floor:
		landed.emit()
	if canopy_open and not is_supported() and (jumped or ground_grace <= 0):
		_begin_glide()

func _glide(delta: float) -> void:
	# W remains cruise after takeoff; diving is a deliberate Shift action.
	var pitch_input := test_pitch if control_override else float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_SHIFT))
	var turn_input := test_turn if control_override else float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var brake := float(test_brake if control_override else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	# Camera look never commands the wing. Input changes incidence and bank only.
	pitch = move_toward(pitch, Aero.TRIM + pitch_input * 0.16 + brake * 0.04, delta * 1.4)
	bank = move_toward(bank, turn_input * 0.85, delta * 4.0)
	velocity = Aero.integrate(velocity, wind_velocity, heading, pitch, bank, brake, equipment_level, delta, canopy_fill)
	# The wing follows its actual horizontal airflow, rather than rotating velocity.
	var horizontal := Vector2(velocity.x - wind_velocity.x, velocity.z - wind_velocity.z)
	if horizontal.length_squared() > 0.0001:
		heading = lerp_angle(heading, atan2(horizontal.x, -horizontal.y), 1 - exp(-8.0 * delta))
	last_impact = velocity.length()
	move_and_slide()
	grounded = is_on_floor()
	visual.rotation = Vector3(0, -heading, -bank * 0.20)
	canopy.rotation = Vector3(pitch, -heading, -bank)
	if is_on_floor():
		_touch_down()

func _touch_down() -> void:
	flying = false
	grounded = true
	support_normal = get_floor_normal()
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
	var distance := 7.0
	var orbit := Vector3(-sin(render_heading) * cos(view_pitch), -sin(view_pitch), cos(render_heading) * cos(view_pitch))
	var target := at + Vector3.UP * 1.0
	# Ground bumps/steps do not kick the camera. Mouse aim stays immediate.
	camera_anchor_y = lerpf(camera_anchor_y, target.y, 1 - exp(-14 * delta)) if is_supported() else target.y
	target.y = camera_anchor_y
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = camera_probe
	query.transform = Transform3D(Basis.IDENTITY, target)
	query.motion = orbit * distance
	query.exclude = [get_rid()]
	var sweep := get_world_3d().direct_space_state.cast_motion(query)
	var clear_distance := maxf(0.2, distance * sweep[0] - 0.08)
	camera_boom = minf(camera_boom, clear_distance)
	camera_boom = lerpf(camera_boom, clear_distance, 1 - exp(-8 * delta))
	camera.position = target + orbit * camera_boom
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
			left_arm = arm
		else:
			right_leg = leg
			right_arm = arm

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
