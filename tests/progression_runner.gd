extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")
const HUD = preload("res://ui/game_hud.gd")
const Lens = preload("res://rendering/objective_lens.gd")

const CHECKPOINT_IDS := [
	"colony_gathers",
	"new_arrivals",
	"nursery_network",
	"predators_find_place",
	"living_ecosystem",
]
const NURSERY_CENTERS := [
	Vector2(-230.0, -140.0),
	Vector2(230.0, -140.0),
	Vector2(240.0, 180.0),
]

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_test_checkpoint_contract_is_five_focused_challenges()
	_test_new_checkpoints_open_mostly_unfulfilled()
	_test_colony_requires_population_and_distinct_feeding()
	_test_new_generation_requires_fresh_births_growth_and_geography()
	_test_nursery_network_requires_fresh_young_and_three_live_groups()
	_test_predator_rhythm_requires_fresh_order_distinct_foxes_and_recovery()
	_test_final_cycle_is_fresh_ordered_and_latched()
	_test_objective_lens_tracks_fresh_newborns_and_birthplaces()
	_test_objective_lens_shares_nursery_classification()
	_test_objective_lens_cleans_up_markers_and_feedback()
	_test_nursery_requires_food_presence_not_volume()
	_test_local_nurseries_survive_unfed_rabbit_bridges()
	_test_safe_haven_counter_supports_three_zones()
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
	_test_checkpoint_ui_is_compact_and_capped()
	_test_checkpoint_ui_maps_every_evidence_type()
	_test_nursery_is_the_single_player_facing_term()
	_test_every_goal_has_an_on_demand_explainer()
	_test_checkpoint_guide_stays_stable_across_live_phases()
	_test_minor_and_major_feedback_are_distinct()
	_test_debug_retains_exact_evaluator_detail()
	_test_completion_ui_and_sandbox_epilogue()
	_test_fresh_system_resets_the_run()
	print("\n%d focused progression tests passed; %d failed." % [passed, failures.size()])
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
		systems.simulation.add_rabbit(Vector2(float(index % 4) * 18.0, float(index / 4) * 18.0), "placement")

func _ensure_foxes(systems, count: int) -> void:
	while systems.simulation.population("fox") < count:
		var index: int = systems.simulation.population("fox")
		systems.simulation.add_fox(Vector2(90.0 + float(index) * 25.0, 0.0), "placement")

func _kill_all_rabbits(systems, cause: String = "test") -> void:
	for rabbit_id in systems.simulation.rabbits.keys():
		systems.simulation.kill_rabbit(rabbit_id, cause)

func _arrange_havens(systems, rabbit_count: int, haven_count: int) -> void:
	_ensure_rabbits(systems, rabbit_count)
	var centers: Array = NURSERY_CENTERS.slice(0, haven_count)
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

func _add_fresh_young(systems, positions: Array, fed_count: int) -> Array[int]:
	var ids: Array[int] = []
	for position in positions:
		var entity_id: int = systems.simulation.add_rabbit(position, "birth")
		systems.simulation.rabbits[entity_id]["age"] = 12.0
		ids.append(entity_id)
	for index in range(mini(fed_count, ids.size())):
		systems.run_director.record_creature_fed("rabbit", ids[index], -1)
	return ids

func _satisfy_current_checkpoint(systems) -> void:
	match systems.run_director.current_milestone_id():
		"colony_gathers":
			_ensure_rabbits(systems, 4)
			var founders: Array = systems.simulation.rabbits.keys()
			for index in range(3):
				systems.run_director.record_creature_fed("rabbit", founders[index], -1)
		"new_arrivals":
			_ensure_rabbits(systems, 4)
			_add_fresh_young(systems, [
				NURSERY_CENTERS[0], NURSERY_CENTERS[0] + Vector2(18.0, 0.0),
				NURSERY_CENTERS[1], NURSERY_CENTERS[1] + Vector2(18.0, 0.0),
			], 3)
		"nursery_network":
			_add_fresh_young(systems, NURSERY_CENTERS, 3)
			_arrange_havens(systems, 12, 3)
		"predators_find_place":
			_arrange_havens(systems, 12, 3)
			_ensure_foxes(systems, 2)
			var fox_ids: Array = systems.simulation.foxes.keys()
			systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[0], Vector2.ZERO)
			_add_fresh_young(systems, [NURSERY_CENTERS[0]], 1)
			systems.run_director.record_predation(fox_ids[1], systems.simulation.rabbits.keys()[1], Vector2.ZERO)
		"living_ecosystem":
			_arrange_havens(systems, 15, 3)
			_ensure_foxes(systems, 2)
			var fox_ids: Array = systems.simulation.foxes.keys()
			systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[0], Vector2.ZERO)
			_add_fresh_young(systems, [NURSERY_CENTERS[0]], 1)
			systems.run_director.record_predation(fox_ids[1], systems.simulation.rabbits.keys()[1], Vector2.ZERO)
			_add_fresh_young(systems, [NURSERY_CENTERS[1]], 1)
			_add_fresh_young(systems, [NURSERY_CENTERS[2]], 1)
			systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[2], Vector2.ZERO)
	systems.advance(0.3)

