class_name WorldView
extends Node2D

const ObjectiveLensState = preload("res://rendering/objective_lens.gd")
const BiomeTheme = preload("res://ui/theme/biome_theme.gd")
const AnimalArt = preload("res://rendering/animal_art.gd")
const AnimalMotion = preload("res://rendering/animal_motion.gd")
const HabitatArt = preload("res://rendering/habitat_art.gd")
const ForageArt = preload("res://rendering/forage_art.gd")
const MEADOW_GROUND: Texture2D = preload("res://assets/environment/meadow_ground.png")
const STREAM_WATER: Texture2D = preload("res://assets/environment/stream_water.png")

const WORLD_REVEAL_RESPONSE := 0.30
const ANIMAL_VISUAL_SCALE := 1.42
const PLANT_VISUAL_SCALE := 1.14
const OBJECTIVE_VISUAL_SCALE := 1.20
const MAX_ZOOM_COMPENSATION := 1.58
const LIFE_EVENT_DURATION := 6.0
const MAX_LIFE_EVENT_LABELS := 6

var systems: GameSystems
var simulation: EcosystemSimulation
var display_radius := 360.0
var placement_position := Vector2.ZERO
var placement_item := ""
var placement_valid := false
var placement_quality := "fair"
var placement_visible := false
var debug_enabled := false
var debug_selected_kind := ""
var debug_selected_id := -1
var selected_animal_kind := ""
var selected_animal_id := -1
var spawn_effects: Dictionary = {}
var ambient_effects: Array = []
var details: Array = []
var visual_clock := 0.0
var expansion_flash := 0.0
var critical_visual := 0.0
var camera_zoom := 1.0
var objective_lens = ObjectiveLensState.new()
var foliage_subjects: Dictionary = {}
var habitat_wash_geometry: Dictionary = {}
const FOLIAGE_CELL_SIZE := 80.0

const COLOR_GRASS := Color("#a7bc85")
const COLOR_GRASS_LIGHT := Color("#c4d09c")
const COLOR_FOREST := Color("#668b68")
const COLOR_FOREST_DARK := Color("#416b55")
const COLOR_THICKET := Color("#809452")
const COLOR_THICKET_DARK := Color("#536e4d")
const COLOR_STREAM := Color("#6faeb1")
const COLOR_STREAM_DEEP := Color("#467f89")
const COLOR_BANK := Color("#9e9468")
const COLOR_RABBIT := Color("#f5eee0")
const COLOR_FOX := Color("#dc7749")
const COLOR_OUTSIDE := Color("#314e43")
const COLOR_SOIL := Color("#806f48")

func setup(p_systems: GameSystems) -> void:
	systems = p_systems
	simulation = systems.simulation
	display_radius = simulation.world_radius
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	simulation.entity_added.connect(_on_entity_added)
	simulation.entity_removed.connect(_on_entity_removed)
	simulation.plant_eaten.connect(_on_plant_eaten)
	simulation.plant_state_changed.connect(_on_plant_state_changed)
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
	# Guarantee enough vertical structure inside every generated woodland patch.
	# The broad habitat wash stays readable, while these seeded trees provide the
	# illustrated canopy rhythm that makes it feel like an actual forest margin.
	for patch_index in range(simulation.terrain.woodland_patches.size()):
		var patch: Dictionary = simulation.terrain.woodland_patches[patch_index]
		for ring in range(2):
			var tree_count := 5 + ring * 4
			for tree_index in range(tree_count):
				var angle := float(tree_index) / float(tree_count) * TAU + float(patch_index) * 0.73 + float(ring) * 0.31
				var local_radius := float(patch["radius"]) * (0.24 + float(ring) * 0.34) * detail_rng.randf_range(0.82, 1.08)
				var local := Vector2(cos(angle), sin(angle) * float(patch["squash"])) * local_radius
				var tree_position: Vector2 = patch["center"] + local.rotated(float(patch["rotation"]))
				if simulation.terrain.is_water(tree_position):
					continue
				details.append({
					"position": tree_position,
					"kind": "tree",
					"size": detail_rng.randf_range(0.82, 1.18),
					"tone": detail_rng.randf(),
				})
	# Seed low foliage from the actual refuge fields. These anchors, like trees,
	# remain fixed when the world expands.
	for patch_index in range(simulation.terrain.thicket_patches.size()):
		var patch: Dictionary = simulation.terrain.thicket_patches[patch_index]
		for index in range(11):
			var angle := float(index) * 2.39996 + float(patch_index) * 0.61
			var radius := sqrt((float(index) + 0.5) / 11.0) * float(patch["radius"]) * 0.72
			var local := Vector2(cos(angle), sin(angle) * float(patch["squash"])) * radius
			var position: Vector2 = patch["center"] + local.rotated(float(patch["rotation"]))
			if not simulation.terrain.is_water(position):
				details.append({"position": position, "kind": "shrub", "size": 1.15 + float(index % 3) * 0.22, "tone": fmod(float(index) * 0.31 + float(patch_index) * 0.17, 1.0)})
	details.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector2(a["position"]).y < Vector2(b["position"]).y)

func process_visual(delta: float) -> void:
	visual_clock += delta
	objective_lens.update(systems.current_objective_lens(), delta)
	display_radius = lerpf(display_radius, simulation.world_radius, 1.0 - exp(-delta * WORLD_REVEAL_RESPONSE))
	if absf(display_radius - simulation.world_radius) < 0.25:
		display_radius = simulation.world_radius
	expansion_flash = maxf(0.0, expansion_flash - delta)
	var critical_target := 1.0 if systems.is_critical() else 0.0
	critical_visual = lerpf(critical_visual, critical_target, 1.0 - exp(-delta * 2.2))
	for entity_id in spawn_effects.keys():
		spawn_effects[entity_id]["age"] += delta
		if spawn_effects[entity_id]["age"] > float(spawn_effects[entity_id].get("duration", 0.65)):
			spawn_effects.erase(entity_id)
	for effect in ambient_effects:
		effect["age"] += delta
	for index in range(ambient_effects.size() - 1, -1, -1):
		if ambient_effects[index]["age"] > ambient_effects[index]["duration"]:
			ambient_effects.remove_at(index)
	queue_redraw()

func set_camera_zoom(value: float) -> void:
	camera_zoom = maxf(0.01, value)

func is_position_revealed(position: Vector2) -> bool:
	if simulation == null:
		return false
	var clearance := float(simulation.config["world"].get("placement_clearance", 0.0))
	return position.length() <= simulation.boundary_radius_at(position.angle(), display_radius) - clearance

func _zoom_compensation() -> float:
	# Preserve most of the on-screen size of gameplay pieces as geography grows.
	# They still become a little smaller over the full run, so expansion remains
	# perceptible, but never enough to demand squinting.
	return clampf(pow(1.0 / camera_zoom, 0.72), 1.0, MAX_ZOOM_COMPENSATION)

func set_placement_preview(item: String, world_position: Vector2, valid: bool, visible: bool = true, quality: String = "fair") -> void:
	placement_item = item
	placement_position = world_position
	placement_valid = valid
	placement_quality = quality
	placement_visible = visible and not item.is_empty()
	queue_redraw()

func set_public_selection(kind: String, entity_id: int) -> void:
	selected_animal_kind = kind
	selected_animal_id = entity_id
	queue_redraw()

func set_debug_selection(kind: String, entity_id: int) -> void:
	debug_selected_kind = kind
	debug_selected_id = entity_id
	queue_redraw()

