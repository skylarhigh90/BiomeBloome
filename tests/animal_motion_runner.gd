extends SceneTree

const Motion = preload("res://rendering/animal_motion.gd")

var failures: Array[String] = []
var passed := 0

func _initialize() -> void:
	_test_landing_and_interrupt()
	_test_live_stop_transitions()
	_test_fox_distance_and_facing()
	_test_clock_and_pause()
	_test_capture_event()
	_test_preview_defaults()
	print("%d animal motion tests passed; %d failed." % [passed, failures.size()])
	for failure in failures:
		printerr("FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: " + label)
	else:
		failures.append(label)

func _flat_config() -> Dictionary:
	var cfg := GameConfig.make()
	cfg["world"]["forest_patch_count"] = 0
	cfg["terrain"]["thicket"]["patch_count"] = 0
	cfg["terrain"]["stream"]["enabled"] = false
	return cfg

func _test_landing_and_interrupt() -> void:
	var rabbit := {
		"type": "rabbit", "behavior": "return_home", "position": Vector2(20.0, 15.0),
		"velocity": Vector2(45.0, 0.0), "motion_velocity": Vector2(40.0, 0.0),
		"gait_phase": 3.5, "previous_gait_phase": 3.4, "facing": 0.0,
	}
	var before := Motion.sample(rabbit, 1.0, 1.0, 0.1)
	Motion.begin_step(rabbit, 1.0, 0.1)
	rabbit["previous_gait_phase"] = rabbit["gait_phase"]
	rabbit["behavior"] = "eat"
	rabbit["velocity"] = Vector2.ZERO
	rabbit["motion_velocity"] = Vector2.ZERO
	Motion.finish_step(rabbit, 0.1)
	var at_stop := Motion.sample(rabbit, 0.0, 1.1, 0.1)
	var during := Motion.sample(rabbit, 0.5, 1.1, 0.1)
	_check(float(before["lift"]) > 4.0 and is_equal_approx(float(at_stop["lift"]), float(before["lift"])) and Vector2(at_stop["stretch"]).is_equal_approx(before["stretch"]), "planting preserves the exact preceding airborne pose")
	_check(float(during["lift"]) > 0.0 and float(during["lift"]) < float(before["lift"]), "ordinary stop lowers the body continuously during the fixed step")
	var interrupted := rabbit.duplicate(true)
	var before_interrupt := Motion.sample(interrupted, 1.0, 1.1, 0.1)
	Motion.begin_step(interrupted, 1.1, 0.1)
	interrupted["behavior"] = "flee"
	interrupted["gait_phase"] = 3.75
	interrupted["motion_velocity"] = Vector2(90.0, 0.0)
	Motion.finish_step(interrupted, 0.1)
	var interrupt_start := Motion.sample(interrupted, 0.0, 1.2, 0.1)
	_check(is_equal_approx(float(interrupt_start["lift"]), float(before_interrupt["lift"])) and float(Motion.sample(interrupted, 1.0, 1.2, 0.1)["move"]) > 0.9, "danger can resume locomotion immediately without a pose snap")
	Motion.begin_step(rabbit, 1.1, 0.1)
	Motion.finish_step(rabbit, 0.1)
	var landed := Motion.sample(rabbit, 1.0, 1.2, 0.1)
	_check(is_zero_approx(float(landed["lift"])) and is_zero_approx(float(landed["move"])) and Vector2(landed["stretch"]).is_equal_approx(Vector2.ONE), "a maximum-height ordinary stop settles fully in 0.20 simulation seconds")
	for tick in range(20):
		Motion.begin_step(rabbit, 1.2 + tick * 0.1, 0.1)
		Motion.finish_step(rabbit, 0.1)
	_check(rabbit["position"] == Vector2(20.0, 15.0) and rabbit["behavior"] == "eat" and is_zero_approx(float(Motion.sample(rabbit, 0.5, 3.2, 0.1)["lift"])), "presentation leaves sustained feeding planted and does not change behavior")

func _fox() -> Dictionary:
	return {"type": "fox", "behavior": "wander", "position": Vector2.ZERO, "previous_position": Vector2.ZERO, "velocity": Vector2(40.0, 0.0), "facing": 0.7, "previous_facing": 0.7, "gait_phase": 0.0, "previous_gait_phase": 0.0}

func _test_live_stop_transitions() -> void:
	var sim := EcosystemSimulation.new(_flat_config())
	sim.add_plant("berry_bush", Vector2(60.0, 0.0))
	var id := sim.add_rabbit(Vector2(-100.0, 0.0))
	var rabbit: Dictionary = sim.rabbits[id]
	rabbit["hunger"] = 30.0
	var airborne_stops := 0
	var continuous := true
	for tick in range(120):
		var was_planted: bool = rabbit["behavior"] in Motion.PLANTED_ACTIVITIES
		var before := Motion.sample(rabbit, 1.0, sim.simulation_time, 0.1)
		sim.step(0.1)
		if not was_planted and rabbit["behavior"] in Motion.PLANTED_ACTIVITIES and float(before["lift"]) > 0.5:
			airborne_stops += 1
			var start := Motion.sample(rabbit, 0.0, sim.simulation_time, 0.1)
			continuous = continuous and is_equal_approx(float(start["lift"]), float(before["lift"])) and Vector2(start["stretch"]).is_equal_approx(before["stretch"])
			continuous = continuous and Vector2(rabbit["position"]).is_equal_approx(rabbit["previous_position"])
	_check(airborne_stops > 0 and continuous, "live forage-to-rest transitions preserve airborne poses while the motor stays planted")

