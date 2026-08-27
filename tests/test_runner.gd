extends SceneTree

const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")
const Systems = preload("res://game/game_systems.gd")

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_run_all()
	print("\n%d behavior tests passed; %d failed." % [passed, failures.size()])
	for failure in failures:
		printerr("FAILED: %s" % failure)
	quit(1 if not failures.is_empty() else 0)

func _run_all() -> void:
	_test_placement_consumes_one()
	_test_invalid_placement_consumes_nothing()
	_test_population_is_actual_entities()
	_test_rabbit_seeks_nearby_food()
	_test_rabbit_cannot_eat_distant_food()
	_test_rabbit_flees_nearby_fox()
	_test_fox_targets_nearby_rabbit()
	_test_hunt_removes_exact_prey()
	_test_plant_loses_food_when_eaten()
	_test_plant_regenerates()
	_test_rabbit_reproduction_creates_entity()
	_test_rabbit_reproduction_requires_readiness()
	_test_fox_reproduction_creates_entity()
	_test_fox_reproduction_requires_readiness()
	_test_starvation_kills_creatures()
	_test_pause_stops_simulation_time()
	_test_speed_multipliers()
	_test_objective_stability_progresses_and_resets()
	_test_objective_completion_preserves_world()
	_test_supply_adds_inventory()
	_test_expansion_increases_world()
	_test_seeded_behavior_is_reproducible()
	_test_spatial_hash_handles_prototype_scale()

func _fresh_config() -> Dictionary:
	return Config.make().duplicate(true)

func _expect(condition: bool, name: String, detail: String = "") -> void:
	if condition:
		passed += 1
		print("PASS: %s" % name)
	else:
		failures.append("%s%s" % [name, " — " + detail if not detail.is_empty() else ""])

func _step_many(simulation, seconds: float) -> void:
	var steps := ceili(seconds / 0.1)
	for index in range(steps):
		simulation.step(0.1)

func _make_eligible_rabbit(simulation, entity_id: int) -> void:
	var rabbit: Dictionary = simulation.rabbits[entity_id]
	rabbit["age"] = 30.0
	rabbit["hunger"] = 0.0
	rabbit["recent_food"] = 100.0
	rabbit["reproduction_cooldown"] = 0.0

func _make_eligible_fox(simulation, entity_id: int) -> void:
	var fox: Dictionary = simulation.foxes[entity_id]
	fox["age"] = 40.0
	fox["hunger"] = 0.0
	fox["recent_food"] = 100.0
	fox["reproduction_cooldown"] = 0.0

func _test_placement_consumes_one() -> void:
	var systems = Systems.new(_fresh_config())
	var before: int = systems.inventory["rabbit"]
	var entity_id: int = systems.place_item("rabbit", Vector2.ZERO)
	_expect(entity_id > 0 and systems.inventory["rabbit"] == before - 1 and systems.simulation.rabbits.has(entity_id), "successful placement consumes exactly one")

func _test_invalid_placement_consumes_nothing() -> void:
	var systems = Systems.new(_fresh_config())
	var before: int = systems.inventory["fox"]
	var entity_id: int = systems.place_item("fox", Vector2(5000.0, 0.0))
	_expect(entity_id == -1 and systems.inventory["fox"] == before and systems.simulation.foxes.is_empty(), "invalid placement consumes nothing")

func _test_population_is_actual_entities() -> void:
	var sim = Simulation.new(_fresh_config())
	var first: int = sim.add_rabbit(Vector2.ZERO)
	var second: int = sim.add_rabbit(Vector2(20.0, 0.0))
	var counted_two: bool = sim.population("rabbit") == sim.rabbits.size() and sim.population("rabbit") == 2
	sim.kill_rabbit(first, "test")
	_expect(counted_two and sim.population("rabbit") == 1 and sim.rabbits.has(second), "population counters reflect living entities")

