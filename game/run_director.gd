class_name RunDirector
extends RefCounted

signal milestone_completed(index: int, milestone: Dictionary)
signal unlock_changed(item: String, unlocked: bool)
signal state_changed(previous_state: String, new_state: String)
signal critical_started
signal critical_recovered
signal first_recovery_supply_requested
signal run_failed(recap: String)
signal run_completed

const STATE_PLAYING := "playing"
const STATE_CRITICAL := "critical"
const STATE_GAME_OVER := "game_over"
const STATE_COMPLETED := "completed"
const STATE_SANDBOX := "sandbox"

var config: Dictionary
var progression: Dictionary
var milestones: Array
var unlocked: Dictionary = {}
var supply_pool := "meadow"

var milestone_index := 0
var completed_milestones: Array[String] = []
var milestone_stability := 0.0
var milestone_rabbit_births := 0
var milestone_hunts := 0
var milestone_events: Array = []
var milestone_fed_rabbit_ids: Dictionary = {}
var milestone_fed_born_rabbit_ids: Dictionary = {}
var milestone_fed_fox_ids: Dictionary = {}
var placed_rabbit_ids: Dictionary = {}
var born_rabbit_ids: Dictionary = {}
var sequence_progress := 0
var sequence_started_at := -1.0
var sequence_completed := false
var last_safe_haven_groups: Array = []

var run_state := STATE_PLAYING
var rabbit_failure_armed := false
var critical_entry_elapsed := 0.0
var critical_elapsed := 0.0
var critical_recovery_elapsed := 0.0
var critical_episode_count := 0
var first_rescue_used := false
var failure_recap := ""

var clock_time := 0.0
var trend_sample_elapsed := 0.0
var trend_history: Array = []
var recent_rabbit_deaths: Array = []

func _init(p_config: Dictionary = {}) -> void:
	config = p_config if not p_config.is_empty() else GameConfig.make()
	progression = config["progression"]
	milestones = progression["milestones"]
	supply_pool = str(progression["initial_supply_pool"])
	for item in progression["initial_unlocked"]:
		unlocked[str(item)] = true

func is_unlocked(item: String) -> bool:
	return bool(unlocked.get(item, false))

func current_milestone() -> Dictionary:
	if milestone_index < 0 or milestone_index >= milestones.size():
		return {}
	return milestones[milestone_index]

func current_milestone_id() -> String:
	var milestone := current_milestone()
	return "" if milestone.is_empty() else str(milestone["id"])

func milestone_by_id(milestone_id: String) -> Dictionary:
	for milestone in milestones:
		if str(milestone["id"]) == milestone_id:
			return milestone
	return {}

func milestone_position(milestone_id: String) -> int:
	for index in range(milestones.size()):
		if str(milestones[index]["id"]) == milestone_id:
			return index
	return -1

func has_completed(milestone_id: String) -> bool:
	return milestone_id in completed_milestones

func record_entity_added(kind: String, entity_id: int, reason: String) -> void:
	if kind != "rabbit":
		return
	if reason == "birth":
		born_rabbit_ids[entity_id] = true
		if run_state == STATE_PLAYING:
			milestone_rabbit_births += 1
			_record_ecology_event("birth", entity_id)
	else:
		placed_rabbit_ids[entity_id] = true

func record_entity_removed(kind: String, entity_id: int, _position: Vector2, cause: String) -> void:
	if kind == "rabbit":
		recent_rabbit_deaths.append({"time": clock_time, "id": entity_id, "cause": cause})
		_trim_recent_deaths()

func record_creature_fed(kind: String, entity_id: int, _food_id: int) -> void:
	if run_state != STATE_PLAYING:
		return
	if kind == "rabbit":
		if placed_rabbit_ids.has(entity_id):
			milestone_fed_rabbit_ids[entity_id] = true
		if born_rabbit_ids.has(entity_id):
			milestone_fed_born_rabbit_ids[entity_id] = true
	elif kind == "fox":
		milestone_fed_fox_ids[entity_id] = true

