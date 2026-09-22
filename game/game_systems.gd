class_name GameSystems
extends RefCounted

signal inventory_changed
signal unlocks_changed
signal supply_ready(choices: Array)
signal supply_claimed(bundle: Dictionary)
signal milestone_completed(index: int, milestone_id: String, message: String)
signal world_expanded(new_radius: float)
signal run_state_changed(previous_state: String, new_state: String)
signal critical_started
signal critical_recovered
signal run_failed(recap: String)
signal run_completed
signal ecology_story_added(story: Dictionary)
signal undo_state_changed
signal tool_state_changed
signal placement_succeeded(item: String, entity_id: int, position: Vector2)
signal transplant_succeeded(plant_id: int, item: String, position: Vector2)

var config: Dictionary
var simulation: EcosystemSimulation
var run_director: RunDirector
var inventory: Dictionary
var selected_item := ""
var simulation_speed := 1.0
var accumulator := 0.0
var supply_time_remaining: float
var supply_choices: Array = []
var supply_pending := false
var supply_resume_speed := 1.0
var forced_recovery_supply := false
var rng := RandomNumberGenerator.new()
var real_time := 0.0
var last_placement: Dictionary = {}
var transplant_charges := 0
var remove_food_mode := false
var transplant_mode := false
var transplant_source_id := -1
var ecology_stories: Array[Dictionary] = []
var latest_loss: Dictionary = {}
var _life_warning_state: Dictionary = {}
var _life_sample_remaining := 0.0
var _family_watch: Dictionary = {}
var _family_watch_time := -INF
var life_revision := 0

func _init(p_config: Dictionary = {}) -> void:
	config = p_config if not p_config.is_empty() else GameConfig.make()
	simulation = EcosystemSimulation.new(config)
	run_director = RunDirector.new(config)
	inventory = config["inventory"].duplicate(true)
	supply_time_remaining = float(config["supply"]["interval"])
	rng.seed = int(config["simulation"]["seed"]) + 12003
	simulation.entity_added.connect(_on_simulation_entity_added)
	simulation.entity_removed.connect(run_director.record_entity_removed)
	simulation.entity_removed.connect(_on_simulation_entity_removed)
	simulation.plant_transplanted.connect(func(_id: int, _before: Vector2, _after: Vector2) -> void: _invalidate_life_readout())
	simulation.creature_fed.connect(run_director.record_creature_fed)
	simulation.predation_succeeded.connect(run_director.record_predation)
	simulation.animal_story.connect(_on_animal_story)
	simulation.animal_died.connect(_on_animal_died)
	run_director.milestone_completed.connect(_on_director_milestone_completed)
	run_director.unlock_changed.connect(_on_director_unlock_changed)
	run_director.state_changed.connect(_on_director_state_changed)
	run_director.critical_started.connect(_on_director_critical_started)
	run_director.critical_recovered.connect(_on_director_critical_recovered)
	run_director.first_recovery_supply_requested.connect(_on_first_recovery_supply_requested)
	run_director.run_failed.connect(_on_director_run_failed)
	run_director.run_completed.connect(_on_director_run_completed)

func _on_simulation_entity_added(kind: String, entity_id: int, reason: String) -> void:
	_invalidate_life_readout()
	var position := Vector2.INF
	if kind == "rabbit" and simulation.rabbits.has(entity_id):
		position = simulation.rabbits[entity_id]["position"]
	run_director.record_entity_added(kind, entity_id, reason, position)

func _on_simulation_entity_removed(kind: String, entity_id: int, _position: Vector2, _cause: String) -> void:
	_invalidate_life_readout()
	_life_warning_state.erase("%s:%d" % [kind, entity_id])

func _invalidate_life_readout() -> void:
	_family_watch_time = -INF
	life_revision += 1

func set_speed(speed: float) -> void:
	if supply_pending and speed > 0.0:
		return
	if speed in [0.0, 1.0, 2.0, 3.0] and run_director.run_state not in [RunDirector.STATE_GAME_OVER, RunDirector.STATE_COMPLETED]:
		simulation_speed = speed

func is_paused() -> bool:
	return simulation_speed == 0.0

func is_critical() -> bool:
	return run_director.run_state == RunDirector.STATE_CRITICAL

func is_game_over() -> bool:
	return run_director.run_state == RunDirector.STATE_GAME_OVER

