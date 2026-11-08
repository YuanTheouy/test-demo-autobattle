extends RefCounted

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func run(world: Node3D) -> void:
	for i in 20:
		await world.get_tree().physics_frame
	var pilot = world.player
	pilot.control_override = true
	var dive := 22.0
	var climb := 22.0
	var flat := 22.0
	for i in 60:
		dive = world.Glider.evolve_speed(dive, -0.5, false, 1.0 / 60)
		climb = world.Glider.evolve_speed(climb, 0.4, false, 1.0 / 60)
		flat = world.Glider.evolve_speed(flat, 0, false, 1.0 / 60)
	check(dive > 22 and climb < 22 and flat < 22, "Dive gains speed; climbing and level flight spend speed")
	check(world.Glider.evolve_speed(30, 0, true, 0.1) < world.Glider.evolve_speed(30, 0, false, 0.1), "Brake must slow down")
	check(world.Glider.evolve_speed(30, 0, false, 0.1, 1) > world.Glider.evolve_speed(30, 0, false, 0.1, 0), "Upgraded wing must have lower drag")
	var caps := 0
	for child in world.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh:
			if child.mesh.top_radius > 20 and child.mesh.cap_top and absf(child.position.y + child.mesh.height * 0.5 - 64) < 0.01:
				caps += 1
	check(caps == 1, "Camp must have exactly one visible top face, avoiding z-fighting")
	var below: float = world.sample_lift(Vector3(0, 111.99, -265), 0)
	var above: float = world.sample_lift(Vector3(0, 112.01, -265), 0)
	check(absf(below - above) < 0.01, "Thermal ceiling must be continuous")
	check(world.sample_lift(Vector3(0, 150, -265), 0) == 0, "Old wing cannot use upper wind")
	check(world.sample_lift(Vector3(0, 150, -265), 1) > 15, "Remote route must benefit from new wing")
	check(world.sample_lift(Vector3(18, 110, -529), 0) == 0, "Highland thermal cannot be entered from low altitude")
	check(world.sample_lift(Vector3(-42, 60, -68), 0) == 0, "Landing area must be sheltered")
	var standing_position: Vector3 = pilot.position
	var standing_velocity: Vector3 = pilot.velocity
	pilot.launch()
	check(pilot.velocity.distance_to(standing_velocity) < 0.001 and pilot.canopy_open and not pilot.flying, "Opening on ground must add no impulse or flight state")
	for i in 60:
		await world.get_tree().physics_frame
	check(pilot.position.distance_to(standing_position) < 0.03 and pilot.airspeed == 0, "Standing with canopy open must stay stationary")
	pilot.toggle_paraglider()
	pilot.reset_at(Vector3(48, 63, -80))
	for i in 15:
		await world.get_tree().physics_frame
	pilot.test_walk = 1
	for i in 25:
		await world.get_tree().physics_frame
	var running_velocity: Vector3 = pilot.velocity
	pilot.launch()
	check(pilot.velocity.distance_to(running_velocity) < 0.001, "Deploying while running must preserve velocity")
	pilot.jump()
	await world.get_tree().physics_frame
	check(pilot.flying and absf(pilot.airspeed - 9) < 0.1 and pilot.velocity.y < 8.5, "Run and ordinary jump supply initial airspeed without upward boost")
	pilot.test_walk = 0
	# Hold the new wing near the old hard ceiling for four seconds.
	pilot.reset_at(Vector3(0, 181, -265))
	pilot.flying = true
	pilot.canopy_open = true
	pilot.set_equipment(1)
	pilot.pitch = 0
	pilot.airspeed = 19
	pilot.velocity = Vector3.ZERO
	pilot.test_turn = 1
	pilot.reset_physics_interpolation()
	var last_velocity := 0.0
	var largest_step := 0.0
	for i in 240:
		await world.get_tree().physics_frame
		largest_step = maxf(largest_step, absf(pilot.velocity.y - last_velocity))
		last_velocity = pilot.velocity.y
	check(largest_step < 1.0 and not pilot.disabled, "Thermal top must not flip vertical velocity abruptly")
	# Releasing and holding the brake must also keep the vertical acceleration bounded.
	pilot.test_brake = true
	last_velocity = pilot.velocity.y
	for i in 30:
		await world.get_tree().physics_frame
		check(absf(pilot.velocity.y - last_velocity) < 1.0, "Braking must not subtract a fixed vertical velocity every frame")
		last_velocity = pilot.velocity.y
	pilot.test_brake = false
	pilot.test_turn = 0
	world._restart()
	# Reproduce the reported fast/steep approach to the membrane island.
	pilot.position = Vector3(48, 65, -94)
	pilot.flying = true
	pilot.pitch = -0.9
	pilot.airspeed = 55
	pilot.velocity = Vector3(0, -30, -25)
	pilot.reset_physics_interpolation()
	for i in 30:
		await world.get_tree().physics_frame
		if not pilot.flying:
			break
	check(not pilot.flying and pilot.is_on_floor() and not pilot.disabled, "Fast steep landing must become grounded, never death")
	for i in 120:
		await world.get_tree().physics_frame
	check(not pilot.disabled and pilot.is_on_floor() and world.current_island == "membrane", "Landing must remain on membrane island without automatic restart")
	check(pilot.canopy_open and pilot.canopy.visible, "Landing must preserve the open canopy until F is pressed")
	pilot.toggle_paraglider()
	# Far-away E must not collect; physically run to the object and then collect.
	pilot.reset_at(Vector3(48, 63, -80))
	for i in 15:
		await world.get_tree().physics_frame
	world._interact()
	check(world.inventory.membrane == 0, "Material must require proximity")
	var start_x: float = pilot.position.x
	pilot.test_strafe = 1
	for i in 20:
		await world.get_tree().physics_frame
	pilot.test_strafe = 0
	check(pilot.position.x > start_x + 2 and pilot.is_on_floor(), "Ground D must strafe and stay on island")
	pilot.test_walk = 1
	for i in 150:
		await world.get_tree().physics_frame
		if pilot.position.z < -92:
			break
	pilot.test_walk = 0
	for i in 5:
		await world.get_tree().physics_frame
	world._interact()
	world._interact()
	check(world.inventory.membrane == 2, "Run to membrane, press E and collect exactly once")
	var floor_y: float = pilot.position.y
	pilot.jump()
	for i in 15:
		await world.get_tree().physics_frame
	check(pilot.position.y > floor_y + 1 and not pilot.flying, "Space must jump the person without deploying the canopy")
	for i in 60:
		await world.get_tree().physics_frame
	check(pilot.is_on_floor() and not pilot.disabled, "A normal jump lands safely")
	pilot.jump()
	for i in 10:
		await world.get_tree().physics_frame
	pilot.toggle_paraglider()
	for i in 4:
		await world.get_tree().physics_frame
	check(pilot.flying and pilot.canopy.visible, "F deploys the separate canopy during a jump")
	pilot.toggle_paraglider()
	for i in 90:
		await world.get_tree().physics_frame
	check(not pilot.flying and not pilot.canopy.visible and pilot.is_on_floor() and not pilot.disabled, "F retracts canopy and the person can fall back onto the island")
	for id in ["wood", "ruins"]:
		for island in world.islands:
			if island.id == id:
				pilot.reset_at(island.pos + Vector3(0, 1, 0))
				for i in 12:
					await world.get_tree().physics_frame
				world._interact()
				world._interact()
	check(world.inventory.wood == 3 and world.inventory.membrane == 2 and world.inventory.plan == 1, "Materials collect once per island")
	pilot.reset_at(Vector3(6, 65, 23))
	for i in 12:
		await world.get_tree().physics_frame
	world._interact()
	check(world.upgraded and pilot.equipment_level == 1 and world.inventory.wood == 0, "Nearby workbench consumes materials and equips upgraded canopy")
	world._restart()
	check(world.upgraded and world.collected.size() == 3 and pilot.equipment_level == 1, "Recovery preserves equipment and collected materials")
	pilot.reset_at(Vector3(18, 177, -615))
	for i in 12:
		await world.get_tree().physics_frame
	world._interact()
	check(world.finished, "Walk up to final beacon and activate it")
	world.finished = false
	pilot.position = world.gate_positions[1] + Vector3(11, 0, 5)
	pilot.launch()
	pilot.pitch = 0
	pilot.airspeed = 36
	for i in 120:
		await world.get_tree().physics_frame
	check(not pilot.disabled and not pilot.flying and pilot.is_on_floor() and pilot.canopy_open, "Wall contact must preserve canopy state and allow landing, not kill the person")
	pilot.position = Vector3(300, -19, -300)
	await world.get_tree().physics_frame
	check(pilot.disabled, "Only falling out of the world triggers recovery")
	world._restart()
	check(not pilot.disabled and not pilot.flying and pilot.position.distance_to(world.checkpoint) < 0.1, "Void recovery returns to checkpoint")
	if not failed:
		print("SKYGLIDE REGRESSION PASS: fast steep landing, ground stability, canopy separation, WASD movement, jump, nearby E gathering, redeploy/retract, crafting, safe wall contact, void recovery, continuous thermals")
	world.get_tree().quit(1 if failed else 0)
