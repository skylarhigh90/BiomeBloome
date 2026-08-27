extends Node2D

var config: Dictionary
var systems: GameSystems
var world_view: WorldView
var camera: Camera2D
var hud: GameHUD
var camera_zoom_target := 1.0
var camera_manual_cooldown := 0.0
var dragging_camera := false
var debug_enabled := false
var debug_selected_kind := ""
var debug_selected_id := -1

func _ready() -> void:
	config = GameConfig.make()
	systems = GameSystems.new(config)
	world_view = WorldView.new()
	world_view.name = "WorldView"
	add_child(world_view)
	world_view.setup(systems)

	camera = Camera2D.new()
	camera.name = "WorldCamera"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.5
	camera.enabled = true
	add_child(camera)
	camera_zoom_target = _fit_zoom_for_radius(systems.simulation.world_radius)
	camera.zoom = Vector2.ONE * camera_zoom_target

	hud = GameHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(systems)
	hud.inventory_selected.connect(_on_inventory_selected)
	hud.speed_selected.connect(_on_speed_selected)
	hud.supply_selected.connect(_on_supply_selected)
	hud.restart_requested.connect(_on_restart_requested)
	systems.world_expanded.connect(_on_world_expanded)

	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_placement_preview()

func _process(delta: float) -> void:
	systems.advance(delta)
	world_view.process_visual(delta)
	hud.process_visual(delta)
	camera_manual_cooldown = maxf(0.0, camera_manual_cooldown - delta)
	_update_camera(delta)
	_update_placement_preview()
	if debug_enabled:
		_update_debug_panel()

func _update_camera(delta: float) -> void:
	var input_direction := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	if input_direction.length_squared() > 0.0:
		camera.position += input_direction * 330.0 / camera.zoom.x * delta
		camera_manual_cooldown = 4.0
	var zoom_value := lerpf(camera.zoom.x, camera_zoom_target, 1.0 - exp(-delta * 4.2))
	camera.zoom = Vector2.ONE * zoom_value
	var pan_limit := maxf(0.0, systems.simulation.world_radius - 120.0 / camera.zoom.x)
	if camera.position.length() > pan_limit:
		camera.position = camera.position.normalized() * pan_limit

func _fit_zoom_for_radius(radius: float) -> float:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = Vector2(1280.0, 800.0)
	var reserved_vertical := 150.0
	var available := Vector2(viewport_size.x - 90.0, viewport_size.y - reserved_vertical)
	var diameter := radius * 2.0 + 70.0
	return clampf(minf(available.x / diameter, available.y / diameter), 0.42, 1.45)

func _on_world_expanded(new_radius: float) -> void:
	# Expansions always get a gentle accommodation; later manual zoom remains possible.
	camera_zoom_target = minf(camera_zoom_target, _fit_zoom_for_radius(new_radius))

func _on_viewport_size_changed() -> void:
	if camera_manual_cooldown <= 0.0:
		camera_zoom_target = _fit_zoom_for_radius(systems.simulation.world_radius)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_toggle_debug()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			systems.clear_selection()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SPACE:
			systems.set_speed(1.0 if systems.is_paused() else 0.0)
			hud.refresh()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			dragging_camera = event.pressed
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			camera_zoom_target = clampf(camera_zoom_target * factor, 0.42, 1.8)
			camera_manual_cooldown = 7.0
			get_viewport().set_input_as_handled()
			return
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var world_position := get_global_mouse_position()
			if not systems.selected_item.is_empty():
				var placed_id := systems.place_item(systems.selected_item, world_position)
				if placed_id != -1:
					hud.refresh()
				_update_placement_preview()
				get_viewport().set_input_as_handled()
			elif debug_enabled:
				_select_debug_entity(world_position)
				get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and dragging_camera:
		camera.position -= event.relative / camera.zoom.x
		camera_manual_cooldown = 7.0
		get_viewport().set_input_as_handled()

func _on_inventory_selected(item: String) -> void:
	if systems.selected_item == item:
		systems.clear_selection()
	else:
		systems.select_item(item)
	_update_placement_preview()

func _on_speed_selected(speed: float) -> void:
	systems.set_speed(speed)
	hud.refresh()

func _on_supply_selected(index: int) -> void:
	systems.choose_supply(index)
	hud.refresh()

func _on_restart_requested() -> void:
	get_tree().reload_current_scene()

func _update_placement_preview() -> void:
	if systems == null or world_view == null:
		return
	var item := systems.selected_item
	var position := get_global_mouse_position()
	world_view.set_placement_preview(item, position, systems.can_place(item, position), not item.is_empty())

func _toggle_debug() -> void:
	debug_enabled = not debug_enabled
	world_view.debug_enabled = debug_enabled
	hud.set_debug_visible(debug_enabled)
	if not debug_enabled:
		debug_selected_kind = ""
		debug_selected_id = -1
		world_view.set_debug_selection("", -1)

func _select_debug_entity(position: Vector2) -> void:
	var nearest_kind := ""
	var nearest_id := -1
	var nearest_distance := 28.0 * 28.0 / (camera.zoom.x * camera.zoom.x)
	for kind in ["rabbit", "fox"]:
		var source: Dictionary = systems.simulation.rabbits if kind == "rabbit" else systems.simulation.foxes
		for entity in source.values():
			var distance: float = position.distance_squared_to(entity["position"])
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_kind = kind
				nearest_id = entity["id"]
	debug_selected_kind = nearest_kind
	debug_selected_id = nearest_id
	world_view.set_debug_selection(nearest_kind, nearest_id)

func _update_debug_panel() -> void:
	var sim := systems.simulation
	var lines: Array[String] = [
		"DEBUG · F3 to close · click an animal",
		"Fixed tick: %.1f Hz   Speed: %.0f×" % [1.0 / config["simulation"]["fixed_step"], systems.simulation_speed],
		"Rabbits: %d   Foxes: %d   Plants: %d" % [sim.rabbits.size(), sim.foxes.size(), sim.plants.size()],
		"Seed: %d   Sim time: %.1fs" % [config["simulation"]["seed"], sim.simulation_time],
	]
	if debug_selected_id != -1:
		var data := sim.debug_entity(debug_selected_kind, debug_selected_id)
		if data.is_empty():
			debug_selected_id = -1
			world_view.set_debug_selection("", -1)
		else:
			lines.append("%s #%d · %s" % [debug_selected_kind.capitalize(), data["id"], data["behavior"]])
			lines.append("Hunger %.1f · Age %.1f · Cooldown %.1f" % [data["hunger"], data["age"], data["reproduction_cooldown"]])
			lines.append("Target %s · Nearby %s" % [str(data["target_id"]), str(data["nearby"])])
	hud.update_debug("\n".join(lines))
