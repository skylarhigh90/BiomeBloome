extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")

const RUN_DURATION := 800.0
const REACTIVE_OPENING_CENTERS := [
	Vector2.ZERO,
	Vector2(-290.0, -170.0),
	Vector2(290.0, -170.0),
]
const CHECKPOINT_ORDER := [
	"colony_gathers",
	"new_arrivals",
	"young_foragers",
	"birthplaces",
	"nursery_network",
	"first_hunt",
	"life_returns",
	"two_safe_havens",
	"predators_find_place",
	"living_ecosystem",
]

var placement_serial := 0

func _initialize() -> void:
	var requested := OS.get_cmdline_user_args()
	var duration := RUN_DURATION
	if requested.size() > 1:
		duration = float(requested[1])
	var social_radius := -1.0
	if requested.size() > 2:
		social_radius = float(requested[2])
	var population_cap := -1
	if requested.size() > 3:
		population_cap = int(requested[3])
	if not requested.is_empty():
		var requested_result := _run_strategy(str(requested[0]), duration, social_radius, population_cap)
		var radius_label := "default" if social_radius < 0.0 else "social radius %.0f" % social_radius
		var cap_label := "default cap" if population_cap < 0 else "cap %d" % population_cap
		print("\nSTRATEGY PLAYTEST · %s · %s · %s: %s" % [str(requested[0]).to_upper(), radius_label, cap_label, str(requested_result)])
		quit(0)
		return
	var dump := _run_strategy("dump", minf(duration, 360.0))
	var deliberate := _run_strategy("deliberate", duration)
	var overstock := _run_strategy("predator_overstock", minf(duration, 700.0))
	print("\nSTRATEGY PLAYTEST · DUMP EVERYTHING: %s" % str(dump))
	print("STRATEGY PLAYTEST · DELIBERATE NURSERY-NETWORK: %s" % str(deliberate))
	print("STRATEGY PLAYTEST · PREDATOR OVERSTOCK: %s" % str(overstock))
	if bool(dump["completed"]) or str(dump["stopped_at"]) != "birthplaces":
		printerr("PLAYTEST FAILED: dense central placement bypassed the separated-birthplace checkpoint.")
		quit(1)
		return
	var deliberate_rank := CHECKPOINT_ORDER.size() if bool(deliberate["completed"]) else CHECKPOINT_ORDER.find(str(deliberate["stopped_at"]))
	if deliberate_rank < CHECKPOINT_ORDER.find("two_safe_havens") or str(deliberate["state"]) == RunDirector.STATE_GAME_OVER:
		printerr("PLAYTEST FAILED: deliberate nursery-network play did not reach the compound nursery challenge in a recoverable state.")
		quit(1)
		return
	if bool(deliberate["completed"]) and float(deliberate["simulation_time"]) < 500.0:
		printerr("PLAYTEST FAILED: the redesigned run completed too quickly to provide the intended challenge.")
		quit(1)
		return
	if int(deliberate["natural_births"]) < 4 or int(deliberate["successful_hunts"]) < 4:
		printerr("PLAYTEST FAILED: completion did not arise from enough live ecological events.")
		quit(1)
		return
	print("Playtest passed: deliberate play reached the hard compound nursery arc through live births, feeding, hunts, spatial evidence, and supplies without an automatic quick completion.")
	print("Full checkpoint reachability is covered by progression_runner; contrast strategies report their stopping checkpoint and ecological outcome above.")
	quit(0)

