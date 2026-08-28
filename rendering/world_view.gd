class_name WorldView
extends Node2D

var systems: GameSystems
var simulation: EcosystemSimulation
var display_radius := 360.0
var placement_position := Vector2.ZERO
var placement_item := ""
var placement_valid := false
var placement_visible := false
var debug_enabled := false
var debug_selected_kind := ""
var debug_selected_id := -1
var spawn_effects: Dictionary = {}
var ambient_effects: Array = []
var details: Array = []
var visual_clock := 0.0
var expansion_flash := 0.0
var critical_visual := 0.0

const COLOR_GRASS := Color("#91bd73")
const COLOR_GRASS_LIGHT := Color("#b4d58f")
const COLOR_FOREST := Color("#4a7d58")
const COLOR_FOREST_DARK := Color("#315d45")
const COLOR_THICKET := Color("#54764b")
const COLOR_THICKET_DARK := Color("#36553c")
const COLOR_STREAM := Color("#6faeb1")
const COLOR_STREAM_DEEP := Color("#467f89")
const COLOR_BANK := Color("#9e9468")
const COLOR_RABBIT := Color("#f5eee0")
const COLOR_FOX := Color("#dc7749")
const COLOR_OUTSIDE := Color("#17372e")
const COLOR_SOIL := Color("#806f48")

func setup(p_systems: GameSystems) -> void:
	systems = p_systems
	simulation = systems.simulation
	display_radius = simulation.world_radius
	simulation.entity_added.connect(_on_entity_added)
	simulation.entity_removed.connect(_on_entity_removed)
	simulation.plant_eaten.connect(_on_plant_eaten)
	systems.world_expanded.connect(_on_world_expanded)
	_generate_details()
	queue_redraw()

func _generate_details() -> void:
	details.clear()
	var detail_rng := RandomNumberGenerator.new()
	detail_rng.seed = int(simulation.config["simulation"]["seed"]) + 4421
	var maximum: float = simulation.config["world"]["maximum_radius"]
	for index in range(440):
		var position := Vector2.from_angle(detail_rng.randf_range(0.0, TAU)) * sqrt(detail_rng.randf()) * maximum * 0.96
		if simulation.terrain.is_water(position):
			continue
		var forest := simulation.terrain_forestness(position)
		var thicket := simulation.terrain.thicket_cover(position)
		var roll := detail_rng.randf()
		var kind := "shrub" if thicket > 0.48 else ("tree" if forest > 0.58 else ("tuft" if roll < 0.42 else ("flower" if roll < 0.82 else "stone")))
		details.append({
			"position": position,
			"kind": kind,
			"size": detail_rng.randf_range(0.9, 1.5) if kind == "tree" else detail_rng.randf_range(0.75, 1.25),
			"tone": detail_rng.randf(),
		})

func process_visual(delta: float) -> void:
	visual_clock += delta
	display_radius = lerpf(display_radius, simulation.world_radius, 1.0 - exp(-delta * 1.45))
	expansion_flash = maxf(0.0, expansion_flash - delta)
	var critical_target := 1.0 if systems.is_critical() else 0.0
	critical_visual = lerpf(critical_visual, critical_target, 1.0 - exp(-delta * 2.2))
	for entity_id in spawn_effects.keys():
		spawn_effects[entity_id]["age"] += delta
		if spawn_effects[entity_id]["age"] > 0.65:
			spawn_effects.erase(entity_id)
	for effect in ambient_effects:
		effect["age"] += delta
	for index in range(ambient_effects.size() - 1, -1, -1):
		if ambient_effects[index]["age"] > ambient_effects[index]["duration"]:
			ambient_effects.remove_at(index)
	queue_redraw()

func set_placement_preview(item: String, world_position: Vector2, valid: bool, visible: bool = true) -> void:
	placement_item = item
	placement_position = world_position
	placement_valid = valid
	placement_visible = visible and not item.is_empty()
	queue_redraw()

func set_debug_selection(kind: String, entity_id: int) -> void:
	debug_selected_kind = kind
	debug_selected_id = entity_id
	queue_redraw()

func _on_entity_added(kind: String, entity_id: int, reason: String) -> void:
	spawn_effects[entity_id] = {"age": 0.0, "kind": kind, "reason": reason}

func _on_entity_removed(kind: String, _entity_id: int, position: Vector2, cause: String) -> void:
	var duration := 1.65 if kind == "rabbit" and cause == "starvation" else 0.85
	ambient_effects.append({"type": "death", "kind": kind, "position": position, "cause": cause, "age": 0.0, "duration": duration})

func _on_plant_eaten(_plant_id: int, position: Vector2) -> void:
	if ambient_effects.size() < 28:
		ambient_effects.append({"type": "nibble", "position": position, "age": 0.0, "duration": 0.42})