func _on_entity_added(kind: String, entity_id: int, reason: String) -> void:
	spawn_effects[entity_id] = {"age": 0.0, "kind": kind, "reason": reason, "duration": 1.8 if reason == "birth" else 0.65}
	if reason == "birth" and kind in ["rabbit", "fox"]:
		var animal: Dictionary = simulation.animal_snapshot(kind, entity_id)
		_add_life_event({
			"type": "birth", "kind": kind, "entity_id": entity_id,
			"position": animal.get("position", Vector2.ZERO),
			"label": "%s · born" % str(animal.get("name", kind.capitalize())),
			"age": 0.0, "duration": LIFE_EVENT_DURATION,
		})

func _on_entity_removed(kind: String, entity_id: int, position: Vector2, cause: String) -> void:
	spawn_effects.erase(entity_id)
	if cause == "undo":
		return
	if kind not in ["rabbit", "fox"]:
		ambient_effects.append({"type": "removal", "kind": kind, "position": position, "cause": cause, "age": 0.0, "duration": 0.85})
		return
	# A newborn's label must not keep saying "born" over a later death marker.
	for index in range(ambient_effects.size() - 1, -1, -1):
		if int(ambient_effects[index].get("entity_id", -1)) == entity_id:
			ambient_effects.remove_at(index)
	var animal: Dictionary = {}
	if simulation.has_method("death_snapshot"):
		animal = simulation.call("death_snapshot", kind, entity_id)
	var cause_text := "died"
	match cause:
		"age":
			cause_text = "died of old age"
		"starvation":
			cause_text = "starved"
		"predation":
			cause_text = "caught by a fox"
	_add_life_event({
		"type": "death", "kind": kind, "entity_id": entity_id,
		"position": position, "cause": cause,
		"label": "%s · %s" % [str(animal.get("name", kind.capitalize())), cause_text],
		"age": 0.0, "duration": LIFE_EVENT_DURATION,
	})

func _add_life_event(effect: Dictionary) -> void:
	var label_count := 0
	for existing in ambient_effects:
		if existing["type"] in ["birth", "death"]:
			label_count += 1
	if label_count >= MAX_LIFE_EVENT_LABELS:
		for index in range(ambient_effects.size()):
			if ambient_effects[index]["type"] in ["birth", "death"]:
				ambient_effects.remove_at(index)
				break
	ambient_effects.append(effect)

func _on_plant_eaten(_plant_id: int, position: Vector2) -> void:
	if ambient_effects.size() < 28:
		ambient_effects.append({"type": "nibble", "position": position, "age": 0.0, "duration": 0.42})

func _on_plant_state_changed(_plant_id: int, _previous_state: String, new_state: String, position: Vector2) -> void:
	if new_state not in ["depleted", "recovering", "healthy"] or ambient_effects.size() >= 28:
		return
	ambient_effects.append({
		"type": "plant_state",
		"state": new_state,
		"position": position,
		"age": 0.0,
		"duration": 1.05 if new_state == "depleted" else 1.35,
	})

func _on_world_expanded(_new_radius: float) -> void:
	expansion_flash = 2.2

var removal_target_id := -1

func _draw() -> void:
	_draw_terrain()
	_draw_pollen()
	_draw_details()
	var pieces := _build_scene_pieces()
	_draw_ground_pieces(pieces)
	_draw_objective_evidence()
	_draw_scene_pieces(pieces)
	_draw_life_stage_markers()
	_draw_objective_evidence_symbols()
	_draw_objective_attention()
	_draw_effects()
	_draw_objective_feedback()
	_draw_life_event_labels()
	_draw_public_selection()
	_draw_debug()
	_draw_placement_preview()
	if systems.remove_food_mode and not systems.supply_pending and systems.simulation.plants.has(removal_target_id):
		var target: Vector2 = systems.simulation.plants[removal_target_id]["position"]
		var color := Color(0.85, 0.32, 0.23)
		draw_arc(target, 22.0, 0.0, TAU, 48, color, 2.5, true)
		draw_line(target + Vector2(-7, -7), target + Vector2(7, 7), color, 2.5, true)
		draw_line(target + Vector2(-7, 7), target + Vector2(7, -7), color, 2.5, true)

func _draw_terrain() -> void:
	var boundary := _boundary_polygon(display_radius, 128)
	var maximum_radius: float = float(simulation.config["world"]["maximum_radius"])
	var texture_extent := maximum_radius * 1.34
	var meadow_tint := Color.WHITE.lerp(Color("#c69a63"), critical_visual * 0.56)
	meadow_tint = meadow_tint.darkened(critical_visual * 0.12)
	# Let silhouettes and habitat boundaries carry the scene. The existing
	# painted material contributes only a quiet grain over the meadow palette.
	draw_rect(Rect2(Vector2.ONE * -texture_extent, Vector2.ONE * texture_extent * 2.0), COLOR_GRASS.lerp(Color("#b5a078"), critical_visual * 0.48))
	meadow_tint.a = 0.14
	for tile_y in range(2):
		for tile_x in range(2):
			var tile_position := Vector2(
				-texture_extent + float(tile_x) * texture_extent,
				-texture_extent + float(tile_y) * texture_extent
			)
			draw_texture_rect(MEADOW_GROUND, Rect2(tile_position, Vector2.ONE * texture_extent), false, meadow_tint)
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
		var shadow_patch: Dictionary = patch.duplicate()
		shadow_patch["center"] = center + Vector2(0.0, 7.0)
		_draw_habitat_wash(shadow_patch, 1.035, patch_index, Color(0.17, 0.28, 0.18, 0.09))
		var tone := COLOR_FOREST.lerp(Color("#5d8b68"), float(patch["tone"]) * 0.36).darkened(critical_visual * 0.18)
		tone.a = 0.24
		_draw_habitat_wash(patch, 1.0, patch_index, tone)
		var inner_tone := COLOR_FOREST_DARK.lerp(tone, 0.58)
		inner_tone.a = 0.12
		_draw_habitat_wash(patch, 0.68, patch_index + 71, inner_tone)
		_draw_forest_edge_tufts(patch, patch_index)
	# Low cover has a warmer floor and dense clustered leaves. Its individual
	# crowns share depth ordering with creatures, rather than overlaying them all.
	for patch_index in range(simulation.terrain.thicket_patches.size()):
		var patch: Dictionary = simulation.terrain.thicket_patches[patch_index]
		var center: Vector2 = patch["center"]
		var radius: float = patch["radius"]
		if center.length() - radius > display_radius * 1.02:
			continue
		var tone := COLOR_THICKET.lerp(Color("#6f8b54"), float(patch["tone"]) * 0.38).darkened(critical_visual * 0.15)
		_draw_habitat_wash(patch, 1.0, patch_index + 311, Color(tone.r, tone.g, tone.b, 0.28))
		_draw_habitat_wash(patch, 0.67, patch_index + 419, Color(COLOR_THICKET_DARK.r, COLOR_THICKET_DARK.g, COLOR_THICKET_DARK.b, 0.15))
	_draw_stream()
	_draw_exterior_mask(boundary)
	_draw_exterior_ambience()
	# A soft reveal edge communicates the growing playable boundary without
	# turning it back into a raised board or globe.
	var rim_color := Color(0.83, 0.94, 0.66, 0.24 + expansion_flash * 0.05)
	draw_polyline(boundary, rim_color, 3.2, true)
	var inner_boundary := _boundary_polygon(maxf(0.0, display_radius - 8.0), 128)
	draw_polyline(inner_boundary, Color(COLOR_SOIL.r, COLOR_SOIL.g, COLOR_SOIL.b, 0.14), 1.4, true)

