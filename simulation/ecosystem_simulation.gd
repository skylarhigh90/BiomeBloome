class_name EcosystemSimulation
extends RefCounted

signal entity_added(kind: String, entity_id: int, reason: String)
signal entity_removed(kind: String, entity_id: int, position: Vector2, cause: String)
signal plant_eaten(plant_id: int, position: Vector2)

var config: Dictionary
var rng := RandomNumberGenerator.new()
var spatial: SpatialHash
var simulation_time := 0.0
var world_radius: float
var rabbits: Dictionary = {}
var foxes: Dictionary = {}
var plants: Dictionary = {}
var forest_patches: Array = []
var next_entity_id := 1
var last_tick_stats := {"queries": 0, "captures": 0, "births": 0}

func _init(p_config: Dictionary = {}, p_seed: int = -1) -> void:
	config = p_config if not p_config.is_empty() else GameConfig.make()
	var seed_value: int = config["simulation"]["seed"] if p_seed < 0 else p_seed
	rng.seed = seed_value
	spatial = SpatialHash.new(float(config["simulation"]["spatial_cell_size"]))
	world_radius = float(config["world"]["initial_radius"])
	_generate_forest_patches(seed_value)

func _generate_forest_patches(seed_value: int) -> void:
	forest_patches.clear()
	var patch_rng := RandomNumberGenerator.new()
	patch_rng.seed = seed_value + 7719
	var world_cfg: Dictionary = config["world"]
	var max_radius: float = world_cfg["maximum_radius"]
	for index in range(int(world_cfg["forest_patch_count"])):
		var angle := patch_rng.randf_range(0.0, TAU)
		var distance := sqrt(patch_rng.randf()) * max_radius * 0.88
		var patch_radius := patch_rng.randf_range(world_cfg["forest_patch_min_radius"], world_cfg["forest_patch_max_radius"])
		var center := Vector2.from_angle(angle) * distance
		forest_patches.append({
			"center": center,
			"radius": patch_radius,
			"squash": patch_rng.randf_range(0.72, 1.28),
			"rotation": patch_rng.randf_range(0.0, TAU),
			"tone": patch_rng.randf(),
		})

func reset() -> void:
	simulation_time = 0.0
	world_radius = float(config["world"]["initial_radius"])
	rabbits.clear()
	foxes.clear()
	plants.clear()
	spatial.clear()
	next_entity_id = 1
	rng.seed = int(config["simulation"]["seed"])

func boundary_radius_at(angle: float, radius_override: float = -1.0) -> float:
	var base := world_radius if radius_override < 0.0 else radius_override
	return base * (1.0 + sin(angle * 5.0 + 0.8) * 0.018 + sin(angle * 9.0 - 1.7) * 0.012)

func is_position_valid(position: Vector2) -> bool:
	var distance := position.length()
	if distance > boundary_radius_at(position.angle()) - float(config["world"]["placement_clearance"]):
		return false
	return true

func terrain_forestness(position: Vector2) -> float:
	var strongest := 0.0
	for patch in forest_patches:
		var local: Vector2 = (position - patch["center"]).rotated(-float(patch["rotation"]))
		local.y /= float(patch["squash"])
		var normalized := local.length() / float(patch["radius"])
		if normalized < 1.25:
			var value := smoothstep(1.2, 0.36, normalized)
			strongest = maxf(strongest, value)
	return clampf(strongest, 0.0, 1.0)

