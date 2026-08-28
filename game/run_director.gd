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
var milestone_born_rabbit_ids: Dictionary = {}
var milestone_birth_positions: Array[Vector2] = []
var placed_rabbit_ids: Dictionary = {}
var born_rabbit_ids: Dictionary = {}
var sequence_progress := 0
var sequence_started_at := -1.0
var sequence_completed := false
var last_safe_haven_groups: Array = []
var spatial_evidence_cache: Dictionary = {}
var spatial_evidence_cache_key := ""
var spatial_evidence_sampled_at := -INF

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

func record_entity_added(kind: String, entity_id: int, reason: String, position: Vector2 = Vector2.INF) -> void:
	if kind != "rabbit":
		return
	if reason == "birth":
		born_rabbit_ids[entity_id] = true
		if run_state == STATE_PLAYING:
			milestone_rabbit_births += 1
			milestone_born_rabbit_ids[entity_id] = true
			if position != Vector2.INF:
				milestone_birth_positions.append(position)
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
	var criterion_progress := _milestone_criterion_progress(milestone, simulation)
	var evidence_met := _criteria_are_met(criterion_progress)
	var trend_met := not _is_severely_declining(milestone, simulation)
	var populations_met := simulation.population("rabbit") >= int(milestone.get("rabbit_min", 0)) \
		and simulation.population("fox") >= int(milestone.get("fox_min", 0))
	var starvation_met := not _has_forbidden_starvation(milestone, simulation)
	var goals := _milestone_goal_progress(milestone, simulation, criterion_progress, trend_met)
	return {
		"milestone_id": str(milestone["id"]),
		"phase": milestone_phase(simulation),
		"rabbit_count": simulation.population("rabbit"),
		"rabbit_target": int(milestone.get("rabbit_min", 0)),
		"fox_count": simulation.population("fox"),
		"fox_target": int(milestone.get("fox_min", 0)),
		"birth_count": milestone_rabbit_births,
		"birth_target": _criterion_target(criterion_progress, "rabbit_birth"),
		"hunt_count": milestone_hunts,
		"hunt_target": _criterion_target(criterion_progress, "hunts"),
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
		"criteria": criterion_progress,
		"goals": goals,
	}

func spatial_evidence(simulation: EcosystemSimulation, requirements: Dictionary = {}) -> Dictionary:
	var haven_cfg: Dictionary = progression.get("safe_havens", {}).duplicate(true)
	for key in ["rabbits_per_group", "minimum_separation", "minimum_local_food"]:
		if requirements.has(key):
			haven_cfg[key] = requirements[key]
	var required_groups := int(requirements.get("target", haven_cfg.get("minimum_groups", 2)))
	var group_size := int(haven_cfg.get("rabbits_per_group", 2))
	var food_radius := float(config["rabbit"]["food_detection_radius"])
	# A nursery is a bounded local nucleus around a rabbit, not the transitive
	# connected component of every nearby rabbit. This keeps a wandering rabbit
	# or a long Rabbit chain from merging and invalidating otherwise healthy
	# refuges while retaining terrain-aware proximity and forage checks.
	var group_radius := minf(food_radius * 0.75, float(config["rabbit"]["mating_radius"]) * 1.65)
	var food_needed := float(haven_cfg.get("minimum_local_food", config["rabbit"]["local_food_needed"]))
	var forage_by_rabbit: Dictionary = {}
	for rabbit_id in simulation.rabbits:
		var food_ids: Dictionary = {}
		var rabbit_position: Vector2 = simulation.rabbits[rabbit_id]["position"]
		for plant_id in simulation.plants:
			var plant: Dictionary = simulation.plants[plant_id]
			if simulation.plant_is_food_available(plant) \
				and rabbit_position.distance_to(plant["position"]) <= food_radius \
				and simulation.ground_route_distance(rabbit_position, plant["position"], food_radius) <= food_radius:
				food_ids[plant_id] = true
		if not food_ids.is_empty():
			forage_by_rabbit[rabbit_id] = food_ids
	var viable: Array = []
	for seed_id in forage_by_rabbit:
		var seed_position: Vector2 = simulation.rabbits[seed_id]["position"]
		var member_ids: Array[int] = []
		for rabbit_id in forage_by_rabbit:
			var rabbit_position: Vector2 = simulation.rabbits[rabbit_id]["position"]
			if seed_position.distance_to(rabbit_position) > group_radius \
				or simulation.ground_route_distance(seed_position, rabbit_position, group_radius) > group_radius:
				continue
			member_ids.append(rabbit_id)
		if member_ids.size() < group_size:
			continue
		var food_ids: Dictionary = {}
		for plant_id in forage_by_rabbit[seed_id]:
			var plant_position: Vector2 = simulation.plants[plant_id]["position"]
			if seed_position.distance_to(plant_position) <= group_radius \
				and simulation.ground_route_distance(seed_position, plant_position, group_radius) <= group_radius:
				food_ids[plant_id] = true
		var available_food := 0.0
		for plant_id in food_ids:
			available_food += float(simulation.plants[plant_id]["food"])
		if available_food >= food_needed:
			viable.append({
				"members": member_ids,
				"center": seed_position,
				"food": available_food,
				"food_ids": food_ids.duplicate(),
			})
	var separation := float(haven_cfg.get("minimum_separation", 300.0))
	var separated_groups := _select_separated_nursery_zones(viable, required_groups, separation, simulation)
	last_safe_haven_groups = separated_groups
	return {
		"met": separated_groups.size() >= required_groups,
		"viable_group_count": viable.size(),
		"separated_group_count": separated_groups.size(),
		"groups": separated_groups,
		"minimum_separation": separation,
		"required_groups": required_groups,
	}