func _draw_stream() -> void:
	var points: PackedVector2Array = simulation.terrain.stream_points
	var widths: PackedFloat32Array = simulation.terrain.stream_half_widths
	if points.size() < 2:
		return
	# Layered banks give the channel a soft painted edge: earth shadow, mossy lip,
	# shallow water, then the cool moving center.
	draw_set_transform(Vector2(3.5, 6.0), 0.0, Vector2.ONE)
	_draw_stream_band(points, widths, 12.0, Color(0.08, 0.16, 0.12, 0.34))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_stream_band(points, widths, 10.0, Color(0.39, 0.45, 0.29, 0.88))
	_draw_stream_band(points, widths, 7.0, Color(COLOR_BANK.r, COLOR_BANK.g, COLOR_BANK.b, 0.92))
	_draw_stream_band(points, widths, 4.0, Color("#8fbda4").darkened(critical_visual * 0.08))
	_draw_stream_band(points, widths, 0.0, COLOR_STREAM_DEEP.darkened(critical_visual * 0.12))
	_draw_textured_stream(points, widths)
	_draw_stream_edges(points, widths)
	_draw_riverbank_details(points, widths)
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
		draw_colored_polygon(ford_shape, Color(0.69, 0.75, 0.61, 0.26))
		draw_line(center - normal * width, center + normal * width, Color(0.80, 0.91, 0.78, 0.20), 5.0, true)
		for stone_index in range(7):
			var amount := (float(stone_index) - 3.0) / 6.0
			var stone_position := center + normal * amount * width * 1.45 + tangent * sin(float(stone_index) * 2.3) * 3.2
			_draw_stone(stone_position, 0.72 + float(stone_index % 3) * 0.12, tangent.angle() + float(stone_index) * 0.18, 0.96)
			draw_arc(stone_position + tangent * 1.5, 5.5, tangent.angle() - 0.8, tangent.angle() + 0.8, 10, Color(0.76, 0.92, 0.91, 0.34), 1.0, true)
	# Moving glints sit above the painted current and keep the material alive.
	for index in range(2, points.size() - 2, 3):
		var point := points[index]
		if not _inside_display(point, -30.0):
			continue
		var tangent := (points[index + 1] - points[index - 1]).normalized()
		var phase := 0.28 + sin(visual_clock * 0.85 + float(index) * 1.7) * 0.14
		var drift := tangent * fmod(visual_clock * 3.0 + float(index * 7), 10.0)
		draw_line(point - tangent * 7.0 + drift, point + tangent * 5.0 + drift, Color(0.80, 0.95, 0.92, phase), 1.25, true)

func _draw_textured_stream(points: PackedVector2Array, widths: PackedFloat32Array) -> void:
	var flow_offset := Vector2(visual_clock * 0.0025, visual_clock * 0.010)
	var water_tint := Color.WHITE.lerp(Color("#9b866f"), critical_visual * 0.22)
	water_tint.a = 0.34
	for index in range(points.size() - 1):
		var first := points[index]
		var second := points[index + 1]
		var tangent := (second - first).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var first_width := float(widths[index])
		var second_width := float(widths[index + 1])
		var polygon := PackedVector2Array([
			first - normal * first_width,
			second - normal * second_width,
			second + normal * second_width,
			first + normal * first_width,
		])
		var uvs := PackedVector2Array()
		for vertex in polygon:
			uvs.append(vertex / 230.0 + flow_offset)
		draw_polygon(polygon, PackedColorArray([water_tint]), uvs, STREAM_WATER)

func _draw_stream_edges(points: PackedVector2Array, widths: PackedFloat32Array) -> void:
	for index in range(points.size() - 1):
		var first := points[index]
		var second := points[index + 1]
		var tangent := (second - first).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var first_width := float(widths[index])
		var second_width := float(widths[index + 1])
		draw_line(first - normal * (first_width - 1.3), second - normal * (second_width - 1.3), Color(0.72, 0.91, 0.85, 0.40), 1.25, true)
		draw_line(first + normal * (first_width + 0.8), second + normal * (second_width + 0.8), Color(0.14, 0.31, 0.29, 0.30), 1.6, true)

func _draw_riverbank_details(points: PackedVector2Array, widths: PackedFloat32Array) -> void:
	for index in range(2, points.size() - 2, 2):
		var tangent := (points[index + 1] - points[index - 1]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		for side in [-1.0, 1.0]:
			var bank_position: Vector2 = points[index] + normal * side * (float(widths[index]) + 7.0)
			bank_position += tangent * sin(float(index) * 2.17 + side) * 4.0
			if not _inside_display(bank_position, -8.0):
				continue
			var detail_slot := int(index / 2) + (1 if side > 0.0 else 0)
			if detail_slot % 3 == 0:
				_draw_stone(bank_position, 1.04 + float(index % 3) * 0.15, tangent.angle(), 0.84)
				if detail_slot % 6 == 0:
					_draw_stone(bank_position + tangent * 8.0 - normal * side * 2.0, 0.72, tangent.angle() + 0.42, 0.76)
					_draw_stone(bank_position - tangent * 6.0 + normal * side * 1.5, 0.48, tangent.angle() - 0.35, 0.66)
			else:
				var reed_tone := Color("#68834d") if side > 0.0 else Color("#778e50")
				for blade in range(5):
					var offset := tangent * (float(blade) - 2.0) * 1.8
					var lean := tangent * sin(float(index + blade)) * 1.8
					var blade_tip := bank_position + offset + Vector2(0.0, -4.0 - float(blade % 3) * 2.0) + lean
					draw_line(bank_position + offset + Vector2(0.0, 2.0), blade_tip, Color(reed_tone.r, reed_tone.g, reed_tone.b, 0.72), 1.25, true)
					if blade % 2 == 0:
						draw_circle(blade_tip, 0.9, Color(0.75, 0.68, 0.40, 0.66))

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
	# These are the same seeded trees that will be revealed later. Their ground
	# anchors never follow the expanding boundary.
	for detail in details:
		if detail["kind"] != "tree":
			continue
		var position: Vector2 = detail["position"]
		var beyond := position.length() - simulation.boundary_radius_at(position.angle(), display_radius)
		if beyond <= -5.0 or beyond > 72.0:
			continue
		var alpha := 1.0 - smoothstep(-5.0, 72.0, beyond)
		_draw_conifer(position, _scenery_scale(detail), float(detail["tone"]), alpha)

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

func _draw_habitat_wash(patch: Dictionary, size_factor: float, phase: int, color: Color) -> void:
	# Six cached contours feather habitat transitions without per-frame geometry
	# work, while the terrain fields remain the source of every patch position.
	var key := "%s:%s:%.3f:%d" % [patch["center"], patch["radius"], size_factor, phase]
	if not habitat_wash_geometry.has(key):
		var contours: Array[PackedVector2Array] = []
		for layer in range(6):
			contours.append(_organic_ellipse(patch, size_factor * lerpf(1.06, 0.84, float(layer) / 5.0), phase))
		habitat_wash_geometry[key] = contours
	var tint := color
	tint.a = 1.0 - pow(1.0 - color.a, 1.0 / 6.0)
	for contour in habitat_wash_geometry[key]:
		draw_colored_polygon(contour, tint)

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
		if not _inside_display(position, 5.0) or detail["kind"] in ["tree", "shrub"]:
			continue
		var size: float = detail["size"]
		match detail["kind"]:
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
				_draw_stone(position, size * 0.68, float(detail["tone"]) * PI, 0.62)

func _draw_conifer(position: Vector2, size_factor: float, tone: float, alpha: float = 1.0) -> void:
	HabitatArt.draw_tree(self, position, size_factor, tone, alpha, critical_visual)

func _draw_stone(position: Vector2, size_factor: float, rotation: float, alpha: float = 1.0) -> void:
	draw_set_transform(position, rotation, Vector2.ONE * size_factor)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7.2, 2.8), Vector2(-3.4, -2.1), Vector2(4.8, -1.0), Vector2(8.5, 4.3), Vector2(-1.0, 6.3),
	]), Color(0.05, 0.11, 0.09, 0.20 * alpha))
	var stone := Color("#777b6e").lerp(Color("#a49e83"), fmod(absf(rotation), 1.0) * 0.45).darkened(critical_visual * 0.08)
	stone.a = alpha
	draw_colored_polygon(PackedVector2Array([
		Vector2(-7.0, 1.2), Vector2(-3.0, -4.0), Vector2(3.7, -3.3), Vector2(7.0, 1.5), Vector2(3.0, 4.0), Vector2(-4.6, 3.7),
	]), stone)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.0, -4.0), Vector2(3.7, -3.3), Vector2(1.4, -0.2), Vector2(-4.6, 0.2),
	]), Color(0.78, 0.79, 0.68, 0.38 * alpha))
	draw_line(Vector2(1.4, -0.2), Vector2(3.0, 4.0), Color(0.29, 0.32, 0.29, 0.34 * alpha), 0.9, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _scenery_scale(detail: Dictionary) -> float:
	# Some zoom compensation keeps the canopy/animal relationship stable while
	# maintaining the existing minimum readable size for gameplay creatures.
	return float(detail["size"]) * sqrt(_zoom_compensation())

func _animal_scale(animal: Dictionary) -> float:
	var factor := _spawn_scale(int(animal["id"])) * ANIMAL_VISUAL_SCALE * _zoom_compensation()
	var adult_age := float(simulation.config[animal["type"]]["adult_age"])
	return factor * lerpf(0.66, 1.0, clampf(float(animal["age"]) / maxf(0.01, adult_age), 0.0, 1.0))

func _build_scene_pieces() -> Array:
	var pieces: Array = []
	foliage_subjects.clear()
	var alpha := systems.interpolation_alpha()
	for source in [simulation.rabbits, simulation.foxes]:
		for animal in source.values():
			var position: Vector2 = animal["previous_position"].lerp(animal["position"], alpha)
			var pose := AnimalMotion.sample(animal, alpha, simulation.simulation_time, float(simulation.config["simulation"]["fixed_step"]))
			pieces.append({"kind": "animal", "position": position, "data": animal, "pose": pose, "scale": _animal_scale(animal)})
			var cell := Vector2i(floori(position.x / FOLIAGE_CELL_SIZE), floori(position.y / FOLIAGE_CELL_SIZE))
			if not foliage_subjects.has(cell):
				foliage_subjects[cell] = []
			foliage_subjects[cell].append(position)
	for plant in simulation.plants.values():
		if not simulation.terrain.is_deep_water(plant["position"]):
			pieces.append({"kind": "plant", "position": plant["position"], "data": plant, "scale": _spawn_scale(plant["id"]) * PLANT_VISUAL_SCALE * _zoom_compensation()})
	for detail in details:
		if detail["kind"] in ["tree", "shrub"] and _inside_display(detail["position"], 5.0):
			pieces.append({"kind": detail["kind"], "position": detail["position"], "data": detail, "scale": _scenery_scale(detail)})
	pieces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["position"].y), float(b["position"].y)):
			return float(a["position"].y) < float(b["position"].y)
		return str(a["kind"]) < str(b["kind"]))
	return pieces

