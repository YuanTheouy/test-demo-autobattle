extends SceneTree

var world: Node3D
var pilot: CharacterBody3D
var frames := 0
var capture := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	pilot = world.player
	pilot.control_override = true
	capture = "--capture" in OS.get_cmdline_user_args()
	# Only ordinary flight inputs, island interaction and on-foot turning are used.
	var route := [
		["land", Vector3(-42, 58, -68), "wood"],
		["climb", Vector3(-5, 91, -61), ""],
		["land", Vector3(48, 62, -94), "membrane"],
		["climb", Vector3(15, 100, -145), ""],
		["land", Vector3(0, 78, -180), "ruins"],
		["climb", Vector3(-5, 94, -61), ""],
		["land", Vector3(0, 64, 23), "camp"],
		["climb", Vector3(15, 103, -145), ""],
		["climb", Vector3(0, 167, -265), ""],
		["land", Vector3(20, 142, -445), "entry"],
		["climb", Vector3(18, 197, -529), ""],
		["land", Vector3(-36, 149, -510), "crystal"],
		["climb", Vector3(18, 197, -529), ""],
		["land", Vector3(10, 176, -620), "summit"],
	]
	for leg in route:
		if not await _fly(leg[0], leg[1], leg[2]):
			quit(1)
			return
		if leg[0] == "land":
			var interaction: Dictionary = world.interaction_target()
			if not interaction.is_empty() and not await _walk_to(interaction.pos):
				quit(1)
				return
			world._interact()
			if leg[2] == "camp" and not world.upgraded:
				push_error("Workbench did not produce the upgraded wing")
				quit(1)
				return
		print("Route: %s %s at %s" % [leg[0], leg[2], pilot.position])
	if not world.finished or world.inventory.crystal != 1:
		push_error("Two-level route did not finish")
		quit(1)
		return
	print("SKYGLIDE ROUTE PASS: collect all materials, return and craft, cross high gap, collect wind crystal, light final beacon; %.1f simulated seconds" % (frames / 60.0))
	quit()

func _fly(kind: String, target: Vector3, island_id: String) -> bool:
	if not pilot.flying:
		for frame in 240:
			var offset := target - pilot.position
			var error := wrapf(atan2(offset.x, -offset.z) - pilot.heading, -PI, PI)
			pilot.test_turn = clampf(error * 5, -1, 1)
			if absf(error) < 0.03:
				break
			await physics_frame
			frames += 1
		pilot.test_turn = 0
		pilot.test_brake = false
		pilot.launch()
	var landing := false
	var landing_radius := 20.0
	for island in world.islands:
		if island.id == island_id:
			landing_radius = float(island.radius)
	for frame in 2400:
		var offset := target - pilot.position
		var distance := Vector2(offset.x, offset.z).length()
		var angle := atan2(offset.x, -offset.z)
		pilot.test_turn = clampf(wrapf(angle - pilot.heading, -PI, PI) * 5, -1, 1)
		var desired_pitch := -0.06
		if kind == "land":
			landing = landing or distance < landing_radius - 4
			if landing:
				desired_pitch = -0.10
				pilot.test_brake = pilot.airspeed > 10
			else:
				desired_pitch = clampf(atan2(offset.y + 12, maxf(distance, 1)), -0.5, 0.12)
				pilot.test_brake = false
		else:
			pilot.test_brake = distance < 40 and pilot.airspeed > 16
			if distance < 27 and pilot.position.y >= target.y:
				pilot.test_brake = false
				return true
		pilot.test_pitch = clampf((desired_pitch - pilot.pitch) * 6, -1, 1)
		await physics_frame
		frames += 1
		if capture and frame == 80:
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("res://flight_check.png")
		if pilot.disabled:
			push_error("Route crashed approaching %s %s at %s" % [kind, island_id, pilot.position])
			return false
		if not pilot.flying:
			if kind == "land" and world.current_island == island_id:
				return true
			push_error("Unexpected landing on %s while heading to %s" % [world.current_island, island_id])
			return false
	push_error("Route timeout: %s %s; position %s; speed %.1f; target %s" % [kind, island_id, pilot.position, pilot.airspeed, target])
	return false

func _walk_to(target: Vector3) -> bool:
	for frame in 800:
		var offset := target - pilot.position
		if Vector2(offset.x, offset.z).length() < 2.8:
			pilot.test_walk = 0
			pilot.test_turn = 0
			for i in 5:
				await physics_frame
			return true
		var error := wrapf(atan2(offset.x, -offset.z) - pilot.ground_view_heading, -PI, PI)
		pilot.test_turn = clampf(error * 5, -1, 1)
		pilot.test_walk = 1 if absf(error) < 0.7 else 0
		await physics_frame
		frames += 1
		if pilot.flying or pilot.disabled or not pilot.is_on_floor():
			push_error("Walking to interaction must remain on island")
			return false
	push_error("Unable to walk to material/workbench/beacon")
	return false
