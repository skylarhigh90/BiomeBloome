extends SceneTree

var game
var frames := 0
var populated := false

func _initialize() -> void:
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		# The seeded Stream can move through earlier fixed smoke-test coordinates.
		# Resolve nearby playable points so this remains a renderer/HUD smoke test;
		# placement rejection itself is covered by terrain_runner.gd.
		game.systems.place_item("berry_bush", _placeable_near("berry_bush", Vector2(-90.0, 70.0)))
		game.systems.place_item("carrot_patch", _placeable_near("carrot_patch", Vector2(90.0, 70.0)))
		game.systems.place_item("rabbit", _placeable_near("rabbit", Vector2(-45.0, -55.0)))
		game.systems.place_item("rabbit", _placeable_near("rabbit", Vector2(45.0, -55.0)))
		game.systems.simulation.add_fox(Vector2(70.0, -15.0))
		game.debug_enabled = true
		game.world_view.debug_enabled = true
		game.world_view.queue_redraw()
		game.systems.set_speed(2.0)
		game.systems.supply_time_remaining = 0.1
		populated = true
	if frames >= 24:
		if populated and game.systems.simulation.rabbits.size() == 2 and game.systems.simulation.foxes.size() == 1 and game.systems.simulation.plants.size() == 2 and game.systems.supply_pending and game.systems.is_paused() and game.hud.supply_overlay.visible:
			print("Visual smoke passed: scene, HUD, terrain, renderers, and the auto-paused Meadow Mail reward instantiated without runtime errors.")
			quit(0)
		else:
			printerr("Visual smoke failed to instantiate the playable scene.")
			quit(1)
	return false

func _placeable_near(item: String, preferred: Vector2) -> Vector2:
	for ring in range(8):
		var radius := float(ring) * 18.0
		for spoke in range(16):
			var candidate := preferred + Vector2.from_angle(float(spoke) / 16.0 * TAU) * radius
			if game.systems.can_place(item, candidate):
				return candidate
	return Vector2.INF
