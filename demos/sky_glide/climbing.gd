extends RefCounted

var actor: CharacterBody3D
var active := false
var normal := Vector3.BACK
var cooldown := 0.0
var mantle_phase := -1
var mantle_top := Vector3.ZERO
var mantle_goal := Vector3.ZERO

func _init(owner: CharacterBody3D) -> void:
	actor = owner

func reset() -> void:
	active = false
	cooldown = 0.25
	mantle_phase = -1

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_ray(query)

func release(push_off: bool = false) -> void:
	active = false
	mantle_phase = -1
	cooldown = 0.30
	if push_off:
		actor.velocity = normal * 3.0 + Vector3.UP * actor.JUMP_SPEED
		actor.jump_buffer = 0
		actor.ground_grace = 0
	if actor.canopy_open and not actor.is_on_floor():
		actor._begin_glide()

func tick(delta: float, wish: Vector2, grab: bool, jump_requested: bool) -> bool:
	cooldown = maxf(0, cooldown - delta)
	if active and jump_requested:
		release(true)
		return false
	if mantle_phase >= 0:
		_mantle(delta)
		return true
	if not grab:
		if active:
			release()
		return false
	if not active:
		if cooldown > 0:
			return false
		var forward := Vector3(sin(actor.ground_view_heading), 0, -cos(actor.ground_view_heading))
		var hit := ray(actor.position + Vector3.UP * 0.3, actor.position + Vector3.UP * 0.3 + forward * 1.15)
		if hit.is_empty() or hit.normal.y > 0.65 or hit.normal.y < -0.75:
			return false
		active = true
		normal = hit.normal
		actor.flying = false
		actor.velocity = Vector3.ZERO
	var contact := ray(actor.position + Vector3.UP * 0.3, actor.position + Vector3.UP * 0.3 - normal * 1.2)
	if contact.is_empty():
		if wish.y > 0 and _start_mantle():
			_mantle(delta)
			return true
		release()
		return false
	normal = contact.normal
	if wish.y > 0 and _start_mantle():
		_mantle(delta)
		return true
	var up := Vector3.UP.slide(normal).normalized()
	var right := up.cross(normal).normalized()
	actor.velocity = (up * wish.y + right * wish.x).limit_length() * 2.6 - normal * 1.2
	actor.heading = atan2(-normal.x, normal.z)
	actor.move_and_slide()
	actor.visual.rotation = Vector3(0, -actor.heading, 0)
	actor.canopy.rotation = Vector3(0, -actor.heading, 0)
	if actor.is_on_floor() and wish.y < 0:
		release()
	return true

func _start_mantle() -> bool:
	var forward := -normal * Vector3(1, 0, 1)
	if forward.length_squared() < 0.1:
		return false
	forward = forward.normalized()
	var origin := actor.position + forward * 0.95 + Vector3.UP * 1.8
	var top := ray(origin, origin + Vector3.DOWN * 2.0)
	if top.is_empty() or top.normal.y < 0.75:
		return false
	var goal: Vector3 = top.position + Vector3.UP * 0.94
	if goal.y - actor.position.y > 1.6 or goal.y < actor.position.y + 0.05:
		return false
	var raised := actor.global_transform
	var rise := Vector3.UP * (goal.y - actor.position.y)
	if actor.test_move(raised, rise):
		return false
	raised.origin += rise
	if actor.test_move(raised, goal - raised.origin):
		return false
	mantle_top = raised.origin
	mantle_goal = goal
	mantle_phase = 0
	return true

func _mantle(delta: float) -> void:
	var target := mantle_top if mantle_phase == 0 else mantle_goal
	var difference := target - actor.position
	if difference.length() < 0.04:
		if mantle_phase == 0:
			mantle_phase = 1
			return
		active = false
		mantle_phase = -1
		cooldown = 0.4
		actor.velocity = Vector3.DOWN
		actor.move_and_slide()
		actor.apply_floor_snap()
		actor.landed.emit()
		return
	actor.velocity = difference.normalized() * minf(5, difference.length() / delta)
	actor.move_and_slide()
