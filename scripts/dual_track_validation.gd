extends SceneTree
const Sim = preload("res://scripts/dual_track_simulation.gd")
func _initialize(): call_deferred("run_checks")
func play(profile: Dictionary, kind: int, a: Vector2i, b: Vector2i) -> Dictionary:
	var sim := Sim.new()
	sim.reset([profile, Sim.enemy_profile(kind)], [a, b])
	return sim.run()
func semantics() -> Array:
	var p := Sim.player_profile()
	p.move = {"condition":"无","yes":["接敌"],"no":["站立"]}
	p.weapon.condition = "无"
	var opponent := Sim.enemy_profile(0)
	var sim := Sim.new()
	sim.reset([p,opponent],[Vector2i(0,0),Vector2i(2,2)])
	var before := sim.units.duplicate(true)
	var morale := sim.morale.duplicate()
	sim.calculate()
	assert(sim.units == before and sim.morale == morale, "Planning must not publish future damage or cells")
	sim.tick()
	assert(sim.units[0].pose == "移动" and sim.units[0].weapon_action == "瞄准" and sim.units[0].cell == Vector2i(0,0))
	sim.tick()
	assert(sim.units[0].cell != Vector2i(0,0) and sim.units[0].weapon_action == "击发" and sim.units[0].pose == "移动")
	var a := Sim.new()
	a.reset([Sim.player_profile(),Sim.enemy_profile(3)],[Vector2i(0,1),Vector2i(1,0)])
	var b := Sim.new()
	b.decision_order = [1,0]
	b.reset([Sim.player_profile(),Sim.enemy_profile(3)],[Vector2i(0,1),Vector2i(1,0)])
	assert(a.run().history == b.run().history, "Both tracks and both teams must use the same old snapshot")
	var stationary := Sim.enemy_profile(0)
	sim.reset([stationary,stationary],[Vector2i(0,0),Vector2i(2,2)])
	sim.morale = [1,1]
	sim.next_segment = sim.calculate()
	sim.tick()
	sim.tick()
	assert(sim.finished and sim.beat == 2 and sim.morale == [0,0] and sim.winner == -1 and sim.units.size() == 2)
	var ended := sim.history.duplicate(true)
	sim.tick()
	assert(sim.history == ended, "Encounter ends once; no post-result action")
	var quiet := Sim.player_profile()
	quiet.weapon = {"condition":"无","yes":["等待"],"no":["等待"]}
	sim.reset([quiet,quiet],[Vector2i(0,0),Vector2i(2,2)],[Vector2i(1,1)])
	var result := sim.run()
	assert(result.beats == 18 and result.shots == [0,0] and result.morale == [3,3])
	return ["independent movement+aim+fire", "two-beat crossing and public grid endpoints", "planning does not publish future damage", "same snapshot and team order independence", "simultaneous morale loss and zero-morale stop; bots stay visible", "18-beat bound even if nobody attacks", "obstacles and occupancy stay legal"]

func verify_navigation() -> void:
	change_scene_to_file("res://puzzle_arena.tscn")
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == "res://puzzle_arena.tscn")
	var menu: MenuButton
	for child in current_scene.get_children():
		if child is MenuButton and child.text == "载入示范": menu = child
	assert(menu != null)
	menu.get_popup().id_pressed.emit(2)
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == "res://dual_track_arena.tscn")
	var back: Button
	for child in current_scene.get_children():
		if child is Button and child.text == "← 返回原型": back = child
	assert(back != null)
	back.pressed.emit()
	await process_frame
	await process_frame
	assert(current_scene.scene_file_path == "res://puzzle_arena.tscn")

func run_checks():
	var checks := semantics()
	var candidates: Array = []
	for condition in Sim.CONDITIONS:
		var p := Sim.player_profile()
		p.weapon.condition = condition
		candidates.append(p)
	var examples: Array = []
	var count := 0
	for x in range(3):
		for y in range(3):
			for xx in range(3):
				for yy in range(3):
					var a := Vector2i(x,y)
					var b := Vector2i(xx,yy)
					if a == b: continue
					var results: Array = []
					for p in candidates:
						var kinds: Array = []
						for kind in range(4):
							kinds.append(play(p,kind,a,b))
							count += 1
						results.append(kinds)
					for i in range(candidates.size()):
						for j in range(i+1,candidates.size()):
							for first in range(4):
								for second in range(4):
									if first == second: continue
									var aa: Dictionary = results[i][first]
									var ab: Dictionary = results[j][first]
									var ba: Dictionary = results[i][second]
									var bb: Dictionary = results[j][second]
									var d1: int = aa.morale[0]-aa.morale[1]-(ab.morale[0]-ab.morale[1])
									var d2: int = bb.morale[0]-bb.morale[1]-(ba.morale[0]-ba.morale[1])
									if d1 > 0 and d2 > 0 and aa.winner == 0 and bb.winner == 0 and i == 3 and aa.concurrent[0] > 0 and bb.concurrent[0] > 0:
										examples.append({"spawns":[a,b],"conditions":[Sim.CONDITIONS[i],Sim.CONDITIONS[j]],"enemies":[first,second],"margins":[d1,d2],"results":[aa,ab,ba,bb]})
	examples.sort_custom(func(a,b): return a.margins[0]+a.margins[1] > b.margins[0]+b.margins[1])
	assert(not examples.is_empty(), "Need an actual one-cell reversal, not only a hypothetical example")
	print("SEARCH ",count," encounters, reversals ",examples.size())
	await verify_navigation()
	checks.append("actual demo menu enters dual-track scene; actual back button returns to legacy scene")
	var report := {"searched":count,"checks":checks,"player_profile":Sim.player_profile(),"enemies":[Sim.enemy_profile(0),Sim.enemy_profile(1),Sim.enemy_profile(2),Sim.enemy_profile(3)],"reversal_count":examples.size(),"examples":examples.slice(0,1)}
	var f := FileAccess.open("res://reports/dual-track-search.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	for example in examples.slice(0,1):
		print("PICK ",example.spawns," ",example.conditions," enemies ",example.enemies," margins ",example.margins)
		for r in example.results: print("  ",r.winner," ",r.morale," shots ",r.shots," hits ",r.hits," concurrent ",r.concurrent)
	quit()
