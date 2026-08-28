extends SceneTree

const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")
const Systems = preload("res://game/game_systems.gd")

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_test_seeded_generation_and_playable_mix()
	_test_stream_and_expansion_are_coherent()
	_test_deep_water_placement_is_rejected()
	_test_food_suitability_matches_terrain_roles()
	_test_land_cover_preferences_and_hunt_override()
	_test_rabbit_selects_reachable_thicket()
	_test_thicket_disrupts_but_does_not_disable_hunting()
	_test_food_route_uses_a_ford()
	_test_fox_route_uses_a_ford()
	_test_water_separates_threats_mates_and_food()
	_test_safe_havens_require_reachable_food()
	_test_newborn_search_never_returns_deep_water()
	_test_route_queries_fit_prototype_budget()
	print("\n%d V0.4 terrain tests passed; %d failed." % [passed, failures.size()])
	for failure in failures:
		printerr("FAILED: %s" % failure)
	quit(1 if not failures.is_empty() else 0)

func _expect(condition: bool, name: String, detail: String = "") -> void:
	if condition:
		passed += 1
		print("PASS: %s" % name)
	else:
		failures.append("%s%s" % [name, " — " + detail if not detail.is_empty() else ""])

func _test_seeded_generation_and_playable_mix() -> void:
	var first = Simulation.new(Config.make().duplicate(true), 240817)
	var second = Simulation.new(Config.make().duplicate(true), 240817)
	var first_summary: Dictionary = first.terrain.generation_summary(first.world_radius)
	var samples: Dictionary = first_summary["samples"]
	var reproducible: bool = first.terrain.woodland_patches == second.terrain.woodland_patches \
		and first.terrain.thicket_patches == second.terrain.thicket_patches \
		and first.terrain.stream_points == second.terrain.stream_points \
		and first.terrain.fords == second.terrain.fords
	var playable_mix := int(samples["meadow"]) > 0 and int(samples["woodland"]) > 0 \
		and int(samples["thicket"]) > 0 and int(samples["stream"]) > 0 \
		and int(first_summary["visible_fords"]) >= 1
	_expect(reproducible and playable_mix, "same seed reproduces a playable four-environment landscape", str(first_summary))

func _test_stream_and_expansion_are_coherent() -> void:
	var sim = Simulation.new(Config.make().duplicate(true), 240817)
	var points_before: PackedVector2Array = sim.terrain.stream_points.duplicate()
	var fords_before: Array = sim.terrain.fords.duplicate(true)
	var initial_summary: Dictionary = sim.terrain.generation_summary(sim.world_radius)
	var crossed_maximum: bool = sim.terrain.stream_points[0].length() > sim.config["world"]["maximum_radius"] \
		and sim.terrain.stream_points[-1].length() > sim.config["world"]["maximum_radius"]
	sim.expand_world(435.0)
	var expanded_summary: Dictionary = sim.terrain.generation_summary(sim.world_radius)
	var continuation: bool = sim.terrain.stream_points == points_before and sim.terrain.fords == fords_before \
		and int(expanded_summary["visible_fords"]) >= int(initial_summary["visible_fords"])
	_expect(crossed_maximum and continuation, "one seeded Stream crosses the maximum world and expansion reveals its continuation")

func _test_deep_water_placement_is_rejected() -> void:
	var systems = Systems.new(Config.make().duplicate(true))
	var deep := _deep_stream_point(systems.simulation)
	var rabbit_before: int = systems.inventory["rabbit"]
	var carrot_before: int = systems.inventory["carrot_patch"]
	var rabbit_result := systems.place_item("rabbit", deep)
	var carrot_result := systems.place_item("carrot_patch", deep)
	var bank := _bank_point(systems.simulation, deep, 30.0)
	var bank_result := systems.place_item("carrot_patch", bank)
	_expect(rabbit_result == -1 and carrot_result == -1 \
		and systems.inventory["rabbit"] == rabbit_before \
		and systems.inventory["carrot_patch"] == carrot_before - 1 \
		and bank_result != -1, "deep-water placement is rejected without inventory loss while bank placement works", "%s / %s" % [str(deep), str(bank)])