func record_predation(fox_id: int, rabbit_id: int, _position: Vector2) -> void:
	if run_state != STATE_PLAYING:
		return
	milestone_hunts += 1
	milestone_fed_fox_ids[fox_id] = true
	_record_ecology_event("hunt", rabbit_id)

func tick(delta: float, simulation: EcosystemSimulation, _inventory: Dictionary = {}, _supply_choices: Array = [], supply_pending: bool = false) -> void:
	if delta <= 0.0:
		return
	clock_time = simulation.simulation_time
	_trim_recent_deaths()
	if run_state in [STATE_GAME_OVER, STATE_COMPLETED, STATE_SANDBOX]:
		return
	_update_trend(delta, simulation)
	if run_state == STATE_CRITICAL:
		_update_critical(delta, simulation, supply_pending)
		return
	_update_milestone(delta, simulation)
	if run_state == STATE_PLAYING:
		_update_critical_entry(delta, simulation)

func milestone_status(simulation: EcosystemSimulation) -> String:
	var milestone := current_milestone()
	if milestone.is_empty():
		return "The ecosystem is established."
	var phase := milestone_phase(simulation)
	var labels: Dictionary = milestone.get("labels", {})
	return str(labels.get(phase, milestone.get("summary", "Watch the ecosystem.")))

func milestone_phase(simulation: EcosystemSimulation) -> String:
	var milestone := current_milestone()
	if milestone.is_empty():
		return "complete"
	if simulation.population("rabbit") < int(milestone.get("rabbit_min", 0)) \
		or simulation.population("fox") < int(milestone.get("fox_min", 0)):
		return "low"
	if _has_forbidden_starvation(milestone, simulation):
		return "starving"
	if not _milestone_evidence_met(milestone, simulation):
		return "evidence"
	if _is_severely_declining(milestone, simulation):
		return "declining"
	return "stabilizing"

func milestone_progress(simulation: EcosystemSimulation) -> Dictionary:
	var milestone := current_milestone()
	if milestone.is_empty():
		return {}
	var sequence: Array = milestone.get("event_sequence", [])
	var evidence_window := float(milestone.get("evidence_window", 0.0))
	var sequence_remaining := evidence_window
	if sequence_started_at >= 0.0:
		sequence_remaining = maxf(0.0, evidence_window - (clock_time - sequence_started_at))
	var evidence_met := _milestone_evidence_met(milestone, simulation)
	var trend_met := not _is_severely_declining(milestone, simulation)
	var populations_met := simulation.population("rabbit") >= int(milestone.get("rabbit_min", 0)) \
		and simulation.population("fox") >= int(milestone.get("fox_min", 0))
	var starvation_met := not _has_forbidden_starvation(milestone, simulation)
	return {
		"milestone_id": str(milestone["id"]),
		"phase": milestone_phase(simulation),
		"rabbit_count": simulation.population("rabbit"),
		"rabbit_target": int(milestone.get("rabbit_min", 0)),
		"fox_count": simulation.population("fox"),
		"fox_target": int(milestone.get("fox_min", 0)),
		"birth_count": milestone_rabbit_births,
		"birth_target": int(milestone.get("rabbit_births", 0)),
		"hunt_count": milestone_hunts,
		"hunt_target": int(milestone.get("hunts", 0)),
		"fed_founder_count": _living_set_count(milestone_fed_rabbit_ids, simulation.rabbits),
		"fed_born_count": _living_set_count(milestone_fed_born_rabbit_ids, simulation.rabbits),
		"fed_fox_count": _living_set_count(milestone_fed_fox_ids, simulation.foxes),
		"safe_haven_count": last_safe_haven_groups.size(),
		"evidence_met": evidence_met,
		"trend_met": trend_met,
		"populations_met": populations_met,
		"starvation_met": starvation_met,
		"hold_active": evidence_met and trend_met and populations_met and starvation_met,
		"stability_elapsed": milestone_stability,
		"stability_target": float(milestone.get("stabilization", 0.0)),
		"sequence": sequence,
		"sequence_progress": sequence_progress,
		"sequence_started": sequence_started_at >= 0.0,
		"sequence_completed": sequence_completed,
		"sequence_time_remaining": sequence_remaining,
		"evidence_window": evidence_window,
	}

