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
	var model = study.face_model
	var profiles := 0
	for a in [0.45, sqrt(5.0) / 3.0, 0.98]:
		for width in [0.16, 0.24, 0.38]:
			for depth in [0.8, 1.0, 1.2]:
				model.build(a, width, depth)
				var max_x := -INF
				var min_y := INF
				var max_y := -INF
				check(model.secondary_triangles.size() < 240, "Detailed geometry stays small enough for interactive rotation")
				for tri in model.secondary_triangles:
					check(is_equal_approx(tri[3].length(), 1), "Flat patch normals are normalized")
					for i in 3:
						var p: Vector3 = tri[i]
						check(p.is_finite(), "Secondary mesh contains no nonfinite vertex")
						check(absf(p.x) <= model.half_width(p.y) + 0.0001, "Secondary planes preserve existing face/jaw width")
						max_x = maxf(max_x, p.x)
						min_y = minf(min_y, p.y)
						max_y = maxf(max_y, p.y)
				check(is_equal_approx(max_x, a), "Existing maximum face width is unchanged")
				check(is_equal_approx(min_y, -4.0 / 3.0) and is_equal_approx(max_y, 2.0 / 3.0), "Hair/chin heights are unchanged")
				var x: float = 0.47 * a
				var brow: Dictionary = model.secondary_bvh.intersect_ray(Vector3(x, 0.035, 4), Vector3.FORWARD)
				var socket: Dictionary = model.secondary_bvh.intersect_ray(Vector3(x, -0.18, 4), Vector3.FORWARD)
				var cheek: Dictionary = model.secondary_bvh.intersect_ray(Vector3(x, -0.43, 4), Vector3.FORWARD)
				check(not brow.is_empty() and not socket.is_empty() and not cheek.is_empty(), "BVH intersects brow, eye socket and cheek")
				if not brow.is_empty() and not socket.is_empty() and not cheek.is_empty():
					check(socket.position.z < brow.position.z - 0.08 and socket.position.z < cheek.position.z - 0.08, "Eye socket genuinely recedes between brow and cheek")
				for y in [2.0 / 3.0, 0.0, -1.0 / 3.0, -2.0 / 3.0, -1.0, -4.0 / 3.0]:
					var section: Array[Vector3] = model.secondary_section(y)
					check(section.size() >= 4, "All user landmark sections remain available")
					for p in section:
						check(is_equal_approx(p.y, y), "Landmark section keeps exact user height")
				profiles += 1
	study.model_signature = Vector3(-1, -1, -1)
	study._sync_face_model()
	var revision: int = study.model_revision
	for yaw in [-180, -90, 0, 45, 90, 180]:
		for pitch in [-90, 0, 90]:
			study.set_angles(yaw, pitch, 25)
			study._sync_face_model()
			check(study.model_revision == revision, "Rotation does not rebuild relief or BVH")
	study.set_angles(0, 0, 0)
	check(study._point_visible(model.secondary_front(-1.1)), "Chin/labial plane is visible from front")
	check(not study._point_visible(Vector3(0, -0.3, 0)), "Front geometry hides rear surfaces")
	if failures.is_empty():
		print("SECONDARY PASS: %d proportion sets, preserved widths/heights, recessed sockets, BVH and rotation cache" % profiles)
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