func is_completed() -> bool:
	return run_director.run_state == RunDirector.STATE_COMPLETED

func advance(real_delta: float) -> int:
	if real_delta > 0.0:
		real_time += real_delta
		if not last_placement.is_empty() and not can_undo_last_placement():
			last_placement.clear()
			undo_state_changed.emit()
	if simulation_speed <= 0.0 or real_delta <= 0.0:
		return 0
	var fixed_step: float = config["simulation"]["fixed_step"]
	accumulator += real_delta * simulation_speed
	var completed_steps := 0
	var maximum_steps: int = config["simulation"]["max_steps_per_frame"]
	while accumulator + 0.000001 >= fixed_step and completed_steps < maximum_steps:
		accumulator -= fixed_step
		_tick_systems(fixed_step)
		completed_steps += 1
		if simulation_speed <= 0.0:
			accumulator = 0.0
			break
	if completed_steps >= maximum_steps:
		accumulator = minf(accumulator, fixed_step)
	return completed_steps

func _tick_systems(delta: float) -> void:
	simulation.step(delta)
	_life_sample_remaining -= delta
	if _life_sample_remaining <= 0.0:
		_life_sample_remaining = 0.5
		_update_life_warnings()
	_update_supply(delta)
	run_director.tick(delta, simulation, inventory, supply_choices, supply_pending)

func can_place(item: String, position: Vector2) -> bool:
	if supply_pending:
		return false
	if not run_director.is_unlocked(item):
		return false
	if not inventory.has(item) or int(inventory[item]) <= 0:
		return false
	if not simulation.is_position_valid(position):
		return false
	if item in ["carrot_patch", "berry_bush"]:
		for plant in simulation.plants.values():
			if position.distance_to(plant["position"]) < 15.0:
				return false
	return item in ["rabbit", "fox", "carrot_patch", "berry_bush"]

func place_item(item: String, position: Vector2) -> int:
	if not can_place(item, position):
		return -1
	var entity_id := -1
	match item:
		"rabbit":
			entity_id = simulation.add_rabbit(position)
		"fox":
			entity_id = simulation.add_fox(position)
		"carrot_patch", "berry_bush":
			entity_id = simulation.add_plant(item, position)
	if entity_id == -1:
		return -1
	inventory[item] = int(inventory[item]) - 1
	if int(inventory[item]) <= 0 and selected_item == item:
		selected_item = ""
	last_placement = {
		"item": item,
		"entity_id": entity_id,
		"expires_at": real_time + float(config.get("tools", {}).get("undo_seconds", 5.0)),
	}
	inventory_changed.emit()
	undo_state_changed.emit()
	placement_succeeded.emit(item, entity_id, position)
	return entity_id

func can_undo_last_placement() -> bool:
	if last_placement.is_empty() or real_time > float(last_placement.get("expires_at", -1.0)):
		return false
	var item := str(last_placement.get("item", ""))
	var entity_id := int(last_placement.get("entity_id", -1))
	if item == "rabbit":
		return simulation.rabbits.has(entity_id)
	if item == "fox":
		return simulation.foxes.has(entity_id)
	return simulation.plants.has(entity_id)

func undo_last_placement() -> bool:
	if not can_undo_last_placement():
		last_placement.clear()
		undo_state_changed.emit()
		return false
	var item := str(last_placement["item"])
	var entity_id := int(last_placement["entity_id"])
	var removed := false
	if item == "rabbit":
		removed = simulation.kill_rabbit(entity_id, "undo")
	elif item == "fox":
		removed = simulation.kill_fox(entity_id, "undo")
	else:
		removed = simulation.remove_plant(entity_id, "undo")
	if removed:
		inventory[item] = int(inventory.get(item, 0)) + 1
		_add_story("undo", "Placement undone · %s returned to the satchel" % _item_label(item), item, entity_id, Vector2.INF)
	last_placement.clear()
	inventory_changed.emit()
	undo_state_changed.emit()
	return removed

func begin_remove_food() -> bool:
	if supply_pending or is_game_over() or is_completed() or simulation.plants.is_empty():
		return false
	cancel_transplant()
	selected_item = ""
	remove_food_mode = true
	inventory_changed.emit()
	tool_state_changed.emit()
	return true

func cancel_remove_food() -> void:
	if not remove_food_mode:
		return
	remove_food_mode = false
	tool_state_changed.emit()