func spatial_evidence(simulation: EcosystemSimulation) -> Dictionary:
	var haven_cfg: Dictionary = progression.get("safe_havens", {})
	var group_size := int(haven_cfg.get("rabbits_per_group", 2))
	var food_radius := float(config["rabbit"]["food_detection_radius"])
	# A haven is a shared local refuge, not a momentary mating contact. The
	# slightly wider neighborhood tolerates normal wandering while remaining
	# well inside a rabbit's forage range.
	var group_radius := minf(food_radius * 0.75, float(config["rabbit"]["mating_radius"]) * 1.65)
	var food_needed := float(haven_cfg.get("minimum_local_food", config["rabbit"]["local_food_needed"]))
	var unvisited: Dictionary = {}
	for rabbit_id in simulation.rabbits:
		unvisited[rabbit_id] = true
	var viable: Array = []
	while not unvisited.is_empty():
		var seed_id: int = unvisited.keys()[0]
		var queue: Array[int] = [seed_id]
		var member_ids: Array[int] = []
		unvisited.erase(seed_id)
		while not queue.is_empty():
			var rabbit_id: int = queue.pop_front()
			member_ids.append(rabbit_id)
			var position: Vector2 = simulation.rabbits[rabbit_id]["position"]
			for other_id in unvisited.keys():
				var other_position: Vector2 = simulation.rabbits[other_id]["position"]
				if position.distance_to(other_position) <= group_radius \
					and simulation.ground_route_distance(position, other_position, group_radius) <= group_radius:
					unvisited.erase(other_id)
					queue.append(other_id)
		if member_ids.size() < group_size:
			continue
		var food_ids: Dictionary = {}
		var every_rabbit_has_food := true
		var center := Vector2.ZERO
		for rabbit_id in member_ids:
			var rabbit_position: Vector2 = simulation.rabbits[rabbit_id]["position"]
			center += rabbit_position
			var rabbit_has_food := false
			for plant_id in simulation.plants:
				var plant: Dictionary = simulation.plants[plant_id]
				if float(plant["food"]) > 0.15 \
					and rabbit_position.distance_to(plant["position"]) <= food_radius \
					and simulation.ground_route_distance(rabbit_position, plant["position"], food_radius) <= food_radius:
					rabbit_has_food = true
					food_ids[plant_id] = true
			if not rabbit_has_food:
				every_rabbit_has_food = false
		var available_food := 0.0
		for plant_id in food_ids:
			available_food += float(simulation.plants[plant_id]["food"])
		if every_rabbit_has_food and available_food >= food_needed:
			viable.append({
				"members": member_ids,
				"center": center / float(member_ids.size()),
				"food": available_food,
			})
	var separation := maxf(
		float(haven_cfg.get("minimum_separation", 300.0)),
		float(config["fox"]["prey_detection_radius"]) * 1.2
	)
	var separated_groups: Array = []
	for first_index in range(viable.size()):
		for second_index in range(first_index + 1, viable.size()):
			if _minimum_group_distance(viable[first_index], viable[second_index], simulation) >= separation:
				separated_groups = [viable[first_index], viable[second_index]]
				break
		if not separated_groups.is_empty():
			break
	last_safe_haven_groups = separated_groups
	return {
		"met": separated_groups.size() >= int(haven_cfg.get("minimum_groups", 2)),
		"viable_group_count": viable.size(),
		"separated_group_count": separated_groups.size(),
		"groups": separated_groups,
		"minimum_separation": separation,
	}

func continue_observing() -> bool:
	if run_state != STATE_COMPLETED:
		return false
	_set_state(STATE_SANDBOX)
	return true

