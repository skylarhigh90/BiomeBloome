extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")
const HUD = preload("res://ui/game_hud.gd")
const Lens = preload("res://rendering/objective_lens.gd")
const AudioDirector = preload("res://game/meadow_audio_director.gd")

const CHECKPOINT_IDS := ["first_meal", "first_family", "two_homes", "nursery_network", "hunt_and_recover", "living_balance"]
const NURSERY_CENTERS := [Vector2(-230.0, -140.0), Vector2(230.0, -140.0), Vector2(240.0, 180.0)]

var failures: Array[String] = []
var passed = 0

func _initialize() -> void:
	_test_checkpoint_contract_is_six_distinct_acts()
	_test_opening_inventory_is_focused()
	_test_first_meal_requires_distinct_living_founders()
	_test_first_family_requires_births_and_one_growing_forager()
	_test_two_homes_combines_geography_and_habitat_quality()
	_test_nursery_network_carries_existing_homes_forward()
	_test_hunt_and_recover_accepts_either_event_order()
	_test_recovery_uses_act_opening_population()
	_test_final_window_is_recent_not_latched_forever()
	_test_final_window_accepts_either_event_order()
	_test_objective_lens_tracks_the_first_young_forager()
	_test_objective_lens_shares_nursery_classification()
	_test_objective_lens_cleans_up_feedback()
	_test_nursery_requires_usable_food_presence()
	_test_nursery_counter_supports_three_zones()
	_test_reward_cadence_unlocks_and_expands_persistently()
	_test_timed_undo_restores_inventory_and_entity_state()
	_test_undo_expires_in_real_time_even_while_paused()
	_test_placement_assessment_exposes_habitat_quality()
	_test_transplant_moves_a_plant_and_spends_one_charge()
	_test_animals_have_public_identity_and_history()
	_test_lineage_links_child_and_both_parents()
	_test_animal_field_note_surfaces_lineage_and_follow_action()
	_test_ecology_feed_records_player_facing_moments()
	_test_procedural_audio_has_distinct_event_cues()
	_test_supply_pool_progression()
	_test_supply_guarantees_required_fox_replacement()
	_test_critical_arms_only_after_the_nursery_network()
	_test_loss_of_breeding_group_enters_critical_at_one_x()
	_test_fox_extinction_is_not_game_over()
	_test_supply_modal_pauses_critical_grace()
	_test_first_critical_supply_keeps_the_rabbit_rescue()
	_test_recovery_requires_a_living_settling_period()
	_test_failed_recovery_causes_game_over()
	_test_checkpoint_ui_is_compact_and_complete()
	_test_every_goal_has_an_on_demand_explainer()
	_test_nursery_is_the_single_player_facing_group_term()
	_test_minor_major_and_final_feedback_are_distinct()
	_test_completion_ui_and_sandbox_epilogue()
	_test_fresh_system_resets_the_run()
	print("\n%d focused progression and interaction tests passed; %d failed." % [passed, failures.size()])
	for failure in failures:
		printerr("FAILED: %s" % failure)
	quit(1 if not failures.is_empty() else 0)

func _fast_config() -> Dictionary:
	var config = Config.make().duplicate(true)
	config["simulation"]["max_steps_per_frame"] = 1000
	config["simulation"]["reproduction_check_interval"] = 9999.0
	config["supply"]["interval"] = 1000.0
	config["progression"]["spatial_sample_interval"] = 0.0
	config["rabbit"]["hunger_rate"] = 0.0
	config["rabbit"]["move_speed"] = 0.0
	config["rabbit"]["lifespan"] = 9999.0
	config["fox"]["hunger_rate"] = 0.0
	config["fox"]["move_speed"] = 0.0
	config["fox"]["lifespan"] = 9999.0
	for milestone in config["progression"]["milestones"]:
		milestone["stabilization"] = 0.2
		for criterion in milestone.get("criteria", []):
			if str(criterion.get("type", "")) == "born_rabbit_fed":
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
		systems.simulation.add_rabbit(Vector2(float(index % 4) * 16.0, float(index / 4) * 16.0), "placement")

func _ensure_foxes(systems, count: int) -> void:
	while systems.simulation.population("fox") < count:
		var index: int = systems.simulation.population("fox")
		systems.simulation.add_fox(Vector2(80.0 + float(index) * 22.0, 0.0), "placement")

func _kill_all_rabbits(systems, cause: String = "test") -> void:
	for rabbit_id in systems.simulation.rabbits.keys():
		systems.simulation.kill_rabbit(rabbit_id, cause)