func add_rabbit(position: Vector2, reason: String = "placement") -> int:
	var cfg: Dictionary = config["rabbit"]
	var entity_id := _take_id()
	var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
	rabbits[entity_id] = {
		"id": entity_id,
		"type": "rabbit",
		"position": position,
		"previous_position": position,
		"velocity": direction * cfg["move_speed"] * 0.35,
		"age": 0.0 if reason == "birth" else rng.randf_range(cfg["adult_age"], cfg["adult_age"] + 12.0),
		"hunger": 17.0 if reason == "birth" else rng.randf_range(9.0, 22.0),
		"behavior": "wander",
		"target_id": -1,
		"reproduction_cooldown": cfg["newborn_cooldown"] if reason == "birth" else rng.randf_range(2.0, 8.0),
		"alive": true,
		"recent_food": 4.0,
		"wander_direction": direction,
		"wander_timer": rng.randf_range(1.2, 3.6),
		"starvation_time": 0.0,
		"lifespan": cfg["lifespan"] * rng.randf_range(0.86, 1.16),
		"created_at": simulation_time,
		"reason": reason,
	}
	entity_added.emit("rabbit", entity_id, reason)
	return entity_id

func add_fox(position: Vector2, reason: String = "placement") -> int:
	var cfg: Dictionary = config["fox"]
	var entity_id := _take_id()
	var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
	foxes[entity_id] = {
		"id": entity_id,
		"type": "fox",
		"position": position,
		"previous_position": position,
		"velocity": direction * cfg["move_speed"] * 0.35,
		"age": 0.0 if reason == "birth" else rng.randf_range(cfg["adult_age"], cfg["adult_age"] + 20.0),
		"hunger": 16.0 if reason == "birth" else rng.randf_range(10.0, 24.0),
		"behavior": "wander",
		"target_id": -1,
		"reproduction_cooldown": cfg["newborn_cooldown"] if reason == "birth" else rng.randf_range(12.0, 30.0),
		"alive": true,
		"recent_food": 0.0,
		"wander_direction": direction,
		"wander_timer": rng.randf_range(1.4, 4.2),
		"starvation_time": 0.0,
		"capture_progress": 0.0,
		"lifespan": cfg["lifespan"] * rng.randf_range(0.88, 1.14),
		"created_at": simulation_time,
		"reason": reason,
	}
	entity_added.emit("fox", entity_id, reason)
	return entity_id

func add_plant(plant_type: String, position: Vector2, reason: String = "placement") -> int:
	if not config["plants"].has(plant_type):
		return -1
	var cfg: Dictionary = config["plants"][plant_type]
	var entity_id := _take_id()
	plants[entity_id] = {
		"id": entity_id,
		"type": plant_type,
		"position": position,
		"food": float(cfg["max_food"]),
		"max_food": float(cfg["max_food"]),
		"regeneration": float(cfg["regeneration"]),
		"alive": true,
		"created_at": simulation_time,
		"reason": reason,
	}
	entity_added.emit(plant_type, entity_id, reason)
	return entity_id

func _take_id() -> int:
	var result := next_entity_id
	next_entity_id += 1
	return result

func population(kind: String) -> int:
	if kind == "rabbit":
		return rabbits.size()
	if kind == "fox":
		return foxes.size()
	return 0

func kill_rabbit(entity_id: int, cause: String = "predation") -> bool:
	if not rabbits.has(entity_id):
		return false
	var position: Vector2 = rabbits[entity_id]["position"]
	rabbits.erase(entity_id)
	entity_removed.emit("rabbit", entity_id, position, cause)
	return true

func kill_fox(entity_id: int, cause: String = "starvation") -> bool:
	if not foxes.has(entity_id):
		return false
	var position: Vector2 = foxes[entity_id]["position"]
	foxes.erase(entity_id)
	entity_removed.emit("fox", entity_id, position, cause)
	return true

func expand_world(amount: float) -> bool:
	var maximum: float = config["world"]["maximum_radius"]
	var before := world_radius
	world_radius = minf(maximum, world_radius + amount)
	return world_radius > before

func rebuild_spatial_index() -> void:
	spatial.clear()
	for entity_id in rabbits:
		spatial.insert("rabbit", entity_id, rabbits[entity_id]["position"])
	for entity_id in foxes:
		spatial.insert("fox", entity_id, foxes[entity_id]["position"])
	for entity_id in plants:
		spatial.insert("plant", entity_id, plants[entity_id]["position"])

