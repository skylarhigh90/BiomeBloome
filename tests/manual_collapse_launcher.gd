extends SceneTree

const MainScene = preload("res://game/main.tscn")

var game

func _initialize() -> void:
	game = MainScene.instantiate()
	root.add_child(game)
	_stage_collapse_scenario.call_deferred()

func _stage_collapse_scenario() -> void:
	await process_frame
	var systems = game.systems
	var director = systems.run_director
	director.milestone_index = director.milestone_position("predators_find_place")
	director.completed_milestones = ["colony_gathers", "new_arrivals", "nursery_network"]
	director.rabbit_failure_armed = true
	director.supply_pool = "web"
	director.unlocked["fox"] = true
	director._reset_milestone_evidence()
	systems.simulation.expand_world(float(systems.config["world"]["expansion_amount"]))
	systems.inventory = {"rabbit": 3, "fox": 4, "carrot_patch": 0, "berry_bush": 0}
	for index in range(7):
		var angle := float(index) / 7.0 * TAU
		var radius := 34.0 + float(index % 2) * 22.0
		systems.simulation.add_plant("berry_bush" if index % 2 == 0 else "carrot_patch", Vector2.from_angle(angle) * radius)
	for index in range(8):
		var angle := float(index) / 8.0 * TAU
		systems.simulation.add_rabbit(Vector2.from_angle(angle) * 24.0)
	systems.simulation_speed = 0.0
	systems.inventory_changed.emit()
	systems.unlocks_changed.emit()
	game.hud.refresh()