func _advance_to(systems, milestone_id: String) -> void:
	var guard := 0
	while systems.run_director.current_milestone_id() != milestone_id and systems.run_director.run_state == RunDirector.STATE_PLAYING and guard < 8:
		_satisfy_current_checkpoint(systems)
		guard += 1

func _complete_run(systems) -> void:
	var guard := 0
	while systems.run_director.run_state == RunDirector.STATE_PLAYING and guard < 8:
		_satisfy_current_checkpoint(systems)
		guard += 1

func _test_checkpoint_contract_is_five_focused_challenges() -> void:
	var config := Config.make()
	var milestones: Array = config["progression"]["milestones"]
	var ids: Array[String] = []
	var tiers: Array[String] = []
	var holds: Array[float] = []
	var configured_rows: Array[int] = []
	var fresh_criterion_counts: Array[int] = []
	for milestone in milestones:
		ids.append(str(milestone["id"]))
		tiers.append(str(milestone["tier"]))
		holds.append(float(milestone["stabilization"]))
		var rows: int = milestone.get("criteria", []).size() + (1 if int(milestone.get("rabbit_min", 0)) > 0 else 0) + (1 if int(milestone.get("fox_min", 0)) > 0 else 0) + 1
		configured_rows.append(rows)
		var fresh_count := 0
		for criterion in milestone.get("criteria", []):
			if str(criterion.get("type", "")) in ["founders_fed", "rabbit_birth", "ordered_cycle", "distinct_foxes_fed", "separated_birth_zones"] \
				or bool(criterion.get("fresh_only", false)):
				fresh_count += 1
		fresh_criterion_counts.append(fresh_count)
	var valid: bool = ids == CHECKPOINT_IDS \
		and tiers == ["minor", "minor", "major", "major", "final"] \
		and configured_rows == [3, 4, 4, 4, 5] \
		and fresh_criterion_counts == [1, 3, 2, 3, 3] \
		and holds == [10.0, 16.0, 20.0, 22.0, 30.0]
	_expect(valid, "the run uses five longer checkpoints with no more than five visible goals", str({"ids": ids, "rows": configured_rows, "fresh": fresh_criterion_counts, "holds": holds}))

func _test_new_checkpoints_open_mostly_unfulfilled() -> void:
	var systems = Systems.new(_fast_config())
	var observations: Dictionary = {}
	while systems.run_director.run_state == RunDirector.STATE_PLAYING:
		var leaving: String = systems.run_director.current_milestone_id()
		_satisfy_current_checkpoint(systems)
		if systems.run_director.run_state != RunDirector.STATE_PLAYING:
			break
		var progress: Dictionary = systems.current_objective_progress()
		var met := 0
		var zeroed_fresh := true
		for criterion in progress["criteria"]:
			if bool(criterion["met"]):
				met += 1
			if str(criterion["type"]) != "safe_havens":
				zeroed_fresh = zeroed_fresh and int(criterion["current"]) == 0
		observations[systems.run_director.current_milestone_id()] = {"met": met, "fresh_zero": zeroed_fresh, "after": leaving}
	var valid: bool = observations.size() == 4
	for entry in observations.values():
		valid = valid and int(entry["met"]) <= 1 and bool(entry["fresh_zero"])
	_expect(valid, "every later checkpoint resets its new work and opens with at most one carried goal", str(observations))

