extends SceneTree

## Manual narrow-viewport checkpoint capture. Run with:
##   godot --path . --resolution 376x900 --script tests/checkpoint_visual_runner.gd -- 5 /tmp/checkpoint-5.png living_cycle

var game
var frames := 0
var checkpoint_number := 5
var output_path := "/private/tmp/biome-checkpoint.png"
var explained_goal_id := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		checkpoint_number = clampi(int(args[0]), 1, 5)
	if args.size() > 1:
		output_path = str(args[1])
	if args.size() > 2:
		explained_goal_id = str(args[2])
	root.content_scale_size = Vector2i(376, 900)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		_prepare_checkpoint()
	if frames == 8:
		game.hud._fit_objective_panel_to_content()
	if frames == 16:
		var image := root.get_texture().get_image()
		var error := image.save_png(output_path)
		if error != OK:
			printerr("Checkpoint visual capture failed: %s" % error_string(error))
			quit(1)
			return false
		print("Checkpoint %d visual capture saved: %s" % [checkpoint_number, output_path])
		quit(0)
	return false

func _prepare_checkpoint() -> void:
	game.systems.set_speed(0.0)
	game.systems.supply_time_remaining = 9999.0
	game.systems.run_director.milestone_index = checkpoint_number - 1
	game.systems.run_director._reset_milestone_evidence()
	var milestone: Dictionary = game.systems.run_director.current_milestone()
	var rabbit_count := maxi(22, int(milestone.get("rabbit_min", 0)))
	for index in range(rabbit_count):
		game.systems.simulation.add_rabbit(Vector2(float(index % 6) * 18.0 - 45.0, float(index / 6) * 18.0 - 25.0), "visual_test")
	for index in range(int(milestone.get("fox_min", 0))):
		game.systems.simulation.add_fox(Vector2(120.0 + float(index) * 35.0, 0.0), "visual_test")
	game.hud.refresh()
	if not explained_goal_id.is_empty() and game.hud.objective_progress_view.goal_rows.has(explained_goal_id):
		game.hud.objective_progress_view.goal_rows[explained_goal_id]["help_button"].pressed.emit()
	for control in [game.hud.population_panel, game.hud.supply_panel, game.hud.inventory_panel, game.hud.speed_panel, game.hud.restart_button]:
		control.visible = false
	game.world_view.queue_redraw()
