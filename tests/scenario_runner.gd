extends SceneTree

const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var colony := _scenario_rabbit_colony()
	var poor := _scenario_poor_placement()
	var predator := _scenario_predator_introduction()
	var collapse := _scenario_predator_collapse()
	print("\nSCENARIO A · Rabbit colony: %s" % str(colony))
	print("SCENARIO B · Poor placement: %s" % str(poor))
	print("SCENARIO C · Predator introduction: %s" % str(predator))
	print("SCENARIO D · Predator collapse: %s" % str(collapse))
	print("SCENARIO E · Spatial difference: colony survival %.2f vs isolated %.2f" % [colony["survival"], poor["survival"]])
	_check(colony["peak"] > colony["start"], "A: a fed rabbit colony reproduces")
	_check(colony["end"] >= 3, "A: a fed colony remains viable")
	_check(colony["peak"] > colony["end"], "A: local food pressure corrects an overshoot without a global cap")
	_check(poor["end"] < colony["end"] and poor["survival"] < colony["survival"], "B/E: poor, distant placement has a worse outcome")
	_check(predator["hunting_ticks"] > 0, "C: a nearby hungry fox enters hunting behavior")
	_check(predator["fleeing_ticks"] > 0, "C: nearby rabbits visibly enter flee behavior")
	# Births can offset captures during this growing-colony scenario, so net decline is not
	# required; an observed removal is the direct evidence that physical predation occurred.
	_check(predator["captures"] > 0, "C: physical predation removes rabbits")
	_check(collapse["rabbit_low"] < collapse["rabbit_start"] * 0.6, "D: excess foxes drive rabbit decline")
	_check(collapse["fox_end"] < collapse["fox_peak"], "D: prey loss is followed by fox starvation/decline")
	if failures.is_empty():
		print("\nAll five ecological scenario checks passed.")
	else:
		for failure in failures:
			printerr("SCENARIO FAILED: %s" % failure)
	quit(0 if failures.is_empty() else 1)

func _scenario_rabbit_colony() -> Dictionary:
	var sim = Simulation.new(Config.make().duplicate(true), 401)
	_add_food_patch(sim, Vector2.ZERO, 6)
	for index in range(5):
		sim.add_rabbit(Vector2.from_angle(float(index) / 5.0 * TAU) * 24.0)
	var start: int = sim.rabbits.size()
	var peak: int = start
	for tick in range(2400):
		sim.step(0.1)
		peak = maxi(peak, sim.rabbits.size())
	return {"start": start, "peak": peak, "end": sim.rabbits.size(), "survival": float(sim.rabbits.size()) / float(start)}

func _scenario_poor_placement() -> Dictionary:
	var sim = Simulation.new(Config.make().duplicate(true), 401)
	sim.add_plant("carrot_patch", Vector2.ZERO)
	for index in range(5):
		var angle := float(index) / 5.0 * TAU
		sim.add_rabbit(Vector2.from_angle(angle) * 285.0)
	var start: int = sim.rabbits.size()
	var peak: int = start
	for tick in range(1200):
		sim.step(0.1)
		peak = maxi(peak, sim.rabbits.size())
	return {"start": start, "peak": peak, "end": sim.rabbits.size(), "survival": float(sim.rabbits.size()) / float(start)}

func _scenario_predator_introduction() -> Dictionary:
	var sim = Simulation.new(Config.make().duplicate(true), 882)
	_add_food_patch(sim, Vector2.ZERO, 7)
	for index in range(10):
		sim.add_rabbit(Vector2.from_angle(float(index) / 10.0 * TAU) * (25.0 + float(index % 3) * 10.0))
	for tick in range(280):
		sim.step(0.1)
	var fox_id: int = sim.add_fox(Vector2(14.0, 0.0))
	sim.foxes[fox_id]["hunger"] = 42.0
	var rabbit_peak: int = sim.rabbits.size()
	var fleeing_ticks := 0
	var hunting_ticks := 0
	var captures := 0
	for tick in range(700):
		var before: int = sim.rabbits.size()
		sim.step(0.1)
		rabbit_peak = maxi(rabbit_peak, sim.rabbits.size())
		captures += maxi(0, before - sim.rabbits.size())
		for rabbit in sim.rabbits.values():
			if rabbit["behavior"] == "flee":
				fleeing_ticks += 1
		if sim.foxes.has(fox_id) and sim.foxes[fox_id]["behavior"] == "hunt":
			hunting_ticks += 1
	return {"rabbit_peak": rabbit_peak, "rabbit_end": sim.rabbits.size(), "fox_end": sim.foxes.size(), "captures": captures, "fleeing_ticks": fleeing_ticks, "hunting_ticks": hunting_ticks}

func _scenario_predator_collapse() -> Dictionary:
	var config := Config.make().duplicate(true)
	# This is a deliberately extreme placement strategy, using normal species tuning.
	var sim = Simulation.new(config, 1733)
	_add_food_patch(sim, Vector2.ZERO, 7)
	for index in range(14):
		sim.add_rabbit(Vector2.from_angle(float(index) / 14.0 * TAU) * (28.0 + float(index % 4) * 9.0))
	for index in range(8):
		var fox_id: int = sim.add_fox(Vector2.from_angle(float(index) / 8.0 * TAU) * 72.0)
		sim.foxes[fox_id]["hunger"] = 46.0
	var rabbit_start: int = sim.rabbits.size()
	var rabbit_low: int = rabbit_start
	var fox_peak: int = sim.foxes.size()
	for tick in range(2400):
		sim.step(0.1)
		rabbit_low = mini(rabbit_low, sim.rabbits.size())
		fox_peak = maxi(fox_peak, sim.foxes.size())
	return {"rabbit_start": rabbit_start, "rabbit_low": rabbit_low, "rabbit_end": sim.rabbits.size(), "fox_peak": fox_peak, "fox_end": sim.foxes.size()}

func _add_food_patch(simulation, center: Vector2, count: int) -> void:
	for index in range(count):
		var angle := float(index) / float(count) * TAU
		var radius := 30.0 + float(index % 2) * 22.0
		simulation.add_plant("berry_bush" if index % 2 == 0 else "carrot_patch", center + Vector2.from_angle(angle) * radius)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