func _on_world_expanded(_new_radius: float) -> void:
	expansion_flash = 2.2

func _draw() -> void:
	_draw_terrain()
	_draw_pollen()
	_draw_details()
	_draw_plants()
	_draw_animals()
	_draw_thicket_foreground()
	_draw_effects()
	_draw_debug()
	_draw_placement_preview()

func _draw_terrain() -> void:
	var boundary := _boundary_polygon(display_radius, 128)
	# A low offset shadow makes the biome feel like a raised miniature rather than a flat disk.
	draw_set_transform(Vector2(0.0, 12.0), 0.0, Vector2.ONE)
	draw_colored_polygon(_boundary_polygon(display_radius + 7.0, 128), Color(0.02, 0.10, 0.075, 0.38))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(boundary, COLOR_GRASS.darkened(critical_visual * 0.16))
	# Broad tonal washes break up the meadow without competing with placeable plants.
	for layer in range(4):
		var radius := maxf(0.0, display_radius - 24.0 - float(layer) * 52.0)
		var wash := _boundary_polygon(radius, 112)
		draw_colored_polygon(wash, Color(COLOR_GRASS_LIGHT.r, COLOR_GRASS_LIGHT.g, COLOR_GRASS_LIGHT.b, 0.024 + float(layer % 2) * 0.012))
	# Wide nested contours remove any board-like feel while retaining habitat readability.
	for patch_index in range(simulation.terrain.woodland_patches.size()):
		var patch: Dictionary = simulation.terrain.woodland_patches[patch_index]
		var center: Vector2 = patch["center"]
		var radius: float = patch["radius"]
		if center.length() - radius > display_radius * 1.01:
			continue
		var outer := _organic_ellipse(patch, 1.0, patch_index)
		var shadow_patch: Dictionary = patch.duplicate()
		shadow_patch["center"] = center + Vector2(0.0, 7.0)
		draw_colored_polygon(_organic_ellipse(shadow_patch, 1.035, patch_index), Color(0.08, 0.20, 0.13, 0.22))
		var tone := COLOR_FOREST.lerp(Color("#5d8b68"), float(patch["tone"]) * 0.36).darkened(critical_visual * 0.18)
		draw_colored_polygon(outer, tone)
		var inner := _organic_ellipse(patch, 0.68, patch_index + 71)
		var inner_tone := COLOR_FOREST_DARK.lerp(tone, 0.58)
		inner_tone.a = 0.22
		draw_colored_polygon(inner, inner_tone)
		_draw_forest_edge_tufts(patch, patch_index)
	# Thicket is lower and more broken than Woodland. Its foreground leaves are
	# drawn after animals so entering cover remains visible without hiding them.
	for patch_index in range(simulation.terrain.thicket_patches.size()):
		var patch: Dictionary = simulation.terrain.thicket_patches[patch_index]
		var center: Vector2 = patch["center"]
		var radius: float = patch["radius"]
		if center.length() - radius > display_radius * 1.02:
			continue
		var outer := _organic_ellipse(patch, 1.0, patch_index + 311)
		var tone := COLOR_THICKET.lerp(Color("#6f8b54"), float(patch["tone"]) * 0.38).darkened(critical_visual * 0.15)
		draw_colored_polygon(outer, Color(tone.r, tone.g, tone.b, 0.82))
		var inner := _organic_ellipse(patch, 0.67, patch_index + 419)
		draw_colored_polygon(inner, Color(COLOR_THICKET_DARK.r, COLOR_THICKET_DARK.g, COLOR_THICKET_DARK.b, 0.28))
	_draw_stream()
	_draw_exterior_mask(boundary)
	_draw_exterior_ambience()
	# A warm grassy lip communicates the growing playable boundary.
	var rim_color := Color(0.83, 0.94, 0.66, 0.30 + expansion_flash * 0.05)
	draw_polyline(boundary, rim_color, 6.0, true)
	var inner_boundary := _boundary_polygon(maxf(0.0, display_radius - 8.0), 128)
	draw_polyline(inner_boundary, Color(COLOR_SOIL.r, COLOR_SOIL.g, COLOR_SOIL.b, 0.22), 2.0, true)

