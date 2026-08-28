extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")
const HUD = preload("res://ui/game_hud.gd")

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_test_checkpoint_contract_and_reward_tiers()
	_test_colony_gathers_requires_population()
	_test_new_arrivals_requires_two_births()
	_test_young_foragers_require_born_rabbits_to_feed()
	_test_birthplaces_require_three_separated_births()
	_test_nursery_network_requires_three_live_groups()
	_test_first_hunt_requires_successful_predation()
	_test_life_returns_requires_fresh_birth()
	_test_two_safe_havens_are_spatial_and_stable()
	_test_local_nurseries_survive_unfed_rabbit_bridges()
	_test_safe_haven_counter_supports_three_zones()
	_test_two_distinct_foxes_and_birth_are_required()
	_test_final_cycle_is_fresh_ordered_and_latched()
	_test_reward_timing_and_persistent_expansions()
	_test_supply_pool_progression()
	_test_critical_is_armed_only_after_nursery_network()
	_test_loss_of_breeding_group_enters_critical_at_one_x()
	_test_fox_extinction_is_not_game_over()
	_test_inventory_and_pending_supply_do_not_prevent_critical()
	_test_supply_modal_pauses_critical_grace()
	_test_recovery_requires_living_settling_period()
	_test_failed_recovery_causes_game_over()
	_test_first_recovery_supply_is_not_repeated()
	_test_checkpoint_ui_uses_compact_live_progress()
	_test_checkpoint_ui_maps_every_evidence_type()
	_test_checkpoint_ui_distinguishes_live_hunger_states()
	_test_checkpoint_ui_uses_player_facing_guidance()
	_test_minor_and_major_feedback_are_distinct()
	_test_debug_retains_exact_evaluator_detail()
	_test_completion_ui_and_sandbox_epilogue()
	_test_fresh_system_resets_the_run()
	print("\n%d V0.5 compound progression tests passed; %d failed." % [passed, failures.size()])
	for failure in failures:
		printerr("FAILED: %s" % failure)
	quit(1 if not failures.is_empty() else 0)

func _fast_config() -> Dictionary:
	var config := Config.make().duplicate(true)
	config["simulation"]["max_steps_per_frame"] = 1000
	config["supply"]["interval"] = 100.0
	config["progression"]["spatial_sample_interval"] = 0.0
	config["rabbit"]["hunger_rate"] = 0.0
	config["rabbit"]["lifespan"] = 9999.0
	config["fox"]["hunger_rate"] = 0.0
	config["fox"]["lifespan"] = 9999.0
	for milestone in config["progression"]["milestones"]:
		milestone["stabilization"] = 0.2
		milestone["severe_decline_fraction"] = 1.1
	for criterion in config["progression"]["milestones"][2]["criteria"]:
		if str(criterion["type"]) == "born_rabbit_fed":
			criterion["minimum_age"] = 0.0
	config["progression"]["critical"]["entry_debounce"] = 0.2
	config["progression"]["critical"]["recovery_settling"] = 0.3
	config["progression"]["critical"]["grace_duration"] = 1.2
	config["progression"]["critical"]["first_rescue_delay"] = 0.2
	return config

func _expect(condition: bool, name: String, detail: String = "") -> void:
	if condition:
		passed += 1
		print("PASS: %s" % name)
	else:
		failures.append("%s%s" % [name, " — " + detail if not detail.is_empty() else ""])

func _ensure_rabbits(systems, count: int) -> void:
	while systems.simulation.population("rabbit") < count:
		var index: int = systems.simulation.population("rabbit")
		systems.simulation.add_rabbit(Vector2(float(index % 4) * 18.0, float(index / 4) * 18.0), "placement")

func _ensure_foxes(systems, count: int) -> void:
	while systems.simulation.population("fox") < count:
		var index: int = systems.simulation.population("fox")
		systems.simulation.add_fox(Vector2(90.0 + float(index) * 25.0, 0.0), "placement")

func _kill_all_rabbits(systems, cause: String = "test") -> void:
	for rabbit_id in systems.simulation.rabbits.keys():
		systems.simulation.kill_rabbit(rabbit_id, cause)

func _arrange_two_havens(systems, rabbit_count: int = 12) -> void:
	_arrange_havens(systems, rabbit_count, 2)

func _arrange_havens(systems, rabbit_count: int, haven_count: int) -> void:
	_ensure_rabbits(systems, rabbit_count)
	var centers := [Vector2(-230.0, -140.0), Vector2(230.0, -140.0)]
	if haven_count >= 3:
		centers.append(Vector2(240.0, 180.0))
	var ids: Array = systems.simulation.rabbits.keys()
	for index in range(ids.size()):
		var center: Vector2 = centers[index % centers.size()]
		var row := float(index / centers.size())
		var rabbit: Dictionary = systems.simulation.rabbits[ids[index]]
		rabbit["position"] = center + Vector2(0.0, row * 16.0)
		rabbit["previous_position"] = rabbit["position"]
		rabbit["velocity"] = Vector2.ZERO
		rabbit["previous_velocity"] = Vector2.ZERO
	for center in centers:
		for row in range(3):
			var plant_id: int = systems.simulation.add_plant("berry_bush", center + Vector2(0.0, 8.0 + float(row) * 24.0))
			systems.simulation.plants[plant_id]["food"] = 30.0

