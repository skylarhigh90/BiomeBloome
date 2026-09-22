extends "res://tests/lifecycle_playtest_runner.gd"

## Render the naturally blocked opening and a real inventory response to its hint.
## No animal state, food amounts, or simulation rules are adjusted.
var viewport: SubViewport
var world: WorldView
var hud: GameHUD
var systems: GameSystems
var output := "res://docs/playtests/2026-09-22/lifecycle-visuals"
var newborn_id := -1
var first_birth_time := -1.0
var capture_bounds: Dictionary = {}

func _initialize() -> void:
	_run_visual_opening.call_deferred()

func _run_visual_opening() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 800)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := Node2D.new()
	viewport.add_child(scene)
	var cfg := GameConfig.make()
	cfg["simulation"]["seed"] = 240821
	systems = GameSystems.new(cfg)
	world = WorldView.new()
	scene.add_child(world)
	world.setup(systems)
	var camera := Camera2D.new()
	camera.position = Vector2(0, 40)
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * 1.45
	camera.enabled = true
	scene.add_child(camera)
	world.set_camera_zoom(1.45)
	hud = GameHUD.new()
	scene.add_child(hud)
	hud.setup(systems)
	var mirror := TextureRect.new()
	mirror.texture = viewport.get_texture()
	mirror.size = Vector2(1280, 800)
	root.add_child(mirror)
	systems.simulation.entity_added.connect(func(kind: String, id: int, reason: String) -> void:
		if kind == "rabbit" and reason == "birth" and newborn_id < 0:
			newborn_id = id
			first_birth_time = snappedf(systems.simulation.simulation_time, 0.1)
	)
	var anchor := _find_opening_anchor(systems)
	for offset in [Vector2(-45, -35), Vector2(0, -45), Vector2(45, -35), Vector2(-30, 25), Vector2(30, 25)]:
		_check(systems.place_item("carrot_patch", anchor + offset) >= 0, "Natural screenshot places each starting carrot through inventory")
	var founders: Array[int] = []
	for offset in [Vector2(-22, -4), Vector2(22, -4), Vector2(-22, 13), Vector2(22, 13)]:
		var id := systems.place_item("rabbit", anchor + offset)
		_check(id >= 0, "Natural screenshot places each starting rabbit through inventory")
		founders.append(id)
	for tick in range(300):
		_step_visual()
	var founder_id := founders[0]
	var status := systems.simulation.rabbit_birth_status(founder_id)
	_check(systems.simulation.population("rabbit") == 4 and str(status["code"]) == "local_capacity", "At30s the unmodified seed naturally shows four rabbits blocked by forage capacity")
	hud.show_animal("rabbit", founder_id)
	world.set_public_selection("rabbit", founder_id)
	await _capture_opening("08-natural-opening-blocked")
	var action := _follow_forage_hint(systems, founder_id)
	_check(str(action.get("item", "")) == "berry_bush" and int(action.get("inventory_before", 0)) == 2 and int(action.get("inventory_after", 0)) == 1, "The hint response spends exactly one earned berry bush")
	for tick in range(10):
		_step_visual()
	_check(newborn_id >= 0 and is_equal_approx(first_birth_time, 30.9), "The natural birth follows at30.9s")
	hud.show_animal("rabbit", newborn_id)
	world.set_public_selection("rabbit", newborn_id)
	await _capture_opening("09-natural-opening-after-hint")
	var report := {
		"method": "Actual GameHUD and WorldView on default GameSystems seed240821; ordinary initial inventory placements. At30s, place one earned berry bush using the same helper as the hint-response telemetry.",
		"before_time": 30.0,
		"before_status": status,
		"action": action,
		"after_time": snappedf(systems.simulation.simulation_time, 0.1),
		"first_birth_time": first_birth_time,
		"newborn_snapshot": systems.simulation.animal_snapshot("rabbit", newborn_id),
		"ui_bounds": capture_bounds,
		"failures": failures,
	}
	FileAccess.open(output + "/natural-opening.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	for failure in failures:
		printerr("FAILED: " + failure)
	print("Natural opening visuals captured at30s and31s; first birth%.1fs; %dfailures." % [first_birth_time, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _step_visual() -> void:
	systems.advance(0.1)
	world.process_visual(0.1)
	hud.process_visual(0.1)

func _capture_opening(label: String) -> void:
	hud.refresh()
	world.queue_redraw()
	await process_frame
	# Accelerated simulation can cross a checkpoint in the same rendered frame.
	# Let the actual objective-card entrance tween settle before photographing it.
	await create_timer(0.7).timeout
	hud.refresh()
	await process_frame
	hud.refresh()
	await process_frame
	RenderingServer.force_draw(false, 1.0 / 60.0)
	viewport.get_texture().get_image().save_png(output + "/" + label + ".png")
	var objective := hud.objective_panel.get_global_rect()
	var population := hud.population_panel.get_global_rect()
	var inventory_hint := hud.placement_hint.get_global_rect()
	var inspector := hud.animal_panel.get_global_rect()
	capture_bounds[label] = {"objective": objective, "population": population, "inventory_hint": inventory_hint, "inspector": inspector}
	_check(objective.position.y >= 0.0 and objective.end.y < inventory_hint.position.y, label + ": objective fits above inventory")
	_check(not objective.intersects(population) and not objective.intersects(inspector), label + ": objective clears other HUD panels")
	_check(inspector.end.y < inventory_hint.position.y, label + ": animal inspector clears inventory")
