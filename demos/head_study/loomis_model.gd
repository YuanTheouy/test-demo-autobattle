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
var secondary_triangles: Array = []
var secondary_edges: Array = []
var secondary_bvh := TriangleMesh.new()
var secondary_nose_bvh := TriangleMesh.new()

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
	_build_secondary()

func half_width(y: float) -> float:
	var rho := sqrt(1 - cut * cut)
	var slope := (cut - chin_width) / (4.0 / 3.0 - rho)
	return minf(cut, cut + slope * (y + rho))

func _build_secondary() -> void:
	# Loomis plate 9 guides topology, not numerical anatomy. Width and height
	# remain the user's construction; the relief is an authored approximation.
	secondary_triangles.clear()
	secondary_edges.clear()
	var heights := [
		[HAIR, HAIR, HAIR, HAIR, HAIR],
		[0.0, 0.025, 0.035, 0.07, 0.0],
		[-0.18, -0.16, -0.18, -0.14, -0.20],
		[EYE, EYE, EYE, EYE, EYE],
		[-0.50, -0.49, -0.43, -0.39, -0.48],
		[NOSE, NOSE, NOSE, NOSE, NOSE],
		[-0.83, -0.83, -0.79, -0.79, -0.85],
		[MOUTH, MOUTH, MOUTH, MOUTH, MOUTH],
		[-1.10, -1.10, -1.10, -1.10, -1.10],
		[CHIN, CHIN, CHIN, CHIN, CHIN]]
	var depths := [
		[0.78, 0.79, 0.76, 0.64, 0.0],
		[1.02, 1.03, 1.01, 0.90, 0.0],
		[1.00, 0.92, 0.79, 0.78, 0.0],
		[0.98, 0.95, 0.87, 0.86, 0.0],
		[0.96, 0.99, 0.99, 0.84, 0.0],
		[0.94, 1.02, 0.85, 0.64, 0.0],
		[0.90, 0.93, 0.82, 0.55, 0.0],
		[0.83, 0.86, 0.79, 0.48, 0.0],
		[0.75, 0.73, 0.71, 0.43, 0.0],
		[0.68, 0.68, 0.66, 0.48, 0.0]]
	var fractions := [0.0, 0.18, 0.47, 0.75, 1.0]
	var rings: Array = []
	for row in heights.size():
		var ring: Array[Vector3] = []
		for col in range(-4, 5):
			var i := absi(col)
			var y: float = heights[row][i]
			ring.append(Vector3(signf(col) * fractions[i] * half_width(y), y, depths[row][i] * depth))
		rings.append(ring)
	for row in rings.size() - 1:
		for col in 8:
			_quad(rings[row][col], rings[row + 1][col], rings[row + 1][col + 1], rings[row][col + 1], 0)
		# Back closure. No convex enclosure can represent the recessed eye sockets.
		var left: Vector3 = rings[row][0]
		var right: Vector3 = rings[row][8]
		var lower_left: Vector3 = rings[row + 1][0]
		var lower_right: Vector3 = rings[row + 1][8]
		_quad(right, lower_right, lower_left, left, 0)
	for row in [0, rings.size() - 1]:
		var anchor := Vector3(0, HAIR if row == 0 else CHIN, 0)
		for col in 8:
			_triangle(anchor, rings[row][col] if row == 0 else rings[row][col + 1], rings[row][col + 1] if row == 0 else rings[row][col], 0)
	# Structural edges only: omit triangulation diagonals and full-width mouth bands.
	for row in [0, 1, 3, 4]:
		for col in 8:
			if row == 4 and col in [3, 4]:
				continue
			secondary_edges.append([rings[row][col], rings[row][col + 1]])
	for col in [1, 3, 5, 7]:
		for row in rings.size() - 1:
			if col in [3, 5] and row < 1:
				continue
			secondary_edges.append([rings[row][col], rings[row + 1][col]])
	for col in [0, 8]:
		for row in rings.size() - 1:
			secondary_edges.append([rings[row][col], rings[row + 1][col]])
	for col in 8:
		secondary_edges.append([rings.back()[col], rings.back()[col + 1]])
	# Small lip mass, with the mouth seam exactly on the user's y=-R.
	var corner_l := Vector3(-half_width(MOUTH) * 0.46, MOUTH, 0.80 * depth)
	var corner_r := Vector3(half_width(MOUTH) * 0.46, MOUTH, 0.80 * depth)
	var seam := Vector3(0, MOUTH, 0.90 * depth)
	var upper := Vector3(0, MOUTH + 0.055, 0.88 * depth)
	var lower := Vector3(0, MOUTH - 0.055, 0.89 * depth)
	_triangle(corner_l, seam, upper, 0)
	_triangle(seam, corner_r, upper, 0)
	_triangle(corner_l, lower, seam, 0)
	_triangle(seam, lower, corner_r, 0)
	secondary_edges.append([corner_l, seam, 2])
	secondary_edges.append([seam, corner_r, 2])
	# Symmetric nose planes: bridge, side walls, tip, wings, and underside.
	var root_l := Vector3(-cut * 0.13, -0.09, 1.025 * depth)
	var root_r := Vector3(cut * 0.13, -0.09, 1.025 * depth)
	var tip := Vector3(0, -0.565, 1.20 * depth)
	var tip_l := tip + Vector3(-cut * 0.085, 0, 0)
	var tip_r := tip + Vector3(cut * 0.085, 0, 0)
	var base := Vector3(0, NOSE, 1.085 * depth)
	var wing_l := Vector3(-cut * 0.22, NOSE, 1.02 * depth)
	var wing_r := Vector3(cut * 0.22, NOSE, 1.02 * depth)
	var nose_l := Vector3(-cut * 0.13, -0.54, 1.12 * depth)
	var nose_r := Vector3(cut * 0.13, -0.54, 1.12 * depth)
	_quad(root_l, tip_l, tip_r, root_r, 1)
	_quad(root_l, wing_l, nose_l, tip_l, 1)
	_quad(tip_r, nose_r, wing_r, root_r, 1)
	_triangle(nose_l, wing_l, base, 1)
	_triangle(nose_l, base, tip_l, 1)
	_triangle(tip_l, base, tip_r, 1)
	_triangle(tip_r, base, nose_r, 1)
	_triangle(nose_r, base, wing_r, 1)
	for edge in [[root_l, root_r], [root_l, tip_l], [root_r, tip_r], [nose_l, tip_l], [nose_r, tip_r], [tip_l, tip_r], [wing_l, base], [base, wing_r], [nose_l, wing_l], [nose_r, wing_r]]:
		secondary_edges.append([edge[0], edge[1], 1])
	var body_faces := PackedVector3Array()
	var nose_faces := PackedVector3Array()
	for tri in secondary_triangles:
		for i in 3:
			if tri[4] == 1:
				nose_faces.append(tri[i])
			else:
				body_faces.append(tri[i])
	secondary_bvh.create_from_faces(body_faces)
	secondary_nose_bvh.create_from_faces(nose_faces)
	# Eyelid creases follow the recessed surface; they do not alter face width.
	for side in [-1.0, 1.0]:
		var upper_lid: Array[Vector3] = []
		var lower_lid: Array[Vector3] = []
		for i in 5:
			var u := float(i) / 4
			var x: float = side * cut * lerpf(0.22, 0.70, u)
			var arch := sin(PI * u)
			var y := -0.26 + 0.055 * arch
			for target in [0, 1]:
				var yy := y if target == 0 else -0.26 - 0.015 * arch
				var hit := secondary_bvh.intersect_ray(Vector3(x, yy, 4), Vector3.FORWARD)
				var p := Vector3(x, yy, 0.85 * depth) if hit.is_empty() else Vector3(hit.position)
				p.z += 0.003
				if target == 0:
					upper_lid.append(p)
				else:
					lower_lid.append(p)
		for i in 4:
			secondary_edges.append([upper_lid[i], upper_lid[i + 1], 2])
			secondary_edges.append([lower_lid[i], lower_lid[i + 1], 2])