func _test_rabbit_seeks_nearby_food() -> void:
	var sim = Simulation.new(_fresh_config())
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	sim.add_plant("grass", Vector2(55.0, 0.0))
	sim.rabbits[rabbit_id]["hunger"] = 50.0
	sim.step(0.1)
	_expect(sim.rabbits[rabbit_id]["behavior"] == "seek_food" and sim.rabbits[rabbit_id]["target_id"] != -1, "rabbits seek nearby food")

func _test_rabbit_cannot_eat_distant_food() -> void:
	var config := _fresh_config()
	config["rabbit"]["food_detection_radius"] = 90.0
	var sim = Simulation.new(config)
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	var plant_id: int = sim.add_plant("grass", Vector2(260.0, 0.0))
	sim.rabbits[rabbit_id]["hunger"] = 60.0
	var before: float = sim.plants[plant_id]["food"]
	_step_many(sim, 1.0)
	_expect(is_equal_approx(sim.plants[plant_id]["food"], before), "rabbits cannot consume distant food")

func _test_rabbit_flees_nearby_fox() -> void:
	var sim = Simulation.new(_fresh_config())
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	var fox_id: int = sim.add_fox(Vector2(24.0, 0.0))
	sim.step(0.1)
	var rabbit: Dictionary = sim.rabbits[rabbit_id]
	_expect(rabbit["behavior"] == "flee" and rabbit["target_id"] == fox_id and rabbit["velocity"].x < 0.0, "rabbits flee nearby foxes")

func _test_fox_targets_nearby_rabbit() -> void:
	var sim = Simulation.new(_fresh_config())
	var fox_id: int = sim.add_fox(Vector2.ZERO)
	var rabbit_id: int = sim.add_rabbit(Vector2(70.0, 0.0))
	sim.foxes[fox_id]["hunger"] = 60.0
	sim.step(0.1)
	_expect(sim.foxes[fox_id]["behavior"] == "hunt" and sim.foxes[fox_id]["target_id"] == rabbit_id, "foxes target nearby rabbits")

func _test_hunt_removes_exact_prey() -> void:
	var config := _fresh_config()
	config["rabbit"]["flee_speed"] = 0.0
	config["fox"]["capture_distance"] = 40.0
	config["fox"]["capture_rate"] = 100.0
	var sim = Simulation.new(config)
	var fox_id: int = sim.add_fox(Vector2.ZERO)
	var prey_id: int = sim.add_rabbit(Vector2(4.0, 0.0))
	var other_id: int = sim.add_rabbit(Vector2(180.0, 0.0))
	sim.foxes[fox_id]["hunger"] = 60.0
	sim.step(0.1)
	_expect(not sim.rabbits.has(prey_id) and sim.rabbits.has(other_id) and sim.foxes[fox_id]["hunger"] < 60.0, "successful hunt removes the exact prey entity")

func _test_plant_loses_food_when_eaten() -> void:
	var sim = Simulation.new(_fresh_config())
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	var plant_id: int = sim.add_plant("berry_bush", Vector2(3.0, 0.0))
	sim.rabbits[rabbit_id]["hunger"] = 55.0
	var before: float = sim.plants[plant_id]["food"]
	sim.step(0.1)
	_expect(sim.plants[plant_id]["food"] < before, "plants lose food when eaten")

func _test_plant_regenerates() -> void:
	var sim = Simulation.new(_fresh_config())
	var plant_id: int = sim.add_plant("grass", Vector2.ZERO)
	sim.plants[plant_id]["food"] = 0.0
	sim.step(1.0)
	_expect(sim.plants[plant_id]["food"] > 0.0 and sim.plants[plant_id]["food"] <= sim.plants[plant_id]["max_food"], "plant food regenerates")

