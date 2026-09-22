extends SceneTree
const Config = preload("res://config/game_config.gd")
const Simulation = preload("/private/tmp/biome-audit-20260917/profiled_sim.gd")
func _initialize() -> void:
	trial(50,false)
	quit()
func valid_near(sim,p: Vector2) -> Vector2:
	if sim.is_position_valid(p):return p
	for i in range(1,30):
		for j in range(16):
			var q=p+Vector2.from_angle(float(j)/16*TAU)*i*8
			if sim.is_position_valid(q):return q
	return Vector2.ZERO
func trial(n: int, dense: bool) -> void:
	var cfg=Config.make()
	# Population-load experiment, not an ecological outcome experiment.
	cfg.rabbit.reproduction_food_needed=999999
	cfg.fox.reproduction_food_needed=999999
	var sim=Simulation.new(cfg)
	sim.world_radius=940
	var nr=n
	var nf=int(n/5)
	var np=maxi(40,int(n*.6))
	var spread=70.0 if dense else 640.0
	for i in range(np):
		sim.add_plant("carrot_patch" if i%2==0 else "berry_bush",valid_near(sim,Vector2.from_angle(i*2.399963)*sqrt(float(i+1)/np)*spread))
	for i in range(nr):
		sim.add_rabbit(valid_near(sim,Vector2.from_angle(i*2.399963+.3)*sqrt(float(i+1)/nr)*spread))
	for i in range(nf):
		sim.add_fox(valid_near(sim,Vector2.from_angle(i*2.399963+.6)*sqrt(float(i+1)/nf)*spread))
	for i in range(10):sim.step(.1)
	sim.audit_times = {}
	var times: Array[float]=[]
	var queries: Array[int]=[]
	for i in range(150):
		var start=Time.get_ticks_usec()
		sim.step(.1)
		times.append((Time.get_ticks_usec()-start)/1000.0)
		queries.append(sim.last_tick_stats.queries)
	var total=0.0
	for t in times:total+=t
	times.sort()
	queries.sort()
	var result={"rabbits_start":nr,"foxes_start":nf,"plants":np,"dense":dense,"rabbits_end":sim.rabbits.size(),"foxes_end":sim.foxes.size(),"mean_ms":total/times.size(),"p50_ms":times[75],"p95_ms":times[142],"max_ms":times[-1],"queries_p50":queries[75]}
	result["profile_usec"] = sim.audit_times
	print("PROFILE "+JSON.stringify(result))
