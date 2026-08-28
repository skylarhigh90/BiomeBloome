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
	_test_social_vision_is_transitive_and_personal()
	_test_rabbit_finishes_meal_before_roaming()
	_test_rabbit_requires_local_or_social_food_vision()
	_test_rabbit_flees_nearby_fox()
	_test_fox_targets_nearby_rabbit()
	_test_hunt_removes_exact_prey()
	_test_plant_loses_food_when_eaten()
	_test_plant_regenerates()
	_test_plant_depletion_has_recovery_hysteresis()
	_test_rabbit_rejects_depleted_food()
	_test_rabbit_food_choice_is_distance_led()
	_test_carrot_patch_retains_fast_low_capacity_role()
	_test_rabbit_reproduction_creates_entity()
	_test_rabbit_reproduction_requires_readiness()
	_test_fox_reproduction_creates_entity()
	_test_fox_reproduction_requires_readiness()
	_test_hunger_summary_distinguishes_foraging_from_danger()
	_test_starvation_kills_creatures()
	_test_pause_stops_simulation_time()
	_test_speed_multipliers()
	_test_objective_stability_starts_immediately_and_resets()
	_test_objective_completion_preserves_world()
	_test_supply_adds_inventory()
	_test_supply_arrival_pauses_and_restores_speed()
	_test_expansion_increases_world()
	_test_seeded_behavior_is_reproducible()
	_test_rabbit_traits_are_diverse()
	_test_clustered_rabbits_diverge()
	_test_rabbits_spread_across_similar_food_targets()
	_test_spatial_hash_handles_prototype_scale()

func _fresh_config() -> Dictionary:
	return Config.make().duplicate(true)

func _flat_food_config() -> Dictionary:
	var config := _fresh_config()
	config["world"]["forest_patch_count"] = 0
	config["terrain"]["thicket"]["patch_count"] = 0
	config["terrain"]["stream"]["enabled"] = false
	return config

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
	# Food acquisition is isolated here; Stream reachability has dedicated tests.
	var sim = Simulation.new(_flat_food_config())
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	sim.add_plant("carrot_patch", Vector2(55.0, 0.0))
	sim.rabbits[rabbit_id]["hunger"] = 50.0
	sim.step(0.1)
	_expect(sim.rabbits[rabbit_id]["behavior"] == "seek_food" and sim.rabbits[rabbit_id]["target_id"] != -1, "rabbits seek nearby food")

func _test_social_vision_is_transitive_and_personal() -> void:
	var chain_config := _flat_food_config()
	chain_config["rabbit"]["food_detection_radius"] = 80.0
	chain_config["rabbit"]["social_proximity_radius"] = 70.0
	var chain_sim = Simulation.new(chain_config, 6123)
	var chain_ids: Array[int] = []
	for index in range(5):
		var rabbit_id: int = chain_sim.add_rabbit(Vector2(float(index) * 70.0, 0.0))
		chain_sim.rabbits[rabbit_id]["hunger"] = 55.0
		chain_ids.append(rabbit_id)
	var chain_food: int = chain_sim.add_plant("carrot_patch", Vector2(280.0, 0.0))
	chain_sim.step(0.1)
	var chain_shared: bool = int(chain_sim.rabbits[chain_ids[0]]["target_id"]) == chain_food

	var local_config := _flat_food_config()
	local_config["rabbit"]["food_detection_radius"] = 80.0
	local_config["rabbit"]["social_proximity_radius"] = 0.0
	var local_sim = Simulation.new(local_config, 6123)
	var local_ids: Array[int] = []
	for index in range(5):
		var rabbit_id: int = local_sim.add_rabbit(Vector2(float(index) * 70.0, 0.0))
		local_sim.rabbits[rabbit_id]["hunger"] = 55.0
		local_ids.append(rabbit_id)
	var local_food: int = local_sim.add_plant("carrot_patch", Vector2(280.0, 0.0))
	local_sim.step(0.1)
	var local_blind: bool = int(local_sim.rabbits[local_ids[0]]["target_id"]) == -1

	var personal_config := _flat_food_config()
	personal_config["rabbit"]["food_detection_radius"] = 100.0
	personal_config["rabbit"]["social_proximity_radius"] = 300.0
	var personal_sim = Simulation.new(personal_config, 6123)
	var first_id: int = personal_sim.add_rabbit(Vector2.ZERO)
	var second_id: int = personal_sim.add_rabbit(Vector2(260.0, 0.0))
	var left_food: int = personal_sim.add_plant("carrot_patch", Vector2(80.0, 0.0))
	var right_food: int = personal_sim.add_plant("carrot_patch", Vector2(340.0, 0.0))
	personal_sim.rabbits[first_id]["hunger"] = 55.0
	personal_sim.rabbits[second_id]["hunger"] = 55.0
	personal_sim.step(0.1)
	var personal_routes: bool = int(personal_sim.rabbits[first_id]["target_id"]) == left_food \
		and int(personal_sim.rabbits[second_id]["target_id"]) == right_food
	_expect(chain_shared and local_blind and personal_routes, "social vision shares food transitively while route choice remains individual")