func _satisfy_current_checkpoint(systems) -> void:
	match systems.run_director.current_milestone_id():
		"colony_gathers":
			_ensure_rabbits(systems, 4)
		"new_arrivals":
			_ensure_rabbits(systems, 4)
			systems.simulation.add_rabbit(Vector2(-24.0, 8.0), "birth")
			systems.simulation.add_rabbit(Vector2(24.0, 8.0), "birth")
		"young_foragers":
			_ensure_rabbits(systems, 8)
			for young_id in systems.run_director.born_rabbit_ids.keys().slice(0, 2):
				systems.simulation.rabbits[young_id]["age"] = 12.0
				systems.run_director.record_creature_fed("rabbit", young_id, -1)
		"birthplaces":
			_ensure_rabbits(systems, 10)
			for center in [Vector2(-230.0, -140.0), Vector2(230.0, -140.0), Vector2(240.0, 180.0)]:
				systems.simulation.add_rabbit(center, "birth")
		"nursery_network":
			_arrange_havens(systems, 12, 3)
		"first_hunt":
			_ensure_rabbits(systems, 8)
			_ensure_foxes(systems, 1)
			var fox_id: int = systems.simulation.foxes.keys()[0]
			var prey_id: int = systems.simulation.rabbits.keys()[0]
			systems.run_director.record_predation(fox_id, prey_id, systems.simulation.rabbits[prey_id]["position"])
			systems.simulation.add_rabbit(Vector2(28.0, 8.0), "birth")
		"life_returns":
			_ensure_rabbits(systems, 9)
			_ensure_foxes(systems, 1)
			var fox_id: int = systems.simulation.foxes.keys()[0]
			systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[0], Vector2.ZERO)
			systems.simulation.add_rabbit(Vector2(30.0, 8.0), "birth")
			systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[1], Vector2.ZERO)
		"two_safe_havens":
			_arrange_two_havens(systems, 10)
			_ensure_foxes(systems, 1)
			var fox_id: int = systems.simulation.foxes.keys()[0]
			systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[0], Vector2.ZERO)
			systems.simulation.add_rabbit(Vector2(-210.0, 8.0), "birth")
		"predators_find_place":
			_arrange_havens(systems, 12, 3)
			_ensure_foxes(systems, 2)
			var fox_ids: Array = systems.simulation.foxes.keys()
			systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[0], Vector2.ZERO)
			systems.simulation.add_rabbit(Vector2(-210.0, 8.0), "birth")
			systems.run_director.record_predation(fox_ids[1], systems.simulation.rabbits.keys()[1], Vector2.ZERO)
		"living_ecosystem":
			_arrange_havens(systems, 14, 3)
			_ensure_foxes(systems, 2)
			var fox_ids: Array = systems.simulation.foxes.keys()
			systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[0], Vector2.ZERO)
			systems.simulation.add_rabbit(Vector2(-210.0, 8.0), "birth")
			systems.run_director.record_predation(fox_ids[1], systems.simulation.rabbits.keys()[1], Vector2.ZERO)
			systems.simulation.add_rabbit(Vector2(210.0, 8.0), "birth")
			systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[2], Vector2.ZERO)
	systems.advance(0.3)

func _advance_to(systems, milestone_id: String) -> void:
	var guard := 0
	while systems.run_director.current_milestone_id() != milestone_id and systems.run_director.run_state == RunDirector.STATE_PLAYING and guard < 16:
		_satisfy_current_checkpoint(systems)
		guard += 1

func _complete_run(systems) -> void:
	var guard := 0
	while systems.run_director.run_state == RunDirector.STATE_PLAYING and guard < 16:
		_satisfy_current_checkpoint(systems)
		guard += 1

func _test_checkpoint_contract_and_reward_tiers() -> void:
	var config := Config.make()
	var ids: Array[String] = []
	var tiers: Array[String] = []
	var sequences: Array = []
	var criterion_counts: Array[int] = []
	var safe_haven_targets: Array[int] = []
	var rabbit_targets: Array[int] = []
	for milestone in config["progression"]["milestones"]:
		ids.append(str(milestone["id"]))
		tiers.append(str(milestone["tier"]))
		sequences.append(milestone.get("event_sequence", []))
		criterion_counts.append(milestone.get("criteria", []).size())
		rabbit_targets.append(int(milestone.get("rabbit_min", 0)))
		for criterion in milestone.get("criteria", []):
			if str(criterion.get("type", "")) == "safe_havens":
				safe_haven_targets.append(int(criterion.get("target", 0)))
	_expect(ids == ["colony_gathers", "new_arrivals", "young_foragers", "birthplaces", "nursery_network", "first_hunt", "life_returns", "two_safe_havens", "predators_find_place", "living_ecosystem"] \
		and tiers == ["minor", "minor", "minor", "minor", "major", "minor", "major", "minor", "major", "final"] \
		and sequences[5] == ["hunt", "birth"] \
		and sequences[6] == ["hunt", "birth", "hunt"] \
		and sequences[9] == ["hunt", "birth", "hunt", "birth", "hunt"] \
		and criterion_counts == [0, 1, 1, 1, 1, 1, 1, 2, 4, 5] \
		and rabbit_targets == [4, 6, 8, 10, 12, 6, 7, 8, 10, 12] \
		and safe_haven_targets == [3, 2, 3, 3], "the ten-checkpoint arc adds a deliberate five-step rabbit opening before the existing predator progression")

