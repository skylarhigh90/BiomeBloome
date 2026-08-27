class_name GameHUD
extends CanvasLayer

signal inventory_selected(item: String)
signal speed_selected(speed: float)
signal supply_selected(index: int)
signal restart_requested

var systems: GameSystems
var root: Control
var objective_title: Label
var objective_body: Label
var population_label: Label
var supply_countdown: Label
var inventory_buttons: Dictionary = {}
var speed_buttons: Dictionary = {}
var supply_overlay: ColorRect
var supply_title: Label
var supply_buttons: Array = []
var toast_panel: PanelContainer
var toast_label: Label
var debug_panel: PanelContainer
var debug_label: Label
var restart_button: Button
var restart_confirmation_time := 0.0
var toast_time := 0.0

const ITEM_LABELS := {
	"rabbit": "Rabbit",
	"fox": "Fox",
	"grass": "Grass",
	"berry_bush": "Berry Bush",
}

func setup(p_systems: GameSystems) -> void:
	systems = p_systems
	_build_interface()
	systems.inventory_changed.connect(refresh)
	systems.supply_ready.connect(show_supply_choices)
	systems.supply_claimed.connect(_on_supply_claimed)
	systems.objective_completed.connect(_on_objective_completed)
	refresh()

func _build_interface() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var objective_panel := _make_panel(Vector2(272.0, 124.0), Color(0.055, 0.085, 0.067, 0.88))
	objective_panel.position = Vector2(18.0, 18.0)
	root.add_child(objective_panel)
	var objective_box := VBoxContainer.new()
	objective_box.add_theme_constant_override("separation", 6)
	objective_panel.add_child(objective_box)
	objective_title = _make_label("Stage 1 · Establish", 18, Color("#f2ecd9"))
	objective_title.add_theme_font_size_override("font_size", 18)
	objective_box.add_child(objective_title)
	objective_body = _make_label("Rabbit 0 / 8\nStable 0 / 15 sec", 14, Color("#c9d7c2"))
	objective_box.add_child(objective_body)

	var population_panel := _make_panel(Vector2(240.0, 48.0), Color(0.055, 0.085, 0.067, 0.82))
	population_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	population_panel.position = Vector2(-120.0, 18.0)
	root.add_child(population_panel)
	population_label = _make_label("Rabbits 0   ·   Foxes 0", 15, Color("#f2ecd9"))
	population_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	population_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	population_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	population_panel.add_child(population_label)

	var supply_panel := _make_panel(Vector2(230.0, 52.0), Color(0.055, 0.085, 0.067, 0.82))
	supply_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	supply_panel.position = Vector2(-248.0, 18.0)
	root.add_child(supply_panel)
	supply_countdown = _make_label("Next supply: 60s", 14, Color("#d6e5ca"))
	supply_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	supply_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	supply_countdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	supply_panel.add_child(supply_countdown)

	restart_button = _make_button("Restart", Vector2(92.0, 34.0), false)
	restart_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	restart_button.position = Vector2(-110.0, 87.0)
	restart_button.modulate = Color(1, 1, 1, 0.68)
	restart_button.pressed.connect(_on_restart_pressed)
	root.add_child(restart_button)

	var inventory_panel := _make_panel(Vector2(590.0, 82.0), Color(0.045, 0.072, 0.055, 0.91))
	inventory_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	inventory_panel.position = Vector2(-295.0, -100.0)
	root.add_child(inventory_panel)
	var inventory_box := HBoxContainer.new()
	inventory_box.add_theme_constant_override("separation", 8)
	inventory_panel.add_child(inventory_box)
	for item in ["rabbit", "fox", "grass", "berry_bush"]:
		var button := _make_button("", Vector2(132.0, 56.0), true)
		button.pressed.connect(_on_inventory_pressed.bind(item))
		inventory_box.add_child(button)
		inventory_buttons[item] = button

	var speed_panel := _make_panel(Vector2(260.0, 58.0), Color(0.045, 0.072, 0.055, 0.88))
	speed_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_panel.position = Vector2(-278.0, -76.0)
	root.add_child(speed_panel)
	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 6)
	speed_panel.add_child(speed_box)
	for entry in [[0.0, "Pause"], [1.0, "1×"], [2.0, "2×"], [3.0, "3×"]]:
		var button := _make_button(entry[1], Vector2(54.0 if entry[0] > 0.0 else 70.0, 36.0), true)
		button.pressed.connect(_on_speed_pressed.bind(entry[0]))
		speed_box.add_child(button)
		speed_buttons[entry[0]] = button

	_build_supply_overlay()
	_build_toast()
	_build_debug_panel()

func _make_panel(minimum_size: Vector2, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 13
	style.corner_radius_top_right = 13
	style.corner_radius_bottom_left = 13
	style.corner_radius_bottom_right = 13
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.68, 0.8, 0.62, 0.15)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _make_button(text_value: String, minimum_size: Vector2, stronger: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color("#edf1e5"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.19, 0.30, 0.23, 0.96) if stronger else Color(0.16, 0.23, 0.19, 0.76)
	normal.corner_radius_top_left = 9
	normal.corner_radius_top_right = 9
	normal.corner_radius_bottom_left = 9
	normal.corner_radius_bottom_right = 9
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.65, 0.78, 0.58, 0.16)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.28, 0.43, 0.31, 0.98)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.42, 0.57, 0.34, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	return button