func _arrange_nurseries(systems, rabbit_count: int, nursery_count: int) -> void:
	_ensure_rabbits(systems, rabbit_count)
	var centers: Array = NURSERY_CENTERS.slice(0, nursery_count)
	var ids: Array = systems.simulation.rabbits.keys()
	for index in range(ids.size()):
		var center: Vector2 = centers[index % centers.size()]
		var rabbit: Dictionary = systems.simulation.rabbits[ids[index]]
		rabbit["position"] = center + Vector2(0.0, float(index / centers.size()) * 13.0)
		rabbit["previous_position"] = rabbit["position"]
		rabbit["velocity"] = Vector2.ZERO
		rabbit["previous_velocity"] = Vector2.ZERO
	for center in centers:
		var plant_id: int = systems.simulation.add_plant("berry_bush", center + Vector2(20.0, 5.0))
		systems.simulation.plants[plant_id]["food"] = 30.0
		systems.simulation.plants[plant_id]["habitat_capacity_factor"] = 1.0
	systems.simulation.rebuild_spatial_index()

func _add_births(systems, count: int, fed_count: int = 0, parents: Array = []) -> Array[int]:
	var ids: Array[int] = []
	for index in range(count):
		var center: Vector2 = NURSERY_CENTERS[index % NURSERY_CENTERS.size()]
		var entity_id: int = systems.simulation.add_rabbit(center + Vector2(float(index) * 5.0, 0.0), "birth", parents)
		systems.simulation.rabbits[entity_id]["age"] = 8.0
		ids.append(entity_id)
	for index in range(mini(fed_count, ids.size())):
		systems.run_director.record_creature_fed("rabbit", ids[index], -1)
	return ids

func _criterion(progress: Dictionary, criterion_id: String) -> Dictionary:
	for criterion in progress.get("criteria", []):
		if str(criterion.get("id", "")) == criterion_id:
			return criterion
	return {}

func _satisfy_current_checkpoint(systems) -> void:
	match systems.run_director.current_milestone_id():
		"first_meal":
			_ensure_rabbits(systems, 4)
			var founders: Array = systems.simulation.rabbits.keys()
			for index in range(3):
				systems.run_director.record_creature_fed("rabbit", founders[index], -1)
		"first_family":
			_ensure_rabbits(systems, 5)
			_add_births(systems, 2, 1)
		"two_homes":
			_arrange_nurseries(systems, 6, 2)
			var carrot_id: int = systems.simulation.add_plant("carrot_patch", Vector2.ZERO)
			systems.simulation.plants[carrot_id]["habitat_capacity_factor"] = 1.0
			systems.simulation.plants[carrot_id]["food"] = 10.0
		"nursery_network":
			_arrange_nurseries(systems, 9, 3)
		"hunt_and_recover":
			_arrange_nurseries(systems, maxi(12, systems.simulation.population("rabbit")), 3)
			_ensure_foxes(systems, 2)
			if systems.run_director.milestone_start_rabbit_population < 0:
				systems.advance(0.1)
			var fox_ids: Array = systems.simulation.foxes.keys()
			_add_births(systems, 2)
			systems.run_director.record_predation(fox_ids[0], -1, Vector2.ZERO)
			systems.run_director.record_predation(fox_ids[1], -1, Vector2.ZERO)
			_ensure_rabbits(systems, maxi(10, systems.run_director.milestone_start_rabbit_population))
		"living_balance":
			_arrange_nurseries(systems, maxi(12, systems.simulation.population("rabbit")), 3)
			_ensure_foxes(systems, 2)
			var fox_ids: Array = systems.simulation.foxes.keys()
			_add_births(systems, 3)
			for index in range(3):
				systems.run_director.record_predation(fox_ids[index % fox_ids.size()], -1, Vector2.ZERO)
	systems.advance(0.3)

func _advance_to(systems, milestone_id: String) -> void:
	var guard = 0
	while systems.run_director.current_milestone_id() != milestone_id and systems.run_director.run_state == RunDirector.STATE_PLAYING and guard < 10:
		_satisfy_current_checkpoint(systems)
		guard += 1

func _complete_run(systems) -> void:
	var guard = 0
	while systems.run_director.run_state == RunDirector.STATE_PLAYING and guard < 10:
		_satisfy_current_checkpoint(systems)
		guard += 1

func _valid_ground(systems) -> Vector2:
	for radius in range(0, 320, 20):
		for spoke in range(16):
			var position = Vector2.from_angle(float(spoke) / 16.0 * TAU) * float(radius)
			if systems.simulation.is_position_valid(position):
				return position
	return Vector2.ZERO

func _extreme_plant_site(systems, plant_type: String, find_highest: bool) -> Vector2:
	var best = Vector2.INF
	var best_score = -INF if find_highest else INF
	for radius in range(20, 340, 20):
		for spoke in range(32):
			var position = Vector2.from_angle(float(spoke) / 32.0 * TAU) * float(radius)
			if not systems.simulation.is_position_valid(position):
				continue
			var score: float = systems.simulation.terrain.food_capacity_factor(plant_type, position)
			if (find_highest and score > best_score) or (not find_highest and score < best_score):
				best = position
				best_score = score
	return best

