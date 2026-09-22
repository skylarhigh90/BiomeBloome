extends SceneTree

var game
var frames = 0
var output_path = "/private/tmp/biome-gameplay-improvements.png"

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if not args.is_empty():
		output_path = str(args[0])
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_prepare_scene()
	if frames == 20:
		var image = root.get_texture().get_image()
		var error = image.save_png(output_path)
		if error != OK:
			printerr("Gameplay improvements capture failed: %s" % error_string(error))
			quit(1)
			return false
		print("Gameplay improvements capture saved: %s" % output_path)
		quit(0)
	return false

func _prepare_scene() -> void:
	game.systems.set_speed(0.0)
	game.systems.supply_time_remaining = 9999.0
	game.systems.run_director.milestone_index = 2
	game.systems.run_director.unlocked["berry_bush"] = true
	game.systems.run_director.unlocked["transplant"] = true
	game.systems.inventory["berry_bush"] = 2
	game.systems.transplant_charges = 2
	var centers = [Vector2(-175.0, -75.0), Vector2(175.0, 65.0)]
	for center in centers:
		game.systems.simulation.add_plant("berry_bush", _ground_near(center + Vector2(25.0, 12.0)), "visual_test")
		game.systems.simulation.add_plant("carrot_patch", _ground_near(center + Vector2(-25.0, 12.0)), "visual_test")
	var first = game.systems.simulation.add_rabbit(_ground_near(centers[0] + Vector2(-12.0, 0.0)), "placement")
	var second = game.systems.simulation.add_rabbit(_ground_near(centers[0] + Vector2(12.0, 0.0)), "placement")
	for index in range(4):
		game.systems.simulation.add_rabbit(_ground_near(centers[index % 2] + Vector2(float(index) * 9.0, -12.0)), "placement")
	var child = game.systems.simulation.add_rabbit(_ground_near(centers[0] + Vector2(0.0, 18.0)), "birth", [first, second])
	game.systems.simulation.rabbits[child]["age"] = 8.0
	game.systems.simulation.rabbits[child]["meals"] = 3
	game.systems.simulation.rabbits[child]["recent_event"] = "Found forage beside the family"
	game.world_view.set_public_selection("rabbit", child)
	game.hud.show_animal("rabbit", child)
	game.hud.set_followed_animal("rabbit", child)
	game.systems.select_item("berry_bush")
	var preview_position = _best_berry_site()
	var assessment = game.systems.placement_assessment("berry_bush", preview_position)
	game.world_view.set_placement_preview("berry_bush", preview_position, true, true, str(assessment["quality"]))
	game.hud.set_placement_guidance(assessment)
	game.hud.refresh()
	game.world_view.queue_redraw()

func _ground_near(preferred: Vector2) -> Vector2:
	for ring in range(12):
		for spoke in range(24):
			var candidate = preferred + Vector2.from_angle(float(spoke) / 24.0 * TAU) * float(ring) * 12.0
			if game.systems.simulation.is_position_valid(candidate):
				return candidate
	return Vector2.ZERO

func _best_berry_site() -> Vector2:
	var best = Vector2.ZERO
	var best_score = -INF
	for radius in range(40, 320, 20):
		for spoke in range(32):
			var candidate = Vector2.from_angle(float(spoke) / 32.0 * TAU) * float(radius)
			if not game.systems.simulation.is_position_valid(candidate):
				continue
			var score: float = game.systems.simulation.terrain.food_capacity_factor("berry_bush", candidate)
			if score > best_score:
				best = candidate
				best_score = score
	return best
