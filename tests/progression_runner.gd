extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")
const HUD = preload("res://ui/game_hud.gd")

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_test_checkpoint_contract_and_reward_tiers()
	_test_founders_require_distinct_actual_feeding()
	_test_first_new_life_requires_birth()
	_test_next_generation_requires_born_survivor_to_feed()
	_test_first_hunt_requires_successful_predation()
	_test_life_returns_requires_fresh_birth()
	_test_two_safe_havens_are_spatial_and_stable()
	_test_two_distinct_foxes_and_birth_are_required()
	_test_final_cycle_is_fresh_ordered_and_latched()
	_test_reward_timing_and_persistent_expansions()
	_test_supply_pool_progression()
	_test_critical_is_armed_only_after_next_generation()
	_test_loss_of_breeding_group_enters_critical_at_one_x()
	_test_fox_extinction_is_not_game_over()
	_test_inventory_and_pending_supply_do_not_prevent_critical()
	_test_supply_modal_pauses_critical_grace()
	_test_recovery_requires_living_settling_period()
	_test_failed_recovery_causes_game_over()
	_test_first_recovery_supply_is_not_repeated()
	_test_normal_ui_hides_internal_progression_mechanics()
	_test_minor_and_major_feedback_are_distinct()
	_test_debug_retains_exact_evaluator_detail()
	_test_completion_ui_and_sandbox_epilogue()
	_test_fresh_system_resets_the_run()
	print("\n%d V0.3 progression tests passed; %d failed." % [passed, failures.size()])
	for failure in failures:
		printerr("FAILED: %s" % failure)
	quit(1 if not failures.is_empty() else 0)

func _fast_config() -> Dictionary:
	var config := Config.make().duplicate(true)
	config["simulation"]["max_steps_per_frame"] = 1000
	config["supply"]["interval"] = 100.0
	config["rabbit"]["hunger_rate"] = 0.0
	config["rabbit"]["lifespan"] = 9999.0
	config["fox"]["hunger_rate"] = 0.0
	config["fox"]["lifespan"] = 9999.0
	for milestone in config["progression"]["milestones"]:
		milestone["stabilization"] = 0.2
		milestone["severe_decline_fraction"] = 1.1
	config["progression"]["milestones"][2]["born_survival_age"] = 0.0
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

func _feed_current_founders(systems) -> void:
	_ensure_rabbits(systems, 4)
	for rabbit_id in systems.simulation.rabbits.keys().slice(0, 4):
		systems.run_director.record_creature_fed("rabbit", rabbit_id, -1)

func _arrange_two_havens(systems) -> void:
	_ensure_rabbits(systems, 6)
	var ids: Array = systems.simulation.rabbits.keys()
	for index in range(ids.size()):
		var side := -1.0 if index % 2 == 0 else 1.0
		var row := float(index / 2)
		var rabbit: Dictionary = systems.simulation.rabbits[ids[index]]
		rabbit["position"] = Vector2(side * 210.0, row * 16.0)
		rabbit["previous_position"] = rabbit["position"]
		rabbit["velocity"] = Vector2.ZERO
		rabbit["previous_velocity"] = Vector2.ZERO
	for plant in systems.simulation.plants.values():
		plant["food"] = 0.0
	systems.simulation.add_plant("berry_bush", Vector2(-210.0, 10.0))
	systems.simulation.add_plant("berry_bush", Vector2(210.0, 10.0))

