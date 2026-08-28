class_name EcosystemSimulation
extends RefCounted

signal entity_added(kind: String, entity_id: int, reason: String)
signal entity_removed(kind: String, entity_id: int, position: Vector2, cause: String)
signal plant_eaten(plant_id: int, position: Vector2)
signal creature_fed(kind: String, entity_id: int, food_id: int)
signal predation_succeeded(fox_id: int, rabbit_id: int, position: Vector2)

var config: Dictionary
var rng := RandomNumberGenerator.new()
var spatial: SpatialHash
var terrain: TemperateWildsTerrain
var simulation_time := 0.0
var world_radius: float
var rabbits: Dictionary = {}
var foxes: Dictionary = {}
var plants: Dictionary = {}
# Compatibility alias for older rendering/tests; terrain owns the actual data.
var forest_patches: Array = []
var next_entity_id := 1
var last_tick_stats := {"queries": 0, "captures": 0, "births": 0}
var rabbit_food_target_claims: Dictionary = {}

func _init(p_config: Dictionary = {}, p_seed: int = -1) -> void:
	config = p_config if not p_config.is_empty() else GameConfig.make()
	var seed_value: int = config["simulation"]["seed"] if p_seed < 0 else p_seed
	rng.seed = seed_value
	spatial = SpatialHash.new(float(config["simulation"]["spatial_cell_size"]))
	world_radius = float(config["world"]["initial_radius"])
	terrain = TemperateWildsTerrain.new(config, seed_value)
	forest_patches = terrain.woodland_patches

func reset() -> void:
	simulation_time = 0.0
	world_radius = float(config["world"]["initial_radius"])
	rabbits.clear()
	foxes.clear()
	plants.clear()
	rabbit_food_target_claims.clear()
	spatial.clear()
	next_entity_id = 1
	rng.seed = int(config["simulation"]["seed"])

func boundary_radius_at(angle: float, radius_override: float = -1.0) -> float:
	var base := world_radius if radius_override < 0.0 else radius_override
	return terrain.boundary_radius_at(angle, base)

func is_inside_world(position: Vector2, clearance: float = -1.0) -> bool:
	var actual_clearance := float(config["world"]["placement_clearance"]) if clearance < 0.0 else clearance
	return terrain.is_inside_world(position, world_radius, actual_clearance)

func is_position_valid(position: Vector2) -> bool:
	return terrain.can_occupy_ground(position, world_radius, float(config["world"]["placement_clearance"]))

func terrain_forestness(position: Vector2) -> float:
	return terrain.woodland_cover(position)