func debug_lines(simulation: EcosystemSimulation = null) -> Array[String]:
	var lines: Array[String] = []
	var milestone := current_milestone()
	if milestone.is_empty():
		lines.append("Run %s · %d/%d checkpoints" % [run_state, completed_milestones.size(), milestones.size()])
	else:
		lines.append("Checkpoint %d/%d · %s" % [milestone_index + 1, milestones.size(), str(milestone["id"])])
		lines.append("Evidence births %d · hunts %d · founders fed %d · born fed %d · foxes fed %d" % [milestone_rabbit_births, milestone_hunts, milestone_fed_rabbit_ids.size(), milestone_fed_born_rabbit_ids.size(), milestone_fed_fox_ids.size()])
		lines.append("Sequence %d/%d · stable %.1fs/%.1fs" % [sequence_progress, milestone.get("event_sequence", []).size(), milestone_stability, float(milestone.get("stabilization", 0.0))])
		if simulation != null:
			var evidence := spatial_evidence(simulation) if str(milestone.get("evidence_type", "")) == "safe_havens" else {}
			lines.append("Population rabbit %d · fox %d · phase %s" % [simulation.population("rabbit"), simulation.population("fox"), milestone_phase(simulation)])
			if not evidence.is_empty():
				lines.append("Havens viable %d · separated %d · separation %.0f" % [evidence["viable_group_count"], evidence["separated_group_count"], evidence["minimum_separation"]])
	lines.append("Critical %s · entry %.1fs · grace %.1fs · recovery %.1fs" % [str(rabbit_failure_armed), critical_entry_elapsed, critical_elapsed, critical_recovery_elapsed])
	return lines

func _update_milestone(delta: float, simulation: EcosystemSimulation) -> void:
	var milestone := current_milestone()
	if milestone.is_empty():
		return
	_expire_sequence(milestone)
	var populations_met := simulation.population("rabbit") >= int(milestone.get("rabbit_min", 0)) \
		and simulation.population("fox") >= int(milestone.get("fox_min", 0))
	var stable := populations_met \
		and _milestone_evidence_met(milestone, simulation) \
		and not _has_forbidden_starvation(milestone, simulation) \
		and not _is_severely_declining(milestone, simulation)
	if stable:
		milestone_stability += delta
	else:
		milestone_stability = 0.0
	if milestone_stability + 0.000001 >= float(milestone.get("stabilization", 0.0)):
		_complete_current_milestone()

func _milestone_evidence_met(milestone: Dictionary, simulation: EcosystemSimulation) -> bool:
	match str(milestone.get("evidence_type", "")):
		"founders_fed":
			return _living_set_count(milestone_fed_rabbit_ids, simulation.rabbits) >= int(milestone.get("distinct_rabbits_fed", 1))
		"rabbit_birth":
			return milestone_rabbit_births >= int(milestone.get("rabbit_births", 1))
		"born_rabbit_fed":
			var survival_age := float(milestone.get("born_survival_age", 0.0))
			for rabbit_id in milestone_fed_born_rabbit_ids:
				if simulation.rabbits.has(rabbit_id) and float(simulation.rabbits[rabbit_id]["age"]) >= survival_age:
					return true
			return false
		"living_fox_fed":
			return milestone_hunts >= int(milestone.get("hunts", 1)) \
				and _living_set_count(milestone_fed_fox_ids, simulation.foxes) >= 1
		"safe_havens":
			return bool(spatial_evidence(simulation)["met"])
		"two_foxes_fed_and_birth":
			return milestone_rabbit_births >= int(milestone.get("rabbit_births", 1)) \
				and _living_set_count(milestone_fed_fox_ids, simulation.foxes) >= int(milestone.get("distinct_foxes_fed", 2))
		"ordered_cycle":
			return sequence_completed
	return true

func _has_forbidden_starvation(milestone: Dictionary, simulation: EcosystemSimulation) -> bool:
	if bool(milestone.get("forbid_active_starvation", false)) and _has_severe_starvation(simulation.hunger_summary("rabbit")):
		return true
	if bool(milestone.get("forbid_fox_starvation", false)) and _has_severe_starvation(simulation.hunger_summary("fox")):
		return true
	return false

