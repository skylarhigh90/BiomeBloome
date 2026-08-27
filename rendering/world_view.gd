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

const COLOR_GRASS := Color("#94bc78")
const COLOR_GRASS_LIGHT := Color("#a8cb88")
const COLOR_FOREST := Color("#4f7f61")
const COLOR_FOREST_DARK := Color("#3e6951")
const COLOR_RABBIT := Color("#f5eee0")
const COLOR_FOX := Color("#dc7749")
const COLOR_OUTSIDE := Color("#0e1311")

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
	for index in range(310):
		var position := Vector2.from_angle(detail_rng.randf_range(0.0, TAU)) * sqrt(detail_rng.randf()) * maximum * 0.96
		var forest := simulation.terrain_forestness(position)
		var kind := "tree" if forest > 0.58 else ("flower" if detail_rng.randf() < 0.55 else "stone")
		details.append({
			"position": position,
			"kind": kind,
			"size": detail_rng.randf_range(0.7, 1.3),
			"tone": detail_rng.randf(),
		})

func process_visual(delta: float) -> void:
	visual_clock += delta
	display_radius = lerpf(display_radius, simulation.world_radius, 1.0 - exp(-delta * 1.45))
	expansion_flash = maxf(0.0, expansion_flash - delta)
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
	ambient_effects.append({"type": "death", "kind": kind, "position": position, "cause": cause, "age": 0.0, "duration": 0.85})

func _on_plant_eaten(_plant_id: int, position: Vector2) -> void:
	if ambient_effects.size() < 28:
		ambient_effects.append({"type": "nibble", "position": position, "age": 0.0, "duration": 0.42})

func _on_world_expanded(_new_radius: float) -> void:
	expansion_flash = 2.2

func _draw() -> void:
	_draw_terrain()
	_draw_details()
	_draw_plants()
	_draw_animals()
	_draw_effects()
	_draw_debug()
	_draw_placement_preview()

func _draw_terrain() -> void:
	var boundary := _boundary_polygon(display_radius, 128)
	draw_colored_polygon(boundary, COLOR_GRASS)
	# Wide nested contours remove any board-like feel while retaining habitat readability.
	for patch_index in range(simulation.forest_patches.size()):
		var patch: Dictionary = simulation.forest_patches[patch_index]
		var center: Vector2 = patch["center"]
		var radius: float = patch["radius"]
		if center.length() - radius > display_radius * 1.01:
			continue
		var outer := _organic_ellipse(patch, 1.0, patch_index)
		var tone := COLOR_FOREST.lerp(Color("#5d8b68"), float(patch["tone"]) * 0.36)
		draw_colored_polygon(outer, tone)
		var inner := _organic_ellipse(patch, 0.68, patch_index + 71)
		draw_colored_polygon(inner, COLOR_FOREST_DARK.lerp(tone, 0.38))
	_draw_exterior_mask(boundary)
	# A soft rim communicates the growing playable boundary.
	var rim_color := Color(0.78, 0.91, 0.68, 0.19 + expansion_flash * 0.05)
	draw_polyline(boundary, rim_color, 5.0, true)
	var inner_boundary := _boundary_polygon(maxf(0.0, display_radius - 8.0), 128)
	draw_polyline(inner_boundary, Color(0.2, 0.34, 0.23, 0.18), 2.0, true)

func _draw_exterior_mask(boundary: PackedVector2Array) -> void:
	var far_radius: float = float(simulation.config["world"]["maximum_radius"]) * 2.4
	for index in range(boundary.size()):
		var next_index := (index + 1) % boundary.size()
		var inner_a: Vector2 = boundary[index]
		var inner_b: Vector2 = boundary[next_index]
		var outer_a := inner_a.normalized() * far_radius
		var outer_b := inner_b.normalized() * far_radius
		draw_colored_polygon(PackedVector2Array([inner_a, outer_a, outer_b, inner_b]), COLOR_OUTSIDE)

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

