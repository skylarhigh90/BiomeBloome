extends SceneTree

## Manual Objective Lens inspection at the normal 1280x800 gameplay viewport.
## Run without --headless:
##   godot --path . --script res://tests/objective_lens_visual_runner.gd -- newborns /tmp/objective-newborns.png
##   godot --path . --script res://tests/objective_lens_visual_runner.gd -- birthplaces /tmp/objective-birthplaces.png
##   godot --path . --script res://tests/objective_lens_visual_runner.gd -- birthplace_nearby /tmp/objective-birthplace-nearby.png
##   godot --path . --script res://tests/objective_lens_visual_runner.gd -- nurseries /tmp/objective-nurseries.png

var game
var frames := 0
var mode := "newborns"
var output_path := "/private/tmp/biome-objective-lens.png"
var birthplace_positions: Array[Vector2] = []

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
	if mode in ["birthplaces", "birthplace_nearby"]:
		if frames == 8:
			_add_birth(birthplace_positions[0] + Vector2(28.0, 8.0))
		if mode == "birthplaces" and frames == 14:
			_add_birth(birthplace_positions[1])
		if mode == "birthplaces" and frames == 20:
			_add_birth(birthplace_positions[2])
	var capture_frame := 16 if mode == "birthplace_nearby" else 32
	if frames == capture_frame:
		game.hud.refresh()
		var image := root.get_texture().get_image()
		var error := image.save_png(output_path)
		if error != OK:
			printerr("Objective Lens visual capture failed: %s" % error_string(error))
			quit(1)
			return false
		print("Objective Lens '%s' capture saved: %s" % [mode, output_path])
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
	game.world_view.objective_lens.clear_immediately()
	if mode in ["birthplaces", "birthplace_nearby"]:
		_prepare_birthplaces()
	elif mode == "nurseries":
		_prepare_nurseries()
	else:
		_prepare_newborns()
	game.hud.refresh()
	game.world_view.queue_redraw()

func _prepare_newborns() -> void:
	game.systems.run_director.milestone_index = 2
	game.systems.run_director._reset_milestone_evidence()
	var adult_positions := [
		Vector2(-170.0, -78.0), Vector2(-118.0, 35.0), Vector2(-42.0, -104.0),
		Vector2(76.0, -78.0), Vector2(150.0, 34.0),
	]
	for position in adult_positions:
		var adult_id: int = game.systems.simulation.add_rabbit(_ground_near(position), "visual_test")
		_freeze_rabbit(adult_id)
	for position in [Vector2(-115.0, 112.0), Vector2(5.0, 110.0), Vector2(125.0, 110.0)]:
		var plant_position := _ground_near(position)
		game.systems.simulation.add_plant("carrot_patch", plant_position, "visual_test")
	var needs_food: int = game.systems.simulation.add_rabbit(_ground_near(Vector2(-118.0, 82.0)), "birth")
	var growing: int = game.systems.simulation.add_rabbit(_ground_near(Vector2(2.0, 76.0)), "birth")
	var satisfied: int = game.systems.simulation.add_rabbit(_ground_near(Vector2(122.0, 80.0)), "birth")
	for rabbit_id in [needs_food, growing, satisfied]:
		_freeze_rabbit(rabbit_id)
	game.systems.simulation.rabbits[needs_food]["age"] = 9.0
	game.systems.simulation.rabbits[growing]["age"] = 4.0
	game.systems.simulation.rabbits[satisfied]["age"] = 9.0
	game.systems.run_director.record_creature_fed("rabbit", growing, -1)
	game.systems.run_director.record_creature_fed("rabbit", satisfied, -1)
	print("Newborn Lens: amber needs food, teal has fed/is growing, green check has satisfied the criterion.")

func _prepare_birthplaces() -> void:
	game.systems.run_director.milestone_index = 3
	game.systems.run_director._reset_milestone_evidence()
	birthplace_positions = [
		_ground_near(Vector2(-185.0, -92.0)),
		_ground_near(Vector2(0.0, 145.0)),
		_ground_near(Vector2(190.0, -82.0)),
	]
	for area_index in range(birthplace_positions.size()):
		var center := birthplace_positions[area_index]
		for member_index in range(2):
			var adult_id: int = game.systems.simulation.add_rabbit(_ground_near(center + Vector2(-18.0 + float(member_index) * 36.0, -20.0)), "visual_test")
			_freeze_rabbit(adult_id)
		game.systems.simulation.add_plant("berry_bush", _ground_near(center + Vector2(0.0, 30.0)), "visual_test")
	_add_birth(birthplace_positions[0])
	print("Birthplace Lens: birth 2 reinforces area 1; later separated births establish areas 2 and 3.")

func _prepare_nurseries() -> void:
	game.systems.run_director.milestone_index = 4
	game.systems.run_director._reset_milestone_evidence()
	var nursery_center := _ground_near(Vector2(155.0, -62.0))
	for offset in [Vector2(-19.0, -8.0), Vector2(17.0, -10.0), Vector2(0.0, 18.0)]:
		var rabbit_id: int = game.systems.simulation.add_rabbit(_ground_near(nursery_center + offset), "visual_test")
		_freeze_rabbit(rabbit_id)
	game.systems.simulation.add_plant("berry_bush", _ground_near(nursery_center + Vector2(8.0, 32.0)), "visual_test")
	for position in [
		Vector2(-245.0, -185.0), Vector2(-105.0, -205.0), Vector2(30.0, -225.0),
		Vector2(-250.0, 15.0), Vector2(-105.0, 35.0), Vector2(-245.0, 205.0),
		Vector2(-75.0, 225.0), Vector2(80.0, 215.0), Vector2(250.0, 185.0),
	]:
		var rabbit_id: int = game.systems.simulation.add_rabbit(_ground_near(position), "visual_test")
		_freeze_rabbit(rabbit_id)
	print("Nursery Lens: the HUD's 1/3 count is paired with one persistent NURSERY 1 plaque in the meadow.")

func _add_birth(position: Vector2) -> void:
	var rabbit_id: int = game.systems.simulation.add_rabbit(_ground_near(position), "birth")
	_freeze_rabbit(rabbit_id)
	game.hud.refresh()

func _freeze_rabbit(entity_id: int) -> void:
	var rabbit: Dictionary = game.systems.simulation.rabbits[entity_id]
	rabbit["velocity"] = Vector2.ZERO
	rabbit["previous_velocity"] = Vector2.ZERO
	rabbit["previous_position"] = rabbit["position"]
	rabbit["hunger"] = 8.0

func _ground_near(preferred: Vector2) -> Vector2:
	for ring in range(12):
		var radius := float(ring) * 10.0
		for spoke in range(24):
			var candidate := preferred + Vector2.from_angle(float(spoke) / 24.0 * TAU) * radius
			if game.systems.simulation.is_position_valid(candidate):
				return candidate
	return preferred
