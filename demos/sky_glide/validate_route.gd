extends SceneTree

var world: Node3D
var pilot: CharacterBody3D
var frames := 0
var braking := false
var walking := false

func _initialize() -> void:
	call_deferred("_run")

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)

func _aim(yaw: float, nose_pitch: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(wrapf(yaw - pilot.ground_view_heading, -PI, PI) / 0.0025, -(nose_pitch - pilot.view_pitch) / 0.0025)
	event.screen_relative = event.relative
	Input.parse_input_event(event)

func _brake(value: bool) -> void:
	if braking == value:
		return
	braking = value
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = value
	Input.parse_input_event(event)

func _walk(value: bool) -> void:
	if walking != value:
		walking = value
		_key(KEY_W, value)

func _run() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	pilot = world.player
	for i in 20:
		await physics_frame
	# No control overrides, teleports, direct speed/heading changes or direct interactions.
	var route := [
		["land", Vector3(-42, 58, -68), "wood"],
		["climb", Vector3(-5, 91, -61), ""],
		["land", Vector3(48, 62, -94), "membrane"],
		["climb", Vector3(15, 100, -145), ""],
		["land", Vector3(0, 78, -180), "ruins"],
		["climb", Vector3(-5, 94, -61), ""],
		["land", Vector3(0, 64, 23), "camp"],
		["climb", Vector3(15, 103, -145), ""],
		["climb", Vector3(0, 167, -265), ""],
		["land", Vector3(20, 142, -445), "entry"],
		["climb", Vector3(18, 197, -529), ""],
		["land", Vector3(-36, 149, -510), "crystal"],
		["climb", Vector3(18, 197, -529), ""],
		["land", Vector3(10, 176, -620), "summit"],
	]
	for leg in route:
		if not await _fly(leg[0], leg[1], leg[2]):
			quit(1)
			return
		if leg[0] == "land":
			var interaction: Dictionary = world.interaction_target()
			if not interaction.is_empty() and not await _walk_to(interaction.pos):
				quit(1)
				return
			_tap(KEY_E)
			await physics_frame
			if leg[2] == "camp" and not world.upgraded:
				push_error("Ground-level E did not craft the upgraded wing")
				quit(1)
				return
		print("Input route: %s %s at %s" % [leg[0], leg[2], pilot.position])
	if not world.finished or world.inventory.crystal != 1 or world.collected.size() != 4:
		push_error("Input route did not collect all materials and finish both levels")
		quit(1)
		return
	print("SKYGLIDE INPUT ROUTE PASS: normal mouse aim, RMB brake, F deploy, WASD walking and E gathering/crafting/beacon; %.1f simulated seconds" % (frames / 60.0))
	quit()

func _fly(kind: String, target: Vector3, island_id: String) -> bool:
	_walk(false)
	_brake(false)
	if not pilot.flying:
		var offset := target - pilot.position
		_aim(atan2(offset.x, -offset.z), -0.06)
		await physics_frame
		# Align character with the view by one ordinary on-foot step.
		_walk(true)
		for i in 6:
			await physics_frame
		_walk(false)
		_tap(KEY_F)
	var landing := false
	var landing_radius := 20.0
	for island in world.islands:
		if island.id == island_id:
			landing_radius = float(island.radius)
	for frame in 2400:
		var offset := target - pilot.position
		var distance := Vector2(offset.x, offset.z).length()
		var desired_pitch := -0.06
		if kind == "land":
			landing = landing or distance < landing_radius - 4
			if landing:
				desired_pitch = -0.10
				_brake(pilot.airspeed > 10)
			else:
				desired_pitch = clampf(atan2(offset.y + 12, maxf(distance, 1)), -0.5, 0.12)
				_brake(false)
		else:
			_brake(distance < 40 and pilot.airspeed > 16)
			if distance < 27 and pilot.position.y >= target.y:
				_brake(false)
				return true
		_aim(atan2(offset.x, -offset.z), desired_pitch)
		await physics_frame
		frames += 1
		if pilot.disabled:
			push_error("Input route crashed approaching %s %s at %s" % [kind, island_id, pilot.position])
			return false
		if not pilot.flying:
			_brake(false)
			if kind == "land" and world.current_island == island_id:
				return true
			push_error("Input route unexpectedly landed on %s while heading to %s" % [world.current_island, island_id])
			return false
	push_error("Input route timeout: %s %s; at %s" % [kind, island_id, pilot.position])
	return false

func _walk_to(target: Vector3) -> bool:
	for frame in 800:
		var offset := target - pilot.position
		if Vector2(offset.x, offset.z).length() < 2.8:
			_walk(false)
			for i in 5:
				await physics_frame
			return true
		_aim(atan2(offset.x, -offset.z), -0.18)
		_walk(true)
		await physics_frame
		frames += 1
		if pilot.flying or pilot.disabled or not pilot.is_on_floor():
			push_error("Ordinary on-foot input must stay on island")
			return false
	push_error("Unable to walk to material/workbench/beacon")
	return false