func remove_food(plant_id: int) -> bool:
	if not remove_food_mode or supply_pending or is_game_over() or is_completed():
		return false
	if not simulation.plants.has(plant_id):
		return false
	var plant: Dictionary = simulation.plants[plant_id]
	if not simulation.remove_plant(plant_id, "discard"):
		return false
	if int(last_placement.get("entity_id", -1)) == plant_id:
		last_placement.clear()
		undo_state_changed.emit()
	cancel_remove_food()
	_add_story("discard", "%s removed · no refund" % _item_label(str(plant["type"])), str(plant["type"]), plant_id, plant["position"])
	return true

func begin_transplant() -> bool:
	if supply_pending or transplant_charges <= 0 or not run_director.is_unlocked("transplant"):
		return false
	cancel_remove_food()
	selected_item = ""
	transplant_mode = true
	transplant_source_id = -1
	inventory_changed.emit()
	tool_state_changed.emit()
	return true

func cancel_transplant() -> void:
	if not transplant_mode:
		return
	transplant_mode = false
	transplant_source_id = -1
	tool_state_changed.emit()

func choose_transplant_source(plant_id: int) -> bool:
	if not transplant_mode or not simulation.plants.has(plant_id):
		return false
	transplant_source_id = plant_id
	tool_state_changed.emit()
	return true

func complete_transplant(position: Vector2) -> bool:
	if not transplant_mode or transplant_source_id == -1 or transplant_charges <= 0:
		return false
	if not simulation.can_transplant_plant(transplant_source_id, position):
		return false
	var plant_id := transplant_source_id
	var item := str(simulation.plants[plant_id]["type"])
	var retained := float(config.get("tools", {}).get("transplant_retained_biomass", 0.65))
	if not simulation.transplant_plant(plant_id, position, retained):
		return false
	transplant_charges -= 1
	transplant_mode = false
	transplant_source_id = -1
	_add_story("transplant", "%s moved to a new habitat" % _item_label(item), item, plant_id, position)
	tool_state_changed.emit()
	transplant_succeeded.emit(plant_id, item, position)
	return true

func placement_assessment(item: String, position: Vector2, excluded_plant_id: int = -1) -> Dictionary:
	if item.is_empty():
		return {}
	var valid := simulation.is_position_valid(position)
	if valid and item in ["carrot_patch", "berry_bush"]:
		for plant_id in simulation.plants:
			if int(plant_id) == excluded_plant_id:
				continue
			if position.distance_to(simulation.plants[plant_id]["position"]) < 15.0:
				valid = false
				break
	if not valid:
		return {"valid": false, "quality": "invalid", "title": "Cannot place here", "detail": "Choose revealed dry ground with enough space."}
	if item in ["carrot_patch", "berry_bush"]:
		var factor := simulation.terrain.food_capacity_factor(item, position)
		var quality := "rich" if factor >= 1.05 else ("fair" if factor >= 0.78 else "poor")
		var habitat_copy := "Open Meadow gives Carrots their best recovery." if item == "carrot_patch" else "Woodland and Thicket margins give Berries their best recovery."
		return {"valid": true, "quality": quality, "title": "%s habitat" % quality.capitalize(), "detail": "%s This site supports %d%% of standard capacity." % [habitat_copy, roundi(factor * 100.0)], "score": factor}
	if item == "rabbit":
		var food_count := 0
		for plant in simulation.plants.values():
			if simulation.plant_is_food_available(plant) and simulation.ground_route_distance(position, plant["position"], float(config["rabbit"]["food_detection_radius"])) <= float(config["rabbit"]["food_detection_radius"]):
				food_count += 1
		var quality := "rich" if food_count >= 2 else ("fair" if food_count == 1 else "poor")
		var companions := 0
		var nursery_radius := minf(float(config["rabbit"]["food_detection_radius"]) * 0.75, float(config["rabbit"]["mating_radius"]) * 1.65)
		for rabbit in simulation.rabbits.values():
			if position.distance_to(rabbit["position"]) <= nursery_radius and simulation.ground_route_distance(position, rabbit["position"], nursery_radius) <= nursery_radius:
				companions += 1
		var company := "%d nearby rabbits · a nursery needs 3 together." % companions
		if companions == 0:
			company = "No companions yet · place 3 together to start a nursery."
		elif companions < 3:
			company = "%d nearby · add %d to make a group of 3." % [companions, 3 - companions]
		return {"valid": true, "quality": quality, "title": "%s rabbit start" % quality.capitalize(), "detail": "%d forage patches. %s" % [food_count, company], "nearby_rabbits": companions}
	var reachable_prey := 0
	for rabbit in simulation.rabbits.values():
		if simulation.ground_route_distance(position, rabbit["position"], float(config["fox"]["prey_detection_radius"])) <= float(config["fox"]["prey_detection_radius"]):
			reachable_prey += 1
	var projected_foxes := simulation.population("fox") + 1
	var prey_ratio := float(simulation.population("rabbit")) / float(maxi(1, projected_foxes))
	var woodland := simulation.terrain.woodland_cover(position)
	var quality := "rich" if reachable_prey >= 4 and prey_ratio >= 6.0 and woodland >= 0.25 else ("fair" if reachable_prey >= 2 and prey_ratio >= 5.0 else "poor")
	return {"valid": true, "quality": quality, "title": "%s fox territory" % quality.capitalize(), "detail": "%d reachable rabbits · %.1f rabbits per fox after placement." % [reachable_prey, prey_ratio]}

