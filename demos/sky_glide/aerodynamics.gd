extends RefCounted

# Quasi-steady wing approximation, SI units. No powered thrust or velocity targets.
# Lift is perpendicular to relative airflow; all drag terms dissipate energy.
const MASS := 85.0
const GRAVITY := 9.81
const AIR_DENSITY := 1.225
const TRIM := -0.04

static func forces(velocity: Vector3, wind: Vector3, heading: float, incidence: float, bank: float, brake: float, equipment: int) -> Dictionary:
	var relative := velocity - wind
	var gravity := Vector3.DOWN * MASS * GRAVITY
	var speed_squared := relative.length_squared()
	if speed_squared < 0.00000001:
		return {"gravity": gravity, "lift": Vector3.ZERO, "drag": Vector3.ZERO, "alpha": 0.0}
	var air_direction := relative / sqrt(speed_squared)
	var chord := Vector3(sin(heading) * cos(incidence), sin(incidence), -cos(heading) * cos(incidence))
	var span := Vector3(cos(heading), 0, sin(heading)).rotated(chord, bank)
	var normal := span.cross(chord).normalized()
	var alpha := atan2(-relative.dot(normal), relative.dot(chord))
	# Smooth over the full angle range, including separated flow; no speed cutoff.
	var cl := 0.35 * cos(alpha) + 1.40 * sin(2 * alpha)
	var area := 20.0 if equipment > 0 else 18.0
	var profile_drag := 0.045 if equipment > 0 else 0.080
	var induced_drag := 0.040 if equipment > 0 else 0.060
	var cd := profile_drag + induced_drag * cl * cl + 0.50 * sin(alpha) * sin(alpha) + brake * 0.24
	var dynamic_pressure := 0.5 * AIR_DENSITY * speed_squared
	var lift_direction := air_direction.cross(normal).cross(air_direction)
	var lift_force := lift_direction.normalized() * dynamic_pressure * area * cl
	var drag_force := -air_direction * dynamic_pressure * area * cd
	var sideways_speed := relative.dot(span)
	drag_force -= span * sideways_speed * absf(sideways_speed) * 0.5 * AIR_DENSITY * area * 0.35
	return {"gravity": gravity, "lift": lift_force, "drag": drag_force, "alpha": alpha}

static func acceleration(velocity: Vector3, wind: Vector3, heading: float, incidence: float, bank: float, brake: float, equipment: int) -> Vector3:
	var force := forces(velocity, wind, heading, incidence, bank, brake, equipment)
	return (force.gravity + force.lift + force.drag) / MASS

static func integrate(velocity: Vector3, wind: Vector3, heading: float, incidence: float, bank: float, brake: float, equipment: int, delta: float) -> Vector3:
	var steps := maxi(1, ceili(delta * 120.0))
	var dt := delta / steps
	var result := velocity
	for i in steps:
		var midpoint := result + acceleration(result, wind, heading, incidence, bank, brake, equipment) * dt * 0.5
		result += acceleration(midpoint, wind, heading, incidence, bank, brake, equipment) * dt
	return result
