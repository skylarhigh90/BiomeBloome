class_name GameSystems
extends RefCounted

signal inventory_changed
signal supply_ready(choices: Array)
signal supply_claimed(bundle: Dictionary)
signal objective_completed(index: int, objective_name: String)
signal world_expanded(new_radius: float)

var config: Dictionary
var simulation: EcosystemSimulation
var inventory: Dictionary
var selected_item := ""
var simulation_speed := 1.0
var accumulator := 0.0
var supply_time_remaining: float
var supply_choices: Array = []
var supply_pending := false
var objective_index := 0
var objective_stability := 0.0
var ecosystem_established := false
var expansion_time_remaining: float
var rng := RandomNumberGenerator.new()

func _init(p_config: Dictionary = {}) -> void:
	config = p_config if not p_config.is_empty() else GameConfig.make()
	simulation = EcosystemSimulation.new(config)
	inventory = config["inventory"].duplicate(true)
	supply_time_remaining = float(config["supply"]["interval"])
	expansion_time_remaining = float(config["world"]["expansion_interval"])
	rng.seed = int(config["simulation"]["seed"]) + 12003

func set_speed(speed: float) -> void:
	if speed in [0.0, 1.0, 2.0, 3.0]:
		simulation_speed = speed

func is_paused() -> bool:
	return simulation_speed == 0.0

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
	if completed_steps >= maximum_steps:
		accumulator = minf(accumulator, fixed_step)
	return completed_steps

func _tick_systems(delta: float) -> void:
	simulation.step(delta)
	_update_supply(delta)
	_update_objective(delta)
	_update_expansion(delta)

func can_place(item: String, position: Vector2) -> bool:
	if not inventory.has(item) or int(inventory[item]) <= 0:
		return false
	if not simulation.is_position_valid(position):
		return false
	if item in ["grass", "berry_bush"]:
		for plant in simulation.plants.values():
			if position.distance_to(plant["position"]) < 15.0:
				return false
	return item in ["rabbit", "fox", "grass", "berry_bush"]

func place_item(item: String, position: Vector2) -> int:
	if not can_place(item, position):
		return -1
	var entity_id := -1
	match item:
		"rabbit":
			entity_id = simulation.add_rabbit(position)
		"fox":
			entity_id = simulation.add_fox(position)
		"grass", "berry_bush":
			entity_id = simulation.add_plant(item, position)
	if entity_id == -1:
		return -1
	inventory[item] = int(inventory[item]) - 1
	if int(inventory[item]) <= 0 and selected_item == item:
		selected_item = ""
	inventory_changed.emit()
	return entity_id

func select_item(item: String) -> bool:
	if inventory.has(item) and int(inventory[item]) > 0:
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
		supply_pending = true
		supply_ready.emit(supply_choices)

func _make_supply_choices() -> void:
	var bundles: Array = config["supply"]["bundles"]
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
	supply_claimed.emit(bundle)
	return true

func add_inventory(items: Dictionary) -> void:
	for item in items:
		if inventory.has(item):
			inventory[item] = int(inventory[item]) + int(items[item])
		else:
			inventory[item] = int(items[item])
	inventory_changed.emit()

func _update_objective(delta: float) -> void:
	if ecosystem_established:
		return
	var objectives: Array = config["objectives"]
	if objective_index >= objectives.size():
		ecosystem_established = true
		return
	var objective: Dictionary = objectives[objective_index]
	var all_met := true
	for kind in objective["targets"]:
		if simulation.population(kind) < int(objective["targets"][kind]):
			all_met = false
			break
	if all_met:
		objective_stability += delta
	else:
		objective_stability = 0.0
	if objective_stability + 0.0001 >= float(objective["duration"]):
		var completed_index := objective_index
		var completed_name: String = objective["name"]
		objective_index += 1
		objective_stability = 0.0
		if objective_index >= objectives.size():
			ecosystem_established = true
		objective_completed.emit(completed_index, completed_name)

func current_objective() -> Dictionary:
	if ecosystem_established or objective_index >= config["objectives"].size():
		return {}
	return config["objectives"][objective_index]

func _update_expansion(delta: float) -> void:
	if simulation.world_radius >= float(config["world"]["maximum_radius"]):
		return
	expansion_time_remaining -= delta
	if expansion_time_remaining <= 0.0:
		if simulation.expand_world(float(config["world"]["expansion_amount"])):
			world_expanded.emit(simulation.world_radius)
		expansion_time_remaining += float(config["world"]["expansion_interval"])

func interpolation_alpha() -> float:
	return clampf(accumulator / float(config["simulation"]["fixed_step"]), 0.0, 1.0)
