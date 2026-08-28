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

func _init(p_config: Dictionary = {}) -> void:
	config = p_config if not p_config.is_empty() else GameConfig.make()
	simulation = EcosystemSimulation.new(config)
	run_director = RunDirector.new(config)
	inventory = config["inventory"].duplicate(true)
	supply_time_remaining = float(config["supply"]["interval"])
	rng.seed = int(config["simulation"]["seed"]) + 12003
	simulation.entity_added.connect(run_director.record_entity_added)
	simulation.entity_removed.connect(run_director.record_entity_removed)
	simulation.creature_fed.connect(run_director.record_creature_fed)
	simulation.predation_succeeded.connect(run_director.record_predation)
	run_director.milestone_completed.connect(_on_director_milestone_completed)
	run_director.unlock_changed.connect(_on_director_unlock_changed)
	run_director.state_changed.connect(_on_director_state_changed)
	run_director.critical_started.connect(_on_director_critical_started)
	run_director.critical_recovered.connect(_on_director_critical_recovered)
	run_director.first_recovery_supply_requested.connect(_on_first_recovery_supply_requested)
	run_director.run_failed.connect(_on_director_run_failed)
	run_director.run_completed.connect(_on_director_run_completed)

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
	inventory_changed.emit()
	return entity_id

func select_item(item: String) -> bool:
	if supply_pending:
		return false
	if run_director.is_unlocked(item) and inventory.has(item) and int(inventory[item]) > 0:
		selected_item = item
		inventory_changed.emit()
		return true
	selected_item = ""
	inventory_changed.emit()
	return false

func clear_selection() -> void:
	selected_item = ""
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
		forced_recovery_supply = false
		return
	if bundles.size() == 1:
		supply_choices = [bundles[0].duplicate(true)]
		return
	var first_index := rng.randi_range(0, bundles.size() - 1)
	var second_index := rng.randi_range(0, bundles.size() - 2)
	if second_index >= first_index:
		second_index += 1
	supply_choices = [bundles[first_index].duplicate(true), bundles[second_index].duplicate(true)]

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
