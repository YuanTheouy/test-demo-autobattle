extends RefCounted
## Authoritative board markers: never derive a cell from an animated body.
const Beat = preload("res://scripts/beat_simulation.gd")

static func markers(units: Array) -> Array:
	var groups: Dictionary = {}
	for u in units:
		if u.hp <= 0: continue
		if not groups.has(u.cell): groups[u.cell] = []
		groups[u.cell].append(u)
	var result: Array = []
	for cell in groups:
		var occupants: Array = groups[cell]
		occupants.sort_custom(func(a, b): return a.uid < b.uid)
		for lane in range(occupants.size()):
			var u: Dictionary = occupants[lane]
			var direction: String = {Vector2i.RIGHT: "右", Vector2i.LEFT: "左", Vector2i.UP: "上", Vector2i.DOWN: "下"}.get(u.trend, "无")
			result.append({"uid": u.uid, "cell": cell, "p": Beat.center(cell), "team": u.team, "stationary": u.pose == "站稳", "trend": u.trend, "identity": "%s%d %s" % ["蓝" if u.team == 0 else "红", u.member + 1, Beat.name_of(cell)], "pose_text": "站稳" if u.pose == "站稳" else "移动·" + direction, "lane": lane, "count": occupants.size()})
	return result