func _test_colony_gathers_requires_population() -> void:
	var systems = Systems.new(_fast_config())
	_ensure_rabbits(systems, 3)
	systems.advance(0.3)
	var three_blocked: bool = systems.run_director.current_milestone_id() == "colony_gathers"
	_ensure_rabbits(systems, 4)
	systems.advance(0.3)
	_expect(three_blocked and systems.run_director.has_completed("colony_gathers"), "A Colony Gathers requires the player to establish the four-rabbit population target")

func _test_new_arrivals_requires_two_births() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "new_arrivals")
	_ensure_rabbits(systems, 8)
	systems.advance(0.3)
	var placements_blocked: bool = systems.run_director.current_milestone_id() == "new_arrivals"
	systems.simulation.add_rabbit(Vector2(-20.0, 0.0), "birth")
	systems.advance(0.3)
	var one_birth_blocked: bool = systems.run_director.current_milestone_id() == "new_arrivals"
	systems.simulation.add_rabbit(Vector2(20.0, 0.0), "birth")
	systems.advance(0.3)
	_expect(placements_blocked and one_birth_blocked and systems.run_director.has_completed("new_arrivals"), "New Arrivals requires two natural births; placed rabbits cannot satisfy the target")

func _test_young_foragers_require_born_rabbits_to_feed() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "young_foragers")
	_ensure_rabbits(systems, 8)
	var placed_ids: Array = systems.run_director.placed_rabbit_ids.keys()
	systems.run_director.record_creature_fed("rabbit", placed_ids[0], -1)
	systems.advance(0.3)
	var placed_feeding_blocked: bool = systems.run_director.current_milestone_id() == "young_foragers"
	var young_ids: Array = systems.run_director.born_rabbit_ids.keys()
	for young_id in young_ids:
		systems.simulation.rabbits[young_id]["age"] = 12.0
	systems.run_director.record_creature_fed("rabbit", young_ids[0], -1)
	systems.advance(0.3)
	var one_young_blocked: bool = systems.run_director.current_milestone_id() == "young_foragers"
	systems.run_director.record_creature_fed("rabbit", young_ids[1], -1)
	systems.advance(0.3)
	_expect(placed_feeding_blocked and one_young_blocked and systems.run_director.has_completed("young_foragers"), "Young Foragers requires two meadow-born rabbits to grow and feed")

func _test_birthplaces_require_three_separated_births() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "birthplaces")
	_ensure_rabbits(systems, 10)
	systems.simulation.add_rabbit(Vector2(-230.0, -140.0), "birth")
	systems.simulation.add_rabbit(Vector2(-210.0, -140.0), "birth")
	systems.simulation.add_rabbit(Vector2(230.0, -140.0), "birth")
	systems.advance(0.3)
	var two_areas_blocked: bool = systems.run_director.current_milestone_id() == "birthplaces"
	systems.simulation.add_rabbit(Vector2(240.0, 180.0), "birth")
	systems.advance(0.3)
	_expect(two_areas_blocked and systems.run_director.has_completed("birthplaces"), "Life Across the Meadow requires fresh births in three genuinely separated areas")

func _test_nursery_network_requires_three_live_groups() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][4]["stabilization"] = 0.5
	var systems = Systems.new(config)
	_advance_to(systems, "nursery_network")
	_arrange_havens(systems, 12, 2)
	systems.advance(0.6)
	var two_groups_blocked: bool = systems.run_director.current_milestone_id() == "nursery_network"
	_arrange_havens(systems, 12, 3)
	systems.advance(0.6)
	_expect(two_groups_blocked and systems.run_director.has_completed("nursery_network"), "A Nursery Network requires three simultaneous well-fed groups with at least three rabbits each")

func _test_first_hunt_requires_successful_predation() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "first_hunt")
	_ensure_rabbits(systems, 6)
	_ensure_foxes(systems, 1)
	var fox_id: int = systems.simulation.foxes.keys()[0]
	var prey_id: int = systems.simulation.rabbits.keys()[0]
	systems.simulation.foxes[fox_id]["behavior"] = "hunt"
	systems.simulation.foxes[fox_id]["target_id"] = prey_id
	systems.advance(0.3)
	var chase_blocked: bool = systems.run_director.current_milestone_id() == "first_hunt"
	var prey_position: Vector2 = systems.simulation.rabbits[prey_id]["position"]
	systems.simulation.foxes[fox_id]["position"] = prey_position
	systems.simulation.foxes[fox_id]["previous_position"] = prey_position
	systems.simulation.foxes[fox_id]["hunger"] = 60.0
	systems.simulation.foxes[fox_id]["capture_progress"] = 0.99
	systems.advance(0.5)
	var hunt_without_recovery_blocked: bool = systems.run_director.current_milestone_id() == "first_hunt" \
		and systems.run_director.sequence_progress == 1
	systems.simulation.add_rabbit(Vector2(70.0, 0.0), "birth")
	systems.advance(0.3)
	_expect(chase_blocked and hunt_without_recovery_blocked and systems.run_director.has_completed("first_hunt"), "Recovery After the Hunt requires a successful predation event followed by natural renewal")

