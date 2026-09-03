extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")
const HUD = preload("res://ui/game_hud.gd")
const Lens = preload("res://rendering/objective_lens.gd")

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_test_checkpoint_contract_and_reward_tiers()
	_test_colony_gathers_requires_population()
	_test_new_arrivals_requires_two_births()
	_test_young_foragers_require_born_rabbits_to_feed()
	_test_birthplaces_require_three_separated_births()
	_test_objective_lens_tracks_newborn_identity_and_progress()
	_test_objective_lens_shares_birthplace_classification()
	_test_objective_lens_shares_nursery_classification()
	_test_objective_lens_cleans_up_markers_and_feedback()
	_test_nursery_network_requires_three_live_groups()
	_test_nursery_network_requires_food_presence_not_volume()
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
	_test_nursery_is_the_single_player_facing_term()
	_test_checkpoint_ui_distinguishes_live_hunger_states()
	_test_checkpoint_ui_explains_colony_stability_without_threshold_math()
	_test_checkpoint_ui_stays_scan_first()
	_test_checkpoint_hint_stays_stable_across_live_phases()
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
	var centers := [Vector2(-230.0, -140.0)]
	if haven_count >= 2:
		centers.append(Vector2(230.0, -140.0))
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
	# 130 units is still one local breeding area; 150 units is enough to begin
	# another one under the gameplay-scale birthplace threshold.
	systems.simulation.add_rabbit(Vector2(0.0, 0.0), "birth")
	systems.simulation.add_rabbit(Vector2(130.0, 0.0), "birth")
	systems.simulation.add_rabbit(Vector2(270.0, 0.0), "birth")
	systems.advance(0.3)
	var two_areas_blocked: bool = systems.run_director.current_milestone_id() == "birthplaces"
	systems.simulation.add_rabbit(Vector2(420.0, 0.0), "birth")
	systems.advance(0.3)
	_expect(two_areas_blocked and systems.run_director.has_completed("birthplaces"), "Life Across the Meadow requires fresh births in three genuinely separated areas")

func _test_objective_lens_tracks_newborn_identity_and_progress() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][2]["criteria"][0]["minimum_age"] = 8.0
	var systems = Systems.new(config)
	systems.run_director.milestone_index = 1
	systems.run_director._reset_milestone_evidence()
	var first_id: int = systems.simulation.add_rabbit(Vector2(-20.0, 0.0), "birth")
	var second_id: int = systems.simulation.add_rabbit(Vector2(20.0, 0.0), "birth")
	var arrivals: Dictionary = systems.current_objective_lens()
	var arrival_ids: Array[int] = []
	for marker in arrivals["attention"]:
		arrival_ids.append(int(marker["entity_id"]))

	systems.run_director.milestone_index = 2
	systems.run_director._reset_milestone_evidence()
	var before_feed: Dictionary = systems.current_objective_lens()
	var before_states := {}
	for marker in before_feed["attention"]:
		before_states[int(marker["entity_id"])] = str(marker["state"])
	systems.run_director.record_creature_fed("rabbit", first_id, -1)
	var after_feed: Dictionary = systems.current_objective_lens()
	var after_feed_states := {}
	for marker in after_feed["attention"]:
		after_feed_states[int(marker["entity_id"])] = str(marker["state"])
	systems.simulation.rabbits[first_id]["age"] = 9.0
	var after_growth: Dictionary = systems.current_objective_lens()
	var after_growth_states := {}
	for marker in after_growth["attention"]:
		after_growth_states[int(marker["entity_id"])] = str(marker["state"])
	systems.simulation.kill_rabbit(second_id, "test")
	var after_death: Dictionary = systems.current_objective_lens()
	var death_ids: Array[int] = []
	for marker in after_death["attention"]:
		death_ids.append(int(marker["entity_id"]))
	systems.run_director.milestone_index = 3
	systems.run_director._reset_milestone_evidence()
	var next_checkpoint: Dictionary = systems.current_objective_lens()

	var valid: bool = bool(arrivals["active"]) \
		and arrival_ids.has(first_id) and arrival_ids.has(second_id) \
		and before_states.get(first_id) == "needs_food" and before_states.get(second_id) == "needs_food" \
		and after_feed_states.get(first_id) == "growing" and after_feed_states.get(second_id) == "needs_food" \
		and after_growth_states.get(first_id) == "satisfied" \
		and death_ids == [first_id] and next_checkpoint["attention"].is_empty()
	_expect(valid, "Objective Lens follows evaluator-owned newborn identity through needs-food, growing, satisfied, death, and checkpoint cleanup", str(after_growth_states))

