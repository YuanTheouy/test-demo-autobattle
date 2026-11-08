extends SceneTree

var world: Node3D
var pilot: CharacterBody3D
var frames := 0
var braking := false
var walking := false
var held: Dictionary = {}
var previous_heading := 0.0

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

func _hold(code: Key, value: bool) -> void:
	if bool(held.get(code, false)) != value:
		held[code] = value
		_key(code, value)

func _walk(value: bool) -> void:
	walking = value
	_hold(KEY_W, value)

func _clear_flight_keys() -> void:
	for code in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SHIFT]:
		_hold(code, false)

func _steer(yaw: float, desired_pitch: float) -> void:
	var error := wrapf(yaw - pilot.heading, -PI, PI)
	var yaw_rate := wrapf(pilot.heading - previous_heading, -PI, PI) * 60
	previous_heading = pilot.heading
	var wanted_bank := clampf(error * 1.3 - yaw_rate * 0.6, -0.60, 0.60)
	_hold(KEY_D, pilot.bank < wanted_bank - 0.035)
	_hold(KEY_A, pilot.bank > wanted_bank + 0.035)
	_hold(KEY_S, pilot.pitch < desired_pitch - 0.012)
	_hold(KEY_SHIFT, pilot.pitch > desired_pitch + 0.012)

func _run() -> void:
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	pilot = world.player
	for i in 20:
		await physics_frame
	# No control overrides, teleports, direct speed/heading changes or direct interactions.
	var route := [
		["land", Vector3(-42, 58, -68), "wood"],
		["land", Vector3(48, 62, -94), "membrane"],
		["climb", Vector3(0, 92, -130), ""],
		["land", Vector3(0, 78, -180), "ruins"],
		["land", Vector3(0, 64, 23), "camp"],
		["climb", Vector3(0, 165, -265), ""],
		["land", Vector3(20, 142, -445), "entry"],
		["climb", Vector3(18, 197, -529), ""],
		["land", Vector3(-36, 149, -510), "crystal"],
		["climb", Vector3(18, 197, -529), ""],
		["land", Vector3(10, 176, -620), "summit"],
	]
	for index in route.size():
		var leg: Array = route[index]
		var exit_target: Vector3 = route[index + 1][1] if index + 1 < route.size() else Vector3.ZERO
		if not await _fly(leg[0], leg[1], leg[2], exit_target):
			quit(1)
			return
		if leg[0] == "land":
			if leg[2] == "camp" and pilot.position.y > 67:
				if not await _walk_to(Vector3(-6, pilot.position.y, pilot.position.z)):
					quit(1)
					return
				if not await _walk_to(Vector3(-6, 64, 43)):
					quit(1)
					return
				if not await _walk_to(Vector3(6, 64, 43)):
					quit(1)
					return
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

func _fly(kind: String, target: Vector3, island_id: String, exit_target: Vector3) -> bool:
	_walk(false)
	_clear_flight_keys()
	_brake(false)
	previous_heading = pilot.heading
	if not pilot.flying:
		if world.current_island == "camp":
			if not await _walk_to(Vector3(12, 64, pilot.position.z)):
				return false
			if not await _walk_to(Vector3(6, 64, 43)):
				return false
			if not await _walk_to(Vector3(-6, 64, 43)):
				return false
			if not await _walk_to(Vector3(-6, 84, -6)):
				return false
		else:
			for island in world.islands:
				if island.id == world.current_island:
					var direction := target - Vector3(island.pos)
					direction.y = 0
					if not await _walk_to(Vector3(island.pos) + direction.normalized() * float(island.radius) * 0.84):
						return false
		var offset := target - pilot.position
		_aim(atan2(offset.x, -offset.z), -0.30)
		_walk(true)
		for i in 15:
			await physics_frame
		_tap(KEY_SPACE)
		for i in 8:
			await physics_frame
		_walk(false)
		if not pilot.canopy_open:
			_tap(KEY_F)
	var landing := false
	var landing_radius := 20.0
	for island in world.islands:
		if island.id == island_id:
			landing_radius = float(island.radius)
	for frame in (3600 if kind == "climb" else 2400):
		var offset := target - pilot.position
		var distance := Vector2(offset.x, offset.z).length()
		var desired_heading := atan2(offset.x, -offset.z)
		var desired_pitch: float = pilot.Aero.TRIM
		if kind == "land":
			landing = landing or distance < landing_radius - 4
			if landing:
				desired_pitch = 0.04
				_brake(true)
			else:
				desired_pitch = pilot.Aero.TRIM
				_brake(false)
		else:
			_brake(distance < 40 and pilot.airspeed > 16)
			if distance < 30 and distance > 1:
				var outward := Vector3(-offset.x, 0, -offset.z).normalized()
				var tangent := Vector3(-outward.z, 0, outward.x)
				var orbit_direction := tangent - outward * (distance - 17) / 9.0
				desired_heading = atan2(orbit_direction.x, -orbit_direction.z)
			var exit_direction := (exit_target - pilot.position) * Vector3(1, 0, 1)
			var movement: Vector3 = pilot.velocity * Vector3(1, 0, 1)
			if distance < 42 and pilot.position.y >= target.y and movement.normalized().dot(exit_direction.normalized()) > 0.8:
				_brake(false)
				return true
		_aim(desired_heading, -0.18)
		_steer(desired_heading, desired_pitch)
		await physics_frame
		frames += 1
		if pilot.disabled:
			push_error("Input route crashed approaching %s %s at %s" % [kind, island_id, pilot.position])
			return false
		if not pilot.flying and pilot.is_on_floor():
			_clear_flight_keys()
			_brake(false)
			if kind == "land" and world.current_island == island_id:
				return true
			push_error("Input route unexpectedly contacted %s at %s while heading to %s" % [world.current_island, pilot.position, island_id])
			return false
	push_error("Input route timeout: %s %s; at %s" % [kind, island_id, pilot.position])
	return false

func _walk_to(target: Vector3) -> bool:
	_clear_flight_keys()
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
			push_error("Ordinary on-foot input must stay on island: at %s target %s velocity %s flying %s floor %s" % [pilot.position, target, pilot.velocity, pilot.flying, pilot.is_on_floor()])
			return false
	push_error("Unable to walk to %s from %s" % [target, pilot.position])
	return false
