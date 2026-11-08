extends SceneTree

var world: Node3D
var pilot: CharacterBody3D
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code)
	key(code, false)

func click(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func ticks(count: int) -> void:
	for i in count:
		await physics_frame

func _run() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	pilot = world.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await ticks(20)
	check(not pilot.control_override, "This test must use real input dispatch, never controller overrides")
	check(not pilot.first_person and pilot.is_on_floor(), "Start third-person on the ground beside the workbench")
	var start_y := pilot.position.y
	tap(KEY_E)
	await ticks(2)
	check(world.toast.contains("还需轻木") and absf(pilot.position.y - start_y) < 0.1, "E uses the workbench from ground level without jumping")
	world.toast = ""
	click(MOUSE_BUTTON_LEFT)
	await ticks(2)
	check(world.toast.contains("还需轻木"), "Left click must use the nearby workbench too")
	var standing_position := pilot.position
	tap(KEY_F)
	await ticks(30)
	check(pilot.canopy_open and not pilot.flying and pilot.position.distance_to(standing_position) < 0.03 and pilot.airspeed == 0, "Ground F only opens canopy and never moves or jumps the person")
	tap(KEY_F)
	await ticks(2)
	tap(KEY_F)
	tap(KEY_SPACE)
	await ticks(120)
	check(pilot.canopy_open and pilot.canopy.visible and pilot.is_on_floor(), "Open canopy must remain open after jumping and landing without F")
	tap(KEY_SPACE)
	await ticks(8)
	check(pilot.canopy_open and pilot.flying, "A second jump must keep the existing open canopy")
	tap(KEY_F)
	await ticks(100)
	check(not pilot.canopy_open and pilot.is_on_floor(), "Only F closes canopy, and landing preserves the closed state")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(120, -80)
	mouse.screen_relative = mouse.relative
	Input.parse_input_event(mouse)
	await ticks(2)
	check(absf(pilot.ground_view_heading - 0.3) < 0.01 and absf(pilot.view_pitch - 0.02) < 0.01, "Mouse rotates both axes consistently without holding a button or viewport scaling sensitivity")
	check(absf(pilot.camera.rotation.x - pilot.view_pitch) < 0.01, "Third-person camera must follow mouse pitch")
	tap(KEY_V)
	await ticks(2)
	check(pilot.first_person, "V optionally switches view; third person is the default")
	tap(KEY_V)
	tap(KEY_M)
	await ticks(2)
	check(paused and world.map_view.visible, "Map must pause flight")
	tap(KEY_M)
	await ticks(2)
	check(not paused and not world.map_view.visible, "Closing map must resume")
	# A fixture on the membrane island isolates actual WASD/E interaction handling.
	# The separate route test flies here from spawn without fixtures or teleportation.
	pilot.reset_at(Vector3(48, world.terrains.membrane.height_at(48, -80) + 1, -80))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await ticks(20)
	tap(KEY_E)
	await ticks(2)
	check(world.inventory.membrane == 0, "E must not collect from the far edge of the island")
	key(KEY_W)
	await ticks(75)
	key(KEY_W, false)
	await ticks(6)
	check(pilot.position.z < -89 and pilot.is_on_floor(), "Actual W input must run toward the membrane crate")
	tap(KEY_E)
	await ticks(2)
	check(world.inventory.membrane == 2, "Actual E input collects membrane when standing by the crate")
	click(MOUSE_BUTTON_LEFT)
	await ticks(2)
	check(world.inventory.membrane == 2, "Left click cannot duplicate collected materials")
	key(KEY_W)
	await ticks(20)
	var grounded_y := pilot.position.y
	tap(KEY_SPACE)
	await ticks(15)
	check(pilot.position.y > grounded_y + 0.9 and not pilot.flying, "Actual Space input jumps without opening canopy: rise=%.3f flying=%s" % [pilot.position.y - grounded_y, pilot.flying])
	tap(KEY_F)
	key(KEY_W, false)
	await ticks(3)
	check(pilot.flying, "Actual F input opens canopy")
	var before_look: Vector3 = pilot.velocity
	var before_heading: float = pilot.heading
	mouse = InputEventMouseMotion.new()
	mouse.relative = Vector2(800, 300)
	mouse.screen_relative = mouse.relative
	Input.parse_input_event(mouse)
	check(pilot.velocity.distance_to(before_look) < 0.0001 and absf(pilot.heading - before_heading) < 0.0001, "Looking around in flight must not steer or rewrite velocity")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	Input.parse_input_event(right)
	var speed: float = pilot.airspeed
	await ticks(12)
	check(pilot.airspeed < speed - 0.15, "Right mouse button must brake in flight through aerodynamic drag")
	right = right.duplicate()
	right.pressed = false
	Input.parse_input_event(right)
	tap(KEY_F)
	await ticks(100)
	check(not pilot.flying and pilot.is_on_floor() and not pilot.disabled, "F closes canopy and allows a normal landing")
	if not failed:
		print("SKYGLIDE INPUT PASS: third-person mouse look, V, ground-level E/LMB workbench, actual WASD membrane gathering, jump, F deploy/retract, RMB brake, paused map")
	quit(1 if failed else 0)
