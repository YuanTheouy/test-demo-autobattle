extends "res://third_party/stairs_character.gd"
## Movement adapted from GDQuest's player_3d_template_v3.gd (MIT).
## Commit 6f3292ed36537e33230e5ea9205d424b37b180af; third_party/gdquest-code.LICENSE.
## Retains camera-relative input, independent vertical velocity and acceleration.
## Adds separate ground braking and limited, nonpropulsive airborne steering.

@export var ground_acceleration := 60.0
@export var ground_braking := 75.0
@export var air_steering := 7.0

static func camera_relative_input(input: Vector2, yaw: float) -> Vector3:
	var forward := Vector3(sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, sin(yaw))
	return (forward * input.y + right * input.x).limit_length()

func walk_velocity(direction: Vector3, speed: float, gravity: float, delta: float) -> void:
	# GDQuest: separate y so smoothing horizontal input cannot cancel gravity.
	velocity.y = 0
	var acceleration := ground_braking if direction.is_zero_approx() else ground_acceleration
	velocity = velocity.move_toward(direction * speed, acceleration * delta)
	velocity.y = -gravity * delta
	desired_velocity = direction * speed

func airborne_velocity(direction: Vector3, wind: Vector3, gravity: float, delta: float) -> void:
	# Air steering can bend an existing jump, but cannot start flying from rest.
	var y_velocity := velocity.y
	var horizontal := velocity * Vector3(1, 0, 1)
	if not direction.is_zero_approx():
		horizontal = horizontal.move_toward(direction * horizontal.length(), air_steering * delta)
	velocity = horizontal + Vector3.UP * y_velocity
	var relative := velocity - wind
	velocity += (Vector3.DOWN * gravity - relative * relative.length() * 0.003) * delta