func _test_checkpoint_contract_is_six_distinct_acts() -> void:
	var config = Config.make()
	var milestones: Array = config["progression"]["milestones"]
	var ids: Array[String] = []
	var rows: Array[int] = []
	var holds: Array[float] = []
	var no_ordered_cycles = true
	var born_feeding_count = 0
	for milestone in milestones:
		ids.append(str(milestone["id"]))
		rows.append(milestone.get("criteria", []).size() + (1 if int(milestone.get("rabbit_min", 0)) > 0 else 0) + (1 if int(milestone.get("fox_min", 0)) > 0 else 0) + 1)
		holds.append(float(milestone["stabilization"]))
		for criterion in milestone.get("criteria", []):
			no_ordered_cycles = no_ordered_cycles and str(criterion.get("type", "")) != "ordered_cycle"
			if str(criterion.get("type", "")) == "born_rabbit_fed":
				born_feeding_count += 1
	var valid = ids == CHECKPOINT_IDS and rows.max() <= 5 and no_ordered_cycles and born_feeding_count == 1 and holds == [8.0, 12.0, 16.0, 8.0, 22.0, 4.0]
	_expect(valid, "the run uses six distinct acts, no forced event order, and at most five visible goals", str({"ids": ids, "rows": rows, "holds": holds}))

func _test_opening_inventory_is_focused() -> void:
	var config = Config.make()
	_expect(config["inventory"] == {"rabbit": 4, "fox": 0, "carrot_patch": 5, "berry_bush": 0} and config["progression"]["initial_unlocked"] == ["rabbit", "carrot_patch"], "the opening teaches one animal and one forage type before adding complexity")

func _test_first_meal_requires_distinct_living_founders() -> void:
	var systems = Systems.new(_fast_config())
	_ensure_rabbits(systems, 4)
	var ids: Array = systems.simulation.rabbits.keys()
	for index in range(2):
		systems.run_director.record_creature_fed("rabbit", ids[index], -1)
	systems.advance(0.3)
	var blocked_at_two = systems.run_director.current_milestone_id() == "first_meal"
	systems.run_director.record_creature_fed("rabbit", ids[2], -1)
	systems.advance(0.3)
	_expect(blocked_at_two and systems.run_director.has_completed("first_meal"), "The First Meal requires three distinct living founders to eat")

func _test_first_family_requires_births_and_one_growing_forager() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "first_family")
	_ensure_rabbits(systems, 9)
	systems.advance(0.3)
	var placements_do_not_count = systems.run_director.current_milestone_id() == "first_family"
	_add_births(systems, 2)
	systems.advance(0.3)
	var unfed_young_blocks = systems.run_director.current_milestone_id() == "first_family"
	var born_ids: Array = systems.run_director.milestone_born_rabbit_ids.keys()
	systems.run_director.record_creature_fed("rabbit", born_ids[0], -1)
	systems.advance(0.3)
	_expect(placements_do_not_count and unfed_young_blocks and systems.run_director.has_completed("first_family"), "The First Family teaches births and one young forager without geography repetition")

func _test_two_homes_combines_geography_and_habitat_quality() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "two_homes")
	_arrange_nurseries(systems, 6, 2)
	for plant in systems.simulation.plants.values():
		plant["habitat_capacity_factor"] = 0.5
	systems.advance(0.3)
	var poor_food_blocks = systems.run_director.current_milestone_id() == "two_homes"
	var carrot_id = systems.simulation.add_plant("carrot_patch", Vector2.ZERO)
	systems.simulation.plants[carrot_id]["habitat_capacity_factor"] = 1.0
	for plant in systems.simulation.plants.values():
		if plant["type"] == "berry_bush":
			plant["habitat_capacity_factor"] = 1.0
	systems.advance(0.3)
	_expect(poor_food_blocks and systems.run_director.has_completed("two_homes"), "Two Lasting Homes requires both separated groups and productive Carrot/Berry habitat")

func _test_nursery_network_carries_existing_homes_forward() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "nursery_network")
	_arrange_nurseries(systems, 9, 2)
	systems.advance(0.3)
	var two_blocked = systems.run_director.current_milestone_id() == "nursery_network"
	_arrange_nurseries(systems, 9, 3)
	systems.advance(0.3)
	var milestone = systems.run_director.milestone_by_id("nursery_network")
	var only_live_goal = milestone["criteria"].size() == 1 and milestone["criteria"][0]["type"] == "safe_havens"
	_expect(two_blocked and only_live_goal and systems.run_director.has_completed("nursery_network"), "A Nursery Network adds one new home and carries prior living work forward")

