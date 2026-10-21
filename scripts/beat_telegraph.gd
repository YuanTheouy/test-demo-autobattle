extends RefCounted
## Forecast only: dates use the exact same integer beats as strike resolution.
const Beat = preload("res://scripts/beat_simulation.gd")

static func divisions(total_beats: int) -> Array[float]:
	var cuts: Array[float] = []
	for boundary in range(1, total_beats): cuts.append(float(boundary) / total_beats)
	return cuts

static func cells(sim, elapsed: float) -> Array:
	var incoming: Array = []
	for strike in sim.strikes:
		incoming.append({"cells": strike.cells, "due": strike.at, "start": strike.get("warn_from", strike.at - maxi(1, Beat.flight_delay(strike.skill))), "team": strike.team})
	for u in sim.units:
		if u.hp <= 0 or u.mode not in ["前摇", "释放硬直"]: continue
		var count: int = 1 if u.mode == "前摇" else u.left
		var due: int = sim.beat + (u.left if u.mode == "前摇" else 0) + 1 + Beat.flight_delay(u.active_skill)
		# Only the next not-yet-released shot matters; later shots share its cells.
		if count > 0:
			incoming.append({"cells": u.lock_cells, "due": due, "start": u.attack_started, "team": u.team})
	var nearest: Dictionary = {}
	for attack in incoming:
		if attack.due <= sim.beat: continue
		for cell in attack.cells:
			var key := "%d:%d:%d" % [cell.x, cell.y, attack.team]
			if nearest.has(key) and nearest[key].due <= attack.due: continue
			nearest[key] = {"cell": cell, "due": attack.due, "start": attack.start, "team": attack.team}
	# Leave a small notch until the actual impact beat has been resolved, including
	# when single-stepping. A completed bright frame is reserved for real effects.
	var visual_beat: float = sim.beat + clampf(elapsed / Beat.SECONDS, 0.0, 0.98)
	var result: Array = []
	for warning in nearest.values():
		warning.remaining = warning.due - sim.beat
		warning.total_beats = maxi(1, warning.due - warning.start)
		warning.progress = clampf((visual_beat - warning.start) / warning.total_beats, 0.0, 0.995)
		result.append(warning)
	return result