func _foliage_alpha(position: Vector2, radius: float, minimum_alpha: float) -> float:
	var cell := Vector2i(floori(position.x / FOLIAGE_CELL_SIZE), floori(position.y / FOLIAGE_CELL_SIZE))
	var opacity := 1.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for subject in foliage_subjects.get(cell + Vector2i(dx, dy), []):
				var offset: Vector2 = subject - position
				# Keep this continuous on both sides of the depth boundary. Cutting
				# opacity at the anchor makes the entire canopy pop while crossing it.
				var distance := Vector2(offset.x, offset.y / 0.86).length()
				opacity = minf(opacity, lerpf(minimum_alpha, 1.0, smoothstep(radius * 0.45, radius + 12.0 * _zoom_compensation(), distance)))
	return opacity

func _draw_ground_pieces(pieces: Array) -> void:
	for piece in pieces:
		var position: Vector2 = piece["position"]
		var scale_factor := float(piece["scale"])
		match piece["kind"]:
			"tree", "shrub":
				var footprint := HabitatArt.tree_footprint(scale_factor) if piece["kind"] == "tree" else HabitatArt.shrub_footprint(scale_factor)
				HabitatArt.draw_shadow(self, position, footprint)
			"animal":
				var lift := float(piece["pose"]["lift"])
				var radius := 8.2 if piece["data"]["type"] == "rabbit" else 11.0
				draw_set_transform(position + Vector2(0.0, 4.0 * scale_factor), 0.0, Vector2(1.0, 0.64) * scale_factor)
				draw_circle(Vector2.ZERO, radius - lift * 0.24, Color(0.07, 0.13, 0.10, 0.22 - lift * 0.012))
			"plant":
				var plant: Dictionary = piece["data"]
				draw_set_transform(position, 0.0, Vector2.ONE * scale_factor)
				_draw_plant_habitat_footprint(plant["type"], _plant_habitat_quality(plant), plant["id"])
		# Every item starts from world coordinates, including foliage helpers.
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_scene_pieces(pieces: Array) -> void:
	for piece in pieces:
		var position: Vector2 = piece["position"]
		var scale_factor := float(piece["scale"])
		var data: Dictionary = piece["data"]
		match piece["kind"]:
			"tree":
				_draw_conifer(position, scale_factor, float(data["tone"]), _foliage_alpha(position, 28.0 * scale_factor, 0.30))
			"shrub":
				HabitatArt.draw_shrub(self, position, scale_factor, float(data["tone"]), _foliage_alpha(position, 13.0 * scale_factor, 0.28), critical_visual)
			"plant":
				draw_set_transform(position, 0.0, Vector2.ONE * scale_factor)
				if data["type"] == "carrot_patch":
					_draw_carrot_patch(simulation.plant_stock_ratio(data), simulation.plant_ecology_state(data), data["id"], _plant_habitat_quality(data), false)
				else:
					_draw_berry_bush(simulation.plant_stock_ratio(data), simulation.plant_ecology_state(data), data["id"], _plant_habitat_quality(data), false)
			"animal":
				var pose: Dictionary = piece["pose"]
				draw_set_transform(position - Vector2(0.0, float(pose["lift"]) * scale_factor), float(pose["facing"]), Vector2(pose["stretch"]) * scale_factor)
				if data["type"] == "rabbit":
					_draw_rabbit(data, pose)
				else:
					_draw_fox(data, pose)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _plant_habitat_quality(plant: Dictionary) -> float:
	var suitability_cfg: Dictionary = simulation.config.get("terrain", {}).get("food_suitability", {})
	var poor := float(suitability_cfg.get("poor_capacity_factor", 0.48))
	var rich := float(suitability_cfg.get("rich_capacity_factor", 1.28))
	return clampf(inverse_lerp(poor, rich, float(plant.get("habitat_capacity_factor", 1.0))), 0.0, 1.0)

func _habitat_quality_at(plant_type: String, position: Vector2) -> float:
	var suitability_cfg: Dictionary = simulation.config.get("terrain", {}).get("food_suitability", {})
	var poor := float(suitability_cfg.get("poor_capacity_factor", 0.48))
	var rich := float(suitability_cfg.get("rich_capacity_factor", 1.28))
	var capacity := simulation.terrain.food_capacity_factor(plant_type, position)
	return clampf(inverse_lerp(poor, rich, capacity), 0.0, 1.0)

