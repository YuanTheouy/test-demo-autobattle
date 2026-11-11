extends RefCounted
## User-defined drawing construction, in units of skull radius R.
const HAIR := 2.0 / 3.0
const EYE := -1.0 / 3.0
const NOSE := -2.0 / 3.0
const MOUTH := -1.0
const CHIN := -4.0 / 3.0
var planes: Array[Plane] = []
var nose_planes: Array[Plane] = []
var edges: Array = []
var nose_edges: Array = []
var vertices: Array[Vector3] = []
var depth := 1.0
var chin_width := 0.24
var cut := sqrt(5.0) / 3.0

func build(a: float, width: float, projection: float) -> void:
	cut = a
	chin_width = width
	depth = projection
	var rho := sqrt(1 - a * a)
	var jaw_slope := (a - width) / (4.0 / 3.0 - rho)
	planes = [Plane(Vector3.UP, HAIR), Plane(Vector3.DOWN, -CHIN), Plane(Vector3.FORWARD, 0)]
	for side in [-1.0, 1.0]:
		planes.append(Plane(Vector3(side, 0, 0), a))
		planes.append(_plane(Vector3(side, -jaw_slope, 0), a + jaw_slope * rho))
		planes.append(_plane(Vector3(side, 0, 0.35 / depth), a + 0.16))
	var profile := [Vector2(HAIR, 0.78), Vector2(0, 1.02), Vector2(NOSE, 0.94), Vector2(MOUTH, 0.83), Vector2(CHIN, 0.68)]
	for i in profile.size() - 1:
		var p: Vector2 = profile[i]
		var q: Vector2 = profile[i + 1]
		var slope := (q.y - p.y) * depth / (q.x - p.x)
		planes.append(_plane(Vector3(0, -slope, 1), p.y * depth - slope * p.x))
	nose_planes = [Plane(Vector3.UP, EYE), Plane(Vector3.DOWN, -NOSE), Plane(Vector3.FORWARD, -0.88 * depth), _plane(Vector3(0, 0.69, 1.0 / depth), 0.76)]
	for side in [-1.0, 1.0]:
		nose_planes.append(_plane(Vector3(side, 0.3, 0), -0.1))
	var mesh := _polyhedron(planes)
	vertices = mesh.vertices
	edges = mesh.edges
	nose_edges = _polyhedron(nose_planes).edges

func _plane(normal: Vector3, d: float) -> Plane:
	return Plane(normal.normalized(), d / normal.length())

func _polyhedron(bounds: Array[Plane]) -> Dictionary:
	var points: Array[Vector3] = []
	for i in bounds.size():
		for j in range(i + 1, bounds.size()):
			for k in range(j + 1, bounds.size()):
				var a := bounds[i]
				var b := bounds[j]
				var c := bounds[k]
				var det := a.normal.dot(b.normal.cross(c.normal))
				if absf(det) < 0.00001:
					continue
				var p := (a.d * b.normal.cross(c.normal) + b.d * c.normal.cross(a.normal) + c.d * a.normal.cross(b.normal)) / det
				var inside := true
				for bound in bounds:
					if bound.distance_to(p) > 0.0001:
						inside = false
						break
				if inside:
					var unique := true
					for existing in points:
						if existing.distance_squared_to(p) < 0.000001:
							unique = false
							break
					if unique:
						points.append(p)
	var segments: Array = []
	var used: Dictionary = {}
	for bound in bounds:
		var indices: Array[int] = []
		var center := Vector3.ZERO
		for i in points.size():
			if absf(bound.distance_to(points[i])) < 0.0002:
				indices.append(i)
				center += points[i]
		if indices.size() < 3:
			continue
		center /= indices.size()
		var u := bound.normal.cross(Vector3.UP if absf(bound.normal.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := bound.normal.cross(u)
		indices.sort_custom(func(a: int, b: int): return atan2((points[a] - center).dot(v), (points[a] - center).dot(u)) < atan2((points[b] - center).dot(v), (points[b] - center).dot(u)))
		for i in indices.size():
			var a := indices[i]
			var b := indices[(i + 1) % indices.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not used.has(key):
				used[key] = true
				segments.append([points[a], points[b]])
	return {"vertices": points, "edges": segments}

func section(y: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for edge in edges:
		var a: Vector3 = edge[0]
		var b: Vector3 = edge[1]
		if absf(a.y - b.y) < 0.00001:
			continue
		var t := (y - a.y) / (b.y - a.y)
		if t < -0.0001 or t > 1.0001:
			continue
		var p := a.lerp(b, clampf(t, 0, 1))
		var unique := true
		for existing in points:
			if existing.distance_squared_to(p) < 0.000001:
				unique = false
		if unique:
			points.append(p)
	var center := Vector3.ZERO
	for point in points:
		center += point
	if points.is_empty():
		return points
	center /= points.size()
	points.sort_custom(func(a: Vector3, b: Vector3): return atan2(a.z - center.z, a.x - center.x) < atan2(b.z - center.z, b.x - center.x))
	return points

func front(y: float) -> Vector3:
	var z := INF
	for plane in planes:
		if plane.normal.z > 0.00001:
			z = minf(z, (plane.d - plane.normal.y * y) / plane.normal.z)
	return Vector3(0, y, z)