func _test_rabbit_finishes_meal_before_roaming() -> void:
	var config := _flat_food_config()
	var sim = Simulation.new(config, 4217)
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	var plant_id: int = sim.add_plant("carrot_patch", Vector2.ZERO)
	sim.rabbits[rabbit_id]["hunger"] = config["rabbit"]["hungry_at"] + 1.0
	var food_before: float = sim.plants[plant_id]["food"]
	var meal_ticks := 0
	for tick in range(20):
		sim.step(0.1)
		if sim.rabbits[rabbit_id]["behavior"] == "eat":
			meal_ticks += 1
		if meal_ticks > 0 and not sim.rabbits[rabbit_id]["food_motivated"]:
			break
	var rabbit: Dictionary = sim.rabbits[rabbit_id]
	var consumed: float = food_before - float(sim.plants[plant_id]["food"])
	var finished_meal: bool = meal_ticks >= 4 and consumed >= 1.5 and rabbit["hunger"] <= config["rabbit"]["sated_at"]
	sim.step(0.1)
	var moved_on: bool = rabbit["behavior"] == "wander" and rabbit["target_id"] == -1 and not rabbit["food_motivated"]
	var distance_when_hungry_again := 0.0
	for tick in range(200):
		sim.step(0.1)
		if rabbit["food_motivated"]:
			distance_when_hungry_again = rabbit["position"].distance_to(sim.plants[plant_id]["position"])
			break
	var explored_beyond_patch: bool = distance_when_hungry_again >= 40.0
	_expect(finished_meal and moved_on and explored_beyond_patch, "rabbits finish a meal and roam beyond the patch", "%d eating ticks, %.2f food consumed, %.1f units away when hungry again" % [meal_ticks, consumed, distance_when_hungry_again])

func _test_rabbit_requires_local_or_social_food_vision() -> void:
	var config := _flat_food_config()
	config["rabbit"]["food_detection_radius"] = 90.0
	config["rabbit"]["social_proximity_radius"] = 0.0
	var sim = Simulation.new(config)
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	var plant_id: int = sim.add_plant("carrot_patch", Vector2(260.0, 0.0))
	sim.rabbits[rabbit_id]["hunger"] = 60.0
	var before: float = sim.plants[plant_id]["food"]
	sim.step(0.1)
	_expect(sim.plants[plant_id]["food"] == before and sim.rabbits[rabbit_id]["target_id"] == -1, "food remains outside an isolated rabbit's local vision", "%.2f -> %.2f; target %s" % [before, sim.plants[plant_id]["food"], str(sim.rabbits[rabbit_id]["target_id"])])

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
	var plant_id: int = sim.add_plant("carrot_patch", Vector2.ZERO)
	sim.plants[plant_id]["food"] = 0.0
	sim.step(1.0)
	_expect(sim.plants[plant_id]["food"] > 0.0 and sim.plants[plant_id]["food"] <= sim.plants[plant_id]["max_food"], "plant food regenerates")

