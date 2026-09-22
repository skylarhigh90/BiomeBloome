class_name GameConfig
extends RefCounted

const WORLD_EXPANSION_STEP := 48.0

## Focused six-act progression plus terrain and balance values live here.
static func make() -> Dictionary:
	return {
		"simulation": {
			"fixed_step": 0.1,
			"spatial_cell_size": 96.0,
			"seed": 240817,
			"max_steps_per_frame": 24,
			"reproduction_check_interval": 1.0,
		},
		"rabbit": {
			"move_speed": 38.0,
			"flee_speed": 72.0,
			"exhausted_flee_speed": 50.0,
			"flee_stamina_capacity": 8.5,
			"flee_stamina_recovery": 1.4,
			"steering": 4.8,
			"speed_variation": 0.18,
			"turn_variation": 0.35,
			"hunger_threshold_variation": 4.0,
			"caution_variation": 0.14,
			"decision_interval_min": 0.18,
			"decision_interval_max": 0.55,
			"wander_turn_rate": 0.9,
			"wander_turn_response": 2.8,
			"wander_noise_interval_min": 0.45,
			"wander_noise_interval_max": 1.25,
			"personal_space_min": 28.0,
			"personal_space_max": 36.0,
			"separation_strength": 0.58,
			"food_crowding_penalty": 26.0,
			"food_stock_preference": 38.0,
			# One complete fixed-step bite. Smaller scraps do not count as a usable
			# meal even before a patch crosses its depletion threshold.
			"minimum_food_bite": 0.12,
			"hunger_rate": 1.45,
			# Rabbits begin looking before they are in visible distress. Hunger still
			# controls appetite, but food should be a noticeable influence on movement.
			"hungry_at": 20.0,
			# Once feeding starts, rabbits finish a meal before roaming again. This
			# lower release threshold prevents one-bite trips back to the same plant.
			"sated_at": 11.0,
			# UI warning starts well before starvation, leaving roughly 30 seconds
			# to react at 1x even when a rabbit cannot find food.
			"hunger_warning_at": 56.0,
			# This remains for local nursery/progression evidence. Rabbit food
			# acquisition uses it as each Rabbit's local vision limit.
			"food_detection_radius": 175.0,
			# Hungry Rabbits first search locally, then deliberately widen the search.
			# Remembered patches remain useful after the colony has wandered away.
			"food_memory_duration": 90.0,
			"emergency_search_after": 3.0,
			"emergency_search_radius_factor": 2.6,
			"critical_search_radius_factor": 8.0,
			"emergency_grazing": true,
			# Nearby Rabbits share their current local vision through a connected
			# social group. Keep this smaller than food vision so social awareness is
			# earned by staying together rather than being global by default.
			"social_proximity_radius": 50.0,
			# A Rabbit's first dependable meal becomes its home. Nearby diners share
			# that anchor, producing stable local colonies without global flocking.
			"home_join_radius": 82.0,
			"home_loaf_radius": 34.0,
			"home_return_radius": 62.0,
			"home_loaf_speed_factor": 0.24,
			"home_return_speed_factor": 0.78,
			# Ready adults gather more tightly at home, so mating follows residency
			# instead of depending on two random wander paths crossing.
			"home_mating_radius": 24.0,
			"home_mating_speed_factor": 0.38,
			# A temporary empty patch should not erase a home. After enough cumulative
			# hungry time, a meal well outside the home range can establish a new one.
			"home_relocation_hungry_time": 24.0,
			"home_relocation_distance": 110.0,
			"fox_detection_radius": 105.0,
			"flee_release_radius": 132.0,
			# Severe hunger makes Rabbits accept more predation risk rather than flee
			# indefinitely until they starve beside usable food.
			"starving_threat_radius_factor": 0.48,
			"eat_distance": 13.0,
			# Intake is spread across a visible feeding bout. Food value and daily
			# hunger costs are unchanged; eating now occupies real simulation time.
			"eat_rate": 1.2,
			"feeding_site_radius": 24.0,
			"feeding_arrival_distance": 5.0,
			"rest_duration": 4.0,
			"observe_duration": 1.2,
			"hop_frequency": 2.4,
			"food_value": 7.5,
			"mating_radius": 82.0,
			"reproduction_cooldown": 34.0,
			"reproduction_hunger_max": 34.0,
			"reproduction_food_needed": 18.0,
			"local_food_needed": 14.0,
			# Births are paid for from real local biomass and only occur when the
			# renewable forage flow can carry another Rabbit. This is the main
			# anti-boom/bust feedback loop, not an arbitrary population cap.
			"reproduction_resource_radius": 210.0,
			"reproduction_capacity_utilization": 0.80,
			"reproduction_min_stock_ratio": 0.34,
			"reproduction_biomass_cost": 2.0,
			"reproduction_parent_energy_cost": 10.0,
			"reproduction_parent_hunger_cost": 4.0,
			"adult_age": 12.0,
			"starvation_threshold": 78.0,
			"starvation_duration": 16.0,
			"starvation_recovery_rate": 2.0,
			"feeding_starvation_relief": 1.75,
			"lifespan": 225.0,
			"recent_food_decay": 0.34,
			"birth_litter_min": 1,
			"birth_litter_max": 1,
			"newborn_cooldown": 24.0,
			"max_population": 400,
		},
		"fox": {
			"move_speed": 44.0,
			"chase_speed": 64.0,
			# Foxes use a short closing burst instead of receiving a permanent speed
			# advantage. Failed pursuits force a recovery window and a prey change.
			"sprint_speed": 78.0,
			"exhausted_chase_speed": 60.0,
			"sprint_stamina_capacity": 5.5,
			"sprint_restart_stamina": 2.5,
			"sprint_stamina_recovery": 1.0,
			"desperation_stamina_recovery_factor": 1.8,
			"desperation_speed_factor": 1.30,
			"sprint_activation_radius": 175.0,
			"meal_stamina_restore": 1.5,
			"max_pursuit_duration": 24.0,
			"pursuit_rest_duration": 3.5,
			"failed_target_memory": 9.0,
			"pursuit_learning_per_failure": 0.14,
			"pursuit_learning_max_bonus": 0.56,
			"steering": 3.8,
			"hunger_rate": 0.45,
			"hunt_at": 30.0,
			"prey_detection_radius": 260.0,
			"emergency_detection_factor": 6.0,
			"prey_competition_penalty": 150.0,
			"covered_prey_penalty": 52.0,
			"capture_distance": 12.0,
			"capture_rate": 2.0,
			"meal_value": 62.0,
			"mating_radius": 105.0,
			"reproduction_cooldown": 72.0,
			"reproduction_hunger_max": 28.0,
			"reproduction_food_needed": 34.0,
			"reproduction_resource_radius": 380.0,
			"reproduction_prey_per_fox": 6.0,
			"adult_age": 18.0,
			"starvation_threshold": 82.0,
			"starvation_duration": 30.0,
			"starvation_recovery_rate": 1.5,
			"lifespan": 330.0,
			"recent_food_decay": 0.28,
			"newborn_cooldown": 55.0,
			"max_population": 80,
		},
		"plants": {
			"carrot_patch": {
				"max_food": 14.0,
				"regeneration": 0.42,
				"abundant_ratio": 0.70,
				"healthy_ratio": 0.35,
				"depleted_ratio": 0.10,
				# Fast Carrots need a higher release threshold to remain visibly out of
				# service for about 15 seconds rather than returning as tiny bites.
				"recovery_ratio": 0.52,
			},
			"berry_bush": {
				"max_food": 24.0,
				"regeneration": 0.34,
				"abundant_ratio": 0.70,
				"healthy_ratio": 0.35,
				"depleted_ratio": 0.10,
				"recovery_ratio": 0.42,
			},
		},
		"world": {
			"initial_radius": 360.0,
			"expansion_amount": WORLD_EXPANSION_STEP,
			"maximum_radius": 940.0,
			"forest_patch_count": 27,
			"forest_patch_min_radius": 95.0,
			"forest_patch_max_radius": 205.0,
			"placement_clearance": 9.0,
		},
		"terrain": {
			"query_bin_size": 240.0,
			"woodland": {
				"fox_patrol_search_radius": 420.0,
				"fox_patrol_cover_target": 0.58,
				"fox_patrol_replan_interval": 4.5,
				"fox_wander_steering_strength": 0.62,
			},
			"thicket": {
				"patch_count": 22,
				"patch_min_radius": 44.0,
				"patch_max_radius": 88.0,
				"rabbit_speed_factor": 0.99,
				"fox_speed_factor": 0.58,
				"fox_capture_rate_factor": 0.38,
				"fox_capture_range_factor": 0.72,
				"refuge_search_radius": 230.0,
				"refuge_cover_min": 0.48,
				"refuge_threat_detection_factor": 1.38,
				"refuge_evasion_speed_factor": 0.82,
				"rabbit_flee_stamina_drain_factor": 0.30,
			},
			"stream": {
				"enabled": true,
				"point_count": 49,
				"initial_offset_ratio": 0.34,
				"meander": 78.0,
				"half_width_min": 25.0,
				"half_width_max": 35.0,
				"deep_water_threshold": 0.34,
				"ford_positions": [0.19, 0.48, 0.81],
				"ford_radius": 38.0,
			},
			"routing": {
				"path_sample_spacing": 11.0,
				"bank_approach_clearance": 34.0,
				"waypoint_reached_distance": 17.0,
				"moving_target_replan_distance": 34.0,
				"moving_target_replan_interval": 0.55,
			},
			"food_suitability": {
				"carrot_minimum": 0.42,
				"carrot_meadow_bonus": 0.78,
				"carrot_maximum": 1.20,
				"berry_base": 0.62,
				"berry_margin_peak": 0.46,
				"berry_margin_bonus": 0.62,
				"berry_deep_cover_start": 0.68,
				"berry_deep_cover_penalty": 0.34,
				"berry_minimum": 0.46,
				"berry_maximum": 1.24,
				"poor_capacity_factor": 0.48,
				"rich_capacity_factor": 1.28,
			},
		},
		"inventory": {
			"rabbit": 4,
			"fox": 0,
			"carrot_patch": 5,
			"berry_bush": 0,
		},
		"tools": {
			"undo_seconds": 5.0,
			"transplant_retained_biomass": 0.65,
		},
		"supply": {
			"interval": 90.0,
			"pools": {
				"meadow": [
					{"name": "Carrot starters", "items": {"rabbit": 1, "carrot_patch": 1}},
					{"name": "Berry refuge", "items": {"rabbit": 1, "berry_bush": 1}},
					{"name": "Fresh harvest", "items": {"carrot_patch": 2, "berry_bush": 1}},
					{"name": "Forage patch", "items": {"carrot_patch": 1, "berry_bush": 1}},
				],
				"web": [
					{"name": "Carrot renewal", "items": {"rabbit": 1, "carrot_patch": 1}},
					{"name": "Berry refuge", "items": {"rabbit": 1, "berry_bush": 1}},
					{"name": "Forest balance", "items": {"fox": 1, "carrot_patch": 1}},
					{"name": "Fresh harvest", "items": {"carrot_patch": 2, "berry_bush": 1}},
					{"name": "Wild pair", "items": {"rabbit": 1, "fox": 1}},
					{"name": "Forage patch", "items": {"carrot_patch": 1, "berry_bush": 1}},
				],
				"living": [
					{"name": "Carrot renewal", "items": {"carrot_patch": 2}},
					{"name": "Berry refuge", "items": {"berry_bush": 2}},
					{"name": "Forest balance", "items": {"fox": 1, "carrot_patch": 1}},
					{"name": "Wild balance", "items": {"rabbit": 1, "fox": 1}},
					{"name": "Fresh harvest", "items": {"carrot_patch": 2, "berry_bush": 1}},
					{"name": "Dense forage", "items": {"carrot_patch": 1, "berry_bush": 2}},
				],
			},
			"first_collapse_bundle": {"name": "Carrot starters", "items": {"rabbit": 2, "carrot_patch": 1}},
		},
		"progression": {
			"initial_unlocked": ["rabbit", "carrot_patch"],
			"initial_supply_pool": "meadow",
			"trend_sample_interval": 1.0,
			"trend_history_duration": 35.0,
			"spatial_sample_interval": 0.5,
			# Retain this evaluator key for compatibility. Player-facing copy calls
			# every qualifying rabbit group a nursery.
			"safe_havens": {
				"minimum_groups": 2,
				"rabbits_per_group": 2,
				"minimum_separation": 300.0,
				"minimum_local_food": 14.0,
			},
			# Six distinct acts introduce one new idea at a time. Live habitat state
			# carries forward; checkpoint-local event counters are used only when the
			# event itself is the lesson, never to make the player repeat old proofs.
			"milestones": [
				{
					"id": "first_meal",
					"tier": "minor",
					"title": "The First Meal",
					"summary": "Welcome 4 rabbits and help 3 founders find food.",
					"guide_intro": "This checkpoint begins with the rabbits you place. Living-animal credit can fall if a counted rabbit dies.",
					"goal_help": {
						"rabbit_population": {
							"behavior": "LIVE · CAN CHANGE",
							"detail": "Keep at least four rabbits alive in the meadow at the same time.",
						},
						"founders_fed": {
							"behavior": "LIVING CREDIT · CAN FALL",
							"detail": "Three different rabbits placed by you must each eat. A rabbit only counts while it is alive.",
						},
						"hold": {
							"behavior": "TOGETHER · TIMER RESETS",
							"detail": "Once every goal is complete, keep them complete together. If any live goal drops, the hold starts over.",
						},
					},
					"display_populations": ["rabbit"],
					"rabbit_min": 4,
					"fox_min": 0,
					"criteria": [
						{
							"id": "founders_fed",
							"type": "founders_fed",
							"label": "Founders that ate",
							"metric_label": "FED FOUNDERS",
							"target": 3,
						},
					],
					"stabilization": 8.0,
					"labels": {
						"low": "The first rabbits are gathering...",
						"evidence": "The founders are looking for food...",
						"stabilizing": "The colony is settling...",
					},
					"guidance": "Place four rabbits with reachable Carrot Patches nearby. Three different founders must eat before the colony can settle.",
					"teaser": "Berry Bushes will bring slower, lasting forage to woodland edges.",
					"completion_message": "The founders have eaten · Berry Bushes unlocked",
					"effects": {
						"expand_world": WORLD_EXPANSION_STEP * 1.5,
						"unlock": ["berry_bush"],
						"introduction": {"berry_bush": 2},
					},
				},
				{
					"id": "first_family",
					"tier": "minor",
					"title": "The First Family",
					"summary": "Let the founders raise young, then watch one learn to forage.",
					"guide_intro": "Only births after this checkpoint opens count. This is the one checkpoint that teaches newborn growth; later acts build on the result instead of asking for the same proof again.",
					"goal_help": {
						"rabbit_population": {
							"behavior": "LIVE · CAN CHANGE",
							"detail": "Keep at least five rabbits alive while the new generation grows.",
						},
						"new_rabbits": {
							"behavior": "SAVED · THIS CHECKPOINT",
							"detail": "Count rabbit births that happen naturally after this checkpoint begins. Placed rabbits do not count as births.",
						},
						"young_rabbits_fed": {
							"behavior": "LIVING CREDIT · CAN FALL",
							"detail": "One rabbit born during this checkpoint must grow beyond its newborn stage and eat. It only counts while alive.",
						},
						"hold": {
							"behavior": "TOGETHER · TIMER RESETS",
							"detail": "Once every goal is complete, keep the living young rabbits safe through the hold. If a live goal drops, the hold starts over.",
						},
					},
					"display_populations": ["rabbit"],
					"rabbit_min": 5,
					"fox_min": 0,
					"criteria": [
						{
							"id": "new_rabbits",
							"type": "rabbit_birth",
							"label": "Rabbits born this checkpoint",
							"metric_label": "NEW RABBITS",
							"target": 2,
						},
						{
							"id": "young_rabbits_fed",
							"type": "born_rabbit_fed",
							"label": "New young that grow and eat",
							"metric_label": "YOUNG FORAGERS",
							"target": 1,
							"minimum_age": 6.0,
							"fresh_only": true,
						},
					],
					"stabilization": 12.0,
					"labels": {
						"evidence": "The new generation is still taking shape...",
						"stabilizing": "The young generation is holding...",
					},
					"guidance": "Keep adult rabbits together near stocked food. Two natural births and one young forager establish the first family.",
					"teaser": "Next, use Meadow and woodland-edge forage to establish two lasting homes.",
					"completion_message": "The first family is thriving · Transplant unlocked",
					"effects": {
						"expand_world": WORLD_EXPANSION_STEP * 1.5,
						"unlock": ["transplant"],
						"transplant_charges": 1,
					},
				},
				{
					"id": "two_homes",
					"tier": "minor",
					"title": "Two Lasting Homes",
					"summary": "Build 2 separated nurseries with productive Carrots and Berries.",
					"guide_intro": "Nurseries and plant productivity are live conditions. The placement preview now shows habitat quality, and Transplant lets you correct one poor plant site without discarding the plant.",
					"goal_help": {
						"rabbit_population": {
							"behavior": "LIVE · CAN CHANGE",
							"detail": "Keep at least six rabbits alive so two groups of three can form.",
						},
						"nurseries": {
							"behavior": "LIVE · CAN RISE OR FALL",
							"detail": "A nursery is at least three rabbits gathered around usable nearby food. Build two groups in separate parts of the meadow; numbered cradle markers show which groups count right now.",
						},
						"productive_forages": {
							"behavior": "LIVE · CAN RISE OR FALL",
							"detail": "Keep at least one usable Carrot Patch and one usable Berry Bush in productive habitat. The placement preview labels rich, fair, and poor sites before you commit.",
						},
						"hold": {
							"behavior": "TOGETHER · TIMER RESETS",
							"detail": "Keep both nurseries and both productive forage types live together. If a group disperses or its food depletes, the hold starts over.",
						},
					},
					"display_populations": ["rabbit"],
					"rabbit_min": 6,
					"fox_min": 0,
					"criteria": [
						{
							"id": "nurseries",
							"type": "safe_havens",
							"label": "Stable nursery groups",
							"metric_label": "NURSERIES",
							"lens_label": "Nursery",
							"target": 2,
							"rabbits_per_group": 3,
							"minimum_separation": 240.0,
							"minimum_local_food": 0.0,
						},
						{
							"id": "productive_forages",
							"type": "productive_forages",
							"label": "Productive forage types",
							"metric_label": "FORAGE TYPES",
							"target": 2,
							"plant_types": ["carrot_patch", "berry_bush"],
							"minimum_capacity_factor": 0.78,
						},
					],
					"stabilization": 16.0,
					"labels": {
						"evidence": "The nursery network is still being built...",
						"stabilizing": "The nursery network is holding...",
					},
					"guidance": "Use the habitat preview to place both food types well, then support two groups of three rabbits around separate forage sites.",
					"teaser": "A third nursery will make the meadow resilient enough for predators.",
					"completion_message": "Two lasting homes · Nursery starters and Transplant charge gained",
					"effects": {
						"expand_world": WORLD_EXPANSION_STEP * 1.5,
						"introduction": {"rabbit": 3, "carrot_patch": 2},
						"transplant_charges": 1,
					},
				},
				{
					"id": "nursery_network",
					"tier": "major",
					"title": "A Nursery Network",
					"summary": "Grow the 2 homes into a network of 3 live nurseries.",
					"guide_intro": "Your two existing homes already count if they remain healthy. This act asks for one meaningful expansion, not another round of fresh birth records.",
					"goal_help": {
						"rabbit_population": {
							"behavior": "LIVE · CAN CHANGE",
							"detail": "Keep at least nine rabbits alive so three groups of three can form.",
						},
						"nurseries": {
							"behavior": "LIVE · CAN RISE OR FALL",
							"detail": "Maintain three separated groups of at least three rabbits around usable nearby food. Existing nurseries carry directly into this act.",
						},
						"hold": {
							"behavior": "TOGETHER · TIMER RESETS",
							"detail": "Keep all three nursery groups alive together. If a group disperses or loses usable food, the hold starts over.",
						},
					},
					"display_populations": ["rabbit"],
					"rabbit_min": 9,
					"fox_min": 0,
					"criteria": [
						{
							"id": "nurseries",
							"type": "safe_havens",
							"label": "Stable nursery groups",
							"metric_label": "NURSERIES",
							"lens_label": "Nursery",
							"target": 3,
							"rabbits_per_group": 3,
							"minimum_separation": 240.0,
							"minimum_local_food": 8.0,
						},
					],
					"stabilization": 8.0,
					"labels": {
						"low": "The network needs more rabbits...",
						"evidence": "One more lasting home will complete the network...",
						"stabilizing": "The nursery network is holding...",
					},
					"guidance": "Use your nursery starters: place food at a separate site, then settle 3 rabbits together there. The rabbit preview counts nearby companions.",
					"teaser": "Tracks have appeared. Two hunters are waiting beyond the meadow.",
					"completion_message": "The nursery network is ready · Foxes have arrived",
					"effects": {
						"expand_world": WORLD_EXPANSION_STEP * 1.5,
						"unlock": ["fox"],
						"introduction": {"fox": 2},
						"supply_pool": "web",
						"arm_rabbit_failure": true,
					},
				},
				{
					"id": "hunt_and_recover",
					"tier": "major",
					"title": "Hunt and Recover",
					"summary": "Let both foxes feed, then rebuild the rabbit population.",
					"guide_intro": "Hunts and births may happen in any order. The challenge is to support both predators while ending with at least as many rabbits as the act began with.",
					"goal_help": {
						"hunts": {
							"behavior": "SAVED · THIS CHECKPOINT",
							"detail": "Count successful fox hunts during this act. Hunts can occur before or after births.",
						},
						"recovery_births": {
							"behavior": "SAVED · THIS CHECKPOINT",
							"detail": "Count natural rabbit births during this act. Births can occur before or after hunts.",
						},
						"foxes_fed": {
							"behavior": "LIVING CREDIT · CAN FALL",
							"detail": "Two different living foxes must each make a successful hunt during this act.",
						},
						"population_recovery": {
							"behavior": "LIVE · CAN RISE OR FALL",
							"detail": "Return the colony to at least the rabbit population present when this act opened, with an absolute minimum of ten rabbits.",
						},
						"hold": {
							"behavior": "TOGETHER · TIMER RESETS",
							"detail": "Once both foxes have hunted, births have occurred, and the colony has recovered, keep those outcomes together through the hold.",
						},
					},
					"display_populations": ["rabbit", "fox"],
					"rabbit_min": 0,
					"fox_min": 0,
					"criteria": [
						{
							"id": "hunts",
							"type": "hunts",
							"label": "Successful hunts",
							"metric_label": "HUNTS",
							"target": 2,
						},
						{
							"id": "recovery_births",
							"type": "rabbit_birth",
							"label": "Rabbit births",
							"metric_label": "BIRTHS",
							"target": 2,
						},
						{
							"id": "foxes_fed",
							"type": "distinct_foxes_fed",
							"label": "Different foxes hunt",
							"metric_label": "FOXES FED",
							"target": 2,
						},
						{
							"id": "population_recovery",
							"type": "population_recovery",
							"label": "Rabbit population recovered",
							"metric_label": "COLONY RECOVERY",
							"minimum": 10,
						},
					],
					"stabilization": 22.0,
					"labels": {
						"evidence": "The new food-web rhythm is still forming...",
						"stabilizing": "Both hunters and the new generation are holding...",
					},
					"guidance": "Let both foxes hunt, keep forage productive, and help the rabbit colony replace its losses. The events no longer need a lucky order.",
					"teaser": "The final act asks the whole meadow to stay productive during one living window.",
					"completion_message": "Hunt recovery proven · Transplant charge gained",
					"effects": {
						"expand_world": WORLD_EXPANSION_STEP * 2.0,
						"supply_pool": "living",
						"transplant_charges": 1,
					},
				},
				{
					"id": "living_balance",
					"tier": "final",
					"title": "Living Balance",
					"summary": "Keep 2 nurseries thriving while births and hunts share one living window.",
					"guide_intro": "The final proof measures outcomes, not event order. Build enough forage and refuge that three births and three hunts can coexist within the same recent window.",
					"goal_help": {
						"safe_havens": {
							"behavior": "LIVE · CAN RISE OR FALL",
							"detail": "A nursery is at least three rabbits gathered around enough usable nearby food. Keep two separated groups thriving through predator pressure. Your third home provides a reserve when one group scatters; numbered cradle markers show the groups that count now.",
						},
						"living_window": {
							"behavior": "RECENT WINDOW · UPDATES LIVE",
							"detail": "Within the same recent 150 seconds, record three natural births and three successful hunts while at least two foxes and twelve rabbits remain alive. Event order does not matter.",
						},
						"prey_balance": {
							"behavior": "LIVE · CAN RISE OR FALL",
							"detail": "Keep at least five rabbits for every living fox. This protects the prey base without requiring a specific event sequence.",
						},
						"rabbit_health": {
							"behavior": "LIVE · CAN RISE OR FALL",
							"detail": "Keep severe rabbit starvation below one fifth of the living colony during the final hold.",
						},
						"hold": {
							"behavior": "TOGETHER · TIMER RESETS",
							"detail": "Keep the nurseries, recent birth-and-hunt window, prey balance, and rabbit health true together for the final hold.",
						},
					},
					"display_populations": ["rabbit", "fox"],
					"rabbit_min": 0,
					"fox_min": 0,
					"criteria": [
						{
							"id": "safe_havens",
							"type": "safe_havens",
							"label": "Separated nurseries",
							"metric_label": "NURSERIES",
							"lens_label": "Nursery",
							"target": 2,
							"rabbits_per_group": 3,
							"minimum_separation": 240.0,
							"minimum_local_food": 10.0,
						},
						{
							"id": "living_window",
							"type": "ecology_window",
							"label": "Living birth-and-hunt window",
							"metric_label": "LIVING WINDOW",
							"window": 150.0,
							"birth_target": 3,
							"hunt_target": 3,
							"rabbit_minimum": 12,
							"fox_minimum": 2,
						},
						{
							"id": "prey_balance",
							"type": "prey_per_fox",
							"label": "Rabbits per fox",
							"metric_label": "PREY BALANCE",
							"target": 5,
						},
					],
					"forbid_active_starvation": true,
					# The 150-second ecology window already proves persistence; this short
					# confirmation prevents a transient frame without adding another wait.
					"stabilization": 4.0,
					"labels": {
						"evidence": "The living web still needs fresh renewal...",
						"stabilizing": "The whole meadow is holding together...",
					},
					"guidance": "Keep two nurseries thriving through the hunts; the third home is your reserve. Support both foxes while births replace the losses.",
					"teaser": "What happens next belongs to the meadow.",
					"completion_message": "Ecosystem Established",
					"effects": {"complete_run": true},
				},
			],
			"critical": {
				"breeding_group": 2,
				"entry_debounce": 4.0,
				"recovery_population": 2,
				"recovery_settling": 8.0,
				"grace_duration": 45.0,
				"first_rescue_delay": 6.0,
				"recent_event_window": 90.0,
			},
		},
	}