func select_item(item: String) -> bool:
	if supply_pending:
		return false
	cancel_remove_food()
	if run_director.is_unlocked(item) and inventory.has(item) and int(inventory[item]) > 0:
		selected_item = item
		inventory_changed.emit()
		return true
	selected_item = ""
	inventory_changed.emit()
	return false

func clear_selection() -> void:
	cancel_remove_food()
	selected_item = ""
	cancel_transplant()
	inventory_changed.emit()

func _update_supply(delta: float) -> void:
	if supply_pending:
		return
	supply_time_remaining = maxf(0.0, supply_time_remaining - delta)
	if supply_time_remaining <= 0.0:
		_make_supply_choices()
		if supply_choices.is_empty():
			supply_time_remaining = float(config["supply"]["interval"])
			return
		supply_resume_speed = simulation_speed
		simulation_speed = 0.0
		accumulator = 0.0
		supply_pending = true
		supply_ready.emit(supply_choices)

func available_supply_bundles() -> Array:
	var pools: Dictionary = config["supply"]["pools"]
	var source: Array = pools.get(run_director.supply_pool, [])
	var available: Array = []
	for bundle in source:
		var allowed := true
		for item in bundle["items"]:
			if not run_director.is_unlocked(item):
				allowed = false
				break
		if allowed:
			available.append(bundle)
	return available

func _make_supply_choices() -> void:
	var bundles := available_supply_bundles()
	if bundles.is_empty():
		supply_choices = []
		return
	if forced_recovery_supply:
		var recovery: Dictionary = config["supply"]["first_collapse_bundle"].duplicate(true)
		var other: Dictionary = bundles[rng.randi_range(0, bundles.size() - 1)].duplicate(true)
		supply_choices = [recovery, other]
		if rng.randf() < 0.5:
			supply_choices.reverse()
		_ensure_required_fox_choice(bundles)
		forced_recovery_supply = false
		return
	if bundles.size() == 1:
		supply_choices = [bundles[0].duplicate(true)]
		_ensure_required_fox_choice(bundles)
		return
	var first_index := rng.randi_range(0, bundles.size() - 1)
	var second_index := rng.randi_range(0, bundles.size() - 2)
	if second_index >= first_index:
		second_index += 1
	supply_choices = [bundles[first_index].duplicate(true), bundles[second_index].duplicate(true)]
	_ensure_required_fox_choice(bundles)

func _ensure_required_fox_choice(available: Array) -> void:
	if is_critical() or not run_director.is_unlocked("fox") or simulation.population("fox") >= 2 or int(inventory.get("fox", 0)) > 0:
		return
	for choice in supply_choices:
		if int(choice.get("items", {}).get("fox", 0)) > 0:
			return
	for bundle in available:
		if int(bundle.get("items", {}).get("fox", 0)) > 0:
			if supply_choices.is_empty():
				supply_choices.append(bundle.duplicate(true))
			else:
				supply_choices[supply_choices.size() - 1] = bundle.duplicate(true)
			return

func choose_supply(choice_index: int) -> bool:
	if not supply_pending or choice_index < 0 or choice_index >= supply_choices.size():
		return false
	var bundle: Dictionary = supply_choices[choice_index]
	add_inventory(bundle["items"])
	supply_pending = false
	supply_time_remaining = float(config["supply"]["interval"])
	supply_choices = []
	if run_director.run_state not in [RunDirector.STATE_GAME_OVER, RunDirector.STATE_COMPLETED]:
		simulation_speed = supply_resume_speed
	supply_claimed.emit(bundle)
	return true