func _test_life_returns_requires_fresh_birth() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "life_returns")
	_ensure_rabbits(systems, 9)
	_ensure_foxes(systems, 1)
	var fox_id: int = systems.simulation.foxes.keys()[0]
	systems.simulation.add_rabbit(Vector2(70.0, 0.0), "birth")
	var birth_out_of_order_blocked: bool = systems.run_director.sequence_progress == 0
	systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(74.0, 0.0), "birth")
	systems.advance(0.3)
	var partial_cycle_blocked: bool = systems.run_director.current_milestone_id() == "life_returns" and systems.run_director.sequence_progress == 2
	systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[1], Vector2.ZERO)
	systems.advance(0.3)
	_expect(birth_out_of_order_blocked and partial_cycle_blocked and systems.run_director.has_completed("life_returns"), "Predator–Prey Rhythm requires hunt, renewal, then another hunt in order")

func _test_two_safe_havens_are_spatial_and_stable() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][7]["stabilization"] = 0.5
	var systems = Systems.new(config)
	_advance_to(systems, "two_safe_havens")
	_ensure_rabbits(systems, 8)
	_ensure_foxes(systems, 1)
	var fox_id: int = systems.simulation.foxes.keys()[0]
	systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(-210.0, 8.0), "birth")
	var ids: Array = systems.simulation.rabbits.keys()
	for index in range(ids.size()):
		var rabbit: Dictionary = systems.simulation.rabbits[ids[index]]
		rabbit["position"] = Vector2(-245.0 + float(index) * 70.0, 0.0)
		rabbit["previous_position"] = rabbit["position"]
	for plant in systems.simulation.plants.values():
		plant["food"] = 0.0
		plant["depletion_latched"] = true
	var shared_plant_id: int = systems.simulation.add_plant("berry_bush", Vector2.ZERO)
	systems.simulation.plants[shared_plant_id]["food"] = 30.0
	var stretched_rejected := not bool(systems.run_director.spatial_evidence(systems.simulation)["met"])
	_arrange_two_havens(systems)
	systems.advance(0.2)
	var transient_rejected: bool = systems.run_director.current_milestone_id() == "two_safe_havens"
	for index in range(ids.size()):
		systems.simulation.rabbits[ids[index]]["position"] = Vector2(float(index) * 12.0, 0.0)
	systems.advance(0.1)
	_arrange_two_havens(systems)
	systems.advance(0.4)
	var short_hold_rejected: bool = systems.run_director.current_milestone_id() == "two_safe_havens"
	systems.advance(0.2)
	_expect(stretched_rejected and transient_rejected and short_hold_rejected and systems.run_director.has_completed("two_safe_havens"), "Havens Under Pressure requires a hunt-renewal cycle plus two separated refuges that survive the hold", str({
		"stretched_rejected": stretched_rejected,
		"transient_rejected": transient_rejected,
		"short_hold_rejected": short_hold_rejected,
		"completed": systems.run_director.has_completed("two_safe_havens"),
	}))

func _test_local_nurseries_survive_unfed_rabbit_bridges() -> void:
	var systems = Systems.new(_fast_config())
	var sim = systems.simulation
	for x in [-210.0, -194.0, -90.0, 30.0, 150.0, 194.0, 210.0]:
		sim.add_rabbit(Vector2(x, 0.0))
	for x in [-210.0, 210.0]:
		var plant_id: int = sim.add_plant("berry_bush", Vector2(x, 10.0))
		sim.plants[plant_id]["food"] = 30.0
	var evidence: Dictionary = systems.run_director.spatial_evidence(sim, {
		"target": 2,
		"rabbits_per_group": 2,
		"minimum_separation": 280.0,
		"minimum_local_food": 12.0,
	})
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 2, "local nursery nuclei remain valid when unrelated unfed rabbits form a proximity chain", str(evidence))

func _test_safe_haven_counter_supports_three_zones() -> void:
	var systems = Systems.new(_fast_config())
	var sim = systems.simulation
	var centers := [Vector2(-250.0, -170.0), Vector2(250.0, -170.0), Vector2(-250.0, 170.0)]
	for center in centers:
		sim.add_rabbit(center + Vector2(-8.0, 0.0))
		sim.add_rabbit(center + Vector2(8.0, 0.0))
		var plant_id: int = sim.add_plant("berry_bush", center + Vector2(0.0, 10.0))
		sim.plants[plant_id]["food"] = 30.0
	var evidence: Dictionary = systems.run_director.spatial_evidence(sim, {
		"target": 3,
		"rabbits_per_group": 2,
		"minimum_separation": 280.0,
		"minimum_local_food": 12.0,
	})
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 3, "Safe Haven evidence can count three mutually separated local nursery zones", str(evidence))