func _test_objective_lens_shares_birthplace_classification() -> void:
	var systems = Systems.new(_fast_config())
	systems.run_director.milestone_index = 3
	systems.run_director._reset_milestone_evidence()
	systems.simulation.add_rabbit(Vector2(0.0, 0.0), "birth")
	var first: Dictionary = systems.current_objective_lens()
	systems.simulation.add_rabbit(Vector2(130.0, 0.0), "birth")
	var nearby: Dictionary = systems.current_objective_lens()
	systems.simulation.add_rabbit(Vector2(270.0, 0.0), "birth")
	systems.simulation.add_rabbit(Vector2(420.0, 0.0), "birth")
	var separated: Dictionary = systems.current_objective_lens()
	var progress: Dictionary = systems.current_objective_progress()
	var birthplace_goal: Dictionary = progress["criteria"][0]
	var nearby_event: Dictionary = nearby["events"][1]
	var no_evaluator_constants := true
	for marker in separated["evidence"]:
		no_evaluator_constants = no_evaluator_constants and not marker.has("minimum_separation") and not marker.has("radius")
	var ordinals: Array[int] = []
	for marker in separated["evidence"]:
		ordinals.append(int(marker["ordinal"]))
	var valid: bool = first["evidence"].size() == 1 \
		and str(first["events"][0]["state"]) == "established" \
		and nearby["evidence"].size() == 1 \
		and str(nearby_event["state"]) == "reinforced" and int(nearby_event["ordinal"]) == 1 \
		and separated["evidence"].size() == int(birthplace_goal["current"]) \
		and ordinals == [1, 2, 3] and no_evaluator_constants
	_expect(valid, "Objective Lens uses the evaluator's exact established/reinforced birthplace classification without exposing its radius", str(separated))

func _test_objective_lens_shares_nursery_classification() -> void:
	var systems = Systems.new(_fast_config())
	systems.run_director.milestone_index = 4
	systems.run_director._reset_milestone_evidence()
	_arrange_havens(systems, 12, 2)
	var lens: Dictionary = systems.current_objective_lens()
	var progress: Dictionary = systems.current_objective_progress()
	var nursery_goal: Dictionary = progress["criteria"][0]
	var ordinals: Array[int] = []
	var semantic_markers := true
	var no_evaluator_constants := true
	for marker in lens["evidence"]:
		ordinals.append(int(marker["ordinal"]))
		semantic_markers = semantic_markers \
			and str(marker.get("role", "")) == "nursery" \
			and str(marker.get("label", "")) == "Nursery" \
			and marker.get("position", Vector2.INF) != Vector2.INF
		no_evaluator_constants = no_evaluator_constants \
			and not marker.has("radius") \
			and not marker.has("minimum_separation") \
			and not marker.has("minimum_local_food") \
			and not marker.has("food") \
			and not marker.has("member_ids") \
			and not marker.has("food_ids")
	var valid: bool = lens["evidence"].size() == int(nursery_goal["current"]) \
		and lens["events"].size() == lens["evidence"].size() \
		and ordinals == [1, 2] and semantic_markers and no_evaluator_constants
	_expect(valid, "Objective Lens marks exactly the live nurseries counted by progression without exposing evaluator thresholds", str(lens))

func _test_objective_lens_cleans_up_markers_and_feedback() -> void:
	var lens = Lens.new()
	var active := {
		"objective_id": "birthplaces",
		"active": true,
		"attention": [{"id": "young:1", "role": "offspring", "entity_kind": "rabbit", "entity_id": 1, "position": Vector2.ZERO, "state": "needs_food"}],
		"evidence": [{"id": "area:0", "role": "birthplace", "position": Vector2.ZERO, "ordinal": 1, "state": "recorded"}],
		"events": [{"id": "birth:0", "role": "birthplace", "position": Vector2.ZERO, "ordinal": 1, "state": "established"}],
	}
	lens.update(active, 0.1)
	lens.update(active, 0.1)
	var no_duplicate_feedback: bool = lens.feedback.size() == 1
	var reset_evidence: Dictionary = active.duplicate(true)
	reset_evidence["evidence_revision"] = 1
	lens.update(reset_evidence, 0.01)
	var reset_rearms_feedback: bool = lens.feedback.size() == 2
	lens.update({"objective_id": "nursery_network", "active": true, "attention": [], "evidence": [], "events": []}, 0.05)
	var old_marker_fading: bool = not lens.attention_markers.is_empty() and not lens.evidence_markers.is_empty()
	lens.update({"objective_id": "nursery_network", "active": false}, 1.5)
	var faded_cleanly: bool = lens.attention_markers.is_empty() and lens.evidence_markers.is_empty() and lens.feedback.is_empty()
	lens.clear_immediately()
	var reset_cleanly: bool = lens.objective_id.is_empty() and lens.seen_event_ids.is_empty()
	_expect(no_duplicate_feedback and reset_rearms_feedback and old_marker_fading and faded_cleanly and reset_cleanly, "Objective Lens deduplicates evidence feedback and cleans up across evidence resets, checkpoint changes, inactive states, and restart", str({
		"deduplicated": no_duplicate_feedback,
		"reset_rearmed": reset_rearms_feedback,
		"fading": old_marker_fading,
		"faded": faded_cleanly,
		"reset": reset_cleanly,
	}))

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
	_expect(two_groups_blocked and systems.run_director.has_completed("nursery_network"), "A Nursery Network requires three simultaneous nurseries with at least three rabbits each")

