class_name TemperateWildsTerrain
extends RefCounted

## Concrete V0.4 terrain model. Land cover remains analytic and continuous;
## the Stream is a separate hydrology layer with a few explicit ground fords.

var config: Dictionary
var seed_value: int
var maximum_radius: float
var initial_radius: float

var woodland_patches: Array = []
var thicket_patches: Array = []
var stream_points := PackedVector2Array()
var stream_half_widths := PackedFloat32Array()
var fords: Array = []

var _terrain_bins: Dictionary = {}
var _terrain_bin_size := 240.0
var _stream_bins: Dictionary = {}
var _stream_bin_size := 128.0

func _init(p_config: Dictionary, p_seed: int) -> void:
	config = p_config
	seed_value = p_seed
	maximum_radius = float(config["world"]["maximum_radius"])
	initial_radius = float(config["world"]["initial_radius"])
	_terrain_bin_size = float(config.get("terrain", {}).get("query_bin_size", 240.0))
	_generate_woodland()
	_generate_stream()
	_rebuild_stream_bins()
	_generate_thicket()
	_rebuild_terrain_bins()

func boundary_radius_at(angle: float, radius_override: float) -> float:
	return radius_override * (1.0 + sin(angle * 5.0 + 0.8) * 0.018 + sin(angle * 9.0 - 1.7) * 0.012)

func is_inside_world(position: Vector2, world_radius: float, clearance: float = 0.0) -> bool:
	return position.length() <= boundary_radius_at(position.angle(), world_radius) - clearance

func can_occupy_ground(position: Vector2, world_radius: float, clearance: float = 0.0) -> bool:
	return is_inside_world(position, world_radius, clearance) and not is_deep_water(position)

func woodland_cover(position: Vector2) -> float:
	return _cover_from_kind(position, "woodland")

func thicket_cover(position: Vector2) -> float:
	return _cover_from_kind(position, "thicket")

func meadow_cover(position: Vector2) -> float:
	if is_water(position):
		return 0.0
	return clampf(1.0 - maxf(woodland_cover(position), thicket_cover(position)), 0.0, 1.0)

func habitat_at(position: Vector2) -> Dictionary:
	var woodland := woodland_cover(position)
	var thicket := thicket_cover(position)
	var water := water_depth(position)
	return {
		"meadow": 0.0 if water > 0.0 else clampf(1.0 - maxf(woodland, thicket), 0.0, 1.0),
		"woodland": woodland,
		"thicket": thicket,
		"water": water,
		"deep_water": is_deep_water(position),
	}

func local_habitat_composition(position: Vector2, radius: float = 72.0, sample_count: int = 12) -> Dictionary:
	var meadow := meadow_cover(position)
	var woodland := woodland_cover(position)
	var thicket := thicket_cover(position)
	var water := water_depth(position)
	var samples := maxi(1, sample_count) + 1
	for index in range(maxi(1, sample_count)):
		var direction := Vector2.from_angle(float(index) / float(maxi(1, sample_count)) * TAU)
		var sample := position + direction * radius
		meadow += meadow_cover(sample)
		woodland += woodland_cover(sample)
		thicket += thicket_cover(sample)
		water += water_depth(sample)
	return {
		"meadow": meadow / float(samples),
		"woodland": woodland / float(samples),
		"thicket": thicket / float(samples),
		"water": water / float(samples),
	}

