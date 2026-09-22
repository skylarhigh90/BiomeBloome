extends SceneTree

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_test_personal_and_pair_gates()
	_test_forage_gates_and_birth()
	_test_readouts_do_not_change_simulation()
	_test_death_records()
	_test_archive_lifetime()
	print("%d lifecycle tests passed; %d failed." % [passed, failures.size()])
	for failure in failures:
		printerr("FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: " + label)
	else:
		failures.append(label)

func _flat_config() -> Dictionary:
	var cfg := GameConfig.make()
	cfg["world"]["forest_patch_count"] = 0
	cfg["terrain"]["thicket"]["patch_count"] = 0
	cfg["terrain"]["stream"]["enabled"] = false
	return cfg

func _make_ready(sim: EcosystemSimulation, id: int) -> void:
	sim.rabbits[id]["age"] = 30.0
	sim.rabbits[id]["hunger"] = 0.0
	sim.rabbits[id]["recent_food"] = 100.0
	sim.rabbits[id]["reproduction_cooldown"] = 0.0

func _ready_pair() -> EcosystemSimulation:
	var sim := EcosystemSimulation.new(_flat_config(), 374)
	_make_ready(sim, sim.add_rabbit(Vector2.ZERO))
	_make_ready(sim, sim.add_rabbit(Vector2(12.0, 0.0)))
	for index in range(4):
		sim.add_plant("carrot_patch", Vector2(-45.0 + 30.0 * index, 40.0))
	sim.rebuild_spatial_index()
	return sim

func _test_personal_and_pair_gates() -> void:
	var sim := _ready_pair()
	var rabbit: Dictionary = sim.rabbits[1]
	var gates := [
		{"field": "age", "value": 0.0, "code": "young"},
		{"field": "hunger", "value": 40.0, "code": "hungry"},
		{"field": "reproduction_cooldown", "value": 12.0, "code": "recovering"},
		{"field": "recent_food", "value": 4.0, "code": "needs_meals"},
	]
	for gate in gates:
		_make_ready(sim, 1)
		rabbit[gate["field"]] = gate["value"]
		var status := sim.rabbit_birth_status(1)
		sim._process_rabbit_reproduction()
		_check(status["code"] == gate["code"] and not status["ready"] and sim.rabbits.size() == 2, "%s diagnosis agrees with a blocked birth" % gate["code"])
	_make_ready(sim, 1)
	sim.rabbits[2]["recent_food"] = 0.0
	_check(sim.rabbit_birth_status(1)["code"] == "mate_not_ready", "a nearby underfed adult explains the wait for a companion")
	_make_ready(sim, 2)
	sim.rabbits[2]["position"] = Vector2(150.0, 0.0)
	_check(sim.rabbit_birth_status(1)["code"] == "needs_mate", "readout sees a companion move out of reach without mutating the spatial index")
	sim.config["rabbit"]["max_population"] = 2
	_check(sim.rabbit_birth_status(1)["code"] == "population_limit", "hard population cap has a distinct explanation")
	_check(sim.rabbit_birth_status(-1)["code"] == "missing", "missing rabbit can be inspected safely")

func _test_forage_gates_and_birth() -> void:
	var no_food := _ready_pair()
	for plant in no_food.plants.values():
		plant["food"] = 0.0
		no_food._update_plant_ecology_state(plant)
	var low_stock := _ready_pair()
	low_stock.config["rabbit"]["local_food_needed"] = 0.0
	for plant in low_stock.plants.values():
		plant["food"] = float(plant["max_food"]) * 0.30
		low_stock._update_plant_ecology_state(plant)
	var low_capacity := _ready_pair()
	for plant in low_capacity.plants.values():
		plant["regeneration"] = 0.0
	var world_stock := _ready_pair()
	for index in range(16):
		var id := world_stock.add_plant("carrot_patch", Vector2(300.0, index * 2.0))
		world_stock.plants[id]["food"] = 0.0
		world_stock._update_plant_ecology_state(world_stock.plants[id])
	var world_capacity := _ready_pair()
	for index in range(12):
		world_capacity.add_rabbit(Vector2(300.0, index * 2.0))
	var scenarios := [
		{"sim": no_food, "code": "local_food"},
		{"sim": low_stock, "code": "local_stock"},
		{"sim": low_capacity, "code": "local_capacity"},
		{"sim": world_stock, "code": "world_stock"},
		{"sim": world_capacity, "code": "world_capacity"},
	]
	for scenario in scenarios:
		var sim: EcosystemSimulation = scenario["sim"]
		sim.rebuild_spatial_index()
		var before := sim.rabbits.size()
		var status := sim.rabbit_birth_status(1)
		sim._process_rabbit_reproduction()
		_check(status["code"] == scenario["code"] and not status["ready"] and sim.rabbits.size() == before, "%s diagnosis agrees with an actual forage-blocked birth (got %s)" % [scenario["code"], status["code"]])
	var ready := _ready_pair()
	var status := ready.rabbit_birth_status(1)
	ready._process_rabbit_reproduction()
	_check(status["ready"] and ready.rabbits.size() == 3, "ready parents with surplus forage produce an actual newborn")
	_check(ready.rabbit_birth_status(1)["code"] == "recovering", "a successful birth is followed by a visible family rest period")
	var paused := EcosystemSimulation.new(_flat_config())
	_make_ready(paused, paused.add_rabbit(Vector2.ZERO))
	_make_ready(paused, paused.add_rabbit(Vector2(12.0, 0.0)))
	for index in range(4):
		paused.add_plant("carrot_patch", Vector2(index * 30.0, 40.0))
	_check(paused.rabbit_birth_status(1)["ready"] and paused.spatial.cells.is_empty(), "paused placements have current diagnostics without altering the simulation index")