func _test_colony_requires_population_and_distinct_feeding() -> void:
	var systems = Systems.new(_fast_config())
	_ensure_rabbits(systems, 4)
	var ids: Array = systems.simulation.rabbits.keys()
	for index in range(2):
		systems.run_director.record_creature_fed("rabbit", ids[index], -1)
	systems.advance(0.3)
	var two_fed_blocked: bool = systems.run_director.current_milestone_id() == "colony_gathers"
	systems.run_director.record_creature_fed("rabbit", ids[2], -1)
	systems.advance(0.3)
	_expect(two_fed_blocked and systems.run_director.has_completed("colony_gathers"), "A Colony Gathers requires four living rabbits and three distinct fed founders")

func _test_new_generation_requires_fresh_births_growth_and_geography() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "new_arrivals")
	_ensure_rabbits(systems, 12)
	systems.advance(0.3)
	var placements_blocked: bool = systems.run_director.current_milestone_id() == "new_arrivals"
	var young := _add_fresh_young(systems, [Vector2.ZERO, Vector2(20.0, 0.0), Vector2(40.0, 0.0), Vector2(60.0, 0.0)], 3)
	systems.advance(0.3)
	var one_area_blocked: bool = systems.run_director.current_milestone_id() == "new_arrivals"
	var moved_id: int = young[3]
	# Birthplace evidence records the location at birth, so moving a rabbit cannot
	# manufacture a second birth area. A genuinely new distant birth is required.
	systems.simulation.rabbits[moved_id]["position"] = Vector2(300.0, 0.0)
	systems.advance(0.3)
	var movement_blocked: bool = systems.run_director.current_milestone_id() == "new_arrivals"
	_add_fresh_young(systems, [Vector2(300.0, 0.0)], 1)
	systems.advance(0.3)
	_expect(placements_blocked and one_area_blocked and movement_blocked and systems.run_director.has_completed("new_arrivals"), "A New Generation requires checkpoint-local births, fed young, and genuinely separated birth areas")

func _test_nursery_network_requires_fresh_young_and_three_live_groups() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "nursery_network")
	_arrange_havens(systems, 12, 3)
	systems.advance(0.3)
	var inherited_layout_blocked: bool = systems.run_director.current_milestone_id() == "nursery_network"
	_add_fresh_young(systems, NURSERY_CENTERS, 3)
	_arrange_havens(systems, 15, 2)
	systems.advance(0.3)
	var two_groups_blocked: bool = systems.run_director.current_milestone_id() == "nursery_network"
	_arrange_havens(systems, 15, 3)
	systems.advance(0.3)
	_expect(inherited_layout_blocked and two_groups_blocked and systems.run_director.has_completed("nursery_network"), "A Nursery Network requires fresh raised young in three areas plus three simultaneous live nurseries")

func _test_predator_rhythm_requires_fresh_order_distinct_foxes_and_recovery() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "predators_find_place")
	_arrange_havens(systems, 12, 3)
	_ensure_foxes(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	_add_fresh_young(systems, [NURSERY_CENTERS[0]], 1)
	var birth_first_ignored: bool = systems.run_director.sequence_progress == 0
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[1], Vector2.ZERO)
	var wrong_order_ignored: bool = systems.run_director.sequence_progress == 1
	var pre_cycle_young_ignored: bool = int(systems.current_objective_progress()["criteria"][2]["current"]) == 0
	_add_fresh_young(systems, [NURSERY_CENTERS[1]], 1)
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[2], Vector2.ZERO)
	systems.advance(0.3)
	var one_fox_blocked: bool = systems.run_director.current_milestone_id() == "predators_find_place"
	systems.run_director.record_predation(fox_ids[1], systems.simulation.rabbits.keys()[3], Vector2.ZERO)
	systems.advance(0.3)
	_expect(birth_first_ignored and wrong_order_ignored and pre_cycle_young_ignored and one_fox_blocked and systems.run_director.has_completed("predators_find_place"), "Predator–Prey Rhythm requires a fresh ordered cycle, two distinct hunters, and a fed rabbit born after the opening hunt")