func _test_nursery_network_requires_food_presence_not_volume() -> void:
	var config := _fast_config()
	var systems = Systems.new(config)
	var sim = systems.simulation
	for position in [Vector2(-8.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 8.0)]:
		sim.add_rabbit(position)
	var plant_id: int = sim.add_plant("carrot_patch", Vector2(0.0, 14.0))
	sim.plants[plant_id]["food"] = 0.45
	var evidence: Dictionary = systems.run_director.spatial_evidence(sim, {
		"target": 1,
		"rabbits_per_group": 3,
		"minimum_separation": 280.0,
		"minimum_local_food": 0.0,
	})
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 1, "A nursery needs usable nearby food but not a minimum biomass volume", str(evidence))

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
	_expect(stretched_rejected and transient_rejected and short_hold_rejected and systems.run_director.has_completed("two_safe_havens"), "Nurseries Under Pressure requires a hunt-renewal cycle plus two separated nurseries that survive the hold", str({
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
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 3, "Nursery evidence can count three mutually separated local nursery zones", str(evidence))

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
	_expect(one_fox_blocked and systems.run_director.has_completed("predators_find_place"), "Predators Find Their Place requires two distinct hunters, a complete recovery rhythm, nurseries, and enough prey per fox")

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
	var expansion_step := float(systems.config["world"]["expansion_amount"])
	var initial_radius: float = systems.simulation.world_radius
	var preserved_plant: int = systems.simulation.add_plant("carrot_patch", Vector2(120.0, 0.0))
	_advance_to(systems, "nursery_network")
	var early_reveals_ok: bool = systems.simulation.world_radius == initial_radius + expansion_step * 4.0
	var before_major: float = systems.simulation.world_radius
	_satisfy_current_checkpoint(systems)
	var first_major_ok: bool = systems.simulation.world_radius == before_major + expansion_step and systems.run_director.is_unlocked("fox") and systems.inventory["fox"] == 2 and systems.run_director.supply_pool == "web"
	_advance_to(systems, "life_returns")
	var before_second: float = systems.simulation.world_radius
	_satisfy_current_checkpoint(systems)
	var second_major_ok: bool = systems.simulation.world_radius == before_second + expansion_step
	_advance_to(systems, "predators_find_place")
	var before_third: float = systems.simulation.world_radius
	_satisfy_current_checkpoint(systems)
	var third_major_ok: bool = systems.simulation.world_radius == before_third + expansion_step and systems.run_director.supply_pool == "living"
	var after: float = systems.simulation.world_radius
	systems.advance(0.5)
	_expect(early_reveals_ok and first_major_ok and second_major_ok and third_major_ok and after == initial_radius + expansion_step * 9.0 and systems.simulation.world_radius == after and systems.simulation.plants.has(preserved_plant), "every completed checkpoint reveals one persistent terrain step while major rewards still occur at checkpoints 5, 7, and 9")

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
		rabbit_row["title"].text,
		rabbit_row["value"].text,
	]).to_lower()
	var checklist_layout: bool = "checkpoint 1 of 10" in joined and "rabbits alive" in joined
	var animal_heuristic: bool = rabbit_row["glyph"] != null and rabbit_row["glyph"].kind == "rabbit"
	var actual_progress: bool = initial_population == "0/4 rabbits" and live_population == "1/4 rabbits"
	var compact: bool = is_equal_approx(hud.objective_panel.custom_minimum_size.x, 360.0)
	var no_extra_copy: bool = hud.objective_progress_view.get_child_count() == 8 \
		and hud.objective_progress_view.rows_box.get_child_count() == 2 \
		and rabbit_row["container"].get_child_count() == 3 \
		and hud.objective_progress_view.details_button.visible \
		and hud.objective_progress_view.next_heading.text == "TRY THIS"
	_expect(checklist_layout and animal_heuristic and actual_progress and compact and no_extra_copy, "checkpoint UI uses compact one-line goal rows with recognizable population art", joined)
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
				var goal_type := str(goal["type"])
				var unit: String = str({
					"founders_fed": "rabbits",
					"rabbit_birth": "births",
					"born_rabbit_fed": "rabbits",
					"safe_havens": "nurseries",
					"separated_birth_zones": "areas",
					"distinct_foxes_fed": "foxes",
					"prey_per_fox": "rabbits/fox",
					"rabbit_population": "rabbits",
					"fox_population": "foxes",
				}.get(goal_type, "goals"))
				var expected_value := "%d/%d %s" % [int(goal["current"]), int(goal["target"]), unit]
				if goal_type == "health":
					expected_value = {"fed": "Fed", "hungry": "Hungry", "starving": "Starving", "absent": "—"}.get(str(goal["status"]), "—")
				elif goal_type == "trend":
					expected_value = {
						"stable": "Stable",
						"under_pressure": "Under pressure",
						"falling": "Falling fast",
					}.get(str(goal["status"]), "Stable" if bool(goal["met"]) else "Falling fast")
				mapped = mapped and row["value"].text == expected_value
				if str(goal["type"]) == "fox_population":
					mapped = mapped and row["glyph"] != null and row["glyph"].kind == "fox"
				observed.append("%s %s" % [goal_id, row["value"].text])
		mapped = mapped and hud.objective_progress_view.goal_rows.has("hold")
		hud.free()
	_expect(mapped, "checkpoint UI maps every structured checkpoint goal into the task/status list", "; ".join(observed))