func _draw_stream() -> void:
	var points: PackedVector2Array = simulation.terrain.stream_points
	var widths: PackedFloat32Array = simulation.terrain.stream_half_widths
	if points.size() < 2:
		return
	_draw_stream_band(points, widths, 7.0, Color(COLOR_BANK.r, COLOR_BANK.g, COLOR_BANK.b, 0.94))
	_draw_stream_band(points, widths, 0.0, COLOR_STREAM_DEEP.darkened(critical_visual * 0.12))
	for ford in simulation.terrain.fords:
		var center: Vector2 = ford["position"]
		if not _inside_display(center, -float(ford["radius"])):
			continue
		var tangent: Vector2 = ford["tangent"]
		var normal: Vector2 = ford["normal"]
		var length: float = float(ford["radius"]) * 0.72
		var width: float = float(ford["half_width"]) + 4.0
		var ford_shape := PackedVector2Array([
			center - tangent * length - normal * width,
			center + tangent * length - normal * width,
			center + tangent * length + normal * width,
			center - tangent * length + normal * width,
		])
		draw_colored_polygon(ford_shape, Color("#91aaa0"))
		draw_polyline(ford_shape, Color(0.78, 0.73, 0.52, 0.50), 2.0, true)
		for stone_index in range(5):
			var amount := (float(stone_index) - 2.0) / 4.0
			var stone_position := center + normal * amount * width * 1.45 + tangent * sin(float(stone_index) * 2.3) * 3.2
			draw_circle(stone_position + Vector2(1.0, 1.8), 4.2, Color(0.12, 0.22, 0.20, 0.18))
			draw_circle(stone_position, 3.7, Color("#b7aa7c"))
	# Sparse moving highlights make the channel read as water without adding noise.
	for index in range(2, points.size() - 2, 3):
		var point := points[index]
		if not _inside_display(point, -30.0):
			continue
		var tangent := (points[index + 1] - points[index - 1]).normalized()
		var phase := 0.35 + sin(visual_clock * 0.85 + float(index) * 1.7) * 0.18
		draw_line(point - tangent * 8.0, point + tangent * 8.0, Color(0.80, 0.94, 0.91, phase), 1.4, true)

func _draw_stream_band(points: PackedVector2Array, widths: PackedFloat32Array, extra_width: float, color: Color) -> void:
	for index in range(points.size() - 1):
		var first := points[index]
		var second := points[index + 1]
		var tangent := (second - first).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var first_width := float(widths[index]) + extra_width
		var second_width := float(widths[index + 1]) + extra_width
		draw_colored_polygon(PackedVector2Array([
			first - normal * first_width,
			second - normal * second_width,
			second + normal * second_width,
			first + normal * first_width,
		]), color)
		if index > 0:
			draw_circle(first, first_width, color)

func _draw_exterior_mask(boundary: PackedVector2Array) -> void:
	var far_radius: float = float(simulation.config["world"]["maximum_radius"]) * 2.4
	for index in range(boundary.size()):
		var next_index := (index + 1) % boundary.size()
		var inner_a: Vector2 = boundary[index]
		var inner_b: Vector2 = boundary[next_index]
		var outer_a := inner_a.normalized() * far_radius
		var outer_b := inner_b.normalized() * far_radius
		draw_colored_polygon(PackedVector2Array([inner_a, outer_a, outer_b, inner_b]), COLOR_OUTSIDE)

