extends SceneTree

# Matched compact-colony observation, with normal mortality/reproduction and no
# intervention. Optional arguments: output.json, seed. Measurements use actual
# displacement, so changing a velocity label cannot make this test pass.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[1]) if args.size() > 1 else 240817
	var sim := EcosystemSimulation.new(GameConfig.make(), seed_value)
	for index in range(9):
		var p := Vector2.from_angle(float(index) * TAU / 9.0) * 60.0
		sim.add_plant("berry_bush" if index % 3 == 0 else "carrot_patch", p)
	for index in range(7):
		sim.add_rabbit(Vector2.from_angle(float(index) * 2.399) * 30.0)
	var speeds := {"eat": [], "loaf": [], "socialize": []}
	var bouts: Array[float] = []
	var eating: Dictionary = {}
	var overlaps := 0
	var samples := 0
	var births := [0]
	var starvation := [0]
	sim.entity_added.connect(func(kind, _id, reason):
		if kind == "rabbit" and reason == "birth": births[0] += 1
	)
	sim.entity_removed.connect(func(kind, _id, _p, cause):
		if kind == "rabbit" and cause == "starvation": starvation[0] += 1
	)
	for tick in range(1200):
		sim.step(0.1)
		for rabbit in sim.rabbits.values():
			var state: String = rabbit["behavior"]
			var id: int = rabbit["id"]
			var speed: float = Vector2(rabbit["position"]).distance_to(rabbit["previous_position"]) / 0.1
			if speeds.has(state): speeds[state].append(speed)
			if state == "eat":
				eating[id] = float(eating.get(id, 0.0)) + 0.1
			elif eating.has(id):
				bouts.append(eating[id])
				eating.erase(id)
			if tick % 5 != 0: continue
			samples += 1
			for other in sim.rabbits.values():
				if other["id"] != id and Vector2(rabbit["position"]).distance_to(other["position"]) < 18.0:
					overlaps += 1
					break
	var result := {"seed": seed_value, "duration": 120.0, "rabbits": sim.rabbits.size(), "births": births[0], "starvation": starvation[0], "overlap_sample_fraction": float(overlaps) / maxi(1, samples), "median_eating_bout": _median(bouts), "states": {}}
	for state in speeds:
		var stationary := 0
		for speed in speeds[state]:
			if speed < 1.0: stationary += 1
		result["states"][state] = {"samples": speeds[state].size(), "median_speed": _median(speeds[state]), "stationary_fraction": float(stationary) / maxi(1, speeds[state].size())}
	print(JSON.stringify(result))
	if not args.is_empty(): FileAccess.open(args[0], FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	quit()

func _median(values: Array) -> float:
	if values.is_empty(): return 0.0
	values.sort()
	return float(values[values.size() / 2])