func query_nearby(kind: String, position: Vector2, radius: float) -> Array:
	last_tick_stats["queries"] += 1
	return spatial.query(kind, position, radius)

func step(delta: float) -> void:
	if delta <= 0.0:
		return
	simulation_time += delta
	last_tick_stats = {"queries": 0, "captures": 0, "births": 0}
	_regenerate_plants(delta)
	rebuild_spatial_index()
	var dead_rabbits: Array = []
	var dead_foxes: Array = []
	for entity_id in rabbits.keys():
		if rabbits.has(entity_id) and _update_rabbit(rabbits[entity_id], delta):
			dead_rabbits.append(entity_id)
	for entity_id in foxes.keys():
		if foxes.has(entity_id) and _update_fox(foxes[entity_id], delta):
			dead_foxes.append(entity_id)
	for entity_id in dead_rabbits:
		kill_rabbit(entity_id, "starvation" if rabbits.has(entity_id) and rabbits[entity_id]["age"] < rabbits[entity_id]["lifespan"] else "age")
	for entity_id in dead_foxes:
		kill_fox(entity_id, "starvation" if foxes.has(entity_id) and foxes[entity_id]["age"] < foxes[entity_id]["lifespan"] else "age")
	rebuild_spatial_index()
	_process_rabbit_reproduction()
	_process_fox_reproduction()

func _regenerate_plants(delta: float) -> void:
	for plant in plants.values():
		plant["food"] = minf(plant["max_food"], plant["food"] + plant["regeneration"] * delta)

func _update_rabbit(rabbit: Dictionary, delta: float) -> bool:
	var cfg: Dictionary = config["rabbit"]
	rabbit["previous_position"] = rabbit["position"]
	rabbit["age"] += delta
	rabbit["hunger"] += cfg["hunger_rate"] * delta
	rabbit["recent_food"] = maxf(0.0, rabbit["recent_food"] - cfg["recent_food_decay"] * delta)
	rabbit["reproduction_cooldown"] = maxf(0.0, rabbit["reproduction_cooldown"] - delta)
	var position: Vector2 = rabbit["position"]
	var desired := Vector2.ZERO
	var threat := _nearest_entry(query_nearby("fox", position, cfg["flee_release_radius"]), position)
	if not threat.is_empty() and position.distance_to(threat["position"]) <= cfg["fox_detection_radius"]:
		rabbit["behavior"] = "flee"
		rabbit["target_id"] = threat["id"]
		var away: Vector2 = position - threat["position"]
		if away.length_squared() < 0.01:
			away = Vector2.from_angle(rng.randf_range(0.0, TAU))
		desired = away.normalized() * cfg["flee_speed"]
	elif rabbit["hunger"] >= cfg["hungry_at"]:
		var food := _best_food_target(position, cfg["food_detection_radius"])
		if not food.is_empty():
			rabbit["behavior"] = "seek_food"
			rabbit["target_id"] = food["id"]
			desired = position.direction_to(food["position"]) * cfg["move_speed"]
			if position.distance_to(food["position"]) <= cfg["eat_distance"]:
				_consume_plant(rabbit, plants[food["id"]], delta)
		else:
			rabbit["behavior"] = "forage"
			rabbit["target_id"] = -1
			desired = _wander_velocity(rabbit, cfg["move_speed"], delta, false)
	else:
		rabbit["behavior"] = "wander"
		rabbit["target_id"] = -1
		desired = _wander_velocity(rabbit, cfg["move_speed"], delta, false)
	desired += _habitat_steering(position, false) * cfg["move_speed"] * (0.12 if rabbit["behavior"] == "flee" else 0.32)
	_move_entity(rabbit, desired, cfg["steering"], delta)
	return _update_mortality(rabbit, cfg, delta)