func _select_separated_nursery_zones(candidates: Array, required_groups: int, minimum_separation: float, simulation: EcosystemSimulation) -> Array:
	if candidates.is_empty() or required_groups <= 0:
		return []
	var best: Array = []
	# Several projection orders keep a dense central candidate from masking two
	# valid outer nurseries. The search remains bounded even at the live Rabbit
	# cap, and naturally supports targets above two.
	var directions := [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.DOWN,
		Vector2.UP,
		Vector2(1.0, 1.0).normalized(),
		Vector2(-1.0, 1.0).normalized(),
		Vector2(1.0, -1.0).normalized(),
		Vector2(-1.0, -1.0).normalized(),
	]
	for direction in directions:
		var ordered := candidates.duplicate()
		ordered.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			var first_projection: float = Vector2(first["center"]).dot(direction)
			var second_projection: float = Vector2(second["center"]).dot(direction)
			if not is_equal_approx(first_projection, second_projection):
				return first_projection < second_projection
			return int(first["members"].size()) > int(second["members"].size())
		)
		var selected: Array = []
		for candidate in ordered:
			var separated := true
			for existing in selected:
				if not _nursery_zones_are_separated(candidate, existing, minimum_separation, simulation):
					separated = false
					break
			if not separated:
				continue
			selected.append(candidate)
			if selected.size() >= required_groups:
				break
		if selected.size() > best.size():
			best = selected
		if best.size() >= required_groups:
			break
	return best

func _nursery_zones_are_separated(first: Dictionary, second: Dictionary, minimum_separation: float, simulation: EcosystemSimulation) -> bool:
	for first_id in first["members"]:
		if first_id in second["members"]:
			return false
	for first_food_id in first["food_ids"]:
		if second["food_ids"].has(first_food_id):
			return false
	var first_center: Vector2 = first["center"]
	var second_center: Vector2 = second["center"]
	if first_center.distance_to(second_center) >= minimum_separation:
		return true
	return simulation.ground_route_distance(first_center, second_center, minimum_separation) >= minimum_separation

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
			var evidence := {}
			for configured in milestone.get("criteria", []):
				if str(configured.get("type", "")) == "safe_havens":
					evidence = spatial_evidence(simulation, configured)
					break
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
	return _criteria_are_met(_milestone_criterion_progress(milestone, simulation))

func _milestone_criterion_progress(milestone: Dictionary, simulation: EcosystemSimulation) -> Array:
	var results: Array = []
	for configured in milestone.get("criteria", []):
		var criterion: Dictionary = configured
		results.append(_criterion_progress(criterion, milestone, simulation))
	return results

