extends SceneTree

const Aero = preload("res://aerodynamics.gd")
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func trajectory(initial: Vector3, pitch: float, equipment: int, fps: int, seconds: float = 20.0) -> Dictionary:
	var velocity := initial
	var position := Vector3(0, 1000, 0)
	var max_energy_gain := 0.0
	var previous_energy := 0.5 * velocity.length_squared() + Aero.GRAVITY * position.y
	for i in roundi(seconds * fps):
		var next := Aero.integrate(velocity, Vector3.ZERO, 0, pitch, 0, 0, equipment, 1.0 / fps)
		position += (velocity + next) * 0.5 / fps
		velocity = next
		var energy := 0.5 * velocity.length_squared() + Aero.GRAVITY * position.y
		max_energy_gain = maxf(max_energy_gain, energy - previous_energy)
		previous_energy = energy
	return {"velocity": velocity, "position": position, "gain": max_energy_gain, "ratio": -velocity.z / -velocity.y}

func _run() -> void:
	var resting := Aero.forces(Vector3.ZERO, Vector3.ZERO, 0, Aero.TRIM, 0, 0, 0)
	check(resting.lift == Vector3.ZERO and resting.drag == Vector3.ZERO, "Zero airspeed creates zero aerodynamic force")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77892
	for i in 240:
		var velocity := Vector3(rng.randf_range(-25, 25), rng.randf_range(-25, 25), rng.randf_range(-25, 25))
		var wind := Vector3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-5, 5))
		var force := Aero.forces(velocity, wind, rng.randf_range(-PI, PI), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.6, 0.6), rng.randf(), i % 2)
		var relative := velocity - wind
		check(absf(force.lift.dot(relative)) < 0.00001 * maxf(1, force.lift.length() * relative.length()), "Lift must do no work along relative airflow")
		check(force.drag.dot(relative) <= 0.001, "Drag must dissipate energy in relative airflow")
	var below := Aero.acceleration(Vector3(0, -1, -14.999), Vector3.ZERO, 0, Aero.TRIM, 0, 0, 0)
	var above := Aero.acceleration(Vector3(0, -1, -15.001), Vector3.ZERO, 0, Aero.TRIM, 0, 0, 0)
	check(below.distance_to(above) < 0.02, "No discontinuity at the old 15 m/s threshold")
	var basic := trajectory(Vector3(0, 0, -9), Aero.TRIM, 0, 120)
	var advanced := trajectory(Vector3(0, 0, -9), Aero.TRIM, 1, 120)
	check(-basic.velocity.z > 8 and -basic.velocity.z < 13 and -basic.velocity.y < 2.5 and basic.ratio > 5, "Running takeoff must settle into shallow glide")
	check(advanced.ratio > basic.ratio * 1.35, "Equipment must improve glide ratio through wing parameters")
	check(basic.gain < 0.002 and advanced.gain < 0.002, "Still-air mechanical energy must not increase")
	for fps in [30, 60]:
		var other := trajectory(Vector3(0, 0, -9), Aero.TRIM, 0, fps)
		check(other.velocity.distance_to(basic.velocity) < 0.02 and other.position.distance_to(basic.position) < 0.1, "30/60/120 Hz trajectories must agree")
	var drop := trajectory(Vector3.ZERO, Aero.TRIM, 0, 120, 6)
	check(-drop.position.z > 30 and drop.position.y > 975, "Zero-speed descent must develop forward glide without launch impulse")
	var dive := trajectory(Vector3(0, -1, -10), -0.26, 0, 120, 3)
	var neutral := trajectory(Vector3(0, -1, -10), Aero.TRIM, 0, 120, 3)
	var flare := trajectory(Vector3(0, -1, -14), 0.18, 0, 120, 2)
	check(dive.velocity.length() > neutral.velocity.length() and dive.position.y < neutral.position.y, "Diving must trade height for speed")
	check(flare.velocity.length() < 14 and flare.gain < 0.002, "Pulling up must spend kinetic energy, never add thrust")
	var no_brake := Aero.forces(Vector3(0, -1, -10), Vector3.ZERO, 0, Aero.TRIM, 0, 0, 0)
	var brake := Aero.forces(Vector3(0, -1, -10), Vector3.ZERO, 0, Aero.TRIM, 0, 1, 0)
	check(brake.drag.length() > no_brake.drag.length(), "Brake must increase drag")
	print("AERO METRICS basic=", basic.velocity, " ratio=", basic.ratio, " advanced=", advanced.velocity, " ratio=", advanced.ratio, " drop6s=", drop.position - Vector3(0, 1000, 0))
	if not failed:
		print("AERODYNAMICS PASS: passive forces, energy dissipation, threshold continuity, running/drop takeoff, dive/flare/brake, equipment, 30/60/120 Hz")
	quit(1 if failed else 0)
