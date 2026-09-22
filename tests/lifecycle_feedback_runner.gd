extends SceneTree

var passed := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("PASS: " + label)
	else:
		failures.append(label)
		printerr("FAILED: " + label)

func _run() -> void:
	var cfg := GameConfig.make()
	cfg["terrain"]["stream"]["enabled"] = false
	cfg["rabbit"]["move_speed"] = 0.0
	cfg["rabbit"]["hunger_rate"] = 0.0
	cfg["supply"]["interval"] = 9999.0
	var systems := GameSystems.new(cfg)
	var hud := GameHUD.new()
	root.add_child(hud)
	hud.setup(systems)
	var world := WorldView.new()
	root.add_child(world)
	world.setup(systems)
	var id := systems.simulation.add_rabbit(Vector2.ZERO)
	var animal: Dictionary = systems.simulation.rabbits[id]
	animal["reproduction_cooldown"] = 0.0
	animal["recent_food"] = 0.0
	systems.advance(0.6)
	hud.show_animal("rabbit", id)
	hud.refresh()
	_check(hud.animal_birth_label.text.contains("Building food reserves") and hud.rabbit_hunger_label.text == "Well fed", "comfortable hunger no longer promises a birth; field note explains reserves")
	var family_progress := {"milestone_id": "first_family", "rabbit_target": 5, "rabbit_count": 4, "birth_count": 0, "birth_target": 2}
	var coach := hud._checkpoint_action({}, family_progress)
	_check(str(coach["title"]).contains("Building food reserves") and not str(coach["detail"]).contains("Place them"), "First Family coaches the live birth blocker instead of asking for unavailable rabbits")
	systems.family_watch()
	var revision_before := systems.life_revision
	systems.set_speed(0.0)
	systems.simulation.add_plant("carrot_patch", Vector2(20.0, 0.0))
	_check(systems.life_revision > revision_before and systems._family_watch_time == -INF, "paused placement invalidates cached family guidance")
	animal["age"] = float(animal["lifespan"]) * 0.79
	systems.set_speed(1.0)
	systems.advance(0.6)
	hud.refresh()
	_check(_has_story(systems, "elder", id) and hud.animal_life_label.text.contains("Clock badge"), "elder warning precedes death and the field note explains the clock")
	var name: String = animal["name"]
	animal["age"] = float(animal["lifespan"]) - 0.05
	systems.advance(0.1)
	hud.refresh()
	_check(hud.inspected_animal_id == id and hud.animal_status_label.text == "Died of old age" and not hud.animal_follow_button.visible, "a selected animal becomes a named memorial instead of disappearing from the inspector")
	_check(systems.latest_loss["name"] == name and hud.rabbit_hunger_label.text.contains("old age") and _has_story(systems, "death", id), "population loss, journal and memorial agree on the actual cause")
	var newborn := systems.simulation.add_rabbit(Vector2(45.0, 0.0), "birth", [id])
	_check(str(systems.ecology_stories[0]["description"]).contains(name), "birth announcement retains the named deceased parent")
	for index in range(12): systems.simulation.add_rabbit(Vector2(100.0 + index, 0.0))
	hud.hide_animal()
	hud.process_visual(9.0)
	_check(hud.last_loss_button.visible and hud.last_loss_button.text.contains(name), "latest loss remains accessible after the transient notice and newer arrivals")
	hud._inspect_last_loss()
	_check(hud.animal_name_label.text == name and hud.animal_status_label.text.contains("old age"), "last-loss action reopens the preserved cause")
	hud.hide_animal()
	hud._open_life_journal()
	_check(hud.journal_panel.visible and not hud.story_panel.visible and not hud.animal_panel.visible and hud.journal_entries.get_child_count() > 12, "journal exposes older events without overlapping the overview or field note")
	var reading_entry := hud.journal_entries.get_child(0)
	var hungry := systems.simulation.add_rabbit(Vector2(250.0, 0.0))
	systems.simulation.rabbits[hungry]["hunger"] = 60.0
	systems.advance(0.6)
	_check(_has_story(systems, "hunger_warning", hungry), "food distress receives a named warning before starvation")
	_check(is_instance_valid(reading_entry) and reading_entry.get_parent() == hud.journal_entries, "incoming events preserve the open journal's rows and keyboard focus")
	systems.simulation.kill_rabbit(hungry, "starvation")
	hud.show_animal("rabbit", hungry)
	_check(hud.animal_status_label.text == "Died from starvation" and hud.animal_activity_label.text.contains("fresh forage"), "starvation memorial explains the corrective action")
	var caught := systems.simulation.add_rabbit(Vector2(280.0, 0.0))
	systems.simulation.kill_rabbit(caught, "predation")
	hud.show_animal("rabbit", caught)
	_check(hud.animal_status_label.text == "Caught by a fox", "predation has a distinct explanation")
	var removed := systems.simulation.add_rabbit(Vector2(300.0, 0.0))
	var loss_before: Dictionary = systems.latest_loss.duplicate()
	var stories_before := systems.ecology_stories.size()
	systems.simulation.kill_rabbit(removed, "undo")
	_check(systems.ecology_stories.size() == stories_before and systems.latest_loss == loss_before, "undo never creates a false loss or replaces the last loss")
	world.process_visual(4.0)
	var newborn_visible := false
	for effect in world.ambient_effects:
		if int(effect.get("entity_id", -1)) == newborn and effect["type"] == "birth": newborn_visible = true
	_check(newborn_visible, "birth announcement remains visible for multiple real seconds")
	world.process_visual(2.1)
	var life_labels := 0
	for effect in world.ambient_effects:
		if effect["type"] in ["birth", "death"]: life_labels += 1
	_check(life_labels == 0, "world announcements expire without lingering labels")
	await process_frame
	hud.free()
	world.free()
	print("%d lifecycle feedback checks passed; %d failed." % [passed, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _has_story(systems: GameSystems, type: String, id: int) -> bool:
	for story in systems.ecology_stories:
		if story["type"] == type and int(story["entity_id"]) == id: return true
	return false