func _inside_display(position: Vector2, margin: float = 0.0) -> bool:
	return position.length() <= simulation.boundary_radius_at(position.angle(), display_radius) - margin

func _draw_details() -> void:
	for detail in details:
		var position: Vector2 = detail["position"]
		if not _inside_display(position, 5.0):
			continue
		var size: float = detail["size"]
		match detail["kind"]:
			"tree":
				draw_circle(position + Vector2(1.5, 2.5), 7.0 * size, Color(0.11, 0.23, 0.16, 0.18))
				draw_circle(position, 6.0 * size, Color("#315f46").lerp(Color("#447455"), detail["tone"]))
				draw_circle(position + Vector2(-2.0, -2.0) * size, 3.5 * size, Color(0.38, 0.58, 0.38, 0.72))
			"flower":
				var flower_color := Color("#f3d99b") if detail["tone"] > 0.5 else Color("#e9b8bd")
				draw_circle(position, 1.8 * size, flower_color)
				draw_circle(position, 0.65 * size, Color("#fff1bb"))
			"stone":
				draw_circle(position, 2.7 * size, Color(0.46, 0.52, 0.44, 0.42))
				draw_circle(position + Vector2(-0.8, -0.8), 1.5 * size, Color(0.69, 0.72, 0.62, 0.35))

func _draw_plants() -> void:
	for plant in simulation.plants.values():
		var position: Vector2 = plant["position"]
		var fullness: float = clampf(plant["food"] / plant["max_food"], 0.08, 1.0)
		var scale_factor := _spawn_scale(plant["id"])
		draw_set_transform(position, 0.0, Vector2.ONE * scale_factor)
		if plant["type"] == "grass":
			_draw_grass(fullness, plant["id"])
		else:
			_draw_berry_bush(fullness, plant["id"])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_grass(fullness: float, entity_id: int) -> void:
	var sway := sin(visual_clock * 1.3 + entity_id) * 0.8
	draw_circle(Vector2(0.0, 4.0), 8.0, Color(0.16, 0.28, 0.12, 0.12))
	var blades := 4 + int(round(fullness * 4.0))
	for index in range(blades):
		var x := (float(index) - float(blades - 1) * 0.5) * 2.0
		var height := 7.0 + fmod(float(entity_id * 7 + index * 11), 5.0) * fullness
		var color := Color("#3e7a43").lerp(Color("#6da94d"), float(index % 3) / 3.0)
		draw_line(Vector2(x, 5.0), Vector2(x + sway + sin(index) * 1.3, 5.0 - height), color, 1.8, true)

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
		var rotation := velocity.angle() if velocity.length_squared() > 0.1 else 0.0
		var scale_factor := _spawn_scale(animal["id"])
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
	var hop := sin(visual_clock * (5.5 + moving * 4.0) + rabbit["id"]) * moving
	draw_circle(Vector2(-1.0, 3.5), 7.8, Color(0.11, 0.15, 0.12, 0.17))
	# Ears point in the travel direction, making fleeing and foraging readable.
	draw_colored_polygon(PackedVector2Array([Vector2(4.0, -3.0), Vector2(13.0, -6.5), Vector2(11.0, -1.0)]), Color("#e7ded0"))
	draw_colored_polygon(PackedVector2Array([Vector2(4.0, 2.5), Vector2(13.0, 5.8), Vector2(10.7, 0.9)]), Color("#eee5d7"))
	draw_line(Vector2(6.0, -2.5), Vector2(10.6, -4.8), Color("#d7aeb0"), 1.1, true)
	draw_circle(Vector2(-1.0, hop * 0.5), 7.2, COLOR_RABBIT)
	draw_circle(Vector2(5.5, 0.0), 5.4, Color("#fbf5e9"))
	draw_circle(Vector2(7.4, -2.2), 1.0, Color("#343333"))
	draw_circle(Vector2(-7.0, 0.0), 2.5, Color("#ffffff"))
	if rabbit["behavior"] == "flee":
		draw_arc(Vector2.ZERO, 10.5, -0.8, 0.8, 12, Color(1.0, 0.86, 0.57, 0.65), 1.1, true)