func _test_food_suitability_matches_terrain_roles() -> void:
	var sim = Simulation.new(Config.make().duplicate(true))
	var meadow := _find_best_food_point(sim, "carrot_patch")
	var margin := _find_best_food_point(sim, "berry_bush")
	var carrots_meadow: float = sim.terrain.food_suitability("carrot_patch", meadow)
	var carrots_margin: float = sim.terrain.food_suitability("carrot_patch", margin)
	var berries_meadow: float = sim.terrain.food_suitability("berry_bush", meadow)
	var berries_margin: float = sim.terrain.food_suitability("berry_bush", margin)
	_expect(carrots_meadow > carrots_margin and berries_margin > berries_meadow, "Carrot Patch favors Meadow while Berry Bush favors sheltered margins", "carrot %.2f/%.2f berry %.2f/%.2f" % [carrots_meadow, carrots_margin, berries_meadow, berries_margin])

func _test_land_cover_preferences_and_hunt_override() -> void:
	var sim = Simulation.new(_controlled_land_config(), 1904)
	_add_controlled_woodland(sim, Vector2(48.0, 0.0), 45.0)
	var rabbit_steering: Vector2 = sim._habitat_steering(Vector2.ZERO, false, 0.0)
	var fox_steering: Vector2 = sim._habitat_steering(Vector2.ZERO, true, 0.0)
	var fox_id: int = sim.add_fox(Vector2.ZERO)
	var rabbit_id: int = sim.add_rabbit(Vector2(-90.0, 0.0))
	sim.foxes[fox_id]["hunger"] = 60.0
	sim.step(0.1)
	var fox: Dictionary = sim.foxes[fox_id]
	var readable_roles: bool = rabbit_steering.x < -0.2 and fox_steering.x > 0.2 \
		and fox["behavior"] == "hunt" and fox["target_id"] == rabbit_id and fox["velocity"].x < 0.0
	_expect(readable_roles, "Rabbits retain an open-land bias, Foxes retain a Woodland bias, and active pursuit overrides wandering habitat", "steering %.2f/%.2f chase %.2f" % [rabbit_steering.x, fox_steering.x, fox["velocity"].x])

func _test_rabbit_selects_reachable_thicket() -> void:
	var config := _controlled_land_config()
	var sim = Simulation.new(config, 4412)
	_add_controlled_thicket(sim, Vector2(78.0, 0.0), 62.0)
	var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
	var fox_id: int = sim.add_fox(Vector2(-34.0, 0.0))
	sim.foxes[fox_id]["hunger"] = 50.0
	sim.step(0.1)
	var rabbit: Dictionary = sim.rabbits[rabbit_id]
	var chose_cover: bool = rabbit["behavior"] == "flee" and rabbit["refuge_position"] != Vector2.INF \
		and rabbit["velocity"].x > 0.0 and sim.terrain.thicket_cover(rabbit["refuge_position"]) > 0.5
	_expect(chose_cover, "a threatened Rabbit visibly chooses reachable Thicket away from the Fox", str(rabbit["refuge_position"]))

func _test_thicket_disrupts_but_does_not_disable_hunting() -> void:
	var open_config := _controlled_land_config()
	open_config["rabbit"]["flee_speed"] = 0.0
	open_config["fox"]["capture_rate"] = 3.0
	var cover_config := open_config.duplicate(true)
	var open_sim = Simulation.new(open_config, 712)
	var cover_sim = Simulation.new(cover_config, 712)
	_add_controlled_thicket(cover_sim, Vector2.ZERO, 72.0)
	for sim in [open_sim, cover_sim]:
		var rabbit_id: int = sim.add_rabbit(Vector2.ZERO)
		var fox_id: int = sim.add_fox(Vector2(7.0, 0.0))
		sim.rabbits[rabbit_id]["velocity"] = Vector2.ZERO
		sim.foxes[fox_id]["hunger"] = 60.0
	for tick in range(2):
		open_sim.step(0.1)
		cover_sim.step(0.1)
	var open_progress: float = open_sim.foxes.values()[0]["capture_progress"] if not open_sim.foxes.is_empty() else 1.0
	var cover_progress: float = cover_sim.foxes.values()[0]["capture_progress"] if not cover_sim.foxes.is_empty() else 1.0
	var disrupted := cover_progress < open_progress
	for tick in range(80):
		if cover_sim.rabbits.is_empty():
			break
		cover_sim.step(0.1)
	_expect(disrupted and cover_sim.rabbits.is_empty(), "Thicket slows capture buildup but does not make Rabbits invulnerable", "open %.2f cover %.2f" % [open_progress, cover_progress])

