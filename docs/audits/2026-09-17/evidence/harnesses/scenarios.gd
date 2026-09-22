extends SceneTree
const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")
var output := "/private/tmp/biome-audit-20260917"
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	var scenario = args[0] if args.size() > 0 else "A"
	var duration = float(args[1]) if args.size() > 1 else 1800.0
	var seeds = [240817, 9327, 401, 9031, 17117]
	if args.size() > 2: seeds = [int(args[2])]
	for seed_value in seeds: run_trial(scenario, seed_value, duration)
	quit()
func valid_near(sim, wanted: Vector2) -> Vector2:
	if sim.is_position_valid(wanted): return wanted
	for ring in range(1, 30):
		for spoke in range(32):
			var p = wanted + Vector2.from_angle(float(spoke) / 32.0 * TAU) * ring * 8.0
			if sim.is_position_valid(p): return p
	push_error("Invalid audit setup")
	return Vector2.INF
func run_trial(scenario: String, seed_value: int, duration: float) -> void:
	var cfg = Config.make().duplicate(true)
	cfg["simulation"]["seed"] = seed_value
	var sim = Simulation.new(cfg, seed_value)
	sim.world_radius = 600.0 if not scenario.begins_with("F") else 940.0
	var centers = [Vector2(-200,-140), Vector2(220,-100), Vector2(0,200)]
	if scenario == "B_compact": centers = [Vector2(-180,-80), Vector2(-90,-20), Vector2(-190,30)]
	var plant_count = 12 if scenario == "A" else (3 if scenario == "D" else (36 if scenario in ["B_rich", "B_compact"] else 18))
	var rabbit_count = 7 if scenario == "A" else (6 if scenario.begins_with("F") else 24)
	var fox_count = 0 if scenario == "A" else (10 if scenario == "C" else 2)
	if scenario.begins_with("F"):
		centers = []
		for i in range(6): centers.append(Vector2.from_angle(float(i) / 6.0 * TAU) * 640.0)
	# E and E_open are a paired habitat experiment: identical flat ground,
	# resource placement, populations and RNG; E alone has explicit refuge cover.
	if scenario in ["E", "E_open"]:
		cfg["terrain"]["stream"]["enabled"] = false
		sim.terrain.woodland_patches.clear()
		sim.terrain.thicket_patches.clear()
		sim.terrain._rebuild_terrain_bins()
	var layout = {"plants":[],"rabbits":[],"foxes":[]}
	for i in range(plant_count):
		var p = valid_near(sim, centers[i % centers.size()] + Vector2.from_angle(float(i) * 2.399963) * (28.0 + float(i / centers.size()) * 9.0))
		var kind = "carrot_patch" if i % 3 != 2 else "berry_bush"
		sim.add_plant(kind, p)
		layout.plants.append({"type":kind,"x":p.x,"y":p.y})
	if scenario == "E":
		for center in centers:
			sim.terrain.thicket_patches.append(sim.terrain._make_patch(center + Vector2(90,0), 75.0, 1.0, 0.0, 0.5, "thicket"))
		sim.terrain._rebuild_terrain_bins()
	for i in range(rabbit_count):
		var p = valid_near(sim, centers[(int(i / 2) * 2) % centers.size() if scenario == "F_pairs" else i % centers.size()] + Vector2.from_angle(float(i) * 2.399963) * (12.0 + float(i % 4) * 8.0))
		sim.add_rabbit(p)
		layout.rabbits.append({"x":p.x,"y":p.y})
	for i in range(fox_count):
		var p = valid_near(sim, (Vector2(0,-100) if scenario.begins_with("F") else centers[i % centers.size()]) + Vector2(-100.0, float(i / centers.size()) * 35.0))
		sim.add_fox(p)
		layout.foxes.append({"x":p.x,"y":p.y})
	var events = {"rabbit_births":0,"fox_births":0,"hunts":0,"rabbit_age":0,"rabbit_starvation":0,"rabbit_predation":0,"fox_age":0,"fox_starvation":0}
	var eventfile = FileAccess.open(output + "/%s_%d_events.jsonl" % [scenario,seed_value],FileAccess.WRITE)
	sim.entity_added.connect(func(kind, id, reason):
		if reason == "birth":
			events[kind + "_births"] += 1
			eventfile.store_line(JSON.stringify({"t":sim.simulation_time,"kind":kind,"event":"birth","id":id}))
	)
	sim.entity_removed.connect(func(kind,id,p,cause):
		var key = kind + "_" + cause
		events[key] = int(events.get(key,0)) + 1
		eventfile.store_line(JSON.stringify({"t":sim.simulation_time,"kind":kind,"event":cause,"id":id,"x":p.x,"y":p.y}))
	)
	sim.predation_succeeded.connect(func(_fox,_rabbit,_p): events.hunts += 1)
	var prefix = output + "/%s_%d" % [scenario,seed_value]
	var csv = FileAccess.open(prefix + ".csv", FileAccess.WRITE)
	csv.store_line("time,rabbits,foxes,biomass,stock_ratio,capacity,rabbit_births,fox_births,hunts,rabbit_age,rabbit_starvation,fox_age,fox_starvation,rabbit_mean_hunger,fox_mean_hunger,rabbits_in_cover")
	var peak_r = rabbit_count
	var peak_f = fox_count
	var zero_r = -1.0
	var zero_f = -1.0
	var timings: Array[float] = []
	var started = Time.get_ticks_usec()
	for tick in range(ceili(duration / 0.1) + 1):
		if tick % 50 == 0:
			var b = sim.ecosystem_forage_budget()
			var rh = 0.0
			var fh = 0.0
			var covered = 0
			for e in sim.rabbits.values():
				rh += float(e.hunger)
				if sim.terrain.thicket_cover(e.position) >= 0.48: covered += 1
			for e in sim.foxes.values(): fh += float(e.hunger)
			csv.store_line("%.1f,%d,%d,%.4f,%.4f,%.4f,%d,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%d" % [sim.simulation_time,sim.rabbits.size(),sim.foxes.size(),b.total_food,b.stock_ratio,b.sustainable_rabbits,events.rabbit_births,events.fox_births,events.hunts,events.rabbit_age,events.rabbit_starvation,events.fox_age,events.fox_starvation,rh/maxi(1,sim.rabbits.size()),fh/maxi(1,sim.foxes.size()),covered])
		if tick == ceili(duration / 0.1): break
		var start = Time.get_ticks_usec()
		sim.step(0.1)
		timings.append(float(Time.get_ticks_usec()-start)/1000.0)
		peak_r = maxi(peak_r,sim.rabbits.size())
		peak_f = maxi(peak_f,sim.foxes.size())
		if sim.rabbits.is_empty() and zero_r < 0.0: zero_r = sim.simulation_time
		if sim.foxes.is_empty() and zero_f < 0.0 and fox_count > 0: zero_f = sim.simulation_time
		if tick % 3000 == 2999:
			print("PROGRESS %s %d t=%.0f r=%d f=%d" % [scenario,seed_value,sim.simulation_time,sim.rabbits.size(),sim.foxes.size()])
			csv.flush()
	timings.sort()
	var summary = {"scenario":scenario,"seed":seed_value,"duration":duration,"world_radius":sim.world_radius,"start_r":rabbit_count,"start_f":fox_count,"plants":plant_count,"end_r":sim.rabbits.size(),"end_f":sim.foxes.size(),"peak_r":peak_r,"peak_f":peak_f,"extinction_r":zero_r,"extinction_f":zero_f,"events":events,"budget":sim.ecosystem_forage_budget(),"elapsed_real_seconds":float(Time.get_ticks_usec()-started)/1e6,"step_p50_ms":timings[int(timings.size()*0.5)],"step_p95_ms":timings[int(timings.size()*0.95)],"layout":layout}
	FileAccess.open(prefix + ".json",FileAccess.WRITE).store_string(JSON.stringify(summary,"  "))
	print("SUMMARY " + JSON.stringify(summary))
	csv.close()
	eventfile.close()
