extends SceneTree
## Real rendered frames, including continuous slider updates and the full grid.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var study = load("res://main.tscn").instantiate()
	root.add_child(study)
	study.grid = not "--no-grid" in OS.get_cmdline_user_args()
	var timings: Array[float] = []
	for i in 140:
		var start := Time.get_ticks_usec()
		study.set_angles((i * 7) % 360 - 180, 60 * sin(i * 0.11), 50 * cos(i * 0.07))
		if not "--rotation-only" in OS.get_cmdline_user_args():
			study.sliders.cut.value = 0.7 + 0.2 * sin(i * 0.09)
		if study.sliders.has("cap_opacity"):
			study.sliders.cap_opacity.value = 0.3 + 0.2 * sin(i * 0.08)
		await process_frame
		await RenderingServer.frame_post_draw
		if i >= 20:
			timings.append((Time.get_ticks_usec() - start) / 1000.0)
	timings.sort()
	print("HEAD STUDY FRAME MS: median=%.2f p95=%.2f max=%.2f (120 moving frames, grid=%s)" % [timings[60], timings[114], timings.back(), study.grid])
	quit()