func _test_hunt_and_recover_accepts_either_event_order() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "hunt_and_recover")
	_arrange_nurseries(systems, 12, 3)
	_ensure_foxes(systems, 2)
	systems.run_director.milestone_start_rabbit_population = -1
	systems.advance(0.1)
	_add_births(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	systems.run_director.record_predation(fox_ids[0], -1, Vector2.ZERO)
	systems.run_director.record_predation(fox_ids[1], -1, Vector2.ZERO)
	var progress = systems.current_objective_progress()
	var valid = bool(_criterion(progress, "hunts").get("met", false)) and bool(_criterion(progress, "recovery_births").get("met", false)) and bool(_criterion(progress, "foxes_fed").get("met", false)) and systems.run_director.sequence_progress == 0
	_expect(valid, "Hunt and Recover accepts births before hunts and credits two individual foxes")

func _test_recovery_uses_act_opening_population() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "hunt_and_recover")
	_arrange_nurseries(systems, 12, 3)
	_ensure_foxes(systems, 2)
	systems.run_director.milestone_start_rabbit_population = -1
	systems.advance(0.1)
	var baseline = systems.run_director.milestone_start_rabbit_population
	var rabbit_ids: Array = systems.simulation.rabbits.keys()
	for index in range(3):
		systems.simulation.kill_rabbit(rabbit_ids[index], "predation")
	_add_births(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	systems.run_director.record_predation(fox_ids[0], -1, Vector2.ZERO)
	systems.run_director.record_predation(fox_ids[1], -1, Vector2.ZERO)
	systems.advance(0.3)
	var blocked_below_baseline = systems.run_director.current_milestone_id() == "hunt_and_recover"
	_add_births(systems, 1)
	systems.advance(0.3)
	_expect(baseline == 12 and blocked_below_baseline and systems.run_director.has_completed("hunt_and_recover"), "recovery restores the population present when the predator act opened")

func _test_final_window_is_recent_not_latched_forever() -> void:
	var config = _fast_config()
	config["progression"]["milestones"][5]["criteria"][1]["window"] = 0.35
	config["progression"]["milestones"][5]["stabilization"] = 2.0
	var systems = Systems.new(config)
	_advance_to(systems, "living_balance")
	_arrange_nurseries(systems, 12, 3)
	_ensure_foxes(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	_add_births(systems, 3)
	for index in range(3):
		systems.run_director.record_predation(fox_ids[index % 2], -1, Vector2.ZERO)
	var met_now = bool(_criterion(systems.current_objective_progress(), "living_window").get("met", false))
	systems.advance(0.5)
	var expired = not bool(_criterion(systems.current_objective_progress(), "living_window").get("met", true)) and is_zero_approx(systems.run_director.milestone_stability)
	_expect(met_now and expired, "the final ecology proof is a genuinely recent window rather than permanent event credit")

func _test_final_window_accepts_either_event_order() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "living_balance")
	_arrange_nurseries(systems, 12, 3)
	_ensure_foxes(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	for index in range(3):
		systems.run_director.record_predation(fox_ids[index % 2], -1, Vector2.ZERO)
	_add_births(systems, 3)
	var progress = _criterion(systems.current_objective_progress(), "living_window")
	_expect(bool(progress.get("met", false)) and int(progress.get("births", 0)) == 3 and int(progress.get("hunts", 0)) == 3, "Living Balance accepts hunts before births and measures the combined outcome")

func _test_objective_lens_tracks_the_first_young_forager() -> void:
	var config = _fast_config()
	config["progression"]["milestones"][1]["criteria"][1]["minimum_age"] = 8.0
	var systems = Systems.new(config)
	systems.run_director.milestone_index = 1
	systems.run_director._reset_milestone_evidence()
	var child_id = systems.simulation.add_rabbit(Vector2.ZERO, "birth")
	var before_state = _lens_state_for(systems.current_objective_lens(), child_id)
	systems.run_director.record_creature_fed("rabbit", child_id, -1)
	var growing_state = _lens_state_for(systems.current_objective_lens(), child_id)
	systems.simulation.rabbits[child_id]["age"] = 9.0
	var mature_state = _lens_state_for(systems.current_objective_lens(), child_id)
	_expect(before_state == "needs_food" and growing_state == "growing" and mature_state == "satisfied", "Objective Lens follows the one taught young-forager journey", str([before_state, growing_state, mature_state]))

func _lens_state_for(snapshot: Dictionary, entity_id: int) -> String:
	for marker in snapshot["attention"]:
		if int(marker.get("entity_id", -1)) == entity_id:
			return str(marker["state"])
	return ""

func _test_objective_lens_shares_nursery_classification() -> void:
	var systems = Systems.new(_fast_config())
	systems.run_director.milestone_index = 2
	systems.run_director._reset_milestone_evidence()
	_arrange_nurseries(systems, 6, 2)
	var lens = systems.current_objective_lens()
	var progress = systems.current_objective_progress()
	var ordinals: Array[int] = []
	for marker in lens["evidence"]:
		if str(marker.get("role", "")) == "nursery":
			ordinals.append(int(marker["ordinal"]))
	_expect(ordinals == [1, 2] and ordinals.size() == int(_criterion(progress, "nurseries")["current"]), "Objective Lens displays exactly the nursery groups counted by progression", str(lens))

func _test_objective_lens_cleans_up_feedback() -> void:
	var lens = Lens.new()
	var active = {"objective_id": "first_family", "active": true, "attention": [{"id": "young:1", "role": "offspring", "entity_kind": "rabbit", "entity_id": 1, "position": Vector2.ZERO, "state": "needs_food"}], "evidence": [], "events": [{"id": "birth:0", "role": "birthplace", "position": Vector2.ZERO, "ordinal": 1, "state": "established"}]}
	lens.update(active, 0.1)
	lens.update(active, 0.1)
	var deduplicated = lens.feedback.size() == 1
	lens.update({"objective_id": "two_homes", "active": false}, 1.5)
	_expect(deduplicated and lens.attention_markers.is_empty() and lens.feedback.is_empty(), "Objective Lens deduplicates moments and cleans up when an act changes")

func _test_nursery_requires_usable_food_presence() -> void:
	var systems = Systems.new(_fast_config())
	for position in [Vector2(-8.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 8.0)]:
		systems.simulation.add_rabbit(position)
	var plant_id = systems.simulation.add_plant("carrot_patch", Vector2(0.0, 14.0))
	systems.simulation.plants[plant_id]["food"] = 0.45
	var evidence = systems.run_director.spatial_evidence(systems.simulation, {"target": 1, "rabbits_per_group": 3, "minimum_separation": 280.0, "minimum_local_food": 0.0})
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 1, "a nursery needs usable nearby food without a hidden biomass quota", str(evidence))

func _test_nursery_counter_supports_three_zones() -> void:
	var systems = Systems.new(_fast_config())
	_arrange_nurseries(systems, 9, 3)
	var evidence = systems.run_director.spatial_evidence(systems.simulation, {"target": 3, "rabbits_per_group": 3, "minimum_separation": 280.0, "minimum_local_food": 8.0})
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 3, "nursery evidence supports three mutually separated local groups", str(evidence))