func _test_plant_depletion_has_recovery_hysteresis() -> void:
	var sim = Simulation.new(_flat_food_config())
	var plant_id: int = sim.add_plant("carrot_patch", Vector2.ZERO)
	var states: Array[String] = []
	sim.plant_state_changed.connect(func(changed_id: int, _previous: String, current: String, _position: Vector2) -> void:
		if changed_id == plant_id:
			states.append(current)
	)
	sim.plants[plant_id]["food"] = 0.0
	var unavailable_while_recovering := true
	var recovered_at := -1.0
	for _tick in range(400):
		sim.step(0.1)
		var plant: Dictionary = sim.plants[plant_id]
		if bool(plant["depletion_latched"]) and sim.plant_is_food_available(plant):
			unavailable_while_recovering = false
		if not bool(plant["depletion_latched"]):
			recovered_at = sim.simulation_time
			break
	_expect(
		unavailable_while_recovering and _has_plant_state_sequence(states) \
			and recovered_at >= 15.0 and recovered_at <= 24.0,
		"depleted Carrots remain unavailable through a visible recovery window",
		"states %s, recovered %.1fs" % [str(states), recovered_at],
	)

func _has_plant_state_sequence(states: Array[String]) -> bool:
	return "depleted" in states and "recovering" in states and "healthy" in states \
		and states.find("depleted") < states.find("recovering") \
		and states.find("recovering") < states.find("healthy")

func _test_rabbit_rejects_depleted_food() -> void:
	var sim = Simulation.new(_flat_food_config())
	var depleted_id: int = sim.add_plant("carrot_patch", Vector2(-20.0, 0.0))
	var healthy_id: int = sim.add_plant("carrot_patch", Vector2(65.0, 0.0))
	sim.plants[depleted_id]["food"] = 0.0
	sim._update_plant_ecology_state(sim.plants[depleted_id])
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	sim.rabbits[rabbit_id]["hunger"] = 55.0
	sim.step(0.1)
	_expect(sim.rabbits[rabbit_id]["target_id"] == healthy_id and not sim.plant_is_food_available(sim.plants[depleted_id]), "Rabbits reject depletion-latched food and choose a usable alternative")

func _test_rabbit_food_choice_is_distance_led() -> void:
	var equal_sim = Simulation.new(_flat_food_config(), 6641)
	var near_id: int = equal_sim.add_plant("carrot_patch", Vector2(-35.0, 0.0))
	equal_sim.add_plant("carrot_patch", Vector2(145.0, 0.0))
	var rabbit_id: int = equal_sim.add_rabbit(Vector2.ZERO)
	equal_sim.rabbits[rabbit_id]["hunger"] = 55.0
	equal_sim.step(0.1)
	_expect(int(equal_sim.rabbits[rabbit_id]["target_id"]) == near_id, "reachable food choice is led by route distance")

func _test_carrot_patch_retains_fast_low_capacity_role() -> void:
	var plants: Dictionary = _fresh_config()["plants"]
	var carrots: Dictionary = plants["carrot_patch"]
	var berries: Dictionary = plants["berry_bush"]
	_expect(
		float(carrots["max_food"]) < float(berries["max_food"])
		and float(carrots["regeneration"]) > float(berries["regeneration"]),
		"carrot patches remain the fast-growing, low-capacity food",
	)

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
	sim.add_plant("carrot_patch", Vector2(4.0, 4.0))
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

func _test_hunger_summary_distinguishes_foraging_from_danger() -> void:
	var config := _fresh_config()
	var sim = Simulation.new(config)
	var finding_food: int = sim.add_rabbit(Vector2.ZERO)
	var without_food: int = sim.add_rabbit(Vector2(20.0, 0.0))
	var starving: int = sim.add_rabbit(Vector2(40.0, 0.0))
	sim.rabbits[finding_food]["hunger"] = config["rabbit"]["hunger_warning_at"] + 1.0
	sim.rabbits[finding_food]["behavior"] = "seek_food"
	sim.rabbits[without_food]["hunger"] = config["rabbit"]["hunger_warning_at"] + 2.0
	sim.rabbits[without_food]["behavior"] = "forage"
	sim.rabbits[starving]["hunger"] = config["rabbit"]["starvation_threshold"] + 1.0
	sim.rabbits[starving]["behavior"] = "seek_food"
	var summary: Dictionary = sim.hunger_summary("rabbit")
	_expect(summary["state"] == "starving" and summary["warning_count"] == 3 and summary["unserved_count"] == 1 and summary["starving_count"] == 1, "hunger summary separates rabbits finding food from rabbits that need help")

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

