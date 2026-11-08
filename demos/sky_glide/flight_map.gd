extends Control

var world: Node3D
var refresh := 0.0
const TEXT = Color("f3edda")

func _ready() -> void:
	position = Vector2(270, 170)
	size = Vector2(900, 540)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(delta: float) -> void:
	refresh += delta
	if visible and refresh > 0.08:
		refresh = 0
		queue_redraw()

func project(at: Vector3) -> Vector2:
	return Vector2(90 + (30 - at.z), 260 + at.x * 1.65)

func _draw() -> void:
	if not is_instance_valid(world):
		return
	var font := ThemeDB.fallback_font
	draw_style_box(_style(), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(30, 44), "航图 / SKY ATLAS", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, TEXT)
	draw_string(font, Vector2(30, 77), "M 收起 · 地图打开时仍在飞行 · 标注为岛面海拔", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("a8c8c3"))
	draw_string(font, Vector2(60, 122), "01  草海群岛", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("c8dda3"))
	draw_string(font, Vector2(520, 122), "02  石柱群岛", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("8ddbd3"))
	var start := project(Vector3(0, 0, -180))
	var end := project(Vector3(20, 0, -445))
	draw_dashed_line(start, end, Color("dfbd79"), 2, 7)
	for thermal in world.thermals:
		var center: Vector2 = thermal.center
		var point := project(Vector3(center.x, 0, center.y))
		draw_arc(point, float(thermal.radius) * 0.46, 0, TAU, 32, Color(0.46, 0.8, 0.72, 0.45), 1.5)
		draw_string(font, point + Vector2(-4, 5), "↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("92d9c2"))
	for island in world.islands:
		var at: Vector3 = island.pos
		var point := project(at)
		var color := Color("a8c785") if island.region == 1 else Color("82cabe")
		draw_circle(point, float(island.radius) * 0.4, color)
		if world.collected.has(island.id):
			draw_arc(point, float(island.radius) * 0.4 + 4, 0, TAU, 24, TEXT, 1.5)
		draw_string(font, point + Vector2(-28, 29), island.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		draw_string(font, point + Vector2(-15, 46), "%d m" % roundi(at.y), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("a8c8c3"))
	var player = world.player
	var point := project(player.position)
	draw_circle(point, 6, Color("ffcf79"))
	var direction := Vector2(cos(player.heading), sin(player.heading))
	draw_line(point, point + direction * 18, Color("ffcf79"), 3)
	draw_string(font, Vector2(30, 465), "第一关：轻木岛 + 翼膜岛 + 遗迹图纸 → 返回起风营地，按 E 制作远行翼", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)
	draw_string(font, Vector2(30, 495), "第二关：借高空风道升到约 165 m → 远渡石柱群岛 → 点亮最远处信标", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)

func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.15, 0.19, 0.97)
	style.set_corner_radius_all(18)
	style.border_color = Color("739e9b")
	style.set_border_width_all(1)
	return style
