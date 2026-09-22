extends SceneTree

# Controlled normal-scale movement/feeding/rest capture using the actual scene.
# Offline 30 Hz frames make the exported clip's timing independent of PNG cost.
var game
var view: SubViewport
var frame := 0
var output := "/private/tmp/biome-v07-gait-final"
var capture_log: FileAccess

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	capture_log = FileAccess.open(output + "/captures.jsonl", FileAccess.WRITE)
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
	if frame == 0:
		game.set_process(false)
		game.systems.supply_time_remaining = 9999.0
		var sim = game.systems.simulation
		sim.config["terrain"]["stream"]["enabled"] = false
		sim.config["world"]["forest_patch_count"] = 0
		sim.config["terrain"]["thicket"]["patch_count"] = 0
		sim.terrain = TemperateWildsTerrain.new(sim.config, 240817)
		sim.forest_patches = sim.terrain.woodland_patches
		game.world_view.details.clear()
		game.hud.visible = false
		game.camera.position = Vector2.ZERO
		game.camera_zoom_target = 1.25
		game.camera.zoom = Vector2.ONE * 1.25
		sim.add_plant("berry_bush", Vector2(60.0, 0.0))
		var id: int = sim.add_rabbit(Vector2(-100.0, 0.0))
		sim.rabbits[id]["hunger"] = 30.0
		game.hud.show_animal("rabbit", id)
	game.systems.set_speed(1.0 if frame < 180 else 3.0)
	game._process(1.0 / 30.0)
	RenderingServer.force_draw(false, 1.0 / 30.0)
	view.get_texture().get_image().save_png(output + "/frame_%05d.png" % frame)
	var rabbit: Dictionary = game.systems.simulation.rabbits.values()[0]
	capture_log.store_line(JSON.stringify({"frame": frame, "t": game.systems.simulation.simulation_time, "speed": game.systems.simulation_speed, "behavior": rabbit["behavior"], "gait_phase": rabbit["gait_phase"], "position": rabbit["position"]}))
	frame += 1
	if frame >= 360:
		capture_log.close()
		print("Controlled gait clip: 360 frames at 30 Hz; first 6 seconds at 1x, then 6 seconds at 3x.")
		quit()
	return false
