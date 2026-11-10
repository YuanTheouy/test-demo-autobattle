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
	study.sliders.cap_opacity.value = 0.15
	study.sliders.cut.value = 0.45
	check(is_equal_approx(study.cap_opacity, 0.15) and is_equal_approx(study.cut, 0.45), "Actual sliders update geometry and transparency")
	for a in [0.45, 0.76, 0.98]:
		study.sliders.cut.value = a
		var join := asin(a)
		var rho := sqrt(1 - a * a)
		check(study._side_meridian_point(join).is_equal_approx(Vector3(a, rho, 0)), "Arc joins cut chord exactly")
		check(study._side_meridian_point(PI - join).is_equal_approx(Vector3(a, -rho, 0)), "Chord rejoins lower arc exactly")
		for t in [0.2, 1.0, 2.1, 3.8, 4.8, 5.9]:
			var point: Vector3 = study._side_meridian_point(t)
			check(is_zero_approx(point.z), "New meridian lies in Z=0, perpendicular to face meridian X=0")
			if absf(sin(t)) <= a:
				check(is_equal_approx(point.length(), 1), "Uncut meridian remains on sphere")
			else:
				check(is_equal_approx(absf(point.x), a) and absf(point.y) <= rho, "Cut part lies on straight chord of planar disc")
	study.set_angles(55, 25, 20)
	var chord_top: Vector2 = study.project_point(Vector3(study.cut, sqrt(1 - study.cut * study.cut), 0))
	var chord_bottom: Vector2 = study.project_point(Vector3(study.cut, -sqrt(1 - study.cut * study.cut), 0))
	var chord_center: Vector2 = study.project_point(study._side_meridian_point(PI / 2))
	check(absf((chord_top - chord_center).cross(chord_bottom - chord_center)) < 0.05, "Projected cut chord stays straight after combined rotation")
	for a in [0.45, 0.76, 0.98]:
		study.sliders.cut.value = a
		for h in [-0.65, 0.0, 0.4, 0.65]:
			var r := sqrt(1 - h * h)
			var joints: Array[float] = study._horizontal_joints(h)
			check(joints.size() == (4 if r > a else 0), "Horizontal chords only exist when latitude reaches cut plane")
			if r > a:
				var z := sqrt(r * r - a * a)
				var chord_a: Vector3 = study._horizontal_point(joints[0], h)
				var chord_b: Vector3 = study._horizontal_point(joints[1], h)
				check(chord_a.is_equal_approx(Vector3(a, h, z)) and chord_b.is_equal_approx(Vector3(a, h, -z)), "Horizontal arc joins both chord endpoints exactly")
				var pa: Vector2 = study.project_point(chord_a)
				var pb: Vector2 = study.project_point(chord_b)
				var pm: Vector2 = study.project_point(study._horizontal_point(PI / 2, h))
				check(absf((pa - pm).cross(pb - pm)) < 0.05, "Horizontal cut chord projects to a straight line")
			for t in [0.2, 1.0, 2.1, 3.8, 4.8, 5.9]:
				var point: Vector3 = study._horizontal_point(t, h)
				check(is_equal_approx(point.y, h), "Horizontal line keeps selected height")
				if absf(r * sin(t)) <= a:
					check(is_equal_approx(point.length(), 1), "Uncut horizontal arc remains on sphere")
				else:
					check(is_equal_approx(absf(point.x), a) and point.length_squared() <= 1.00001, "Horizontal chord lies inside planar cut disc")
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
	study.caps = true
	check(study._point_visible(Vector3(study.cut, 0, 0)), "Transparent cap does not hide the cut face")
	check(not study._point_visible(Vector3(-study.cut, 0, 0)), "Far cut is occluded")
	study.sliced = false
	check(study._point_visible(Vector3.RIGHT), "Whole sphere restores removed surface")
	check(study._side_meridian_point(PI / 2).is_equal_approx(Vector3.RIGHT), "Disabling cuts restores complete circular meridian")
	check(study._horizontal_point(PI / 2, 0).is_equal_approx(Vector3.RIGHT), "Disabling cuts restores complete equator")
	if failures.is_empty():
		print("HEAD STUDY PASS: angle signs, actual sliders, %d poses, cut geometry, projection and occlusion" % poses)
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
