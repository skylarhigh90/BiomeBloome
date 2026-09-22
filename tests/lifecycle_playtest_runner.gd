extends SceneTree

## Observe the opening without spending later supplies or changing the ecology.
## Run: godot --headless --path . --script res://tests/lifecycle_playtest_runner.gd -- output.json
## Hint response: append a seed and "respond" after the output path (seed 240821 reproduces a long wait).
const DEFAULT_SEEDS := [240817, 240818, 240819, 240820, 240821]
const OBSERVATION_SECONDS := 290.0

var failures: Array[String] = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var results: Array[Dictionary] = []
	var seeds: Array = DEFAULT_SEEDS
	if args.size() > 1:
		seeds = [int(args[1])]
	if args.size() > 2 and str(args[2]) == "respond":
		var response := _run_opening(int(seeds[0]), true, true)
		_check(Array(response["actions"]).size() == 1, "Responded to the forage diagnosis by spending exactly one available plant")
		_check(response["first_birth_time"] != null and float(response["first_birth_time"]) < 60.0, "Following the diagnosis produces young before one simulated minute")
		response["failures"] = failures
		FileAccess.open(str(args[0]), FileAccess.WRITE).store_string(JSON.stringify(response, "  "))
		print("Hint response seed %d: %s; first birth %s s; %d failures." % [seeds[0], str(response["actions"]), str(response["first_birth_time"]), failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	for seed_value in seeds:
		var observed := _run_opening(int(seed_value), true)
		results.append(observed)
		_validate_opening(observed)
		print("Opening seed %d: first birth %s s, %d births, %d losses, %d founder losses, stopped at %.1f s" % [
			seed_value, str(observed["first_birth_time"]), Array(observed["births"]).size(),
			Array(observed["deaths"]).size(), Array(observed["founder_deaths"]).size(), observed["simulation_time"],
		])
	# Repeated inspector reads must not perturb RNG or the underlying world.
	var control := _run_opening(int(seeds[0]), false)
	var same_ecology: bool = results[0]["ecology_signature"] == control["ecology_signature"]
	_check(same_ecology, "Observing birth status does not change birth/death events or final animal positions")
	var report := {
		"method": "Default GameConfig, four starting rabbits and five starting carrots placed together. Later supply choices are claimed only to resume time; no later stock is placed. No animal fields, food reserves, mortality, or breeding settings are modified.",
		"duration_requested": OBSERVATION_SECONDS,
		"units": "Simulation seconds; divide warning lead times by the selected game speed for wall-clock seconds.",
		"observation_changes_ecology": not same_ecology,
		"runs": results,
		"failures": failures,
	}
	if not args.is_empty():
		var output := FileAccess.open(str(args[0]), FileAccess.WRITE)
		if output == null:
			failures.append("Could not write requested telemetry: " + str(args[0]))
		else:
			output.store_string(JSON.stringify(report, "  "))
	for failure in failures:
		printerr("FAILED: " + failure)
	print("Lifecycle opening playtest: %d runs; %d failures." % [results.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _run_opening(seed_value: int, inspect_births: bool, respond_to_hint: bool = false) -> Dictionary:
	var cfg := GameConfig.make()
	cfg["simulation"]["seed"] = seed_value
	var systems := GameSystems.new(cfg)
	var sim := systems.simulation
	var stories: Array[Dictionary] = []
	var births: Array[Dictionary] = []
	var deaths: Array[Dictionary] = []
	var founders: Array[int] = []
	var founder_names: Dictionary = {}
	var status_transitions: Array[Dictionary] = []
	var last_status: Dictionary = {}
	var signature: Array = []
	var probes: Array[Dictionary] = []
	var actions: Array[Dictionary] = []
	var claims := 0
	systems.ecology_story_added.connect(func(story: Dictionary) -> void:
		stories.append(story.duplicate(true))
	)
	sim.entity_added.connect(func(kind: String, entity_id: int, reason: String) -> void:
		if kind == "rabbit" and reason == "birth":
			var rabbit: Dictionary = sim.rabbits[entity_id]
			var event := {"id": entity_id, "name": rabbit["name"], "time": snappedf(sim.simulation_time, 0.1), "parents": rabbit["parent_ids"].duplicate(), "position": rabbit["position"]}
			births.append(event)
			signature.append(["birth", entity_id, event["time"], event["position"]])
	)
	sim.entity_removed.connect(func(kind: String, entity_id: int, position: Vector2, cause: String) -> void:
		if kind != "rabbit":
			return
		var death := sim.death_snapshot(kind, entity_id).duplicate(true)
		death["id"] = entity_id
		death["recorded_cause"] = cause
		death["recorded_time"] = snappedf(sim.simulation_time, 0.1)
		death["founder"] = founders.has(entity_id)
		deaths.append(death)
		signature.append(["death", entity_id, death["recorded_time"], cause, position])
	)
	var anchor := _find_opening_anchor(systems)
	var plant_offsets := [Vector2(-45, -35), Vector2(0, -45), Vector2(45, -35), Vector2(-30, 25), Vector2(30, 25)]
	var animal_offsets := [Vector2(-22, -4), Vector2(22, -4), Vector2(-22, 13), Vector2(22, 13)]
	var plants_placed := 0
	for offset in plant_offsets:
		if systems.place_item("carrot_patch", anchor + offset) >= 0:
			plants_placed += 1
	for offset in animal_offsets:
		var entity_id := systems.place_item("rabbit", anchor + offset)
		if entity_id >= 0:
			founders.append(entity_id)
			founder_names[entity_id] = sim.rabbits[entity_id]["name"]
	var ticks := ceili(OBSERVATION_SECONDS / 0.1)
	for tick in range(ticks):
		if systems.supply_pending:
			systems.choose_supply(0)
			claims += 1
		if inspect_births and tick % 10 == 0:
			for entity_id in founders:
				if not sim.rabbits.has(entity_id):
					continue
				var status: Dictionary = sim.rabbit_birth_status(entity_id)
				var code := str(status.get("code", ""))
				if str(last_status.get(entity_id, "")) != code:
					last_status[entity_id] = code
					status_transitions.append({"id": entity_id, "name": founder_names[entity_id], "time": snappedf(sim.simulation_time, 0.1), "status": status.duplicate(true)})
			if tick in [100, 300, 600, 1200]:
				var probe := {"time": snappedf(sim.simulation_time, 0.1), "rabbits": []}
				for entity_id in founders:
					if sim.rabbits.has(entity_id):
						probe["rabbits"].append({"id": entity_id, "name": founder_names[entity_id], "status": sim.rabbit_birth_status(entity_id)})
				probes.append(probe)
		if respond_to_hint and tick >= 300 and actions.is_empty():
			var blocked_id := -1
			for entity_id in founders:
				if sim.rabbits.has(entity_id) and str(sim.rabbit_birth_status(entity_id)["code"]) == "local_capacity":
					blocked_id = entity_id
					break
			if blocked_id >= 0:
				var action := _follow_forage_hint(systems, blocked_id)
				if not action.is_empty():
					actions.append(action)
		systems.advance(0.1)
		if systems.is_completed() or systems.is_game_over():
			break
	var founder_deaths: Array[Dictionary] = []
	for death in deaths:
		var event_id := int(death["id"])
		var event_time := float(death["recorded_time"])
		var relevant_type := "elder" if str(death["recorded_cause"]) == "age" else "hunger_warning"
		var prior_warning := -1.0
		var death_story := {}
		for story in stories:
			if int(story["entity_id"]) != event_id:
				continue
			if str(story["type"]) == relevant_type and float(story["time"]) < event_time:
				prior_warning = float(story["time"])
			if str(story["type"]) == "death":
				death_story = story
		death["prior_warning_type"] = relevant_type
		death["prior_warning_time"] = snappedf(prior_warning, 0.1)
		death["warning_lead_seconds"] = snappedf(event_time - prior_warning, 0.1) if prior_warning >= 0.0 else -1.0
		death["death_story"] = death_story
		if bool(death["founder"]):
			founder_deaths.append(death)
	for rabbit in sim.rabbits.values():
		signature.append(["survivor", rabbit["id"], rabbit["position"], rabbit["age"], rabbit["hunger"]])
	return {
		"seed": seed_value,
		"anchor": anchor,
		"initial_placements": {"rabbits": founders.size(), "carrots": plants_placed},
		"founders": founder_names,
		"simulation_time": snappedf(sim.simulation_time, 0.1),
		"state": systems.run_director.run_state,
		"objective": systems.run_director.current_milestone_id(),
		"supplies_claimed_without_placement": claims,
		"first_birth_time": births[0]["time"] if not births.is_empty() else null,
		"births": births,
		"deaths": deaths,
		"founder_deaths": founder_deaths,
		"birth_status_transitions": status_transitions,
		"status_probes": probes,
		"actions": actions,
		"stories": stories,
		"final_population": sim.population("rabbit"),
		"ecology_signature": signature,
	}

func _follow_forage_hint(systems: GameSystems, blocked_id: int) -> Dictionary:
	var anchor: Vector2 = systems.simulation.rabbits[blocked_id]["home_position"]
	var best_item := ""
	var best_position := Vector2.ZERO
	var best_score := -INF
	var best_assessment := {}
	# These are the same placement assessments shown to a player moving a plant
	# preview. No hidden biomass or breeding state is edited.
	for item in ["berry_bush", "carrot_patch"]:
		if int(systems.inventory.get(item, 0)) <= 0 or not systems.run_director.is_unlocked(item):
			continue
		for ring in range(1, 6):
			for spoke in range(16):
				var position := anchor + Vector2.from_angle(float(spoke) / 16.0 * TAU) * float(ring) * 20.0
				if not systems.can_place(item, position):
					continue
				var assessment := systems.placement_assessment(item, position)
				var score := float(assessment.get("score", 0.0))
				if score > best_score:
					best_item = item
					best_position = position
					best_score = score
					best_assessment = assessment
	if best_item.is_empty():
		return {}
	var status := systems.simulation.rabbit_birth_status(blocked_id)
	var inventory_before := int(systems.inventory[best_item])
	var plant_id := systems.place_item(best_item, best_position)
	if plant_id < 0:
		return {}
	return {
		"time": snappedf(systems.simulation.simulation_time, 0.1),
		"trigger": status,
		"action": "Place one productive forage plant near the blocked rabbit's home",
		"item": best_item,
		"position": best_position,
		"assessment": best_assessment,
		"inventory_before": inventory_before,
		"inventory_after": int(systems.inventory[best_item]),
		"plant_id": plant_id,
	}

func _find_opening_anchor(systems: GameSystems) -> Vector2:
	var offsets := [Vector2(-45, -35), Vector2(0, -45), Vector2(45, -35), Vector2(-30, 25), Vector2(30, 25), Vector2(-22, -4), Vector2(22, -4), Vector2(-22, 13), Vector2(22, 13)]
	for ring in range(7):
		for spoke in range(16):
			var anchor := Vector2.from_angle(float(spoke) / 16.0 * TAU) * float(ring) * 35.0
			var valid := true
			for offset in offsets:
				if not systems.simulation.is_position_valid(anchor + offset):
					valid = false
					break
			if valid:
				return anchor
	return Vector2.ZERO

func _validate_opening(result: Dictionary) -> void:
	var label := "seed %d" % int(result["seed"])
	_check(int(result["initial_placements"]["rabbits"]) == 4 and int(result["initial_placements"]["carrots"]) == 5, label + ": placed only the complete initial stock")
	_check(not Array(result["birth_status_transitions"]).is_empty(), label + ": opening reports live birth blockers")
	_check(Array(result["founder_deaths"]).size() == 4, label + ": observed all four founders' natural deaths")
	for birth in result["births"]:
		var found := false
		for story in result["stories"]:
			if story["type"] == "birth" and int(story["entity_id"]) == int(birth["id"]):
				found = true
		_check(found, label + ": named birth story for rabbit %d" % int(birth["id"]))
	for death in result["deaths"]:
		var death_label := label + ": rabbit %d" % int(death["id"])
		_check(str(death.get("name", "")) != "" and str(death.get("cause", "")) == str(death["recorded_cause"]), death_label + " retains identity and true cause after removal")
		var description := str(Dictionary(death["death_story"]).get("description", ""))
		_check(description.contains(str(death.get("name", ""))) and description.contains(str(death.get("cause_label", ""))), death_label + " has a named story explaining its cause of death")
		_check(float(death["warning_lead_seconds"]) > 0.0, death_label + " has a cause-specific warning before death")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