func _run_strategy(strategy: String, duration: float, social_radius: float = -1.0, population_cap: int = -1) -> Dictionary:
	placement_serial = 0
	var playtest_config := Config.make().duplicate(true)
	if social_radius >= 0.0:
		playtest_config["rabbit"]["social_proximity_radius"] = social_radius
	# Keep long strategy comparisons computationally bounded. Incremental world
	# reveals give rabbits more room to roam, so deliberate play receives enough
	# headroom to reinforce all three nurseries; dense dumping remains capped more
	# tightly, while the reactive opening may use a modest additional reserve.
	var default_population_cap := 16 if strategy == "dump" else (24 if strategy == "reactive" else 20)
	playtest_config["rabbit"]["max_population"] = population_cap if population_cap > 0 else default_population_cap
	playtest_config["fox"]["max_population"] = 10
	var systems = Systems.new(playtest_config)
	var checkpoint_times: Dictionary = {}
	var checkpoint_populations: Dictionary = {}
	var evidence_times: Dictionary = {}
	var evidence_streaks: Dictionary = {}
	var maximum_evidence_streaks: Dictionary = {}
	var events := {"natural_births": 0, "successful_hunts": 0, "starvation_losses": 0, "supplies_claimed": 0}
	var rabbit_low := 999999
	var rabbit_high := 0
	systems.milestone_completed.connect(func(_index: int, milestone_id: String, _message: String) -> void:
		checkpoint_times[milestone_id] = snappedf(systems.simulation.simulation_time, 0.1)
		checkpoint_populations[milestone_id] = systems.simulation.population("rabbit")
	)
	systems.simulation.entity_added.connect(func(kind: String, _entity_id: int, reason: String) -> void:
		if kind == "rabbit" and reason == "birth":
			events["natural_births"] += 1
	)
	systems.simulation.predation_succeeded.connect(func(_fox_id: int, _rabbit_id: int, _position: Vector2) -> void:
		events["successful_hunts"] += 1
	)
	systems.simulation.entity_removed.connect(func(kind: String, _entity_id: int, _position: Vector2, cause: String) -> void:
		if kind == "rabbit" and cause == "starvation":
			events["starvation_losses"] += 1
	)
	systems.supply_claimed.connect(func(_bundle: Dictionary) -> void:
		events["supplies_claimed"] += 1
	)
	_place_inventory(systems, strategy)
	var ticks := ceili(duration / 0.1)
	for tick in range(ticks):
		if systems.supply_pending:
			systems.choose_supply(_choose_supply(systems, strategy))
		if tick % 10 == 0:
			_place_inventory(systems, strategy)
		systems.advance(0.1)
		var current_id: String = systems.run_director.current_milestone_id()
		if not current_id.is_empty() and not evidence_times.has(current_id):
			var progress: Dictionary = systems.current_objective_progress()
			if not progress.is_empty() and bool(progress["evidence_met"]):
				evidence_times[current_id] = snappedf(systems.simulation.simulation_time, 0.1)
		if not current_id.is_empty():
			var progress: Dictionary = systems.current_objective_progress()
			if not progress.is_empty() and bool(progress["evidence_met"]):
				evidence_streaks[current_id] = float(evidence_streaks.get(current_id, 0.0)) + 0.1
				maximum_evidence_streaks[current_id] = maxf(float(maximum_evidence_streaks.get(current_id, 0.0)), float(evidence_streaks[current_id]))
			else:
				evidence_streaks[current_id] = 0.0
		var rabbits: int = systems.simulation.population("rabbit")
		rabbit_low = mini(rabbit_low, rabbits)
		rabbit_high = maxi(rabbit_high, rabbits)
		if systems.is_completed() or systems.is_game_over():
			break
	var completed := systems.is_completed()
	var completion_time: float = systems.simulation.simulation_time
	var sandbox_continued := false
	if completed:
		sandbox_continued = systems.continue_observing()
		var before: float = systems.simulation.simulation_time
		systems.advance(0.5)
		sandbox_continued = sandbox_continued and systems.simulation.simulation_time > before
	var waits: Dictionary = {}
	var previous_time := 0.0
	var longest_wait := 0.0
	for milestone_id in CHECKPOINT_ORDER:
		if not checkpoint_times.has(milestone_id):
			break
		var checkpoint_time: float = checkpoint_times[milestone_id]
		var wait := checkpoint_time - previous_time
		waits[milestone_id] = snappedf(wait, 0.1)
		longest_wait = maxf(longest_wait, wait)
		previous_time = checkpoint_time
	var spatial: Dictionary = systems.run_director.spatial_evidence(systems.simulation)
	var current_progress: Dictionary = systems.current_objective_progress()
	return {
		"completed": completed,
		"state": systems.run_director.run_state,
		"stopped_at": "complete" if completed else systems.run_director.current_milestone_id(),
		"simulation_time": snappedf(completion_time, 0.1),
		"checkpoint_times": checkpoint_times,
		"checkpoint_populations": checkpoint_populations,
		"evidence_times": evidence_times,
		"maximum_evidence_streaks": maximum_evidence_streaks,
		"checkpoint_waits": waits,
		"longest_checkpoint_wait": snappedf(longest_wait, 0.1),
		"rabbits": systems.simulation.population("rabbit"),
		"foxes": systems.simulation.population("fox"),
		"rabbit_low": rabbit_low,
		"rabbit_high": rabbit_high,
		"natural_births": events["natural_births"],
		"successful_hunts": events["successful_hunts"],
		"starvation_losses": events["starvation_losses"],
		"supplies_claimed": events["supplies_claimed"],
		"rabbit_hunger": systems.simulation.hunger_summary("rabbit"),
		"separated_havens_now": int(spatial["separated_group_count"]),
		"current_progress": current_progress,
		"sandbox_continued": sandbox_continued,
	}