func _test_reward_cadence_unlocks_and_expands_persistently() -> void:
	var systems = Systems.new(_fast_config())
	var step = float(systems.config["world"]["expansion_amount"])
	var initial_radius = systems.simulation.world_radius
	var preserved_plant = systems.simulation.add_plant("carrot_patch", Vector2(120.0, 0.0))
	_advance_to(systems, "first_family")
	var first_reward = is_equal_approx(systems.simulation.world_radius, initial_radius + step * 1.5) and systems.run_director.is_unlocked("berry_bush") and int(systems.inventory["berry_bush"]) == 2
	_advance_to(systems, "two_homes")
	var tool_reward = systems.run_director.is_unlocked("transplant") and systems.transplant_charges == 1
	_advance_to(systems, "hunt_and_recover")
	var predator_reward = is_equal_approx(systems.simulation.world_radius, initial_radius + step * 6.0) and systems.run_director.is_unlocked("fox") and int(systems.inventory["fox"]) == 2
	_satisfy_current_checkpoint(systems)
	var late_reward = is_equal_approx(systems.simulation.world_radius, initial_radius + step * 8.0) and systems.transplant_charges == 3 and systems.run_director.supply_pool == "living"
	_expect(first_reward and tool_reward and predator_reward and late_reward and systems.simulation.plants.has(preserved_plant), "every act pays out an unlock, tool charge, predator arrival, or persistent terrain reveal")

func _test_timed_undo_restores_inventory_and_entity_state() -> void:
	var systems = Systems.new(_fast_config())
	var before = int(systems.inventory["rabbit"])
	var rabbit_id = systems.place_item("rabbit", _valid_ground(systems))
	var available = rabbit_id != -1 and systems.can_undo_last_placement()
	var undone = systems.undo_last_placement()
	_expect(available and undone and not systems.simulation.rabbits.has(rabbit_id) and int(systems.inventory["rabbit"]) == before, "timed undo cleanly restores the last placement to the satchel")

func _test_undo_expires_in_real_time_even_while_paused() -> void:
	var systems = Systems.new(_fast_config())
	var rabbit_id = systems.place_item("rabbit", _valid_ground(systems))
	systems.set_speed(0.0)
	systems.advance(5.1)
	_expect(rabbit_id != -1 and not systems.can_undo_last_placement() and systems.simulation.rabbits.has(rabbit_id), "undo expires after five real seconds even while simulation time is paused")

func _test_placement_assessment_exposes_habitat_quality() -> void:
	var systems = Systems.new(_fast_config())
	var rich = systems.placement_assessment("berry_bush", _extreme_plant_site(systems, "berry_bush", true))
	var poor = systems.placement_assessment("berry_bush", _extreme_plant_site(systems, "berry_bush", false))
	_expect(bool(rich.get("valid", false)) and bool(poor.get("valid", false)) and float(rich.get("score", 0.0)) > float(poor.get("score", 0.0)) + 0.15 and rich["quality"] != poor["quality"], "placement preview turns terrain suitability into a readable quality decision", str({"rich": rich, "poor": poor}))

