extends SceneTree

const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var sustainable := _sustainable_use_trial()
	var redistribution := _redistribution_trial()
	var no_alternative := _no_alternative_trial()
	var berry_recovery := _berry_recovery_trial()
	print("\nPLANT ECOLOGY A · Sustainable use: %s" % str(sustainable))
	print("PLANT ECOLOGY B/D · Overgrazing and two-region redistribution: %s" % str(redistribution))
	print("PLANT ECOLOGY C · No alternative food: %s" % str(no_alternative))
	print("PLANT ECOLOGY · Berry recovery window: %s" % str(berry_recovery))
	_check(int(sustainable["feeding_events"]) > 0 and int(sustainable["depletions"]) == 0 \
		and float(sustainable["minimum_ratio"]) > 0.10 and int(sustainable["survivors"]) == 2,
		"Sustainable pressure should feed two Rabbits without repeatedly collapsing the patch.")
	_check(bool(redistribution["depleted"]) and bool(redistribution["abandoned_while_latched"]),
		"Overgrazing should latch the first patch and make Rabbits abandon it.")
	_check(bool(redistribution["fed_at_alternative"]) and bool(redistribution["entered_alternative_region"]),
		"Rabbits should naturally move to and feed in the second reachable region.")
	_check(bool(redistribution["recovered"]) and float(redistribution["recovery_seconds"]) >= 15.0 \
		and float(redistribution["recovery_seconds"]) <= 45.0,
		"The exhausted patch should visibly recover on a readable 15–45 second timescale.")
	_check(bool(redistribution["feeding_resumed_at_origin"]),
		"A recovered original feeding region should become usable again.")
	_check(bool(no_alternative["depleted"]) and int(no_alternative["starvation_losses"]) > 0,
		"With no alternative food, depletion should still permit hunger and starvation consequences.")
	_check(bool(berry_recovery["recovered"]) and float(berry_recovery["recovery_seconds"]) >= 15.0 \
		and float(berry_recovery["recovery_seconds"]) <= 45.0,
		"A depleted Berry Bush should rebuild a usable reserve on the target 15–45 second timescale.")
	if failures.is_empty():
		print("Plant ecology scenarios passed: sustainable pressure, durable depletion, redistribution, recovery, and starvation all emerged from normal Rabbit behavior.")
		quit(0)
		return
	for failure in failures:
		printerr("PLANT ECOLOGY FAILED: %s" % failure)
	quit(1)

func _flat_config() -> Dictionary:
	var config := Config.make().duplicate(true)
	config["world"]["forest_patch_count"] = 0
	config["terrain"]["thicket"]["patch_count"] = 0
	config["terrain"]["stream"]["enabled"] = false
	config["rabbit"]["reproduction_food_needed"] = 99999.0
	config["rabbit"]["lifespan"] = 9999.0
	return config

func _sustainable_use_trial() -> Dictionary:
	var config := _flat_config()
	config["rabbit"]["move_speed"] = 20.0
	config["rabbit"]["food_detection_radius"] = 240.0
	var sim = Simulation.new(config, 7412)
	var plant_id: int = sim.add_plant("carrot_patch", Vector2.ZERO)
	var events := {"feeding": 0, "depletions": 0}
	sim.creature_fed.connect(func(kind: String, _rabbit_id: int, source_id: int) -> void:
		if kind == "rabbit" and source_id == plant_id:
			events["feeding"] = int(events["feeding"]) + 1
	)
	sim.plant_state_changed.connect(func(changed_id: int, _previous: String, current: String, _position: Vector2) -> void:
		if changed_id == plant_id and current == "depleted":
			events["depletions"] = int(events["depletions"]) + 1
	)
	for index in range(2):
		var rabbit_id: int = sim.add_rabbit(Vector2(-7.0 + float(index) * 14.0, 0.0))
		sim.rabbits[rabbit_id]["hunger"] = 31.0
	var minimum_ratio := 1.0
	for _tick in range(1800):
		sim.step(0.1)
		minimum_ratio = minf(minimum_ratio, sim.plant_stock_ratio(sim.plants[plant_id]))
	return {
		"feeding_events": events["feeding"],
		"depletions": events["depletions"],
		"minimum_ratio": snappedf(minimum_ratio, 0.001),
		"survivors": sim.rabbits.size(),
		"final_state": sim.plant_ecology_state(sim.plants[plant_id]),
	}