func _draw_fox(fox: Dictionary) -> void:
	var pace := clampf(fox["velocity"].length() / 64.0, 0.0, 1.0)
	var tail_sway := sin(visual_clock * (3.0 + pace * 3.5) + fox["id"]) * 2.2
	draw_circle(Vector2(-1.0, 4.0), 9.0, Color(0.11, 0.13, 0.1, 0.2))
	draw_circle(Vector2(-4.0, tail_sway), 7.2, Color("#c95f39"))
	draw_circle(Vector2(-10.0, tail_sway * 1.25), 4.2, Color("#f0d6b5"))
	draw_circle(Vector2(0.0, 0.0), 8.2, COLOR_FOX)
	draw_colored_polygon(PackedVector2Array([Vector2(3.0, -5.5), Vector2(7.0, -11.0), Vector2(9.0, -3.5)]), Color("#bd5236"))
	draw_colored_polygon(PackedVector2Array([Vector2(3.0, 5.5), Vector2(7.0, 11.0), Vector2(9.0, 3.5)]), Color("#bd5236"))
	draw_colored_polygon(PackedVector2Array([Vector2(3.5, -5.8), Vector2(14.0, 0.0), Vector2(3.5, 5.8)]), Color("#e98955"))
	draw_colored_polygon(PackedVector2Array([Vector2(8.5, -3.0), Vector2(14.0, 0.0), Vector2(8.5, 3.0)]), Color("#f3dfc8"))
	draw_circle(Vector2(8.0, -2.6), 0.95, Color("#252c26"))
	draw_circle(Vector2(14.0, 0.0), 1.15, Color("#282b28"))
	if fox["behavior"] == "hunt":
		draw_arc(Vector2.ZERO, 12.0, -0.5, 0.5, 10, Color(1.0, 0.74, 0.42, 0.72), 1.3, true)

func _draw_effects() -> void:
	for effect in ambient_effects:
		var progress: float = clampf(effect["age"] / effect["duration"], 0.0, 1.0)
		if effect["type"] == "death":
			var color := Color(0.96, 0.89, 0.74, (1.0 - progress) * 0.42)
			draw_circle(effect["position"], 5.0 + progress * 12.0, color, false, 1.7, true)
		elif effect["type"] == "nibble":
			var color := Color(1.0, 0.94, 0.67, (1.0 - progress) * 0.55)
			draw_circle(effect["position"] + Vector2(0.0, -9.0 - progress * 7.0), 2.1 * (1.0 - progress), color)
	if expansion_flash > 0.0:
		var progress := 1.0 - expansion_flash / 2.2
		var radius := lerpf(display_radius - 35.0, display_radius + 8.0, progress)
		var boundary := _boundary_polygon(radius, 128)
		draw_polyline(boundary, Color(0.9, 1.0, 0.76, sin(progress * PI) * 0.48), 4.0, true)

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

func _draw_placement_preview() -> void:
	if not placement_visible:
		return
	var color := Color(0.95, 1.0, 0.86, 0.68) if placement_valid else Color(1.0, 0.45, 0.4, 0.68)
	draw_circle(placement_position, 18.0, Color(color.r, color.g, color.b, 0.10))
	draw_circle(placement_position, 18.0, color, false, 1.5, true)
	draw_set_transform(placement_position, 0.0, Vector2.ONE * 0.78)
	match placement_item:
		"rabbit":
			_draw_rabbit({"id": 0, "velocity": Vector2.RIGHT, "behavior": "preview"})
		"fox":
			_draw_fox({"id": 0, "velocity": Vector2.RIGHT, "behavior": "preview"})
		"grass":
			_draw_grass(1.0, 0)
		"berry_bush":
			_draw_berry_bush(1.0, 0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