func _test_objective_stability_starts_immediately_and_resets() -> void:
	var config := _fresh_config()
	var milestone: Dictionary = config["progression"]["milestones"][0]
	milestone["rabbit_min"] = 1
	milestone["criteria"] = []
	milestone["stabilization"] = 3.0
	var systems = Systems.new(config)
	var rabbit_id: int = systems.simulation.add_rabbit(Vector2.ZERO)
	systems.advance(0.5)
	var progressed: bool = systems.run_director.milestone_stability > 0.39
	systems.simulation.kill_rabbit(rabbit_id, "test")
	systems.advance(0.1)
	_expect(progressed and is_zero_approx(systems.run_director.milestone_stability), "milestone stability starts immediately and resets")

func _test_objective_completion_preserves_world() -> void:
	var config := _fresh_config()
	var milestone: Dictionary = config["progression"]["milestones"][0]
	milestone["rabbit_min"] = 1
	milestone["criteria"] = []
	milestone["stabilization"] = 0.1
	var systems = Systems.new(config)
	var rabbit_id: int = systems.simulation.add_rabbit(Vector2.ZERO)
	var plant_id: int = systems.simulation.add_plant("carrot_patch", Vector2(40.0, 0.0))
	systems.advance(0.1)
	_expect(systems.run_director.completed_milestones.has("colony_gathers") and systems.simulation.rabbits.has(rabbit_id) and systems.simulation.plants.has(plant_id), "milestone completion preserves the world")

func _test_supply_adds_inventory() -> void:
	var systems = Systems.new(_fresh_config())
	var before: int = systems.inventory["carrot_patch"]
	systems.supply_pending = true
	systems.supply_choices = [{"name": "Test", "items": {"carrot_patch": 3}}]
	var chosen := systems.choose_supply(0)
	_expect(chosen and systems.inventory["carrot_patch"] == before + 3 and not systems.supply_pending, "supply choices add configured inventory")

func _test_supply_arrival_pauses_and_restores_speed() -> void:
	var config := _fresh_config()
	config["simulation"]["max_steps_per_frame"] = 100
	config["supply"]["interval"] = 0.2
	var systems = Systems.new(config)
	var announcement := {"paused": false}
	systems.supply_ready.connect(func(_choices: Array) -> void:
		announcement["paused"] = systems.is_paused()
	)
	systems.set_speed(2.0)
	systems.advance(0.2)
	var arrived_paused: bool = systems.supply_pending and systems.is_paused() and is_equal_approx(systems.supply_resume_speed, 2.0)
	var frozen_time: float = systems.simulation.simulation_time
	systems.set_speed(3.0)
	systems.advance(2.0)
	var stayed_frozen: bool = is_equal_approx(systems.simulation.simulation_time, frozen_time) and systems.is_paused()
	var placement_blocked: bool = not systems.can_place("rabbit", Vector2.ZERO)
	var claimed: bool = systems.choose_supply(0)
	var duplicate_blocked: bool = not systems.choose_supply(0)
	_expect(bool(announcement["paused"]) and arrived_paused and stayed_frozen and placement_blocked and claimed and duplicate_blocked and is_equal_approx(systems.simulation_speed, 2.0), "supply arrival freezes the meadow before announcing choices, blocks play, and restores the exact prior speed")

func _test_expansion_increases_world() -> void:
	var config := _fresh_config()
	var milestone: Dictionary = config["progression"]["milestones"][0]
	milestone["rabbit_min"] = 1
	milestone["criteria"] = []
	milestone["stabilization"] = 0.1
	milestone["effects"]["expand_world"] = 100.0
	var systems = Systems.new(config)
	var before: float = systems.simulation.world_radius
	systems.simulation.add_rabbit(Vector2.ZERO)
	systems.advance(0.1)
	_expect(systems.simulation.world_radius == before + 100.0, "milestone expansion increases playable area")

