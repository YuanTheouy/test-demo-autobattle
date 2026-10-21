extends Button
var game
var uid := 0

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	for style in ["normal", "hover", "pressed", "disabled", "focus"]: add_theme_stylebox_override(style, StyleBoxEmpty.new())
	pressed.connect(func(): game.begin_ultimate_aim(uid))

func _process(_delta: float) -> void:
	if game == null or game.units.size() <= uid: return
	var u: Dictionary = game.units[uid]
	disabled = not game.started or u.hp <= 0 or u.ult_charge < 100 or u.phase == "大招蓄力"
	tooltip_text = game.ultimate_name(uid) + ("：45伤害，宽幅光束，墙体可挡。" if uid == 0 else "：沿方向三连轰炸，每枚22伤害，可越过墙体。") + "每12秒充满，释放需70精力且公共CD结束；点击头像后慢放瞄准，左键确认，恢复未就绪则排队并保留精力；再次点击头像取消排队。右键/Esc取消瞄准。"
	queue_redraw()

func _draw() -> void:
	if game == null or game.units.size() <= uid: return
	var u: Dictionary = game.units[uid]
	var p := Vector2(45, 35)
	var ready: bool = u.ult_charge >= 100 and u.hp > 0
	var color := Color("81ddff") if ready else Color("587f9b")
	if u.hp <= 0: color = Color("48525e")
	draw_circle(p, 27, Color("142b3c"))
	draw_circle(p + Vector2(0, 4), 16, Color("20648e"))
	draw_circle(p - Vector2(0, 3), 12, Color("52b6ff") if u.hp > 0 else color)
	draw_line(p + Vector2(0, 2), p + Vector2(11, -12), Color("cff5ff"), 6, true)
	draw_arc(p, 32, -PI / 2, TAU - PI / 2, 64, Color("273b4b"), 4, true)
	if u.ult_charge > 0: draw_arc(p, 32, -PI / 2, -PI / 2 + TAU * u.ult_charge / 100, 64, color, 4, true)
	if game.ultimate_aim == uid or (is_hovered() and ready): draw_arc(p, 37, 0, TAU, 64, Color("f5d78b"), 2, true)
	var status: String = "已倒下" if u.hp <= 0 else ("已排队" if u.ult_pending else ("瞄准中" if game.ultimate_aim == uid else ("点击释放" if ready else "%d%%" % u.ult_charge)))
	draw_string(game.font, Vector2(16, 82), "蓝%d · %s" % [uid + 1, status], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
	draw_string(game.font, Vector2(18, 99), game.ultimate_name(uid), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c9e6f3"))
