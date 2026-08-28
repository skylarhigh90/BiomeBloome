extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")

const RUN_DURATION := 800.0
const CHECKPOINT_ORDER := [
	"founders_forage",
	"first_new_life",
	"next_generation",
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
	if not requested.is_empty():
		var requested_result := _run_strategy(str(requested[0]), duration)
		print("\nSTRATEGY PLAYTEST · %s: %s" % [str(requested[0]).to_upper(), str(requested_result)])
		quit(0)
		return
	var dump := _run_strategy("dump", minf(duration, 360.0))
	var deliberate := _run_strategy("deliberate", duration)
	var overstock := _run_strategy("predator_overstock", minf(duration, 450.0))
	print("\nSTRATEGY PLAYTEST · DUMP EVERYTHING: %s" % str(dump))
	print("STRATEGY PLAYTEST · DELIBERATE TWO-REFUGE: %s" % str(deliberate))
	print("STRATEGY PLAYTEST · PREDATOR OVERSTOCK: %s" % str(overstock))
	if not bool(deliberate["completed"]):
		printerr("PLAYTEST FAILED: deliberate two-refuge play did not establish the ecosystem.")
		quit(1)
		return
	if float(deliberate["longest_checkpoint_wait"]) > 240.0:
		printerr("PLAYTEST FAILED: deliberate play encountered an excessive checkpoint wait.")
		quit(1)
		return
	if int(deliberate["natural_births"]) < 4 or int(deliberate["successful_hunts"]) < 4:
		printerr("PLAYTEST FAILED: completion did not arise from enough live ecological events.")
		quit(1)
		return
	print("Playtest passed: deliberate play completed through live births, feeding, hunts, spatial refuges, supplies, and all eight ID-tracked checkpoints.")
	print("Contrast strategies were also exercised through the same live simulation; their stopping checkpoint and ecological outcome are reported above.")
	quit(0)

func _run_strategy(strategy: String, duration: float) -> Dictionary:
	placement_serial = 0
	var systems = Systems.new(Config.make().duplicate(true))
	var checkpoint_times: Dictionary = {}
	var evidence_times: Dictionary = {}
	var evidence_streaks: Dictionary = {}
	var maximum_evidence_streaks: Dictionary = {}
	var events := {"natural_births": 0, "successful_hunts": 0, "starvation_losses": 0, "supplies_claimed": 0}
	var rabbit_low := 999999
	var rabbit_high := 0
	systems.milestone_completed.connect(func(_index: int, milestone_id: String, _message: String) -> void:
		checkpoint_times[milestone_id] = snappedf(systems.simulation.simulation_time, 0.1)
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
	var plant_target := 999 if strategy == "dump" else (16 if systems.run_director.has_completed("life_returns") else 8)
	var hunger: Dictionary = systems.simulation.hunger_summary("rabbit")
	if int(hunger.get("unserved_count", 0)) > 0:
		plant_target += 8
	while int(systems.inventory.get("carrot_patch", 0)) > 0 and systems.simulation.plants.size() < plant_target:
		if not _place_plant(systems, "carrot_patch", strategy):
			break
	while int(systems.inventory.get("berry_bush", 0)) > 0 and systems.simulation.plants.size() < plant_target:
		if not _place_plant(systems, "berry_bush", strategy):
			break
	var rabbit_limit := 999 if strategy == "dump" else 4
	if systems.run_director.has_completed("next_generation"):
		rabbit_limit = 10
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
		elif systems.run_director.has_completed("two_safe_havens") and systems.simulation.population("rabbit") >= 12:
			desired_foxes = 2
		elif systems.simulation.population("rabbit") >= 10:
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
		var position := _refuge_position(systems, strategy, "plant")
		placement_serial += 1
		if systems.place_item(kind, position) != -1:
			return true
	return false

func _refuge_position(systems, strategy: String, kind: String) -> Vector2:
	if strategy == "dump":
		var dump_radius := 12.0 + float(placement_serial % 5) * 9.0
		return Vector2.from_angle(float(placement_serial) * 2.399) * dump_radius
	var side := -1.0 if placement_serial % 2 == 0 else 1.0
	var center := Vector2(side * 220.0, 0.0)
	var radius := 8.0 + float((placement_serial / 2) % 5) * (13.0 if kind == "plant" else 7.0)
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
		center = Vector2(side * 150.0, 80.0)
		radius = 28.0
	var candidate := center + Vector2.from_angle(angle) * radius
	if systems.simulation.is_position_valid(candidate):
		return candidate
	return center * 0.86

func _choose_supply(systems, strategy: String) -> int:
	var best_index := 0
	var best_score := -INF
	for index in range(systems.supply_choices.size()):
		var items: Dictionary = systems.supply_choices[index]["items"]
		var score := float(items.get("carrot_patch", 0)) * 1.5 + float(items.get("berry_bush", 0)) * 2.0
		if int(systems.simulation.hunger_summary("rabbit").get("unserved_count", 0)) > 0:
			score += float(items.get("carrot_patch", 0)) * 3.0 + float(items.get("berry_bush", 0)) * 4.0
		if systems.simulation.population("rabbit") < 12:
			score += float(items.get("rabbit", 0)) * 3.0
		else:
			score += float(items.get("rabbit", 0)) * 0.4
		if strategy == "predator_overstock":
			score += float(items.get("fox", 0)) * 9.0
		elif systems.run_director.is_unlocked("fox") and systems.simulation.population("fox") < 2:
			score += float(items.get("fox", 0)) * 8.0
		if score > best_score:
			best_score = score
			best_index = index
	return best_index