func _test_seeded_behavior_is_reproducible() -> void:
	var first = Simulation.new(_fresh_config(), 9912)
	var second = Simulation.new(_fresh_config(), 9912)
	for sim in [first, second]:
		var rabbit_id: int = sim.add_rabbit(Vector2(10.0, 12.0))
		sim.add_plant("carrot_patch", Vector2(70.0, 15.0))
		sim.rabbits[rabbit_id]["hunger"] = 50.0
		_step_many(sim, 4.0)
	var first_rabbit: Dictionary = first.rabbits.values()[0]
	var second_rabbit: Dictionary = second.rabbits.values()[0]
	_expect(first_rabbit["position"].is_equal_approx(second_rabbit["position"]) and is_equal_approx(first_rabbit["hunger"], second_rabbit["hunger"]), "fixed seeded behavior is reproducible")

func _test_rabbit_traits_are_diverse() -> void:
	var first = Simulation.new(_fresh_config(), 8821)
	var second = Simulation.new(_fresh_config(), 8821)
	var first_profiles: Array = []
	var second_profiles: Array = []
	var distinct_speeds: Dictionary = {}
	for index in range(8):
		for sim in [first, second]:
			var rabbit_id: int = sim.add_rabbit(Vector2(float(index) * 2.0, 0.0))
			var rabbit: Dictionary = sim.rabbits[rabbit_id]
			var profile := Vector3(rabbit["speed_scale"], rabbit["turn_scale"], rabbit["decision_interval"])
			if sim == first:
				first_profiles.append(profile)
				distinct_speeds[snappedf(rabbit["speed_scale"], 0.001)] = true
			else:
				second_profiles.append(profile)
	_expect(first_profiles == second_profiles and distinct_speeds.size() >= 6, "rabbit individuality is diverse and seed-reproducible")

func _test_clustered_rabbits_diverge() -> void:
	var config := _fresh_config()
	config["world"]["forest_patch_count"] = 0
	config["rabbit"]["hunger_rate"] = 0.0
	config["rabbit"]["hungry_at"] = 999.0
	var sim = Simulation.new(config, 7712)
	var first_id: int = sim.add_rabbit(Vector2.ZERO)
	var second_id: int = sim.add_rabbit(Vector2.ZERO)
	for rabbit_id in [first_id, second_id]:
		var rabbit: Dictionary = sim.rabbits[rabbit_id]
		rabbit["position"] = Vector2.ZERO
		rabbit["previous_position"] = Vector2.ZERO
		rabbit["velocity"] = Vector2.RIGHT * 12.0
		rabbit["previous_velocity"] = rabbit["velocity"]
		rabbit["wander_direction"] = Vector2.RIGHT
	_step_many(sim, 2.5)
	var distance: float = sim.rabbits[first_id]["position"].distance_to(sim.rabbits[second_id]["position"])
	_expect(distance >= 8.0, "co-located rabbits develop separate trajectories", "%.2f units apart" % distance)

func _test_rabbits_spread_across_similar_food_targets() -> void:
	var config := _flat_food_config()
	var sim = Simulation.new(config, 9814)
	var left_plant: int = sim.add_plant("carrot_patch", Vector2(-72.0, 0.0))
	var right_plant: int = sim.add_plant("carrot_patch", Vector2(72.0, 0.0))
	var chosen: Dictionary = {}
	for index in range(8):
		var position := Vector2(0.0, float(index - 4) * 1.5)
		var rabbit_id: int = sim.add_rabbit(position)
		sim.rabbits[rabbit_id]["hunger"] = 50.0
	sim.step(0.1)
	for rabbit in sim.rabbits.values():
		if rabbit["target_id"] in [left_plant, right_plant]:
			chosen[rabbit["target_id"]] = int(chosen.get(rabbit["target_id"], 0)) + 1
	var balanced: bool = chosen.size() == 2 and int(chosen[left_plant]) >= 2 and int(chosen[right_plant]) >= 2
	_expect(balanced, "similar food targets attract different rabbits", str(chosen))

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
		sim.add_plant("carrot_patch" if index % 2 == 0 else "berry_bush", position)
	var started := Time.get_ticks_msec()
	for tick in range(10):
		sim.step(0.1)
	var elapsed := Time.get_ticks_msec() - started
	_expect(elapsed < 2500 and sim.last_tick_stats["queries"] < 1000, "spatial lookup remains practical at 150 rabbits and 30 foxes", "%d ms, %d queries" % [elapsed, sim.last_tick_stats["queries"]])
