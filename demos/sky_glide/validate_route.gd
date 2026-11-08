extends SceneTree

# Flies the complete route using only the same pitch/turn/brake controls as a player.
# No teleportation, lift overrides, or speed overrides after takeoff.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	var pilot = world.player
	pilot.control_override = true
	pilot.launch()
	var stage := 0
	for frame in 2400:
		var target := Vector3.ZERO
		if stage == 0:
			target = Vector3(0, 44, -64)
			if pilot.position.z < -65:
				stage = 1
		elif stage == 1:
			target = Vector3(-8, 34, -142)
			if pilot.position.z < -143:
				stage = 2
		elif stage == 2:
			target = Vector3(-8, 38, -208)
			if Vector2(pilot.position.x + 8, pilot.position.z + 208).length() < 14:
				stage = 3
		elif stage == 4:
			target = Vector3(0, 79, -292)
		if stage == 3:
			pilot.test_pitch = clampf(-pilot.pitch * 5, -1, 1)
			pilot.test_turn = 1.0
			pilot.test_brake = pilot.airspeed > 16
			if pilot.position.y > 98:
				stage = 4
		else:
			var offset: Vector3 = target - pilot.position
			var horizontal := Vector2(offset.x, offset.z).length()
			var desired_pitch := clampf(atan2(offset.y, maxf(horizontal, 1)), -0.65, 0.5)
			pilot.test_pitch = clampf((desired_pitch - pilot.pitch) * 6, -1, 1)
			var desired_heading := atan2(offset.x, -offset.z)
			pilot.test_turn = clampf(wrapf(desired_heading - pilot.heading, -PI, PI) * 4, -1, 1)
			pilot.test_brake = (stage == 2 and horizontal < 40 and pilot.airspeed > 18) or (stage == 4 and horizontal < 45 and pilot.airspeed > 19)
		await physics_frame
		if pilot.disabled:
			push_error("Route crashed at stage %d, position %s" % [stage, pilot.position])
			quit(1)
			return
		if world.finished:
			if not world.gate_flags[0] or not world.gate_flags[1]:
				push_error("Route skipped an arch")
				quit(1)
				return
			print("SKYGLIDE ROUTE PASS: both arches, thermal climb, destination landing; %.1f seconds" % (frame / 60.0))
			quit()
			return
	push_error("Route timed out at stage %d, position %s" % [stage, pilot.position])
	quit(1)
