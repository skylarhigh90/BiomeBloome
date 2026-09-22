class_name AnimalMotion
extends RefCounted

# Presentation distances are independent of the motor and ecology tuning.
const FOX_STRIDE_LENGTH := 29.0
const LANDING_DURATION := 0.20
const RABBIT_HOP_HEIGHT := 4.8
const CAPTURE_DURATION := 0.44
const PLANTED_ACTIVITIES := ["eat", "loaf", "socialize", "observe"]

# Capture the visible endpoint before a simulation step changes activity or
# velocity. This preserves an airborne pose when the motor plants its feet.
static func begin_step(animal: Dictionary, simulation_time: float, fixed_step: float) -> void:
	var pose := sample(animal, 1.0, simulation_time, fixed_step)
	animal["previous_visual_move"] = pose["move"]
	animal["previous_visual_lift"] = pose["lift"]
	animal["previous_visual_stretch"] = pose["stretch"]
	animal["previous_visual_planted"] = _is_planted(animal)

static func finish_step(animal: Dictionary, delta: float) -> void:
	var is_rabbit := str(animal.get("type", "rabbit")) == "rabbit"
	var velocity: Vector2 = animal.get("motion_velocity", animal.get("velocity", Vector2.ZERO))
	var moving := clampf(velocity.length() / 30.0, 0.0, 1.0)
	if not is_rabbit:
		var displacement: Vector2 = Vector2(animal["position"]) - Vector2(animal["previous_position"])
		animal["gait_phase"] = float(animal.get("gait_phase", 0.0)) + displacement.length() / FOX_STRIDE_LENGTH
		moving = clampf(displacement.length() / maxf(0.0001, delta) / 64.0, 0.0, 1.0)
		if displacement.length_squared() > 0.0001:
			animal["facing"] = lerp_angle(float(animal.get("facing", displacement.angle())), displacement.angle(), 1.0 - exp(-10.0 * delta))
	animal["visual_move"] = moving
	var natural := _gait_pose(is_rabbit, float(animal.get("gait_phase", 0.0)), moving)
	animal["visual_lift"] = natural["lift"]
	animal["visual_stretch"] = natural["stretch"]
	if is_rabbit and _is_planted(animal):
		# Feet stay at the simulation's chosen feeding/rest position. Only the
		# drawn body settles, within two default fixed steps, even after a high hop.
		animal["visual_move"] = move_toward(float(animal.get("previous_visual_move", 0.0)), 0.0, delta / LANDING_DURATION)
		animal["visual_lift"] = move_toward(float(animal.get("previous_visual_lift", 0.0)), 0.0, RABBIT_HOP_HEIGHT * delta / LANDING_DURATION)
		animal["visual_stretch"] = Vector2(animal.get("previous_visual_stretch", Vector2.ONE)).move_toward(Vector2.ONE, 0.20 * delta / LANDING_DURATION)

static func sample(animal: Dictionary, alpha: float, simulation_time: float, fixed_step: float) -> Dictionary:
	var blend := clampf(alpha, 0.0, 1.0)
	var time := maxf(0.0, simulation_time - (1.0 - blend) * fixed_step)
	var is_rabbit := str(animal.get("type", "rabbit")) == "rabbit"
	var velocity: Vector2 = animal.get("motion_velocity", animal.get("velocity", Vector2.ZERO))
	var fallback_move := 0.0 if _is_planted(animal) else clampf(velocity.length() / (30.0 if is_rabbit else 64.0), 0.0, 1.0)
	var current_move := float(animal.get("visual_move", fallback_move))
	var moving := lerpf(float(animal.get("previous_visual_move", current_move)), current_move, blend)
	var phase := lerpf(float(animal.get("previous_gait_phase", animal.get("gait_phase", 0.0))), float(animal.get("gait_phase", 0.0)), blend)
	var facing := float(animal.get("facing", velocity.angle() if velocity.length_squared() > 0.01 else 0.0))
	facing = lerp_angle(float(animal.get("previous_facing", facing)), facing, blend)
	var gait := _gait_pose(is_rabbit, phase, moving)
	if is_rabbit and (_is_planted(animal) or bool(animal.get("previous_visual_planted", false))):
		# Normal travel samples the continuous hop curve. Activity boundaries
		# interpolate the actual previous pose so stopping cannot cut off a hop;
		# resuming (including flight from danger) never waits for that landing.
		gait["lift"] = lerpf(float(animal.get("previous_visual_lift", 0.0)), float(animal.get("visual_lift", 0.0)), blend)
		gait["stretch"] = Vector2(animal.get("previous_visual_stretch", Vector2.ONE)).lerp(animal.get("visual_stretch", Vector2.ONE), blend)
	var capture := 0.0
	if not is_rabbit:
		var captured_at := float(animal.get("last_capture_time", -INF))
		var since_capture := time - captured_at
		if since_capture >= 0.0 and since_capture < CAPTURE_DURATION:
			capture = sin(PI * pow(since_capture / CAPTURE_DURATION, 0.55))
	return {
		"phase": phase,
		"move": moving,
		"time": time,
		"lift": gait["lift"],
		"stretch": gait["stretch"],
		"facing": facing,
		"capture": capture,
	}

static func _is_planted(animal: Dictionary) -> bool:
	return str(animal.get("type", "rabbit")) == "rabbit" and str(animal.get("behavior", "")) in PLANTED_ACTIVITIES

static func _gait_pose(is_rabbit: bool, phase: float, moving: float) -> Dictionary:
	if is_rabbit:
		var flight := sin(clampf((fposmod(phase, 1.0) - 0.15) / 0.70, 0.0, 1.0) * PI)
		return {
			"lift": flight * moving * RABBIT_HOP_HEIGHT,
			"stretch": Vector2(1.0 + flight * moving * 0.10, 1.0 - (1.0 - flight) * moving * 0.10),
		}
	# One rise per diagonal pair: two contacts, and two rises, per full trot.
	var stride := sin(phase * TAU)
	return {"lift": absf(stride) * moving * 0.85, "stretch": Vector2(1.0 + stride * moving * 0.025, 1.0 - stride * moving * 0.025)}