func _test_transplant_moves_a_plant_and_spends_one_charge() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "two_homes")
	var poor_site = _extreme_plant_site(systems, "berry_bush", false)
	var rich_site = _extreme_plant_site(systems, "berry_bush", true)
	var plant_id = systems.simulation.add_plant("berry_bush", poor_site)
	var old_capacity = float(systems.simulation.plants[plant_id]["habitat_capacity_factor"])
	var old_food = float(systems.simulation.plants[plant_id]["food"])
	var charges_before = systems.transplant_charges
	var moved = systems.begin_transplant() and systems.choose_transplant_source(plant_id) and systems.complete_transplant(rich_site)
	var plant: Dictionary = systems.simulation.plants[plant_id]
	_expect(moved and plant["position"] == rich_site and float(plant["habitat_capacity_factor"]) > old_capacity and float(plant["food"]) <= old_food * 0.65 + 0.001 and systems.transplant_charges == charges_before - 1, "transplant corrects a poor site with a biomass cost and limited charge")

func _test_animals_have_public_identity_and_history() -> void:
	var systems = Systems.new(_fast_config())
	var rabbit_id = systems.simulation.add_rabbit(Vector2.ZERO)
	var before = systems.simulation.animal_snapshot("rabbit", rabbit_id)
	systems.simulation.rabbits[rabbit_id]["meals"] = 2
	systems.simulation.rabbits[rabbit_id]["recent_event"] = "Ate nearby forage"
	var after = systems.simulation.animal_snapshot("rabbit", rabbit_id)
	_expect(not str(before.get("name", "")).is_empty() and before["stage"] == "Adult" and int(after["meals"]) == 2 and after["recent_event"] == "Ate nearby forage" and not str(after["activity"]).is_empty(), "every animal exposes a stable name, life stage, needs, activity, and personal history")

func _test_lineage_links_child_and_both_parents() -> void:
	var systems = Systems.new(_fast_config())
	var first = systems.simulation.add_rabbit(Vector2(-8.0, 0.0))
	var second = systems.simulation.add_rabbit(Vector2(8.0, 0.0))
	var child = systems.simulation.add_rabbit(Vector2.ZERO, "birth", [first, second])
	var snapshot = systems.simulation.animal_snapshot("rabbit", child)
	var linked_back = systems.simulation.rabbits[first]["offspring_ids"].has(child) and systems.simulation.rabbits[second]["offspring_ids"].has(child)
	_expect(snapshot["parent_names"].size() == 2 and linked_back, "a newborn links to both named parents and both parents retain the child in their lineage")

func _test_animal_field_note_surfaces_lineage_and_follow_action() -> void:
	var systems = Systems.new(_fast_config())
	var first = systems.simulation.add_rabbit(Vector2(-8.0, 0.0))
	var second = systems.simulation.add_rabbit(Vector2(8.0, 0.0))
	var child = systems.simulation.add_rabbit(Vector2.ZERO, "birth", [first, second])
	var snapshot: Dictionary = systems.simulation.animal_snapshot("rabbit", child)
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	var followed := {"kind": "", "id": -1}
	hud.animal_follow_requested.connect(func(kind: String, entity_id: int) -> void:
		followed["kind"] = kind
		followed["id"] = entity_id
	)
	hud.show_animal("rabbit", child)
	hud.animal_follow_button.pressed.emit()
	var parent_names: Array = snapshot["parent_names"]
	var visible_copy = hud.animal_panel.visible and hud.animal_name_label.text == snapshot["name"] and " & ".join(parent_names) in hud.animal_family_label.text and "Follow " in hud.animal_follow_button.text
	var follow_works = followed == {"kind": "rabbit", "id": child}
	_expect(visible_copy and follow_works, "clicking an animal exposes its named family note and a working follow action", str({"family": hud.animal_family_label.text, "followed": followed}))
	hud.free()

func _test_ecology_feed_records_player_facing_moments() -> void:
	var systems = Systems.new(_fast_config())
	var rabbit_id = systems.simulation.add_rabbit(Vector2.ZERO)
	systems.simulation.animal_story.emit("rabbit", rabbit_id, "first_meal", -1, Vector2.ZERO)
	var descriptions: Array[String] = []
	for story in systems.ecology_stories:
		descriptions.append(str(story["description"]))
	_expect(descriptions.size() == 2 and "found a first meal" in descriptions[0] and "joined the meadow" in descriptions[1], "the ecology feed records named arrivals and meaningful life moments", str(descriptions))

func _test_procedural_audio_has_distinct_event_cues() -> void:
	var systems = Systems.new(_fast_config())
	var audio = AudioDirector.new()
	root.add_child(audio)
	audio.setup(systems)
	var required = ["place_animal", "place_plant", "birth", "first_meal", "hunt", "transplant", "supply", "milestone", "warning", "complete"]
	var complete = true
	for key in required:
		complete = complete and audio.streams.has(key) and audio.streams[key] is AudioStreamWAV
	var ambience_loops = audio.ambience_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
	audio.set_enabled(false)
	_expect(complete and ambience_loops and not audio.enabled and not audio.ambience_player.playing, "original procedural ambience and distinct action, ecology, reward, and danger cues are available and mutable")
	audio.free()