func _test_readouts_do_not_change_simulation() -> void:
	var observed := _ready_pair()
	var unobserved := _ready_pair()
	var initial_state := observed.rng.state
	var initial_stats := observed.last_tick_stats.duplicate(true)
	var initial_animals := observed.rabbits.duplicate(true)
	var initial_index := observed.spatial.cells.duplicate(true)
	var snapshot := observed.animal_snapshot("rabbit", 1)
	_check(snapshot.has("birth_status") and snapshot.has("age_ratio") and snapshot.has("starvation_time"), "animal field notes expose family and mortality state")
	_check(observed.rng.state == initial_state and observed.last_tick_stats == initial_stats and observed.rabbits == initial_animals and observed.spatial.cells == initial_index, "reading lifecycle state changes no RNG, entities, query counters, or spatial index")
	for tick in range(160):
		for id in observed.rabbits:
			observed.animal_snapshot("rabbit", id)
		observed.step(0.1)
		unobserved.step(0.1)
	_check(observed.rng.state == unobserved.rng.state and observed.rabbits == unobserved.rabbits and observed.plants == unobserved.plants, "frequent inspection leaves the full seeded playthrough unchanged")

func _test_death_records() -> void:
	var sim := EcosystemSimulation.new(_flat_config())
	var old := sim.add_rabbit(Vector2.ZERO)
	var starving := sim.add_rabbit(Vector2(120.0, 0.0))
	var old_name: String = sim.rabbits[old]["name"]
	var starving_name: String = sim.rabbits[starving]["name"]
	sim.rabbits[old]["age"] = sim.rabbits[old]["lifespan"]
	sim.rabbits[old]["hunger"] = 0.0
	sim.rabbits[starving]["hunger"] = 100.0
	sim.rabbits[starving]["starvation_time"] = sim.config["rabbit"]["starvation_duration"]
	var event_observations: Array[Dictionary] = []
	var death_events: Array[Dictionary] = []
	var removed_callback := func(kind: String, id: int, _position: Vector2, _cause: String) -> void:
		event_observations.append(sim.death_snapshot(kind, id))
	var died_callback := func(snapshot: Dictionary) -> void:
		death_events.append(snapshot)
	sim.entity_removed.connect(removed_callback)
	sim.animal_died.connect(died_callback)
	sim.step(0.1)
	sim.entity_removed.disconnect(removed_callback)
	sim.animal_died.disconnect(died_callback)
	var old_record := sim.death_snapshot("rabbit", old)
	var starved_record := sim.death_snapshot("rabbit", starving)
	_check(old_record["name"] == old_name and old_record["cause"] == "age" and old_record["age"] >= old_record["lifespan"], "natural old-age death retains its name and true cause")
	_check(starved_record["name"] == starving_name and starved_record["cause"] == "starvation" and starved_record["age"] < starved_record["lifespan"], "natural starvation death is distinguished from old age")
	_check(event_observations.size() == 2 and not event_observations[0].is_empty() and death_events.size() == 2 and not death_events[0]["alive"], "named death records are available to both death and removal listeners")
	old_record["name"] = "Changed outside the archive"
	_check(sim.death_snapshot("rabbit", old)["name"] == old_name, "callers cannot accidentally overwrite the death archive")
	var child := sim.add_rabbit(Vector2.ZERO, "birth", [old, starving])
	_check(sim.animal_snapshot("rabbit", child)["parent_names"] == [old_name, starving_name], "young retain their parents' names after a death")
	sim.kill_rabbit(child, "predation")
	_check(sim.death_snapshot("rabbit", child)["cause"] == "predation", "a hunt preserves the prey's identity and distinct cause")
	var fox := sim.add_fox(Vector2.ZERO)
	sim.kill_fox(fox, "age")
	_check(sim.death_snapshot("fox", fox)["kind"] == "fox", "fox deaths use the same observable lifecycle contract")
	var undo := sim.add_rabbit(Vector2.ZERO)
	sim.kill_rabbit(undo, "undo")
	_check(sim.death_snapshot("rabbit", undo).is_empty(), "undo is never reported as an animal death")

func _test_archive_lifetime() -> void:
	var sim := EcosystemSimulation.new(_flat_config())
	for index in range(129):
		sim.kill_rabbit(sim.add_rabbit(Vector2.ZERO), "age")
	_check(sim.animal_deaths.size() == 128 and sim.death_snapshot("rabbit", 1).is_empty() and not sim.death_snapshot("rabbit", 129).is_empty(), "death history is bounded and keeps the most recent losses")
	sim.reset()
	_check(sim.animal_deaths.is_empty(), "a fresh run clears its predecessor's death history")