func food_suitability(plant_type: String, position: Vector2) -> float:
	var composition := local_habitat_composition(position, 58.0, 8)
	var suitability_cfg: Dictionary = config.get("terrain", {}).get("food_suitability", {})
	if plant_type == "carrot_patch":
		var carrot_minimum := float(suitability_cfg.get("carrot_minimum", 0.42))
		return clampf(
			carrot_minimum + float(composition["meadow"]) * float(suitability_cfg.get("carrot_meadow_bonus", 0.78)),
			carrot_minimum,
			float(suitability_cfg.get("carrot_maximum", 1.20)),
		)
	if plant_type == "berry_bush":
		var woodland: float = composition["woodland"]
		var thicket: float = composition["thicket"]
		var sheltered := maxf(woodland, thicket)
		var margin_peak := float(suitability_cfg.get("berry_margin_peak", 0.46))
		var margin := 1.0 - absf(sheltered - margin_peak) / maxf(0.01, margin_peak)
		var deep_cover_penalty := smoothstep(
			float(suitability_cfg.get("berry_deep_cover_start", 0.68)),
			1.0,
			sheltered,
		) * float(suitability_cfg.get("berry_deep_cover_penalty", 0.34))
		return clampf(
			float(suitability_cfg.get("berry_base", 0.62))
				+ maxf(0.0, margin) * float(suitability_cfg.get("berry_margin_bonus", 0.62))
				- deep_cover_penalty,
			float(suitability_cfg.get("berry_minimum", 0.46)),
			float(suitability_cfg.get("berry_maximum", 1.24)),
		)
	return 1.0

func food_capacity_factor(plant_type: String, position: Vector2) -> float:
	var suitability := food_suitability(plant_type, position)
	var suitability_cfg: Dictionary = config.get("terrain", {}).get("food_suitability", {})
	var minimum: float
	var maximum: float
	if plant_type == "carrot_patch":
		minimum = float(suitability_cfg.get("carrot_minimum", 0.42))
		maximum = float(suitability_cfg.get("carrot_maximum", 1.20))
	else:
		minimum = float(suitability_cfg.get("berry_minimum", 0.46))
		maximum = float(suitability_cfg.get("berry_maximum", 1.24))
	var quality := clampf(inverse_lerp(minimum, maximum, suitability), 0.0, 1.0)
	return lerpf(
		float(suitability_cfg.get("poor_capacity_factor", 0.48)),
		float(suitability_cfg.get("rich_capacity_factor", 1.28)),
		quality,
	)

func ground_speed_factor(kind: String, position: Vector2) -> float:
	var cover := thicket_cover(position)
	var terrain_cfg: Dictionary = config.get("terrain", {})
	var thicket_cfg: Dictionary = terrain_cfg.get("thicket", {})
	if kind == "fox":
		return lerpf(1.0, float(thicket_cfg.get("fox_speed_factor", 0.74)), cover)
	if kind == "rabbit":
		return lerpf(1.0, float(thicket_cfg.get("rabbit_speed_factor", 0.96)), cover)
	return 1.0

func water_depth(position: Vector2) -> float:
	if stream_points.size() < 2:
		return 0.0
	var info := _near_stream_info(position)
	if info.is_empty():
		return 0.0
	var distance: float = absf(info["signed_distance"])
	var half_width: float = info["half_width"]
	if distance > half_width + 5.0:
		return 0.0
	var raw_depth := clampf(1.0 - distance / maxf(1.0, half_width), 0.0, 1.0)
	var ford_strength := _ford_strength(position)
	return raw_depth * (1.0 - ford_strength * 0.88)

func is_water(position: Vector2) -> bool:
	return water_depth(position) > 0.02

func is_deep_water(position: Vector2) -> bool:
	var stream_cfg: Dictionary = config.get("terrain", {}).get("stream", {})
	return water_depth(position) >= float(stream_cfg.get("deep_water_threshold", 0.34))

func stream_info(position: Vector2) -> Dictionary:
	if stream_points.size() < 2:
		return {}
	var nearby: Array = _stream_bins.get(_stream_bin(position), [])
	if not nearby.is_empty():
		return _best_stream_info(position, nearby)
	var all_segments: Array = []
	for index in range(stream_points.size() - 1):
		all_segments.append(index)
	return _best_stream_info(position, all_segments)

func _best_stream_info(position: Vector2, segment_indices: Array) -> Dictionary:
	var best_distance_squared := INF
	var best: Dictionary = {}
	for index_value in segment_indices:
		var index := int(index_value)
		var first := stream_points[index]
		var second := stream_points[index + 1]
		var segment := second - first
		var length_squared := segment.length_squared()
		if length_squared <= 0.0001:
			continue
		var amount := clampf((position - first).dot(segment) / length_squared, 0.0, 1.0)
		var closest := first + segment * amount
		var distance_squared := position.distance_squared_to(closest)
		if distance_squared >= best_distance_squared:
			continue
		best_distance_squared = distance_squared
		var tangent := segment.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var width := lerpf(stream_half_widths[index], stream_half_widths[index + 1], amount)
		best = {
			"closest": closest,
			"tangent": tangent,
			"normal": normal,
			"signed_distance": (position - closest).dot(normal),
			"distance": sqrt(distance_squared),
			"half_width": width,
			"segment": index,
		}
	return best

