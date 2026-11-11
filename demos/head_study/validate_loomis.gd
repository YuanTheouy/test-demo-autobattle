extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var study = load("res://main.tscn").instantiate()
	root.add_child(study)
	study._sync_face_model()
	check(is_equal_approx(sqrt(1 - study.cut * study.cut), 2.0 / 3.0), "Default side circle has radius 2R/3")
	var model = study.face_model
	var profiles := 0
	for a in [0.45, sqrt(5.0) / 3.0, 0.98]:
		for width in [0.16, 0.24, 0.38]:
			for depth in [0.8, 1.0, 1.2]:
				model.build(a, width, depth)
				check(model.planes.size() <= 16 and model.nose_planes.size() <= 8, "Plane count fits GPU uniforms")
				check(model.vertices.size() >= 12 and model.edges.size() >= 18 and model.nose_edges.size() >= 6, "Closed facial solid and nose wedge have geometry")
				var min_y := INF
				var max_y := -INF
				for p in model.vertices:
					min_y = minf(min_y, p.y)
					max_y = maxf(max_y, p.y)
					for plane in model.planes:
						check(plane.distance_to(p) < 0.001, "Vertices remain inside all facial bounds")
				check(is_equal_approx(min_y, -4.0 / 3.0) and is_equal_approx(max_y, 2.0 / 3.0), "Hair and chin match user proportions")
				for y in [2.0 / 3.0, 0.0, -1.0 / 3.0, -2.0 / 3.0, -1.0, -4.0 / 3.0]:
					var section: Array[Vector3] = model.section(y)
					check(section.size() >= 4, "Every landmark has a closed cross-section")
					for point in section:
						check(is_equal_approx(point.y, y), "Landmark heights remain fixed in head coordinates")
					var front: Vector3 = model.front(y)
					for plane in model.planes:
						check(plane.distance_to(front) < 0.001, "Face centerline stays on facial surface")
				profiles += 1
	# Rebuild once after the geometry audit; angle-only changes reuse model and uniforms.
	study.model_signature = Vector3(-1, -1, -1)
	study._sync_face_model()
	var revision: int = study.model_revision
	for y in [-180, -90, 0, 45, 90, 180]:
		for p in [-90, 0, 90]:
			study.set_angles(y, p, 25)
			study._sync_face_model()
			check(study.model_revision == revision, "Rotation does not rebuild facial geometry")
	study.set_angles(0, 0, 0)
	check(study._point_visible(model.front(-1)), "Mouth plane is visible from front")
	check(not study._point_visible(Vector3(0, -0.3, 0)), "Back facial surface is occluded from front")
	if failures.is_empty():
		print("LOOMIS PASS: 27 parameter sets, exact landmark proportions, convex solids, sections, occlusion and rotation cache")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
