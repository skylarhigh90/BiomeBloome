extends SceneTree
var audit_viewport
var game
var frame := 0
var captures := 0
var last_capture := -1.0
var last_status := -1.0
var last_sample := -1.0
var watched := -1
var directory := "/private/tmp/biome-audit-20260917/predator_verified_forced"
var telemetry
var capture_log
func _initialize() -> void:
	audit_viewport = SubViewport.new()
	audit_viewport.size = Vector2i(1280,800)
	audit_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(audit_viewport)
	game = load("res://game/main.tscn").instantiate()
	audit_viewport.add_child(game)
	var preview = TextureRect.new()
	preview.texture = audit_viewport.get_texture()
	preview.size = Vector2(1280,800)
	root.add_child(preview)
	telemetry = FileAccess.open(directory + "/telemetry.jsonl",FileAccess.WRITE)
	capture_log = FileAccess.open(directory + "/captures.csv",FileAccess.WRITE)
	capture_log.store_line("frame,simulation_time")
func ground(sim,p: Vector2) -> Vector2:
	if sim.is_position_valid(p): return p
	for i in range(1,30):
		for j in range(24):
			var q = p + Vector2.from_angle(float(j)/24.0*TAU)*i*8.0
			if sim.is_position_valid(q): return q
	return Vector2.ZERO
func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3: return false
	var s = game.systems
	var sim = s.simulation
	if frame == 3:
		s.run_director.run_state = "sandbox"
		s.supply_time_remaining = 999999.0
		sim.world_radius = 600.0
		game.world_view.display_radius = 600.0
		var centers = [Vector2(-200,-140),Vector2(220,-100),Vector2(0,200)]
		for i in range(18):
			sim.add_plant("berry_bush" if i%3==2 else "carrot_patch",ground(sim,centers[i%3]+Vector2.from_angle(i*2.399963)*(28+float(i/3)*9)))
		for i in range(24):
			sim.add_rabbit(ground(sim,centers[i%3]+Vector2.from_angle(i*2.399963)*(12+float(i%4)*8)))
		for i in range(2):
			var id = sim.add_fox(ground(sim,centers[i]+Vector2(-100,0)))
			if watched == -1: watched = id
		game.world_view.set_public_selection("fox",watched)
		game.hud.show_animal("fox",watched)
	# Hold 1x to inspect gait; changing speed is not part of this experiment.
	s.set_speed(1.0)
	var t = sim.simulation_time
	if t < 90 and sim.foxes.has(watched):
		game.camera.position = sim.foxes[watched].position
		game.camera_zoom_target = 1.4
	else:
		game.hud.hide_animal()
		game.camera.position = Vector2.ZERO
		game.camera_zoom_target = 0.75
	if t-last_sample >= 0.099:
		var entities = []
		for kind in ["rabbit","fox"]:
			var source = sim.rabbits if kind=="rabbit" else sim.foxes
			for e in source.values():
				entities.append({"id":e.id,"kind":kind,"x":e.position.x,"y":e.position.y,"vx":e.velocity.x,"vy":e.velocity.y,"behavior":e.behavior,"target":e.target_id,"hunger":e.hunger,"failed":e.get("failed_pursuits",0),"hunt_time":e.get("hunt_time",0),"stamina":e.get("sprint_stamina",e.get("flee_stamina",0)),"cover":sim.terrain.thicket_cover(e.position),"meals":e.meals})
		telemetry.store_line(JSON.stringify({"t":t,"watched":watched,"animals":entities}))
		last_sample=t
	if t-last_capture>=0.099:
		RenderingServer.force_draw(false, 1.0 / 60.0)
		audit_viewport.get_texture().get_image().save_png(directory+"/frame_%06d.png"%captures)
		capture_log.store_line("%d,%.3f"%[captures,t])
		captures+=1
		last_capture=t
	if t-last_status>=20:
		print("PREDATOR t=%.1f r=%d f=%d"%[t,sim.rabbits.size(),sim.foxes.size()])
		telemetry.flush()
		capture_log.flush()
		last_status=t
	if t>=180:
		telemetry.close()
		capture_log.close()
		quit()
	return false