func _test_nursery_is_the_single_player_facing_term() -> void:
	var player_copy: Array[String] = []
	for milestone_value in Config.make()["progression"]["milestones"]:
		var milestone: Dictionary = milestone_value
		for field in ["title", "summary", "guidance", "teaser", "completion_message"]:
			player_copy.append(str(milestone.get(field, "")))
		for label in milestone.get("labels", {}).values():
			player_copy.append(str(label))
		for criterion_value in milestone.get("criteria", []):
			var criterion: Dictionary = criterion_value
			for field in ["label", "metric_label", "lens_label"]:
				player_copy.append(str(criterion.get(field, "")))
	var hud = HUD.new()
	var late_nursery_coach: Dictionary = hud._qualitative_objective_coach("two_safe_havens", "evidence", "playing")
	player_copy.append(str(late_nursery_coach.get("title", "")))
	player_copy.append(str(late_nursery_coach.get("detail", "")))
	hud.free()
	var joined := " ".join(player_copy).to_lower()
	_expect("nurser" in joined and not "haven" in joined, "player-facing progression consistently calls every viable rabbit group a nursery", joined)

func _test_checkpoint_ui_explains_colony_stability_without_threshold_math() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][6]["severe_decline_fraction"] = 0.38
	var systems = Systems.new(config)
	systems.run_director.milestone_index = 6
	_ensure_rabbits(systems, 10)
	_ensure_foxes(systems, 1)
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	systems.advance(1.1)
	hud.refresh()
	var trend_row: Dictionary = hud.objective_progress_view.goal_rows["rabbit_trend"]
	var stable: bool = trend_row["title"].text == "Colony stability" \
		and trend_row["value"].text == "Stable"

	var rabbit_ids: Array = systems.simulation.rabbits.keys()
	for index in range(3):
		systems.simulation.kill_rabbit(rabbit_ids[index], "predation")
	systems.advance(1.1)
	hud.refresh()
	var under_pressure: bool = trend_row["value"].text == "Under pressure" \
		and trend_row["value"].theme_type_variation == "LabelWarning"

	systems.simulation.kill_rabbit(rabbit_ids[3], "predation")
	systems.advance(1.1)
	hud.refresh()
	var falling: bool = trend_row["value"].text == "Falling fast" \
		and trend_row["value"].theme_type_variation == "LabelDanger" \
		and "checkpoint is paused" in trend_row["value"].tooltip_text.to_lower()
	var hides_threshold_math: bool = "%" not in trend_row["value"].text \
		and "/" not in trend_row["value"].text \
		and "%" not in trend_row["value"].tooltip_text
	_expect(stable and under_pressure and falling and hides_threshold_math, "checkpoint UI translates the rabbit-loss threshold into plain colony-stability states", trend_row["value"].text)
	hud.free()

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

