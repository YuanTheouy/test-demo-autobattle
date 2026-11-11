extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func snapshot(study: Control) -> Image:
	study.queue_redraw()
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func distance(a: Color, b: Color) -> float:
	return Vector3(a.r-b.r, a.g-b.g, a.b-b.b).length()

func _run() -> void:
	var study = load("res://main.tscn").instantiate()
	root.add_child(study)
	study.landmarks = false
	study.plane_edges = false
	study.caps = false
	study.axes = false
	study.set_angles(0, 0, 0)
	var detailed := await snapshot(study)
	var sample: Vector2 = study.project_point(Vector3(study.cut * 0.47, -0.18, 0))
	study.secondary_enabled = false
	var basic := await snapshot(study)
	if distance(detailed.get_pixelv(sample), basic.get_pixelv(sample)) < 0.03:
		failures.append("GPU secondary mode must change recessed eye socket shading")
	study.secondary_enabled = true
	study.set_angles(90, 0, 0)
	var with_nose := await snapshot(study)
	var nose_sample: Vector2 = study.project_point(Vector3(0, -0.57, 1.16))
	study.nose_enabled = false
	var no_nose := await snapshot(study)
	if distance(with_nose.get_pixelv(nose_sample), no_nose.get_pixelv(nose_sample)) < 0.04:
		failures.append("GPU secondary nose toggle must change side silhouette")
	study.nose_enabled = true
	for pose in [[0, 90, 0], [0, -90, 0], [180, 0, 0], [-90, 30, 35]]:
		study.set_angles(pose[0], pose[1], pose[2])
		var image := await snapshot(study)
		if image.is_empty():
			failures.append("Extreme views must render")
	if failures.is_empty():
		print("SECONDARY GPU PASS: socket shading, basic/detail comparison, nose silhouette and extreme views")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
