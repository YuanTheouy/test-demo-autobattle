extends CharacterBody3D
## Adapted from Andicraft/stairs-character, commit 5403d02f6b64b49a1d1bd7af11dd51a6edfc9e6c.
## Copyright 2023 Andrea Jörgensen; MIT, see stairs-character.LICENSE.
## Local changes: explicit tick lifecycle, jump exclusion, walkable down-snap,
## support reporting and bounded rise. The upstream up/forward/down shape sweep
## replaces the demo's previous step approximation.

@export var step_height := 0.35
var grounded := false
var support_normal := Vector3.UP
var desired_velocity := Vector3.ZERO
var stepped_height := 0.0
var _collider_margin := 0.001

func is_supported() -> bool:
	return grounded or is_on_floor()

func reset_support() -> void:
	grounded = false
	support_normal = Vector3.UP
	stepped_height = 0

func move_and_stair_step(allow_steps: bool) -> void:
	var was_grounded := is_supported()
	stepped_height = 0
	if allow_steps and was_grounded:
		stair_step_up()
	move_and_slide()
	grounded = is_on_floor()
	if grounded:
		support_normal = get_floor_normal()
	if allow_steps and was_grounded:
		stair_step_down()

func stair_step_down() -> void:
	if is_on_floor():
		return
	var result := PhysicsTestMotionResult3D.new()
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = global_transform
	parameters.motion = Vector3.DOWN * step_height
	parameters.margin = _collider_margin
	if not PhysicsServer3D.body_test_motion(get_rid(), parameters, result):
		return
	var normal := result.get_collision_normal(0)
	if normal.angle_to(Vector3.UP) > floor_max_angle:
		return
	global_transform = global_transform.translated(result.get_travel())
	stepped_height += result.get_travel().y
	apply_floor_snap()
	grounded = true
	support_normal = normal
	velocity = velocity.slide(normal)

func stair_step_up() -> void:
	var horizontal_velocity := velocity * Vector3(1, 0, 1)
	var testing_velocity := horizontal_velocity if not horizontal_velocity.is_zero_approx() else desired_velocity
	if testing_velocity.is_zero_approx():
		return
	var result := PhysicsTestMotionResult3D.new()
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.margin = _collider_margin
	var motion_transform := global_transform
	parameters.from = motion_transform
	parameters.motion = testing_velocity * get_physics_process_delta_time()
	if not PhysicsServer3D.body_test_motion(get_rid(), parameters, result):
		return
	# Slopes are handled by move_and_slide + floor_constant_speed, not stair lifts.
	if result.get_collision_normal(0).angle_to(Vector3.UP) <= floor_max_angle:
		return
	var remainder := result.get_remainder()
	motion_transform = motion_transform.translated(result.get_travel())
	parameters.from = motion_transform
	parameters.motion = Vector3.UP * step_height
	PhysicsServer3D.body_test_motion(get_rid(), parameters, result)
	motion_transform = motion_transform.translated(result.get_travel())
	var raised_distance := result.get_travel().y
	if raised_distance <= 0:
		return
	parameters.from = motion_transform
	parameters.motion = remainder
	PhysicsServer3D.body_test_motion(get_rid(), parameters, result)
	motion_transform = motion_transform.translated(result.get_travel())
	parameters.from = motion_transform
	parameters.motion = Vector3.DOWN * raised_distance
	if not PhysicsServer3D.body_test_motion(get_rid(), parameters, result):
		return
	motion_transform = motion_transform.translated(result.get_travel())
	var normal := result.get_collision_normal(0)
	if normal.angle_to(Vector3.UP) > floor_max_angle:
		return
	var rise := motion_transform.origin.y - global_position.y
	if rise <= 0.001 or rise > step_height + _collider_margin:
		return
	global_position.y = motion_transform.origin.y
	stepped_height = rise
	support_normal = normal