func _test_two_distinct_foxes_and_birth_are_required() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "predators_find_place")
	_arrange_havens(systems, 12, 3)
	_ensure_foxes(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(-210.0, 8.0), "birth")
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[1], Vector2.ZERO)
	systems.advance(0.3)
	var one_fox_blocked: bool = systems.run_director.current_milestone_id() == "predators_find_place"
	systems.run_director.record_predation(fox_ids[1], systems.simulation.rabbits.keys()[2], Vector2.ZERO)
	systems.advance(0.3)
	_expect(one_fox_blocked and systems.run_director.has_completed("predators_find_place"), "Predators Find Their Place requires two distinct hunters, a complete recovery rhythm, safe havens, and enough prey per fox")

func _test_final_cycle_is_fresh_ordered_and_latched() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][9]["stabilization"] = 0.6
	config["progression"]["milestones"][9]["evidence_window"] = 0.2
	var systems = Systems.new(config)
	_advance_to(systems, "predators_find_place")
	_satisfy_current_checkpoint(systems)
	var fresh_reset: bool = systems.run_director.current_milestone_id() == "living_ecosystem" and systems.run_director.sequence_progress == 0
	_arrange_havens(systems, 14, 3)
	_ensure_foxes(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	systems.simulation.add_rabbit(Vector2(-210.0, 8.0), "birth")
	var birth_first_ignored: bool = systems.run_director.sequence_progress == 0
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[1], Vector2.ZERO)
	var wrong_order_blocked: bool = systems.run_director.sequence_progress == 1 and not systems.run_director.sequence_completed
	systems.simulation.add_rabbit(Vector2(-210.0, 8.0), "birth")
	systems.run_director.record_predation(fox_ids[1], systems.simulation.rabbits.keys()[2], Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(210.0, 8.0), "birth")
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[3], Vector2.ZERO)
	systems.advance(0.3)
	var latched_after_window: bool = systems.run_director.sequence_completed and systems.run_director.run_state == RunDirector.STATE_PLAYING
	systems.advance(0.4)
	_expect(fresh_reset and birth_first_ignored and wrong_order_blocked and latched_after_window and systems.run_director.run_state == RunDirector.STATE_COMPLETED, "Living Ecosystem needs a fresh hunt-first five-step cycle, distributed renewal, and latches the proof through the final hold")

func _test_reward_timing_and_persistent_expansions() -> void:
	var systems = Systems.new(_fast_config())
	var preserved_plant: int = systems.simulation.add_plant("carrot_patch", Vector2(120.0, 0.0))
	_advance_to(systems, "nursery_network")
	var before_major: float = systems.simulation.world_radius
	_satisfy_current_checkpoint(systems)
	var first_major_ok: bool = systems.simulation.world_radius == before_major + 145.0 and systems.run_director.is_unlocked("fox") and systems.inventory["fox"] == 2 and systems.run_director.supply_pool == "web"
	_advance_to(systems, "life_returns")
	var before_second: float = systems.simulation.world_radius
	_satisfy_current_checkpoint(systems)
	var second_major_ok: bool = systems.simulation.world_radius == before_second + 145.0
	_advance_to(systems, "predators_find_place")
	var before_third: float = systems.simulation.world_radius
	_satisfy_current_checkpoint(systems)
	var third_major_ok: bool = systems.simulation.world_radius == before_third + 145.0 and systems.run_director.supply_pool == "living"
	var after: float = systems.simulation.world_radius
	systems.advance(0.5)
	_expect(first_major_ok and second_major_ok and third_major_ok and after == 795.0 and systems.simulation.world_radius == after and systems.simulation.plants.has(preserved_plant), "major rewards occur at checkpoints 5, 7, and 9 exactly once without resetting the world")

func _test_supply_pool_progression() -> void:
	var config := Config.make()
	var pools: Dictionary = config["supply"]["pools"]
	var living_rabbit_bundles := 0
	var living_plant_units := 0
	for bundle in pools["living"]:
		if bundle["items"].has("rabbit"):
			living_rabbit_bundles += 1
		living_plant_units += int(bundle["items"].get("carrot_patch", 0)) + int(bundle["items"].get("berry_bush", 0))
	_expect(pools.size() == 3 and float(config["supply"]["interval"]) == 90.0 and living_rabbit_bundles == 1 and living_plant_units >= 8, "supplies stay on three pools and Living shifts toward plant support with fewer rabbit top-ups")

func _test_critical_is_armed_only_after_nursery_network() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "nursery_network")
	_kill_all_rabbits(systems)
	systems.advance(1.0)
	var safe_before: bool = systems.run_director.run_state == RunDirector.STATE_PLAYING and not systems.run_director.rabbit_failure_armed
	var second = Systems.new(_fast_config())
	_advance_to(second, "first_hunt")
	_expect(safe_before and second.run_director.rabbit_failure_armed, "Critical remains dormant until the Nursery Network is established")

