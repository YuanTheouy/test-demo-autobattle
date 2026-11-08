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

func key(code: Key, value: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = value
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code, true)
	key(code, false)

func grab(value: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = value
	Input.parse_input_event(event)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func box(at: Vector3, size: Vector3, angle: float = 0) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = at
	body.rotation.x = angle
	world.add_child(body)

func set_canopy(value: bool) -> void:
	if pilot.canopy_open != value:
		pilot.toggle_paraglider()

func _run() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	pilot = world.player
	await ticks(20)
	check(world.wind_volumes.size() == world.thermals.size(), "Every updraft needs a visible volume")
	for i in world.thermals.size():
		var volume: MeshInstance3D = world.wind_volumes[i]
		var thermal: Dictionary = world.thermals[i]
		check(volume.mesh is CylinderMesh and is_equal_approx(volume.mesh.top_radius, thermal.radius) and is_equal_approx(volume.mesh.height, float(thermal.top) - float(thermal.bottom)), "Wind cylinder must match actual wind bounds")
		check(volume.material_override is ShaderMaterial and volume.get_child_count() == 0, "Wind volume must be translucent decoration, never a collider")
	# Exercise the actual 20 m tower, not only a simplified wall fixture.
	pilot.reset_at(Vector3(14, 65, 9.65))
	await ticks(25)
	grab(true)
	key(KEY_W, true)
	var main_tower_top := false
	for i in 650:
		await physics_frame
		if not pilot.climber.active and pilot.is_on_floor() and pilot.position.y > 85:
			main_tower_top = true
			break
	key(KEY_W, false)
	grab(false)
	await ticks(8)
	check(main_tower_top, "Actual main-island tower must be climbable and allow standing on top: %s" % pilot.position)
	tap(KEY_R)
	await ticks(20)
	# Isolated fixture space. Main scene and input dispatch remain active.
	world.set_physics_process(false)
	pilot.wind_velocity = Vector3.ZERO
	pilot.control_override = true
	var index := 0
	for degrees in [15, 30, 40, -30]:
		var angle := deg_to_rad(float(degrees))
		var x := -180 + index * 28.0
		box(Vector3(x, 30 - 0.5 * cos(angle), 500 - 0.5 * sin(angle)), Vector3(12, 1, 40), angle)
		for opened in [false, true]:
			pilot.test_walk = 0
			pilot.reset_at(Vector3(x, 32, 500))
			set_canopy(false)
			await ticks(50)
			set_canopy(opened)
			pilot.test_walk = 1
			await ticks(20)
			check(pilot.is_on_floor(), "Fixture must stand on %d degree slope" % degrees)
			var start: Vector3 = pilot.position
			var support: Vector3 = pilot.get_floor_normal()
			pilot.jump()
			await ticks(12)
			var separation := (pilot.position - start).dot(support)
			check(separation > 0.6 and not pilot.is_on_floor(), "Running slope jump must clear support: %d degrees open=%s separation=%.3f" % [degrees, opened, separation])
			check(pilot.canopy_open == opened, "Slope jump must not change canopy state")
		index += 1
	pilot.test_walk = 0
	pilot.control_override = false
	box(Vector3(100, -0.5, 500), Vector3(30, 1, 30))
	box(Vector3(100, 3, 500), Vector3(8, 6, 4))
	pilot.reset_at(Vector3(100, 1, 502.65))
	set_canopy(false)
	await ticks(25)
	grab(true)
	key(KEY_W, true)
	var climbed := false
	var mantled := false
	for i in 260:
		await physics_frame
		climbed = climbed or pilot.climber.active
		if climbed and not pilot.climber.active and pilot.is_on_floor() and pilot.position.y > 6.7:
			mantled = true
			break
	key(KEY_W, false)
	grab(false)
	await ticks(8)
	check(climbed and mantled, "Holding LMB and W must climb the wall and mantle onto its top: %s active=%s phase=%d" % [pilot.position, pilot.climber.active, pilot.climber.mantle_phase])
	check(not pilot.canopy_open, "Climbing and mantling cannot open the canopy")
	key(KEY_W, true)
	await ticks(10)
	tap(KEY_SPACE)
	await ticks(8)
	key(KEY_W, false)
	var momentum: Vector3 = pilot.velocity
	tap(KEY_F)
	check(pilot.velocity.distance_to(momentum) < 0.001, "Deploying after a climb must preserve momentum")
	await ticks(20)
	check(pilot.canopy_open and pilot.flying and pilot.position.z < 498, "Climb, stand, run, jump and deploy must actually leave the top")
	# Grab a wall again, then deliberately push off and deploy.
	pilot.reset_at(Vector3(100, 1, 502.65))
	set_canopy(false)
	await ticks(25)
	grab(true)
	key(KEY_W, true)
	await ticks(65)
	key(KEY_W, false)
	check(pilot.climber.active and pilot.position.y > 2.5, "Second wall grab must gain real height")
	tap(KEY_SPACE)
	grab(false)
	await ticks(2)
	check(not pilot.climber.active and pilot.velocity.z > 1, "Space must push away from the wall")
	tap(KEY_F)
	await ticks(5)
	check(pilot.flying and pilot.canopy_open, "Wall jump must allow F deployment")
	# Both manual return and death return to the main island, retaining inventory.
	world.set_physics_process(true)
	pilot.reset_at(Vector3(48, 63, -94))
	await ticks(25)
	world._on_land()
	check(world.current_island == "membrane", "Respawn fixture must first visit another island")
	world.inventory.wood = 3
	var before_open: bool = pilot.canopy_open
	tap(KEY_R)
	await ticks(2)
	check(pilot.position.distance_to(world.MAIN_SPAWN) < 0.2 and world.current_island == "camp" and world.inventory.wood == 3, "R must return to main island with materials")
	check(pilot.canopy_open == before_open, "Respawn must preserve F-controlled canopy state")
	pilot.position = Vector3(0, -19, 500)
	await ticks(110)
	check(pilot.position.distance_to(world.MAIN_SPAWN) < 0.3 and not pilot.disabled and world.inventory.wood == 3, "Death must also return to main island")
	if not failed:
		print("TRAVERSAL PASS: uphill/downhill jumps with open/closed canopy, visible wind cylinders, LMB climbing, mantle, wall jump, run/jump/deploy, main-island respawn")
	quit(1 if failed else 0)