func _test_food_route_uses_a_ford() -> void:
	var config := Config.make().duplicate(true)
	config["rabbit"]["food_detection_radius"] = 260.0
	var sim = Simulation.new(config)
	var setup: Dictionary = _across_ford_setup(sim)
	var rabbit_id: int = sim.add_rabbit(setup["start"])
	var plant_id: int = sim.add_plant("carrot_patch", setup["target"])
	sim.rabbits[rabbit_id]["hunger"] = 58.0
	sim.step(0.1)
	var rabbit: Dictionary = sim.rabbits[rabbit_id]
	var routed: bool = rabbit["target_id"] == plant_id and rabbit["route_ford"] != Vector2.INF \
		and not rabbit["route_waypoints"].is_empty() and float(rabbit["route_distance"]) > float(rabbit["route_direct_distance"])
	var stayed_dry := true
	var starting_distance: float = setup["start"].distance_to(setup["target"])
	var closest_distance := starting_distance
	for tick in range(160):
		sim.step(0.1)
		closest_distance = minf(closest_distance, sim.rabbits[rabbit_id]["position"].distance_to(setup["target"]))
		if sim.terrain.is_deep_water(sim.rabbits[rabbit_id]["position"]):
			stayed_dry = false
			break
	var final_rabbit: Dictionary = sim.rabbits[rabbit_id]
	_expect(routed and stayed_dry and closest_distance < starting_distance * 0.45, "Rabbit food selection makes route progress through a ford and never crosses deep water directly", "%s, %.1f -> %.1f, start %s, %s at %s v%s via %s" % [str(rabbit["route_ford"]), starting_distance, closest_distance, str(setup["start"]), final_rabbit["behavior"], str(final_rabbit["position"]), str(final_rabbit["velocity"]), str(final_rabbit["route_waypoints"])])

func _test_fox_route_uses_a_ford() -> void:
	var config := Config.make().duplicate(true)
	config["fox"]["prey_detection_radius"] = 310.0
	config["rabbit"]["flee_speed"] = 0.0
	var sim = Simulation.new(config)
	var setup: Dictionary = _across_ford_setup(sim)
	var fox_id: int = sim.add_fox(setup["start"])
	var rabbit_id: int = sim.add_rabbit(setup["target"])
	sim.foxes[fox_id]["hunger"] = 60.0
	sim.step(0.1)
	var fox: Dictionary = sim.foxes[fox_id]
	var routed: bool = fox["target_id"] == rabbit_id and fox["route_ford"] != Vector2.INF and not fox["route_waypoints"].is_empty()
	var stayed_dry := true
	var starting_distance: float = setup["start"].distance_to(setup["target"])
	var closest_distance := starting_distance
	for tick in range(120):
		if not sim.foxes.has(fox_id):
			break
		sim.step(0.1)
		closest_distance = minf(closest_distance, sim.foxes[fox_id]["position"].distance_to(setup["target"]))
		if sim.terrain.is_deep_water(sim.foxes[fox_id]["position"]):
			stayed_dry = false
			break
	_expect(routed and stayed_dry and closest_distance < starting_distance * 0.45, "Fox pursuit makes route progress through a ford without bank oscillation or deep-water entry", "%.1f -> %.1f" % [starting_distance, closest_distance])