func _criterion_progress(criterion: Dictionary, milestone: Dictionary, simulation: EcosystemSimulation) -> Dictionary:
	var criterion_type := str(criterion.get("type", ""))
	var target := int(criterion.get("target", 1))
	var current := 0
	match criterion_type:
		"founders_fed":
			current = _living_set_count(milestone_fed_rabbit_ids, simulation.rabbits)
		"rabbit_birth":
			current = milestone_rabbit_births
		"born_rabbit_fed":
			var eligible_ids: Dictionary = milestone_born_rabbit_ids if bool(criterion.get("fresh_only", false)) else born_rabbit_ids
			var minimum_age := float(criterion.get("minimum_age", milestone.get("born_survival_age", 0.0)))
			for rabbit_id in milestone_fed_born_rabbit_ids:
				if eligible_ids.has(rabbit_id) and simulation.rabbits.has(rabbit_id) \
					and float(simulation.rabbits[rabbit_id]["age"]) >= minimum_age:
					current += 1
		"hunts":
			current = milestone_hunts
		"distinct_foxes_fed":
			current = _living_set_count(milestone_fed_fox_ids, simulation.foxes)
		"safe_havens":
			var evidence := _cached_spatial_evidence(simulation, criterion)
			current = int(evidence["separated_group_count"])
		"separated_birth_zones":
			current = _separated_birth_zone_count(float(criterion.get("minimum_separation", 220.0)))
		"ordered_cycle":
			target = milestone.get("event_sequence", []).size()
			current = target if sequence_completed else sequence_progress
		"prey_per_fox":
			var fox_count := simulation.population("fox")
			current = simulation.population("rabbit") if fox_count <= 0 else floori(float(simulation.population("rabbit")) / float(fox_count))
		_:
			target = 1
			current = 1
	var result := {
		"id": str(criterion.get("id", criterion_type)),
		"type": criterion_type,
		"label": str(criterion.get("label", "Ecological evidence")),
		"metric_label": str(criterion.get("metric_label", "ECOLOGICAL PROOF")),
		"kind": str(criterion.get("kind", _criterion_kind(criterion_type))),
		"current": current,
		"target": target,
		"met": current >= target,
	}
	for detail in ["rabbits_per_group", "minimum_local_food", "minimum_separation"]:
		if criterion.has(detail):
			result[detail] = criterion[detail]
	return result

func _milestone_goal_progress(milestone: Dictionary, simulation: EcosystemSimulation, criterion_progress: Array, trend_met: bool) -> Array:
	var goals: Array = []
	var rabbit_target := int(milestone.get("rabbit_min", 0))
	if rabbit_target > 0:
		goals.append(_goal_result("rabbit_population", "rabbit_population", "Rabbits alive", "RABBITS ALIVE", "rabbit", simulation.population("rabbit"), rabbit_target))
	var fox_target := int(milestone.get("fox_min", 0))
	if fox_target > 0:
		goals.append(_goal_result("fox_population", "fox_population", "Foxes alive", "FOXES ALIVE", "fox", simulation.population("fox"), fox_target))
	for result in criterion_progress:
		goals.append(result)
	if bool(milestone.get("forbid_active_starvation", false)):
		goals.append(_health_goal_result("rabbit_health", "rabbit", simulation.hunger_summary("rabbit")))
	if bool(milestone.get("forbid_fox_starvation", false)):
		goals.append(_health_goal_result("fox_health", "fox", simulation.hunger_summary("fox")))
	if float(milestone.get("decline_window", 0.0)) > 0.0:
		goals.append(_trend_goal_result(milestone, simulation, trend_met))
	return goals

func _health_goal_result(id: String, kind: String, summary: Dictionary) -> Dictionary:
	var population := int(summary.get("population", 0))
	var starving_count := int(summary.get("starving_count", 0))
	var warning_count := int(summary.get("warning_count", 0))
	var blocked_at := maxi(1, ceili(float(population) * 0.20)) if population > 0 else 1
	var maximum_allowed := blocked_at - 1
	var met := starving_count <= maximum_allowed
	var status := "absent" if population <= 0 else ("starving" if not met else ("hungry" if warning_count > 0 else "fed"))
	var display_name := "Rabbits" if kind == "rabbit" else "Foxes"
	return {
		"id": id,
		"type": "health",
		"label": "%s hunger" % display_name.trim_suffix("s"),
		"metric_label": "%s HUNGER" % display_name.to_upper(),
		"kind": kind,
		"current": starving_count,
		"target": maximum_allowed,
		"met": met,
		"status": status,
		"warning_count": warning_count,
		"population": population,
		"tooltip": "%d of %d %s starving. This checkpoint pauses above %d." % [starving_count, population, display_name.to_lower(), maximum_allowed],
		"unmet_state": "danger",
	}