func _draw_plant_habitat_footprint(plant_type: String, quality: float, entity_id: int) -> void:
	# The footprint is established at placement and never changes with grazing.
	# Fertile sites retain a broad green verge; poor sites retain pale compacted soil.
	var radius := lerpf(13.0, 17.5, quality)
	var ground := Color("#9a8156").lerp(Color("#5d844a"), quality)
	draw_circle(Vector2(1.2, 4.2), radius + 1.8, Color(0.06, 0.14, 0.09, 0.13))
	draw_circle(Vector2.ZERO, radius, Color(ground.r, ground.g, ground.b, 0.50))
	draw_arc(Vector2.ZERO, radius - 1.2, 0.0, TAU, 28, Color(0.83, 0.89, 0.58, 0.12 + quality * 0.20), 1.4, true)
	if quality < 0.42:
		for index in range(3):
			var angle := float(index) / 3.0 * TAU + float(entity_id) * 0.31
			var start := Vector2.from_angle(angle) * (5.5 + float(index % 2) * 2.0)
			draw_line(start, start + Vector2.from_angle(angle + 0.55) * 4.2, Color(0.34, 0.27, 0.16, 0.38), 1.1, true)
	elif quality > 0.62:
		for index in range(5):
			var angle := float(index) / 5.0 * TAU + float(entity_id) * 0.19
			var base := Vector2.from_angle(angle) * (radius - 2.2)
			var height := 2.8 + quality * 2.3
			draw_line(base, base + Vector2(sin(angle) * 1.4, -height), Color(0.31, 0.58, 0.28, 0.58), 1.2, true)
	# Berries favor a slightly leafier permanent verge; this is species identity,
	# not a stock indication.
	if plant_type == "berry_bush" and quality > 0.52:
		draw_circle(Vector2(-radius * 0.62, 2.5), 2.2, Color(0.35, 0.61, 0.31, 0.42))

func _draw_carrot_patch(stock_ratio: float, ecology_state: String, entity_id: int, habitat_quality: float, footprint: bool = true) -> void:
	if footprint:
		_draw_plant_habitat_footprint("carrot_patch", habitat_quality, entity_id)
	ForageArt.draw_carrot(self, stock_ratio, ecology_state, entity_id, visual_clock)

func _draw_berry_bush(stock_ratio: float, ecology_state: String, entity_id: int, habitat_quality: float, footprint: bool = true) -> void:
	if footprint:
		_draw_plant_habitat_footprint("berry_bush", habitat_quality, entity_id)
	ForageArt.draw_berry(self, stock_ratio, ecology_state, entity_id, visual_clock)

