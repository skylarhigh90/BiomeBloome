extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")

var placement_serial := 0

func _initialize() -> void:
	var variants := ["current", "no supplies", "one-rabbit litters", "looser food gate", "richer plants", "richer food", "stronger fox pursuit"]
	var requested := OS.get_cmdline_user_args()
	if not requested.is_empty():
		variants = [" ".join(requested)]
	print("\nBALANCE PROBE · 240 simulated seconds per variant")
	for variant in variants:
		var config := Config.make().duplicate(true)
		_apply_variant(config, variant)
		print("%s: %s" % [variant, str(_run_managed_strategy(config, 240.0))])
	quit(0)

func _apply_variant(config: Dictionary, variant: String) -> void:
	if variant == "no supplies":
		config["supply"]["interval"] = 9999.0
	elif variant == "one-rabbit litters":
		config["rabbit"]["birth_litter_max"] = 1
	elif variant in ["looser food gate", "richer food"]:
		config["rabbit"]["local_food_needed"] = 5.0
	if variant in ["richer plants", "richer food"]:
		config["plants"]["carrot_patch"]["max_food"] = 17.0
		config["plants"]["carrot_patch"]["regeneration"] = 0.58
		config["plants"]["berry_bush"]["max_food"] = 30.0
		config["plants"]["berry_bush"]["regeneration"] = 0.42
	if variant == "stronger fox pursuit":
		config["fox"]["chase_speed"] = 68.0
		config["fox"]["prey_detection_radius"] = 250.0
		config["fox"]["capture_rate"] = 2.1

func _run_managed_strategy(config: Dictionary, duration: float) -> Dictionary:
	placement_serial = 0
	var systems = Systems.new(config)
	var events := {
		"rabbit_births": 0,
		"predation": 0,
		"rabbit_starvation": 0,
		"rabbit_age": 0,
		"fox_births": 0,
		"fox_starvation": 0,
		"supplied_rabbits": 0,
		"supplied_foxes": 0,
		"supplied_plants": 0,
	}
	systems.simulation.entity_added.connect(func(kind: String, _id: int, reason: String) -> void:
		if kind == "rabbit" and reason == "birth":
			events["rabbit_births"] += 1
		elif kind == "fox" and reason == "birth":
			events["fox_births"] += 1
	)
	systems.simulation.entity_removed.connect(func(kind: String, _id: int, _position: Vector2, cause: String) -> void:
		if kind == "rabbit" and cause == "predation":
			events["predation"] += 1
		elif kind == "rabbit" and cause == "starvation":
			events["rabbit_starvation"] += 1
		elif kind == "rabbit" and cause == "age":
			events["rabbit_age"] += 1
		elif kind == "fox" and cause == "starvation":
			events["fox_starvation"] += 1
	)
	systems.supply_claimed.connect(func(bundle: Dictionary) -> void:
		var items: Dictionary = bundle["items"]
		events["supplied_rabbits"] += int(items.get("rabbit", 0))
		events["supplied_foxes"] += int(items.get("fox", 0))
		events["supplied_plants"] += int(items.get("carrot_patch", 0)) + int(items.get("berry_bush", 0))
	)
	_place_available_items(systems)
	var low: int = systems.simulation.population("rabbit")
	var peak: int = low
	var total_food_fraction := 0.0
	var food_samples := 0
	var milestone_times: Array = []
	var previous_milestone := 0
	for tick in range(int(duration * 10.0)):
		if systems.supply_pending:
			systems.choose_supply(_choose_supply(systems))
			_place_available_items(systems)
		elif tick % 10 == 0:
			_place_available_items(systems)
		if systems.is_completed():
			systems.continue_observing()
		systems.advance(0.1)
		var rabbits: int = systems.simulation.population("rabbit")
		low = mini(low, rabbits)
		peak = maxi(peak, rabbits)
		if systems.run_director.milestone_index != previous_milestone:
			milestone_times.append(snappedf(systems.simulation.simulation_time, 0.1))
			previous_milestone = systems.run_director.milestone_index
		if tick % 100 == 0:
			var current_food := 0.0
			var maximum_food := 0.0
			for plant in systems.simulation.plants.values():
				current_food += float(plant["food"])
				maximum_food += float(plant["max_food"])
			if maximum_food > 0.0:
				total_food_fraction += current_food / maximum_food
				food_samples += 1
		if systems.is_game_over():
			break
	return {
		"milestones": milestone_times,
		"state": systems.run_director.run_state,
		"rabbit_end": systems.simulation.population("rabbit"),
		"rabbit_low": low,
		"rabbit_peak": peak,
		"fox_end": systems.simulation.population("fox"),
		"plants": systems.simulation.plants.size(),
		"avg_food_fraction": snappedf(total_food_fraction / maxf(1.0, float(food_samples)), 0.01),
		"sequence_progress": systems.run_director.debug_lines(),
		"recent_ecology_events": systems.run_director.milestone_events,
		"events": events,
	}

func _place_available_items(systems) -> void:
	while int(systems.inventory.get("carrot_patch", 0)) > 0:
		if not _place_plant(systems, "carrot_patch"):
			break
	while int(systems.inventory.get("berry_bush", 0)) > 0:
		if not _place_plant(systems, "berry_bush"):
			break
	while int(systems.inventory.get("rabbit", 0)) > 0 and systems.simulation.population("rabbit") < 18:
		var angle := float(placement_serial) * 2.399
		var radius := 18.0 + float(placement_serial % 4) * 9.0
		if systems.place_item("rabbit", Vector2.from_angle(angle) * radius) == -1:
			break
		placement_serial += 1
	while int(systems.inventory.get("fox", 0)) > 0 and systems.simulation.population("fox") < 2:
		var angle := float(placement_serial) * 2.117
		if systems.place_item("fox", Vector2.from_angle(angle) * 115.0) == -1:
			break
		placement_serial += 1

func _place_plant(systems, kind: String) -> bool:
	for _attempt in range(30):
		var angle := float(placement_serial) * 2.399
		var radius := 42.0 + float(placement_serial % 9) * 20.0
		placement_serial += 1
		if systems.place_item(kind, Vector2.from_angle(angle) * radius) != -1:
			return true
	return false

func _choose_supply(systems) -> int:
	var best_index := 0
	var best_score := -INF
	for index in range(systems.supply_choices.size()):
		var items: Dictionary = systems.supply_choices[index]["items"]
		var score := float(items.get("carrot_patch", 0)) + float(items.get("berry_bush", 0)) * 1.4
		if systems.simulation.population("rabbit") < 12:
			score += float(items.get("rabbit", 0)) * 2.2
		else:
			score += float(items.get("rabbit", 0)) * 0.5
		if systems.run_director.is_unlocked("fox") and systems.simulation.population("fox") < 2:
			score += float(items.get("fox", 0)) * 3.0
		if score > best_score:
			best_score = score
			best_index = index
	return best_index