func _enter_critical(systems) -> void:
	_advance_to(systems, "first_hunt")
	_kill_all_rabbits(systems, "starvation")
	systems.inventory["rabbit"] = 0
	systems.supply_pending = false
	systems.supply_choices = []
	systems.supply_time_remaining = 100.0
	systems.advance(0.3)

func _test_loss_of_breeding_group_enters_critical_at_one_x() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "first_hunt")
	systems.set_speed(3.0)
	_kill_all_rabbits(systems)
	systems.inventory["rabbit"] = 0
	systems.advance(0.1)
	_expect(systems.run_director.run_state == RunDirector.STATE_CRITICAL and is_equal_approx(systems.simulation_speed, 1.0), "loss of breeding recovery capacity enters Critical and returns speed to 1x")

func _test_fox_extinction_is_not_game_over() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "first_hunt")
	_ensure_foxes(systems, 1)
	for fox_id in systems.simulation.foxes.keys():
		systems.simulation.kill_fox(fox_id, "test")
	systems.advance(1.5)
	_expect(systems.run_director.run_state == RunDirector.STATE_PLAYING, "fox extinction alone does not trigger Critical or Game Over")

func _test_inventory_and_pending_supply_do_not_prevent_critical() -> void:
	var with_inventory = Systems.new(_fast_config())
	_advance_to(with_inventory, "first_hunt")
	_kill_all_rabbits(with_inventory)
	with_inventory.inventory["rabbit"] = 3
	with_inventory.advance(0.3)
	var inventory_failed: bool = with_inventory.run_director.run_state == RunDirector.STATE_CRITICAL
	var with_supply = Systems.new(_fast_config())
	_advance_to(with_supply, "first_hunt")
	_kill_all_rabbits(with_supply)
	with_supply.inventory["rabbit"] = 3
	with_supply.supply_pending = true
	with_supply.supply_choices = [{"name": "Carrot starters", "items": {"rabbit": 2}}]
	with_supply.advance(0.3)
	_expect(inventory_failed and with_supply.run_director.run_state == RunDirector.STATE_CRITICAL, "only living rabbits count toward collapse prevention")

func _test_supply_modal_pauses_critical_grace() -> void:
	var systems = Systems.new(_fast_config())
	_enter_critical(systems)
	systems.supply_pending = true
	systems.supply_choices = [{"name": "Fresh harvest", "items": {"carrot_patch": 1}}]
	var before: float = systems.run_director.critical_elapsed
	systems.advance(2.0)
	_expect(systems.run_director.run_state == RunDirector.STATE_CRITICAL and is_equal_approx(systems.run_director.critical_elapsed, before), "the blocking supply chooser pauses hidden Critical grace")

func _test_recovery_requires_living_settling_period() -> void:
	var systems = Systems.new(_fast_config())
	_enter_critical(systems)
	systems.supply_pending = false
	systems.supply_choices = []
	systems.forced_recovery_supply = false
	systems.supply_time_remaining = 100.0
	systems.simulation.add_rabbit(Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(18.0, 0.0))
	systems.advance(0.1)
	var still_critical: bool = systems.run_director.run_state == RunDirector.STATE_CRITICAL
	systems.advance(0.3)
	_expect(still_critical and systems.run_director.run_state == RunDirector.STATE_PLAYING, "a restored living breeding group must settle before Critical recovery")

func _test_failed_recovery_causes_game_over() -> void:
	var config := _fast_config()
	config["progression"]["critical"]["first_rescue_delay"] = 5.0
	config["progression"]["critical"]["grace_duration"] = 0.6
	var systems = Systems.new(config)
	_enter_critical(systems)
	systems.advance(0.7)
	_expect(systems.run_director.run_state == RunDirector.STATE_GAME_OVER and is_zero_approx(systems.simulation_speed), "unrecovered Critical state ends the run")

func _test_first_recovery_supply_is_not_repeated() -> void:
	var systems = Systems.new(_fast_config())
	_enter_critical(systems)
	systems.advance(0.3)
	var useful_first := false
	var recovery_index := -1
	for index in range(systems.supply_choices.size()):
		var bundle: Dictionary = systems.supply_choices[index]
		if int(bundle["items"].get("rabbit", 0)) >= 2:
			useful_first = true
			recovery_index = index
	if recovery_index >= 0:
		systems.choose_supply(recovery_index)
	systems.forced_recovery_supply = false
	systems.supply_time_remaining = 100.0
	systems.simulation.add_rabbit(Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(18.0, 0.0))
	systems.advance(0.4)
	_kill_all_rabbits(systems)
	systems.inventory["rabbit"] = 0
	systems.supply_time_remaining = 100.0
	systems.advance(0.3)
	_expect(useful_first and systems.run_director.critical_episode_count == 2 and not systems.forced_recovery_supply and systems.supply_time_remaining > 90.0, "the first Critical gets one ordinary recovery supply and later episodes do not")

