class_name EcosystemSimulation
extends RefCounted

const FOX_WOODLAND_ROUTE_BASE := -2000000

const PLANT_ABUNDANT := "abundant"
const PLANT_HEALTHY := "healthy"
const PLANT_SPARSE := "sparse"
const PLANT_DEPLETED := "depleted"
const PLANT_RECOVERING := "recovering"

signal entity_added(kind: String, entity_id: int, reason: String)
signal entity_removed(kind: String, entity_id: int, position: Vector2, cause: String)
signal plant_eaten(plant_id: int, position: Vector2)
signal plant_state_changed(plant_id: int, previous_state: String, new_state: String, position: Vector2)
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
var rabbit_shared_food_vision: Dictionary = {}
var rabbit_social_groups: Dictionary = {}
var fox_prey_target_claims: Dictionary = {}
var reproduction_check_timer := 0.0

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
	rabbit_shared_food_vision.clear()
	rabbit_social_groups.clear()
	fox_prey_target_claims.clear()
	reproduction_check_timer = 0.0
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
		"food_memory": {},
		"forage_failure_time": 0.0,
		"last_fed_position": Vector2.INF,
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
		"personal_space": rng.randf_range(cfg["personal_space_min"], cfg["personal_space_max"]),
		"refuge_position": Vector2.INF,
		"flee_stamina": float(cfg.get("flee_stamina_capacity", 0.0)),
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
		"hunger": 16.0 if reason == "birth" else rng.randf_range(maxf(0.0, float(cfg["hunt_at"]) - 2.0), float(cfg["hunt_at"]) + 8.0),
		"behavior": "wander",
		"target_id": -1,
		"reproduction_cooldown": cfg["newborn_cooldown"] if reason == "birth" else rng.randf_range(12.0, 30.0),
		"alive": true,
		"recent_food": 0.0,
		"wander_direction": direction,
		"wander_timer": rng.randf_range(1.4, 4.2),
		"starvation_time": 0.0,
		"capture_progress": 0.0,
		"sprint_stamina": float(cfg.get("sprint_stamina_capacity", 0.0)),
		"is_sprinting": false,
		"hunt_time": 0.0,
		"failed_pursuits": 0,
		"pursuit_rest_time": 0.0,
		"failed_target_id": -1,
		"failed_target_timer": 0.0,
		"route_waypoints": [],
		"route_target_position": Vector2.INF,
		"route_target_id": -1,
		"route_ford": Vector2.INF,
		"route_distance": 0.0,
		"route_direct_distance": 0.0,
		"route_replan_timer": 0.0,
		"woodland_patrol_position": Vector2.INF,
		"woodland_patrol_timer": 0.0,
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
	var base_max_food := float(cfg["max_food"])
	var capacity_factor := terrain.food_capacity_factor(plant_type, position)
	var effective_max_food := base_max_food * capacity_factor
	plants[entity_id] = {
		"id": entity_id,
		"type": plant_type,
		"position": position,
		"food": effective_max_food,
		"max_food": effective_max_food,
		"base_max_food": base_max_food,
		"habitat_capacity_factor": capacity_factor,
		"regeneration": float(cfg["regeneration"]),
		"habitat_suitability": suitability,
		"ecology_state": PLANT_ABUNDANT,
		"depletion_latched": false,
		"state_changed_at": simulation_time,
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
	_rebuild_rabbit_shared_food_vision()
	_rebuild_rabbit_food_target_claims()
	_rebuild_fox_prey_target_claims()
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
	reproduction_check_timer -= delta
	if reproduction_check_timer <= 0.0:
		_process_rabbit_reproduction()
		_process_fox_reproduction()
		reproduction_check_timer = float(config["simulation"].get("reproduction_check_interval", 1.0))

func _regenerate_plants(delta: float) -> void:
	for plant in plants.values():
		# Direct test/debug state changes and future loading can put biomass below
		# the threshold without passing through _consume_plant.
		_update_plant_ecology_state(plant)
		var suitability: float = plant.get("habitat_suitability", terrain.food_suitability(plant["type"], plant["position"]))
		plant["habitat_suitability"] = suitability
		plant["food"] = minf(plant["max_food"], plant["food"] + plant["regeneration"] * suitability * delta)
		_update_plant_ecology_state(plant)

func plant_stock_ratio(plant: Dictionary) -> float:
	return clampf(float(plant.get("food", 0.0)) / maxf(0.01, float(plant.get("max_food", 0.0))), 0.0, 1.0)

func plant_ecology_state(plant: Dictionary) -> String:
	return str(plant.get("ecology_state", _unlatched_plant_state(plant)))

func plant_is_food_available(plant: Dictionary) -> bool:
	if bool(plant.get("depletion_latched", false)):
		return false
	return float(plant.get("food", 0.0)) + 0.000001 >= float(config["rabbit"].get("minimum_food_bite", 0.45))

func _update_plant_ecology_state(plant: Dictionary) -> void:
	var cfg: Dictionary = config["plants"][plant["type"]]
	var ratio := plant_stock_ratio(plant)
	var depleted_ratio := float(cfg.get("depleted_ratio", 0.10))
	var recovery_ratio := maxf(depleted_ratio, float(cfg.get("recovery_ratio", 0.35)))
	var latched := bool(plant.get("depletion_latched", false))
	if not latched and ratio <= depleted_ratio + 0.000001:
		latched = true
	elif latched and ratio + 0.000001 >= recovery_ratio:
		latched = false
	plant["depletion_latched"] = latched
	var next_state: String
	if latched:
		next_state = PLANT_DEPLETED if ratio < depleted_ratio else PLANT_RECOVERING
	else:
		next_state = _unlatched_plant_state(plant)
	var previous_state := str(plant.get("ecology_state", next_state))
	if previous_state == next_state:
		return
	plant["ecology_state"] = next_state
	plant["state_changed_at"] = simulation_time
	plant_state_changed.emit(plant["id"], previous_state, next_state, plant["position"])

func _unlatched_plant_state(plant: Dictionary) -> String:
	var cfg: Dictionary = config["plants"][plant["type"]]
	var ratio := plant_stock_ratio(plant)
	if ratio >= float(cfg.get("abundant_ratio", 0.70)):
		return PLANT_ABUNDANT
	if ratio >= float(cfg.get("healthy_ratio", 0.35)):
		return PLANT_HEALTHY
	return PLANT_SPARSE

func _rebuild_rabbit_food_target_claims() -> void:
	rabbit_food_target_claims.clear()
	for rabbit in rabbits.values():
		var target_id: int = rabbit["target_id"]
		if target_id != -1 and plants.has(target_id):
			rabbit_food_target_claims[target_id] = int(rabbit_food_target_claims.get(target_id, 0)) + 1

func _rebuild_rabbit_shared_food_vision() -> void:
	rabbit_shared_food_vision.clear()
	rabbit_social_groups.clear()
	if rabbits.is_empty():
		return
	var local_vision: Dictionary = {}
	for rabbit in rabbits.values():
		var visible_food: Dictionary = {}
		for entry in query_nearby("plant", rabbit["position"], float(config["rabbit"]["food_detection_radius"])):
			if plants.has(entry["id"]) and plant_is_food_available(plants[entry["id"]]):
				visible_food[entry["id"]] = true
		local_vision[rabbit["id"]] = visible_food

	var social_radius := float(config["rabbit"].get("social_proximity_radius", 0.0))
	if social_radius <= 0.0:
		for rabbit_id in local_vision:
			rabbit_shared_food_vision[rabbit_id] = local_vision[rabbit_id]
			rabbit_social_groups[rabbit_id] = [rabbit_id]
			_update_rabbit_food_memory(rabbits[rabbit_id], local_vision[rabbit_id])
		return

	var visited: Dictionary = {}
	for seed_rabbit in rabbits.values():
		var seed_id: int = seed_rabbit["id"]
		if visited.has(seed_id):
			continue
		var queue: Array[int] = [seed_id]
		visited[seed_id] = true
		var group: Array[int] = []
		var shared_food: Dictionary = {}
		while not queue.is_empty():
			var current_id: int = queue.pop_front()
			if not rabbits.has(current_id):
				continue
			group.append(current_id)
			for food_id in local_vision[current_id]:
				shared_food[food_id] = true
			for entry in query_nearby("rabbit", rabbits[current_id]["position"], social_radius):
				var neighbor_id: int = entry["id"]
				if not visited.has(neighbor_id):
					visited[neighbor_id] = true
					queue.append(neighbor_id)
		for member_id in group:
			rabbit_shared_food_vision[member_id] = shared_food.duplicate()
			rabbit_social_groups[member_id] = group.duplicate()
			_update_rabbit_food_memory(rabbits[member_id], shared_food)

func _update_rabbit_food_memory(rabbit: Dictionary, visible_food: Dictionary) -> void:
	var memory: Dictionary = rabbit.get("food_memory", {})
	var duration := float(config["rabbit"].get("food_memory_duration", 75.0))
	for food_id in visible_food:
		memory[food_id] = simulation_time
	for food_id in memory.keys():
		if not plants.has(food_id) or simulation_time - float(memory[food_id]) > duration:
			memory.erase(food_id)
	rabbit["food_memory"] = memory

func _rebuild_fox_prey_target_claims() -> void:
	fox_prey_target_claims.clear()
	for fox in foxes.values():
		var target_id := int(fox.get("target_id", -1))
		if target_id != -1 and rabbits.has(target_id):
			fox_prey_target_claims[target_id] = int(fox_prey_target_claims.get(target_id, 0)) + 1

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
	var hunger_risk_pressure := clampf(inverse_lerp(float(cfg["hunger_warning_at"]), float(cfg["starvation_threshold"]), float(rabbit["hunger"])), 0.0, 1.0)
	var starving_threat_factor := float(cfg.get("starving_threat_radius_factor", 1.0))
	detection_radius *= lerpf(1.0, starving_threat_factor, hunger_risk_pressure)
	release_radius *= lerpf(1.0, starving_threat_factor, hunger_risk_pressure)
	var was_fleeing: bool = rabbit["behavior"] == "flee"
	var flee_stamina_capacity := float(cfg.get("flee_stamina_capacity", 0.0))
	if not was_fleeing:
		rabbit["flee_stamina"] = minf(flee_stamina_capacity, float(rabbit.get("flee_stamina", 0.0)) + float(cfg.get("flee_stamina_recovery", 0.0)) * delta)
	var thicket_cfg: Dictionary = config["terrain"]["thicket"]
	var refuge_detection_radius := detection_radius * float(thicket_cfg.get("refuge_threat_detection_factor", 1.0))
	var threat := _best_reachable_threat(position, maxf(release_radius, refuge_detection_radius))
	var flee_radius := release_radius if rabbit["behavior"] == "flee" else detection_radius
	var refuge_position: Vector2 = rabbit.get("refuge_position", Vector2.INF)
	var prepared_refuge: Dictionary = {}
	var should_flee := not threat.is_empty() and float(threat["route"]["distance"]) <= flee_radius
	if not threat.is_empty() and not should_flee and float(threat["route"]["distance"]) <= refuge_detection_radius:
		var retained_refuge := refuge_position != Vector2.INF and is_position_valid(refuge_position) \
			and terrain.thicket_cover(refuge_position) >= float(thicket_cfg["refuge_cover_min"])
		if retained_refuge:
			should_flee = true
		else:
			prepared_refuge = terrain.nearest_reachable_thicket(
				position,
				threat["position"],
				world_radius,
				float(thicket_cfg["refuge_search_radius"]),
			)
			should_flee = not prepared_refuge.is_empty()
	if should_flee:
		rabbit["behavior"] = "flee"
		var active_flee_speed := float(cfg["flee_speed"])
		if float(rabbit.get("flee_stamina", 0.0)) > 0.0:
			var cover := terrain.thicket_cover(position)
			var stamina_drain := lerpf(1.0, float(thicket_cfg.get("rabbit_flee_stamina_drain_factor", 1.0)), cover)
			rabbit["flee_stamina"] = maxf(0.0, float(rabbit["flee_stamina"]) - delta * stamina_drain)
		else:
			active_flee_speed = float(cfg.get("exhausted_flee_speed", cfg["move_speed"]))
		_set_rabbit_target(rabbit, threat["id"])
		var needs_refuge := not was_fleeing or refuge_position == Vector2.INF \
			or not is_position_valid(refuge_position) \
			or terrain.thicket_cover(refuge_position) < float(thicket_cfg["refuge_cover_min"])
		if needs_refuge:
			var refuge := prepared_refuge if not prepared_refuge.is_empty() else terrain.nearest_reachable_thicket(
				position,
				threat["position"],
				world_radius,
				float(thicket_cfg["refuge_search_radius"]),
			)
			if not refuge.is_empty():
				rabbit["refuge_position"] = refuge["position"]
				_set_ground_route(rabbit, refuge["position"], -1000000 - int(threat["id"]), refuge["route"])
			else:
				rabbit["refuge_position"] = Vector2.INF
				_clear_ground_route(rabbit)
			refuge_position = rabbit["refuge_position"]
		if refuge_position != Vector2.INF:
			var refuge_speed: float = active_flee_speed * rabbit["speed_scale"]
			if terrain.thicket_cover(position) >= float(thicket_cfg["refuge_cover_min"]):
				# Once inside, keep evading through deep cover. Routing forever to one
				# exact refuge point made Rabbits bunch up and oscillate there, turning
				# their sanctuary into an easier Fox target. Movement is careful rather
				# than a full open-ground sprint, so successful hunts remain possible.
				var cover_evasion_speed: float = active_flee_speed * rabbit["speed_scale"] \
					* float(thicket_cfg.get("refuge_evasion_speed_factor", 0.82))
				desired = _rabbit_refuge_evasion_velocity(rabbit, threat["position"], cover_evasion_speed)
			else:
				desired = _velocity_along_route(rabbit, refuge_position, -1000000 - int(threat["id"]), refuge_speed, false)
		if desired.length_squared() < 0.01:
			var away: Vector2 = position - threat["position"]
			if away.length_squared() < 0.01:
				away = Vector2.from_angle(rng.randf_range(0.0, TAU))
			desired = away.normalized() * active_flee_speed * rabbit["speed_scale"]
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
		var target_valid := _rabbit_food_target_is_valid(rabbit)
		if hungry and not target_valid:
			rabbit["forage_failure_time"] = float(rabbit.get("forage_failure_time", 0.0)) + delta
		elif target_valid:
			rabbit["forage_failure_time"] = maxf(0.0, float(rabbit.get("forage_failure_time", 0.0)) - delta * 2.0)
		else:
			rabbit["forage_failure_time"] = 0.0
		var needs_decision: bool = rabbit["decision_timer"] <= 0.0
		needs_decision = needs_decision or (hungry and rabbit["behavior"] in ["wander", "forage"] and not target_valid)
		needs_decision = needs_decision or (not hungry and rabbit["behavior"] != "wander")
		needs_decision = needs_decision or (rabbit["behavior"] in ["seek_food", "eat"] and not target_valid)
		if needs_decision:
			rabbit["decision_timer"] = rabbit["decision_interval"]
			if hungry:
				if not target_valid:
					var food := _best_food_target(rabbit, _rabbit_food_candidates(rabbit))
					if not food.is_empty():
						var previous_target_id: int = rabbit["target_id"]
						rabbit["behavior"] = "seek_food"
						_set_rabbit_target(rabbit, food["id"])
						# Food patches and terrain are static. Preserve progress through an
						# existing route when a decision tick keeps the same target; rebuilding
						# it can restore an already-reached bank waypoint and cause oscillation.
						if previous_target_id != int(food["id"]) \
							or int(rabbit.get("route_target_id", -1)) != int(food["id"]):
							_set_ground_route(rabbit, food["position"], food["id"], food["route"])
					else:
						rabbit["behavior"] = "forage"
						_set_rabbit_target(rabbit, -1)
						_clear_ground_route(rabbit)
			else:
				rabbit["behavior"] = "wander"
				_set_rabbit_target(rabbit, -1)
				_clear_ground_route(rabbit)
		target_valid = hungry and _rabbit_food_target_is_valid(rabbit)
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
	# Target routes should visually win over ambient habitat preference. Otherwise
	# the weak Meadow bias can push a Rabbit back into a bank while it is trying
	# to line up with a ford.
	var habitat_strength: float = 0.06 if rabbit["behavior"] in ["flee", "seek_food", "eat", "forage"] else 0.32 * rabbit["habitat_bias"]
	desired += _habitat_steering(position, false, rabbit["habitat_phase"]) * cfg["move_speed"] * habitat_strength
	_move_entity(rabbit, desired, cfg["steering"] * rabbit["turn_scale"], delta)
	return _update_mortality(rabbit, cfg, delta)

func _rabbit_refuge_evasion_velocity(rabbit: Dictionary, threat_position: Vector2, speed: float) -> Vector2:
	var position: Vector2 = rabbit["position"]
	var away := position - threat_position
	if away.length_squared() < 0.01:
		away = Vector2.from_angle(float(rabbit["id"]) * 2.399)
	away = away.normalized()
	var best_direction := away
	var best_score := -INF
	var sample_distance := 19.0
	for index in range(8):
		var offset := (float(index) - 3.5) * PI / 7.0
		var direction := away.rotated(offset)
		var candidate := position + direction * sample_distance
		if not is_position_valid(candidate):
			continue
		var cover := terrain.thicket_cover(candidate)
		var threat_gain := candidate.distance_to(threat_position) - position.distance_to(threat_position)
		var personal_spread := sin(float(rabbit["id"]) * 1.71 + float(index) * 2.13) * 0.7
		var score := cover * 34.0 + threat_gain * 0.72 + direction.dot(away) * 3.0 + personal_spread
		if score > best_score:
			best_score = score
			best_direction = direction
	return best_direction * speed

func _update_fox(fox: Dictionary, delta: float) -> bool:
	var cfg: Dictionary = config["fox"]
	fox["previous_position"] = fox["position"]
	fox["previous_velocity"] = fox["velocity"]
	fox["age"] += delta
	fox["hunger"] += cfg["hunger_rate"] * delta
	fox["recent_food"] = maxf(0.0, fox["recent_food"] - cfg["recent_food_decay"] * delta)
	fox["reproduction_cooldown"] = maxf(0.0, fox["reproduction_cooldown"] - delta)
	fox["route_replan_timer"] = maxf(0.0, float(fox.get("route_replan_timer", 0.0)) - delta)
	fox["woodland_patrol_timer"] = maxf(0.0, float(fox.get("woodland_patrol_timer", 0.0)) - delta)
	fox["failed_target_timer"] = maxf(0.0, float(fox.get("failed_target_timer", 0.0)) - delta)
	fox["pursuit_rest_time"] = maxf(0.0, float(fox.get("pursuit_rest_time", 0.0)) - delta)
	if float(fox["failed_target_timer"]) <= 0.0:
		fox["failed_target_id"] = -1
	var stamina_capacity := float(cfg.get("sprint_stamina_capacity", 0.0))
	if fox["behavior"] != "hunt" or float(fox["pursuit_rest_time"]) > 0.0:
		fox["sprint_stamina"] = minf(stamina_capacity, float(fox.get("sprint_stamina", 0.0)) + float(cfg.get("sprint_stamina_recovery", 0.0)) * delta)
	var position: Vector2 = fox["position"]
	var hunger_pressure := clampf(inverse_lerp(float(cfg["hunt_at"]), float(cfg["starvation_threshold"]), float(fox["hunger"])), 0.0, 1.0)
	var base_search_radius := float(cfg["prey_detection_radius"])
	var emergency_search_radius := minf(world_radius * 2.0, base_search_radius * float(cfg.get("emergency_detection_factor", 1.55)))
	var search_radius := lerpf(base_search_radius, emergency_search_radius, hunger_pressure)
	var prey: Dictionary = {}
	if fox["target_id"] != -1 and rabbits.has(fox["target_id"]):
		var target_rabbit: Dictionary = rabbits[fox["target_id"]]
		if int(fox.get("failed_target_id", -1)) != int(fox["target_id"]) \
			and position.distance_to(target_rabbit["position"]) <= search_radius * 1.25:
			# Terrain is static and every acquired target was reachable when chosen.
			# Keep following the cached crossing until the moving-target threshold in
			# _velocity_along_route asks for a materially useful replan.
			prey = {"id": fox["target_id"], "position": target_rabbit["position"], "route": {}}
	if prey.is_empty() and fox["hunger"] >= cfg["hunt_at"] and float(fox["pursuit_rest_time"]) <= 0.0:
		prey = _best_reachable_prey(fox, search_radius)
	var desired := Vector2.ZERO
	if not prey.is_empty():
		fox["behavior"] = "hunt"
		fox["woodland_patrol_position"] = Vector2.INF
		if fox["target_id"] != prey["id"]:
			fox["hunt_time"] = 0.0
			_set_ground_route(fox, prey["position"], prey["id"], prey["route"])
		_set_fox_target(fox, prey["id"])
		fox["hunt_time"] = float(fox.get("hunt_time", 0.0)) + delta
		var prey_distance := position.distance_to(prey["position"])
		if float(fox["hunt_time"]) >= float(cfg.get("max_pursuit_duration", 20.0)):
			fox["failed_target_id"] = prey["id"]
			fox["failed_pursuits"] = int(fox.get("failed_pursuits", 0)) + 1
			fox["failed_target_timer"] = float(cfg.get("failed_target_memory", 8.0))
			fox["pursuit_rest_time"] = float(cfg.get("pursuit_rest_duration", 3.5))
			fox["hunt_time"] = 0.0
			_set_fox_target(fox, -1)
			_clear_ground_route(fox)
			prey = {}
		else:
			var learning_bonus := minf(
				float(cfg.get("pursuit_learning_max_bonus", 0.0)),
				float(fox.get("failed_pursuits", 0)) * float(cfg.get("pursuit_learning_per_failure", 0.0)),
			)
			var desperation_speed := lerpf(1.0, float(cfg.get("desperation_speed_factor", 1.0)), hunger_pressure) * (1.0 + learning_bonus)
			var chase_speed := float(cfg["chase_speed"]) * desperation_speed
			var sprint_radius := float(cfg.get("sprint_activation_radius", 170.0))
			var stamina_recovery := float(cfg.get("sprint_stamina_recovery", 0.0)) \
				* lerpf(1.0, float(cfg.get("desperation_stamina_recovery_factor", 1.0)), hunger_pressure)
			if prey_distance > sprint_radius:
				fox["is_sprinting"] = false
				fox["sprint_stamina"] = minf(stamina_capacity, float(fox["sprint_stamina"]) + stamina_recovery * delta)
			else:
				if not bool(fox.get("is_sprinting", false)):
					fox["sprint_stamina"] = minf(stamina_capacity, float(fox["sprint_stamina"]) + stamina_recovery * delta)
					if float(fox["sprint_stamina"]) >= float(cfg.get("sprint_restart_stamina", stamina_capacity)):
						fox["is_sprinting"] = true
				if bool(fox.get("is_sprinting", false)):
					chase_speed = float(cfg.get("sprint_speed", chase_speed)) * desperation_speed
					fox["sprint_stamina"] = maxf(0.0, float(fox["sprint_stamina"]) - delta)
					if float(fox["sprint_stamina"]) <= 0.0:
						fox["is_sprinting"] = false
				else:
					chase_speed = float(cfg.get("exhausted_chase_speed", chase_speed)) * desperation_speed
			desired = _velocity_along_route(fox, prey["position"], prey["id"], chase_speed, true)
	if not prey.is_empty():
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
					fox["starvation_time"] = 0.0
					fox["failed_pursuits"] = 0
					fox["sprint_stamina"] = minf(stamina_capacity, float(fox["sprint_stamina"]) + float(cfg.get("meal_stamina_restore", 1.5)))
					fox["is_sprinting"] = false
					creature_fed.emit("fox", fox["id"], prey_id)
					predation_succeeded.emit(fox["id"], prey_id, prey_position)
					fox["capture_progress"] = 0.0
				fox["hunt_time"] = 0.0
				_set_fox_target(fox, -1)
				_clear_ground_route(fox)
				last_tick_stats["captures"] += 1
		else:
			fox["capture_progress"] = maxf(0.0, fox["capture_progress"] - delta * 0.7)
	if prey.is_empty():
		fox["behavior"] = "wander"
		fox["is_sprinting"] = false
		_set_fox_target(fox, -1)
		if float(fox["pursuit_rest_time"]) <= 0.0:
			fox["hunt_time"] = 0.0
		fox["capture_progress"] = 0.0
		if int(fox.get("route_target_id", -1)) >= 0:
			_clear_ground_route(fox)
		desired = _fox_woodland_wander_velocity(fox, cfg, delta)
	var woodland_strength := float(config["terrain"].get("woodland", {}).get("fox_wander_steering_strength", 0.62))
	desired += _habitat_steering(position, true) * cfg["move_speed"] * (0.06 if fox["behavior"] == "hunt" else woodland_strength)
	_move_entity(fox, desired, cfg["steering"], delta)
	return _update_mortality(fox, cfg, delta)

func _fox_woodland_wander_velocity(fox: Dictionary, cfg: Dictionary, delta: float) -> Vector2:
	var wander := _wander_velocity(fox, cfg["move_speed"], delta, true)
	var woodland_cfg: Dictionary = config["terrain"].get("woodland", {})
	var cover_target := float(woodland_cfg.get("fox_patrol_cover_target", 0.58))
	var current_cover := terrain.woodland_cover(fox["position"])
	var patrol_position: Vector2 = fox.get("woodland_patrol_position", Vector2.INF)
	var patrol_route_id := FOX_WOODLAND_ROUTE_BASE - int(fox["id"])
	if current_cover >= cover_target:
		fox["woodland_patrol_position"] = Vector2.INF
		if int(fox.get("route_target_id", -1)) == patrol_route_id:
			_clear_ground_route(fox)
		return wander
	if float(fox.get("woodland_patrol_timer", 0.0)) <= 0.0 or patrol_position == Vector2.INF \
		or not is_position_valid(patrol_position):
		fox["woodland_patrol_timer"] = float(woodland_cfg.get("fox_patrol_replan_interval", 4.5)) * rng.randf_range(0.82, 1.18)
		var patrol := terrain.nearest_reachable_woodland(
			fox["position"],
			world_radius,
			float(woodland_cfg.get("fox_patrol_search_radius", 420.0)),
		)
		if patrol.is_empty():
			fox["woodland_patrol_position"] = Vector2.INF
			if int(fox.get("route_target_id", -1)) == patrol_route_id:
				_clear_ground_route(fox)
			return wander
		patrol_position = patrol["position"]
		fox["woodland_patrol_position"] = patrol_position
		_set_ground_route(fox, patrol_position, patrol_route_id, patrol["route"])
	var routed := _velocity_along_route(fox, patrol_position, patrol_route_id, cfg["move_speed"], false)
	if routed.length_squared() <= 0.01:
		return wander
	return (wander * 0.24 + routed * 0.92).limit_length(float(cfg["move_speed"]))

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

func _rabbit_food_target_is_valid(rabbit: Dictionary) -> bool:
	var target_id: int = rabbit["target_id"]
	if target_id == -1 or not plants.has(target_id):
		return false
	var plant: Dictionary = plants[target_id]
	if not _plant_is_available_to_rabbit(rabbit, plant):
		return false
	# Plants and terrain do not move. Once a reachable route is selected, its
	# cached distance remains sufficient for target retention; the waypoint
	# follower handles progress without sampling the Stream twice every tick.
	if int(rabbit.get("route_target_id", -1)) == target_id \
		and Vector2(rabbit.get("route_target_position", Vector2.INF)).is_equal_approx(plant["position"]):
		return is_finite(float(rabbit.get("route_distance", INF)))
	return bool(ground_route(rabbit["position"], plant["position"]).get("reachable", false))

func _plant_is_available_to_rabbit(rabbit: Dictionary, plant: Dictionary) -> bool:
	if plant_is_food_available(plant):
		return true
	var cfg: Dictionary = config["rabbit"]
	return bool(cfg.get("emergency_grazing", true)) \
		and float(rabbit["hunger"]) >= float(cfg["starvation_threshold"]) \
		and float(plant.get("food", 0.0)) + 0.000001 >= float(cfg.get("minimum_food_bite", 0.45))

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
	var best_score := INF
	var cfg: Dictionary = config["fox"]
	for entry in query_nearby("rabbit", position, radius):
		if int(entry["id"]) == int(fox.get("failed_target_id", -1)) and float(fox.get("failed_target_timer", 0.0)) > 0.0:
			continue
		var route := ground_route(position, entry["position"], radius)
		if not bool(route["reachable"]):
			continue
		var claims := int(fox_prey_target_claims.get(entry["id"], 0))
		if int(fox.get("target_id", -1)) == int(entry["id"]):
			claims = maxi(0, claims - 1)
		var cover := terrain.thicket_cover(entry["position"])
		var score := float(route["distance"]) \
			+ float(claims) * float(cfg.get("prey_competition_penalty", 150.0)) \
			+ cover * float(cfg.get("covered_prey_penalty", 52.0))
		if score < best_score:
			best_score = score
			best = {"id": entry["id"], "position": entry["position"], "route": route}
	return best

func _set_fox_target(fox: Dictionary, target_id: int) -> void:
	var previous_id := int(fox.get("target_id", -1))
	if previous_id == target_id:
		return
	if previous_id != -1:
		var remaining := int(fox_prey_target_claims.get(previous_id, 0)) - 1
		if remaining > 0:
			fox_prey_target_claims[previous_id] = remaining
		else:
			fox_prey_target_claims.erase(previous_id)
	fox["target_id"] = target_id
	if target_id != -1 and rabbits.has(target_id):
		fox_prey_target_claims[target_id] = int(fox_prey_target_claims.get(target_id, 0)) + 1

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

func _rabbit_food_candidates(rabbit: Dictionary) -> Dictionary:
	var candidates: Dictionary = Dictionary(rabbit_shared_food_vision.get(rabbit["id"], {})).duplicate()
	var cfg: Dictionary = config["rabbit"]
	var failure_time := float(rabbit.get("forage_failure_time", 0.0))
	var emergency_at := float(cfg.get("emergency_search_after", 3.0))
	var is_critical := float(rabbit["hunger"]) >= float(cfg["starvation_threshold"])
	if failure_time < emergency_at and not is_critical:
		return candidates
	for food_id in Dictionary(rabbit.get("food_memory", {})):
		if plants.has(food_id) and _plant_is_available_to_rabbit(rabbit, plants[food_id]):
			candidates[food_id] = true
	var radius_factor := float(cfg.get("critical_search_radius_factor", 4.0)) if is_critical \
		else float(cfg.get("emergency_search_radius_factor", 2.6))
	var search_radius := minf(world_radius * 2.0, float(cfg["food_detection_radius"]) * radius_factor)
	for entry in query_nearby("plant", rabbit["position"], search_radius):
		if plants.has(entry["id"]) and _plant_is_available_to_rabbit(rabbit, plants[entry["id"]]):
			candidates[entry["id"]] = true
	return candidates

func _best_food_target(rabbit: Dictionary, visible_food: Dictionary) -> Dictionary:
	var position: Vector2 = rabbit["position"]
	var cfg: Dictionary = config["rabbit"]
	var best: Dictionary = {}
	var best_score := INF
	for food_id in visible_food:
		if not plants.has(food_id):
			continue
		var plant: Dictionary = plants[food_id]
		if not _plant_is_available_to_rabbit(rabbit, plant):
			continue
		var route := ground_route(position, plant["position"])
		if not bool(route["reachable"]):
			continue
		var claims: int = rabbit_food_target_claims.get(plant["id"], 0)
		if rabbit["target_id"] == plant["id"]:
			claims = maxi(0, claims - 1)
		# Distance remains the leading signal, while fuller patches and existing
		# diners prevent the colony from repeatedly draining the same nearest scrap.
		var stock_bonus := plant_stock_ratio(plant) * float(cfg.get("food_stock_preference", 38.0))
		var score: float = float(route["distance"]) \
			+ float(claims) * float(cfg["food_crowding_penalty"]) - stock_bonus
		if score < best_score:
			best_score = score
			best = {"id": plant["id"], "position": plant["position"], "route": route}
	return best


func _consume_plant(rabbit: Dictionary, plant: Dictionary, delta: float) -> void:
	var cfg: Dictionary = config["rabbit"]
	var amount := minf(plant["food"], cfg["eat_rate"] * delta)
	if amount <= 0.0:
		return
	plant["food"] -= amount
	_update_plant_ecology_state(plant)
	rabbit["hunger"] = maxf(0.0, rabbit["hunger"] - amount * cfg["food_value"])
	rabbit["recent_food"] += amount * cfg["food_value"]
	rabbit["starvation_time"] = maxf(0.0, float(rabbit["starvation_time"]) - amount * float(cfg.get("feeding_starvation_relief", 1.5)))
	rabbit["forage_failure_time"] = 0.0
	rabbit["last_fed_position"] = plant["position"]
	var memory: Dictionary = rabbit.get("food_memory", {})
	memory[plant["id"]] = simulation_time
	rabbit["food_memory"] = memory
	rabbit["behavior"] = "eat"
	plant_eaten.emit(plant["id"], plant["position"])
	creature_fed.emit("rabbit", rabbit["id"], plant["id"])

func _update_mortality(entity: Dictionary, cfg: Dictionary, delta: float) -> bool:
	if entity["hunger"] >= cfg["starvation_threshold"]:
		entity["starvation_time"] += delta
	else:
		entity["starvation_time"] = maxf(0.0, entity["starvation_time"] - delta * float(cfg.get("starvation_recovery_rate", 0.45)))
	return entity["starvation_time"] >= cfg["starvation_duration"] or entity["age"] >= entity["lifespan"]

func _process_rabbit_reproduction() -> void:
	var cfg: Dictionary = config["rabbit"]
	if rabbits.size() >= int(cfg["max_population"]):
		return
	var paired: Dictionary = {}
	var births: Array[Vector2] = []
	for entity_id in rabbits.keys():
		if paired.has(entity_id) or not _rabbit_is_eligible(rabbits[entity_id]):
			continue
		var rabbit: Dictionary = rabbits[entity_id]
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
		var mate: Dictionary = rabbits[mate_id]
		var midpoint: Vector2 = (rabbit["position"] + mate["position"]) * 0.5
		var litter := rng.randi_range(int(cfg["birth_litter_min"]), int(cfg["birth_litter_max"]))
		if not _local_forage_can_support_births(midpoint, litter, births):
			continue
		var child_positions: Array[Vector2] = []
		for child_index in range(litter):
			if rabbits.size() + births.size() + child_positions.size() >= int(cfg["max_population"]):
				break
			var child_position := _nearby_valid_position(midpoint, 10.0 + child_index * 4.0)
			if child_position != Vector2.INF:
				child_positions.append(child_position)
		if child_positions.is_empty():
			continue
		var biomass_cost := float(cfg.get("reproduction_biomass_cost", 0.0)) * float(child_positions.size())
		if _consume_local_biomass(midpoint, float(cfg.get("reproduction_resource_radius", cfg["mating_radius"])), biomass_cost) + 0.000001 < biomass_cost:
			continue
		paired[entity_id] = true
		paired[mate_id] = true
		rabbit["reproduction_cooldown"] = cfg["reproduction_cooldown"]
		mate["reproduction_cooldown"] = cfg["reproduction_cooldown"]
		var energy_cost := float(cfg.get("reproduction_parent_energy_cost", 0.0))
		var hunger_cost := float(cfg.get("reproduction_parent_hunger_cost", 0.0))
		for parent in [rabbit, mate]:
			parent["recent_food"] = maxf(0.0, float(parent["recent_food"]) - energy_cost)
			parent["hunger"] = minf(float(cfg["starvation_threshold"]), float(parent["hunger"]) + hunger_cost)
		births.append_array(child_positions)
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
		var midpoint: Vector2 = (fox["position"] + foxes[mate_id]["position"]) * 0.5
		var resource_radius := float(cfg.get("reproduction_resource_radius", cfg["mating_radius"]))
		var local_prey := _local_reachable_count("rabbit", midpoint, resource_radius)
		var local_foxes := _local_reachable_count("fox", midpoint, resource_radius)
		var pending_local := 0
		for birth_position in births:
			if midpoint.distance_to(birth_position) <= resource_radius:
				pending_local += 1
		var required_prey := float(local_foxes + pending_local + 1) * float(cfg.get("reproduction_prey_per_fox", 0.0))
		if float(local_prey) < required_prey:
			continue
		paired[entity_id] = true
		paired[mate_id] = true
		fox["reproduction_cooldown"] = cfg["reproduction_cooldown"]
		foxes[mate_id]["reproduction_cooldown"] = cfg["reproduction_cooldown"]
		fox["recent_food"] *= 0.25
		foxes[mate_id]["recent_food"] *= 0.25
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

func _local_forage_can_support_births(position: Vector2, birth_count: int, pending_births: Array[Vector2]) -> bool:
	var cfg: Dictionary = config["rabbit"]
	var radius := float(cfg.get("reproduction_resource_radius", cfg["mating_radius"]))
	var budget := local_forage_budget(position, radius)
	if float(budget["available_food"]) < maxf(float(cfg["local_food_needed"]), float(cfg.get("reproduction_biomass_cost", 0.0)) * birth_count):
		return false
	if float(budget["stock_ratio"]) < float(cfg.get("reproduction_min_stock_ratio", 0.0)):
		return false
	var pending_local := 0
	for birth_position in pending_births:
		if position.distance_to(birth_position) <= radius:
			pending_local += 1
	var projected_demand := int(budget["rabbit_count"]) + pending_local + birth_count
	if projected_demand > int(floor(float(budget["sustainable_rabbits"]))):
		return false
	# Local ranges overlap, so a colony split between two patches could otherwise
	# count the same forage twice and still overshoot the meadow as a whole.
	var ecosystem_budget := ecosystem_forage_budget()
	var projected_population := rabbits.size() + pending_births.size() + birth_count
	return float(ecosystem_budget["stock_ratio"]) >= float(cfg.get("reproduction_min_stock_ratio", 0.0)) \
		and projected_population <= int(floor(float(ecosystem_budget["sustainable_rabbits"])))

func ecosystem_forage_budget() -> Dictionary:
	var total_food := 0.0
	var total_capacity := 0.0
	var renewable_biomass_per_second := 0.0
	for plant in plants.values():
		total_food += float(plant["food"])
		total_capacity += float(plant["max_food"])
		renewable_biomass_per_second += float(plant["regeneration"]) * float(plant.get("habitat_suitability", 1.0))
	var cfg: Dictionary = config["rabbit"]
	var sustainable_rabbits := renewable_biomass_per_second * float(cfg["food_value"]) \
		/ maxf(0.001, float(cfg["hunger_rate"])) * float(cfg.get("reproduction_capacity_utilization", 1.0))
	return {
		"total_food": total_food,
		"total_capacity": total_capacity,
		"stock_ratio": total_food / total_capacity if total_capacity > 0.0 else 0.0,
		"renewable_biomass_per_second": renewable_biomass_per_second,
		"sustainable_rabbits": sustainable_rabbits,
		"rabbit_count": rabbits.size(),
	}

func local_forage_budget(position: Vector2, radius: float) -> Dictionary:
	var available_food := 0.0
	var total_food := 0.0
	var total_capacity := 0.0
	var renewable_biomass_per_second := 0.0
	for entry in query_nearby("plant", position, radius):
		if not plants.has(entry["id"]):
			continue
		var plant: Dictionary = plants[entry["id"]]
		if ground_route_distance(position, plant["position"], radius) > radius:
			continue
		total_food += float(plant["food"])
		total_capacity += float(plant["max_food"])
		if plant_is_food_available(plant):
			available_food += float(plant["food"])
		renewable_biomass_per_second += float(plant["regeneration"]) * float(plant.get("habitat_suitability", 1.0))
	var rabbit_count := _local_reachable_count("rabbit", position, radius)
	var cfg: Dictionary = config["rabbit"]
	var sustainable_rabbits := renewable_biomass_per_second * float(cfg["food_value"]) \
		/ maxf(0.001, float(cfg["hunger_rate"])) * float(cfg.get("reproduction_capacity_utilization", 1.0))
	return {
		"available_food": available_food,
		"total_food": total_food,
		"total_capacity": total_capacity,
		"stock_ratio": total_food / total_capacity if total_capacity > 0.0 else 0.0,
		"renewable_biomass_per_second": renewable_biomass_per_second,
		"sustainable_rabbits": sustainable_rabbits,
		"rabbit_count": rabbit_count,
	}

func _local_reachable_count(kind: String, position: Vector2, radius: float) -> int:
	var count := 0
	for entry in query_nearby(kind, position, radius):
		if ground_route_distance(position, entry["position"], radius) <= radius:
			count += 1
	return count

func _consume_local_biomass(position: Vector2, radius: float, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var remaining := amount
	var candidates: Array[Dictionary] = []
	for entry in query_nearby("plant", position, radius):
		if not plants.has(entry["id"]):
			continue
		var plant: Dictionary = plants[entry["id"]]
		if plant_is_food_available(plant) and ground_route_distance(position, plant["position"], radius) <= radius:
			candidates.append(plant)
	while remaining > 0.000001 and not candidates.is_empty():
		var best_index := 0
		var best_ratio := -1.0
		for index in range(candidates.size()):
			var ratio := plant_stock_ratio(candidates[index])
			if ratio > best_ratio:
				best_ratio = ratio
				best_index = index
		var plant: Dictionary = candidates[best_index]
		var consumed := minf(remaining, float(plant["food"]))
		plant["food"] -= consumed
		remaining -= consumed
		_update_plant_ecology_state(plant)
		plant_eaten.emit(plant["id"], plant["position"])
		candidates.remove_at(best_index)
	return amount - remaining

func _local_available_food(position: Vector2, radius: float) -> float:
	var total := 0.0
	for entry in query_nearby("plant", position, radius):
		if plants.has(entry["id"]):
			var plant: Dictionary = plants[entry["id"]]
			if plant_is_food_available(plant) and ground_route_distance(position, entry["position"], radius) <= radius:
				total += float(plant["food"])
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
		var local_food := 0
		for entry in query_nearby("plant", entity["position"], config["rabbit"]["food_detection_radius"]):
			if plants.has(entry["id"]) and plant_is_food_available(plants[entry["id"]]):
				local_food += 1
		var shared_food: Dictionary = rabbit_shared_food_vision.get(entity_id, {})
		var social_group: Array = rabbit_social_groups.get(entity_id, [entity_id])
		nearby = {
			"food": local_food,
			"shared_food": shared_food.size(),
			"social_group": social_group.size(),
			"predators": query_nearby("fox", entity["position"], config["rabbit"]["fox_detection_radius"]).size(),
		}
	else:
		nearby = {"prey": query_nearby("rabbit", entity["position"], config["fox"]["prey_detection_radius"]).size()}
	return {
		"id": entity["id"],
		"type": kind,
		"hunger": entity["hunger"],
		"starvation_time": entity["starvation_time"],
		"age": entity["age"],
		"behavior": entity["behavior"],
		"target_id": entity["target_id"],
		"reproduction_cooldown": entity["reproduction_cooldown"],
		"flee_stamina": float(entity.get("flee_stamina", 0.0)),
		"sprint_stamina": float(entity.get("sprint_stamina", 0.0)),
		"failed_pursuits": int(entity.get("failed_pursuits", 0)),
		"nearby": nearby,
		"terrain": terrain_debug(entity["position"]),
		"refuge_position": entity.get("refuge_position", Vector2.INF),
		"route_waypoints": Array(entity.get("route_waypoints", [])).duplicate(),
		"route_ford": entity.get("route_ford", Vector2.INF),
		"route_distance": float(entity.get("route_distance", 0.0)),
		"route_direct_distance": float(entity.get("route_direct_distance", 0.0)),
	}
