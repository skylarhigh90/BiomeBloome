extends SceneTree

## Manual visual-inspection harness. It uses the real main scene, WorldView,
## camera, and 1280×800 project viewport. Run without --headless:
##   godot --path . --script tests/plant_ecology_visual_runner.gd -- states /tmp/states.png
##   godot --path . --script tests/plant_ecology_visual_runner.gd -- expanded /tmp/expanded.png
##   godot --path . --script tests/plant_ecology_visual_runner.gd -- habitat /tmp/habitat.png
##   godot --path . --script tests/plant_ecology_visual_runner.gd -- redistribution /tmp/redistribution.png

var game
var frames := 0
var mode := "states"
var output_path := "/private/tmp/biome-plant-ecology.png"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		mode = str(args[0])
	if args.size() > 1:
		output_path = str(args[1])
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		_prepare_scene()
	if frames == 12:
		var image := root.get_texture().get_image()
		var error := image.save_png(output_path)
		if error != OK:
			printerr("Plant ecology visual capture failed: %s" % error_string(error))
			quit(1)
			return false
		print("Plant ecology visual capture saved: %s" % output_path)
		quit(0)
	return false

func _prepare_scene() -> void:
	game.systems.set_speed(0.0)
	game.systems.supply_time_remaining = 9999.0
	game.systems.simulation.rabbits.clear()
	game.systems.simulation.foxes.clear()
	game.systems.simulation.plants.clear()
	game.systems.simulation.rebuild_spatial_index()
	game.world_view.spawn_effects.clear()
	game.world_view.ambient_effects.clear()
	if mode == "redistribution":
		_prepare_redistribution()
	elif mode == "habitat":
		_prepare_habitat_comparison()
	else:
		_prepare_state_gallery()
		if mode == "expanded":
			game.systems.simulation.world_radius = float(game.config["world"]["maximum_radius"])
			game.world_view.display_radius = game.systems.simulation.world_radius
			game.camera.zoom = Vector2.ONE * 0.42
			game.camera_zoom_target = 0.42
	print("Visual mode '%s' at camera zoom %.2f." % [mode, game.camera.zoom.x])
	game.world_view.queue_redraw()

func _prepare_state_gallery() -> void:
	var states := ["abundant", "healthy", "sparse", "depleted", "recovering"]
	var ratios := [1.0, 0.52, 0.22, 0.03, 0.22]
	var x_positions := [-240.0, -120.0, 0.0, 120.0, 240.0]
	for row in range(2):
		var plant_type := "carrot_patch" if row == 0 else "berry_bush"
		var y := -82.0 if row == 0 else 82.0
		for index in range(states.size()):
			var position := _ground_near(Vector2(x_positions[index], y))
			var plant_id: int = game.systems.simulation.add_plant(plant_type, position, "visual_test")
			var plant: Dictionary = game.systems.simulation.plants[plant_id]
			# Hold habitat constant across the state row so only current stock changes.
			plant["habitat_capacity_factor"] = 1.0
			if states[index] in ["depleted", "recovering"]:
				plant["food"] = plant["max_food"] * 0.03
				game.systems.simulation._update_plant_ecology_state(plant)
				if states[index] == "recovering":
					plant["food"] = plant["max_food"] * ratios[index]
					game.systems.simulation._update_plant_ecology_state(plant)
			else:
				plant["food"] = plant["max_food"] * ratios[index]
				game.systems.simulation._update_plant_ecology_state(plant)
	print("Visual state order, left to right: Abundant, Healthy, Sparse, Depleted, Recovering. Carrots top; Berries bottom.")

func _prepare_habitat_comparison() -> void:
	var simulation = game.systems.simulation
	for row in range(2):
		var plant_type := "carrot_patch" if row == 0 else "berry_bush"
		var extremes := _habitat_extremes(plant_type)
		for quality_name in ["poor", "rich"]:
			var position: Vector2 = extremes[quality_name]
			var abundant_id: int = simulation.add_plant(plant_type, position, "visual_test")
			var depleted_position := _ground_near(position + Vector2(32.0, 0.0))
			var depleted_id: int = simulation.add_plant(plant_type, depleted_position, "visual_test")
			var depleted: Dictionary = simulation.plants[depleted_id]
			depleted["food"] = depleted["max_food"] * 0.03
			simulation._update_plant_ecology_state(depleted)
			print("%s %s habitat at %s: capacity %.2f; abundant patch %d beside depleted patch %d." % [plant_type, quality_name, str(position), float(simulation.plants[abundant_id]["habitat_capacity_factor"]), abundant_id, depleted_id])

func _habitat_extremes(plant_type: String) -> Dictionary:
	var result := {"poor": Vector2.ZERO, "rich": Vector2.ZERO}
	var poor_quality := INF
	var rich_quality := -INF
	for x in range(-250, 251, 20):
		for y in range(-170, 171, 20):
			var position := Vector2(float(x), float(y))
			if not game.systems.simulation.is_position_valid(position):
				continue
			var quality: float = game.systems.simulation.terrain.food_capacity_factor(plant_type, position)
			if quality < poor_quality:
				poor_quality = quality
				result["poor"] = position
			if quality > rich_quality:
				rich_quality = quality
				result["rich"] = position
	return result

func _prepare_redistribution() -> void:
	var simulation = game.systems.simulation
	var origin := _ground_near(Vector2(-100.0, 0.0))
	var alternative := _ground_near(Vector2(110.0, 0.0))
	var origin_id: int = simulation.add_plant("carrot_patch", origin, "visual_test")
	var alternative_id: int = simulation.add_plant("carrot_patch", alternative, "visual_test")
	for index in range(8):
		var position := _ground_near(origin + Vector2.from_angle(float(index) / 8.0 * TAU) * 11.0)
		var rabbit_id: int = simulation.add_rabbit(position, "visual_test")
		simulation.rabbits[rabbit_id]["hunger"] = 34.0
	for _tick in range(75):
		simulation.step(0.1)
		game.world_view.process_visual(0.1)
	var moved := 0
	for rabbit in simulation.rabbits.values():
		if rabbit["position"].distance_to(alternative) < rabbit["position"].distance_to(origin):
			moved += 1
	print("Redistribution visual at %.1fs: origin=%s, alternative=%s, rabbits nearer alternative=%d/%d." % [simulation.simulation_time, simulation.plant_ecology_state(simulation.plants[origin_id]), simulation.plant_ecology_state(simulation.plants[alternative_id]), moved, simulation.rabbits.size()])

func _ground_near(preferred: Vector2) -> Vector2:
	for ring in range(10):
		var radius := float(ring) * 12.0
		for spoke in range(20):
			var candidate := preferred + Vector2.from_angle(float(spoke) / 20.0 * TAU) * radius
			if game.systems.simulation.is_position_valid(candidate):
				return candidate
	return preferred