func _place_inventory(systems, strategy: String) -> void:
	var rabbit_population: int = systems.simulation.population("rabbit")
	var plant_target := 999 if strategy == "dump" else (16 if systems.run_director.has_completed("life_returns") else 10)
	if strategy != "dump":
		plant_target = maxi(plant_target, ceili(float(rabbit_population) * 0.9))
	# A checkpoint-reactive player follows the compact opening instructions and
	# saves most of the starting forage until separate birthplaces are requested.
	if strategy == "reactive" and systems.run_director.milestone_index < 3:
		plant_target = 4
	var hunger: Dictionary = systems.simulation.hunger_summary("rabbit")
	if int(hunger.get("unserved_count", 0)) > 0:
		plant_target += 12
	if strategy != "dump":
		plant_target = mini(32 if rabbit_population < 8 else 24, plant_target)
	while int(systems.inventory.get("carrot_patch", 0)) > 0 and systems.simulation.plants.size() < plant_target:
		if not _place_plant(systems, "carrot_patch", strategy):
			break
	while int(systems.inventory.get("berry_bush", 0)) > 0 and systems.simulation.plants.size() < plant_target:
		if not _place_plant(systems, "berry_bush", strategy):
			break
	var rabbit_limit := 999 if strategy == "dump" else 6
	if strategy == "reactive":
		rabbit_limit = 4 if systems.run_director.milestone_index < 3 else 16
	if systems.run_director.has_completed("nursery_network"):
		rabbit_limit = 12
	if systems.run_director.has_completed("two_safe_havens"):
		rabbit_limit = 16
	if systems.is_critical():
		rabbit_limit = maxi(rabbit_limit, 10)
	while int(systems.inventory.get("rabbit", 0)) > 0 and systems.simulation.population("rabbit") < rabbit_limit:
		var position := _refuge_position(systems, strategy, "rabbit")
		if systems.place_item("rabbit", position) == -1:
			placement_serial += 1
			if placement_serial > 5000:
				break
			continue
		placement_serial += 1
	var desired_foxes := 0
	if systems.run_director.is_unlocked("fox"):
		if strategy == "predator_overstock":
			desired_foxes = 99
		elif systems.run_director.has_completed("two_safe_havens") and systems.simulation.population("rabbit") >= 16:
			desired_foxes = 2
		elif systems.simulation.population("rabbit") >= 12:
			desired_foxes = 1
	while int(systems.inventory.get("fox", 0)) > 0 and systems.simulation.population("fox") < desired_foxes:
		var position := _refuge_position(systems, strategy, "fox")
		if systems.place_item("fox", position) == -1:
			placement_serial += 1
			if placement_serial > 5000:
				break
			continue
		placement_serial += 1

func _place_plant(systems, kind: String, strategy: String) -> bool:
	for _attempt in range(50):
		var position := _best_plant_position(systems, kind, strategy)
		placement_serial += 1
		if systems.place_item(kind, position) != -1:
			return true
	return false

func _best_plant_position(systems, plant_type: String, strategy: String) -> Vector2:
	if strategy == "dump":
		return _refuge_position(systems, strategy, "plant")
	var refuge_centers := _strategy_refuge_centers(systems)
	var anchor: Vector2 = refuge_centers[placement_serial % refuge_centers.size()]
	if strategy == "reactive" and not systems.run_director.has_completed("nursery_network"):
		anchor = Vector2.ZERO if systems.run_director.milestone_index < 3 else _least_supported_reactive_center(systems, "plant")
	elif systems.simulation.population("rabbit") < 8:
		var neediest: Dictionary = {}
		for rabbit in systems.simulation.rabbits.values():
			if float(rabbit["hunger"]) >= float(systems.config["rabbit"]["hunger_warning_at"]) \
				and (neediest.is_empty() or float(rabbit["hunger"]) > float(neediest["hunger"])):
				neediest = rabbit
		if not neediest.is_empty():
			anchor = neediest["position"]
	var best := Vector2.INF
	var best_score := -INF
	for ring in range(5):
		var radius := 12.0 + float(ring) * 22.0
		for spoke in range(16):
			var angle := float(spoke) / 16.0 * TAU + float(placement_serial) * 0.37
			var candidate := anchor + Vector2.from_angle(angle) * radius
			if not systems.simulation.is_position_valid(candidate):
				continue
			var crowded := false
			for plant in systems.simulation.plants.values():
				if candidate.distance_to(plant["position"]) < 18.0:
					crowded = true
					break
			if crowded:
				continue
			var score: float = systems.simulation.terrain.food_capacity_factor(plant_type, candidate) \
				- candidate.distance_to(anchor) * 0.0008
			if score > best_score:
				best_score = score
				best = candidate
	return best if best != Vector2.INF else anchor