func _test_checkpoint_ui_uses_compact_live_progress() -> void:
	var systems = Systems.new(_fast_config())
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud.refresh()
	var rabbit_row: Dictionary = hud.objective_progress_view.goal_rows["rabbit_population"]
	var initial_population: String = rabbit_row["value"].text
	systems.simulation.add_rabbit(Vector2.ZERO)
	hud.refresh()
	rabbit_row = hud.objective_progress_view.goal_rows["rabbit_population"]
	var live_population: String = rabbit_row["value"].text
	var joined := "\n".join([
		hud.objective_eyebrow.text,
		hud.objective_title.text,
		hud.objective_body.text,
		hud.objective_progress_view.keep_heading.text,
		hud.objective_progress_view.finish_heading.text,
		rabbit_row["title"].text,
		rabbit_row["value"].text,
		hud.objective_progress_view.next_label.text,
	]).to_lower()
	var checklist_layout: bool = "checkpoint 1 of 10" in joined \
		and "keep" in joined \
		and "finish" in joined \
		and "rabbits alive" in joined \
		and "try this" in hud.objective_progress_view.next_heading.text.to_lower()
	var animal_heuristic: bool = rabbit_row["glyph"] != null and rabbit_row["glyph"].kind == "rabbit"
	var actual_progress: bool = initial_population == "0 / min 4" and live_population == "1 / min 4"
	var compact: bool = is_equal_approx(hud.objective_panel.custom_minimum_size.x, 360.0)
	var info_available: bool = hud.objective_progress_view.details_button.text == "Need a hint?" and not hud.objective_progress_view.details_box.visible
	hud.objective_progress_view.details_button.pressed.emit()
	var info_open: bool = hud.objective_progress_view.details_box.visible and hud.objective_progress_view.details_button.text == "Hide hint"
	hud.objective_progress_view.details_button.pressed.emit()
	var info_closed: bool = not hud.objective_progress_view.details_box.visible and hud.objective_progress_view.details_button.text == "Need a hint?"
	_expect(checklist_layout and animal_heuristic and actual_progress and compact and info_available and info_open and info_closed, "checkpoint UI uses a compact task/status checklist with recognizable population art and optional nudges", joined)
	hud.free()

func _test_checkpoint_ui_maps_every_evidence_type() -> void:
	var mapped := true
	var observed: Array[String] = []
	for index in range(Config.make()["progression"]["milestones"].size()):
		var systems = Systems.new(_fast_config())
		systems.run_director.milestone_index = index
		var progress: Dictionary = systems.current_objective_progress()
		var hud = HUD.new()
		root.add_child(hud)
		hud.setup(systems)
		hud.refresh()
		for configured_goal in progress["goals"]:
			var goal: Dictionary = configured_goal
			var goal_id := str(goal["id"])
			if str(goal["type"]) == "ordered_cycle":
				for step_index in range(progress["sequence"].size()):
					var step_id := "%s_step_%d" % [goal_id, step_index]
					mapped = mapped and hud.objective_progress_view.goal_rows.has(step_id)
					if hud.objective_progress_view.goal_rows.has(step_id):
						var step_row: Dictionary = hud.objective_progress_view.goal_rows[step_id]
						mapped = mapped and step_row["title"].text in ["Fox kills a rabbit", "Rabbit is born"]
						observed.append("%s %s" % [step_id, step_row["value"].text])
				continue
			var row_present: bool = hud.objective_progress_view.goal_rows.has(goal_id)
			mapped = mapped and row_present
			if row_present:
				var row: Dictionary = hud.objective_progress_view.goal_rows[goal_id]
				var expected_value := "%d / %d" % [int(goal["current"]), int(goal["target"])]
				if str(goal["type"]) in ["rabbit_population", "fox_population", "prey_per_fox"]:
					expected_value = "%d / min %d" % [int(goal["current"]), int(goal["target"])]
				elif str(goal["type"]) == "health":
					expected_value = {"fed": "Fed", "hungry": "Hungry", "starving": "Starving", "absent": "—"}.get(str(goal["status"]), "—")
				elif str(goal["type"]) == "trend":
					expected_value = "%d%% / max %d%%" % [int(goal["current"]), int(goal["target"])]
				mapped = mapped and row["value"].text == expected_value
				if str(goal["type"]) == "fox_population":
					mapped = mapped and row["glyph"] != null and row["glyph"].kind == "fox"
				observed.append("%s %s" % [goal_id, row["value"].text])
		mapped = mapped and hud.objective_progress_view.goal_rows.has("hold")
		hud.free()
	_expect(mapped, "checkpoint UI maps every structured checkpoint goal into the task/status list", "; ".join(observed))