func _test_final_cycle_is_fresh_ordered_and_latched() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][4]["stabilization"] = 0.6
	config["progression"]["milestones"][4]["evidence_window"] = 0.2
	var systems = Systems.new(config)
	_advance_to(systems, "living_ecosystem")
	var fresh_reset: bool = systems.run_director.sequence_progress == 0
	_arrange_havens(systems, 15, 3)
	_ensure_foxes(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	var first_young := _add_fresh_young(systems, [NURSERY_CENTERS[0]], 1)
	var birth_first_ignored: bool = systems.run_director.sequence_progress == 0
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[1], Vector2.ZERO)
	var wrong_order_blocked: bool = systems.run_director.sequence_progress == 1
	_add_fresh_young(systems, [NURSERY_CENTERS[1]], 1)
	systems.run_director.record_predation(fox_ids[1], systems.simulation.rabbits.keys()[2], Vector2.ZERO)
	_add_fresh_young(systems, [NURSERY_CENTERS[2]], 1)
	_add_fresh_young(systems, [NURSERY_CENTERS[0]], 1)
	systems.run_director.record_predation(fox_ids[0], systems.simulation.rabbits.keys()[3], Vector2.ZERO)
	systems.advance(0.3)
	var latched_after_window: bool = systems.run_director.sequence_completed and systems.run_director.run_state == RunDirector.STATE_PLAYING
	systems.advance(0.4)
	_expect(not first_young.is_empty() and fresh_reset and birth_first_ignored and wrong_order_blocked and latched_after_window and systems.run_director.run_state == RunDirector.STATE_COMPLETED, "Living Ecosystem needs fresh distributed renewal and latches its five-step proof through the final hold")

func _test_objective_lens_tracks_fresh_newborns_and_birthplaces() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][1]["criteria"][1]["minimum_age"] = 8.0
	var systems = Systems.new(config)
	systems.run_director.milestone_index = 1
	systems.run_director._reset_milestone_evidence()
	var first_id: int = systems.simulation.add_rabbit(Vector2.ZERO, "birth")
	var second_id: int = systems.simulation.add_rabbit(Vector2(130.0, 0.0), "birth")
	var third_id: int = systems.simulation.add_rabbit(Vector2(280.0, 0.0), "birth")
	var before: Dictionary = systems.current_objective_lens()
	var before_states := {}
	for marker in before["attention"]:
		if str(marker.get("criterion_id", "")) == "young_rabbits_fed":
			before_states[int(marker["entity_id"])] = str(marker["state"])
	systems.run_director.record_creature_fed("rabbit", first_id, -1)
	var growing: Dictionary = systems.current_objective_lens()
	var growing_state := ""
	for marker in growing["attention"]:
		if str(marker.get("criterion_id", "")) == "young_rabbits_fed" and int(marker["entity_id"]) == first_id:
			growing_state = str(marker["state"])
	systems.simulation.rabbits[first_id]["age"] = 9.0
	var satisfied: Dictionary = systems.current_objective_lens()
	var satisfied_state := ""
	for marker in satisfied["attention"]:
		if str(marker.get("criterion_id", "")) == "young_rabbits_fed" and int(marker["entity_id"]) == first_id:
			satisfied_state = str(marker["state"])
	var birthplace_ordinals: Array[int] = []
	for marker in satisfied["evidence"]:
		if str(marker.get("criterion_id", "")) == "new_birthplaces":
			birthplace_ordinals.append(int(marker["ordinal"]))
	systems.simulation.kill_rabbit(second_id, "test")
	systems.run_director.milestone_index = 2
	systems.run_director._reset_milestone_evidence()
	var cleared: Dictionary = systems.current_objective_lens()
	var valid: bool = before_states.get(first_id) == "needs_food" and before_states.get(second_id) == "needs_food" \
		and before_states.get(third_id) == "needs_food" and growing_state == "growing" and satisfied_state == "satisfied" \
		and birthplace_ordinals == [1, 2] and cleared["attention"].is_empty()
	_expect(valid, "Objective Lens follows fresh young and shares exact birthplace classification before clearing at checkpoint entry", str({"states": before_states, "ordinals": birthplace_ordinals}))

func _test_objective_lens_shares_nursery_classification() -> void:
	var systems = Systems.new(_fast_config())
	systems.run_director.milestone_index = 2
	systems.run_director._reset_milestone_evidence()
	_arrange_havens(systems, 12, 2)
	var lens: Dictionary = systems.current_objective_lens()
	var progress: Dictionary = systems.current_objective_progress()
	var nursery_goal: Dictionary = progress["criteria"][0]
	var ordinals: Array[int] = []
	var semantic_markers := true
	var no_evaluator_constants := true
	for marker in lens["evidence"]:
		if str(marker.get("role", "")) != "nursery":
			continue
		ordinals.append(int(marker["ordinal"]))
		semantic_markers = semantic_markers and str(marker.get("label", "")) == "Nursery" and marker.get("position", Vector2.INF) != Vector2.INF
		no_evaluator_constants = no_evaluator_constants and not marker.has("radius") and not marker.has("minimum_separation") \
			and not marker.has("minimum_local_food") and not marker.has("food") and not marker.has("member_ids") and not marker.has("food_ids")
	var valid := ordinals.size() == int(nursery_goal["current"]) and ordinals == [1, 2] and semantic_markers and no_evaluator_constants
	_expect(valid, "Objective Lens marks exactly the live nurseries counted by progression without exposing evaluator thresholds", str(lens))