func _move_fox(fox: Dictionary, displacement: Vector2, delta: float) -> void:
	Motion.begin_step(fox, 1.0, delta)
	fox["previous_position"] = fox["position"]
	fox["previous_gait_phase"] = fox["gait_phase"]
	fox["previous_facing"] = fox["facing"]
	fox["position"] += displacement
	Motion.finish_step(fox, delta)

func _test_fox_distance_and_facing() -> void:
	var slow := _fox()
	var fast := _fox()
	_move_fox(slow, Vector2(8.0, 0.0), 0.2)
	_move_fox(fast, Vector2(8.0, 0.0), 0.1)
	_check(float(slow["gait_phase"]) > 0.0 and is_equal_approx(float(slow["gait_phase"]), float(fast["gait_phase"])), "fox footfall phase follows distance traveled at different speeds")
	var phase: float = slow["gait_phase"]
	var facing: float = slow["facing"]
	_move_fox(slow, Vector2.ZERO, 0.1)
	var stopped := Motion.sample(slow, 1.0, 1.1, 0.1)
	_check(is_equal_approx(float(stopped["phase"]), phase) and is_equal_approx(float(stopped["facing"]), facing) and is_zero_approx(float(stopped["move"])), "a blocked fox holds its phase and facing despite a nonzero desired velocity")
	var gait := _fox()
	var heights: Array[float] = []
	for frame in range(101):
		gait["gait_phase"] = float(frame) / 100.0
		heights.append(float(Motion.sample(gait, 1.0, 1.0, 0.1)["lift"]))
	var rises := 0
	for frame in range(1, heights.size() - 1):
		if heights[frame] > heights[frame - 1] and heights[frame] > heights[frame + 1]:
			rises += 1
	_check(rises == 2, "fox body has two rises per full diagonal-pair trot cycle")

func _test_clock_and_pause() -> void:
	var one := GameSystems.new(_flat_config())
	var three := GameSystems.new(_flat_config())
	for systems in [one, three]:
		systems.supply_time_remaining = 9999.0
		systems.simulation.add_rabbit(Vector2(100.0, 0.0))
		var fox_id: int = systems.simulation.add_fox(Vector2(-200.0, 0.0))
		systems.simulation.foxes[fox_id]["hunger"] = 0.0
	one.set_speed(1.0)
	three.set_speed(3.0)
	for frame in range(31):
		one.advance(0.05)
		three.advance(0.05 / 3.0)
	for kind in ["rabbit", "fox"]:
		var id := 1 if kind == "rabbit" else 2
		var a: Dictionary = one.simulation.rabbits[id] if kind == "rabbit" else one.simulation.foxes[id]
		var b: Dictionary = three.simulation.rabbits[id] if kind == "rabbit" else three.simulation.foxes[id]
		var pose_a := Motion.sample(a, one.interpolation_alpha(), one.simulation.simulation_time, 0.1)
		var pose_b := Motion.sample(b, three.interpolation_alpha(), three.simulation.simulation_time, 0.1)
		_check(_same_pose(pose_a, pose_b) and Vector2(a["position"]).is_equal_approx(b["position"]), kind + " pose and travel agree at 1x/3x for equal simulation time")
	one.set_speed(0.0)
	var paused_fox: Dictionary = one.simulation.foxes[2]
	# Pause must freeze event envelopes as well as locomotion and idle clocks.
	paused_fox["last_capture_time"] = one.simulation.simulation_time - 0.15
	var paused := Motion.sample(paused_fox, one.interpolation_alpha(), one.simulation.simulation_time, 0.1)
	one.advance(2.0)
	var after := Motion.sample(paused_fox, one.interpolation_alpha(), one.simulation.simulation_time, 0.1)
	_check(float(paused["capture"]) > 0.0 and _same_pose(paused, after), "pause freezes fox gait, facing, idle clock, lift and capture response")

func _same_pose(a: Dictionary, b: Dictionary) -> bool:
	for key in ["phase", "move", "time", "lift", "facing", "capture"]:
		if not is_equal_approx(float(a[key]), float(b[key])):
			return false
	return Vector2(a["stretch"]).is_equal_approx(b["stretch"])

func _test_capture_event() -> void:
	var cfg := _flat_config()
	cfg["fox"]["capture_rate"] = 1000.0
	cfg["fox"]["capture_distance"] = 80.0
	var sim := EcosystemSimulation.new(cfg)
	var rabbit_id := sim.add_rabbit(Vector2.ZERO)
	var fox_id := sim.add_fox(Vector2(8.0, 0.0))
	var fox: Dictionary = sim.foxes[fox_id]
	fox["hunger"] = 50.0
	sim.step(0.1)
	var before := Motion.sample(fox, 0.0, sim.simulation_time, 0.1)
	var response := Motion.sample(fox, 1.0, sim.simulation_time + 0.08, 0.1)
	var after := Motion.sample(fox, 1.0, sim.simulation_time + 0.6, 0.1)
	_check(not sim.rabbits.has(rabbit_id) and int(fox["meals"]) == 1 and is_equal_approx(float(fox["last_capture_time"]), sim.simulation_time), "a successful hunt starts visual capture timing without delaying the meal")
	_check(is_zero_approx(float(before["capture"])) and float(response["capture"]) > 0.5 and is_zero_approx(float(after["capture"])), "capture response begins after the event and settles within half a second")

func _test_preview_defaults() -> void:
	for kind in ["rabbit", "fox"]:
		var pose := Motion.sample({"type": kind}, 1.0, 0.0, 0.1)
		_check(is_zero_approx(float(pose["move"])) and is_zero_approx(float(pose["lift"])) and is_zero_approx(float(pose["capture"])) and Vector2(pose["stretch"]).is_equal_approx(Vector2.ONE), kind + " preview works without live simulation fields")
