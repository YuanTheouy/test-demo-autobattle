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
var style := 0
var patch_count := 0
var secondary_triangles: Array = []
var secondary_edges: Array = []
var secondary_bvh := TriangleMesh.new()
var secondary_nose_bvh := TriangleMesh.new()

func build(a: float, width: float, projection: float, head_style: int = 0) -> void:
	style = head_style
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
	# Match the supplied BASIC-plane plate: no eyelids, lips or cheek subdivisions.
	secondary_triangles.clear()
	secondary_edges.clear()
	patch_count = 0
	var girl := style == 1
	var brow_z := (0.98 if girl else 1.02) * depth
	var eye_z := (0.90 if girl else 0.86) * depth
	var eye_x := cut * (0.82 if girl else 0.76)
	var chin_top_y := -1.16
	var chin_top_width := minf(half_width(chin_top_y), chin_width * 1.18)
	var hair_l := Vector3(-cut * 0.66, HAIR, 0.78 * depth)
	var hair_r := Vector3(cut * 0.66, HAIR, 0.78 * depth)
	var hair_side_l := Vector3(-cut, HAIR, 0)
	var hair_side_r := Vector3(cut, HAIR, 0)
	var brow_l := Vector3(-cut * 0.64, 0, brow_z)
	var brow_r := Vector3(cut * 0.64, 0, brow_z)
	var brow_inner_l := Vector3(-cut * 0.15, 0, brow_z)
	var brow_inner_r := Vector3(cut * 0.15, 0, brow_z)
	var eye_inner_l := Vector3(-cut * 0.17, EYE, 0.94 * depth)
	var eye_inner_r := Vector3(cut * 0.17, EYE, 0.94 * depth)
	var eye_outer_l := Vector3(-eye_x, EYE, eye_z)
	var eye_outer_r := Vector3(eye_x, EYE, eye_z)
	var ear_top_l := Vector3(-cut, 0, 0)
	var ear_top_r := Vector3(cut, 0, 0)
	var ear_bottom_y := -sqrt(1 - cut * cut)
	var cheek_l := Vector3(-half_width(NOSE), NOSE, 0)
	var cheek_r := Vector3(half_width(NOSE), NOSE, 0)
	var jaw_y := lerpf(ear_bottom_y, CHIN, 0.42)
	var jaw_l := Vector3(-half_width(jaw_y), jaw_y, 0.06 * depth)
	var jaw_r := Vector3(half_width(jaw_y), jaw_y, 0.06 * depth)
	var chin_l := Vector3(-chin_top_width, chin_top_y, 0.76 * depth)
	var chin_r := Vector3(chin_top_width, chin_top_y, 0.76 * depth)
	var bottom_l := Vector3(-chin_width, CHIN, 0.68 * depth)
	var bottom_r := Vector3(chin_width, CHIN, 0.68 * depth)
	var back_l := Vector3(-chin_width, CHIN, 0)
	var back_r := Vector3(chin_width, CHIN, 0)
	_patch([hair_l, brow_l, brow_r, hair_r])
	_patch([hair_l, hair_side_l, ear_top_l, cheek_l, eye_outer_l, brow_l])
	_patch([hair_r, brow_r, eye_outer_r, cheek_r, ear_top_r, hair_side_r])
	_patch([brow_l, eye_outer_l, eye_inner_l, brow_inner_l])
	_patch([brow_inner_l, eye_inner_l, eye_inner_r, brow_inner_r])
	_patch([brow_inner_r, eye_inner_r, eye_outer_r, brow_r])
	# One broad lower-face plane: no mouth band, lip mass or cheek micro-facets.
	_patch([eye_outer_l, chin_l, chin_r, eye_outer_r, eye_inner_r, eye_inner_l])
	_patch([eye_outer_l, cheek_l, jaw_l, chin_l])
	_patch([eye_outer_r, chin_r, jaw_r, cheek_r])
	_patch([chin_l, bottom_l, bottom_r, chin_r])
	_patch([jaw_l, back_l, bottom_l, chin_l])
	_patch([jaw_r, chin_r, bottom_r, back_r])
	_patch([hair_side_l, hair_l, hair_r, hair_side_r], 0, false)
	_patch([hair_side_l, hair_side_r, ear_top_r, cheek_r, jaw_r, back_r, back_l, jaw_l, cheek_l, ear_top_l], 0, false, Vector3.FORWARD)
	_patch([bottom_l, back_l, back_r, bottom_r], 0, false, Vector3.DOWN)
	var nose_width := cut * (0.10 if girl else 0.16)
	var root_y := -0.22 if girl else -0.08
	var tip_y := -0.58
	var nose_z := (1.09 if girl else 1.20) * depth
	var root_l := Vector3(-nose_width * 0.65, root_y, 1.00 * depth)
	var root_r := Vector3(nose_width * 0.65, root_y, 1.00 * depth)
	var tip_l := Vector3(-nose_width * 0.72, tip_y, nose_z)
	var tip_r := Vector3(nose_width * 0.72, tip_y, nose_z)
	var wing_l := Vector3(-nose_width, NOSE, 1.00 * depth)
	var wing_r := Vector3(nose_width, NOSE, 1.00 * depth)
	_patch([root_l, tip_l, tip_r, root_r], 1)
	_patch([root_l, wing_l, tip_l], 1)
	_patch([root_r, tip_r, wing_r], 1)
	_patch([wing_l, wing_r, tip_r, tip_l], 1)
	# Deduplicate shared patch boundaries; do not expose render triangulation.
	var unique: Dictionary = {}
	var outline: Array = []
	for edge in secondary_edges:
		var key_a := str(edge[0].snapped(Vector3.ONE * 0.0001))
		var key_b := str(edge[1].snapped(Vector3.ONE * 0.0001))
		var key := key_a + key_b if key_a < key_b else key_b + key_a
		if not unique.has(key):
			unique[key] = true
			outline.append(edge)
	secondary_edges = outline
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

func _patch(points: Array[Vector3], part: int = 0, outline: bool = true, desired_normal: Vector3 = Vector3.ZERO) -> void:
	var normal := Vector3.ZERO
	for i in points.size():
		normal += points[i].cross(points[(i + 1) % points.size()])
	normal = normal.normalized()
	if normal.length_squared() < 0.5:
		return
	var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := normal.cross(u)
	var flat := PackedVector2Array()
	for p in points:
		flat.append(Vector2(p.dot(u), p.dot(v)))
	var indices := Geometry2D.triangulate_polygon(flat)
	if indices.is_empty():
		return
	patch_count += 1
	if desired_normal != Vector3.ZERO:
		normal = desired_normal
	elif normal.z < 0:
		normal = -normal
	for i in range(0, indices.size(), 3):
		_triangle(points[indices[i]], points[indices[i + 1]], points[indices[i + 2]], part, normal)
	if outline:
		for i in points.size():
			secondary_edges.append([points[i], points[(i + 1) % points.size()], part])

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
