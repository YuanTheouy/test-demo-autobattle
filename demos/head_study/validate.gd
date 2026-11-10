extends SceneTree
## Run: Godot --headless --path demos/head_study --script res://validate.gd
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var study = load("res://main.tscn").instantiate()
	root.add_child(study)
	await process_frame
	study.set_angles(90, 0, 0)
	check((study.head_basis * Vector3.BACK).is_equal_approx(Vector3.LEFT), "Positive yaw moves face toward subject's right (-X)")
	study.set_angles(0, 90, 0)
	check((study.head_basis * Vector3.BACK).is_equal_approx(Vector3.DOWN), "Positive pitch nods down (-Y)")
	study.set_angles(0, 0, 90)
	check((study.head_basis * Vector3.UP).is_equal_approx(Vector3.LEFT), "Positive roll tilts crown to subject's right (-X)")
	study.set_angles(0, 0, 0)
	check(study._point_visible(Vector3.BACK), "Face is visible from front")
	check(not study._point_visible(Vector3.FORWARD), "Back is hidden from front")
	check(study._point_visible(Vector3.UP), "Exact tangent is visible (no chord midpoint error)")
	study.sliders.separation.value = 0.85
	study.sliders.cut.value = 0.45
	check(is_equal_approx(study.separation, 0.85) and is_equal_approx(study.cut, 0.45), "Actual sliders update geometry")
	var poses := 0
	for y in [-180, -90, -30, 0, 45, 90, 180]:
		for p in [-90, -35, 0, 35, 90]:
			for r in [-90, 0, 40, 90]:
				study.set_angles(y, p, r)
				check(is_equal_approx(study.head_basis.determinant(), 1), "Rotation preserves handedness")
				for t in [0.0, 0.8, 2.5, 4.7]:
					var point: Vector3 = study._ring_point(study.cut, t)
					check(is_equal_approx(point.length(), 1), "Cut circle is on unit sphere")
					check(is_equal_approx(point.x, study.cut), "Cut circle stays in its plane")
					var projected: Vector2 = study.project_point(point)
					check(projected.is_finite(), "Projection remains finite at extreme angles")
				poses += 1
	# A cut face must occlude the far hemisphere at side view.
	study.set_angles(90, 0, 0)
	study.caps = false
	check(study._point_visible(Vector3(study.cut, 0, 0)), "Near planar cut is visible")
	check(not study._point_visible(Vector3(-study.cut, 0, 0)), "Far cut is occluded")
	study.sliced = false
	check(study._point_visible(Vector3.RIGHT), "Whole sphere restores removed surface")
	if failures.is_empty():
		print("HEAD STUDY PASS: angle signs, actual sliders, %d poses, cut geometry, projection and occlusion" % poses)
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