func stream_side(position: Vector2) -> int:
	var info := stream_info(position)
	if info.is_empty():
		return 0
	return 1 if float(info["signed_distance"]) >= 0.0 else -1

func water_escape_direction(position: Vector2) -> Vector2:
	var info := stream_info(position)
	if info.is_empty():
		return Vector2.ZERO
	var side := 1.0 if float(info["signed_distance"]) >= 0.0 else -1.0
	return Vector2(info["normal"]) * side

func route_between(start: Vector2, target: Vector2, world_radius: float, maximum_distance: float = INF) -> Dictionary:
	var direct_distance := start.distance_to(target)
	var unavailable := {
		"reachable": false,
		"distance": INF,
		"direct_distance": direct_distance,
		"waypoints": [],
		"ford": Vector2.INF,
	}
	if not can_occupy_ground(start, world_radius) or not can_occupy_ground(target, world_radius):
		return unavailable
	if direct_distance > maximum_distance:
		return unavailable
	if direct_path_clear(start, target):
		return {
			"reachable": true,
			"distance": direct_distance,
			"direct_distance": direct_distance,
			"waypoints": [],
			"ford": Vector2.INF,
		}
	var start_side := stream_side(start)
	var target_side := stream_side(target)
	var best := unavailable
	for ford in fords:
		var center: Vector2 = ford["position"]
		if not is_inside_world(center, world_radius, 4.0):
			continue
		var normal: Vector2 = ford["normal"]
		var bank_clearance: float = config.get("terrain", {}).get("routing", {}).get("bank_approach_clearance", 22.0)
		var bank_distance: float = ford["half_width"] + bank_clearance
		var start_approach := center + normal * float(start_side) * bank_distance
		var target_approach := center + normal * float(target_side) * bank_distance
		if not can_occupy_ground(start_approach, world_radius, 2.0) or not can_occupy_ground(target_approach, world_radius, 2.0):
			continue
		var waypoints: Array = []
		var route_distance := INF
		var valid := false
		if start_side != target_side:
			valid = direct_path_clear(start, start_approach) and direct_path_clear(target_approach, target)
			if valid:
				waypoints = [start_approach, center, target_approach]
				route_distance = start.distance_to(start_approach) + start_approach.distance_to(center) + center.distance_to(target_approach) + target_approach.distance_to(target)
		else:
			valid = direct_path_clear(start, start_approach) and direct_path_clear(start_approach, target)
			if valid:
				waypoints = [start_approach]
				route_distance = start.distance_to(start_approach) + start_approach.distance_to(target)
		if valid and route_distance <= maximum_distance and route_distance < float(best["distance"]):
			best = {
				"reachable": true,
				"distance": route_distance,
				"direct_distance": direct_distance,
				"waypoints": waypoints,
				"ford": center,
			}
	return best

func route_distance(start: Vector2, target: Vector2, world_radius: float, maximum_distance: float = INF) -> float:
	return float(route_between(start, target, world_radius, maximum_distance)["distance"])

func direct_path_clear(start: Vector2, target: Vector2) -> bool:
	var distance := start.distance_to(target)
	if distance <= 0.001:
		return not is_deep_water(start)
	var spacing: float = config.get("terrain", {}).get("routing", {}).get("path_sample_spacing", 11.0)
	var steps := maxi(1, ceili(distance / spacing))
	for index in range(1, steps):
		if is_deep_water(start.lerp(target, float(index) / float(steps))):
			return false
	return true

