extends "res://tests/playtest_runner.gd"

# Actual main scene, normal rules, verified SubViewport capture. This is a
# rendered automated observation, not a human usability test or FPS benchmark.
var game
var capture_view: SubViewport
var frame := 0
var capture_index := 0
var last_action := -1
var directory := "/private/tmp/biome-v07-visual"
var telemetry: FileAccess
var capture_duration := 120.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): directory = args[0]
	DirAccess.make_dir_recursive_absolute(directory)
	telemetry = FileAccess.open(directory + "/captures.jsonl", FileAccess.WRITE)
	capture_view = SubViewport.new()
	capture_view.size = Vector2i(1280, 800)
	capture_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture_view)
	game = load("res://game/main.tscn").instantiate()
	capture_view.add_child(game)
	var preview := TextureRect.new()
	preview.texture = capture_view.get_texture()
	preview.size = Vector2(1280, 800)
	root.add_child(preview)

func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3: return false
	var systems = game.systems
	var sim = systems.simulation
	var t: float = sim.simulation_time
	if systems.supply_pending: game.hud.choose_supply_shortcut(_choose_supply(systems, "deliberate"))
	if not systems.supply_pending: systems.set_speed(1.0 if t < 20.0 else 3.0)
	if int(t) != last_action:
		_place_inventory(systems, "deliberate")
		last_action = int(t)
	if not sim.rabbits.is_empty():
		var id: int = sim.rabbits.keys()[0]
		game.camera.position = sim.rabbits[id]["position"] if t < 70.0 else Vector2.ZERO
		game.camera_zoom_target = 1.55 if t < 70.0 else 0.90
		if t < 70.0:
			game.world_view.set_public_selection("rabbit", id)
			game.hud.show_animal("rabbit", id)
		else: game.hud.hide_animal()
	if frame % 3 == 0:
		RenderingServer.force_draw(false, 1.0 / 60.0)
		var captured := capture_view.get_texture().get_image()
		captured.save_png(directory + "/frame_%05d.png" % capture_index)
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		hasher.update(captured.get_data())
		telemetry.store_line(JSON.stringify({"frame": capture_index, "t": t, "speed": systems.simulation_speed, "hash": hasher.finish().hex_encode(), "act": systems.run_director.current_milestone_id()}))
		telemetry.flush()
		capture_index += 1
	if t >= capture_duration or systems.is_game_over():
		telemetry.close()
		print("Rendered observation complete: %d frames, %.1f simulation seconds." % [capture_index, t])
		quit()
	return false