func _test_objective_lens_cleans_up_markers_and_feedback() -> void:
	var lens = Lens.new()
	var active := {
		"objective_id": "new_arrivals",
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
	_expect(no_duplicate_feedback and reset_rearms_feedback and old_marker_fading and faded_cleanly and reset_cleanly, "Objective Lens deduplicates feedback and cleans up across checkpoint evidence resets")

func _test_nursery_requires_food_presence_not_volume() -> void:
	var systems = Systems.new(_fast_config())
	var sim = systems.simulation
	for position in [Vector2(-8.0, 0.0), Vector2(8.0, 0.0), Vector2(0.0, 8.0)]:
		sim.add_rabbit(position)
	var plant_id: int = sim.add_plant("carrot_patch", Vector2(0.0, 14.0))
	sim.plants[plant_id]["food"] = 0.45
	var evidence: Dictionary = systems.run_director.spatial_evidence(sim, {"target": 1, "rabbits_per_group": 3, "minimum_separation": 280.0, "minimum_local_food": 0.0})
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 1, "a nursery needs usable nearby food but not a hidden biomass quota", str(evidence))

func _test_local_nurseries_survive_unfed_rabbit_bridges() -> void:
	var systems = Systems.new(_fast_config())
	var sim = systems.simulation
	for x in [-210.0, -194.0, -90.0, 30.0, 150.0, 194.0, 210.0]:
		sim.add_rabbit(Vector2(x, 0.0))
	for x in [-210.0, 210.0]:
		var plant_id: int = sim.add_plant("berry_bush", Vector2(x, 10.0))
		sim.plants[plant_id]["food"] = 30.0
	var evidence: Dictionary = systems.run_director.spatial_evidence(sim, {"target": 2, "rabbits_per_group": 2, "minimum_separation": 280.0, "minimum_local_food": 12.0})
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 2, "local nursery nuclei remain valid when unrelated unfed rabbits form a proximity chain", str(evidence))

func _test_safe_haven_counter_supports_three_zones() -> void:
	var systems = Systems.new(_fast_config())
	var sim = systems.simulation
	for center in [Vector2(-250.0, -170.0), Vector2(250.0, -170.0), Vector2(-250.0, 170.0)]:
		sim.add_rabbit(center + Vector2(-8.0, 0.0))
		sim.add_rabbit(center + Vector2(8.0, 0.0))
		var plant_id: int = sim.add_plant("berry_bush", center + Vector2(0.0, 10.0))
		sim.plants[plant_id]["food"] = 30.0
	var evidence: Dictionary = systems.run_director.spatial_evidence(sim, {"target": 3, "rabbits_per_group": 2, "minimum_separation": 280.0, "minimum_local_food": 12.0})
	_expect(bool(evidence["met"]) and int(evidence["separated_group_count"]) == 3, "nursery evidence counts three mutually separated local zones", str(evidence))

func _test_reward_timing_and_persistent_expansions() -> void:
	var systems = Systems.new(_fast_config())
	var step := float(systems.config["world"]["expansion_amount"])
	var initial_radius: float = systems.simulation.world_radius
	var preserved_plant: int = systems.simulation.add_plant("carrot_patch", Vector2(120.0, 0.0))
	_advance_to(systems, "nursery_network")
	var opening_reveals: bool = systems.simulation.world_radius == initial_radius + step * 4.0
	_satisfy_current_checkpoint(systems)
	var fox_unlock: bool = systems.simulation.world_radius == initial_radius + step * 6.0 and systems.run_director.is_unlocked("fox") \
		and systems.inventory["fox"] == 2 and systems.run_director.supply_pool == "web"
	_satisfy_current_checkpoint(systems)
	var predator_reward: bool = systems.simulation.world_radius == initial_radius + step * 8.0 and systems.run_director.supply_pool == "living"
	_satisfy_current_checkpoint(systems)
	var final_radius: float = systems.simulation.world_radius
	_expect(opening_reveals and fox_unlock and predator_reward and final_radius == initial_radius + step * 8.0 \
		and systems.simulation.plants.has(preserved_plant), "four checkpoint rewards reveal larger persistent terrain bands while preserving the living world")