func nearest_reachable_thicket(position: Vector2, threat_position: Vector2, world_radius: float, maximum_route: float) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	var current_threat_distance := position.distance_to(threat_position)
	for patch in thicket_patches:
		var center: Vector2 = patch["center"]
		# The geometric center made every fleeing Rabbit converge on one point and
		# then oscillate around it once the route was complete. Aim for a spread of
		# deep-cover points on the side away from the threat instead. Thicket still
		# disrupts pursuit without becoming an invulnerable sanctuary.
		var away := center - threat_position
		if away.length_squared() < 0.01:
			away = position - threat_position
		if away.length_squared() < 0.01:
			away = Vector2.RIGHT
		away = away.normalized()
		var tangent := Vector2(-away.y, away.x)
		var radius := float(patch["radius"])
		var lateral := clampf((position - center).dot(tangent) * 0.72, -radius * 0.28, radius * 0.28)
		var candidate := center + away * radius * 0.50 + tangent * lateral
		if not can_occupy_ground(candidate, world_radius, 4.0) or thicket_cover(candidate) < 0.5:
			candidate = center
		if not can_occupy_ground(candidate, world_radius, 4.0):
			continue
		if thicket_cover(candidate) < 0.5:
			continue
		var route := route_between(position, candidate, world_radius, maximum_route)
		if not bool(route["reachable"]):
			continue
		var threat_distance := candidate.distance_to(threat_position)
		if threat_distance + 6.0 < current_threat_distance:
			continue
		var score: float = route["distance"] - (threat_distance - current_threat_distance) * 0.34
		if score < best_score:
			best_score = score
			best = {
				"position": candidate,
				"route": route,
				"cover": thicket_cover(candidate),
			}
	return best

func nearest_reachable_woodland(position: Vector2, world_radius: float, maximum_route: float) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for patch in woodland_patches:
		var candidate: Vector2 = patch["center"]
		if position.distance_to(candidate) > maximum_route:
			continue
		if not can_occupy_ground(candidate, world_radius, 4.0):
			continue
		if woodland_cover(candidate) < 0.5:
			continue
		var route := route_between(position, candidate, world_radius, maximum_route)
		if bool(route["reachable"]) and float(route["distance"]) < best_distance:
			best_distance = route["distance"]
			best = {
				"position": candidate,
				"route": route,
				"cover": woodland_cover(candidate),
			}
	return best

func generation_summary(world_radius: float) -> Dictionary:
	var samples := {"meadow": 0, "woodland": 0, "thicket": 0, "stream": 0}
	var rings := [world_radius * 0.28, world_radius * 0.58, world_radius * 0.84]
	for radius in rings:
		for index in range(24):
			var point := Vector2.from_angle(float(index) / 24.0 * TAU) * float(radius)
			var habitat := habitat_at(point)
			if float(habitat["water"]) > 0.1:
				samples["stream"] += 1
			elif float(habitat["thicket"]) > 0.45:
				samples["thicket"] += 1
			elif float(habitat["woodland"]) > 0.45:
				samples["woodland"] += 1
			else:
				samples["meadow"] += 1
	return {
		"samples": samples,
		"woodland_patches": woodland_patches.size(),
		"thicket_patches": thicket_patches.size(),
		"stream_points": stream_points.size(),
		"visible_fords": _visible_ford_count(world_radius),
	}

func _generate_woodland() -> void:
	woodland_patches.clear()
	var patch_rng := RandomNumberGenerator.new()
	patch_rng.seed = seed_value + 7719
	var world_cfg: Dictionary = config["world"]
	for index in range(int(world_cfg["forest_patch_count"])):
		var angle := patch_rng.randf_range(0.0, TAU)
		var distance := sqrt(patch_rng.randf()) * maximum_radius * 0.88
		var patch_radius := patch_rng.randf_range(world_cfg["forest_patch_min_radius"], world_cfg["forest_patch_max_radius"])
		woodland_patches.append(_make_patch(
			Vector2.from_angle(angle) * distance,
			patch_radius,
			patch_rng.randf_range(0.72, 1.28),
			patch_rng.randf_range(0.0, TAU),
			patch_rng.randf(),
			"woodland",
		))