func _has_severe_starvation(summary: Dictionary) -> bool:
	var population := int(summary.get("population", 0))
	if population <= 0:
		return false
	var severe_count := maxi(1, ceili(float(population) * 0.20))
	return int(summary.get("starving_count", 0)) >= severe_count

func _complete_current_milestone() -> void:
	var completed_index := milestone_index
	var milestone: Dictionary = milestones[completed_index]
	var milestone_id := str(milestone["id"])
	if milestone_id in completed_milestones:
		return
	completed_milestones.append(milestone_id)
	var effects: Dictionary = milestone.get("effects", {})
	for item in effects.get("unlock", []):
		var item_name := str(item)
		if not is_unlocked(item_name):
			unlocked[item_name] = true
			unlock_changed.emit(item_name, true)
	if effects.has("supply_pool"):
		supply_pool = str(effects["supply_pool"])
	if bool(effects.get("arm_rabbit_failure", false)):
		rabbit_failure_armed = true
	milestone_completed.emit(completed_index, milestone)
	if bool(effects.get("complete_run", false)):
		_set_state(STATE_COMPLETED)
		run_completed.emit()
		return
	milestone_index += 1
	_reset_milestone_evidence()

func _reset_milestone_evidence() -> void:
	milestone_stability = 0.0
	milestone_rabbit_births = 0
	milestone_hunts = 0
	milestone_events.clear()
	milestone_fed_rabbit_ids.clear()
	milestone_fed_born_rabbit_ids.clear()
	milestone_fed_fox_ids.clear()
	sequence_progress = 0
	sequence_started_at = -1.0
	sequence_completed = false
	last_safe_haven_groups.clear()

func _record_ecology_event(event_type: String, entity_id: int) -> void:
	milestone_events.append({"type": event_type, "entity_id": entity_id, "time": clock_time})
	var milestone := current_milestone()
	if not milestone.is_empty() and str(milestone.get("evidence_type", "")) == "ordered_cycle":
		_advance_sequence(event_type, milestone)

func _advance_sequence(event_type: String, milestone: Dictionary) -> void:
	if sequence_completed:
		return
	_expire_sequence(milestone)
	var target: Array = milestone.get("event_sequence", [])
	if target.is_empty():
		return
	if sequence_progress < target.size() and event_type == str(target[sequence_progress]):
		if sequence_progress == 0:
			sequence_started_at = clock_time
		sequence_progress += 1
		if sequence_progress >= target.size():
			sequence_completed = true
		return
	# Extra births or hunts do not erase valid ecological evidence. Only the
	# configured next event advances the ordered cycle, and the window still
	# expires the unfinished sequence as a whole.

func _expire_sequence(milestone: Dictionary) -> void:
	if sequence_completed or sequence_started_at < 0.0:
		return
	var window := float(milestone.get("evidence_window", 0.0))
	if window > 0.0 and clock_time - sequence_started_at > window:
		sequence_progress = 0
		sequence_started_at = -1.0

func _update_trend(delta: float, simulation: EcosystemSimulation) -> void:
	trend_sample_elapsed += delta
	var interval := float(progression.get("trend_sample_interval", 1.0))
	if trend_history.is_empty() or trend_sample_elapsed + 0.000001 >= interval:
		trend_sample_elapsed = 0.0
		trend_history.append({"time": clock_time, "rabbits": simulation.population("rabbit")})
	var history_duration := float(progression.get("trend_history_duration", 35.0))
	while not trend_history.is_empty() and clock_time - float(trend_history[0]["time"]) > history_duration:
		trend_history.pop_front()

func _is_severely_declining(milestone: Dictionary, simulation: EcosystemSimulation) -> bool:
	var window := float(milestone.get("decline_window", 0.0))
	var peak := simulation.population("rabbit")
	for sample in trend_history:
		if clock_time - float(sample["time"]) <= window:
			peak = maxi(peak, int(sample["rabbits"]))
	if peak <= int(milestone.get("rabbit_min", 0)):
		return false
	var fraction := float(milestone.get("severe_decline_fraction", 1.0))
	return simulation.population("rabbit") <= floori(float(peak) * (1.0 - fraction))

