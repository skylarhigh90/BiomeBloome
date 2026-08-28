extends SceneTree

## Reproducible live-simulation trials for the V0.4 manual playtest layouts.
## These complement unit-style terrain assertions; the normal ten-checkpoint
## playthrough remains in playtest_runner.gd.

const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")

var failures: Array[String] = []

func _initialize() -> void:
	var open := _colony_trial(false)
	var refuge := _colony_trial(true)
	var route := _stream_route_trial()
	var barrier := _predator_barrier_trial()
	print("\nV0.4 PLAYTEST A · Open Meadow colony: %s" % str(open))
	print("V0.4 PLAYTEST B · Meadow beside Thicket: %s" % str(refuge))
	print("V0.4 PLAYTEST C · Refuge comparison: open %d survivors / %d captures / %d hunting ticks; refuge %d survivors / %d captures / %d hunting ticks" % [open["end"], open["captures"], open["hunting_ticks"], refuge["end"], refuge["captures"], refuge["hunting_ticks"]])
	print("V0.4 PLAYTEST D · Stream separation: %s" % str(route))
	print("V0.4 PLAYTEST E · Predator across water: %s" % str(barrier))
	_check(int(open["peak_before_fox"]) > int(open["start"]) and int(open["feeding_events"]) > 0, "Open Meadow colony did not establish through feeding.")
	_check(int(open["captures"]) > 0 and int(open["fleeing_ticks"]) > 0, "Exposed Meadow did not become dangerous under Fox pressure.")
	_check(int(refuge["refuge_ticks"]) > 0, "Rabbits did not visibly choose/use the nearby Thicket.")
	_check(int(refuge["captures"]) > 0, "Thicket prevented every hunt instead of disrupting pursuit.")
	# Fox hunger/meal cadence bounds the number of kills in this fixed window, so
	# equal captures do not imply equal pursuit. A valid refuge must either reduce
	# captures/sustain more Rabbits or make Foxes spend materially longer hunting.
	_check(int(refuge["end"]) > int(open["end"]) or int(refuge["captures"]) < int(open["captures"]) \
		or int(refuge["hunting_ticks"]) > int(open["hunting_ticks"]) * 1.10,
		"The refuge layout did not measurably disrupt pursuit compared with exposed Meadow.")
	_check(bool(route["used_ford"]) and bool(route["stayed_dry"]) and bool(route["made_progress"]) and int(route["longest_stall_ticks"]) < 18, "Stream routing was unclear, stuck, or entered deep water.")
	_check(not bool(barrier["across_water_flee"]) and bool(barrier["same_bank_flee"]), "Stream did not change Rabbit threat evaluation as expected.")
	if failures.is_empty():
		print("V0.4 terrain playtests passed. Scenario F is exercised by tests/playtest_runner.gd.")
		quit(0)
		return
	for failure in failures:
		printerr("PLAYTEST FAILED: %s" % failure)
	quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _colony_trial(with_thicket: bool) -> Dictionary:
	var config := _open_land_config()
	config["rabbit"]["max_population"] = 70
	var sim = Simulation.new(config, 9031)
	if with_thicket:
		# A genuinely nearby refuge with an exposed run from the colony into its
		# dense core: protection is meaningful, but the crossing is not risk-free.
		_add_thicket(sim, Vector2(120.0, 0.0), 70.0)
	var events := {"feeding": 0, "captures": 0}
	sim.creature_fed.connect(func(kind: String, _entity_id: int, _source_id: int) -> void:
		if kind == "rabbit":
			events["feeding"] = int(events["feeding"]) + 1
	)
	sim.predation_succeeded.connect(func(_fox_id: int, _rabbit_id: int, _position: Vector2) -> void:
		events["captures"] = int(events["captures"]) + 1
	)
	for index in range(7):
		var position := Vector2.from_angle(float(index) / 7.0 * TAU) * 48.0
		sim.add_plant("carrot_patch", position)
	for index in range(6):
		var rabbit_id: int = sim.add_rabbit(Vector2.from_angle(float(index) / 6.0 * TAU) * 30.0)
		sim.rabbits[rabbit_id]["age"] = 30.0
		sim.rabbits[rabbit_id]["hunger"] = 22.0
		sim.rabbits[rabbit_id]["recent_food"] = 18.0
		sim.rabbits[rabbit_id]["reproduction_cooldown"] = 0.0
	var start := sim.population("rabbit")
	var peak := start
	for _tick in range(700):
		sim.step(0.1)
		peak = maxi(peak, sim.population("rabbit"))
	# Normalize the chase populations so Scenario B measures refuge geography,
	# not the intentionally lower food productivity near cover.
	while sim.population("rabbit") < 20:
		var index := sim.population("rabbit")
		var rabbit_id: int = sim.add_rabbit(Vector2.from_angle(float(index) * 2.399) * (18.0 + float(index % 4) * 7.0))
		sim.rabbits[rabbit_id]["age"] = 30.0
		sim.rabbits[rabbit_id]["hunger"] = 10.0
		sim.rabbits[rabbit_id]["recent_food"] = 18.0
	peak = maxi(peak, sim.population("rabbit"))
	# The chase phase is specifically a refuge-geometry comparison. Clear any
	# retained feeding motivation before introducing Foxes; otherwise differences
	# in local plant recovery can keep one group routing to food during the hunt
	# and confound the cover measurement.
	for rabbit in sim.rabbits.values():
		rabbit["hunger"] = 0.0
		rabbit["food_motivated"] = false
		rabbit["behavior"] = "wander"
		rabbit["target_id"] = -1
		sim._clear_ground_route(rabbit)
	sim.config["rabbit"]["hunger_rate"] = 0.0
	sim.config["rabbit"]["reproduction_food_needed"] = 99999.0
	sim.config["rabbit"]["lifespan"] = 1000.0
	for fox_position in [Vector2(-112.0, -35.0), Vector2(-112.0, 35.0)]:
		var fox_id: int = sim.add_fox(fox_position)
		sim.foxes[fox_id]["hunger"] = 62.0
	var fleeing_ticks := 0
	var refuge_ticks := 0
	var hunting_ticks := 0
	var rabbit_survival_seconds := 0.0
	for _tick in range(600):
		sim.step(0.1)
		rabbit_survival_seconds += float(sim.population("rabbit")) * 0.1
		for rabbit in sim.rabbits.values():
			if rabbit["behavior"] == "flee":
				fleeing_ticks += 1
			if rabbit.get("refuge_position", Vector2.INF) != Vector2.INF:
				refuge_ticks += 1
		for fox in sim.foxes.values():
			if fox["behavior"] == "hunt":
				hunting_ticks += 1
	return {
		"start": start,
		"peak_before_fox": peak,
		"end": sim.population("rabbit"),
		"captures": events["captures"],
		"feeding_events": events["feeding"],
		"fleeing_ticks": fleeing_ticks,
		"refuge_ticks": refuge_ticks,
		"hunting_ticks": hunting_ticks,
		"rabbit_survival_seconds": snappedf(rabbit_survival_seconds, 0.1),
	}