func _test_supply_pool_progression() -> void:
	var config = Config.make()
	var pools: Dictionary = config["supply"]["pools"]
	var living_plant_units = 0
	for bundle in pools["living"]:
		living_plant_units += int(bundle["items"].get("carrot_patch", 0)) + int(bundle["items"].get("berry_bush", 0))
	_expect(pools.size() == 3 and float(config["supply"]["interval"]) == 90.0 and living_plant_units >= 8, "supplies retain three stage-sensitive pools and plant-heavy late support")

func _test_supply_guarantees_required_fox_replacement() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "hunt_and_recover")
	systems.inventory["fox"] = 0
	_ensure_foxes(systems, 1)
	systems._make_supply_choices()
	var has_fox = false
	for choice in systems.supply_choices:
		has_fox = has_fox or int(choice.get("items", {}).get("fox", 0)) > 0
	_expect(has_fox, "when a two-fox objective is active, Meadow Mail always offers a fox replacement")

func _test_critical_arms_only_after_the_nursery_network() -> void:
	var before = Systems.new(_fast_config())
	_advance_to(before, "nursery_network")
	_kill_all_rabbits(before)
	before.advance(1.0)
	var safe_before = before.run_director.run_state == RunDirector.STATE_PLAYING and not before.run_director.rabbit_failure_armed
	var after = Systems.new(_fast_config())
	_advance_to(after, "hunt_and_recover")
	_expect(safe_before and after.run_director.rabbit_failure_armed, "Critical remains dormant until the Nursery Network is established")

func _enter_critical(systems) -> void:
	_advance_to(systems, "hunt_and_recover")
	_kill_all_rabbits(systems, "starvation")
	systems.inventory["rabbit"] = 0
	systems.supply_pending = false
	systems.supply_choices = []
	systems.supply_time_remaining = 100.0
	systems.advance(0.3)

func _test_loss_of_breeding_group_enters_critical_at_one_x() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "hunt_and_recover")
	systems.set_speed(3.0)
	_kill_all_rabbits(systems)
	systems.inventory["rabbit"] = 0
	systems.advance(0.1)
	_expect(systems.run_director.run_state == RunDirector.STATE_CRITICAL and is_equal_approx(systems.simulation_speed, 1.0), "loss of breeding recovery capacity enters Critical and returns speed to 1×")

func _test_fox_extinction_is_not_game_over() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "hunt_and_recover")
	for fox_id in systems.simulation.foxes.keys():
		systems.simulation.kill_fox(fox_id, "test")
	systems.advance(1.0)
	_expect(systems.run_director.run_state == RunDirector.STATE_PLAYING, "fox extinction alone does not trigger Critical or Game Over")

func _test_supply_modal_pauses_critical_grace() -> void:
	var systems = Systems.new(_fast_config())
	_enter_critical(systems)
	systems.supply_pending = true
	systems.supply_choices = [{"name": "Fresh harvest", "items": {"carrot_patch": 1}}]
	var before = systems.run_director.critical_elapsed
	systems.advance(2.0)
	_expect(systems.run_director.run_state == RunDirector.STATE_CRITICAL and is_equal_approx(systems.run_director.critical_elapsed, before), "the blocking supply chooser pauses the Critical grace timer")

func _test_first_critical_supply_keeps_the_rabbit_rescue() -> void:
	var systems = Systems.new(_fast_config())
	_enter_critical(systems)
	systems.advance(0.3)
	var has_rescue = false
	for choice in systems.supply_choices:
		has_rescue = has_rescue or int(choice.get("items", {}).get("rabbit", 0)) >= 2
	_expect(systems.supply_pending and has_rescue, "the guaranteed late Fox replacement never displaces the first Critical rabbit rescue")

func _test_recovery_requires_a_living_settling_period() -> void:
	var systems = Systems.new(_fast_config())
	_enter_critical(systems)
	systems.supply_pending = false
	systems.supply_choices = []
	systems.forced_recovery_supply = false
	systems.supply_time_remaining = 100.0
	systems.simulation.add_rabbit(Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(18.0, 0.0))
	systems.advance(0.1)
	var still_critical = systems.run_director.run_state == RunDirector.STATE_CRITICAL
	systems.advance(0.3)
	_expect(still_critical and systems.run_director.run_state == RunDirector.STATE_PLAYING, "a restored breeding group must remain alive through a settling period")

func _test_failed_recovery_causes_game_over() -> void:
	var config = _fast_config()
	config["progression"]["critical"]["first_rescue_delay"] = 5.0
	config["progression"]["critical"]["grace_duration"] = 0.6
	var systems = Systems.new(config)
	_enter_critical(systems)
	systems.advance(0.7)
	_expect(systems.run_director.run_state == RunDirector.STATE_GAME_OVER and is_zero_approx(systems.simulation_speed), "an unrecovered Critical state still ends the run")

