extends MeshInstance3D
## One triangulated surface is shared by rendering and collision.
## Small level areas are intentional camps/collection pads, not hidden flat colliders.

const SECTORS := 36
const RINGS := 12
var radius := 26.0
var island_id := ""
var faces := PackedVector3Array()
var min_height := 0.0
var max_height := 0.0

func build(center: Vector3, size: float, id: String, color: Color) -> void:
	position = center
	radius = size
	island_id = id
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in RINGS:
		for sector in SECTORS:
			var a := _vertex(ring, sector)
			var b := _vertex(ring + 1, sector)
			var c := _vertex(ring + 1, sector + 1)
			var d := _vertex(ring, sector + 1)
			_triangle(surface, a, b, c, color)
			if ring > 0:
				_triangle(surface, a, c, d, color)
	mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1
	material_override = material
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _vertex(ring: int, sector: int) -> Vector3:
	var angle := TAU * sector / SECTORS
	# Match the existing nine-sided island outline exactly.
	var boundary := radius * cos(PI / 9) / cos(fposmod(angle, TAU / 9) - PI / 9)
	var point := Vector2(cos(angle), sin(angle)) * boundary * ring / RINGS
	return Vector3(point.x, _height(point), point.y)

func _height(point: Vector2) -> float:
	var distance := point.length()
	var hills := 6.0 * exp(-point.distance_squared_to(Vector2(-radius * 0.55, -radius * 0.2)) / (radius * radius * 0.12))
	hills += 4.0 * exp(-point.distance_squared_to(Vector2(radius * 0.55, radius * 0.12)) / (radius * radius * 0.12))
	hills += 1.4 * exp(-point.distance_squared_to(Vector2(0, radius * 0.65)) / (radius * radius * 0.09))
	var height := hills * smoothstep(6, 12, distance) * (1 - smoothstep(radius * 0.75, radius, distance))
	if island_id == "camp":
		var world := point + Vector2(position.x, position.z)
		# A level workbench clearing and the existing wooden ramp remain accessible.
		height *= smoothstep(5, 11, world.distance_to(Vector2(6, 22)))
		height *= smoothstep(6, 11, world.distance_to(Vector2(14, 5)))
		if world.y > -11 and world.y < 43:
			height *= smoothstep(5.1, 11.1, absf(world.x + 6))
		height *= 1 - smoothstep(35, 39, world.y)
	# The terminal's interaction pad is offset from the island's center.
	if island_id == "summit":
		height *= smoothstep(3.5, 7, point.distance_to(Vector2(8, 5)))
	return height

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	# Godot front faces wind clockwise; collision and shading use the same vertices.
	var normal := (c - a).cross(b - a).normalized()
	var tint := color.lerp(Color("8f8a74"), smoothstep(0.15, 0.75, 1 - normal.y))
	tint = tint.lightened(0.025 * sin(a.x * 0.7 + b.z * 0.9))
	for point in [a, b, c]:
		faces.append(point)
		surface.set_color(tint)
		surface.set_normal(normal)
		surface.add_vertex(point)
		min_height = minf(min_height, point.y)
		max_height = maxf(max_height, point.y)

func height_at(world_x: float, world_z: float) -> float:
	var point := Vector2(world_x - position.x, world_z - position.z)
	# Barycentric sampling uses the actual triangles, not the analytic generation field.
	var angle := fposmod(atan2(point.y, point.x), TAU)
	var boundary := radius * cos(PI / 9) / cos(fposmod(angle, TAU / 9) - PI / 9)
	if point.length() > boundary + 0.001:
		return position.y
	var ring := clampi(floori(point.length() / boundary * RINGS), 0, RINGS - 1)
	var sector := clampi(floori(angle / TAU * SECTORS), 0, SECTORS - 1)
	var first := sector * 3 if ring == 0 else SECTORS * 3 + (ring - 1) * SECTORS * 6 + sector * 6
	for i in range(first, first + (3 if ring == 0 else 6), 3):
		var a := Vector2(faces[i].x, faces[i].z)
		var b := Vector2(faces[i + 1].x, faces[i + 1].z)
		var c := Vector2(faces[i + 2].x, faces[i + 2].z)
		var denominator := (b - a).cross(c - a)
		if absf(denominator) < 0.000001:
			continue
		var u := (point - a).cross(c - a) / denominator
		var v := (b - a).cross(point - a) / denominator
		if u >= -0.0001 and v >= -0.0001 and u + v <= 1.0001:
			return position.y + faces[i].y * (1 - u - v) + faces[i + 1].y * u + faces[i + 2].y * v
	return position.y
