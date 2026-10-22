extends "res://scripts/beat_view.gd"

func draw_wall(state: Dictionary, alpha: float) -> void:
	# Grid-aligned solid filler; low tops keep the front 3x3 unobstructed.
	for x in range(int(state.rect.position.x / 80), int(state.rect.end.x / 80)):
		for y in range(int(state.rect.position.y / 80), int(state.rect.end.y / 80)):
			box(Vector2(x, y) * 80, Vector2(80, 80), 22, Color("344958"), alpha)
