extends SceneTree

# Controlled art and motion fixtures through the production main scene.
# Capture timing is prescribed; this is not a frame-rate benchmark.
var game
var viewport: SubViewport
var frame := 0
var output := "/private/tmp/biome-art-motion-2026-09-22"
var telemetry: FileAccess
var maps_only := false
var capture_busy := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	maps_only = args.size() > 1 and args[1] == "maps"
	DirAccess.make_dir_recursive_absolute(output)
	telemetry = FileAccess.open(output + "/telemetry.jsonl", FileAccess.WRITE)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = load("res://game/main.tscn").instantiate()
	viewport.add_child(game)
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.size = Vector2(1280, 800)
	root.add_child(preview)

func _process(_delta: float) -> bool:
	if not capture_busy:
		capture_busy = true
		_step.call_deferred()
	return false

func _step() -> void:
	if frame == 0:
		game.set_process(false)
		game.camera.position_smoothing_enabled = false
		game.systems.supply_time_remaining = 9999.0
		game.systems.set_speed(0.0)
		for point in [Vector2(-130, 0), Vector2(130, 70), Vector2(-100, -100)]:
			var p := _ground_near(point)
			game.systems.simulation.add_plant("berry_bush", p)
			game.systems.simulation.add_rabbit(_ground_near(p + Vector2(25, 0)))
			game.systems.simulation.add_rabbit(_ground_near(p + Vector2(0, 25)), "birth")
		game.systems.simulation.add_fox(_ground_near(Vector2(110, -60)))
		game.world_view.spawn_effects.clear()
		game.world_view.ambient_effects.clear()
		game.hud.refresh()
	if frame == 3:
		await _capture("opening-hud")
		game.hud.visible = false
	if frame == 5:
		await _capture("opening-map")
		game.systems.simulation.world_radius = 744.0
		game.world_view.display_radius = 744.0
		game.camera.zoom = Vector2.ONE * game._fit_zoom_for_radius(744.0)
		game.world_view.set_camera_zoom(game.camera.zoom.x)
	if frame == 7:
		await _capture("expanded-map")
		game.camera.position = _ground_near(Vector2(-100, -40))
		game.camera.zoom = Vector2.ONE * 1.90
		game.world_view.set_camera_zoom(1.90)
	if frame == 9:
		await _capture("detail-map")
		if maps_only:
			telemetry.close()
			print("Map fixtures captured: " + output)
			quit()
			return
		_prepare_motion()
	if frame >= 10 and frame < 250:
		var motion_frame := frame - 10
		game.systems.set_speed(1.0 if motion_frame < 120 else 3.0)
		game.systems.advance(1.0 / 30.0)
		game.world_view.process_visual(1.0 / 30.0)
		await _capture("motion_%04d" % motion_frame)
		var animals := []
		for source in [game.systems.simulation.rabbits, game.systems.simulation.foxes]:
			for a in source.values():
				animals.append({"id": a["id"], "kind": a["type"], "behavior": a["behavior"], "position": a["position"], "velocity": a["velocity"], "phase": a.get("gait_phase", null), "pose": game.world_view.AnimalMotion.sample(a, game.systems.interpolation_alpha(), game.systems.simulation.simulation_time, 0.1)})
		telemetry.store_line(JSON.stringify({"frame": motion_frame, "simulation_time": game.systems.simulation.simulation_time, "speed": game.systems.simulation_speed, "animals": animals}))
	if frame == 250:
		game.systems.simulation.rabbits.clear()
		game.systems.simulation.foxes.clear()
		game.systems.simulation.plants.clear()
		var id: int = game.systems.simulation.add_fox(Vector2.ZERO)
		var fox: Dictionary = game.systems.simulation.foxes[id]
		fox["velocity"] = Vector2.ZERO
		fox["previous_velocity"] = Vector2.ZERO
		fox["hunger"] = 0.0
		game.world_view.spawn_effects.clear()
		game.world_view.ambient_effects.clear()
		game.systems.set_speed(0.0)
		game.camera.zoom = Vector2.ONE * 1.90
		game.world_view.set_camera_zoom(1.90)
	if frame >= 252 and frame <= 282:
		game.systems.advance(1.0 / 30.0)
		game.world_view.process_visual(1.0 / 30.0)
		if frame in [252, 267, 282]:
			await _capture("paused-fox-%d" % frame)
			var fox: Dictionary = game.systems.simulation.foxes.values()[0]
			telemetry.store_line(JSON.stringify({"paused_frame": frame, "simulation_time": game.systems.simulation.simulation_time, "visual_clock": game.world_view.visual_clock, "velocity": fox["velocity"], "pose": game.world_view.AnimalMotion.sample(fox, game.systems.interpolation_alpha(), game.systems.simulation.simulation_time, 0.1)}))
	if frame == 283:
		telemetry.close()
		print("Art and motion capture complete: " + output)
		quit()
	frame += 1
	capture_busy = false

func _prepare_motion() -> void:
	var sim = game.systems.simulation
	sim.rabbits.clear()
	sim.foxes.clear()
	sim.plants.clear()
	sim.config["terrain"]["stream"]["enabled"] = false
	sim.config["world"]["forest_patch_count"] = 0
	sim.config["terrain"]["thicket"]["patch_count"] = 0
	sim.terrain = TemperateWildsTerrain.new(sim.config, 240817)
	sim.forest_patches = sim.terrain.woodland_patches
	sim.world_radius = 744.0
	game.world_view.details.clear()
	game.camera.position = Vector2.ZERO
	game.camera.zoom = Vector2.ONE * 1.38
	game.world_view.set_camera_zoom(1.38)
	sim.add_plant("berry_bush", Vector2(70, -60))
	var rabbit: int = sim.add_rabbit(Vector2(-150, -60))
	sim.rabbits[rabbit]["hunger"] = 32.0
	var fox: int = sim.add_fox(Vector2(-50, 140))
	sim.foxes[fox]["hunger"] = 0.0
	game.world_view.spawn_effects.clear()
	game.world_view.ambient_effects.clear()

func _capture(label: String) -> void:
	game.world_view.queue_redraw()
	# CanvasItem rebuilds draw commands after the frame callback. Keep simulation
	# advancement blocked until those commands reach this capture's viewport.
	await process_frame
	await process_frame
	RenderingServer.force_draw(false, 1.0 / 30.0)
	var captured := viewport.get_texture().get_image()
	if label.begins_with("motion_"):
		captured.save_jpg(output + "/" + label + ".jpg", 0.96)
	else:
		captured.save_png(output + "/" + label + ".png")

func _ground_near(preferred: Vector2) -> Vector2:
	for ring in range(15):
		for spoke in range(24):
			var candidate := preferred + Vector2.from_angle(float(spoke) / 24.0 * TAU) * float(ring) * 12.0
			if game.systems.simulation.is_position_valid(candidate): return candidate
	return Vector2.ZERO