func _build_supply_overlay() -> void:
	supply_overlay = ColorRect.new()
	supply_overlay.color = Color(0.02, 0.035, 0.025, 0.58)
	supply_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	supply_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	supply_overlay.visible = false
	root.add_child(supply_overlay)
	var panel := _make_panel(Vector2(500.0, 232.0), Color(0.07, 0.11, 0.085, 0.98))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-250.0, -116.0)
	supply_overlay.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	supply_title = _make_label("New life arrives", 23, Color("#f5ecd6"))
	supply_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(supply_title)
	var hint := _make_label("Choose one supply bundle. The ecosystem keeps moving.", 13, Color("#bdccb6"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	var choice_box := HBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 12)
	box.add_child(choice_box)
	for index in range(2):
		var button := _make_button("", Vector2(220.0, 112.0), true)
		button.pressed.connect(_on_supply_pressed.bind(index))
		choice_box.add_child(button)
		supply_buttons.append(button)

func _build_toast() -> void:
	toast_panel = _make_panel(Vector2(360.0, 66.0), Color(0.12, 0.20, 0.13, 0.96))
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.position = Vector2(-180.0, 82.0)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	root.add_child(toast_panel)
	toast_label = _make_label("Stage complete", 19, Color("#f6e6a9"))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast_panel.add_child(toast_label)

func _build_debug_panel() -> void:
	debug_panel = _make_panel(Vector2(320.0, 150.0), Color(0.025, 0.04, 0.032, 0.92))
	debug_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	debug_panel.position = Vector2(18.0, -168.0)
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_panel.visible = false
	root.add_child(debug_panel)
	debug_label = _make_label("Debug", 12, Color("#c6e7bd"))
	debug_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debug_panel.add_child(debug_label)

func refresh() -> void:
	if systems == null:
		return
	population_label.text = "Rabbits %d   ·   Foxes %d" % [systems.simulation.population("rabbit"), systems.simulation.population("fox")]
	for item in inventory_buttons:
		var count: int = systems.inventory.get(item, 0)
		var button: Button = inventory_buttons[item]
		button.text = "%s\n×%d" % [ITEM_LABELS[item], count]
		button.disabled = count <= 0
		_set_button_selected(button, systems.selected_item == item)
	for speed in speed_buttons:
		_set_button_selected(speed_buttons[speed], is_equal_approx(float(speed), systems.simulation_speed))
	if systems.ecosystem_established:
		objective_title.text = "Ecosystem established"
		objective_body.text = "Sandbox continues · keep observing"
	else:
		var objective := systems.current_objective()
		objective_title.text = "Stage %d · %s" % [systems.objective_index + 1, objective["name"]]
		var lines: Array[String] = []
		for kind in objective["targets"]:
			lines.append("%s %d / %d" % [kind.capitalize(), systems.simulation.population(kind), objective["targets"][kind]])
		lines.append("Stable %d / %d sec" % [floori(systems.objective_stability), int(objective["duration"])])
		objective_body.text = "\n".join(lines)
	if systems.supply_pending:
		supply_countdown.text = "Supply ready · choose a bundle"
	else:
		supply_countdown.text = "Next supply: %ds" % ceili(systems.supply_time_remaining)

func _set_button_selected(button: Button, selected: bool) -> void:
	if selected:
		button.self_modulate = Color(1.12, 1.12, 0.88, 1.0)
		button.add_theme_color_override("font_color", Color("#fff3bd"))
	else:
		button.self_modulate = Color.WHITE
		button.add_theme_color_override("font_color", Color("#edf1e5"))

func process_visual(delta: float) -> void:
	if restart_confirmation_time > 0.0:
		restart_confirmation_time -= delta
		if restart_confirmation_time <= 0.0:
			restart_button.text = "Restart"
			restart_button.modulate = Color(1, 1, 1, 0.68)
	if toast_time > 0.0:
		toast_time -= delta
		var fade := clampf(toast_time / 0.5, 0.0, 1.0) if toast_time < 0.5 else 1.0
		toast_panel.modulate = Color(1, 1, 1, fade)
		if toast_time <= 0.0:
			toast_panel.visible = false
	refresh()

func show_supply_choices(choices: Array) -> void:
	for index in range(mini(2, choices.size())):
		var bundle: Dictionary = choices[index]
		supply_buttons[index].text = "%s\n\n%s" % [bundle["name"], _format_items(bundle["items"])]
	supply_overlay.visible = true

func _format_items(items: Dictionary) -> String:
	var pieces: Array[String] = []
	for item in items:
		pieces.append("%s ×%d" % [ITEM_LABELS[item], items[item]])
	return "  ·  ".join(pieces)

func _on_inventory_pressed(item: String) -> void:
	inventory_selected.emit(item)

func _on_speed_pressed(speed: float) -> void:
	speed_selected.emit(speed)

func _on_supply_pressed(index: int) -> void:
	supply_selected.emit(index)
	supply_overlay.visible = false

func _on_supply_claimed(bundle: Dictionary) -> void:
	show_toast("%s added to your hand" % bundle["name"], 2.2)

func _on_objective_completed(index: int, objective_name: String) -> void:
	var message := "Ecosystem established" if systems.ecosystem_established else "%s complete · the world lives on" % objective_name
	show_toast(message, 3.2 if systems.ecosystem_established else 2.6)

func show_toast(message: String, duration: float = 2.4) -> void:
	toast_label.text = message
	toast_time = duration
	toast_panel.modulate = Color.WHITE
	toast_panel.visible = true

func _on_restart_pressed() -> void:
	if restart_confirmation_time > 0.0:
		restart_requested.emit()
		return
	restart_confirmation_time = 3.0
	restart_button.text = "Confirm"
	restart_button.modulate = Color(1.0, 0.82, 0.72, 0.95)

func set_debug_visible(enabled: bool) -> void:
	debug_panel.visible = enabled

func update_debug(text_value: String) -> void:
	debug_label.text = text_value
