extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = load("res://main.tscn").instantiate()
	root.add_child(world)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://preview.png")
	world.map_view.visible = true
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://map_preview.png")
	world.map_view.visible = false
	var pilot = world.player
	pilot.control_override = true
	world.upgraded = true
	pilot.set_equipment(1)
	pilot.position = Vector3(0, 177, -265)
	pilot.reset_physics_interpolation()
	pilot.flying = true
	pilot.canopy_open = true
	pilot.airspeed = 18
	pilot.pitch = 0
	pilot.test_turn = 1
	var timings: Array[float] = []
	var last_tick := Time.get_ticks_usec()
	for i in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		if i > 60:
			timings.append((now - last_tick) / 1000.0)
		last_tick = now
		if i in [120, 250]:
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("res://thermal_check_%d.png" % i)
			# Exclude screenshot encoding and disk I/O from runtime frame timings.
			last_tick = Time.get_ticks_usec()
	timings.sort()
	var result := {"frames": timings.size(), "p50_ms": snappedf(timings[timings.size() / 2], 0.01), "p95_ms": snappedf(timings[int(timings.size() * 0.95)], 0.01), "max_ms": snappedf(timings.back(), 0.01), "final_altitude": pilot.position.y}
	var output := FileAccess.open("res://render_check.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	print("SKYGLIDE RENDER CHECK: ", JSON.stringify(result))
	quit()