func _satisfy_current_checkpoint(systems) -> void:
	match systems.run_director.current_milestone_id():
		"founders_forage":
			_feed_current_founders(systems)
		"first_new_life":
			_ensure_rabbits(systems, 2)
			systems.simulation.add_rabbit(Vector2(22.0, 8.0), "birth")
		"next_generation":
			_ensure_rabbits(systems, 4)
			var young_id: int = systems.simulation.add_rabbit(Vector2(24.0, 8.0), "birth")
			systems.simulation.rabbits[young_id]["age"] = 12.0
			systems.run_director.record_creature_fed("rabbit", young_id, -1)
		"first_hunt":
			_ensure_rabbits(systems, 5)
			_ensure_foxes(systems, 1)
			var fox_id: int = systems.simulation.foxes.keys()[0]
			var prey_id: int = systems.simulation.rabbits.keys()[0]
			systems.run_director.record_predation(fox_id, prey_id, systems.simulation.rabbits[prey_id]["position"])
		"life_returns":
			_ensure_rabbits(systems, 4)
			_ensure_foxes(systems, 1)
			systems.simulation.add_rabbit(Vector2(28.0, 8.0), "birth")
		"two_safe_havens":
			_arrange_two_havens(systems)
		"predators_find_place":
			_ensure_rabbits(systems, 6)
			_ensure_foxes(systems, 2)
			var fox_ids: Array = systems.simulation.foxes.keys()
			systems.run_director.record_creature_fed("fox", fox_ids[0], -1)
			systems.run_director.record_creature_fed("fox", fox_ids[1], -1)
			systems.simulation.add_rabbit(Vector2(30.0, 8.0), "birth")
		"living_ecosystem":
			_ensure_rabbits(systems, 8)
			_ensure_foxes(systems, 2)
			var fox_id: int = systems.simulation.foxes.keys()[0]
			systems.simulation.add_rabbit(Vector2(34.0, 8.0), "birth")
			systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[0], Vector2.ZERO)
			systems.simulation.add_rabbit(Vector2(38.0, 8.0), "birth")
			systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[1], Vector2.ZERO)
	systems.advance(0.3)

func _advance_to(systems, milestone_id: String) -> void:
	var guard := 0
	while systems.run_director.current_milestone_id() != milestone_id and systems.run_director.run_state == RunDirector.STATE_PLAYING and guard < 12:
		_satisfy_current_checkpoint(systems)
		guard += 1

func _complete_run(systems) -> void:
	var guard := 0
	while systems.run_director.run_state == RunDirector.STATE_PLAYING and guard < 12:
		_satisfy_current_checkpoint(systems)
		guard += 1

func _test_checkpoint_contract_and_reward_tiers() -> void:
	var config := Config.make()
	var ids: Array[String] = []
	var tiers: Array[String] = []
	for milestone in config["progression"]["milestones"]:
		ids.append(str(milestone["id"]))
		tiers.append(str(milestone["tier"]))
	_expect(ids == ["founders_forage", "first_new_life", "next_generation", "first_hunt", "life_returns", "two_safe_havens", "predators_find_place", "living_ecosystem"] \
		and tiers == ["minor", "minor", "major", "minor", "major", "minor", "major", "final"], "the run uses the locked eight-checkpoint order and reward tiers")

func _test_founders_require_distinct_actual_feeding() -> void:
	var systems = Systems.new(_fast_config())
	_ensure_rabbits(systems, 4)
	var rabbit_ids: Array = systems.simulation.rabbits.keys()
	var plant_id: int = systems.simulation.add_plant("berry_bush", Vector2.ZERO)
	for repeat in range(4):
		systems.simulation._consume_plant(systems.simulation.rabbits[rabbit_ids[0]], systems.simulation.plants[plant_id], 0.05)
	systems.advance(0.3)
	var repeated_blocked: bool = systems.run_director.current_milestone_id() == "founders_forage"
	for index in range(1, 4):
		systems.simulation._consume_plant(systems.simulation.rabbits[rabbit_ids[index]], systems.simulation.plants[plant_id], 0.05)
	systems.advance(0.3)
	_expect(repeated_blocked and systems.run_director.has_completed("founders_forage"), "Founders Find Forage requires distinct placed rabbits to actually feed")

func _test_first_new_life_requires_birth() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "first_new_life")
	_ensure_rabbits(systems, 8)
	systems.advance(0.4)
	var placements_blocked: bool = systems.run_director.current_milestone_id() == "first_new_life"
	systems.simulation.add_rabbit(Vector2(55.0, 0.0), "birth")
	systems.advance(0.3)
	_expect(placements_blocked and systems.run_director.has_completed("first_new_life"), "First New Life counts a natural birth, not placed rabbits")