func _refuge_position(systems, strategy: String, kind: String) -> Vector2:
	if strategy == "dump":
		var dump_radius := 12.0 + float(placement_serial % 5) * 9.0
		return Vector2.from_angle(float(placement_serial) * 2.399) * dump_radius
	if strategy == "reactive" and not systems.run_director.has_completed("nursery_network"):
		var reactive_center := Vector2.ZERO if systems.run_director.milestone_index < 3 else _least_supported_reactive_center(systems, kind)
		var reactive_radius := 9.0 + float(placement_serial % 4) * 8.0
		var reactive_candidate := reactive_center + Vector2.from_angle(float(placement_serial) * 2.399) * reactive_radius
		if systems.simulation.is_position_valid(reactive_candidate):
			return reactive_candidate
		return reactive_center * 0.9
	var refuge_centers := _strategy_refuge_centers(systems)
	var center: Vector2 = refuge_centers[placement_serial % refuge_centers.size()]
	var radius := 8.0 + float((placement_serial / refuge_centers.size()) % 5) * (13.0 if kind == "plant" else 7.0)
	var angle := float(placement_serial) * 2.399
	if kind == "plant":
		var neediest: Dictionary = {}
		for rabbit in systems.simulation.rabbits.values():
			if float(rabbit["hunger"]) >= float(systems.config["rabbit"]["hunger_warning_at"]) and (neediest.is_empty() or float(rabbit["hunger"]) > float(neediest["hunger"])):
				neediest = rabbit
		if not neediest.is_empty():
			var assistance: Vector2 = neediest["position"] + Vector2.from_angle(angle) * 20.0
			if systems.simulation.is_position_valid(assistance):
				return assistance
	if kind == "fox":
		if not systems.simulation.rabbits.is_empty():
			var rabbit_ids: Array = systems.simulation.rabbits.keys()
			var nearby_rabbit: Dictionary = systems.simulation.rabbits[rabbit_ids[placement_serial % rabbit_ids.size()]]
			return nearby_rabbit["position"] + Vector2.from_angle(angle) * 36.0
		center = center * 0.68 + Vector2(0.0, 80.0)
		radius = 28.0
	var candidate := center + Vector2.from_angle(angle) * radius
	if systems.simulation.is_position_valid(candidate):
		return candidate
	return center * 0.86

func _strategy_refuge_centers(_systems) -> Array[Vector2]:
	return [Vector2(-230.0, -140.0), Vector2(230.0, -140.0), Vector2(240.0, 180.0)]

func _least_supported_reactive_center(systems, kind: String) -> Vector2:
	var best_center: Vector2 = REACTIVE_OPENING_CENTERS[0]
	var best_count := 999999
	for configured_center in REACTIVE_OPENING_CENTERS:
		var center: Vector2 = configured_center
		var count := 0
		var entities: Array = systems.simulation.plants.values() if kind == "plant" else systems.simulation.rabbits.values()
		for entity in entities:
			if center.distance_to(entity["position"]) <= 150.0:
				count += 1
		if count < best_count:
			best_count = count
			best_center = center
	return best_center

func _choose_supply(systems, strategy: String) -> int:
	var best_index := 0
	var best_score := -INF
	for index in range(systems.supply_choices.size()):
		var items: Dictionary = systems.supply_choices[index]["items"]
		var score := float(items.get("carrot_patch", 0)) * 1.5 + float(items.get("berry_bush", 0)) * 2.0
		if int(systems.simulation.hunger_summary("rabbit").get("unserved_count", 0)) > 0:
			score += float(items.get("carrot_patch", 0)) * 3.0 + float(items.get("berry_bush", 0)) * 4.0
		var rabbit_reserve_target := 18 if systems.run_director.has_completed("two_safe_havens") else 12
		if systems.simulation.population("rabbit") < rabbit_reserve_target:
			var rabbit_urgency := 10.0 if systems.simulation.population("rabbit") < 8 else 5.0
			score += float(items.get("rabbit", 0)) * rabbit_urgency
		else:
			score += float(items.get("rabbit", 0)) * 0.4
		if strategy == "predator_overstock":
			score += float(items.get("fox", 0)) * 9.0
		elif systems.run_director.is_unlocked("fox") and systems.simulation.population("fox") < 2 and int(systems.inventory.get("fox", 0)) == 0:
			score += float(items.get("fox", 0)) * 8.0
		if score > best_score:
			best_score = score
			best_index = index
	return best_index
