extends "res://tests/playtest_runner.gd"
var game
var frame := 0
var wall := 0.0
var last_action := -1.0
var last_capture := -1.0
var last_sample := -1.0
var last_status := -1.0
var watched := -1
var capture_index := 0
var telemetry
var directory := "/private/tmp/biome-audit-20260917/live"
func _initialize() -> void:
	telemetry = FileAccess.open(directory + "/telemetry.jsonl", FileAccess.WRITE)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
func _process(delta: float) -> bool:
	frame += 1
	wall += delta
	if frame < 3: return false
	var s = game.systems
	var sim = s.simulation
	var t = sim.simulation_time
	if wall - last_action >= 1.0:
		if s.supply_pending: s.choose_supply(_choose_supply(s, "reactive"))
		_place_inventory(s, "reactive")
		last_action = wall
		if watched < 0 and not sim.rabbits.is_empty():
			watched = sim.rabbits.keys()[0]
			game.world_view.set_public_selection("rabbit", watched)
			game.hud.show_animal("rabbit", watched)
	if t < 120 and sim.rabbits.has(watched):
		game.camera.position = sim.rabbits[watched]["position"]
		game.camera_zoom_target = 1.9
	elif t < 240:
		game.camera.position = Vector2.ZERO
		game.camera_zoom_target = 1.0
	else:
		game.camera.position = Vector2.ZERO
		game.camera_zoom_target = 0.70
	if t - last_sample >= 0.099:
		var a = []
		for kind in ["rabbit", "fox"]:
			var source = sim.rabbits if kind == "rabbit" else sim.foxes
			for e in source.values():
				var p: Vector2 = e["position"]
				var v: Vector2 = e["velocity"]
				a.append({"id":e["id"],"kind":kind,"x":p.x,"y":p.y,"vx":v.x,"vy":v.y,"behavior":e["behavior"],"target":e["target_id"],"hunger":e["hunger"],"facing":e.get("facing",null)})
		telemetry.store_line(JSON.stringify({"t":t,"wall":wall,"watched":watched,"act":s.run_director.current_milestone_id(),"animals":a}))
		last_sample = t
	if wall - last_capture >= 0.2:
		root.get_texture().get_image().save_png(directory + "/frame_%06d.png" % capture_index)
		capture_index += 1
		last_capture = wall
	if wall - last_status >= 20.0:
		print("LIVE wall=%.1f sim=%.1f act=%s rabbits=%d foxes=%d plants=%d watched=%d" % [wall,t,s.run_director.current_milestone_id(),sim.rabbits.size(),sim.foxes.size(),sim.plants.size(),watched])
		telemetry.flush()
		last_status = wall
	if s.is_completed(): s.continue_observing()
	if wall >= 360.0 or s.is_game_over():
		telemetry.close()
		quit()
	return false