func add_inventory(items: Dictionary) -> void:
	for item in items:
		if inventory.has(item):
			inventory[item] = int(inventory[item]) + int(items[item])
		else:
			inventory[item] = int(items[item])
	inventory_changed.emit()

func current_objective() -> Dictionary:
	return run_director.current_milestone()

func current_objective_status() -> String:
	return run_director.milestone_status(simulation)

func current_objective_progress() -> Dictionary:
	return run_director.milestone_progress(simulation)

func current_objective_lens() -> Dictionary:
	return run_director.objective_lens_snapshot(simulation)

func continue_observing() -> bool:
	if not run_director.continue_observing():
		return false
	simulation_speed = 1.0
	return true

func interpolation_alpha() -> float:
	return clampf(accumulator / float(config["simulation"]["fixed_step"]), 0.0, 1.0)

func _on_director_milestone_completed(index: int, milestone: Dictionary) -> void:
	var effects: Dictionary = milestone["effects"]
	if effects.has("introduction"):
		add_inventory(effects["introduction"])
	if effects.has("transplant_charges"):
		transplant_charges += int(effects["transplant_charges"])
		tool_state_changed.emit()
	if effects.has("expand_world") and simulation.expand_world(float(effects["expand_world"])):
		world_expanded.emit(simulation.world_radius)
	milestone_completed.emit(index, str(milestone["id"]), str(milestone["completion_message"]))

func _on_director_unlock_changed(_item: String, _unlocked: bool) -> void:
	if not run_director.is_unlocked(selected_item):
		selected_item = ""
	unlocks_changed.emit()
	inventory_changed.emit()

func _on_director_state_changed(previous_state: String, new_state: String) -> void:
	if new_state == RunDirector.STATE_CRITICAL:
		if supply_pending:
			simulation_speed = 0.0
		else:
			simulation_speed = 1.0
	elif new_state in [RunDirector.STATE_GAME_OVER, RunDirector.STATE_COMPLETED]:
		simulation_speed = 0.0
	run_state_changed.emit(previous_state, new_state)

func _on_director_critical_started() -> void:
	critical_started.emit()

func _on_director_critical_recovered() -> void:
	critical_recovered.emit()

func _on_first_recovery_supply_requested() -> void:
	var recovery: Dictionary = config["supply"]["first_collapse_bundle"].duplicate(true)
	if supply_pending:
		if supply_choices.is_empty():
			supply_choices = [recovery]
		else:
			supply_choices[supply_choices.size() - 1] = recovery
		supply_ready.emit(supply_choices)
		return
	forced_recovery_supply = true
	var delay: float = config["progression"]["critical"]["first_rescue_delay"]
	supply_time_remaining = minf(supply_time_remaining, delay)

func _on_director_run_failed(recap: String) -> void:
	run_failed.emit(recap)

func _on_director_run_completed() -> void:
	run_completed.emit()

func _on_animal_story(kind: String, entity_id: int, event_type: String, related_id: int, position: Vector2) -> void:
	var snapshot := simulation.animal_snapshot(kind, entity_id, false)
	if snapshot.is_empty():
		return
	var name := str(snapshot["name"])
	var description := ""
	match event_type:
		"arrival":
			description = "%s %s the meadow" % [name, "entered" if kind == "fox" else "joined"]
		"birth":
			var parents: Array = snapshot.get("parent_names", [])
			description = "%s was born%s" % [name, " to " + " & ".join(parents) if not parents.is_empty() else ""]
		"first_meal":
			description = "%s found a first meal" % name
		"hunt":
			description = "%s completed a hunt" % name
	if not description.is_empty():
		_add_story(event_type, description, kind, entity_id, position, related_id)

func _add_story(event_type: String, description: String, kind: String, entity_id: int, position: Vector2, related_id: int = -1, detail: String = "", cause: String = "") -> void:
	var story := {
		"type": event_type,
		"description": description,
		"kind": kind,
		"entity_id": entity_id,
		"related_id": related_id,
		"position": position,
		"time": simulation.simulation_time,
		"detail": detail,
		"cause": cause,
	}
	ecology_stories.push_front(story)
	if ecology_stories.size() > 128:
		ecology_stories.resize(128)
	ecology_story_added.emit(story)