func _test_supply_pool_progression() -> void:
	var config := Config.make()
	var pools: Dictionary = config["supply"]["pools"]
	var living_rabbit_bundles := 0
	var living_plant_units := 0
	for bundle in pools["living"]:
		if bundle["items"].has("rabbit"):
			living_rabbit_bundles += 1
		living_plant_units += int(bundle["items"].get("carrot_patch", 0)) + int(bundle["items"].get("berry_bush", 0))
	_expect(pools.size() == 3 and float(config["supply"]["interval"]) == 90.0 and living_rabbit_bundles == 1 and living_plant_units >= 8, "supplies retain the three ecological pools and plant-heavy Living support")

func _test_critical_is_armed_only_after_nursery_network() -> void:
	var before = Systems.new(_fast_config())
	_advance_to(before, "nursery_network")
	_kill_all_rabbits(before)
	before.advance(1.0)
	var safe_before: bool = before.run_director.run_state == RunDirector.STATE_PLAYING and not before.run_director.rabbit_failure_armed
	var after = Systems.new(_fast_config())
	_advance_to(after, "predators_find_place")
	_expect(safe_before and after.run_director.rabbit_failure_armed, "Critical remains dormant until the Nursery Network is established")

func _enter_critical(systems) -> void:
	_advance_to(systems, "predators_find_place")
	_kill_all_rabbits(systems, "starvation")
	systems.inventory["rabbit"] = 0
	systems.supply_pending = false
	systems.supply_choices = []
	systems.supply_time_remaining = 100.0
	systems.advance(0.3)

func _test_loss_of_breeding_group_enters_critical_at_one_x() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "predators_find_place")
	systems.set_speed(3.0)
	_kill_all_rabbits(systems)
	systems.inventory["rabbit"] = 0
	systems.advance(0.1)
	_expect(systems.run_director.run_state == RunDirector.STATE_CRITICAL and is_equal_approx(systems.simulation_speed, 1.0), "loss of breeding recovery capacity enters Critical and returns speed to 1x")

func _test_fox_extinction_is_not_game_over() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "predators_find_place")
	_ensure_foxes(systems, 1)
	for fox_id in systems.simulation.foxes.keys():
		systems.simulation.kill_fox(fox_id, "test")
	systems.advance(1.5)
	_expect(systems.run_director.run_state == RunDirector.STATE_PLAYING, "fox extinction alone does not trigger Critical or Game Over")

func _test_inventory_and_pending_supply_do_not_prevent_critical() -> void:
	var with_inventory = Systems.new(_fast_config())
	_advance_to(with_inventory, "predators_find_place")
	_kill_all_rabbits(with_inventory)
	with_inventory.inventory["rabbit"] = 3
	with_inventory.advance(0.3)
	var inventory_failed: bool = with_inventory.run_director.run_state == RunDirector.STATE_CRITICAL
	var with_supply = Systems.new(_fast_config())
	_advance_to(with_supply, "predators_find_place")
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

func _test_checkpoint_ui_is_compact_and_capped() -> void:
	var maximum_rows := 0
	var every_checkpoint_mapped := true
	var final_cycle_compact := false
	for index in range(Config.make()["progression"]["milestones"].size()):
		var systems = Systems.new(_fast_config())
		systems.run_director.milestone_index = index
		systems.run_director._reset_milestone_evidence()
		var hud = HUD.new()
		root.add_child(hud)
		hud.setup(systems)
		hud.refresh()
		maximum_rows = maxi(maximum_rows, hud.objective_progress_view.goal_rows.size())
		var progress: Dictionary = systems.current_objective_progress()
		for goal in progress["goals"]:
			every_checkpoint_mapped = every_checkpoint_mapped and hud.objective_progress_view.goal_rows.has(str(goal["id"]))
		every_checkpoint_mapped = every_checkpoint_mapped and hud.objective_progress_view.goal_rows.has("hold")
		if index == 4:
			var cycle_row: Dictionary = hud.objective_progress_view.goal_rows["living_cycle"]
			final_cycle_compact = cycle_row["title"].text == "Food-web cycle" \
				and cycle_row["value"].text == "0/5 · hunt next" \
				and "Complete these five events in order" in cycle_row["value"].tooltip_text \
				and "Next: fox hunt" in cycle_row["value"].tooltip_text
		hud.free()
	var opening = Systems.new(_fast_config())
	var opening_hud = HUD.new()
	root.add_child(opening_hud)
	opening_hud.setup(opening)
	opening_hud.refresh()
	var rabbit_row: Dictionary = opening_hud.objective_progress_view.goal_rows["rabbit_population"]
	var compact: bool = is_equal_approx(opening_hud.objective_panel.custom_minimum_size.x, 360.0) \
		and opening_hud.objective_eyebrow.text == "CHECKPOINT 1 OF 5" and rabbit_row["value"].text == "0/4 rabbits"
	opening_hud.free()
	_expect(maximum_rows == 5 and every_checkpoint_mapped and final_cycle_compact and compact, "checkpoint UI shows every blocker in at most five rows and compresses ordered cycles into one readable goal")

