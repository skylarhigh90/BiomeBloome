extends SceneTree

const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")

const SEEDS := [240817, 9327, 401]

var failures: Array[String] = []

func _initialize() -> void:
	var requested := OS.get_cmdline_user_args()
	var mode := str(requested[0]) if not requested.is_empty() else "all"
	var active_seeds: Array[int] = []
	if requested.size() > 1:
		active_seeds.append(int(requested[1]))
	else:
		active_seeds.assign(SEEDS)
	if mode in ["all", "rabbits"]:
		print("\nECOSYSTEM STABILITY · renewable carrying capacity")
		for seed_value in active_seeds:
			var result := _rabbit_stability_playthrough(seed_value, 360.0)
			print("Rabbit seed %d: %s" % [seed_value, str(result)])
			_check(int(result["starvation"]) == 0, "seed %d: a correctly stocked colony avoids starvation churn" % seed_value)
			_check(int(result["peak"]) <= int(result["capacity"]), "seed %d: births do not overshoot renewable carrying capacity" % seed_value)
			_check(int(result["end"]) >= int(result["start"]), "seed %d: the founder colony remains viable" % seed_value)

	if mode in ["all", "intervention"]:
		print("\nECOSYSTEM STABILITY · player forage intervention")
		var intervention := _forage_intervention_playthrough(240817)
		print(str(intervention))
		_check(int(intervention["capacity_after"]) > int(intervention["capacity_before"]), "adding food raises carrying capacity")
		_check(int(intervention["births_after"]) > 0, "adding food restarts births after a capacity plateau")
		_check(int(intervention["starvation"]) == 0, "a timely forage intervention avoids starvation")

	if mode in ["all", "predators"]:
		print("\nECOSYSTEM STABILITY · coordinated predators")
		for seed_value in active_seeds:
			var result := _predator_playthrough(seed_value, 180.0)
			print("Predator seed %d: %s" % [seed_value, str(result)])
			_check(int(result["fox_end"]) == 2, "seed %d: both Foxes remain viable" % seed_value)
			_check(int(result["fed_foxes"]) == 2, "seed %d: prey coordination gives both Foxes a meal" % seed_value)
			_check(int(result["rabbit_end"]) >= 18, "seed %d: finite pursuits do not erase the prey base" % seed_value)

	if failures.is_empty():
		print("\nAll long-form ecosystem stability checks passed.")
	else:
		for failure in failures:
			printerr("STABILITY FAILED: %s" % failure)
	quit(0 if failures.is_empty() else 1)

func _base_config(seed_value: int) -> Dictionary:
	var config := Config.make().duplicate(true)
	config["simulation"]["seed"] = seed_value
	config["rabbit"]["lifespan"] = 9999.0
	config["fox"]["lifespan"] = 9999.0
	return config

func _rabbit_stability_playthrough(seed_value: int, duration: float) -> Dictionary:
	var config := _base_config(seed_value)
	config["rabbit"]["max_population"] = 100
	var sim = Simulation.new(config, seed_value)
	_add_food(sim, 7, 5, 210.0)
	for index in range(7):
		var rabbit_id: int = sim.add_rabbit(_valid_near(sim, Vector2.from_angle(float(index) / 7.0 * TAU) * (18.0 + float(index % 4) * 10.0), index))
		sim.rabbits[rabbit_id]["hunger"] = 12.0
	var starvation := {"count": 0}
	sim.entity_removed.connect(func(kind: String, _id: int, _position: Vector2, cause: String) -> void:
		if kind == "rabbit" and cause == "starvation":
			starvation["count"] += 1
	)
	var start: int = sim.rabbits.size()
	var capacity: int = floori(float(sim.ecosystem_forage_budget()["sustainable_rabbits"]))
	var peak: int = start
	for _tick in range(ceili(duration / 0.1)):
		sim.step(0.1)
		peak = maxi(peak, sim.rabbits.size())
	return {
		"start": start,
		"peak": peak,
		"end": sim.rabbits.size(),
		"capacity": capacity,
		"starvation": starvation["count"],
		"stock": snappedf(float(sim.ecosystem_forage_budget()["stock_ratio"]), 0.01),
	}