func add_rabbit(position: Vector2, reason: String = "placement") -> int:
	var cfg: Dictionary = config["rabbit"]
	var entity_id := _take_id()
	var direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
	var velocity: Vector2 = direction * cfg["move_speed"] * 0.35
	var state_jitter := rng.randf_range(-1.0, 1.0) if reason == "birth" else 0.0
	rabbits[entity_id] = {
		"id": entity_id,
		"type": "rabbit",
		"position": position,
		"previous_position": position,
		"velocity": velocity,
		"previous_velocity": velocity,
		"age": 0.0 if reason == "birth" else rng.randf_range(cfg["adult_age"], cfg["adult_age"] + 12.0),
		"hunger": 17.0 + state_jitter * 1.5 if reason == "birth" else rng.randf_range(9.0, 22.0),
		"food_motivated": false,
		"behavior": "wander",
		"target_id": -1,
		"reproduction_cooldown": cfg["newborn_cooldown"] + state_jitter * 1.2 if reason == "birth" else rng.randf_range(2.0, 8.0),
		"alive": true,
		"recent_food": 4.0 + state_jitter * 0.35 if reason == "birth" else 4.0,
		"wander_direction": direction,
		"wander_timer": rng.randf_range(cfg["wander_noise_interval_min"], cfg["wander_noise_interval_max"]),
		"wander_angular_velocity": 0.0,
		"wander_turn_target": rng.randf_range(-cfg["wander_turn_rate"], cfg["wander_turn_rate"]),
		"decision_interval": rng.randf_range(cfg["decision_interval_min"], cfg["decision_interval_max"]),
		"decision_timer": rng.randf_range(0.0, cfg["decision_interval_max"]),
		"speed_scale": rng.randf_range(1.0 - cfg["speed_variation"], 1.0 + cfg["speed_variation"]),
		"turn_scale": rng.randf_range(1.0 - cfg["turn_variation"], 1.0 + cfg["turn_variation"]),
		"hunger_threshold_offset": rng.randf_range(-cfg["hunger_threshold_variation"], cfg["hunger_threshold_variation"]),
		"caution_scale": rng.randf_range(1.0 - cfg["caution_variation"], 1.0 + cfg["caution_variation"]),
		"habitat_bias": rng.randf_range(0.72, 1.28),
		"habitat_phase": rng.randf_range(0.0, TAU),
		"food_choice_phase": rng.randf_range(0.0, TAU),
		"personal_space": rng.randf_range(cfg["personal_space_min"], cfg["personal_space_max"]),
		"refuge_position": Vector2.INF,
		"route_waypoints": [],
		"route_target_position": Vector2.INF,
		"route_target_id": -1,
		"route_ford": Vector2.INF,
		"route_distance": 0.0,
		"route_direct_distance": 0.0,
		"route_replan_timer": 0.0,
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
	var velocity: Vector2 = direction * cfg["move_speed"] * 0.35
	foxes[entity_id] = {
		"id": entity_id,
		"type": "fox",
		"position": position,
		"previous_position": position,
		"velocity": velocity,
		"previous_velocity": velocity,
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
		"route_waypoints": [],
		"route_target_position": Vector2.INF,
		"route_target_id": -1,
		"route_ford": Vector2.INF,
		"route_distance": 0.0,
		"route_direct_distance": 0.0,
		"route_replan_timer": 0.0,
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
	var suitability := terrain.food_suitability(plant_type, position)
	plants[entity_id] = {
		"id": entity_id,
		"type": plant_type,
		"position": position,
		"food": float(cfg["max_food"]),
		"max_food": float(cfg["max_food"]),
		"regeneration": float(cfg["regeneration"]),
		"habitat_suitability": suitability,
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

func hunger_summary(kind: String = "rabbit") -> Dictionary:
	var source: Dictionary = rabbits if kind == "rabbit" else foxes
	if kind not in ["rabbit", "fox"]:
		return {}
	var cfg: Dictionary = config[kind]
	var starvation_at := float(cfg["starvation_threshold"])
	var warning_at := float(cfg.get("hunger_warning_at", lerpf(float(cfg.get("hungry_at", cfg.get("hunt_at", 0.0))), starvation_at, 0.55)))
	var warning_count := 0
	var unserved_count := 0
	var starving_count := 0
	var highest_ratio := 0.0
	for entity in source.values():
		var hunger := float(entity["hunger"])
		highest_ratio = maxf(highest_ratio, hunger / starvation_at)
		if hunger < warning_at:
			continue
		warning_count += 1
		var finding_food: bool = entity["behavior"] in ["seek_food", "eat", "hunt"]
		if not finding_food:
			unserved_count += 1
		if hunger >= starvation_at:
			starving_count += 1
	var state := "safe"
	if starving_count > 0:
		state = "starving"
	elif unserved_count > 0:
		state = "warning"
	elif warning_count > 0:
		state = "foraging"
	return {
		"state": state,
		"population": source.size(),
		"warning_count": warning_count,
		"unserved_count": unserved_count,
		"starving_count": starving_count,
		"highest_ratio": highest_ratio,
		"warning_at": warning_at,
		"starvation_at": starvation_at,
	}

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

func ground_route(position: Vector2, target: Vector2, maximum_distance: float = INF) -> Dictionary:
	return terrain.route_between(position, target, world_radius, maximum_distance)

func ground_route_distance(position: Vector2, target: Vector2, maximum_distance: float = INF) -> float:
	return terrain.route_distance(position, target, world_radius, maximum_distance)

func positions_ground_reachable(position: Vector2, target: Vector2, maximum_distance: float = INF) -> bool:
	return bool(ground_route(position, target, maximum_distance)["reachable"])

func terrain_debug(position: Vector2) -> Dictionary:
	var habitat := terrain.habitat_at(position)
	habitat["composition"] = terrain.local_habitat_composition(position)
	habitat["stream_side"] = terrain.stream_side(position)
	return habitat

func step(delta: float) -> void:
	if delta <= 0.0:
		return
	simulation_time += delta
	last_tick_stats = {"queries": 0, "captures": 0, "births": 0}
	_regenerate_plants(delta)
	rebuild_spatial_index()
	_rebuild_rabbit_food_target_claims()
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
		var suitability: float = plant.get("habitat_suitability", terrain.food_suitability(plant["type"], plant["position"]))
		plant["habitat_suitability"] = suitability
		plant["food"] = minf(plant["max_food"], plant["food"] + plant["regeneration"] * suitability * delta)

func _rebuild_rabbit_food_target_claims() -> void:
	rabbit_food_target_claims.clear()
	for rabbit in rabbits.values():
		var target_id: int = rabbit["target_id"]
		if target_id != -1 and plants.has(target_id):
			rabbit_food_target_claims[target_id] = int(rabbit_food_target_claims.get(target_id, 0)) + 1

func _update_rabbit(rabbit: Dictionary, delta: float) -> bool:
	var cfg: Dictionary = config["rabbit"]
	rabbit["previous_position"] = rabbit["position"]
	rabbit["previous_velocity"] = rabbit["velocity"]
	rabbit["age"] += delta
	rabbit["hunger"] += cfg["hunger_rate"] * delta
	rabbit["recent_food"] = maxf(0.0, rabbit["recent_food"] - cfg["recent_food_decay"] * delta)
	rabbit["reproduction_cooldown"] = maxf(0.0, rabbit["reproduction_cooldown"] - delta)
	rabbit["decision_timer"] -= delta
	rabbit["route_replan_timer"] = maxf(0.0, float(rabbit.get("route_replan_timer", 0.0)) - delta)
	var position: Vector2 = rabbit["position"]
	var desired := Vector2.ZERO
	var caution_scale: float = rabbit["caution_scale"]
	var detection_radius: float = cfg["fox_detection_radius"] * caution_scale
	var release_radius: float = cfg["flee_release_radius"] * caution_scale
	var was_fleeing: bool = rabbit["behavior"] == "flee"
	var threat := _best_reachable_threat(position, maxf(detection_radius, release_radius))
	var flee_radius := release_radius if rabbit["behavior"] == "flee" else detection_radius
	if not threat.is_empty() and float(threat["route"]["distance"]) <= flee_radius:
		rabbit["behavior"] = "flee"
		_set_rabbit_target(rabbit, threat["id"])
		var refuge_position: Vector2 = rabbit.get("refuge_position", Vector2.INF)
		var needs_refuge := not was_fleeing or refuge_position == Vector2.INF \
			or not is_position_valid(refuge_position) \
			or terrain.thicket_cover(refuge_position) < float(config["terrain"]["thicket"]["refuge_cover_min"])
		if needs_refuge:
			var refuge := terrain.nearest_reachable_thicket(
				position,
				threat["position"],
				world_radius,
				float(config["terrain"]["thicket"]["refuge_search_radius"]),
			)
			if not refuge.is_empty():
				rabbit["refuge_position"] = refuge["position"]
				_set_ground_route(rabbit, refuge["position"], -1000000 - int(threat["id"]), refuge["route"])
			else:
				rabbit["refuge_position"] = Vector2.INF
				_clear_ground_route(rabbit)
			refuge_position = rabbit["refuge_position"]
		if refuge_position != Vector2.INF:
			desired = _velocity_along_route(rabbit, refuge_position, -1000000 - int(threat["id"]), cfg["flee_speed"] * rabbit["speed_scale"], false)
		if desired.length_squared() < 0.01:
			var away: Vector2 = position - threat["position"]
			if away.length_squared() < 0.01:
				away = Vector2.from_angle(rng.randf_range(0.0, TAU))
			desired = away.normalized() * cfg["flee_speed"] * rabbit["speed_scale"]
	else:
		if rabbit["behavior"] == "flee":
			rabbit["decision_timer"] = 0.0
			rabbit["refuge_position"] = Vector2.INF
			_clear_ground_route(rabbit)
		var hungry_at: float = cfg["hungry_at"] + rabbit["hunger_threshold_offset"]
		if rabbit["food_motivated"]:
			if rabbit["hunger"] <= cfg["sated_at"]:
				rabbit["food_motivated"] = false
		else:
			if rabbit["hunger"] >= hungry_at:
				rabbit["food_motivated"] = true
		var hungry: bool = rabbit["food_motivated"]
		var target_valid := _rabbit_food_target_is_valid(rabbit, cfg["food_detection_radius"] * 1.2)
		var needs_decision: bool = rabbit["decision_timer"] <= 0.0
		needs_decision = needs_decision or (hungry and rabbit["behavior"] == "wander")
		needs_decision = needs_decision or (not hungry and rabbit["behavior"] != "wander")
		needs_decision = needs_decision or (rabbit["behavior"] in ["seek_food", "eat"] and not target_valid)
		if needs_decision:
			rabbit["decision_timer"] = rabbit["decision_interval"]
			if hungry:
				var food := _best_food_target(rabbit, cfg["food_detection_radius"])
				if not food.is_empty():
					rabbit["behavior"] = "seek_food"
					_set_rabbit_target(rabbit, food["id"])
					_set_ground_route(rabbit, food["position"], food["id"], food["route"])
				else:
					rabbit["behavior"] = "forage"
					_set_rabbit_target(rabbit, -1)
					_clear_ground_route(rabbit)
			else:
				rabbit["behavior"] = "wander"
				_set_rabbit_target(rabbit, -1)
				_clear_ground_route(rabbit)
		target_valid = hungry and _rabbit_food_target_is_valid(rabbit, cfg["food_detection_radius"] * 1.2)
		if target_valid:
			var food: Dictionary = plants[rabbit["target_id"]]
			rabbit["behavior"] = "seek_food"
			desired = _velocity_along_route(rabbit, food["position"], food["id"], cfg["move_speed"] * rabbit["speed_scale"], false)
			if position.distance_to(food["position"]) <= cfg["eat_distance"]:
				_consume_plant(rabbit, food, delta)
		else:
			rabbit["behavior"] = "forage" if hungry else "wander"
			_set_rabbit_target(rabbit, -1)
			_clear_ground_route(rabbit)
			desired = _rabbit_wander_velocity(rabbit, cfg["move_speed"], delta)
	var separation_scale: float = 0.24 if rabbit["behavior"] == "flee" else cfg["separation_strength"]
	desired += _rabbit_separation(rabbit) * cfg["move_speed"] * separation_scale
	var habitat_strength: float = 0.12 if rabbit["behavior"] == "flee" else 0.32 * rabbit["habitat_bias"]
	desired += _habitat_steering(position, false, rabbit["habitat_phase"]) * cfg["move_speed"] * habitat_strength
	_move_entity(rabbit, desired, cfg["steering"] * rabbit["turn_scale"], delta)
	return _update_mortality(rabbit, cfg, delta)

func _update_fox(fox: Dictionary, delta: float) -> bool:
	var cfg: Dictionary = config["fox"]
	fox["previous_position"] = fox["position"]
	fox["previous_velocity"] = fox["velocity"]
	fox["age"] += delta
	fox["hunger"] += cfg["hunger_rate"] * delta
	fox["recent_food"] = maxf(0.0, fox["recent_food"] - cfg["recent_food_decay"] * delta)
	fox["reproduction_cooldown"] = maxf(0.0, fox["reproduction_cooldown"] - delta)
	fox["route_replan_timer"] = maxf(0.0, float(fox.get("route_replan_timer", 0.0)) - delta)
	var position: Vector2 = fox["position"]
	var prey: Dictionary = {}
	if fox["target_id"] != -1 and rabbits.has(fox["target_id"]):
		var target_rabbit: Dictionary = rabbits[fox["target_id"]]
		if position.distance_to(target_rabbit["position"]) <= cfg["prey_detection_radius"] * 1.25:
			# Terrain is static and every acquired target was reachable when chosen.
			# Keep following the cached crossing until the moving-target threshold in
			# _velocity_along_route asks for a materially useful replan.
			prey = {"id": fox["target_id"], "position": target_rabbit["position"], "route": {}}
	if prey.is_empty() and fox["hunger"] >= cfg["hunt_at"]:
		prey = _best_reachable_prey(fox, cfg["prey_detection_radius"])
	var desired := Vector2.ZERO
	if not prey.is_empty():
		fox["behavior"] = "hunt"
		if fox["target_id"] != prey["id"]:
			_set_ground_route(fox, prey["position"], prey["id"], prey["route"])
		fox["target_id"] = prey["id"]
		desired = _velocity_along_route(fox, prey["position"], prey["id"], cfg["chase_speed"], true)
		var cover := terrain.thicket_cover(prey["position"])
		var thicket_cfg: Dictionary = config["terrain"]["thicket"]
		var capture_distance: float = cfg["capture_distance"] * lerpf(1.0, float(thicket_cfg["fox_capture_range_factor"]), cover)
		var capture_rate: float = cfg["capture_rate"] * lerpf(1.0, float(thicket_cfg["fox_capture_rate_factor"]), cover)
		if position.distance_to(prey["position"]) <= capture_distance:
			fox["capture_progress"] += capture_rate * delta
			if fox["capture_progress"] >= 1.0 or rng.randf() < capture_rate * delta * 0.18:
				var prey_id: int = prey["id"]
				var prey_position: Vector2 = rabbits[prey_id]["position"] if rabbits.has(prey_id) else prey["position"]
				if kill_rabbit(prey_id, "predation"):
					fox["hunger"] = maxf(0.0, fox["hunger"] - cfg["meal_value"])
					fox["recent_food"] += cfg["meal_value"]
					creature_fed.emit("fox", fox["id"], prey_id)
					predation_succeeded.emit(fox["id"], prey_id, prey_position)
					fox["capture_progress"] = 0.0
				fox["target_id"] = -1
				_clear_ground_route(fox)
				last_tick_stats["captures"] += 1
		else:
			fox["capture_progress"] = maxf(0.0, fox["capture_progress"] - delta * 0.7)
	else:
		fox["behavior"] = "wander"
		fox["target_id"] = -1
		fox["capture_progress"] = 0.0
		_clear_ground_route(fox)
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

func _rabbit_wander_velocity(rabbit: Dictionary, speed: float, delta: float) -> Vector2:
	var cfg: Dictionary = config["rabbit"]
	rabbit["wander_timer"] -= delta
	if rabbit["wander_timer"] <= 0.0:
		rabbit["wander_turn_target"] = rng.randf_range(-cfg["wander_turn_rate"], cfg["wander_turn_rate"])
		rabbit["wander_timer"] = rng.randf_range(cfg["wander_noise_interval_min"], cfg["wander_noise_interval_max"])
	var turn_blend := 1.0 - exp(-cfg["wander_turn_response"] * delta)
	rabbit["wander_angular_velocity"] = lerpf(rabbit["wander_angular_velocity"], rabbit["wander_turn_target"], turn_blend)
	var direction: Vector2 = rabbit["wander_direction"].rotated(rabbit["wander_angular_velocity"] * delta).normalized()
	rabbit["wander_direction"] = direction
	var pace := 0.62 + sin(simulation_time * 0.7 + rabbit["id"] * 1.37) * 0.12
	return direction * speed * rabbit["speed_scale"] * pace

func _habitat_steering(position: Vector2, prefers_forest: bool, sample_phase: float = 0.0) -> Vector2:
	var sample_distance := 34.0
	var steering := Vector2.ZERO
	for index in range(8):
		var direction := Vector2.from_angle(float(index) / 8.0 * TAU + sample_phase)
		var sample := position + direction * sample_distance
		var forestness := terrain_forestness(sample)
		var score := forestness if prefers_forest else 1.0 - forestness
		if not is_position_valid(sample):
			score -= 2.0
		steering += direction * score
	return steering.normalized() if steering.length_squared() > 1.0 else steering

func _move_entity(entity: Dictionary, desired: Vector2, steering: float, delta: float) -> void:
	var position: Vector2 = entity["position"]
	desired *= terrain.ground_speed_factor(str(entity["type"]), position)
	var edge_distance := position.length()
	var edge_radius := boundary_radius_at(position.angle())
	if edge_distance > edge_radius - 42.0:
		var edge_strength := clampf((edge_distance - (edge_radius - 42.0)) / 42.0, 0.0, 1.0)
		desired = desired.lerp(-position.normalized() * maxf(desired.length(), 35.0), edge_strength)
	var velocity: Vector2 = entity["velocity"]
	velocity = velocity.lerp(desired, 1.0 - exp(-steering * delta))
	var next_position := position + velocity * delta
	if not is_inside_world(next_position):
		velocity = velocity.bounce(position.normalized()).lerp(-position.normalized() * velocity.length(), 0.65)
		next_position = position + velocity * delta
		if not is_inside_world(next_position):
			next_position = position
	elif terrain.is_deep_water(next_position):
		var info := terrain.stream_info(next_position)
		var speed := maxf(18.0, velocity.length())
		var desired_direction := desired.normalized() if desired.length_squared() > 0.01 else velocity.normalized()
		var tangent: Vector2 = info.get("tangent", Vector2.RIGHT)
		var escape := terrain.water_escape_direction(position)
		var options: Array[Vector2] = [tangent, -tangent, escape]
		var best_velocity := Vector2.ZERO
		var best_score := -INF
		for option in options:
			var candidate_velocity: Vector2 = option.normalized() * speed
			var candidate := position + candidate_velocity * delta
			if not is_position_valid(candidate):
				continue
			var score := option.normalized().dot(desired_direction)
			if score > best_score:
				best_score = score
				best_velocity = candidate_velocity
		if best_velocity.length_squared() > 0.01:
			velocity = velocity.lerp(best_velocity, 0.78)
			next_position = position + velocity * delta
		if best_velocity.length_squared() <= 0.01 or not is_position_valid(next_position):
			velocity *= 0.25
			next_position = position
	entity["velocity"] = velocity
	entity["position"] = next_position

func _rabbit_food_target_is_valid(rabbit: Dictionary, radius: float) -> bool:
	var target_id: int = rabbit["target_id"]
	if target_id == -1 or not plants.has(target_id):
		return false
	var plant: Dictionary = plants[target_id]
	if plant["food"] <= 0.15 or rabbit["position"].distance_to(plant["position"]) > radius:
		return false
	# Plants and terrain do not move. Once a reachable route is selected, its
	# cached distance remains sufficient for target retention; the waypoint
	# follower handles progress without sampling the Stream twice every tick.
	if int(rabbit.get("route_target_id", -1)) == target_id \
		and Vector2(rabbit.get("route_target_position", Vector2.INF)).is_equal_approx(plant["position"]):
		return float(rabbit.get("route_distance", INF)) <= radius
	return ground_route_distance(rabbit["position"], plant["position"], radius) <= radius

func _set_rabbit_target(rabbit: Dictionary, target_id: int) -> void:
	var previous_id: int = rabbit["target_id"]
	if previous_id == target_id:
		return
	if plants.has(previous_id):
		var remaining: int = int(rabbit_food_target_claims.get(previous_id, 0)) - 1
		if remaining > 0:
			rabbit_food_target_claims[previous_id] = remaining
		else:
			rabbit_food_target_claims.erase(previous_id)
	rabbit["target_id"] = target_id
	if plants.has(target_id):
		rabbit_food_target_claims[target_id] = int(rabbit_food_target_claims.get(target_id, 0)) + 1

func _set_ground_route(entity: Dictionary, target_position: Vector2, target_id: int, existing_route: Dictionary = {}) -> bool:
	var route := existing_route if not existing_route.is_empty() else ground_route(entity["position"], target_position)
	if not bool(route.get("reachable", false)):
		_clear_ground_route(entity)
		return false
	entity["route_waypoints"] = Array(route.get("waypoints", [])).duplicate()
	entity["route_target_position"] = target_position
	entity["route_target_id"] = target_id
	entity["route_ford"] = route.get("ford", Vector2.INF)
	entity["route_distance"] = float(route.get("distance", entity["position"].distance_to(target_position)))
	entity["route_direct_distance"] = float(route.get("direct_distance", entity["position"].distance_to(target_position)))
	entity["route_replan_timer"] = float(config["terrain"]["routing"]["moving_target_replan_interval"])
	return true

func _clear_ground_route(entity: Dictionary) -> void:
	entity["route_waypoints"] = []
	entity["route_target_position"] = Vector2.INF
	entity["route_target_id"] = -1
	entity["route_ford"] = Vector2.INF
	entity["route_distance"] = 0.0
	entity["route_direct_distance"] = 0.0

func _velocity_along_route(entity: Dictionary, target_position: Vector2, target_id: int, speed: float, moving_target: bool) -> Vector2:
	var recorded_position: Vector2 = entity.get("route_target_position", Vector2.INF)
	var needs_route := int(entity.get("route_target_id", -1)) != target_id or recorded_position == Vector2.INF
	if not needs_route and moving_target and float(entity.get("route_replan_timer", 0.0)) <= 0.0:
		needs_route = recorded_position.distance_to(target_position) >= float(config["terrain"]["routing"]["moving_target_replan_distance"])
	if needs_route and not _set_ground_route(entity, target_position, target_id):
		return Vector2.ZERO
	var waypoints: Array = entity.get("route_waypoints", [])
	var reached_distance := float(config["terrain"]["routing"]["waypoint_reached_distance"])
	while not waypoints.is_empty() and entity["position"].distance_to(waypoints[0]) <= reached_distance:
		waypoints.pop_front()
	entity["route_waypoints"] = waypoints
	var movement_target: Vector2 = target_position if waypoints.is_empty() else waypoints[0]
	if entity["position"].distance_squared_to(movement_target) <= 0.01:
		return Vector2.ZERO
	return entity["position"].direction_to(movement_target) * speed

func _best_reachable_threat(position: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for entry in query_nearby("fox", position, radius):
		var route := ground_route(position, entry["position"], radius)
		if not bool(route["reachable"]):
			continue
		if float(route["distance"]) < best_distance:
			best_distance = route["distance"]
			best = {"id": entry["id"], "position": entry["position"], "route": route}
	return best

func _best_reachable_prey(fox: Dictionary, radius: float) -> Dictionary:
	var position: Vector2 = fox["position"]
	var best: Dictionary = {}
	var best_distance := INF
	for entry in query_nearby("rabbit", position, radius):
		var route := ground_route(position, entry["position"], radius)
		if not bool(route["reachable"]):
			continue
		if float(route["distance"]) < best_distance:
			best_distance = route["distance"]
			best = {"id": entry["id"], "position": entry["position"], "route": route}
	return best

func _rabbit_separation(rabbit: Dictionary) -> Vector2:
	var position: Vector2 = rabbit["position"]
	var radius: float = rabbit["personal_space"]
	var steering := Vector2.ZERO
	for entry in query_nearby("rabbit", position, radius):
		var other_id: int = entry["id"]
		if other_id == rabbit["id"]:
			continue
		var away: Vector2 = position - entry["position"]
		var distance := away.length()
		if distance >= radius:
			continue
		if distance < 0.001:
			var low_id: int = mini(rabbit["id"], other_id)
			var high_id: int = maxi(rabbit["id"], other_id)
			away = Vector2.from_angle(fposmod(float(low_id * 92821 + high_id * 68917) * 0.001, TAU))
			if rabbit["id"] > other_id:
				away = -away
		else:
			away /= distance
		var weight := 1.0 - distance / radius
		steering += away * weight * weight
	return steering.normalized() if steering.length_squared() > 1.0 else steering

func _best_food_target(rabbit: Dictionary, radius: float) -> Dictionary:
	var position: Vector2 = rabbit["position"]
	var cfg: Dictionary = config["rabbit"]
	var best: Dictionary = {}
	var best_score := INF
	for entry in query_nearby("plant", position, radius):
		if not plants.has(entry["id"]):
			continue
		var plant: Dictionary = plants[entry["id"]]
		if plant["food"] <= 0.15:
			continue
		var route := ground_route(position, plant["position"], radius)
		if not bool(route["reachable"]):
			continue
		var attraction: float = config["plants"][plant["type"]]["attraction"]
		var claims: int = rabbit_food_target_claims.get(plant["id"], 0)
		if rabbit["target_id"] == plant["id"]:
			claims = maxi(0, claims - 1)
		var personal_bias: float = sin(float(rabbit["id"]) * 12.9898 + float(plant["id"]) * 78.233 + float(rabbit["food_choice_phase"])) * float(cfg["food_choice_variation"])
		var score: float = float(route["distance"]) / attraction + float(claims) * float(cfg["food_crowding_penalty"]) + personal_bias
		if rabbit["target_id"] == plant["id"]:
			score -= cfg["target_commitment_bonus"]
		if score < best_score:
			best_score = score
			best = {"id": entry["id"], "position": plant["position"], "route": route}
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
	creature_fed.emit("rabbit", rabbit["id"], plant["id"])

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
			if _rabbit_is_eligible(rabbits[entry["id"]]) \
				and ground_route_distance(rabbit["position"], entry["position"], cfg["mating_radius"]) <= cfg["mating_radius"]:
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
		if position != Vector2.INF:
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
			if _fox_is_eligible(foxes[entry["id"]]) \
				and ground_route_distance(fox["position"], entry["position"], cfg["mating_radius"]) <= cfg["mating_radius"]:
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
		if position != Vector2.INF:
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
		if plants.has(entry["id"]) and ground_route_distance(position, entry["position"], radius) <= radius:
			total += float(plants[entry["id"]]["food"])
	return total

func _nearby_valid_position(origin: Vector2, distance: float) -> Vector2:
	for attempt in range(16):
		var candidate := origin + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(distance * 0.45, distance)
		if is_position_valid(candidate):
			return candidate
	if is_position_valid(origin):
		return origin
	for ring in range(1, 5):
		for index in range(12):
			var candidate := origin + Vector2.from_angle(float(index) / 12.0 * TAU) * distance * float(ring)
			if is_position_valid(candidate):
				return candidate
	return Vector2.INF

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
		"terrain": terrain_debug(entity["position"]),
		"refuge_position": entity.get("refuge_position", Vector2.INF),
		"route_waypoints": Array(entity.get("route_waypoints", [])).duplicate(),
		"route_ford": entity.get("route_ford", Vector2.INF),
		"route_distance": float(entity.get("route_distance", 0.0)),
		"route_direct_distance": float(entity.get("route_direct_distance", 0.0)),
	}