func _trend_goal_result(milestone: Dictionary, simulation: EcosystemSimulation, trend_met: bool) -> Dictionary:
	var window := float(milestone.get("decline_window", 0.0))
	var current_population := simulation.population("rabbit")
	var peak := current_population
	for sample in trend_history:
		if clock_time - float(sample["time"]) <= window:
			peak = maxi(peak, int(sample["rabbits"]))
	var loss_percent := 0
	if peak > 0:
		loss_percent = roundi(float(peak - current_population) / float(peak) * 100.0)
	var maximum_percent := roundi(float(milestone.get("severe_decline_fraction", 1.0)) * 100.0)
	return {
		"id": "rabbit_trend",
		"type": "trend",
		"label": "Rabbit loss (%ds)" % roundi(window),
		"metric_label": "RECENT RABBIT LOSS",
		"kind": "rabbit",
		"current": loss_percent,
		"target": maximum_percent,
		"met": trend_met,
		"tooltip": "%d rabbits now; recent peak %d. The checkpoint pauses if losses exceed %d%%." % [current_population, peak, maximum_percent],
		"unmet_state": "danger",
	}

func _goal_result(id: String, type: String, label: String, metric_label: String, kind: String, current: int, target: int, unmet_state: String = "warning") -> Dictionary:
	return {
		"id": id,
		"type": type,
		"label": label,
		"metric_label": metric_label,
		"kind": kind,
		"current": current,
		"target": target,
		"met": current >= target,
		"unmet_state": unmet_state,
	}

func _criteria_are_met(results: Array) -> bool:
	for result in results:
		if not bool(result.get("met", false)):
			return false
	return true

func _criterion_target(results: Array, criterion_type: String) -> int:
	for result in results:
		if str(result.get("type", "")) == criterion_type:
			return int(result.get("target", 0))
	return 0

func _criterion_kind(criterion_type: String) -> String:
	if criterion_type in ["founders_fed", "rabbit_birth", "born_rabbit_fed", "safe_havens", "separated_birth_zones", "prey_per_fox"]:
		return "rabbit"
	if criterion_type in ["hunts", "distinct_foxes_fed"]:
		return "fox"
	return "leaf"

func _separated_birth_zone_count(minimum_separation: float) -> int:
	var representatives: Array[Vector2] = []
	for position in milestone_birth_positions:
		var separated := true
		for existing in representatives:
			if position.distance_to(existing) < minimum_separation:
				separated = false
				break
		if separated:
			representatives.append(position)
	return representatives.size()

func _cached_spatial_evidence(simulation: EcosystemSimulation, requirements: Dictionary) -> Dictionary:
	var cache_key := str(requirements)
	var interval := float(progression.get("spatial_sample_interval", 0.5))
	if interval > 0.0 and cache_key == spatial_evidence_cache_key \
		and not spatial_evidence_cache.is_empty() and clock_time - spatial_evidence_sampled_at < interval:
		last_safe_haven_groups = spatial_evidence_cache.get("groups", [])
		return spatial_evidence_cache
	spatial_evidence_cache = spatial_evidence(simulation, requirements)
	spatial_evidence_cache_key = cache_key
	spatial_evidence_sampled_at = clock_time
	return spatial_evidence_cache

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
	milestone_born_rabbit_ids.clear()
	milestone_birth_positions.clear()
	spatial_evidence_cache.clear()
	spatial_evidence_cache_key = ""
	spatial_evidence_sampled_at = -INF
	sequence_progress = 0
	sequence_started_at = -1.0
	sequence_completed = false
	last_safe_haven_groups.clear()

func _record_ecology_event(event_type: String, entity_id: int) -> void:
	milestone_events.append({"type": event_type, "entity_id": entity_id, "time": clock_time})
	var milestone := current_milestone()
	if not milestone.is_empty() and not milestone.get("event_sequence", []).is_empty():
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

func _trim_recent_deaths() -> void:
	var window := float(progression["critical"].get("recent_event_window", 90.0))
	while not recent_rabbit_deaths.is_empty() and clock_time - float(recent_rabbit_deaths[0]["time"]) > window:
		recent_rabbit_deaths.pop_front()
