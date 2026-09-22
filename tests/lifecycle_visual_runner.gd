extends SceneTree

# Controlled visual fixtures using the real main scene. Natural default-rule
# opening runs are recorded separately by lifecycle_playtest_runner.gd.
var game
var view: SubViewport
var output := "res://docs/playtests/2026-09-22/lifecycle-visuals"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	view = SubViewport.new()
	view.size = Vector2i(1280, 800)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game = load("res://game/main.tscn").instantiate()
	view.add_child(game)
	game.set_process(false)
	var preview := TextureRect.new()
	preview.texture = view.get_texture()
	preview.size = Vector2(1280, 800)
	root.add_child(preview)
	var systems: GameSystems = game.systems
	var sim: EcosystemSimulation = systems.simulation
	game.camera.position_smoothing_enabled = false
	game.camera.position = Vector2.ZERO
	game.camera.zoom = Vector2.ONE * 1.45
	game.world_view.set_camera_zoom(1.45)
	var ids: Array[int] = []
	for point in [Vector2(-70.0, 10.0), Vector2(-35.0, -5.0), Vector2(10.0, -35.0), Vector2(45.0, 10.0)]:
		var id := sim.add_rabbit(point)
		ids.append(id)
		sim.rabbits[id]["recent_food"] = 30.0
		sim.rabbits[id]["reproduction_cooldown"] = 0.0
		sim.rabbits[id]["hunger"] = 8.0
	sim.add_plant("carrot_patch", Vector2(-10.0, 25.0))
	sim.rebuild_spatial_index()
	game.world_view.process_visual(1.0)
	await _capture("01-birth-blocker")
	for point in [Vector2(-100.0, -45.0), Vector2(-35.0, 65.0), Vector2(45.0, 50.0), Vector2(85.0, -35.0)]:
		sim.add_plant("berry_bush", point)
	sim.rebuild_spatial_index()
	sim._process_rabbit_reproduction()
	game.world_view.process_visual(0.35)
	await _capture("02-newborn")
	game.world_view.process_visual(7.0)
	var elder: Dictionary = sim.rabbits[ids[0]]
	elder["age"] = float(elder["lifespan"]) * 0.80
	systems._update_life_warnings()
	game.hud.show_animal("rabbit", ids[0])
	game.world_view.set_public_selection("rabbit", ids[0])
	await _capture("03-elder-warning")
	elder["age"] = float(elder["lifespan"]) - 0.05
	systems.advance(0.1)
	game.world_view.process_visual(0.35)
	await _capture("04-named-death")
	game.hud.hide_animal()
	await _capture("05-persistent-loss")
	game.hud._open_life_journal()
	await _capture("06-life-journal")
	game.hud.journal_open = false
	view.size = Vector2i(1024, 768)
	game.hud._layout_interface()
	await _capture("07-compact-overview")
	var panels_fit: bool = game.hud.story_panel.position.y + game.hud.story_panel.size.y < game.hud.inventory_panel.position.y - 54.0
	view.size = Vector2i(800, 768)
	game.hud._layout_interface()
	await _capture("08-narrow-overview")
	panels_fit = panels_fit and not game.hud.speed_panel.get_rect().intersects(game.hud.story_panel.get_rect())
	panels_fit = panels_fit and game.hud.story_panel.get_rect().end.y < game.hud.inventory_panel.position.y - 54.0
	systems.run_director.milestone_index = 1
	await _capture("09-narrow-family")
	game.hud._layout_interface()
	await _capture("09-narrow-family")
	panels_fit = panels_fit and game.hud.population_panel.get_rect().end.y < game.hud.placement_hint.position.y
	print("Lifecycle visual fixtures captured. Compact overview clears inventory: %s" % panels_fit)
	quit(0 if panels_fit else 1)

func _capture(label: String) -> void:
	game.hud.refresh()
	game.world_view.queue_redraw()
	await process_frame
	await create_timer(0.2).timeout
	game.hud.refresh()
	await process_frame
	game.hud.refresh()
	await process_frame
	RenderingServer.force_draw(false, 1.0 / 60.0)
	view.get_texture().get_image().save_png(output + "/" + label + ".png")