func _test_water_separates_threats_mates_and_food() -> void:
	var config := Config.make().duplicate(true)
	config["rabbit"]["mating_radius"] = 105.0
	config["rabbit"]["food_detection_radius"] = 115.0
	config["rabbit"]["local_food_needed"] = 5.0
	var sim = Simulation.new(config)
	var deep := _deep_stream_point(sim)
	var info: Dictionary = sim.terrain.stream_info(deep)
	var normal: Vector2 = info["normal"]
	var offset: float = info["half_width"] + 13.0
	var first_position := deep + normal * offset
	var second_position := deep - normal * offset
	var first_id: int = sim.add_rabbit(first_position)
	var second_id: int = sim.add_rabbit(second_position)
	var fox_id: int = sim.add_fox(second_position + normal * -8.0)
	var plant_id: int = sim.add_plant("berry_bush", second_position)
	for rabbit_id in [first_id, second_id]:
		var rabbit: Dictionary = sim.rabbits[rabbit_id]
		rabbit["age"] = 30.0
		rabbit["hunger"] = 0.0
		rabbit["recent_food"] = 100.0
		rabbit["reproduction_cooldown"] = 0.0
	sim.foxes[fox_id]["hunger"] = 0.0
	sim.step(0.1)
	var first: Dictionary = sim.rabbits[first_id]
	var route_distance := sim.ground_route_distance(first_position, second_position, 115.0)
	var separated: bool = route_distance > 115.0 and first["behavior"] != "flee" \
		and first["target_id"] != plant_id and sim.rabbits.size() == 2
	_expect(separated, "deep water blocks false threat, mate, and local-food proximity", "route %s behavior %s" % [str(route_distance), str(first["behavior"])])

func _test_safe_havens_require_reachable_food() -> void:
	var systems = Systems.new(Config.make().duplicate(true))
	var sim = systems.simulation
	sim.expand_world(435.0)
	var indices := [16, 32]
	var land_centers: Array[Vector2] = []
	var land_normals: Array[Vector2] = []
	var land_tangents: Array[Vector2] = []
	for index in indices:
		var stream_point: Vector2 = sim.terrain.stream_points[index]
		var info: Dictionary = sim.terrain.stream_info(stream_point)
		var normal: Vector2 = info["normal"]
		var tangent: Vector2 = info["tangent"]
		var bank_distance: float = info["half_width"] + 16.0
		var land_center := stream_point + normal * bank_distance
		var across_center := stream_point - normal * bank_distance
		land_centers.append(land_center)
		land_normals.append(normal)
		land_tangents.append(tangent)
		sim.add_rabbit(land_center + tangent * 8.0)
		sim.add_rabbit(land_center - tangent * 8.0)
		sim.add_plant("berry_bush", across_center)
	var inaccessible: Dictionary = systems.run_director.spatial_evidence(sim)
	for index in range(land_centers.size()):
		# Habitat-adjusted capacity can put one poor-site bush below a haven's
		# minimum biomass. Two nearby bushes keep this a reachability test rather
		# than accidentally testing habitat productivity as well.
		sim.add_plant("berry_bush", land_centers[index] + land_normals[index] * 18.0 + land_tangents[index] * 18.0)
		sim.add_plant("berry_bush", land_centers[index] + land_normals[index] * 18.0 - land_tangents[index] * 18.0)
	var reachable: Dictionary = systems.run_director.spatial_evidence(sim)
	_expect(not bool(inaccessible["met"]) and bool(reachable["met"]), "Safe Haven evidence ignores nearby food across deep water and accepts reachable bank-side food", "%s -> %s" % [str(inaccessible), str(reachable)])

func _test_newborn_search_never_returns_deep_water() -> void:
	var sim = Simulation.new(Config.make().duplicate(true))
	var deep := _deep_stream_point(sim)
	var result: Vector2 = sim._nearby_valid_position(deep, 16.0)
	_expect(result != Vector2.INF and not sim.terrain.is_deep_water(result), "newborn placement search always resolves onto traversable ground", str(result))

