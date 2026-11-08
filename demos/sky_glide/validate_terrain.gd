extends SceneTree

const Glider = preload("res://glider.gd")
var pilot: CharacterBody3D
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var mesh := BoxShape3D.new()
	mesh.size = size
	shape.shape = mesh
	body.position = at
	body.add_child(shape)
	root.add_child(body)

func _run() -> void:
	box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	box(Vector3(0, 0.125, 0), Vector3(5, 0.25, 4))
	box(Vector3(10, 10, 0), Vector3(1, 20, 30))
	pilot = Glider.new()
	pilot.spawn_point = Vector3(0, 1, 6)
	root.add_child(pilot)
	pilot.control_override = true
	for i in 15:
		await physics_frame
	pilot.launch()
	pilot.test_walk = 1
	var highest := 0.0
	var detached := 0
	var unintended_glide := false
	for i in 120:
		await physics_frame
		highest = maxf(highest, pilot.position.y)
		if not pilot.is_on_floor():
			detached += 1
		unintended_glide = unintended_glide or pilot.flying
	check(pilot.position.z < -8 and highest > 1.12, "Walking must cross a 25 cm step without jumping: at %s highest %.3f" % [pilot.position, highest])
	check(detached <= 6 and not unintended_glide and pilot.canopy_open, "Capsule edge contacts must stay within ground grace and never start gliding: detached=%d unintended=%s" % [detached, unintended_glide])
	pilot.test_walk = 0
	pilot.reset_at(Vector3(-8, 1.3, 15))
	pilot.velocity = Vector3(0, -3, -9)
	pilot.flying = true
	for i in 30:
		await physics_frame
		if pilot.is_on_floor():
			break
	check(pilot.is_on_floor() and Vector2(pilot.velocity.x, pilot.velocity.z).length() > 5, "Touchdown must retain tangential momentum")
	for i in 30:
		await physics_frame
	check(Vector2(pilot.velocity.x, pilot.velocity.z).length() < 0.1 and pilot.canopy_open, "Ground friction must stop sliding without folding canopy")
	pilot.reset_at(Vector3(7, 10, 6))
	pilot.velocity = Vector3(8, -1, -6)
	pilot.flying = true
	pilot.heading = atan2(8.0, 6.0)
	var touched := false
	for i in 60:
		await physics_frame
		if pilot.get_slide_collision_count() > 0 and not pilot.is_on_floor():
			touched = true
			check(absf(pilot.velocity.z) > 1 and pilot.canopy_open, "Scraping a wall must preserve tangential motion and canopy state")
			break
	check(touched and not pilot.disabled, "Wall fixture must actually be reached without killing the player")
	if not failed:
		print("TERRAIN PASS: 25 cm step, ground adhesion with canopy open, landing momentum, ground friction, tangential wall slide")
	quit(1 if failed else 0)