func _redistribution_trial() -> Dictionary:
	var config := _flat_config()
	config["rabbit"]["food_detection_radius"] = 250.0
	var sim = Simulation.new(config, 9327)
	var origin_id: int = sim.add_plant("carrot_patch", Vector2(-100.0, 0.0))
	var alternative_id: int = sim.add_plant("carrot_patch", Vector2(110.0, 0.0))
	var result := {
		"depleted": false,
		"depleted_at": -1.0,
		"recovered": false,
		"recovered_at": -1.0,
		"fed_at_alternative": false,
		"entered_alternative_region": false,
		"feeding_resumed_at_origin": false,
		"abandoned_while_latched": true,
	}
	sim.plant_state_changed.connect(func(changed_id: int, _previous: String, current: String, _position: Vector2) -> void:
		if changed_id != origin_id:
			return
		if current == "depleted" and not bool(result["depleted"]):
			result["depleted"] = true
			result["depleted_at"] = sim.simulation_time
		elif current == "healthy" and bool(result["depleted"]) and not bool(result["recovered"]):
			result["recovered"] = true
			result["recovered_at"] = sim.simulation_time
	)
	sim.creature_fed.connect(func(kind: String, _rabbit_id: int, source_id: int) -> void:
		if kind != "rabbit":
			return
		if source_id == alternative_id and bool(result["depleted"]):
			result["fed_at_alternative"] = true
		if source_id == origin_id and bool(result["recovered"]) and bool(result["fed_at_alternative"]):
			result["feeding_resumed_at_origin"] = true
	)
	for index in range(8):
		var position := Vector2(-100.0, 0.0) + Vector2.from_angle(float(index) / 8.0 * TAU) * 8.0
		var rabbit_id: int = sim.add_rabbit(position)
		sim.rabbits[rabbit_id]["hunger"] = 34.0
	for _tick in range(1800):
		sim.step(0.1)
		if bool(result["depleted"]) and sim.simulation_time > float(result["depleted_at"]) + 0.3 \
			and bool(sim.plants[origin_id]["depletion_latched"]):
			for rabbit in sim.rabbits.values():
				if int(rabbit["target_id"]) == origin_id:
					result["abandoned_while_latched"] = false
		for rabbit in sim.rabbits.values():
			if float(rabbit["position"].x) > 20.0:
				result["entered_alternative_region"] = true
		if bool(result["feeding_resumed_at_origin"]):
			break
	result["recovery_seconds"] = snappedf(float(result["recovered_at"]) - float(result["depleted_at"]), 0.1) if bool(result["recovered"]) else -1.0
	result["survivors"] = sim.rabbits.size()
	return result

func _no_alternative_trial() -> Dictionary:
	var config := _flat_config()
	config["rabbit"]["move_speed"] = 20.0
	config["rabbit"]["food_detection_radius"] = 240.0
	var sim = Simulation.new(config, 1517)
	var plant_id: int = sim.add_plant("berry_bush", Vector2.ZERO)
	var result := {"depleted": false, "starvation_losses": 0}
	sim.plant_state_changed.connect(func(changed_id: int, _previous: String, current: String, _position: Vector2) -> void:
		if changed_id == plant_id and current == "depleted":
			result["depleted"] = true
	)
	sim.entity_removed.connect(func(kind: String, _entity_id: int, _position: Vector2, cause: String) -> void:
		if kind == "rabbit" and cause == "starvation":
			result["starvation_losses"] = int(result["starvation_losses"]) + 1
	)
	for index in range(12):
		var rabbit_id: int = sim.add_rabbit(Vector2.from_angle(float(index) / 12.0 * TAU) * 10.0)
		sim.rabbits[rabbit_id]["hunger"] = 36.0
	for _tick in range(2400):
		if sim.rabbits.is_empty():
			break
		sim.step(0.1)
	result["survivors"] = sim.rabbits.size()
	result["final_state"] = sim.plant_ecology_state(sim.plants[plant_id])
	return result

func _berry_recovery_trial() -> Dictionary:
	var sim = Simulation.new(_flat_config(), 4451)
	var plant_id: int = sim.add_plant("berry_bush", Vector2.ZERO)
	var plant: Dictionary = sim.plants[plant_id]
	plant["food"] = 0.0
	sim._update_plant_ecology_state(plant)
	var recovered_at := -1.0
	for _tick in range(500):
		sim.step(0.1)
		if not bool(plant["depletion_latched"]):
			recovered_at = sim.simulation_time
			break
	return {
		"recovered": recovered_at >= 0.0,
		"recovery_seconds": snappedf(recovered_at, 0.1),
		"state": sim.plant_ecology_state(plant),
	}

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
