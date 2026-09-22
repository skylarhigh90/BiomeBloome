extends SceneTree

func _initialize() -> void:
	var cfg := GameConfig.make()
	cfg["world"]["forest_patch_count"] = 0
	cfg["terrain"]["thicket"]["patch_count"] = 0
	cfg["terrain"]["stream"]["enabled"] = false
	var sim := EcosystemSimulation.new(cfg)
	sim.add_plant("berry_bush", Vector2(60.0, 0.0))
	var id := sim.add_rabbit(Vector2(-100.0, 0.0))
	var rabbit: Dictionary = sim.rabbits[id]
	rabbit["hunger"] = 30.0
	var stops: Array = []
	for tick in range(450):
		var previous_behavior := str(rabbit["behavior"])
		var previous_phase := float(rabbit["gait_phase"])
		var previous_speed: float = Vector2(rabbit["velocity"]).length()
		var previous_motor: float = Vector2(rabbit["motion_velocity"]).length()
		sim.step(0.1)
		if str(rabbit["behavior"]) in ["eat", "loaf", "socialize", "observe"] and previous_behavior not in ["eat", "loaf", "socialize", "observe"]:
			var flight := sin(clampf((fposmod(previous_phase, 1.0) - 0.15) / 0.70, 0.0, 1.0) * PI)
			stops.append({"t": sim.simulation_time, "from": previous_behavior, "to": rabbit["behavior"], "phase": fposmod(previous_phase, 1.0), "prior_lift_world": flight * clampf(previous_motor / 30.0, 0.0, 1.0) * 4.8, "prior_speed": previous_speed})
	print(JSON.stringify({"stops": stops}))
	quit()