func _update_fox(fox: Dictionary, delta: float) -> bool:
	var cfg: Dictionary = config["fox"]
	fox["previous_position"] = fox["position"]
	fox["age"] += delta
	fox["hunger"] += cfg["hunger_rate"] * delta
	fox["recent_food"] = maxf(0.0, fox["recent_food"] - cfg["recent_food_decay"] * delta)
	fox["reproduction_cooldown"] = maxf(0.0, fox["reproduction_cooldown"] - delta)
	var position: Vector2 = fox["position"]
	var prey: Dictionary = {}
	if fox["target_id"] != -1 and rabbits.has(fox["target_id"]):
		var target_rabbit: Dictionary = rabbits[fox["target_id"]]
		if position.distance_to(target_rabbit["position"]) <= cfg["prey_detection_radius"] * 1.25:
			prey = {"id": fox["target_id"], "position": target_rabbit["position"]}
	if prey.is_empty() and fox["hunger"] >= cfg["hunt_at"]:
		prey = _nearest_entry(query_nearby("rabbit", position, cfg["prey_detection_radius"]), position)
	var desired := Vector2.ZERO
	if not prey.is_empty():
		fox["behavior"] = "hunt"
		fox["target_id"] = prey["id"]
		desired = position.direction_to(prey["position"]) * cfg["chase_speed"]
		var capture_distance: float = cfg["capture_distance"]
		if position.distance_to(prey["position"]) <= capture_distance:
			fox["capture_progress"] += cfg["capture_rate"] * delta
			if fox["capture_progress"] >= 1.0 or rng.randf() < cfg["capture_rate"] * delta * 0.18:
				if kill_rabbit(prey["id"], "predation"):
					fox["hunger"] = maxf(0.0, fox["hunger"] - cfg["meal_value"])
					fox["recent_food"] += cfg["meal_value"]
					fox["capture_progress"] = 0.0
					fox["target_id"] = -1
					last_tick_stats["captures"] += 1
		else:
			fox["capture_progress"] = maxf(0.0, fox["capture_progress"] - delta * 0.7)
	else:
		fox["behavior"] = "wander"
		fox["target_id"] = -1
		fox["capture_progress"] = 0.0
		desired = _wander_velocity(fox, cfg["move_speed"], delta, true)
	desired += _habitat_steering(position, true) * cfg["move_speed"] * (0.14 if fox["behavior"] == "hunt" else 0.42)
	_move_entity(fox, desired, cfg["steering"], delta)
	return _update_mortality(fox, cfg, delta)

func _wander_velocity(entity: Dictionary, speed: float, delta: float, prefers_forest: bool) -> Vector2:
	entity["wander_timer"] -= delta
	if entity["wander_timer"] <= 0.0:
		var current: Vector2 = entity["wander_direction"]
		var turn := rng.randf_range(-1.05, 1.05)
		entity["wander_direction"] = current.rotated(turn).normalized()
		entity["wander_timer"] = rng.randf_range(1.3, 4.1)
	var pace := 0.62 + sin(simulation_time * 0.7 + entity["id"] * 1.37) * 0.12
	return entity["wander_direction"] * speed * pace

func _habitat_steering(position: Vector2, prefers_forest: bool) -> Vector2:
	var sample_distance := 34.0
	var best_direction := Vector2.ZERO
	var best_score := -INF
	for index in range(8):
		var direction := Vector2.from_angle(float(index) / 8.0 * TAU)
		var sample := position + direction * sample_distance
		var forestness := terrain_forestness(sample)
		var score := forestness if prefers_forest else 1.0 - forestness
		if not is_position_valid(sample):
			score -= 2.0
		if score > best_score:
			best_score = score
			best_direction = direction
	return best_direction