func _generate_thicket() -> void:
	thicket_patches.clear()
	var terrain_cfg: Dictionary = config.get("terrain", {})
	var thicket_cfg: Dictionary = terrain_cfg.get("thicket", {})
	var count := int(thicket_cfg.get("patch_count", 22))
	var minimum_radius := float(thicket_cfg.get("patch_min_radius", 44.0))
	var maximum_patch_radius := float(thicket_cfg.get("patch_max_radius", 88.0))
	var patch_rng := RandomNumberGenerator.new()
	patch_rng.seed = seed_value + 19337
	for index in range(count):
		var center: Vector2
		if index < 4 and stream_points.size() >= 2:
			# Put the first readable refuge choices beside both Stream banks. This
			# makes the food/cover/crossing tradeoff visible in the initial world
			# without hard-scripting checkpoint-specific terrain.
			var bank_amounts := [0.395, 0.445, 0.555, 0.605]
			var frame := _stream_frame_at(float(bank_amounts[index]))
			var side := -1.0 if index % 2 == 0 else 1.0
			center = Vector2(frame["position"]) + Vector2(frame["normal"]) * side * (float(frame["half_width"]) + patch_rng.randf_range(58.0, 84.0))
		else:
			var angle := patch_rng.randf_range(0.0, TAU)
			var distance := lerpf(initial_radius * 0.72, maximum_radius * 0.91, sqrt(patch_rng.randf()))
			center = Vector2.from_angle(angle) * distance
		if is_deep_water(center):
			center += water_escape_direction(center) * 70.0
		thicket_patches.append(_make_patch(
			center,
			patch_rng.randf_range(minimum_radius, maximum_patch_radius),
			patch_rng.randf_range(0.64, 1.34),
			patch_rng.randf_range(0.0, TAU),
			patch_rng.randf(),
			"thicket",
		))