func _test_next_generation_requires_born_survivor_to_feed() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][2]["born_survival_age"] = 1.0
	var systems = Systems.new(config)
	_advance_to(systems, "next_generation")
	_ensure_rabbits(systems, 4)
	var placed_id: int = systems.simulation.rabbits.keys()[0]
	systems.run_director.record_creature_fed("rabbit", placed_id, -1)
	systems.advance(0.3)
	var placed_blocked: bool = systems.run_director.current_milestone_id() == "next_generation"
	var born_id: int = systems.simulation.add_rabbit(Vector2(60.0, 0.0), "birth")
	systems.run_director.record_creature_fed("rabbit", born_id, -1)
	systems.advance(0.3)
	var too_young_blocked: bool = systems.run_director.current_milestone_id() == "next_generation"
	systems.simulation.rabbits[born_id]["age"] = 1.1
	systems.advance(0.3)
	_expect(placed_blocked and too_young_blocked and systems.run_director.has_completed("next_generation"), "The Next Generation Takes Hold needs a born rabbit to survive and feed")

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
	_expect(chase_blocked and systems.run_director.has_completed("first_hunt"), "First Hunt requires the simulation's successful predation event, not a chase")

func _test_life_returns_requires_fresh_birth() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "life_returns")
	_ensure_rabbits(systems, 8)
	systems.advance(0.4)
	var placements_blocked: bool = systems.run_director.current_milestone_id() == "life_returns"
	systems.simulation.add_rabbit(Vector2(70.0, 0.0), "birth")
	systems.advance(0.3)
	_expect(placements_blocked and systems.run_director.has_completed("life_returns"), "Life Returns requires renewal after the hunt checkpoint")

func _test_two_safe_havens_are_spatial_and_stable() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][5]["stabilization"] = 0.5
	var systems = Systems.new(config)
	_advance_to(systems, "two_safe_havens")
	_ensure_rabbits(systems, 8)
	var ids: Array = systems.simulation.rabbits.keys()
	for index in range(ids.size()):
		var rabbit: Dictionary = systems.simulation.rabbits[ids[index]]
		rabbit["position"] = Vector2(-245.0 + float(index) * 70.0, 0.0)
		rabbit["previous_position"] = rabbit["position"]
	for x in [-210.0, -70.0, 70.0, 210.0]:
		systems.simulation.add_plant("berry_bush", Vector2(x, 0.0))
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
	_expect(stretched_rejected and transient_rejected and short_hold_rejected and systems.run_director.has_completed("two_safe_havens"), "Two Safe Havens rejects a stretched colony and transient split, then accepts two separated fed groups")

func _test_two_distinct_foxes_and_birth_are_required() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "predators_find_place")
	_ensure_rabbits(systems, 7)
	_ensure_foxes(systems, 2)
	var fox_ids: Array = systems.simulation.foxes.keys()
	for repeat in range(3):
		systems.simulation.creature_fed.emit("fox", fox_ids[0], -1)
	systems.simulation.add_rabbit(Vector2(80.0, 0.0), "birth")
	systems.advance(0.3)
	var one_fox_blocked: bool = systems.run_director.current_milestone_id() == "predators_find_place"
	systems.simulation.creature_fed.emit("fox", fox_ids[1], -1)
	systems.advance(0.3)
	_expect(one_fox_blocked and systems.run_director.has_completed("predators_find_place"), "Predators Find Their Place requires two distinct living foxes to feed plus rabbit renewal")

