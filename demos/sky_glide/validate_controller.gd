extends SceneTree

var world: Node3D
var pilot: CharacterBody3D
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func key(code: Key, value: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = value
	Input.parse_input_event(event)

func box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = at
	world.add_child(body)

func _run() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	pilot = world.player
	await ticks(20)
	check(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "Use the explicitly selected Jolt backend")
	# Render and collision must share all terrain triangles. Probe real physics,
	# including slopes: a decorative bumpy surface over a flat collider would fail.
	var rng := RandomNumberGenerator.new()
	rng.seed = 32711
	for island in world.islands:
		var terrain = world.terrains[island.id]
		check(terrain.max_height > 3.0, "Each playable island must have substantial relief")
		var shape: ConcavePolygonShape3D = terrain.get_child(0).get_child(0).shape
		check(shape.get_faces() == terrain.faces, "Terrain visuals and collider must use identical triangles")
		for i in 24:
			var angle := rng.randf() * TAU
			var radius := rng.randf_range(0.35, 0.85) * float(island.radius)
			var at: Vector3 = island.pos + Vector3(cos(angle), 0, sin(angle)) * radius
			var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 12, at + Vector3.DOWN * 4)
			query.exclude = [pilot.get_rid()]
			var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.collider == terrain.get_child(0):
				check(absf(hit.position.y - terrain.height_at(at.x, at.z)) < 0.02, "Terrain query must match actual collision height")
	# Cross a real main-island hillside, not a flat test slab.
	var hillside: Node3D = world.terrains.camp
	pilot.reset_at(Vector3(-20, hillside.height_at(-20, 35) + 1, 35))
	await ticks(20)
	var start_y: float = pilot.position.y
	var peak := start_y
	var unsupported := 0
	pilot.toggle_paraglider()
	key(KEY_W, true)
	for i in 110:
		await physics_frame
		peak = maxf(peak, pilot.position.y)
		if not pilot.is_supported():
			unsupported += 1
	key(KEY_W, false)
	await ticks(15)
	check(pilot.position.z < 22 and peak > start_y + 1.5, "Must traverse the real hillside and gain elevation: at=%s gain=%.3f" % [pilot.position, peak - start_y])
	check(unsupported == 0 and not pilot.flying and pilot.canopy_open, "Hill crests cannot launch an open canopy: detached=%d" % unsupported)
	print("HILLSIDE gain=%.2fm detached=%d" % [peak - start_y, unsupported])
	# Isolated staircase: 10 consecutive 30 cm steps in both directions.
	world.set_physics_process(false)
	pilot.wind_velocity = Vector3.ZERO
	box(Vector3(100, -0.5, 500), Vector3(50, 1, 50))
	for i in 10:
		box(Vector3(100, (i + 1) * 0.15, 504 - i * 1.2), Vector3(6, (i + 1) * 0.3, 1.2))
	box(Vector3(100, 1.5, 490), Vector3(6, 3, 6))
	pilot.reset_at(Vector3(100, 1, 507))
	await ticks(20)
	key(KEY_W, true)
	unsupported = 0
	var camera_step := 0.0
	var previous_y: float = pilot.camera.position.y
	for i in 110:
		await physics_frame
		if not pilot.is_supported():
			unsupported += 1
		camera_step = maxf(camera_step, absf(pilot.camera.position.y - previous_y))
		previous_y = pilot.camera.position.y
	key(KEY_W, false)
	await ticks(15)
	check(pilot.position.z < 493 and pilot.position.y > 3.8, "Must climb ten steps without jumping: %s" % pilot.position)
	check(unsupported == 0 and not pilot.flying, "Consecutive stair contacts must remain grounded")
	check(camera_step < 0.18, "30 cm steps should not kick the camera upward in one frame: %.3f" % camera_step)
	key(KEY_S, true)
	await ticks(110)
	key(KEY_S, false)
	await ticks(15)
	check(pilot.position.z > 505 and pilot.position.y < 1 and not pilot.flying, "Descending consecutive stairs must stay attached and reach the floor")
	# A high ledge or insufficient headroom is not an automatic stair.
	box(Vector3(112, 0.4, 500), Vector3(5, 0.8, 3))
	pilot.reset_at(Vector3(112, 1, 504))
	await ticks(20)
	key(KEY_W, true)
	await ticks(75)
	key(KEY_W, false)
	check(pilot.position.z > 501.6 and pilot.position.y < 1.1, "An 80 cm obstacle must require a jump or climb")
	box(Vector3(88, 0.15, 500), Vector3(5, 0.3, 3))
	box(Vector3(88, 2.1, 500), Vector3(5, 0.2, 3))
	pilot.reset_at(Vector3(88, 1, 504))
	await ticks(20)
	key(KEY_W, true)
	await ticks(75)
	key(KEY_W, false)
	check(pilot.position.z > 501.6 and pilot.position.y < 1.1, "A low ceiling must block the step-up sweep")
	# Normal W held after takeoff is neutral; it must not become an accidental dive.
	var neutral := await flight_sample(false)
	var held_w := await flight_sample(true)
	check(neutral.distance_to(held_w) < 0.001, "Holding the takeoff W key must produce the same cruise as neutral input")
	key(KEY_D, true)
	await ticks(12)
	check(pilot.bank > 0.7, "Turn input should respond within 0.2 seconds")
	await ticks(60)
	check(pilot.heading > 0.5, "Sustained turn must actually change the trajectory")
	key(KEY_D, false)
	await ticks(14)
	check(absf(pilot.bank) < 0.001, "Releasing turn must level the canopy within 0.24 seconds")
	key(KEY_SHIFT, true)
	await ticks(15)
	check(pilot.pitch < pilot.Aero.TRIM - 0.12, "Shift deliberately commands a dive")
	key(KEY_SHIFT, false)
	await ticks(15)
	check(absf(pilot.pitch - pilot.Aero.TRIM) < 0.001, "Releasing dive restores trim")
	print("CONTROLLER camera_max_step=%.3fm turn_heading=%.2f" % [camera_step, pilot.heading])
	if not failed:
		print("CONTROLLER PASS: Jolt, matching terrain/collision, real hills, continuous stairs, ceiling/ledge limits, W cruise, responsive turn/release, deliberate dive")
	quit(1 if failed else 0)

func flight_sample(hold_w: bool) -> Vector3:
	pilot.reset_at(Vector3(250, 200, 500))
	pilot.velocity = Vector3(0, -1.71, -10.2)
	pilot._begin_glide()
	key(KEY_W, hold_w)
	await ticks(90)
	key(KEY_W, false)
	return pilot.position