func _move_entity(entity: Dictionary, desired: Vector2, steering: float, delta: float) -> void:
	var position: Vector2 = entity["position"]
	var edge_distance := position.length()
	var edge_radius := boundary_radius_at(position.angle())
	if edge_distance > edge_radius - 42.0:
		var edge_strength := clampf((edge_distance - (edge_radius - 42.0)) / 42.0, 0.0, 1.0)
		desired = desired.lerp(-position.normalized() * maxf(desired.length(), 35.0), edge_strength)
	var velocity: Vector2 = entity["velocity"]
	velocity = velocity.lerp(desired, clampf(steering * delta, 0.0, 1.0))
	var next_position := position + velocity * delta
	if not is_position_valid(next_position):
		velocity = velocity.bounce(position.normalized()).lerp(-position.normalized() * velocity.length(), 0.65)
		next_position = position + velocity * delta
		if not is_position_valid(next_position):
			next_position = position
	entity["velocity"] = velocity
	entity["position"] = next_position

func _best_food_target(position: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for entry in query_nearby("plant", position, radius):
		if not plants.has(entry["id"]):
			continue
		var plant: Dictionary = plants[entry["id"]]
		if plant["food"] <= 0.15:
			continue
		var attraction: float = config["plants"][plant["type"]]["attraction"]
		var score := position.distance_to(plant["position"]) / attraction
		if score < best_score:
			best_score = score
			best = {"id": entry["id"], "position": plant["position"]}
	return best

func _consume_plant(rabbit: Dictionary, plant: Dictionary, delta: float) -> void:
	var cfg: Dictionary = config["rabbit"]
	var amount := minf(plant["food"], cfg["eat_rate"] * delta)
	if amount <= 0.0:
		return
	plant["food"] -= amount
	rabbit["hunger"] = maxf(0.0, rabbit["hunger"] - amount * cfg["food_value"])
	rabbit["recent_food"] += amount * cfg["food_value"]
	rabbit["behavior"] = "eat"
	plant_eaten.emit(plant["id"], plant["position"])

func _update_mortality(entity: Dictionary, cfg: Dictionary, delta: float) -> bool:
	if entity["hunger"] >= cfg["starvation_threshold"]:
		entity["starvation_time"] += delta
	else:
		entity["starvation_time"] = maxf(0.0, entity["starvation_time"] - delta * 0.45)
	return entity["starvation_time"] >= cfg["starvation_duration"] or entity["age"] >= entity["lifespan"]

func _process_rabbit_reproduction() -> void:
	var cfg: Dictionary = config["rabbit"]
	if rabbits.size() >= int(cfg["max_population"]):
		return
	var paired: Dictionary = {}
	var births: Array = []
	for entity_id in rabbits.keys():
		if paired.has(entity_id) or not _rabbit_is_eligible(rabbits[entity_id]):
			continue
		var rabbit: Dictionary = rabbits[entity_id]
		if _local_available_food(rabbit["position"], cfg["mating_radius"]) < cfg["local_food_needed"]:
			continue
		var mate_id := -1
		for entry in query_nearby("rabbit", rabbit["position"], cfg["mating_radius"]):
			if entry["id"] == entity_id or paired.has(entry["id"]) or not rabbits.has(entry["id"]):
				continue
			if _rabbit_is_eligible(rabbits[entry["id"]]):
				mate_id = entry["id"]
				break
		if mate_id == -1:
			continue
		paired[entity_id] = true
		paired[mate_id] = true
		rabbit["reproduction_cooldown"] = cfg["reproduction_cooldown"]
		rabbits[mate_id]["reproduction_cooldown"] = cfg["reproduction_cooldown"]
		rabbit["recent_food"] *= 0.35
		rabbits[mate_id]["recent_food"] *= 0.35
		var litter := rng.randi_range(int(cfg["birth_litter_min"]), int(cfg["birth_litter_max"]))
		for child_index in range(litter):
			if rabbits.size() + births.size() >= int(cfg["max_population"]):
				break
			var midpoint: Vector2 = (rabbit["position"] + rabbits[mate_id]["position"]) * 0.5
			births.append(_nearby_valid_position(midpoint, 10.0 + child_index * 4.0))
	for position in births:
		add_rabbit(position, "birth")
		last_tick_stats["births"] += 1

func _rabbit_is_eligible(rabbit: Dictionary) -> bool:
	var cfg: Dictionary = config["rabbit"]
	return rabbit["age"] >= cfg["adult_age"] \
		and rabbit["hunger"] <= cfg["reproduction_hunger_max"] \
		and rabbit["recent_food"] >= cfg["reproduction_food_needed"] \
		and rabbit["reproduction_cooldown"] <= 0.0

func _process_fox_reproduction() -> void:
	var cfg: Dictionary = config["fox"]
	if foxes.size() >= int(cfg["max_population"]):
		return
	var paired: Dictionary = {}
	var births: Array = []
	for entity_id in foxes.keys():
		if paired.has(entity_id) or not _fox_is_eligible(foxes[entity_id]):
			continue
		var fox: Dictionary = foxes[entity_id]
		var mate_id := -1
		for entry in query_nearby("fox", fox["position"], cfg["mating_radius"]):
			if entry["id"] == entity_id or paired.has(entry["id"]) or not foxes.has(entry["id"]):
				continue
			if _fox_is_eligible(foxes[entry["id"]]):
				mate_id = entry["id"]
				break
		if mate_id == -1:
			continue
		paired[entity_id] = true
		paired[mate_id] = true
		fox["reproduction_cooldown"] = cfg["reproduction_cooldown"]
		foxes[mate_id]["reproduction_cooldown"] = cfg["reproduction_cooldown"]
		fox["recent_food"] *= 0.25
		foxes[mate_id]["recent_food"] *= 0.25
		var midpoint: Vector2 = (fox["position"] + foxes[mate_id]["position"]) * 0.5
		births.append(_nearby_valid_position(midpoint, 15.0))
	for position in births:
		add_fox(position, "birth")
		last_tick_stats["births"] += 1

func _fox_is_eligible(fox: Dictionary) -> bool:
	var cfg: Dictionary = config["fox"]
	return fox["age"] >= cfg["adult_age"] \
		and fox["hunger"] <= cfg["reproduction_hunger_max"] \
		and fox["recent_food"] >= cfg["reproduction_food_needed"] \
		and fox["reproduction_cooldown"] <= 0.0

func _local_available_food(position: Vector2, radius: float) -> float:
	var total := 0.0
	for entry in query_nearby("plant", position, radius):
		if plants.has(entry["id"]):
			total += float(plants[entry["id"]]["food"])
	return total

func _nearby_valid_position(origin: Vector2, distance: float) -> Vector2:
	for attempt in range(8):
		var candidate := origin + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(distance * 0.45, distance)
		if is_position_valid(candidate):
			return candidate
	return origin

func _nearest_entry(entries: Array, position: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance := INF
	for entry in entries:
		var distance := position.distance_squared_to(entry["position"])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = entry
	return nearest

func debug_entity(kind: String, entity_id: int) -> Dictionary:
	var source: Dictionary = rabbits if kind == "rabbit" else foxes
	if not source.has(entity_id):
		return {}
	var entity: Dictionary = source[entity_id]
	var nearby := {}
	if kind == "rabbit":
		nearby = {
			"food": query_nearby("plant", entity["position"], config["rabbit"]["food_detection_radius"]).size(),
			"predators": query_nearby("fox", entity["position"], config["rabbit"]["fox_detection_radius"]).size(),
		}
	else:
		nearby = {"prey": query_nearby("rabbit", entity["position"], config["fox"]["prey_detection_radius"]).size()}
	return {
		"id": entity["id"],
		"type": kind,
		"hunger": entity["hunger"],
		"age": entity["age"],
		"behavior": entity["behavior"],
		"target_id": entity["target_id"],
		"reproduction_cooldown": entity["reproduction_cooldown"],
		"nearby": nearby,
	}