func _test_checkpoint_ui_is_compact_and_complete() -> void:
	var maximum_rows = 0
	var every_goal_mapped = true
	var final_value = ""
	for index in range(CHECKPOINT_IDS.size()):
		var systems = Systems.new(_fast_config())
		systems.run_director.milestone_index = index
		systems.run_director._reset_milestone_evidence()
		var hud = HUD.new()
		root.add_child(hud)
		hud.setup(systems)
		hud.refresh()
		maximum_rows = maxi(maximum_rows, hud.objective_progress_view.goal_rows.size())
		for goal in systems.current_objective_progress()["goals"]:
			every_goal_mapped = every_goal_mapped and hud.objective_progress_view.goal_rows.has(str(goal["id"]))
		if index == 5:
			final_value = hud.objective_progress_view.goal_rows["living_window"]["value"].text
		hud.free()
	_expect(maximum_rows <= 5 and every_goal_mapped and final_value == "B 0/3 · H 0/3", "checkpoint HUD exposes every blocker in five rows or fewer and summarizes the outcome window", final_value)

func _test_every_goal_has_an_on_demand_explainer() -> void:
	var every_goal_explained = true
	var missing: Array[String] = []
	for index in range(CHECKPOINT_IDS.size()):
		var systems = Systems.new(_fast_config())
		systems.run_director.milestone_index = index
		systems.run_director._reset_milestone_evidence()
		var hud = HUD.new()
		root.add_child(hud)
		hud.setup(systems)
		hud.refresh()
		for row_id in hud.objective_progress_view.goal_rows:
			var row: Dictionary = hud.objective_progress_view.goal_rows[row_id]
			var explained: bool = row["help_button"].visible and hud.objective_progress_view.goal_help.has(str(row_id))
			every_goal_explained = every_goal_explained and explained
			if not explained:
				missing.append("%s:%s" % [CHECKPOINT_IDS[index], row_id])
		hud.free()
	_expect(every_goal_explained, "every checkpoint goal retains a stable on-demand explainer", str(missing))

func _test_nursery_is_the_single_player_facing_group_term() -> void:
	var player_copy: Array[String] = []
	for milestone in Config.make()["progression"]["milestones"]:
		for field in ["title", "summary", "guidance", "guide_intro", "teaser", "completion_message"]:
			player_copy.append(str(milestone.get(field, "")))
		for help in milestone.get("goal_help", {}).values():
			player_copy.append(str(help.get("detail", "")))
		for criterion in milestone.get("criteria", []):
			for field in ["label", "metric_label", "lens_label"]:
				player_copy.append(str(criterion.get(field, "")))
	var joined = " ".join(player_copy).to_lower()
	_expect("nurser" in joined and not "haven" in joined, "player-facing progression consistently calls viable rabbit groups nurseries", joined)

func _test_minor_major_and_final_feedback_are_distinct() -> void:
	var systems = Systems.new(_fast_config())
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud._on_milestone_completed(0, "first_meal", "Minor beat")
	var minor = hud.toast_label.text == "Minor beat" and hud.toast_label.theme_type_variation == "BodyLarge"
	hud._on_milestone_completed(3, "nursery_network", "Major beat")
	var major = hud.toast_label.text == "MEADOW MILESTONE · Major beat" and hud.toast_label.theme_type_variation == "HeadingThree"
	hud._on_milestone_completed(5, "living_balance", "Final beat")
	var final = hud.toast_label.text == "Final beat" and hud.toast_label.theme_type_variation == "HeadingThree"
	_expect(minor and major and final, "minor, major, and final rewards use distinct celebration emphasis")
	hud.free()

func _test_completion_ui_and_sandbox_epilogue() -> void:
	var systems = Systems.new(_fast_config())
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud.continue_requested.connect(systems.continue_observing)
	_complete_run(systems)
	var completed_ui = hud.ending_overlay.visible and hud.continue_button.visible and hud.ending_title.text == "Ecosystem Established"
	hud._on_continue_pressed()
	var before = systems.simulation.simulation_time
	systems.advance(0.2)
	hud.refresh()
	var sandbox_rows: Array = hud.objective_progress_view._current_row_ids()
	_expect(completed_ui and not hud.ending_overlay.visible and systems.run_director.run_state == RunDirector.STATE_SANDBOX and systems.simulation.simulation_time > before and sandbox_rows == ["observation"], "completion replaces checkpoint rows with a live sandbox observation goal")
	hud.free()

func _test_fresh_system_resets_the_run() -> void:
	var completed = Systems.new(_fast_config())
	_complete_run(completed)
	var fresh = Systems.new(_fast_config())
	_expect(fresh.run_director.run_state == RunDirector.STATE_PLAYING and fresh.run_director.current_milestone_id() == "first_meal" and fresh.simulation.simulation_time == 0.0 and not fresh.run_director.is_unlocked("fox") and fresh.transplant_charges == 0, "a new ecosystem resets all six acts, unlocks, tools, and simulation state")
