extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	var config := GameConfig.make()
	config["terrain"]["stream"]["enabled"] = false
	var systems := GameSystems.new(config)
	var view := WorldView.new()
	view.setup(systems)
	view.details = [{"kind": "tree", "position": Vector2.ZERO, "size": 1.0, "tone": 0.5}]
	var behind := systems.simulation.add_rabbit(Vector2(0.0, -10.0))
	var front := systems.simulation.add_fox(Vector2(0.0, 55.0))
	systems.simulation.add_plant("berry_bush", Vector2(0.0, 5.0))
	var pieces := view._build_scene_pieces()
	var kinds: Array = []
	for piece in pieces:
		kinds.append(piece["kind"])
	check(kinds == ["animal", "tree", "plant", "animal"], "animals, trees and plants share one ground-depth ordering")
	check(view._foliage_alpha(Vector2.ZERO, 28.0, 0.30) < 0.5, "a creature behind a canopy reveals itself through the foliage")
	systems.simulation.rabbits.erase(behind)
	view._build_scene_pieces()
	check(is_equal_approx(view._foliage_alpha(Vector2.ZERO, 28.0, 0.30), 1.0), "a creature clear of the crown does not fade distant scenery")
	var fixed_position: Vector2 = view.details[0]["position"]
	view.display_radius = 500.0
	systems.simulation.world_radius = 500.0
	view._build_scene_pieces()
	check(view.details[0]["position"] == fixed_position, "world expansion preserves scenery anchors")
	var fox: Dictionary = systems.simulation.foxes[front]
	view.spawn_effects.clear()
	fox["age"] = 0.0
	var juvenile := view._animal_scale(fox)
	fox["age"] = 30.0
	check(juvenile < view._animal_scale(fox) * 0.7, "the art integration preserves juvenile sizing")
	view.free()
	print("%d scene depth checks passed; %d failed." % [passed, failed])
	quit(0 if failed == 0 else 1)

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		printerr("FAILED: " + label)