func _on_animal_died(snapshot: Dictionary) -> void:
	var cause := str(snapshot["cause"])
	var description := "%s %s" % [snapshot["name"], {
		"age": "died of old age",
		"starvation": "died from starvation",
		"predation": "was caught by a fox",
	}.get(cause, "died")]
	var detail := death_explanation(cause, str(snapshot["kind"]))
	latest_loss = snapshot.duplicate(true)
	latest_loss["description"] = description
	latest_loss["detail"] = detail
	_life_warning_state.erase("%s:%d" % [snapshot["kind"], snapshot["id"]])
	_family_watch_time = -INF
	_add_story("death", description, str(snapshot["kind"]), int(snapshot["id"]), snapshot["position"], -1, detail, cause)

func death_explanation(cause: String, kind: String = "rabbit") -> String:
	match cause:
		"age": return "Reached the end of a natural lifespan. Food cannot prevent old age; support a new generation."
		"starvation": return "Went too long without enough food. " + ("Place fresh forage close to the remaining rabbits." if kind == "rabbit" else "Foxes need reachable rabbits to hunt.")
		"predation": return "A fox caught this rabbit while hunting. Keep a well-fed breeding group to replace losses."
	return "This animal is no longer in the meadow."

func _update_life_warnings() -> void:
	for kind in ["rabbit", "fox"]:
		var animals: Dictionary = simulation.rabbits if kind == "rabbit" else simulation.foxes
		var cfg: Dictionary = config[kind]
		for id in animals:
			var animal: Dictionary = animals[id]
			var key := "%s:%d" % [kind, id]
			var warned: Dictionary = _life_warning_state.get(key, {})
			if float(animal["age"]) >= float(animal["lifespan"]) * 0.78 and not bool(warned.get("elder", false)):
				warned["elder"] = true
				_add_story("elder", "%s is growing old" % animal["name"], kind, id, animal["position"], -1,
					"The clock badge marks an elder nearing the end of a natural lifespan. Food cannot stop aging; support the next generation.")
			var hunger := float(animal["hunger"])
			if hunger >= float(cfg.get("hunger_warning_at", cfg["starvation_threshold"])) and not bool(warned.get("hunger", false)):
				warned["hunger"] = true
				_add_story("hunger_warning", "%s needs food soon" % animal["name"], kind, id, animal["position"], -1,
					"Continued hunger leads to starvation. " + ("Place fresh forage near this rabbit." if kind == "rabbit" else "This fox needs reachable rabbits to hunt."))
			elif hunger < float(cfg.get("hungry_at", cfg.get("hunt_at", 20.0))):
				warned.erase("hunger")
			_life_warning_state[key] = warned

func family_watch() -> Dictionary:
	# Diagnose one named rabbit, not a misleading promise about the entire colony.
	# The cheap candidate scan and the local forage query run at most twice a
	# simulated second even though the HUD refreshes every rendered frame.
	if simulation.simulation_time - _family_watch_time < 0.5 and simulation.rabbits.has(int(_family_watch.get("id", -1))):
		return _family_watch
	_family_watch_time = simulation.simulation_time
	_family_watch = {}
	var chosen := -1
	var best_score := -INF
	var cfg: Dictionary = config["rabbit"]
	for id in simulation.rabbits:
		var rabbit: Dictionary = simulation.rabbits[id]
		var score := 0.0
		if float(rabbit["age"]) >= float(cfg["adult_age"]): score += 8.0
		if float(rabbit["hunger"]) <= float(cfg["reproduction_hunger_max"]): score += 4.0
		if float(rabbit["reproduction_cooldown"]) <= 0.0: score += 2.0
		score += minf(1.0, float(rabbit["recent_food"]) / maxf(1.0, float(cfg["reproduction_food_needed"])))
		if score > best_score:
			best_score = score
			chosen = id
	if chosen != -1:
		_family_watch = simulation.rabbit_birth_status(chosen).duplicate()
		_family_watch["id"] = chosen
		_family_watch["name"] = simulation.rabbits[chosen]["name"]
	return _family_watch

func _item_label(item: String) -> String:
	return {"rabbit": "Rabbit", "fox": "Fox", "carrot_patch": "Carrot Patch", "berry_bush": "Berry Bush"}.get(item, item.capitalize())