func _test_rabbit_reproduction_creates_entity() -> void:
	var config := _fresh_config()
	config["rabbit"]["birth_litter_min"] = 1
	config["rabbit"]["birth_litter_max"] = 1
	var sim = Simulation.new(config)
	var first: int = sim.add_rabbit(Vector2.ZERO)
	var second: int = sim.add_rabbit(Vector2(12.0, 0.0))
	sim.add_plant("berry_bush", Vector2(4.0, 10.0))
	_make_eligible_rabbit(sim, first)
	_make_eligible_rabbit(sim, second)
	sim.step(0.1)
	var has_newborn := false
	for rabbit in sim.rabbits.values():
		if rabbit["reason"] == "birth" and rabbit["age"] < 1.0:
			has_newborn = true
	_expect(sim.rabbits.size() == 3 and has_newborn, "rabbit reproduction creates an actual entity")

func _test_rabbit_reproduction_requires_readiness() -> void:
	var sim = Simulation.new(_fresh_config())
	var first: int = sim.add_rabbit(Vector2.ZERO)
	var second: int = sim.add_rabbit(Vector2(10.0, 0.0))
	sim.add_plant("grass", Vector2(4.0, 4.0))
	_make_eligible_rabbit(sim, first)
	_make_eligible_rabbit(sim, second)
	sim.rabbits[first]["reproduction_cooldown"] = 12.0
	sim.step(0.1)
	_expect(sim.rabbits.size() == 2, "rabbit reproduction is limited by cooldown and conditions")

func _test_fox_reproduction_creates_entity() -> void:
	var sim = Simulation.new(_fresh_config())
	var first: int = sim.add_fox(Vector2.ZERO)
	var second: int = sim.add_fox(Vector2(16.0, 0.0))
	_make_eligible_fox(sim, first)
	_make_eligible_fox(sim, second)
	sim.step(0.1)
	var has_newborn := false
	for fox in sim.foxes.values():
		if fox["reason"] == "birth" and fox["age"] < 1.0:
			has_newborn = true
	_expect(sim.foxes.size() == 3 and has_newborn, "fox reproduction creates an actual entity")

func _test_fox_reproduction_requires_readiness() -> void:
	var sim = Simulation.new(_fresh_config())
	var first: int = sim.add_fox(Vector2.ZERO)
	var second: int = sim.add_fox(Vector2(15.0, 0.0))
	_make_eligible_fox(sim, first)
	_make_eligible_fox(sim, second)
	sim.foxes[second]["recent_food"] = 0.0
	sim.step(0.1)
	_expect(sim.foxes.size() == 2, "fox reproduction is limited by feeding and cooldown conditions")

func _test_starvation_kills_creatures() -> void:
	var config := _fresh_config()
	config["rabbit"]["starvation_threshold"] = 1.0
	config["rabbit"]["starvation_duration"] = 0.2
	config["fox"]["starvation_threshold"] = 1.0
	config["fox"]["starvation_duration"] = 0.2
	var sim = Simulation.new(config)
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	var fox_id: int = sim.add_fox(Vector2(200.0, 0.0))
	sim.rabbits[rabbit_id]["hunger"] = 5.0
	sim.foxes[fox_id]["hunger"] = 5.0
	sim.step(0.1)
	sim.step(0.1)
	_expect(not sim.rabbits.has(rabbit_id) and not sim.foxes.has(fox_id), "starvation can kill rabbits and foxes")

func _test_pause_stops_simulation_time() -> void:
	var systems = Systems.new(_fresh_config())
	systems.set_speed(0.0)
	systems.advance(2.0)
	_expect(is_zero_approx(systems.simulation.simulation_time), "simulation pause stops simulation time")

func _test_speed_multipliers() -> void:
	var config_two := _fresh_config()
	config_two["simulation"]["max_steps_per_frame"] = 100
	var two = Systems.new(config_two)
	two.set_speed(2.0)
	two.advance(1.0)
	var config_three := _fresh_config()
	config_three["simulation"]["max_steps_per_frame"] = 100
	var three = Systems.new(config_three)
	three.set_speed(3.0)
	three.advance(1.0)
	_expect(absf(two.simulation.simulation_time - 2.0) < 0.001 and absf(three.simulation.simulation_time - 3.0) < 0.001, "2× and 3× advance simulation proportionally")

