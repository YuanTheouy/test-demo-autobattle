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
	for style in 2:
		for a in [0.45, sqrt(5.0) / 3.0, 0.98]:
			for width in [0.16, 0.24, 0.38]:
				for depth in [0.8, 1.0, 1.2]:
					model.build(a, width, depth, style)
					check(model.patch_count <= 19, "No more than reference-level basic planes, including hidden closures")
					check(model.secondary_triangles.size() <= 56, "Only a small render triangulation is present")
					check(model.secondary_edges.size() <= 50, "No dense structural edge network")
					var min_y := INF
					var max_y := -INF
					for tri in model.secondary_triangles:
						check(tri[4] in [0,1], "Only basic shell and nose: no eyelid/lip feature geometry")
						check(is_equal_approx(tri[3].length(), 1), "Flat patch normals are normalized")
						for i in 3:
							var p: Vector3 = tri[i]
							check(p.is_finite(), "No invalid vertices")
							check(absf(p.x) <= model.half_width(p.y) + 0.0001, "Existing face and jaw width envelope is respected")
							min_y = minf(min_y,p.y)
							max_y = maxf(max_y,p.y)
					check(is_equal_approx(min_y,-4.0/3.0) and is_equal_approx(max_y,2.0/3.0), "Existing height proportions remain intact")
					profiles += 1
	study.set_angles(55,-25,20)
	var saved_cut: float = study.cut
	study.style_buttons[1].pressed.emit()
	study._sync_face_model()
	check(study.head_style == 1 and is_equal_approx(study.chin_width,0.16), "Actual girl button selects narrow-chin preset")
	check(study.face_model.style == 1, "Girl preset reaches rendered geometry")
	check(study.yaw == 55 and study.pitch == -25 and study.roll == 20 and study.cut == saved_cut, "Preset switch preserves angle and side-circle dimensions")
	var girl_nose := 0.0
	for tri in model.secondary_triangles:
		if tri[4] == 1:
			for i in 3:
				girl_nose = maxf(girl_nose,tri[i].z)
	study.style_buttons[0].pressed.emit()
	study._sync_face_model()
	var male_nose := 0.0
	for tri in model.secondary_triangles:
		if tri[4] == 1:
			for i in 3:
				male_nose = maxf(male_nose,tri[i].z)
	check(study.head_style == 0 and is_equal_approx(study.chin_width,0.24), "Actual male button restores male basic planes")
	check(girl_nose < male_nose - 0.05, "Girl preset has a smaller, shallower nose block")
	var revision: int = study.model_revision
	for yaw in [-180,-90,0,45,90,180]:
		for pitch in [-90,0,90]:
			study.set_angles(yaw,pitch,25)
			study._sync_face_model()
			check(study.model_revision == revision, "Rotation does not rebuild geometry or BVH")
	if failures.is_empty():
		print("BASIC HEADS PASS: %d parameter sets, both preset buttons, complexity budget, proportions and rotation cache" % profiles)
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)
