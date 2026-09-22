extends "res://tests/playtest_runner.gd"

# Accelerated main-scene playthrough. All ecology, inventory and progression
# rules are shipped defaults; only wall-clock scheduling is accelerated.
var game
var view: SubViewport
var tick := 0
var initialized := false
var finishing := false
var last_placement_second := -1
var captured_act := ""
var output := "/private/tmp/biome-v07-full-run"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	view = SubViewport.new()
	view.size = Vector2i(1280, 800)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://game/main.tscn").instantiate()
	view.add_child(game)
	var preview := TextureRect.new()
	preview.texture = view.get_texture()
	preview.size = Vector2(1280, 800)
	root.add_child(preview)

func _process(_delta: float) -> bool:
	if finishing:
		return false
	if not initialized:
		game.set_process(false)
		initialized = true
		game.systems.set_speed(1.0)
	var systems = game.systems
	for step_index in range(10):
		if systems.supply_pending: game.hud.choose_supply_shortcut(_choose_supply(systems, "deliberate"))
		var second := int(systems.simulation.simulation_time)
		if not systems.supply_pending and second != last_placement_second:
			_place_inventory(systems, "deliberate")
			last_placement_second = second
		game._process(0.1)
		tick += 1
		var act: String = systems.run_director.current_milestone_id()
		if act != captured_act:
			captured_act = act
			_capture("act_%d" % systems.run_director.milestone_index)
			print("Rendered act %s at %.1fs" % [act, systems.simulation.simulation_time])
		if systems.is_completed():
			finishing = true
			_finish_run()
			return false
		if systems.simulation.simulation_time >= 800.0 or systems.is_game_over():
			_capture("stopped")
			FileAccess.open(output + "/result.json", FileAccess.WRITE).store_string(JSON.stringify({"completed": false, "progress": systems.current_objective_progress()}, "  "))
			quit(1)
			return false
	return false

func _finish_run() -> void:
	# Text, row replacement, layout and ending tweens use deferred scene work.
	# A forced draw inside the same simulation callback can still show old text.
	await create_timer(0.4).timeout
	await process_frame
	_capture("completion")
	game.hud._on_continue_pressed()
	var systems = game.systems
	var before: float = systems.simulation.simulation_time
	game._process(0.5)
	game.hud.refresh()
	await create_timer(0.4).timeout
	await process_frame
	_capture("sandbox")
	var ok: bool = systems.run_director.run_state == RunDirector.STATE_SANDBOX and systems.simulation.simulation_time > before and game.hud.objective_title.text == "A living ecosystem" and game.hud.objective_progress_view._current_row_ids() == ["observation"]
	FileAccess.open(output + "/result.json", FileAccess.WRITE).store_string(JSON.stringify({"completed": true, "simulation_time": before, "sandbox_verified": ok, "rabbits": systems.simulation.rabbits.size(), "foxes": systems.simulation.foxes.size()}, "  "))
	print("Rendered completion and sandbox verified: %s at %.1fs" % [ok, before])
	quit(0 if ok else 1)

func _capture(label: String) -> void:
	game.hud.refresh()
	RenderingServer.force_draw(false, 1.0 / 60.0)
	view.get_texture().get_image().save_png(output + "/" + label + ".png")