func _test_checkpoint_ui_distinguishes_live_hunger_states() -> void:
	var systems = Systems.new(_fast_config())
	systems.run_director.milestone_index = 6
	_ensure_rabbits(systems, 7)
	_ensure_foxes(systems, 1)
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	for rabbit in systems.simulation.rabbits.values():
		rabbit["hunger"] = 0.0
	for fox in systems.simulation.foxes.values():
		fox["hunger"] = 0.0
	hud.refresh()
	var rabbit_row: Dictionary = hud.objective_progress_view.goal_rows["rabbit_health"]
	var fox_row: Dictionary = hud.objective_progress_view.goal_rows["fox_health"]
	var distinct_labels: bool = rabbit_row["title"].text == "Rabbit hunger" and fox_row["title"].text == "Fox hunger"
	var fed_states: bool = rabbit_row["value"].text == "Fed" and fox_row["value"].text == "Fed"
	var rabbit_id: int = systems.simulation.rabbits.keys()[0]
	var fox_id: int = systems.simulation.foxes.keys()[0]
	systems.simulation.rabbits[rabbit_id]["hunger"] = float(systems.config["rabbit"]["hunger_warning_at"]) + 1.0
	systems.simulation.rabbits[rabbit_id]["behavior"] = "seek_food"
	systems.simulation.foxes[fox_id]["hunger"] = float(systems.config["fox"]["starvation_threshold"]) + 1.0
	systems.simulation.foxes[fox_id]["behavior"] = "hunt"
	hud.refresh()
	rabbit_row = hud.objective_progress_view.goal_rows["rabbit_health"]
	fox_row = hud.objective_progress_view.goal_rows["fox_health"]
	var live_states: bool = rabbit_row["value"].text == "Hungry" \
		and rabbit_row["value"].theme_type_variation == "LabelWarning" \
		and fox_row["value"].text == "Starving" \
		and fox_row["value"].theme_type_variation == "LabelDanger"
	var species_glyphs: bool = rabbit_row["glyph"].kind == "rabbit" and fox_row["glyph"].kind == "fox"
	_expect(distinct_labels and fed_states and live_states and species_glyphs, "checkpoint UI gives rabbits and foxes distinct Fed, Hungry, and Starving signals")
	hud.free()

func _test_checkpoint_ui_uses_player_facing_guidance() -> void:
	var systems = Systems.new(_fast_config())
	systems.run_director.milestone_index = 4
	_ensure_rabbits(systems, 12)
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud.refresh()
	hud.objective_progress_view.set_details_open(true)
	var explanation: String = str(hud.objective_progress_view.details_detail.text).to_lower()
	var is_player_facing: bool = "food" in explanation and "three" in explanation
	var avoids_evaluator_language: bool = not "reachable" in explanation and not "minimum" in explanation and not "placing rabbits does not count" in explanation
	_expect(is_player_facing and avoids_evaluator_language, "checkpoint guidance uses a short player-facing nudge instead of evaluator terminology", explanation)
	hud.free()

func _test_debug_retains_exact_evaluator_detail() -> void:
	var systems = Systems.new(_fast_config())
	var debug_text := "\n".join(systems.run_director.debug_lines(systems.simulation))
	_expect("stable 0.0s/0.2s" in debug_text and "founders fed 0" in debug_text and "grace 0.0s" in debug_text, "development debug retains exact evidence, stabilization, and Critical timing")

func _test_minor_and_major_feedback_are_distinct() -> void:
	var systems = Systems.new(_fast_config())
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud._on_milestone_completed(0, "colony_gathers", "Minor beat")
	var minor_compact: bool = hud.toast_label.text == "Minor beat" and hud.toast_label.theme_type_variation == "BodyLarge" and not hud.ending_overlay.visible
	hud._on_milestone_completed(4, "nursery_network", "Major beat")
	var major_emphasized: bool = hud.toast_label.text == "MEADOW MILESTONE · Major beat" and hud.toast_label.theme_type_variation == "HeadingThree" and not hud.ending_overlay.visible
	_expect(minor_compact and major_emphasized, "minor checkpoints use compact feedback while major checkpoints receive stronger non-modal emphasis")
	hud.free()

func _test_completion_ui_and_sandbox_epilogue() -> void:
	var systems = Systems.new(_fast_config())
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud.continue_requested.connect(systems.continue_observing)
	_complete_run(systems)
	var completed_ui: bool = hud.ending_overlay.visible and hud.continue_button.visible and hud.new_ecosystem_button.visible and hud.ending_title.text == "Ecosystem Established"
	hud._on_continue_pressed()
	var before: float = systems.simulation.simulation_time
	systems.advance(0.2)
	_expect(completed_ui and not hud.ending_overlay.visible and systems.run_director.run_state == RunDirector.STATE_SANDBOX and systems.simulation.simulation_time > before, "completion is a single final overlay with a live sandbox epilogue")
	hud.free()

func _test_fresh_system_resets_the_run() -> void:
	var completed = Systems.new(_fast_config())
	_complete_run(completed)
	var fresh = Systems.new(_fast_config())
	_expect(fresh.run_director.run_state == RunDirector.STATE_PLAYING and fresh.run_director.current_milestone_id() == "colony_gathers" and fresh.simulation.simulation_time == 0.0 and not fresh.run_director.is_unlocked("fox"), "a new ecosystem starts from clean ten-checkpoint progression and simulation state")