func _generate_stream() -> void:
	stream_points.clear()
	stream_half_widths.clear()
	fords.clear()
	var stream_cfg: Dictionary = config.get("terrain", {}).get("stream", {})
	if not bool(stream_cfg.get("enabled", true)):
		return
	var stream_rng := RandomNumberGenerator.new()
	stream_rng.seed = seed_value + 31847
	var count := maxi(17, int(stream_cfg.get("point_count", 49)))
	var extent := maximum_radius * 1.18
	var rotation := stream_rng.randf_range(-0.48, 0.48)
	var base_offset := initial_radius * float(stream_cfg.get("initial_offset_ratio", 0.47))
	var phase := stream_rng.randf_range(0.0, TAU)
	var meander := float(stream_cfg.get("meander", 62.0))
	var min_width := float(stream_cfg.get("half_width_min", 20.0))
	var max_width := float(stream_cfg.get("half_width_max", 28.0))
	for index in range(count):
		var amount := float(index) / float(count - 1)
		var local_y := lerpf(-extent, extent, amount)
		var local_x := base_offset \
			+ sin(amount * TAU * 1.55 + phase) * meander \
			+ sin(amount * TAU * 3.4 - phase * 0.37) * meander * 0.24
		stream_points.append(Vector2(local_x, local_y).rotated(rotation))
		var width_noise := sin(amount * TAU * 2.7 + phase * 1.6) * 0.5 + 0.5
		stream_half_widths.append(lerpf(min_width, max_width, width_noise))
	var ford_positions: Array = stream_cfg.get("ford_positions", [0.22, 0.47, 0.76])
	var ford_radius := float(stream_cfg.get("ford_radius", 40.0))
	for ford_amount_value in ford_positions:
		var ford_amount := clampf(float(ford_amount_value), 0.05, 0.95)
		var scaled := ford_amount * float(stream_points.size() - 1)
		var index := mini(stream_points.size() - 2, floori(scaled))
		var blend := scaled - float(index)
		var center := stream_points[index].lerp(stream_points[index + 1], blend)
		var tangent := (stream_points[index + 1] - stream_points[index]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		fords.append({
			"position": center,
			"tangent": tangent,
			"normal": normal,
			"radius": ford_radius,
			"half_width": lerpf(stream_half_widths[index], stream_half_widths[index + 1], blend),
		})

func _stream_frame_at(amount: float) -> Dictionary:
	var scaled := clampf(amount, 0.0, 1.0) * float(stream_points.size() - 1)
	var index := mini(stream_points.size() - 2, floori(scaled))
	var blend := scaled - float(index)
	var tangent := (stream_points[index + 1] - stream_points[index]).normalized()
	return {
		"position": stream_points[index].lerp(stream_points[index + 1], blend),
		"tangent": tangent,
		"normal": Vector2(-tangent.y, tangent.x),
		"half_width": lerpf(stream_half_widths[index], stream_half_widths[index + 1], blend),
	}

func _make_patch(center: Vector2, radius: float, squash: float, rotation: float, tone: float, kind: String) -> Dictionary:
	return {
		"center": center,
		"radius": radius,
		"squash": squash,
		"rotation": rotation,
		"tone": tone,
		"kind": kind,
	}

func _rebuild_terrain_bins() -> void:
	_terrain_bins.clear()
	for patch in woodland_patches:
		_insert_patch_bins(patch)
	for patch in thicket_patches:
		_insert_patch_bins(patch)

func _rebuild_stream_bins() -> void:
	_stream_bins.clear()
	for index in range(stream_points.size() - 1):
		var first := stream_points[index]
		var second := stream_points[index + 1]
		var extent := maxf(stream_half_widths[index], stream_half_widths[index + 1]) + 9.0
		var minimum := _stream_bin(Vector2(minf(first.x, second.x), minf(first.y, second.y)) - Vector2.ONE * extent)
		var maximum := _stream_bin(Vector2(maxf(first.x, second.x), maxf(first.y, second.y)) + Vector2.ONE * extent)
		for cell_x in range(minimum.x, maximum.x + 1):
			for cell_y in range(minimum.y, maximum.y + 1):
				var key := Vector2i(cell_x, cell_y)
				if not _stream_bins.has(key):
					_stream_bins[key] = []
				_stream_bins[key].append(index)

func _insert_patch_bins(patch: Dictionary) -> void:
	var extent: float = patch["radius"] * maxf(1.0, float(patch["squash"])) * 1.3
	var center: Vector2 = patch["center"]
	var minimum := _terrain_bin(center - Vector2.ONE * extent)
	var maximum := _terrain_bin(center + Vector2.ONE * extent)
	for cell_x in range(minimum.x, maximum.x + 1):
		for cell_y in range(minimum.y, maximum.y + 1):
			var key := Vector2i(cell_x, cell_y)
			if not _terrain_bins.has(key):
				_terrain_bins[key] = []
			_terrain_bins[key].append(patch)

func _terrain_bin(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / _terrain_bin_size), floori(position.y / _terrain_bin_size))

func _stream_bin(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / _stream_bin_size), floori(position.y / _stream_bin_size))

func _near_stream_info(position: Vector2) -> Dictionary:
	var nearby: Array = _stream_bins.get(_stream_bin(position), [])
	return {} if nearby.is_empty() else _best_stream_info(position, nearby)

func _cover_from_kind(position: Vector2, kind: String) -> float:
	var strongest := 0.0
	for patch in _terrain_bins.get(_terrain_bin(position), []):
		if str(patch["kind"]) != kind:
			continue
		var local: Vector2 = (position - Vector2(patch["center"])).rotated(-float(patch["rotation"]))
		local.y /= float(patch["squash"])
		var normalized := local.length() / float(patch["radius"])
		if normalized < 1.25:
			strongest = maxf(strongest, smoothstep(1.2, 0.36, normalized))
	return clampf(strongest, 0.0, 1.0)

func _ford_strength(position: Vector2) -> float:
	var strongest := 0.0
	for ford in fords:
		var radius: float = ford["radius"]
		var distance := position.distance_to(ford["position"])
		if distance < radius:
			strongest = maxf(strongest, 1.0 - smoothstep(radius * 0.42, radius, distance))
	return strongest

func _visible_ford_count(world_radius: float) -> int:
	var count := 0
	for ford in fords:
		if is_inside_world(ford["position"], world_radius, 4.0):
			count += 1
	return count
