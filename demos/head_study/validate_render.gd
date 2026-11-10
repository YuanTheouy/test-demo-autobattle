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
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

func _run() -> void:
	var study = load("res://main.tscn").instantiate()
	root.add_child(study)
	study.set_angles(0, 0, 0)
	study.hidden_lines = false
	study.axes = false
	study.caps = false
	var no_caps := await snapshot(study)
	var point: Vector2 = study.center + study.radius * Vector2(0.9, 0.12)
	var paper := no_caps.get_pixelv(point)
	study.caps = true
	study.sliders.cap_opacity.value = 0.05
	var faint := (await snapshot(study)).get_pixelv(point)
	study.sliders.cap_opacity.value = 0.6
	var stronger := (await snapshot(study)).get_pixelv(point)
	if not (distance(paper, faint) > 0.001 and distance(paper, stronger) > distance(paper, faint) * 3):
		failures.append("GPU cap opacity must blend with paper at its original sphere position")
	study.sliced = false
	var full_sphere := await snapshot(study)
	if distance(paper, full_sphere.get_pixelv(point)) <= distance(paper, stronger):
		failures.append("Whole sphere must be more opaque than transparent caps")
	var background_point := Vector2i(12, 350)
	if distance(no_caps.get_pixelv(background_point), full_sphere.get_pixelv(background_point)) > 0.001:
		failures.append("Shader misses must leave background unchanged")
	if failures.is_empty():
		print("HEAD STUDY GPU PASS: in-place caps, opacity slider, solid sphere, transparent background")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