func _triangle(a: Vector3, b: Vector3, c: Vector3, part: int, normal: Vector3 = Vector3.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.00000001:
		return
	secondary_triangles.append([a, b, c, n.normalized() if normal == Vector3.ZERO else normal, part])

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, part: int) -> void:
	var normal := ((b - a).cross(c - a) + (c - a).cross(d - a)).normalized()
	_triangle(a, b, c, part, normal)
	_triangle(a, c, d, part, normal)

func secondary_front(y: float) -> Vector3:
	var hit := secondary_bvh.intersect_ray(Vector3(0, y, 4), Vector3.FORWARD)
	return hit.position if not hit.is_empty() else front(y)

func secondary_section(y: float) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for tri in secondary_triangles:
		if tri[4] == 1:
			continue
		for i in 3:
			var a: Vector3 = tri[i]
			var b: Vector3 = tri[(i + 1) % 3]
			if absf(a.y - b.y) < 0.00001:
				continue
			var t := (y - a.y) / (b.y - a.y)
			if t < -0.00001 or t > 1.00001:
				continue
			var point := a.lerp(b, clampf(t, 0, 1))
			var unique := true
			for existing in points:
				if existing.distance_squared_to(point) < 0.000001:
					unique = false
					break
			if unique:
				points.append(point)
	var center := Vector3(0, y, 0.3 * depth)
	points.sort_custom(func(a: Vector3, b: Vector3): return atan2(a.z - center.z, a.x) < atan2(b.z - center.z, b.x))
	return points

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