func _test_checkpoint_ui_stays_scan_first() -> void:
	var systems = Systems.new(_fast_config())
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud.refresh()
	var rabbit_row: Dictionary = hud.objective_progress_view.goal_rows["rabbit_population"]
	var row_value: String = rabbit_row["value"].text
	var hint_available: bool = hud.objective_progress_view.details_button.visible \
		and hud.objective_progress_view.details_button.text == "Need a hint?" \
		and not hud.objective_progress_view.details_box.visible
	var next_action_visible: bool = hud.objective_progress_view.next_heading.text == "TRY THIS" \
		and not hud.objective_progress_view.next_label.text.is_empty()
	var compact_value: bool = row_value == "0/4 rabbits" and not "min" in row_value and not "needed" in row_value
	hud.objective_progress_view.details_button.pressed.emit()
	var hint_open: bool = hud.objective_progress_view.details_box.visible and hud.objective_progress_view.details_button.text == "Hide hint"
	hud.objective_progress_view.details_button.pressed.emit()
	var hint_closed: bool = not hud.objective_progress_view.details_box.visible and hud.objective_progress_view.details_button.text == "Need a hint?"
	_expect(hint_available and next_action_visible and compact_value and hint_open and hint_closed, "checkpoint UI keeps optional guidance beside compact goal rows", row_value)
	hud.free()

func _test_checkpoint_hint_stays_stable_across_live_phases() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][4]["stabilization"] = 999.0
	var systems = Systems.new(config)
	systems.run_director.milestone_index = 4
	systems.run_director._reset_milestone_evidence()
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)

	_arrange_havens(systems, 12, 2)
	hud.refresh()
	var evidence_phase := str(systems.current_objective_progress()["phase"])
	var action_with_two: String = hud.objective_progress_view.next_label.text
	hud.objective_progress_view.details_button.pressed.emit()
	var initial_hint: String = hud.objective_progress_view.details_detail.text

	_arrange_havens(systems, 12, 3)
	hud.refresh()
	var stabilizing_phase := str(systems.current_objective_progress()["phase"])
	var action_with_three: String = hud.objective_progress_view.next_label.text
	var hint_with_three: String = hud.objective_progress_view.details_detail.text
	var stayed_open_with_three: bool = hud.objective_progress_view.details_box.visible

	_arrange_havens(systems, 12, 2)
	hud.refresh()
	var returned_phase := str(systems.current_objective_progress()["phase"])
	var returned_hint: String = hud.objective_progress_view.details_detail.text
	var stayed_open_after_return: bool = hud.objective_progress_view.details_box.visible

	var stable_definition: bool = initial_hint == hint_with_three \
		and hint_with_three == returned_hint \
		and "A nursery has at least three rabbits" in initial_hint \
		and hud.objective_progress_view.details_detail.get_parent() == hud.objective_progress_view.details_box
	var live_coaching_changed: bool = action_with_two != action_with_three \
		and "1 more nursery" in action_with_two \
		and action_with_three == "Let the pattern settle."
	_expect(
		evidence_phase == "evidence" and stabilizing_phase == "stabilizing" and returned_phase == "evidence" \
			and stable_definition and live_coaching_changed and stayed_open_with_three and stayed_open_after_return,
		"checkpoint hints remain objective-scoped while TRY THIS responds to live nursery phases",
		str({
			"phases": [evidence_phase, stabilizing_phase, returned_phase],
			"hints": [initial_hint, hint_with_three, returned_hint],
			"actions": [action_with_two, action_with_three],
			"open": [stayed_open_with_three, stayed_open_after_return],
		})
	)
	hud.free()

func _test_debug_retains_exact_evaluator_detail() -> void:
	var systems = Systems.new(_fast_config())
	var debug_text := "\n".join(systems.run_director.debug_lines(systems.simulation))
	systems.run_director.milestone_index = 6
	var predator_debug_text := "\n".join(systems.run_director.debug_lines(systems.simulation))
	_expect(
		"stable 0.0s/0.2s" in debug_text and "founders fed 0" in debug_text and "grace 0.0s" in debug_text \
			and "Trend rabbit loss 0% · limit 110% · window 16s" in predator_debug_text,
		"development debug retains exact evidence, stabilization, trend, and Critical timing"
	)

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