func _test_objective_stability_progresses_and_resets() -> void:
	var config := _fresh_config()
	config["objectives"] = [{"name": "Test", "targets": {"rabbit": 1}, "duration": 3.0}]
	var systems = Systems.new(config)
	var rabbit_id: int = systems.simulation.add_rabbit(Vector2.ZERO)
	systems.advance(0.5)
	var progressed: bool = systems.objective_stability > 0.39
	systems.simulation.kill_rabbit(rabbit_id, "test")
	systems.advance(0.1)
	_expect(progressed and is_zero_approx(systems.objective_stability), "objective stability progresses and resets")

func _test_objective_completion_preserves_world() -> void:
	var config := _fresh_config()
	config["objectives"] = [{"name": "Test", "targets": {"rabbit": 1}, "duration": 0.1}]
	var systems = Systems.new(config)
	var rabbit_id: int = systems.simulation.add_rabbit(Vector2.ZERO)
	var plant_id: int = systems.simulation.add_plant("grass", Vector2(40.0, 0.0))
	systems.advance(0.1)
	_expect(systems.ecosystem_established and systems.simulation.rabbits.has(rabbit_id) and systems.simulation.plants.has(plant_id), "objective completion preserves the world")

func _test_supply_adds_inventory() -> void:
	var systems = Systems.new(_fresh_config())
	var before: int = systems.inventory["grass"]
	systems.supply_pending = true
	systems.supply_choices = [{"name": "Test", "items": {"grass": 3}}]
	var chosen := systems.choose_supply(0)
	_expect(chosen and systems.inventory["grass"] == before + 3 and not systems.supply_pending, "supply choices add configured inventory")

func _test_expansion_increases_world() -> void:
	var config := _fresh_config()
	config["world"]["expansion_interval"] = 0.2
	config["world"]["expansion_amount"] = 100.0
	var systems = Systems.new(config)
	var before: float = systems.simulation.world_radius
	systems.advance(0.3)
	_expect(systems.simulation.world_radius == before + 100.0, "map expansion increases playable area")

func _test_seeded_behavior_is_reproducible() -> void:
	var first = Simulation.new(_fresh_config(), 9912)
	var second = Simulation.new(_fresh_config(), 9912)
	for sim in [first, second]:
		var rabbit_id: int = sim.add_rabbit(Vector2(10.0, 12.0))
		sim.add_plant("grass", Vector2(70.0, 15.0))
		sim.rabbits[rabbit_id]["hunger"] = 50.0
		_step_many(sim, 4.0)
	var first_rabbit: Dictionary = first.rabbits.values()[0]
	var second_rabbit: Dictionary = second.rabbits.values()[0]
	_expect(first_rabbit["position"].is_equal_approx(second_rabbit["position"]) and is_equal_approx(first_rabbit["hunger"], second_rabbit["hunger"]), "fixed seeded behavior is reproducible")

func _test_spatial_hash_handles_prototype_scale() -> void:
	var config := _fresh_config()
	config["rabbit"]["reproduction_food_needed"] = 99999.0
	config["fox"]["reproduction_food_needed"] = 99999.0
	var sim = Simulation.new(config)
	for index in range(150):
		var position := Vector2.from_angle(float(index) * 2.399) * (40.0 + float(index % 13) * 20.0)
		sim.add_rabbit(position)
	for index in range(30):
		var position := Vector2.from_angle(float(index) * 1.713) * (80.0 + float(index % 7) * 28.0)
		sim.add_fox(position)
	for index in range(80):
		var position := Vector2.from_angle(float(index) * 2.117) * (50.0 + float(index % 10) * 24.0)
		sim.add_plant("grass" if index % 2 == 0 else "berry_bush", position)
	var started := Time.get_ticks_msec()
	for tick in range(10):
		sim.step(0.1)
	var elapsed := Time.get_ticks_msec() - started
	_expect(elapsed < 2500 and sim.last_tick_stats["queries"] < 1000, "spatial lookup remains practical at 150 rabbits and 30 foxes", "%d ms, %d queries" % [elapsed, sim.last_tick_stats["queries"]])
