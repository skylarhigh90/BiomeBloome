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
		game.systems.place_item("berry_bush", Vector2(-35.0, 10.0))
		game.systems.place_item("grass", Vector2(35.0, 22.0))
		game.systems.place_item("rabbit", Vector2(-10.0, 0.0))
		game.systems.place_item("rabbit", Vector2(12.0, 4.0))
		game.systems.place_item("fox", Vector2(70.0, -15.0))
		game.debug_enabled = true
		game.world_view.debug_enabled = true
		game.world_view.queue_redraw()
		populated = true
	if frames >= 24:
		if populated and game.systems.simulation.rabbits.size() == 2 and game.systems.simulation.foxes.size() == 1 and game.systems.simulation.plants.size() == 2:
			print("Visual smoke passed: scene, HUD, camera, terrain, four placeable renderers, and debug drawing instantiated without runtime errors.")
			quit(0)
		else:
			printerr("Visual smoke failed to instantiate the playable scene.")
			quit(1)
	return false