func _stream_route_trial() -> Dictionary:
	var config := Config.make().duplicate(true)
	config["rabbit"]["food_detection_radius"] = 330.0
	config["rabbit"]["reproduction_food_needed"] = 99999.0
	var sim = Simulation.new(config, int(config["simulation"]["seed"]))
	var setup := _across_ford_setup(sim)
	var rabbit_id: int = sim.add_rabbit(setup["start"])
	sim.add_plant("carrot_patch", setup["target"])
	sim.rabbits[rabbit_id]["hunger"] = 58.0
	sim.step(0.1)
	var used_ford: bool = sim.rabbits[rabbit_id]["route_ford"] != Vector2.INF
	var start_distance: float = setup["start"].distance_to(setup["target"])
	var closest := start_distance
	var stayed_dry := true
	var stall_ticks := 0
	var longest_stall := 0
	for _tick in range(240):
		sim.step(0.1)
		var rabbit: Dictionary = sim.rabbits[rabbit_id]
		closest = minf(closest, rabbit["position"].distance_to(setup["target"]))
		if sim.terrain.is_deep_water(rabbit["position"]):
			stayed_dry = false
		if rabbit["behavior"] == "seek_food" and rabbit["velocity"].length() < 3.0:
			stall_ticks += 1
			longest_stall = maxi(longest_stall, stall_ticks)
		else:
			stall_ticks = 0
	return {
		"used_ford": used_ford,
		"stayed_dry": stayed_dry,
		"made_progress": closest < start_distance * 0.35,
		"distance": "%.1f -> %.1f" % [start_distance, closest],
		"longest_stall_ticks": longest_stall,
	}

func _predator_barrier_trial() -> Dictionary:
	var config := Config.make().duplicate(true)
	config["rabbit"]["reproduction_food_needed"] = 99999.0
	config["fox"]["reproduction_food_needed"] = 99999.0
	var sim = Simulation.new(config, int(config["simulation"]["seed"]))
	var deep := _deep_stream_point(sim)
	var info: Dictionary = sim.terrain.stream_info(deep)
	var normal: Vector2 = info["normal"]
	var bank_distance: float = info["half_width"] + 14.0
	var rabbit_position := deep + normal * bank_distance
	var across_position := deep - normal * bank_distance
	var rabbit_id: int = sim.add_rabbit(rabbit_position)
	var across_fox: int = sim.add_fox(across_position)
	sim.foxes[across_fox]["hunger"] = 60.0
	sim.step(0.1)
	var across_flee: bool = sim.rabbits[rabbit_id]["behavior"] == "flee"
	sim.kill_fox(across_fox, "playtest")
	var same_bank_fox: int = sim.add_fox(rabbit_position + normal * 38.0)
	sim.foxes[same_bank_fox]["hunger"] = 60.0
	sim.step(0.1)
	return {
		"direct_distance": rabbit_position.distance_to(across_position),
		"route_distance": sim.ground_route_distance(rabbit_position, across_position),
		"across_water_flee": across_flee,
		"same_bank_flee": sim.rabbits[rabbit_id]["behavior"] == "flee",
	}

func _open_land_config() -> Dictionary:
	var config := Config.make().duplicate(true)
	config["world"]["forest_patch_count"] = 0
	config["terrain"]["thicket"]["patch_count"] = 0
	config["terrain"]["stream"]["enabled"] = false
	config["fox"]["reproduction_food_needed"] = 99999.0
	return config

func _add_thicket(sim, center: Vector2, radius: float) -> void:
	sim.terrain.thicket_patches.append({
		"center": center,
		"radius": radius,
		"squash": 1.0,
		"rotation": 0.0,
		"tone": 0.5,
		"kind": "thicket",
	})
	sim.terrain._rebuild_terrain_bins()

func _deep_stream_point(sim) -> Vector2:
	for point in sim.terrain.stream_points:
		if point.length() < sim.world_radius - 55.0 and sim.terrain.is_deep_water(point):
			var near_ford := false
			for ford in sim.terrain.fords:
				if point.distance_to(ford["position"]) < float(ford["radius"]) * 1.4:
					near_ford = true
			if not near_ford:
				return point
	return Vector2.INF

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
			return {"start": start, "target": target}
	return {}
