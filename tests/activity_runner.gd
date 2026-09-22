extends SceneTree

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_test_feeding_and_interrupt()
	_test_rest_and_spacing()
	_test_clock_and_replay()
	_test_transplanted_feeding_site()
	_test_nursery_guidance()
	print("%d activity tests passed; %d failed." % [passed, failures.size()])
	for failure in failures: printerr("FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)

func _flat_config() -> Dictionary:
	var cfg := GameConfig.make()
	cfg["world"]["forest_patch_count"] = 0
	cfg["terrain"]["thicket"]["patch_count"] = 0
	cfg["terrain"]["stream"]["enabled"] = false
	return cfg

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: " + label)
	else: failures.append(label)

func _test_feeding_and_interrupt() -> void:
	var sim := EcosystemSimulation.new(_flat_config())
	var plant := sim.add_plant("berry_bush", Vector2.ZERO)
	var id := sim.add_rabbit(Vector2.ZERO)
	var rabbit: Dictionary = sim.rabbits[id]
	rabbit["hunger"] = 35.0
	var position: Vector2 = rabbit["position"]
	for tick in range(15): sim.step(0.1)
	_check(rabbit["behavior"] == "eat" and Vector2(rabbit["position"]).is_equal_approx(position), "a sustained feeding bout has no physical drift")
	_check(rabbit["meals"] == 1 and float(rabbit["hunger"]) < 25.0 and float(sim.plants[plant]["food"]) < float(sim.plants[plant]["max_food"]), "one feeding visit counts once and spends real biomass")
	var fox := sim.add_fox(Vector2(60.0, 0.0))
	sim.foxes[fox]["hunger"] = 0.0
	sim.step(0.1)
	_check(rabbit["behavior"] == "flee" and not Vector2(rabbit["position"]).is_equal_approx(position), "danger interrupts feeding on the next simulation step")
	_check(sim.animal_snapshot("rabbit", id)["activity"] == "Fleeing to safety", "field notes describe the active action")

func _test_rest_and_spacing() -> void:
	var sim := EcosystemSimulation.new(_flat_config())
	sim.add_plant("berry_bush", Vector2.ZERO)
	var first := sim.add_rabbit(Vector2.ZERO)
	sim.rabbits[first]["hunger"] = 0.0
	var resting_ticks := 0
	for tick in range(30):
		sim.step(0.1)
		var rabbit: Dictionary = sim.rabbits[first]
		if rabbit["behavior"] in ["loaf", "socialize", "observe"] and Vector2(rabbit["position"]).is_equal_approx(rabbit["previous_position"]): resting_ticks += 1
	_check(resting_ticks >= 25, "safe home time includes sustained stationary rest")
	var second := sim.add_rabbit(sim.rabbits[first]["position"])
	sim.rabbits[second]["hunger"] = 0.0
	for tick in range(40): sim.step(0.1)
	_check(Vector2(sim.rabbits[first]["position"]).distance_to(sim.rabbits[second]["position"]) >= 18.0, "co-located resting rabbits separate their silhouettes")

func _test_clock_and_replay() -> void:
	var one := GameSystems.new(_flat_config())
	var three := GameSystems.new(_flat_config())
	for system in [one, three]:
		system.supply_time_remaining = 9999.0
		system.simulation.add_rabbit(Vector2.ZERO)
	one.set_speed(1.0)
	three.set_speed(3.0)
	for tick in range(30):
		one.advance(0.1)
		three.advance(0.1 / 3.0)
	var a: Dictionary = one.simulation.rabbits[1]
	var b: Dictionary = three.simulation.rabbits[1]
	_check(Vector2(a["position"]).is_equal_approx(b["position"]) and is_equal_approx(float(a["gait_phase"]), float(b["gait_phase"])), "1x and 3x agree on travel and gait at equal simulation time")
	_check(float(a["gait_phase"]) > 0.0, "travel advances the fixed-step gait")
	var phase: float = a["gait_phase"]
	var facing: float = a["facing"]
	one.set_speed(0.0)
	one.advance(2.0)
	_check(a["gait_phase"] == phase and a["facing"] == facing, "pause freezes gait and facing")

func _test_transplanted_feeding_site() -> void:
	var sim := EcosystemSimulation.new(_flat_config())
	var plant := sim.add_plant("berry_bush", Vector2.ZERO)
	var id := sim.add_rabbit(Vector2.ZERO)
	sim.rabbits[id]["hunger"] = 50.0
	sim.step(0.1)
	sim.transplant_plant(plant, Vector2(100.0, 0.0))
	sim.step(0.1)
	_check(sim.rabbits[id]["behavior"] == "seek_food" and Vector2(sim.rabbits[id]["feeding_position"]).x > 70.0, "transplant invalidates an old feeding site before another bite")

func _test_nursery_guidance() -> void:
	var systems := GameSystems.new(_flat_config())
	systems.simulation.add_plant("carrot_patch", Vector2.ZERO)
	var lonely := systems.placement_assessment("rabbit", Vector2.ZERO)
	systems.simulation.add_rabbit(Vector2(20.0, 0.0))
	var paired := systems.placement_assessment("rabbit", Vector2.ZERO)
	_check(int(lonely["nearby_rabbits"]) == 0 and str(lonely["detail"]).contains("3 together") and int(paired["nearby_rabbits"]) == 1, "placement explains missing companions before the player commits")
	systems.run_director.milestone_index = 2
	var before := int(systems.inventory["rabbit"])
	systems.run_director._complete_current_milestone()
	_check(int(systems.inventory["rabbit"]) == before + 3 and systems.run_director.current_milestone_id() == "nursery_network", "the third-home act gives the player three placeable nursery starters")