func _draw_exterior_ambience() -> void:
	# Dim seed heads and leaves keep the negative space from reading as an empty debug canvas.
	for index in range(58):
		var angle := float(index) * 2.399 + 0.31
		var distance := display_radius + 34.0 + fmod(float(index * 71), 260.0)
		var position := Vector2.from_angle(angle) * distance
		var leaf_color := Color(0.50, 0.69, 0.51, 0.055 + float(index % 3) * 0.012)
		draw_set_transform(position, angle + sin(float(index)) * 0.8, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([Vector2(-5.0, 0.0), Vector2(0.0, -2.6), Vector2(7.0, 0.0), Vector2(0.0, 2.6)]), leaf_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _boundary_polygon(radius: float, point_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(point_count):
		var angle := float(index) / float(point_count) * TAU
		points.append(Vector2.from_angle(angle) * simulation.boundary_radius_at(angle, radius))
	return points

func _organic_ellipse(patch: Dictionary, scale_factor: float, phase: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := 48
	for index in range(count):
		var angle := float(index) / float(count) * TAU
		var wobble := 1.0 + sin(angle * 3.0 + phase * 0.71) * 0.08 + sin(angle * 7.0 - phase * 0.29) * 0.035
		var local := Vector2(cos(angle), sin(angle) * float(patch["squash"])) * float(patch["radius"]) * scale_factor * wobble
		points.append(patch["center"] + local.rotated(float(patch["rotation"])))
	return points

func _draw_forest_edge_tufts(patch: Dictionary, phase: int) -> void:
	for index in range(7):
		var angle := float(index) / 7.0 * TAU + float(phase) * 0.47
		var local := Vector2(cos(angle), sin(angle) * float(patch["squash"])) * float(patch["radius"]) * 0.88
		var position: Vector2 = patch["center"] + local.rotated(float(patch["rotation"]))
		if not _inside_display(position, 8.0):
			continue
		var lean := Vector2(sin(angle) * 1.8, -5.0)
		draw_line(position, position + lean, Color(0.19, 0.38, 0.23, 0.40), 1.3, true)
		draw_line(position + Vector2(2.2, 0.6), position + Vector2(3.6, -3.8), Color(0.32, 0.53, 0.29, 0.35), 1.0, true)

func _inside_display(position: Vector2, margin: float = 0.0) -> bool:
	return position.length() <= simulation.boundary_radius_at(position.angle(), display_radius) - margin

func _draw_pollen() -> void:
	for index in range(28):
		var angle := float(index) * 2.173
		var radius := 38.0 + fmod(float(index * 83), maxf(70.0, display_radius - 45.0))
		var drift := Vector2(sin(visual_clock * 0.22 + index) * 5.0, cos(visual_clock * 0.17 + index * 0.7) * 4.0)
		var position := Vector2.from_angle(angle) * radius + drift
		if _inside_display(position, 15.0) and not simulation.terrain.is_water(position):
			var glow := 0.12 + sin(visual_clock * 0.55 + index) * 0.035
			draw_circle(position, 1.25 + float(index % 3) * 0.25, Color(1.0, 0.91, 0.59, glow))

func _draw_details() -> void:
	for detail in details:
		var position: Vector2 = detail["position"]
		if not _inside_display(position, 5.0):
			continue
		var size: float = detail["size"]
		match detail["kind"]:
			"tree":
				draw_circle(position + Vector2(2.0, 4.0), 8.0 * size, Color(0.07, 0.18, 0.12, 0.24))
				draw_line(position + Vector2(0.0, 4.0), position + Vector2(0.0, 9.0) * size, Color(0.32, 0.25, 0.15, 0.46), 2.1 * size, true)
				var canopy := Color("#315f46").lerp(Color("#4b7d55"), detail["tone"])
				draw_circle(position + Vector2(-3.5, 1.0) * size, 6.0 * size, canopy.darkened(0.06))
				draw_circle(position + Vector2(3.5, 1.0) * size, 6.4 * size, canopy)
				draw_circle(position + Vector2(0.0, -4.0) * size, 6.2 * size, canopy.lightened(0.08))
				draw_circle(position + Vector2(-2.5, -5.0) * size, 2.3 * size, Color(0.54, 0.70, 0.44, 0.46))
			"shrub":
				draw_circle(position + Vector2(1.0, 3.0), 7.5 * size, Color(0.08, 0.16, 0.10, 0.18))
				for leaf_index in range(5):
					var leaf_angle := float(leaf_index) / 5.0 * TAU + float(detail["tone"]) * 2.0
					var leaf_position := position + Vector2.from_angle(leaf_angle) * 4.2 * size
					var leaf_color := Color("#4f7648").lerp(Color("#6f8d51"), float((leaf_index + int(detail["tone"] * 5.0)) % 3) * 0.22)
					draw_circle(leaf_position, 4.3 * size, leaf_color)
			"flower":
				var flower_color := Color("#f3d99b") if detail["tone"] > 0.5 else Color("#e9b8bd")
				draw_line(position + Vector2(0.0, 3.0), position + Vector2(0.0, -2.0) * size, Color(0.28, 0.50, 0.27, 0.55), 1.0, true)
				for petal in range(4):
					draw_circle(position + Vector2.from_angle(float(petal) / 4.0 * TAU) * 1.8 * size, 1.45 * size, flower_color)
				draw_circle(position, 0.75 * size, Color("#fff1bb"))
			"tuft":
				for blade in range(4):
					var x := (float(blade) - 1.5) * 1.8 * size
					var height := (4.0 + float((blade + int(detail["tone"] * 7.0)) % 3)) * size
					draw_line(position + Vector2(x, 2.0), position + Vector2(x + sin(float(blade)) * 1.4, 2.0 - height), Color(0.34, 0.57, 0.29, 0.44), 1.1, true)
			"stone":
				draw_colored_polygon(PackedVector2Array([position + Vector2(-3.4, 2.0) * size, position + Vector2(-1.8, -2.6) * size, position + Vector2(2.6, -2.0) * size, position + Vector2(3.8, 2.4) * size]), Color(0.43, 0.49, 0.40, 0.48))
				draw_line(position + Vector2(-1.5, -1.8) * size, position + Vector2(2.2, -1.2) * size, Color(0.72, 0.75, 0.63, 0.38), 1.0, true)

func _draw_thicket_foreground() -> void:
	for patch_index in range(simulation.terrain.thicket_patches.size()):
		var patch: Dictionary = simulation.terrain.thicket_patches[patch_index]
		var center: Vector2 = patch["center"]
		var radius: float = patch["radius"]
		if center.length() - radius > display_radius * 1.02:
			continue
		for index in range(6):
			var angle := lerpf(0.18, PI - 0.18, float(index) / 5.0)
			var local := Vector2(cos(angle), sin(angle) * float(patch["squash"])) * radius * (0.42 + float(index % 2) * 0.22)
			var position: Vector2 = center + local.rotated(float(patch["rotation"]))
			if not _inside_display(position, 2.0) or simulation.terrain.is_water(position):
				continue
			var leaf_color := COLOR_THICKET_DARK.lerp(COLOR_THICKET, float(index % 3) * 0.24)
			leaf_color.a = 0.34
			draw_circle(position, 6.0 + float(index % 2) * 2.0, leaf_color)

func _draw_plants() -> void:
	for plant in simulation.plants.values():
		var position: Vector2 = plant["position"]
		if simulation.terrain.is_deep_water(position):
			continue
		var fullness: float = clampf(plant["food"] / plant["max_food"], 0.08, 1.0)
		var scale_factor := _spawn_scale(plant["id"])
		draw_set_transform(position, 0.0, Vector2.ONE * scale_factor)
		if plant["type"] == "carrot_patch":
			_draw_carrot_patch(fullness, plant["id"])
		else:
			_draw_berry_bush(fullness, plant["id"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_carrot_patch(fullness: float, entity_id: int) -> void:
	var sway := sin(visual_clock * 1.3 + entity_id) * 0.55
	draw_circle(Vector2(1.0, 5.0), 10.0, Color(0.08, 0.16, 0.10, 0.15))
	draw_colored_polygon(PackedVector2Array([Vector2(-10.0, 2.0), Vector2(-6.0, -1.0), Vector2(6.5, -1.0), Vector2(10.0, 2.5), Vector2(7.0, 7.0), Vector2(-7.5, 7.0)]), Color("#755637"))
	var carrot_count := 1 + int(round(fullness * 3.0))
	var offsets_by_count := {
		1: [0.0],
		2: [-4.0, 4.0],
		3: [-6.0, 0.0, 6.0],
		4: [-7.0, -2.5, 2.5, 7.0],
	}
	var offsets: Array = offsets_by_count[carrot_count]
	for index in range(carrot_count):
		var x: float = offsets[index]
		var top_y := -1.5 + float(index % 2) * 1.4
		var top := Vector2(x, top_y)
		var leaf_tone := Color("#3f793c").lerp(Color("#6da94d"), float(index % 2) * 0.45)
		draw_line(top, top + Vector2(-3.0 + sway, -6.5), leaf_tone, 1.6, true)
		draw_line(top, top + Vector2(sway, -8.0), leaf_tone.lightened(0.08), 1.8, true)
		draw_line(top, top + Vector2(3.0 + sway, -5.8), leaf_tone.darkened(0.05), 1.5, true)
		var root_color := Color("#ee6f22").lerp(Color("#f58a2f"), float((entity_id + index) % 2) * 0.55)
		draw_colored_polygon(PackedVector2Array([top + Vector2(-2.4, 0.0), top + Vector2(2.4, 0.0), top + Vector2(1.4, 4.2), top + Vector2(0.0, 8.3), top + Vector2(-1.5, 4.0)]), root_color)
		draw_line(top + Vector2(-1.1, 2.0), top + Vector2(1.1, 1.7), Color(1.0, 0.72, 0.35, 0.72), 0.9, true)

func _draw_berry_bush(fullness: float, entity_id: int) -> void:
	draw_circle(Vector2(1.5, 3.0), 11.0, Color(0.1, 0.2, 0.12, 0.16))
	for index in range(6):
		var angle := float(index) / 6.0 * TAU + entity_id * 0.1
		var center := Vector2.from_angle(angle) * 5.0
		draw_circle(center, 6.5, Color("#326444").lerp(Color("#477b50"), float(index % 2) * 0.35))
	var berry_count := int(round(fullness * 7.0))
	for index in range(berry_count):
		var angle := float(index) * 2.399 + entity_id * 0.7
		var position := Vector2.from_angle(angle) * (2.5 + float(index % 3) * 2.2)
		draw_circle(position, 1.65, Color("#9f3f5e"))
		draw_circle(position + Vector2(-0.45, -0.55), 0.48, Color(1.0, 0.72, 0.75, 0.7))

func _draw_animals() -> void:
	var animals: Array = []
	for rabbit in simulation.rabbits.values():
		animals.append(rabbit)
	for fox in simulation.foxes.values():
		animals.append(fox)
	animals.sort_custom(_sort_by_y)
	var alpha := systems.interpolation_alpha()
	for animal in animals:
		var position: Vector2 = animal["previous_position"].lerp(animal["position"], alpha)
		var velocity: Vector2 = animal["velocity"]
		var previous_velocity: Vector2 = animal.get("previous_velocity", velocity)
		var rotation := velocity.angle() if velocity.length_squared() > 0.1 else previous_velocity.angle()
		if velocity.length_squared() > 0.1 and previous_velocity.length_squared() > 0.1:
			rotation = lerp_angle(previous_velocity.angle(), velocity.angle(), alpha)
		var scale_factor := _spawn_scale(animal["id"]) * 1.16
		draw_set_transform(position, rotation, Vector2.ONE * scale_factor)
		if animal["type"] == "rabbit":
			_draw_rabbit(animal)
		else:
			_draw_fox(animal)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _sort_by_y(a: Dictionary, b: Dictionary) -> bool:
	return float(a["position"].y) < float(b["position"].y)

func _spawn_scale(entity_id: int) -> float:
	if not spawn_effects.has(entity_id):
		return 1.0
	var age: float = spawn_effects[entity_id]["age"]
	var normalized := clampf(age / 0.48, 0.0, 1.0)
	return 0.22 + _ease_out_back(normalized) * 0.78

func _ease_out_back(value: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(value - 1.0, 3.0) + c1 * pow(value - 1.0, 2.0)

func _draw_rabbit(rabbit: Dictionary) -> void:
	var moving := clampf(rabbit["velocity"].length() / 72.0, 0.0, 1.0)
	var rabbit_cfg: Dictionary = simulation.config["rabbit"]
	var hunger: float = float(rabbit["hunger"])
	var starvation_at: float = float(rabbit_cfg["starvation_threshold"])
	var warning_at: float = float(rabbit_cfg["hunger_warning_at"])
	var hunger_ratio := hunger / starvation_at
	var distress := smoothstep(0.62, 1.0, hunger_ratio)
	var body_color := COLOR_RABBIT.lerp(Color("#b9b2a5"), distress * 0.52)
	var hop := sin(visual_clock * (5.5 + moving * 4.0) + rabbit["id"]) * moving
	draw_circle(Vector2(-1.0, 4.2), 8.2, Color(0.07, 0.13, 0.10, 0.25))
	# Ears point in the travel direction, making fleeing and foraging readable.
	draw_colored_polygon(PackedVector2Array([Vector2(4.0, -3.0), Vector2(13.0, -6.5), Vector2(11.0, -1.0)]), Color("#e7ded0"))
	draw_colored_polygon(PackedVector2Array([Vector2(4.0, 2.5), Vector2(13.0, 5.8), Vector2(10.7, 0.9)]), Color("#eee5d7"))
	draw_line(Vector2(6.0, -2.5), Vector2(10.6, -4.8), Color("#d7aeb0"), 1.1, true)
	draw_circle(Vector2(-1.0, hop * 0.5), 7.8, Color(0.19, 0.27, 0.22, 0.62))
	draw_circle(Vector2(-1.0, hop * 0.5), 7.2, body_color)
	draw_circle(Vector2(5.5, 0.0), 5.4, Color("#fbf5e9").lerp(Color("#c8c0b2"), distress * 0.46))
	draw_circle(Vector2(7.4, -2.2), 1.0, Color("#343333"))
	draw_circle(Vector2(-7.0, 0.0), 2.5, Color("#ffffff"))
	if rabbit["behavior"] == "flee":
		draw_arc(Vector2.ZERO, 10.5, -0.8, 0.8, 12, Color(1.0, 0.86, 0.57, 0.65), 1.1, true)
	elif distress > 0.42:
		var pulse := 0.35 + sin(visual_clock * 4.0 + rabbit["id"]) * 0.12
		draw_arc(Vector2(0.0, -1.0), 10.0, -2.4, -0.75, 9, Color(0.78, 0.72, 0.62, pulse * distress), 1.0, true)
	var has_food_route: bool = rabbit["behavior"] in ["seek_food", "eat"]
	var needs_help := hunger >= warning_at and not has_food_route
	var starving := hunger >= starvation_at
	if needs_help or starving:
		var marker_color := Color("#d96d52") if starving else Color("#e5ad45")
		var urgency := clampf((hunger - warning_at) / maxf(1.0, starvation_at - warning_at), 0.0, 1.0)
		var marker_pulse := 0.58 + sin(visual_clock * (4.2 if starving else 2.8) + rabbit["id"]) * 0.16
		var marker_radius := 11.6 + urgency * 1.4 + marker_pulse * 0.65
		draw_arc(Vector2.ZERO, marker_radius, 0.0, TAU, 28, Color(marker_color.r, marker_color.g, marker_color.b, marker_pulse), 2.0 if starving else 1.45, true)

func _draw_fox(fox: Dictionary) -> void:
	var pace := clampf(fox["velocity"].length() / 64.0, 0.0, 1.0)
	var hunger_ratio: float = float(fox["hunger"]) / float(simulation.config["fox"]["starvation_threshold"])
	var distress := smoothstep(0.65, 1.0, hunger_ratio)
	var body_color := COLOR_FOX.lerp(Color("#9e705d"), distress * 0.48)
	var tail_sway := sin(visual_clock * (3.0 + pace * 3.5) + fox["id"]) * 2.2
	draw_circle(Vector2(-1.0, 4.8), 9.6, Color(0.07, 0.12, 0.09, 0.28))
	draw_circle(Vector2(-4.0, tail_sway), 7.2, Color("#c95f39"))
	draw_circle(Vector2(-10.0, tail_sway * 1.25), 4.2, Color("#f0d6b5"))
	draw_circle(Vector2(0.0, 0.0), 8.9, Color(0.24, 0.24, 0.19, 0.66))
	draw_circle(Vector2(0.0, 0.0), 8.2, body_color)
	draw_colored_polygon(PackedVector2Array([Vector2(3.0, -5.5), Vector2(7.0, -11.0), Vector2(9.0, -3.5)]), Color("#bd5236"))
	draw_colored_polygon(PackedVector2Array([Vector2(3.0, 5.5), Vector2(7.0, 11.0), Vector2(9.0, 3.5)]), Color("#bd5236"))
	draw_colored_polygon(PackedVector2Array([Vector2(3.5, -5.8), Vector2(14.0, 0.0), Vector2(3.5, 5.8)]), Color("#e98955"))
	draw_colored_polygon(PackedVector2Array([Vector2(8.5, -3.0), Vector2(14.0, 0.0), Vector2(8.5, 3.0)]), Color("#f3dfc8"))
	draw_circle(Vector2(8.0, -2.6), 0.95, Color("#252c26"))
	draw_circle(Vector2(14.0, 0.0), 1.15, Color("#282b28"))
	if fox["behavior"] == "hunt":
		draw_arc(Vector2.ZERO, 12.0, -0.5, 0.5, 10, Color(1.0, 0.74, 0.42, 0.72), 1.3, true)
	elif distress > 0.42:
		var pulse := 0.35 + sin(visual_clock * 3.5 + fox["id"]) * 0.12
		draw_arc(Vector2.ZERO, 12.0, -2.35, -0.8, 9, Color(0.72, 0.62, 0.52, pulse * distress), 1.0, true)

func _draw_effects() -> void:
	for entity_id in spawn_effects:
		var spawn: Dictionary = spawn_effects[entity_id]
		var position := _spawn_position(int(entity_id), str(spawn["kind"]))
		if position == Vector2.INF:
			continue
		var progress: float = clampf(float(spawn["age"]) / 0.65, 0.0, 1.0)
		var birth: bool = spawn["reason"] == "birth"
		var base := Color("#fff0a8") if birth else Color("#f1c760")
		var color := Color(base.r, base.g, base.b, (1.0 - progress) * 0.62)
		if not birth:
			for puff in range(4):
				var puff_angle := float(puff) / 4.0 * TAU + float(entity_id)
				var puff_position := position + Vector2.from_angle(puff_angle) * (5.0 + progress * 8.0) + Vector2(0.0, 7.0)
				draw_circle(puff_position, (3.2 + float(puff % 2)) * (1.0 - progress), Color(COLOR_SOIL.r, COLOR_SOIL.g, COLOR_SOIL.b, (1.0 - progress) * 0.28))
		draw_circle(position, 7.0 + progress * 20.0, color, false, 2.2, true)
		for spark in range(5 if birth else 3):
			var angle := float(spark) / float(5 if birth else 3) * TAU + float(entity_id) * 0.31
			var spark_position := position + Vector2.from_angle(angle) * (8.0 + progress * 17.0)
			draw_circle(spark_position, (2.2 if birth else 1.6) * (1.0 - progress), color)
	for effect in ambient_effects:
		var progress: float = clampf(effect["age"] / effect["duration"], 0.0, 1.0)
		if effect["type"] == "death":
			var cause: String = effect.get("cause", "")
			var base_color := Color("#ef9a63") if cause == "predation" else (Color("#d6a84e") if cause == "starvation" else Color("#e8dfc7"))
			var color := Color(base_color.r, base_color.g, base_color.b, (1.0 - progress) * 0.52)
			var radius := 5.0 + progress * (15.0 if cause == "predation" else 10.0)
			draw_circle(effect["position"], radius, color, false, 2.0 if cause in ["predation", "starvation"] else 1.4, true)
			if cause == "predation":
				draw_line(effect["position"] + Vector2(-7.0, -5.0) * (1.0 + progress), effect["position"] + Vector2(7.0, 5.0) * (1.0 + progress), color, 1.5, true)
		elif effect["type"] == "nibble":
			var color := Color(1.0, 0.94, 0.67, (1.0 - progress) * 0.55)
			draw_circle(effect["position"] + Vector2(0.0, -9.0 - progress * 7.0), 2.1 * (1.0 - progress), color)
	if expansion_flash > 0.0:
		var progress := 1.0 - expansion_flash / 2.2
		var radius := lerpf(display_radius - 35.0, display_radius + 8.0, progress)
		var boundary := _boundary_polygon(radius, 128)
		draw_polyline(boundary, Color(0.9, 1.0, 0.76, sin(progress * PI) * 0.48), 4.0, true)

func _spawn_position(entity_id: int, kind: String) -> Vector2:
	if kind == "rabbit" and simulation.rabbits.has(entity_id):
		return simulation.rabbits[entity_id]["position"]
	if kind == "fox" and simulation.foxes.has(entity_id):
		return simulation.foxes[entity_id]["position"]
	if kind in ["carrot_patch", "berry_bush"] and simulation.plants.has(entity_id):
		return simulation.plants[entity_id]["position"]
	return Vector2.INF

func _draw_debug() -> void:
	if not debug_enabled or debug_selected_id == -1:
		return
	var source: Dictionary = simulation.rabbits if debug_selected_kind == "rabbit" else simulation.foxes
	if not source.has(debug_selected_id):
		return
	var entity: Dictionary = source[debug_selected_id]
	var position: Vector2 = entity["position"]
	var color := Color(0.96, 0.88, 0.36, 0.72)
	draw_circle(position, 15.0, color, false, 2.0, true)
	if debug_selected_kind == "rabbit":
		draw_circle(position, simulation.config["rabbit"]["food_detection_radius"], Color(0.55, 0.9, 0.55, 0.22), false, 1.0, true)
		draw_circle(position, simulation.config["rabbit"]["fox_detection_radius"], Color(1.0, 0.55, 0.4, 0.28), false, 1.0, true)
	else:
		draw_circle(position, simulation.config["fox"]["prey_detection_radius"], Color(1.0, 0.62, 0.35, 0.24), false, 1.0, true)
	if entity["target_id"] != -1:
		var target_source: Dictionary = simulation.plants if debug_selected_kind == "rabbit" and simulation.plants.has(entity["target_id"]) else (simulation.foxes if debug_selected_kind == "rabbit" else simulation.rabbits)
		if target_source.has(entity["target_id"]):
			draw_dashed_line(position, target_source[entity["target_id"]]["position"], color, 1.3, 5.0, true)
	var route_points: Array = [position]
	for waypoint in entity.get("route_waypoints", []):
		route_points.append(waypoint)
	var route_target: Vector2 = entity.get("route_target_position", Vector2.INF)
	if route_target != Vector2.INF:
		route_points.append(route_target)
	for index in range(route_points.size() - 1):
		draw_dashed_line(route_points[index], route_points[index + 1], Color(0.97, 0.83, 0.34, 0.78), 1.7, 7.0, true)
	for waypoint in entity.get("route_waypoints", []):
		draw_circle(waypoint, 5.0, Color(0.97, 0.83, 0.34, 0.70), false, 1.6, true)
	var ford: Vector2 = entity.get("route_ford", Vector2.INF)
	if ford != Vector2.INF:
		draw_circle(ford, 8.0, Color(0.55, 0.90, 0.96, 0.72), false, 2.0, true)
	var refuge: Vector2 = entity.get("refuge_position", Vector2.INF)
	if refuge != Vector2.INF:
		draw_circle(refuge, 11.0, Color(0.58, 0.91, 0.49, 0.74), false, 2.0, true)

func _draw_placement_preview() -> void:
	if not placement_visible:
		return
	var color := Color("#ffe27a") if placement_valid else Color("#ff7664")
	var radius := 21.0 + sin(visual_clock * 4.5) * 1.5
	draw_circle(placement_position, radius, Color(color.r, color.g, color.b, 0.13))
	draw_circle(placement_position, radius + 1.5, Color(0.06, 0.16, 0.11, 0.58), false, 3.8, true)
	for segment in range(8):
		var start := float(segment) / 8.0 * TAU + visual_clock * 0.18
		draw_arc(placement_position, radius, start, start + 0.48, 5, Color(color.r, color.g, color.b, 0.83), 2.0, true)
	if not placement_valid:
		draw_line(placement_position + Vector2(-7.0, -7.0), placement_position + Vector2(7.0, 7.0), Color(color.r, color.g, color.b, 0.85), 2.0, true)
		draw_line(placement_position + Vector2(7.0, -7.0), placement_position + Vector2(-7.0, 7.0), Color(color.r, color.g, color.b, 0.85), 2.0, true)
	draw_set_transform(placement_position, 0.0, Vector2.ONE * 1.02)
	match placement_item:
		"rabbit":
			_draw_rabbit({"id": 0, "velocity": Vector2.RIGHT, "behavior": "preview"})
		"fox":
			_draw_fox({"id": 0, "velocity": Vector2.RIGHT, "behavior": "preview"})
		"carrot_patch":
			_draw_carrot_patch(1.0, 0)
		"berry_bush":
			_draw_berry_bush(1.0, 0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
