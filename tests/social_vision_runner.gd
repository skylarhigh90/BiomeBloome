extends SceneTree

const Config = preload("res://config/game_config.gd")
const Simulation = preload("res://simulation/ecosystem_simulation.gd")

const SOCIAL_RADII := [0.0, 35.0, 50.0, 60.0, 70.0, 90.0, 120.0, 160.0]

func _initialize() -> void:
	print("\nSOCIAL VISION SWEEP · local food vision remains 100 units")
	for social_radius in SOCIAL_RADII:
		print("radius %3.0f: %s" % [social_radius, str(_run_trial(float(social_radius)))])
	quit(0)

func _run_trial(social_radius: float) -> Dictionary:
	var config := Config.make().duplicate(true)
	config["world"]["forest_patch_count"] = 0
	config["terrain"]["thicket"]["patch_count"] = 0
	config["terrain"]["stream"]["enabled"] = false
	config["rabbit"]["food_detection_radius"] = 100.0
	config["rabbit"]["social_proximity_radius"] = social_radius
	config["rabbit"]["reproduction_food_needed"] = 99999.0
	config["rabbit"]["lifespan"] = 9999.0
	var sim = Simulation.new(config, 7341)
	var rabbit_ids: Array[int] = []
	for index in range(10):
		var rabbit_id: int = sim.add_rabbit(Vector2(float(index) * 60.0 - 270.0, 0.0))
		sim.rabbits[rabbit_id]["hunger"] = 55.0
		rabbit_ids.append(rabbit_id)
	var plant_id: int = sim.add_plant("carrot_patch", Vector2(330.0, 0.0))
	sim.step(0.1)
	var targets := 0
	var groups: Dictionary = {}
	var largest_shared_view := 0
	for rabbit_id in rabbit_ids:
		if int(sim.rabbits[rabbit_id]["target_id"]) == plant_id:
			targets += 1
		var group: Array = sim.rabbit_social_groups.get(rabbit_id, [rabbit_id])
		groups[group[0]] = true
		largest_shared_view = maxi(largest_shared_view, int(sim.rabbit_shared_food_vision.get(rabbit_id, {}).size()))
	return {
		"groups": groups.size(),
		"rabbits_targeting_food": targets,
		"largest_shared_view": largest_shared_view,
		"first_rabbit_target": int(sim.rabbits[rabbit_ids[0]]["target_id"]) == plant_id,
	}