func _test_checkpoint_ui_maps_every_evidence_type() -> void:
	var mapped := true
	var observed: Array[String] = []
	for index in range(Config.make()["progression"]["milestones"].size()):
		var systems = Systems.new(_fast_config())
		systems.run_director.milestone_index = index
		systems.run_director._reset_milestone_evidence()
		var progress: Dictionary = systems.current_objective_progress()
		var hud = HUD.new()
		root.add_child(hud)
		hud.setup(systems)
		hud.refresh()
		for goal in progress["goals"]:
			var row_present: bool = hud.objective_progress_view.goal_rows.has(str(goal["id"]))
			mapped = mapped and row_present
			if row_present:
				observed.append("%s %s" % [str(goal["id"]), hud.objective_progress_view.goal_rows[str(goal["id"])]["value"].text])
		hud.free()
	_expect(mapped, "checkpoint UI maps every configured evidence type into the focused goal list", "; ".join(observed))

func _test_nursery_is_the_single_player_facing_term() -> void:
	var player_copy: Array[String] = []
	for milestone in Config.make()["progression"]["milestones"]:
		for field in ["title", "summary", "guidance", "guide_intro", "teaser", "completion_message"]:
			player_copy.append(str(milestone.get(field, "")))
		for help in milestone.get("goal_help", {}).values():
			player_copy.append(str(help.get("detail", "")))
		for label in milestone.get("labels", {}).values():
			player_copy.append(str(label))
		for criterion in milestone.get("criteria", []):
			for field in ["label", "metric_label", "lens_label"]:
				player_copy.append(str(criterion.get(field, "")))
	var joined := " ".join(player_copy).to_lower()
	_expect("nurser" in joined and not "haven" in joined, "player-facing progression consistently calls every viable rabbit group a nursery", joined)

func _test_every_goal_has_an_on_demand_explainer() -> void:
	var every_goal_explained := true
	for index in range(Config.make()["progression"]["milestones"].size()):
		var systems = Systems.new(_fast_config())
		systems.run_director.milestone_index = index
		systems.run_director._reset_milestone_evidence()
		var hud = HUD.new()
		root.add_child(hud)
		hud.setup(systems)
		hud.refresh()
		for row_id in hud.objective_progress_view.goal_rows:
			var row: Dictionary = hud.objective_progress_view.goal_rows[row_id]
			every_goal_explained = every_goal_explained and row["help_button"].visible \
				and hud.objective_progress_view.goal_help.has(str(row_id))
		hud.free()

	var final_systems = Systems.new(_fast_config())
	final_systems.run_director.milestone_index = 4
	final_systems.run_director._reset_milestone_evidence()
	var final_hud = HUD.new()
	root.add_child(final_hud)
	final_hud.setup(final_systems)
	final_hud.refresh()
	var nursery_is_still_unmet: bool = final_hud.objective_progress_view.next_label.text == "Build 3 more nurseries."
	var cycle_button: Button = final_hud.objective_progress_view.goal_rows["living_cycle"]["help_button"]
	cycle_button.pressed.emit()
	var cycle_visible_before_nurseries: bool = final_hud.objective_progress_view.selected_help_id == "living_cycle" \
		and final_hud.objective_progress_view.details_box.visible \
		and final_hud.objective_progress_view.details_title.text == "Food-web cycle" \
		and "fox hunts a rabbit → a rabbit is born → a fox hunts → a rabbit is born → a fox hunts" in final_hud.objective_progress_view.details_detail.text \
		and "within 4 minutes of the opening hunt" in final_hud.objective_progress_view.details_detail.text
	var cycle_explanation: String = final_hud.objective_progress_view.details_detail.text
	_arrange_havens(final_systems, 12, 3)
	final_hud.refresh()
	_arrange_havens(final_systems, 12, 1)
	final_hud.refresh()
	var cycle_survived_nursery_fluctuation: bool = final_hud.objective_progress_view.selected_help_id == "living_cycle" \
		and final_hud.objective_progress_view.details_detail.text == cycle_explanation
	_expect(every_goal_explained and nursery_is_still_unmet and cycle_visible_before_nurseries and cycle_survived_nursery_fluctuation, "every goal has a stable explainer and the full final cycle stays readable while nurseries fluctuate")
	final_hud.free()

