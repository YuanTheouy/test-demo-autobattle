extends RefCounted
const Sim = preload("res://scripts/squad_simulation.gd")

static func run(game) -> void:
	assert(not game.running and game.sim.units.size() == 8 and game.sim.squads.size() == 4)
	game.editor.show_page(0)
	game.selected = 1; game.member_index = 0; game.sync_editor()
	game.task_picker.item_selected.emit(2)
	assert(game.settings.tasks[1] == "支援A队" and game.sim.config.tasks[1] == "支援A队")
	game.posture_picker.item_selected.emit(1)
	assert(game.settings.postures[1] == "保持距离")
	game.editor.show_page(1)
	assert(game.editor.tabs.tab_count == 4 and game.editor.widgets.has("else.timeout/skill"))
	assert(not game.editor.widgets.has("pp0/skill"))
	var choice: OptionButton = game.editor.widgets["then/skill"]
	choice.item_selected.emit(choice.get_item_index(2)) # 突刺
	assert(game.settings.programs[2]["then"].skill == "突刺")
	var condition: OptionButton = game.editor.widgets["/condition"]
	condition.item_selected.emit(Sim.CONDITIONS.find("目标正在施法"))
	assert(game.settings.programs[2].condition == "目标正在施法")
	assert(not game.settings.programs[2].has("conditions"))
	assert(not game.editor.widgets.has("/conditions1") and not game.editor.widgets.has("else/conditions1"))
	var node_type: OptionButton = game.editor.widgets["else/type"]
	node_type.item_selected.emit(node_type.item_count - 1) # Explicit second IF, rather than another priority rule.
	assert(game.settings.programs[2]["else"].type == "if")
	assert(game.editor.widgets.has("else.then/skill") and game.editor.widgets.has("else.then/type"))
	var inner_type: OptionButton = game.editor.widgets["else.then/type"]
	for item in inner_type.item_count: assert(inner_type.get_item_text(item) != "IF · 判断")
	game.editor.show_page(2)
	assert(not game.editor.widgets.has("then/skill") and game.editor.widgets.has("pp0/skill"))
	game.selected = 0; game.member_index = 0; game.sync_editor()
	var pp: OptionButton = game.editor.widgets["pp0/condition1"]
	pp.item_selected.emit(Sim.conditions_for("援护").find("保留1PP"))
	assert(game.settings.pp[0][0][1] == "保留1PP")
	var test_path := "user://_squad-flow-template-test.json"
	var original: Dictionary = game.settings.programs[0].duplicate(true)
	game.save_template(test_path)
	game.settings.programs[0] = Sim.action("留空")
	game.load_template(test_path)
	assert(game.settings.programs[0] == original)
	var legacy := FileAccess.open(test_path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"盾兵": {"rules": [["牵制", "无", "无"]], "pp": []}})); legacy.close()
	game.load_template(test_path)
	assert(game.settings.programs[0] == original and "不兼容" in game.editor.note.text)
	game.save_template(test_path)
	game.selected = 1; game.member_index = 0; game.sync_editor(); game.save_template(test_path)
	assert(game.templates.has("盾兵") and game.templates.has("刺客"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path)); game.templates.clear()
	game.settings = Sim.defaults(); game.restart(); game.sync_editor()
	game.editor.show_page(1)
	var duration: OptionButton = game.editor.widgets["else/seconds"]
	assert(duration.get_item_text(duration.selected) == "1秒", "WAIT duration must display its actual configured value")
	game.step_second()
	assert(game.sim.clock == 0)
	for frame in range(61): game._process(1.0 / 60.0)
	assert(is_equal_approx(game.sim.clock, 1.0) and game.step_ticks == 0)
	game.restart()
	var baseline := Sim.new(); baseline.reset(game.settings)
	while not baseline.finished: baseline.tick()
	for rate in [0.5, 1.0, 2.0]:
		game.restart(); game.speed = rate; game.running = true
		for frame in range(12000):
			game._process(1.0 / 60.0)
			if game.sim.finished: break
		assert(game.sim.summary() == baseline.summary())
	var final_state: Dictionary = game.live_sim.summary()
	game.editor.show_page(3); game.refresh_labels()
	game.timeline.value_changed.emit(200)
	assert(game.replaying and is_equal_approx(game.sim.clock, 10.0))
	assert(game.sim.units == game.history[200].units)
	game._process(0.1)
	assert(game.live_sim.summary() == final_state and game.sim.clock == 10.0)
	var event_index := -1
	for index in game.event_ids.size():
		if game.live_sim.events[game.event_ids[index] - 1].kind == "连携": event_index = index; break
	assert(event_index >= 0)
	game.event_picker.select(event_index)
	game.event_picker.item_selected.emit(event_index)
	assert("牵制" in "\n".join(game.causal_lines(game.selected_event)))
	assert("真实来源链" in game.audit_text.text and "IF" in game.audit_text.text)
	game.editor.show_page(1)
	assert(game.editor.widgets["then/skill"].disabled)
	var saved: Array = game.settings.programs.duplicate(true)
	game.editor.edit_node("then", "skill", "留空")
	assert(game.settings.programs == saved, "historical review cannot edit live tactics")
	game.return_live()
	assert(not game.replaying and game.sim.summary() == final_state)
	game.editor.show_page(3)
	game.browse(200)
	game.restart()
	assert(not game.replaying and game.sim.clock == 0 and game.history.size() == 1)
	game.editor.show_page(1)
	assert(not game.editor.widgets["then/skill"].disabled)
	var file := FileAccess.open("res://reports/squad-ui-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": true, "checks": ["four isolated tagged pages", "real task/posture controls", "single condition per IF and direct action editing", "WAIT configuration displayed accurately", "PP-only IF editor", "version3 single-condition program template save/load preserves other roles", "one-second playback before result", "0.5/1/2 speed identical", "timeline/event navigation", "historical state isolated and controls locked", "restart from review returns to editable live setup", "actual branch and state causality audit"], "result": final_state.result, "time": final_state.time}, "\t"))
	print("SQUAD UI PASS: isolated pages, real IF/ELSE editing, generic WAIT, PP, templates and read-only review")
