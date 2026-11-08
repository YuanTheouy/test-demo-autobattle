extends RefCounted

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func run(world: Node3D) -> void:
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
	pilot.launch()
	pilot.pitch = -0.4
	var start: Vector3 = pilot.position
	for i in 75:
		await world.get_tree().physics_frame
	check(pilot.position.z < start.z - 5 and pilot.position.y < start.y and not pilot.disabled, "Actual takeoff and dive must clear platform: %s -> %s; disabled=%s flying=%s" % [start, pilot.position, pilot.disabled, pilot.flying])
	# Hold the new wing near the old hard ceiling for four seconds.
	pilot.position = Vector3(0, 181, -265)
	pilot.set_equipment(1)
	pilot.pitch = 0
	pilot.airspeed = 19
	pilot.launch_lift = 0
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
	for id in ["wood", "membrane", "ruins"]:
		for island in world.islands:
			if island.id == id:
				pilot.position = island.pos + Vector3(0, 0.7, 0)
				pilot.flying = false
				pilot.velocity = Vector3.ZERO
				world._interact()
				world._interact()
	check(world.inventory.wood == 3 and world.inventory.membrane == 2 and world.inventory.plan == 1, "Materials collect once per island")
	pilot.position = Vector3(0, 65, 23)
	world._interact()
	check(world.upgraded and pilot.equipment_level == 1 and world.inventory.wood == 0, "Workbench must consume materials and equip new wing")
	world._restart()
	check(world.upgraded and world.collected.size() == 3 and pilot.equipment_level == 1, "Recovery preserves crafted equipment and collected materials")
	pilot.position = Vector3(10, 176.7, -620)
	world._interact()
	check(world.finished, "Final beacon must complete second level")
	world.finished = false
	world.checkpoint = Vector3(20, 144, -462)
	world._restart()
	pilot.launch()
	pilot.position = world.gate_positions[1] + Vector3(11, 0, 5)
	pilot.pitch = 0
	pilot.airspeed = 36
	for i in 20:
		await world.get_tree().physics_frame
		if pilot.disabled:
			break
	check(pilot.disabled, "Stone arch pillar must collide")
	world._restart()
	check(not pilot.disabled and not pilot.flying and pilot.position.distance_to(world.checkpoint) < 0.1, "Crash recovery must return to checkpoint")
	if not failed:
		print("SKYGLIDE REGRESSION PASS: geometry caps, continuous thermal ceiling, smooth vertical motion, energy, collection, crafting, checkpoint, beacon, collision")
	world.get_tree().quit(1 if failed else 0)