func _test_final_cycle_is_fresh_ordered_and_latched() -> void:
	var config := _fast_config()
	config["progression"]["milestones"][7]["stabilization"] = 0.6
	config["progression"]["milestones"][7]["evidence_window"] = 0.2
	var systems = Systems.new(config)
	_advance_to(systems, "predators_find_place")
	_ensure_rabbits(systems, 9)
	_ensure_foxes(systems, 2)
	var fox_id: int = systems.simulation.foxes.keys()[0]
	for event_type in ["birth", "hunt", "birth", "hunt"]:
		if event_type == "birth":
			systems.simulation.add_rabbit(Vector2(84.0, 0.0), "birth")
		else:
			systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	_satisfy_current_checkpoint(systems)
	var fresh_reset: bool = systems.run_director.current_milestone_id() == "living_ecosystem" and systems.run_director.sequence_progress == 0
	systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(88.0, 0.0), "birth")
	systems.advance(0.1)
	var wrong_order_blocked: bool = systems.run_director.sequence_progress == 1 and not systems.run_director.sequence_completed
	systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[0], Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(92.0, 0.0), "birth")
	systems.run_director.record_predation(fox_id, systems.simulation.rabbits.keys()[1], Vector2.ZERO)
	systems.advance(0.3)
	var latched_after_window: bool = systems.run_director.sequence_completed and systems.run_director.run_state == RunDirector.STATE_PLAYING
	systems.advance(0.4)
	_expect(fresh_reset and wrong_order_blocked and latched_after_window and systems.run_director.run_state == RunDirector.STATE_COMPLETED, "Living Ecosystem needs a fresh ordered cycle and latches it through the final hold")

func _test_reward_timing_and_persistent_expansions() -> void:
	var systems = Systems.new(_fast_config())
	var preserved_plant: int = systems.simulation.add_plant("carrot_patch", Vector2(120.0, 0.0))
	_advance_to(systems, "next_generation")
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
	_expect(first_major_ok and second_major_ok and third_major_ok and after == 795.0 and systems.simulation.world_radius == after and systems.simulation.plants.has(preserved_plant), "major rewards occur at checkpoints 3, 5, and 7 exactly once without resetting the world")

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

func _test_critical_is_armed_only_after_next_generation() -> void:
	var systems = Systems.new(_fast_config())
	_advance_to(systems, "next_generation")
	_kill_all_rabbits(systems)
	systems.advance(1.0)
	var safe_before: bool = systems.run_director.run_state == RunDirector.STATE_PLAYING and not systems.run_director.rabbit_failure_armed
	var second = Systems.new(_fast_config())
	_advance_to(second, "first_hunt")
	_expect(safe_before and second.run_director.rabbit_failure_armed, "Critical remains dormant until The Next Generation Takes Hold")

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

func _visible_label_texts(node: Node, result: Array[String]) -> void:
	if node is Label and node.is_visible_in_tree():
		result.append(str(node.text))
	for child in node.get_children():
		_visible_label_texts(child, result)

func _test_normal_ui_hides_internal_progression_mechanics() -> void:
	var systems = Systems.new(_fast_config())
	var hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)
	hud.refresh()
	var player_texts: Array[String] = [
		hud.objective_eyebrow.text,
		hud.objective_title.text,
		hud.objective_body.text,
		hud.objective_teaser.text,
		hud.objective_coach_detail.text,
	]
	var joined := "\n".join(player_texts).to_lower()
	var mechanics_hidden: bool = not hud.objective_requirements_heading.visible \
		and not hud.objective_evidence_row.visible \
		and not hud.objective_steps_box.visible \
		and not hud.objective_trend_row.visible \
		and not hud.objective_progress_row.visible
	var qualitative: bool = "checkpoint 1 of 8" in joined and "ecosystem is still fragile" in joined and "next ·" in joined
	var no_formulas: bool = " / " not in joined and "stability" not in joined and "evidence window" not in joined and "complete in order" not in joined
	_expect(mechanics_hidden and qualitative and no_formulas, "normal UI uses qualitative checkpoint guidance and hides evaluator mechanics", joined)
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
	hud._on_milestone_completed(0, "founders_forage", "Minor beat")
	var minor_compact: bool = hud.toast_label.text == "Minor beat" and hud.toast_label.theme_type_variation == "BodyLarge" and not hud.ending_overlay.visible
	hud._on_milestone_completed(2, "next_generation", "Major beat")
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
	_expect(fresh.run_director.run_state == RunDirector.STATE_PLAYING and fresh.run_director.current_milestone_id() == "founders_forage" and fresh.simulation.simulation_time == 0.0 and not fresh.run_director.is_unlocked("fox"), "a new ecosystem starts from clean V0.3 progression and simulation state")