func _test_route_queries_fit_prototype_budget() -> void:
	var sim = Simulation.new(Config.make().duplicate(true))
	var points: Array[Vector2] = []
	for index in range(120):
		var point := Vector2.from_angle(float(index) * 2.399) * (80.0 + float(index % 11) * 38.0)
		if sim.is_position_valid(point):
			points.append(point)
	var started := Time.get_ticks_msec()
	var routed := 0
	for repeat in range(6):
		for index in range(points.size()):
			var route := sim.ground_route(points[index], points[(index * 7 + 13) % points.size()])
			if bool(route["reachable"]):
				routed += 1
	var elapsed := Time.get_ticks_msec() - started
	_expect(elapsed < 900 and routed > 0, "bounded terrain and ford-route queries fit the prototype budget", "%d ms for %d routes" % [elapsed, routed])

func _controlled_land_config() -> Dictionary:
	var config := Config.make().duplicate(true)
	config["world"]["forest_patch_count"] = 0
	config["terrain"]["thicket"]["patch_count"] = 0
	config["terrain"]["stream"]["enabled"] = false
	config["rabbit"]["reproduction_food_needed"] = 99999.0
	config["fox"]["reproduction_food_needed"] = 99999.0
	return config

func _add_controlled_thicket(sim, center: Vector2, radius: float) -> void:
	sim.terrain.thicket_patches.append({
		"center": center,
		"radius": radius,
		"squash": 1.0,
		"rotation": 0.0,
		"tone": 0.5,
		"kind": "thicket",
	})
	sim.terrain._rebuild_terrain_bins()

func _add_controlled_woodland(sim, center: Vector2, radius: float) -> void:
	sim.terrain.woodland_patches.append({
		"center": center,
		"radius": radius,
		"squash": 1.0,
		"rotation": 0.0,
		"tone": 0.5,
		"kind": "woodland",
	})
	sim.terrain._rebuild_terrain_bins()

func _deep_stream_point(sim) -> Vector2:
	for point in sim.terrain.stream_points:
		if point.length() < sim.world_radius - 35.0 and sim.terrain.is_deep_water(point):
			return point
	return Vector2.INF

func _bank_point(sim, stream_point: Vector2, extra: float) -> Vector2:
	var info: Dictionary = sim.terrain.stream_info(stream_point)
	return stream_point + Vector2(info["normal"]) * (float(info["half_width"]) + extra)

func _find_habitat_point(sim, kind: String) -> Vector2:
	for ring in range(1, 9):
		for index in range(32):
			var point := Vector2.from_angle(float(index) / 32.0 * TAU) * float(ring) * 38.0
			if not sim.is_position_valid(point):
				continue
			var habitat: Dictionary = sim.terrain.habitat_at(point)
			if float(habitat[kind]) > 0.72:
				return point
	return Vector2.ZERO

func _find_cover_margin(sim) -> Vector2:
	for ring in range(1, 10):
		for index in range(48):
			var point := Vector2.from_angle(float(index) / 48.0 * TAU) * float(ring) * 34.0
			if not sim.is_position_valid(point):
				continue
			var cover := maxf(sim.terrain.woodland_cover(point), sim.terrain.thicket_cover(point))
			if cover >= 0.30 and cover <= 0.62:
				return point
	return Vector2.ZERO

func _find_best_food_point(sim, plant_type: String) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -INF
	for ring in range(1, 12):
		for index in range(64):
			var point := Vector2.from_angle(float(index) / 64.0 * TAU) * float(ring) * 30.0
			if not sim.is_position_valid(point):
				continue
			var score: float = sim.terrain.food_suitability(plant_type, point)
			if score > best_score:
				best_score = score
				best = point
	return best

func _across_ford_setup(sim) -> Dictionary:
	for ford in sim.terrain.fords:
		var center: Vector2 = ford["position"]
		if center.length() > sim.world_radius - 85.0:
			continue
		var normal: Vector2 = ford["normal"]
		var tangent: Vector2 = ford["tangent"]
		var bank_distance: float = ford["half_width"] + 20.0
		var along := float(ford["radius"]) + 18.0
		var start := center + normal * bank_distance + tangent * along
		var target := center - normal * bank_distance + tangent * along
		if sim.is_position_valid(start) and sim.is_position_valid(target) and not sim.terrain.direct_path_clear(start, target):
			return {"start": start, "target": target, "ford": center}
	return {}