func _forage_intervention_playthrough(seed_value: int) -> Dictionary:
	var config := _base_config(seed_value)
	var sim = Simulation.new(config, seed_value)
	_add_food(sim, 7, 5, 210.0)
	for index in range(7):
		sim.add_rabbit(_valid_near(sim, Vector2.from_angle(float(index) / 7.0 * TAU) * 28.0, index))
	var births := {"before": 0, "after": 0, "intervened": false}
	var starvation := {"count": 0}
	sim.entity_added.connect(func(kind: String, _id: int, reason: String) -> void:
		if kind == "rabbit" and reason == "birth":
			births["after" if births["intervened"] else "before"] += 1
	)
	sim.entity_removed.connect(func(kind: String, _id: int, _position: Vector2, cause: String) -> void:
		if kind == "rabbit" and cause == "starvation":
			starvation["count"] += 1
	)
	for _tick in range(1500):
		sim.step(0.1)
	var capacity_before := floori(float(sim.ecosystem_forage_budget()["sustainable_rabbits"]))
	births["intervened"] = true
	for index in range(3):
		sim.add_plant("berry_bush", _valid_near(sim, Vector2.from_angle(float(index) / 3.0 * TAU + 0.4) * 145.0, 500 + index))
	var capacity_after := floori(float(sim.ecosystem_forage_budget()["sustainable_rabbits"]))
	for _tick in range(1200):
		sim.step(0.1)
	return {
		"capacity_before": capacity_before,
		"capacity_after": capacity_after,
		"births_before": births["before"],
		"births_after": births["after"],
		"rabbit_end": sim.rabbits.size(),
		"starvation": starvation["count"],
	}

func _predator_playthrough(seed_value: int, duration: float) -> Dictionary:
	var config := _base_config(seed_value)
	config["rabbit"]["max_population"] = 28
	config["fox"]["max_population"] = 2
	var sim = Simulation.new(config, seed_value)
	sim.world_radius = 744.0
	_add_food(sim, 18, 12, 310.0)
	for index in range(28):
		var radius := 55.0 + float(index % 4) * 45.0
		var rabbit_id: int = sim.add_rabbit(_valid_near(sim, Vector2.from_angle(float(index) / 28.0 * TAU) * radius, index))
		sim.rabbits[rabbit_id]["hunger"] = 8.0
	var first_fox: int = sim.add_fox(_valid_near(sim, Vector2(0.0, -95.0), 91))
	var second_fox: int = sim.add_fox(_valid_near(sim, Vector2(0.0, 95.0), 92))
	sim.foxes[first_fox]["hunger"] = 24.0
	sim.foxes[second_fox]["hunger"] = 24.0
	var meals: Dictionary = {}
	sim.creature_fed.connect(func(kind: String, entity_id: int, _food_id: int) -> void:
		if kind == "fox":
			meals[entity_id] = int(meals.get(entity_id, 0)) + 1
	)
	for _tick in range(ceili(duration / 0.1)):
		sim.step(0.1)
	return {
		"fox_end": sim.foxes.size(),
		"fed_foxes": meals.size(),
		"meals": meals,
		"rabbit_end": sim.rabbits.size(),
	}

func _add_food(sim, carrots: int, berries: int, spread: float) -> void:
	var total := carrots + berries
	for index in range(total):
		var kind := "carrot_patch" if index < carrots else "berry_bush"
		var radius := 48.0 + float(index % 4) * ((spread - 48.0) / 3.0)
		var angle := float(index) * 2.399963
		sim.add_plant(kind, _valid_near(sim, Vector2.from_angle(angle) * radius, 100 + index))

func _valid_near(sim, wanted: Vector2, salt: int) -> Vector2:
	if sim.is_position_valid(wanted):
		return wanted
	for ring in range(1, 12):
		for spoke in range(16):
			var angle := float(spoke) / 16.0 * TAU + float(salt) * 0.37
			var candidate := wanted + Vector2.from_angle(angle) * float(ring) * 12.0
			if sim.is_position_valid(candidate):
				return candidate
	return Vector2.ZERO

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
