extends SceneTree
const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")
func _initialize() -> void:
	for seed_value in [240817,401]: run_probe(seed_value)
	quit()
func run_probe(seed_value: int) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("/private/tmp/biome-audit-20260917/B_%d.json"%seed_value))
	var cfg = Config.make()
	cfg.simulation.seed=seed_value
	var sim = Simulation.new(cfg,seed_value)
	sim.world_radius=600
	for p in data.layout.plants:sim.add_plant(p.type,Vector2(p.x,p.y))
	for p in data.layout.rabbits:sim.add_rabbit(Vector2(p.x,p.y))
	for p in data.layout.foxes:sim.add_fox(Vector2(p.x,p.y))
	var counts={"fox_seconds":0.0,"ready_fox_seconds":0.0,"ready_with_other_ready_seconds":0.0,"ready_pair_near_seconds":0.0,"prey_gate_pass_pair_seconds":0.0,"hunting_fox_seconds":0.0,"wander_fox_seconds":0.0,"ready_hunger_failed_seconds":0.0}
	for tick in range(9000):
		sim.step(.1)
		var ready=[]
		for f in sim.foxes.values():
			counts.fox_seconds+=.1
			counts.hunting_fox_seconds+=.1 if f.behavior=="hunt" else 0
			counts.wander_fox_seconds+=.1 if f.behavior!="hunt" else 0
			if sim._fox_is_eligible(f):ready.append(f)
		counts.ready_fox_seconds+=ready.size()*.1
		if ready.size()>1:counts.ready_with_other_ready_seconds+=ready.size()*.1
		for i in range(ready.size()):
			for j in range(i+1,ready.size()):
				var a=ready[i]
				var b=ready[j]
				if sim.ground_route_distance(a.position,b.position,105)>105:continue
				counts.ready_pair_near_seconds+=.1
				var mid=(a.position+b.position)*.5
				var prey=sim._local_reachable_count("rabbit",mid,380)
				var foxes=sim._local_reachable_count("fox",mid,380)
				if prey >= (foxes+1)*6:counts.prey_gate_pass_pair_seconds+=.1
	print(JSON.stringify({"seed":seed_value,"counts":counts}))