func _draw_life_stage_markers() -> void:
	var scale_factor := _zoom_compensation()
	for source in [simulation.rabbits, simulation.foxes]:
		for animal in source.values():
			if float(animal["age"]) < float(animal["lifespan"]) * 0.78:
				continue
			var position: Vector2 = animal["previous_position"].lerp(animal["position"], systems.interpolation_alpha())
			# The clock stays upright, separate from hunger's orange/red rings.
			draw_set_transform(position + Vector2(0.0, -25.0) * scale_factor, 0.0, Vector2.ONE * scale_factor)
			draw_circle(Vector2(0.5, 1.3), 7.4, Color(0.08, 0.16, 0.13, 0.24))
			draw_circle(Vector2.ZERO, 7.0, Color("#f8efdf"))
			draw_arc(Vector2.ZERO, 5.3, 0.0, TAU, 20, Color("#756a86"), 1.3, true)
			draw_line(Vector2.ZERO, Vector2(0.0, -3.4), Color("#756a86"), 1.5, true)
			draw_line(Vector2.ZERO, Vector2(2.8, 1.5), Color("#756a86"), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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

func _draw_rabbit(rabbit: Dictionary, pose: Dictionary = {}) -> void:
	var rabbit_cfg: Dictionary = simulation.config["rabbit"]
	var hunger: float = float(rabbit["hunger"])
	var starvation_at: float = float(rabbit_cfg["starvation_threshold"])
	var warning_at: float = float(rabbit_cfg["hunger_warning_at"])
	var hunger_ratio := hunger / starvation_at
	var distress := smoothstep(0.62, 1.0, hunger_ratio)
	var body_color := COLOR_RABBIT.lerp(Color("#b9b2a5"), distress * 0.52)
	if pose.is_empty():
		pose = {"phase": 0.0, "move": 0.0, "time": simulation.simulation_time, "capture": 0.0, "lift": 0.0}
	AnimalArt.draw_rabbit(self, rabbit, pose, body_color)
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

func _draw_fox(fox: Dictionary, pose: Dictionary = {}) -> void:
	var hunger_ratio: float = float(fox["hunger"]) / float(simulation.config["fox"]["starvation_threshold"])
	var distress := smoothstep(0.65, 1.0, hunger_ratio)
	var body_color := COLOR_FOX.lerp(Color("#9e705d"), distress * 0.48)
	if pose.is_empty():
		pose = {"phase": 0.0, "move": 0.0, "time": simulation.simulation_time, "capture": 0.0, "lift": 0.0}
	AnimalArt.draw_fox(self, fox, pose, body_color)
	if fox["behavior"] == "hunt":
		draw_arc(Vector2.ZERO, 12.0, -0.5, 0.5, 10, Color(1.0, 0.74, 0.42, 0.72), 1.3, true)
	elif distress > 0.42:
		var pulse := 0.35 + sin(visual_clock * 3.5 + fox["id"]) * 0.12
		draw_arc(Vector2.ZERO, 12.0, -2.35, -0.8, 9, Color(0.72, 0.62, 0.52, pulse * distress), 1.0, true)

func _draw_objective_evidence() -> void:
	for marker in objective_lens.evidence_markers.values():
		var alpha := float(marker.get("alpha", 0.0))
		if alpha <= 0.001:
			continue
		var data: Dictionary = marker["data"]
		match str(data.get("role", "")):
			"birthplace":
				_draw_birthplace_marker(_objective_marker_position(marker), int(data.get("ordinal", 1)), alpha)
			"nursery":
				_draw_nursery_marker(_objective_marker_position(marker), int(data.get("ordinal", 1)), alpha)

func _draw_birthplace_marker(position: Vector2, ordinal: int, alpha: float) -> void:
	if position == Vector2.INF or not _inside_display(position, -42.0):
		return
	draw_set_transform(position, 0.0, Vector2.ONE * OBJECTIVE_VISUAL_SCALE * _zoom_compensation())
	position = Vector2.ZERO
	var leaf: Color = BiomeTheme.COLOR.leaf
	var footprint := _objective_patch(position, 31.0, ordinal * 19)
	draw_colored_polygon(footprint, Color(leaf.r, leaf.g, leaf.b, 0.10 * alpha))
	# Broken, organic strokes communicate a remembered neighborhood rather than
	# the evaluator's exact separation boundary.
	for segment in range(4):
		var start := float(segment) / 4.0 * TAU + float(ordinal) * 0.37
		var radius := 28.0 + sin(float(segment * 7 + ordinal)) * 3.0
		draw_arc(position, radius, start, start + 0.78, 9, Color(leaf.r, leaf.g, leaf.b, 0.42 * alpha), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_nursery_marker(position: Vector2, ordinal: int, alpha: float) -> void:
	if position == Vector2.INF or not _inside_display(position, -58.0):
		return
	draw_set_transform(position, 0.0, Vector2.ONE * OBJECTIVE_VISUAL_SCALE * _zoom_compensation())
	position = Vector2.ZERO
	var cream: Color = BiomeTheme.COLOR.surface_elevated
	var moss: Color = BiomeTheme.COLOR.moss
	var success: Color = BiomeTheme.COLOR.success
	var breath := 0.94 + sin(visual_clock * 0.85 + float(ordinal)) * 0.06
	# This fixed presentation footprint is a soft cradle, not the evaluator's
	# grouping radius. It stays group-scale and avoids the circular language used
	# by individual hunger alerts and the selected-animal ring.
	var footprint := _objective_patch(position, 49.0, ordinal * 31)
	draw_colored_polygon(footprint, Color(cream.r, cream.g, cream.b, 0.095 * alpha * breath))
	draw_colored_polygon(_objective_patch(position, 39.0, ordinal * 47), Color(moss.r, moss.g, moss.b, 0.055 * alpha * breath))
	draw_arc(position, 43.0, 0.18, 1.76, 18, Color(success.r, success.g, success.b, 0.60 * alpha), 2.4, true)
	draw_arc(position, 43.0, 1.38, PI - 0.18, 18, Color(success.r, success.g, success.b, 0.60 * alpha), 2.4, true)
	draw_arc(position + Vector2(0.0, -1.0), 38.0, 0.28, PI - 0.28, 24, Color(cream.r, cream.g, cream.b, 0.52 * alpha), 1.2, true)
	# Three pebbles and a leaf make the group-plus-forage idea legible without
	# circling individual animals or pointing to a specific food source.
	for seed_position in [Vector2(-10.0, 8.0), Vector2(0.0, 13.0), Vector2(10.0, 8.0)]:
		draw_circle(position + seed_position, 2.2, Color(cream.r, cream.g, cream.b, 0.68 * alpha))
	draw_line(position + Vector2(0.0, 3.0), position + Vector2(0.0, -7.0), Color(moss.r, moss.g, moss.b, 0.66 * alpha), 1.4, true)
	draw_colored_polygon(PackedVector2Array([
		position + Vector2(0.0, -5.0),
		position + Vector2(-7.0, -10.0),
		position + Vector2(-2.0, -14.0),
	]), Color(moss.r, moss.g, moss.b, 0.72 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_objective_evidence_symbols() -> void:
	for marker in objective_lens.evidence_markers.values():
		var alpha := float(marker.get("alpha", 0.0))
		if alpha <= 0.001:
			continue
		var data: Dictionary = marker["data"]
		match str(data.get("role", "")):
			"birthplace":
				_draw_birthplace_symbol(_objective_marker_position(marker), int(data.get("ordinal", 1)), alpha)
			"nursery":
				_draw_nursery_symbol(_objective_marker_position(marker), str(data.get("label", "Nursery")), int(data.get("ordinal", 1)), alpha)

func _draw_birthplace_symbol(position: Vector2, ordinal: int, alpha: float) -> void:
	if position == Vector2.INF or not _inside_display(position, -42.0):
		return
	draw_set_transform(position, 0.0, Vector2.ONE * OBJECTIVE_VISUAL_SCALE * _zoom_compensation())
	position = Vector2.ZERO
	var success: Color = BiomeTheme.COLOR.success
	var accent: Color = BiomeTheme.COLOR.accent
	var nest_position := position + Vector2(0.0, -10.0)
	draw_line(position + Vector2(0.0, -3.0), position + Vector2(0.0, -15.0), Color(success.r, success.g, success.b, 0.48 * alpha), 1.2, true)
	draw_arc(nest_position, 7.5, 0.20, PI - 0.20, 12, Color(success.r, success.g, success.b, 0.82 * alpha), 1.8, true)
	draw_arc(nest_position + Vector2(0.0, 2.2), 5.2, 0.15, PI - 0.15, 10, Color(accent.r, accent.g, accent.b, 0.72 * alpha), 1.4, true)
	var badge_position := position + Vector2(0.0, -23.0)
	draw_circle(badge_position + Vector2(0.8, 1.2), 7.3, Color(0.06, 0.14, 0.10, 0.16 * alpha))
	draw_circle(badge_position, 6.8, Color(success.r, success.g, success.b, 0.88 * alpha))
	draw_string(ThemeDB.fallback_font, badge_position + Vector2(-6.8, 4.0), str(ordinal), HORIZONTAL_ALIGNMENT_CENTER, 13.6, 11, Color(1.0, 0.98, 0.89, 0.96 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_nursery_symbol(position: Vector2, marker_label: String, ordinal: int, alpha: float) -> void:
	if position == Vector2.INF or not _inside_display(position, -62.0):
		return
	var world_position := position
	var inward := Vector2.UP if position.length() < 90.0 else -position.normalized()
	draw_set_transform(world_position, 0.0, Vector2.ONE * OBJECTIVE_VISUAL_SCALE * _zoom_compensation())
	position = Vector2.ZERO
	var badge_position := inward * 36.0
	var label_text := "%s %d" % [marker_label.to_upper(), ordinal]
	var badge_size := Vector2(84.0 if marker_label.length() > 6 else 70.0, 22.0)
	var cream: Color = BiomeTheme.COLOR.surface_elevated
	var forest: Color = BiomeTheme.COLOR.forest_deep
	var success: Color = BiomeTheme.COLOR.success
	var shadow: Color = Color(forest.r, forest.g, forest.b, 0.22 * alpha)
	var leader_start := position + inward * 13.0
	var leader_end := badge_position - inward * (badge_size.y * 0.5 - 1.0)
	draw_line(leader_start + Vector2(0.8, 1.4), leader_end + Vector2(0.8, 1.4), shadow, 2.2, true)
	draw_line(leader_start, leader_end, Color(success.r, success.g, success.b, 0.86 * alpha), 1.5, true)
	_draw_objective_capsule(badge_position + Vector2(0.9, 1.8), badge_size, shadow, Color.TRANSPARENT)
	_draw_objective_capsule(
		badge_position,
		badge_size,
		Color(cream.r, cream.g, cream.b, 0.96 * alpha),
		Color(success.r, success.g, success.b, 0.94 * alpha)
	)
	draw_string(
		ThemeDB.fallback_font,
		badge_position + Vector2(-badge_size.x * 0.5 + 6.0, 4.6),
		label_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		badge_size.x - 12.0,
		BiomeTheme.TYPE_SIZE.caption,
		Color(forest.r, forest.g, forest.b, 0.98 * alpha)
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_objective_capsule(center: Vector2, size: Vector2, fill: Color, outline: Color) -> void:
	var radius := size.y * 0.5
	var left := center + Vector2(-size.x * 0.5 + radius, 0.0)
	var right := center + Vector2(size.x * 0.5 - radius, 0.0)
	draw_rect(Rect2(left.x, center.y - radius, right.x - left.x, size.y), fill, true)
	draw_circle(left, radius, fill)
	draw_circle(right, radius, fill)
	if outline.a <= 0.001:
		return
	draw_line(left + Vector2(0.0, -radius), right + Vector2(0.0, -radius), outline, 1.7, true)
	draw_line(left + Vector2(0.0, radius), right + Vector2(0.0, radius), outline, 1.7, true)
	draw_arc(left, radius, PI * 0.5, PI * 1.5, 12, outline, 1.7, true)
	draw_arc(right, radius, -PI * 0.5, PI * 0.5, 12, outline, 1.7, true)

func _objective_marker_position(marker: Dictionary) -> Vector2:
	var data: Dictionary = marker.get("data", {})
	return marker.get("display_position", data.get("position", Vector2.INF))

func _objective_patch(center: Vector2, radius: float, phase: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(32):
		var angle := float(index) / 32.0 * TAU
		var wobble := 1.0 + sin(angle * 3.0 + float(phase) * 0.31) * 0.11 + sin(angle * 7.0 - float(phase) * 0.17) * 0.045
		points.append(center + Vector2.from_angle(angle) * radius * wobble)
	return points

func _draw_objective_attention() -> void:
	for marker in objective_lens.attention_markers.values():
		var alpha := float(marker.get("alpha", 0.0))
		if alpha <= 0.001:
			continue
		var data: Dictionary = marker["data"]
		var position := _objective_subject_position(data)
		if position == Vector2.INF or not _inside_display(position, -24.0):
			continue
		match str(data.get("role", "")):
			"offspring":
				_draw_offspring_attention(position, str(data.get("state", "needs_food")), int(data.get("entity_id", 0)), alpha)

func _objective_subject_position(data: Dictionary) -> Vector2:
	var kind := str(data.get("entity_kind", ""))
	var entity_id := int(data.get("entity_id", -1))
	var source: Dictionary = simulation.rabbits if kind == "rabbit" else (simulation.foxes if kind == "fox" else {})
	if source.has(entity_id):
		var entity: Dictionary = source[entity_id]
		return entity["previous_position"].lerp(entity["position"], systems.interpolation_alpha())
	return data.get("position", Vector2.INF)

func _draw_offspring_attention(position: Vector2, state: String, entity_id: int, alpha: float) -> void:
	draw_set_transform(position, 0.0, Vector2.ONE * OBJECTIVE_VISUAL_SCALE * _zoom_compensation())
	position = Vector2.ZERO
	var color: Color = BiomeTheme.COLOR.accent
	if state == "satisfied":
		color = BiomeTheme.COLOR.success
	elif state == "growing":
		color = BiomeTheme.COLOR.info
	var pulse := 0.5 + sin(visual_clock * 2.4 + float(entity_id) * 0.71) * 0.10
	var ring_radius := 13.1 + pulse
	for segment in range(3):
		var start := float(segment) / 3.0 * TAU + visual_clock * 0.10
		draw_arc(position, ring_radius, start, start + 1.38, 8, Color(color.r, color.g, color.b, (0.38 + pulse * 0.16) * alpha), 1.35, true)
	var badge := position + Vector2(0.0, -15.5)
	draw_circle(badge + Vector2(0.7, 1.0), 4.8, Color(0.05, 0.13, 0.09, 0.20 * alpha))
	draw_circle(badge, 4.5, Color(color.r, color.g, color.b, 0.90 * alpha))
	if state == "satisfied":
		draw_line(badge + Vector2(-2.3, 0.0), badge + Vector2(-0.5, 2.0), Color(1.0, 0.98, 0.88, 0.96 * alpha), 1.25, true)
		draw_line(badge + Vector2(-0.5, 2.0), badge + Vector2(2.5, -2.1), Color(1.0, 0.98, 0.88, 0.96 * alpha), 1.25, true)
	elif state == "growing":
		draw_line(badge + Vector2(0.0, 2.7), badge + Vector2(0.0, -2.3), Color(1.0, 0.98, 0.88, 0.92 * alpha), 1.0, true)
		draw_line(badge + Vector2(0.0, -0.5), badge + Vector2(-2.3, -2.1), Color(1.0, 0.98, 0.88, 0.92 * alpha), 1.0, true)
		draw_line(badge + Vector2(0.0, 0.4), badge + Vector2(2.3, -1.3), Color(1.0, 0.98, 0.88, 0.92 * alpha), 1.0, true)
	else:
		draw_circle(badge, 1.35, Color(1.0, 0.98, 0.88, 0.96 * alpha))
		for seed_index in range(3):
			var angle := float(seed_index) / 3.0 * TAU - PI * 0.5
			draw_circle(badge + Vector2.from_angle(angle) * 2.8, 0.65, Color(1.0, 0.98, 0.88, 0.78 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_objective_feedback() -> void:
	for effect in objective_lens.feedback:
		var data: Dictionary = effect["data"]
		var role := str(data.get("role", ""))
		if role == "nursery":
			_draw_nursery_feedback(data, effect)
			continue
		if role != "birthplace":
			continue
		var position: Vector2 = data.get("position", Vector2.INF)
		if position == Vector2.INF or not _inside_display(position, -58.0):
			continue
		draw_set_transform(position, 0.0, Vector2.ONE * OBJECTIVE_VISUAL_SCALE * _zoom_compensation())
		position = Vector2.ZERO
		var progress := clampf(float(effect["age"]) / maxf(0.001, float(effect["duration"])), 0.0, 1.0)
		var established := str(data.get("state", "")) == "established"
		var color: Color = BiomeTheme.COLOR.success if established else BiomeTheme.COLOR.accent
		var wave := sin(progress * PI)
		var radius := lerpf(22.0, 47.0 if established else 35.0, progress)
		draw_arc(position, radius, 0.0, TAU, 36, Color(color.r, color.g, color.b, wave * (0.58 if established else 0.42)), 2.3 if established else 1.7, true)
		if established:
			for spark in range(5):
				var angle := float(spark) / 5.0 * TAU + float(data.get("ordinal", 1)) * 0.43
				var spark_position := position + Vector2.from_angle(angle) * lerpf(15.0, 31.0, progress)
				draw_circle(spark_position, 1.7 * (1.0 - progress), Color(color.r, color.g, color.b, wave * 0.68))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_nursery_feedback(data: Dictionary, effect: Dictionary) -> void:
	var position: Vector2 = data.get("position", Vector2.INF)
	if position == Vector2.INF or not _inside_display(position, -74.0):
		return
	draw_set_transform(position, 0.0, Vector2.ONE * OBJECTIVE_VISUAL_SCALE * _zoom_compensation())
	position = Vector2.ZERO
	var progress := clampf(float(effect["age"]) / maxf(0.001, float(effect["duration"])), 0.0, 1.0)
	var success: Color = BiomeTheme.COLOR.success
	var leaf: Color = BiomeTheme.COLOR.leaf
	var wave := sin(progress * PI)
	var radius := lerpf(40.0, 69.0, progress)
	draw_arc(position, radius, 0.0, TAU, 42, Color(success.r, success.g, success.b, wave * 0.48), 2.4, true)
	for fleck in range(5):
		var angle := float(fleck) / 5.0 * TAU + float(data.get("ordinal", 1)) * 0.51
		var fleck_position := position + Vector2.from_angle(angle) * lerpf(27.0, 55.0, progress)
		draw_circle(fleck_position, 2.1 * (1.0 - progress), Color(leaf.r, leaf.g, leaf.b, wave * 0.76))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_effects() -> void:
	for entity_id in spawn_effects:
		var spawn: Dictionary = spawn_effects[entity_id]
		var position := _spawn_position(int(entity_id), str(spawn["kind"]))
		if position == Vector2.INF:
			continue
		var progress: float = clampf(float(spawn["age"]) / float(spawn.get("duration", 0.65)), 0.0, 1.0)
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
		if birth:
			var celebration_color := Color(0.85, 0.96, 0.65, (1.0 - progress) * 0.9)
			draw_arc(position, 12.0 + progress * 16.0, 0.0, TAU, 36, celebration_color, 2.0, true)
	for effect in ambient_effects:
		var progress: float = clampf(effect["age"] / effect["duration"], 0.0, 1.0)
		if effect["type"] in ["death", "removal"]:
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
		elif effect["type"] == "plant_state":
			var state: String = effect.get("state", "")
			var base_color := Color("#9c7951") if state == "depleted" else (Color("#a7d65f") if state == "recovering" else Color("#d7e77a"))
			var color := Color(base_color.r, base_color.g, base_color.b, (1.0 - progress) * 0.58)
			var radius := lerpf(8.0, 18.0, progress)
			draw_arc(effect["position"], radius, -2.75, -0.35, 16, color, 2.0, true)
			if state != "depleted":
				for spark in range(3):
					var angle := float(spark) / 3.0 * TAU + progress * 0.7
					draw_circle(effect["position"] + Vector2.from_angle(angle) * radius * 0.62 + Vector2(0.0, -progress * 5.0), 1.5 * (1.0 - progress), color)
	if expansion_flash > 0.0:
		var progress := 1.0 - expansion_flash / 2.2
		var radius := lerpf(display_radius - 35.0, display_radius + 8.0, progress)
		var boundary := _boundary_polygon(radius, 128)
		draw_polyline(boundary, Color(0.9, 1.0, 0.76, sin(progress * PI) * 0.48), 4.0, true)

func _draw_life_event_labels() -> void:
	var occupied: Array[Rect2] = []
	# Keep labels legible as the camera pulls back. Times use real visual seconds,
	# so switching to 3x never shortens the opportunity to read a loss.
	var scale_factor := clampf(1.0 / camera_zoom, 0.8, 2.4)
	for effect in ambient_effects:
		if effect["type"] not in ["birth", "death"]:
			continue
		var position: Vector2 = effect["position"]
		if effect["type"] == "birth":
			var current_position := _spawn_position(int(effect["entity_id"]), str(effect["kind"]))
			if current_position != Vector2.INF:
				position = current_position
		var age := float(effect["age"])
		var duration := float(effect["duration"])
		var alpha := minf(clampf(age / 0.15, 0.0, 1.0), clampf((duration - age) / 1.0, 0.0, 1.0))
		var label_text := str(effect["label"])
		var label_size := ThemeDB.fallback_font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var badge_size := Vector2(label_size.x + 20.0, 25.0)
		var center := position + Vector2(0.0, -39.0 - minf(age, 1.0) * 5.0) * scale_factor
		var label_rect := Rect2(center - badge_size * scale_factor * 0.5, badge_size * scale_factor)
		# Nearby births are common: move each capsule up until all names are readable.
		for attempt in range(MAX_LIFE_EVENT_LABELS):
			var overlaps := false
			for previous in occupied:
				if previous.grow(3.0 * scale_factor).intersects(label_rect):
					overlaps = true
					break
			if not overlaps:
				break
			center.y -= 29.0 * scale_factor
			label_rect.position.y -= 29.0 * scale_factor
		occupied.append(label_rect)
		var accent := Color("#547744") if effect["type"] == "birth" else Color("#8a654f")
		if str(effect.get("cause", "")) == "starvation":
			accent = Color("#ad573d")
		draw_line(position + Vector2(0.0, -12.0) * scale_factor, center + Vector2(0.0, badge_size.y * 0.5) * scale_factor, Color(accent.r, accent.g, accent.b, 0.65 * alpha), 1.2 * scale_factor, true)
		draw_set_transform(center, 0.0, Vector2.ONE * scale_factor)
		_draw_objective_capsule(Vector2(0.8, 1.8), badge_size, Color(0.08, 0.16, 0.13, 0.22 * alpha), Color.TRANSPARENT)
		_draw_objective_capsule(Vector2.ZERO, badge_size, Color(0.98, 0.96, 0.89, 0.97 * alpha), Color(accent.r, accent.g, accent.b, 0.9 * alpha))
		draw_string(ThemeDB.fallback_font, Vector2(-label_size.x * 0.5, 4.5), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(accent.r, accent.g, accent.b, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _spawn_position(entity_id: int, kind: String) -> Vector2:
	if kind == "rabbit" and simulation.rabbits.has(entity_id):
		return simulation.rabbits[entity_id]["position"]
	if kind == "fox" and simulation.foxes.has(entity_id):
		return simulation.foxes[entity_id]["position"]
	if kind in ["carrot_patch", "berry_bush"] and simulation.plants.has(entity_id):
		return simulation.plants[entity_id]["position"]
	return Vector2.INF

func _draw_public_selection() -> void:
	if selected_animal_id == -1 or selected_animal_kind not in ["rabbit", "fox"]:
		return
	var source: Dictionary = simulation.rabbits if selected_animal_kind == "rabbit" else simulation.foxes
	if not source.has(selected_animal_id):
		return
	var animal: Dictionary = source[selected_animal_id]
	var position: Vector2 = animal["previous_position"].lerp(animal["position"], systems.interpolation_alpha())
	var color: Color = BiomeTheme.COLOR.moss if selected_animal_kind == "rabbit" else BiomeTheme.COLOR.accent
	var scale_factor := _zoom_compensation()
	var pulse := 15.5 + sin(visual_clock * 2.8) * 1.1
	draw_circle(position, pulse * scale_factor, Color(color.r, color.g, color.b, 0.10))
	for segment in range(4):
		var start := float(segment) * PI * 0.5 + visual_clock * 0.22
		draw_arc(position, pulse * scale_factor, start, start + 0.82, 8, Color(color.r, color.g, color.b, 0.88), 2.2, true)

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
		draw_circle(position, simulation.config["rabbit"].get("social_proximity_radius", 0.0), Color(0.45, 0.78, 0.96, 0.24), false, 1.0, true)
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
	var color := Color("#ff7664")
	if placement_valid:
		color = {
			"rich": Color("#82d67a"),
			"fair": Color("#ffe27a"),
			"poor": Color("#e7a95c"),
		}.get(placement_quality, Color("#ffe27a"))
	var preview_compensation := _zoom_compensation()
	var radius := (21.0 + sin(visual_clock * 4.5) * 1.5) * preview_compensation
	draw_circle(placement_position, radius, Color(color.r, color.g, color.b, 0.13))
	draw_circle(placement_position, radius + 1.5, Color(0.06, 0.16, 0.11, 0.58), false, 3.8, true)
	for segment in range(8):
		var start := float(segment) / 8.0 * TAU + visual_clock * 0.18
		draw_arc(placement_position, radius, start, start + 0.48, 5, Color(color.r, color.g, color.b, 0.83), 2.0, true)
	if not placement_valid:
		draw_line(placement_position + Vector2(-7.0, -7.0) * preview_compensation, placement_position + Vector2(7.0, 7.0) * preview_compensation, Color(color.r, color.g, color.b, 0.85), 2.0, true)
		draw_line(placement_position + Vector2(7.0, -7.0) * preview_compensation, placement_position + Vector2(-7.0, 7.0) * preview_compensation, Color(color.r, color.g, color.b, 0.85), 2.0, true)
	var item_scale := ANIMAL_VISUAL_SCALE if placement_item in ["rabbit", "fox"] else PLANT_VISUAL_SCALE
	draw_set_transform(placement_position, 0.0, Vector2.ONE * item_scale * preview_compensation)
	match placement_item:
		"rabbit":
			_draw_rabbit({"id": 0, "velocity": Vector2.RIGHT, "behavior": "preview", "hunger": 0.0})
		"fox":
			_draw_fox({"id": 0, "velocity": Vector2.RIGHT, "behavior": "preview", "hunger": 0.0})
		"carrot_patch":
			_draw_carrot_patch(1.0, "abundant", 0, _habitat_quality_at("carrot_patch", placement_position))
		"berry_bush":
			_draw_berry_bush(1.0, "abundant", 0, _habitat_quality_at("berry_bush", placement_position))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