func _test_checkpoint_guide_stays_stable_across_live_phases() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][2]["stabilization"] = 999.0
	var systems = Systems.new(config)
	systems.run_director.milestone_index = 2
	systems.run_director._reset_milestone_evidence()
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	_arrange_havens(systems, 12, 2)
	hud.refresh()
	var action_with_two: String = hud.objective_progress_view.next_label.text
	hud.objective_progress_view.details_button.pressed.emit()
	var initial_guide: String = hud.objective_progress_view.details_detail.text
	_arrange_havens(systems, 12, 3)
	hud.refresh()
	var action_with_three: String = hud.objective_progress_view.next_label.text
	var guide_with_three: String = hud.objective_progress_view.details_detail.text
	var stayed_open: bool = hud.objective_progress_view.details_box.visible
	var valid: bool = initial_guide == guide_with_three and "NEXT MOVE is the only guidance that changes" in initial_guide \
		and "1 more nursery" in action_with_two and "young" in action_with_three.to_lower() and stayed_open
	_expect(valid, "the checkpoint guide stays stable while NEXT MOVE reacts to live progress", str({"actions": [action_with_two, action_with_three], "guide": initial_guide}))
	hud.free()

func _test_minor_and_major_feedback_are_distinct() -> void:
	var systems = Systems.new(_fast_config())
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud._on_milestone_completed(0, "colony_gathers", "Minor beat")
	var minor_compact: bool = hud.toast_label.text == "Minor beat" and hud.toast_label.theme_type_variation == "BodyLarge" and not hud.ending_overlay.visible
	hud._on_milestone_completed(2, "nursery_network", "Major beat")
	var major_emphasized: bool = hud.toast_label.text == "MEADOW MILESTONE · Major beat" and hud.toast_label.theme_type_variation == "HeadingThree" and not hud.ending_overlay.visible
	_expect(minor_compact and major_emphasized, "minor and major checkpoint feedback remain visually distinct")
	hud.free()

func _test_debug_retains_exact_evaluator_detail() -> void:
	var systems = Systems.new(_fast_config())
	var opening_debug := "\n".join(systems.run_director.debug_lines(systems.simulation))
	systems.run_director.milestone_index = 4
	systems.run_director._reset_milestone_evidence()
	var final_debug := "\n".join(systems.run_director.debug_lines(systems.simulation))
	_expect("Checkpoint 1/5" in opening_debug and "founders fed 0" in opening_debug and "stable 0.0s/0.2s" in opening_debug \
		and "Checkpoint 5/5" in final_debug and "Sequence 0/5" in final_debug and "grace 0.0s" in final_debug, "development debug retains exact evidence, sequence, hold, and Critical timing")

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
	_expect(completed_ui and not hud.ending_overlay.visible and systems.run_director.run_state == RunDirector.STATE_SANDBOX and systems.simulation.simulation_time > before, "completion remains a single final overlay with a live sandbox epilogue")
	hud.free()

func _test_fresh_system_resets_the_run() -> void:
	var completed = Systems.new(_fast_config())
	_complete_run(completed)
	var fresh = Systems.new(_fast_config())
	_expect(fresh.run_director.run_state == RunDirector.STATE_PLAYING and fresh.run_director.current_milestone_id() == "colony_gathers" \
		and fresh.simulation.simulation_time == 0.0 and not fresh.run_director.is_unlocked("fox"), "a new ecosystem starts from clean five-checkpoint progression and simulation state")