func _update_critical_entry(delta: float, simulation: EcosystemSimulation) -> void:
	if not rabbit_failure_armed:
		critical_entry_elapsed = 0.0
		return
	var critical_cfg: Dictionary = progression["critical"]
	if simulation.population("rabbit") < int(critical_cfg["breeding_group"]):
		critical_entry_elapsed += delta
		if critical_entry_elapsed + 0.000001 >= float(critical_cfg["entry_debounce"]):
			_enter_critical()
	else:
		critical_entry_elapsed = 0.0

func _enter_critical() -> void:
	if run_state != STATE_PLAYING:
		return
	critical_entry_elapsed = 0.0
	critical_elapsed = 0.0
	critical_recovery_elapsed = 0.0
	critical_episode_count += 1
	_set_state(STATE_CRITICAL)
	critical_started.emit()
	if not first_rescue_used:
		first_rescue_used = true
		first_recovery_supply_requested.emit()

func _update_critical(delta: float, simulation: EcosystemSimulation, supply_pending: bool) -> void:
	var critical_cfg: Dictionary = progression["critical"]
	if not supply_pending:
		critical_elapsed += delta
	var recovered_population := simulation.population("rabbit") >= int(critical_cfg["recovery_population"])
	var severe_starvation := int(simulation.hunger_summary("rabbit").get("starving_count", 0)) > 0
	if recovered_population and not severe_starvation:
		critical_recovery_elapsed += delta
	else:
		critical_recovery_elapsed = 0.0
	if critical_recovery_elapsed + 0.000001 >= float(critical_cfg["recovery_settling"]):
		critical_elapsed = 0.0
		critical_recovery_elapsed = 0.0
		_set_state(STATE_PLAYING)
		critical_recovered.emit()
		return
	if critical_elapsed + 0.000001 >= float(critical_cfg["grace_duration"]):
		_fail_run(simulation)

func _fail_run(simulation: EcosystemSimulation) -> void:
	var starvation_losses := 0
	var predation_losses := 0
	for death in recent_rabbit_deaths:
		if str(death["cause"]) == "starvation":
			starvation_losses += 1
		elif str(death["cause"]) == "predation":
			predation_losses += 1
	if starvation_losses > predation_losses and starvation_losses > 0:
		failure_recap = "The rabbit colony lost its breeding group after food became unreachable."
	elif predation_losses > 0:
		failure_recap = "Predation outpaced the rabbit colony's ability to recover."
	else:
		failure_recap = "The rabbit colony fell below a viable breeding group and did not recover."
	if simulation.population("fox") == 0 and predation_losses == 0:
		failure_recap += " Fox loss alone did not end the run."
	_set_state(STATE_GAME_OVER)
	run_failed.emit(failure_recap)

func _set_state(new_state: String) -> void:
	if run_state == new_state:
		return
	var previous := run_state
	run_state = new_state
	state_changed.emit(previous, new_state)

func _living_set_count(ids: Dictionary, living: Dictionary) -> int:
	var count := 0
	for entity_id in ids:
		if living.has(entity_id):
			count += 1
	return count

func _minimum_group_distance(first: Dictionary, second: Dictionary, simulation: EcosystemSimulation) -> float:
	var minimum := INF
	for first_id in first["members"]:
		for second_id in second["members"]:
			var first_position: Vector2 = simulation.rabbits[first_id]["position"]
			var second_position: Vector2 = simulation.rabbits[second_id]["position"]
			minimum = minf(minimum, simulation.ground_route_distance(first_position, second_position))
	return minimum

func _trim_recent_deaths() -> void:
	var window := float(progression["critical"].get("recent_event_window", 90.0))
	while not recent_rabbit_deaths.is_empty() and clock_time - float(recent_rabbit_deaths[0]["time"]) > window:
		recent_rabbit_deaths.pop_front()
