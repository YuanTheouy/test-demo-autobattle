extends RefCounted
## Render-only state. Never writes back to the combat snapshot.
const DURATION := 0.25
const CRUISE_SPEED := 80.0 / (2.0 * DURATION)
var tracks: Dictionary = {}
var flights: Array = []
var bursts: Array = []
var time := 0.0
var beat_age := 0.0

func destination(u: Dictionary) -> Vector2:
	if u.mode == "碰撞":
		var direction := Vector2(u.return_cell - u.cell)
		if direction == Vector2.ZERO: direction = Vector2.RIGHT if u.team == 0 else Vector2.LEFT
		return u.p + direction.normalized() * 30
	if u.mode == "移动硬直":
		var progress: float = float(u.move_total - u.left) / u.move_total
		return Vector2((Vector2(u.move_origin) + Vector2.ONE * 0.5) * 80).lerp(u.action_goal, progress)
	return u.p

func reset(units: Array) -> void:
	tracks.clear()
	flights.clear()
	bursts.clear()
	time = 0.0
	beat_age = 0.0
	for u in units:
		tracks[u.uid] = {"from": destination(u), "to": destination(u), "age": DURATION, "angle_from": u.angle, "angle_to": u.angle, "flash": 0.0, "hurt": 0.0, "heal": 0.0, "v0": Vector2.ZERO, "v1": Vector2.ZERO, "dodge": false, "guide": {}}

func position(u: Dictionary) -> Vector2:
	if not tracks.has(u.uid): return u.p
	var track: Dictionary = tracks[u.uid]
	var t := clampf(track.age / DURATION, 0.0, 1.0)
	# Hermite segments share both position and velocity across beat boundaries.
	return (2 * t * t * t - 3 * t * t + 1) * Vector2(track.from) + (t * t * t - 2 * t * t + t) * DURATION * Vector2(track.v0) + (-2 * t * t * t + 3 * t * t) * Vector2(track.to) + (t * t * t - t * t) * DURATION * Vector2(track.v1)

func velocity(u: Dictionary) -> Vector2:
	if not tracks.has(u.uid): return Vector2.ZERO
	var track: Dictionary = tracks[u.uid]
	if track.age > DURATION + 0.00001: return Vector2.ZERO
	var t := clampf(track.age / DURATION, 0.0, 1.0)
	return ((6 * t * t - 6 * t) * Vector2(track.from) + (3 * t * t - 4 * t + 1) * DURATION * Vector2(track.v0) + (-6 * t * t + 6 * t) * Vector2(track.to) + (3 * t * t - 2 * t) * DURATION * Vector2(track.v1)) / DURATION

func guide(u: Dictionary) -> Dictionary:
	return tracks[u.uid].guide if tracks.has(u.uid) else {}

func movement_guide(old: Dictionary, u: Dictionary) -> Dictionary:
	if u.mode == "碰撞": return {"from": destination(u), "to": (Vector2(u.return_cell) + Vector2.ONE * 0.5) * 80, "text": "下拍弹回", "bounce": true}
	if u.mode == "移动硬直": return {"from": u.p, "to": u.action_goal, "text": "移动余%d拍" % u.left, "bounce": false}
	if u.phase in ["跨格", "侧闪跨格", "弹回"] and old.cell != u.cell:
		return {"from": old.p, "to": u.p, "text": "侧闪" if u.phase == "侧闪跨格" else ("弹回" if u.phase == "弹回" else "跨格"), "bounce": u.phase == "弹回"}
	return {}

func angle(u: Dictionary) -> float:
	if not tracks.has(u.uid): return u.angle
	var track: Dictionary = tracks[u.uid]
	return lerp_angle(track.angle_from, track.angle_to, smoothstep(0.0, 1.0, clampf(track.age / DURATION, 0.0, 1.0)))

func begin(before: Array, after: Array, sim) -> void:
	if tracks.is_empty(): reset(before)
	beat_age = 0.0
	for u in after:
		var old: Dictionary = before[u.uid]
		var p := position(old)
		var v := velocity(old)
		var facing := angle(old)
		var track: Dictionary = tracks[u.uid]
		track.from = p
		track.to = destination(u)
		track.angle_from = facing
		track.angle_to = u.angle
		track.age = 0.0
		track.v0 = v.limit_length(CRUISE_SPEED * 1.5)
		track.v1 = Vector2.ZERO
		if u.phase == "跨格" or u.mode == "移动硬直":
			track.v1 = Vector2(u.trend) * (80.0 / (maxi(1, u.move_total) * DURATION))
		track.guide = movement_guide(old, u)
		track.dodge = u.phase == "侧闪跨格"
		if u.phase == "释放硬直": track.flash = 0.18
		if u.hp < old.hp: track.hurt = 0.2
		if u.hp > old.hp: track.heal = 0.5
	# New attacks only. Flight endpoints are locked integer cells, never homing.
	for strike in sim.strikes:
		var delay: int = strike.at - sim.beat
		var source: Dictionary = after[strike.source]
		if source.phase != "释放硬直" or delay != sim.flight_delay(strike.skill): continue
		for cell in strike.cells:
			flights.append({"from": position(source), "to": sim.center(cell), "age": 0.0, "duration": maxf(DURATION, delay * DURATION), "team": strike.team, "arc": delay >= 2})
	for effect in sim.effects:
		for cell in effect.cells:
			bursts.append({"p": sim.center(cell), "age": 0.0, "team": effect.team, "total_beats": maxi(1, effect.at - effect.get("warn_from", effect.at - maxi(1, sim.flight_delay(effect.skill))))})
		if sim.flight_delay(effect.skill) == 0:
			for cell in effect.cells:
				flights.append({"from": position(after[effect.source]), "to": sim.center(cell), "age": 0.0, "duration": 0.16, "team": effect.team, "arc": false, "beam": true})

func advance(delta: float) -> void:
	time += delta
	beat_age = minf(DURATION, beat_age + delta)
	for track in tracks.values():
		track.age += delta
		for key in ["flash", "hurt", "heal"]: track[key] = maxf(0.0, track[key] - delta)
	for flight in flights: flight.age += delta
	flights = flights.filter(func(f): return f.age < f.duration)
	for burst in bursts: burst.age += delta
	bursts = bursts.filter(func(f): return f.age < 0.35)

func visual(u: Dictionary) -> Dictionary:
	var copy := u.duplicate()
	if not tracks.has(u.uid): return copy
	var track: Dictionary = tracks[u.uid]
	copy.p = position(u)
	copy.angle = angle(u)
	copy.fire_flash = track.flash
	copy.hit_flash = track.hurt
	copy.heal_flash = track.heal
	copy.visual_time = time
	copy.visual_motion = clampf(velocity(u).length() / CRUISE_SPEED, 0.0, 1.0)
	copy.action_left = 1.0 if Vector2(track.from).distance_to(track.to) > 1 and track.age < DURATION else 0.0
	copy.dodge = DURATION - track.age if track.dodge else 0.0
	copy.dodge_dir = Vector2(track.to - track.from).normalized()
	return copy
