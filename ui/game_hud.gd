class_name GameHUD
extends CanvasLayer

signal inventory_selected(item: String)
signal speed_selected(speed: float)
signal supply_selected(index: int)
signal restart_requested
signal continue_requested

const Glyph = preload("res://ui/entity_glyph.gd")
const RewardBurst = preload("res://ui/reward_burst.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")
const HUDStat = preload("res://ui/components/hud_stat.gd")
const HUDStatus = preload("res://ui/components/hud_status.gd")
const InstructionCallout = preload("res://ui/components/instruction_callout.gd")
const InventoryCard = preload("res://ui/components/inventory_card.gd")
const RewardChoiceCard = preload("res://ui/components/reward_choice_card.gd")
const IconTextButton = preload("res://ui/components/icon_text_button.gd")

const SUPPLY_SHEET_SIZE := Vector2(884.0, 500.0)
const POPULATION_PANEL_SIZE := Vector2(410.0, 66.0)

const ITEM_LABELS := {
	"rabbit": "Rabbit",
	"fox": "Fox",
	"carrot_patch": "Carrot patch",
	"berry_bush": "Berry bush",
}

const ITEM_HINTS := {
	"rabbit": "Place a forager near food and shelter",
	"fox": "Place a predator near a healthy rabbit colony",
	"carrot_patch": "Quick-growing, low-capacity food for nearby rabbits",
	"berry_bush": "Dense, slowly renewing forage",
}

var systems: GameSystems
var root: Control

var objective_panel: PanelContainer
var objective_eyebrow: Label
var objective_title: Label
var objective_body: Label
var objective_teaser: Label
var objective_requirements_heading: Label
var objective_goal_rows: Dictionary = {}
var objective_goal_values: Dictionary = {}
var objective_goal_checks: Dictionary = {}
var objective_evidence_row: HBoxContainer
var objective_evidence_check: Label
var objective_evidence_title: Label
var objective_evidence_value: Label
var objective_evidence: Label
var objective_steps_box: VBoxContainer
var objective_steps: Array = []
var objective_trend_row: HBoxContainer
var objective_trend_check: Label
var objective_trend_value: Label
var objective_progress_row: VBoxContainer
var objective_progress: ProgressBar
var objective_progress_label: Label
var objective_progress_value: Label
var objective_progress_hint: Label
var objective_progress_target := 0.0
var objective_coach_panel: PanelContainer
var objective_callout
var objective_coach_detail: Label
var objective_coach_glyph: Control
var objective_layout_mode := ""
var last_objective_id := ""
var last_sequence_progress := 0

var population_panel: PanelContainer
var population_labels: Dictionary = {}
var last_populations := {"rabbit": -1, "fox": -1}
var rabbit_hunger_label: Label
var last_rabbit_hunger_state := ""
var last_rabbit_starving_count := -1
var rabbit_starvation_losses := 0
var rabbit_loss_notice_time := 0.0

var supply_panel: PanelContainer
var supply_countdown: Label
var supply_progress: ProgressBar
var restart_button: Button

var inventory_panel: PanelContainer
var inventory_buttons: Dictionary = {}
var inventory_counts: Dictionary = {}
var inventory_count_labels: Dictionary = {}
var inventory_icons: Dictionary = {}
var inventory_selected_marks: Dictionary = {}
var inventory_width := 590.0
var placement_hint: PanelContainer
var placement_hint_label: Label

var speed_panel: PanelContainer
var speed_buttons: Dictionary = {}

var supply_overlay: ColorRect
var supply_burst: Control
var supply_sheet: PanelContainer
var supply_title: Label
var supply_subtitle: Label
var supply_resume_hint: Label
var supply_peek_button: Button
var supply_peek_hud: PanelContainer
var supply_return_button: Button
var supply_buttons: Array = []
var supply_card_titles: Array = []
var supply_card_roles: Array = []
var supply_card_contents: Array = []
var supply_peeking := false
var supply_claiming := false
var supply_focus_index := 0

var toast_panel: PanelContainer
var toast_label: Label
var debug_panel: PanelContainer
var debug_label: Label
var critical_panel: PanelContainer
var critical_label: Label
var ending_overlay: ColorRect
var ending_panel: PanelContainer
var ending_title: Label
var ending_body: Label
var continue_button: Button
var new_ecosystem_button: Button

var restart_confirmation_time := 0.0
var toast_time := 0.0

func setup(p_systems: GameSystems) -> void:
	systems = p_systems
	_build_interface()
	systems.inventory_changed.connect(refresh)
	systems.unlocks_changed.connect(refresh)
	systems.supply_ready.connect(show_supply_choices)
	systems.supply_claimed.connect(_on_supply_claimed)
	systems.milestone_completed.connect(_on_milestone_completed)
	systems.critical_started.connect(_on_critical_started)
	systems.critical_recovered.connect(_on_critical_recovered)
	systems.run_failed.connect(_on_run_failed)
	systems.run_completed.connect(_on_run_completed)
	systems.simulation.entity_removed.connect(_on_entity_removed)
	refresh()
	_layout_interface.call_deferred()

func _build_interface() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ThemeSystem.create()
	add_child(root)

	_build_objective_card()
	_build_population_pulse()
	_build_supply_indicator()
	_build_inventory_satchel()
	_build_time_controls()
	_build_supply_overlay()
	_build_toast()
	_build_debug_panel()
	_build_critical_panel()
	_build_ending_overlay()
	root.resized.connect(_layout_interface)

func _build_objective_card() -> void:
	objective_panel = _make_panel(Vector2(410.0, 0.0), "SurfaceStandard")
	root.add_child(objective_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	objective_panel.add_child(box)

	objective_eyebrow = _make_label("MILESTONE 01", "eyebrow")
	box.add_child(objective_eyebrow)
	objective_title = _make_label("Grow a self-sustaining rabbit colony", "h1")
	objective_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective_title)
	objective_body = _make_label("Raise a new generation and keep the colony stable.", "body")
	objective_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective_body)

	objective_evidence_row = HBoxContainer.new()
	objective_evidence_row.custom_minimum_size.y = 20.0
	box.add_child(objective_evidence_row)
	objective_evidence_title = _make_label("PROVE THE COLONY", "eyebrow")
	objective_evidence_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_evidence_row.add_child(objective_evidence_title)
	objective_evidence_value = _make_label("0 / 1", "caption")
	objective_evidence_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	objective_evidence_row.add_child(objective_evidence_value)
	objective_evidence_check = _make_requirement_check()
	objective_evidence_check.visible = false

	objective_steps_box = VBoxContainer.new()
	objective_steps_box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	box.add_child(objective_steps_box)
	for index in range(4):
		objective_steps.append(_make_objective_step(index))

	objective_evidence = _make_label("Only a natural birth counts — placing a rabbit does not.", "caption")
	objective_evidence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective_evidence)

	objective_requirements_heading = _make_label("KEEP HEALTHY", "eyebrow")
	box.add_child(objective_requirements_heading)

	for kind in ["rabbit", "fox"]:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, 23.0)
		row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
		box.add_child(row)
		var check := _make_requirement_check()
		row.add_child(check)
		var glyph: Control = Glyph.new().configure(kind, Color.TRANSPARENT, false)
		glyph.custom_minimum_size = Vector2(23.0, 23.0)
		row.add_child(glyph)
		var population_label := "Rabbits alive" if kind == "rabbit" else "Foxes alive"
		var name_label := _make_label(population_label, "label_strong")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		var value := _make_label("0 / 0", "label_strong")
		value.custom_minimum_size.x = 62.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		objective_goal_rows[kind] = row
		objective_goal_values[kind] = value
		objective_goal_checks[kind] = check

	objective_trend_row = _make_requirement_row(box, "Rabbit population")
	objective_trend_check = objective_trend_row.get_meta("check")
	objective_trend_value = objective_trend_row.get_meta("value")

	objective_progress_row = VBoxContainer.new()
	objective_progress_row.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	box.add_child(objective_progress_row)
	var progress_heading := HBoxContainer.new()
	objective_progress_row.add_child(progress_heading)
	objective_progress_label = _make_label("THEN HOLD THE COLONY", "eyebrow")
	objective_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_heading.add_child(objective_progress_label)
	objective_progress_value = _make_label("0 / 0 sec", "label_strong")
	objective_progress_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_heading.add_child(objective_progress_value)
	objective_progress = ProgressBar.new()
	objective_progress.custom_minimum_size = Vector2(0.0, 10.0)
	objective_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_progress.show_percentage = false
	objective_progress.theme_type_variation = "ProgressAccent"
	objective_progress_row.add_child(objective_progress)
	objective_progress_hint = _make_label("Starts when the birth and every health goal are complete.", "caption")
	objective_progress_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_progress_row.add_child(objective_progress_hint)

	objective_callout = InstructionCallout.new().configure(
		"DO THIS NOW",
		"Build the colony to 8 rabbits.",
		"Place rabbits near plentiful carrots or berries.",
		"rabbit"
	)
	objective_coach_panel = objective_callout
	objective_teaser = objective_callout.title_label
	objective_coach_detail = objective_callout.detail_label
	objective_coach_glyph = objective_callout.glyph
	box.add_child(objective_callout)

func _make_objective_step(index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "ObjectiveStepFuture"
	objective_steps_box.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	panel.add_child(row)
	var marker := _make_label(str(index + 1), "label_secondary")
	marker.custom_minimum_size = Vector2(19.0, 23.0)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(marker)
	var glyph: Control = Glyph.new().configure("rabbit", Color.TRANSPARENT, false)
	glyph.custom_minimum_size = Vector2(24.0, 24.0)
	row.add_child(glyph)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	row.add_child(copy)
	var title := _make_label("A baby rabbit is born", "label_strong")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(title)
	var helper := _make_label("Keep two well-fed adult rabbits near forage.", "caption")
	helper.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(helper)
	var state := _make_label("NEXT", "eyebrow_accent")
	state.custom_minimum_size.x = 34.0
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(state)
	return {"panel": panel, "marker": marker, "glyph": glyph, "title": title, "helper": helper, "state": state}

func _make_requirement_check() -> Label:
	var check := _make_label("○", "label_secondary")
	check.custom_minimum_size.x = 17.0
	check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return check

func _make_requirement_row(parent: VBoxContainer, title_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 23.0)
	row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	parent.add_child(row)
	var check := _make_requirement_check()
	row.add_child(check)
	var title := _make_label(title_text, "label_strong")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var value := _make_label("0 / 0", "label_strong")
	value.custom_minimum_size.x = 72.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	row.set_meta("check", check)
	row.set_meta("title", title)
	row.set_meta("value", value)
	return row

func _build_population_pulse() -> void:
	population_panel = _make_panel(POPULATION_PANEL_SIZE, "SurfaceHUDLight")
	root.add_child(population_panel)
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.large)
	population_panel.add_child(box)
	for kind in ["rabbit", "fox"]:
		var stat: Control = HUDStat.new().configure(kind)
		box.add_child(stat)
		population_labels[kind] = stat.value_label
	var divider := VSeparator.new()
	divider.custom_minimum_size = Vector2(1.0, 34.0)
	box.add_child(divider)
	var status: Control = HUDStatus.new().configure("RABBIT FORAGE", "Well fed")
	status.custom_minimum_size.x = 150.0
	box.add_child(status)
	rabbit_hunger_label = status.primary_label

func _build_supply_indicator() -> void:
	supply_panel = _make_panel(Vector2(235.0, 66.0), "SurfaceInformation")
	root.add_child(supply_panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	supply_panel.add_child(box)
	var glyph: Control = Glyph.new().configure("supply", ThemeSystem.COLOR.info)
	glyph.custom_minimum_size = Vector2(40.0, 40.0)
	box.add_child(glyph)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	box.add_child(text_box)
	supply_countdown = _make_label("New supplies in 75", "label_strong")
	text_box.add_child(supply_countdown)
	supply_progress = ProgressBar.new()
	supply_progress.custom_minimum_size = Vector2(0.0, 7.0)
	supply_progress.show_percentage = false
	supply_progress.theme_type_variation = "ProgressInformation"
	text_box.add_child(supply_progress)

	restart_button = _make_button("↻", Vector2(44.0, 44.0), "icon")
	restart_button.tooltip_text = "Restart ecosystem (press twice to confirm)"
	restart_button.pressed.connect(_on_restart_pressed)
	root.add_child(restart_button)

func _build_inventory_satchel() -> void:
	inventory_panel = _make_panel(Vector2(712.0, 108.0), "SurfaceHUD")
	root.add_child(inventory_panel)
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	inventory_panel.add_child(box)
	for item in ["rabbit", "fox", "carrot_patch", "berry_bush"]:
		var card := _make_inventory_card(item)
		card.pressed.connect(_on_inventory_pressed.bind(item))
		box.add_child(card)
		inventory_buttons[item] = card
	placement_hint = _make_panel(Vector2(340.0, 42.0), "SurfaceCallout")
	placement_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placement_hint.visible = false
	root.add_child(placement_hint)
	placement_hint_label = _make_label("Placing Carrot patch  •  click the meadow", "label_strong")
	placement_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placement_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placement_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placement_hint.add_child(placement_hint_label)

func _make_inventory_card(item: String) -> Button:
	var button = InventoryCard.new().configure(item, ITEM_LABELS[item], ITEM_HINTS[item])
	inventory_icons[item] = button.glyph
	inventory_count_labels[item] = button.count_label
	inventory_selected_marks[item] = button.selected_mark
	return button

func _build_time_controls() -> void:
	speed_panel = _make_panel(Vector2(238.0, 62.0), "SurfaceHUD")
	root.add_child(speed_panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	speed_panel.add_child(box)
	for entry in [[0.0, "Ⅱ"], [1.0, "1×"], [2.0, "2×"], [3.0, "3×"]]:
		var button := _make_button(entry[1], Vector2(47.0, 38.0), "compact")
		button.tooltip_text = "Pause" if entry[0] == 0.0 else "Run at %s speed" % entry[1]
		button.pressed.connect(_on_speed_pressed.bind(entry[0]))
		box.add_child(button)
		speed_buttons[entry[0]] = button

func _build_supply_overlay() -> void:
	supply_overlay = ColorRect.new()
	supply_overlay.color = ThemeSystem.COLOR.scrim
	supply_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	supply_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	supply_overlay.visible = false
	supply_overlay.z_index = 80
	root.add_child(supply_overlay)
	supply_burst = RewardBurst.new()
	supply_burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	supply_overlay.add_child(supply_burst)

	supply_sheet = PanelContainer.new()
	supply_sheet.custom_minimum_size = SUPPLY_SHEET_SIZE
	supply_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	supply_sheet.theme_type_variation = "SurfaceRewardSheet"
	supply_sheet.set_anchors_preset(Control.PRESET_CENTER)
	supply_overlay.add_child(supply_sheet)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	supply_sheet.add_child(box)

	var heading := HBoxContainer.new()
	heading.custom_minimum_size.y = 90.0
	heading.add_theme_constant_override("separation", ThemeSystem.SPACE.medium)
	box.add_child(heading)
	var seal := PanelContainer.new()
	seal.custom_minimum_size = Vector2(86.0, 86.0)
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.theme_type_variation = "SurfaceRewardSeal"
	heading.add_child(seal)
	var seal_glyph: Control = Glyph.new().configure("supply", ThemeSystem.COLOR.moss.darkened(0.08), false)
	seal_glyph.custom_minimum_size = Vector2(76.0, 76.0)
	seal.add_child(seal_glyph)
	var heading_copy := VBoxContainer.new()
	heading_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_copy.alignment = BoxContainer.ALIGNMENT_CENTER
	heading_copy.add_theme_constant_override("separation", 0)
	heading.add_child(heading_copy)
	var eyebrow := _make_label("SUPPLIES ARRIVED  •  MEADOW PAUSED", "eyebrow_accent")
	heading_copy.add_child(eyebrow)
	supply_title = _make_label("Meadow Mail!", "display")
	heading_copy.add_child(supply_title)
	supply_subtitle = _make_label("Choose one bundle for your satchel. Take all the time you need.", "body")
	heading_copy.add_child(supply_subtitle)
	supply_peek_button = _make_peek_button("Peek at meadow", Vector2(184.0, 48.0), false)
	supply_peek_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	supply_peek_button.tooltip_text = "Hide these choices and inspect your paused meadow. Nothing will move."
	supply_peek_button.pressed.connect(_on_supply_peek_pressed)
	heading.add_child(supply_peek_button)

	var header_rule := ColorRect.new()
	header_rule.color = ThemeSystem.COLOR.border_subtle
	header_rule.custom_minimum_size.y = 1.0
	header_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header_rule)

	var choice_box := HBoxContainer.new()
	choice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	choice_box.add_theme_constant_override("separation", ThemeSystem.SPACE.large)
	choice_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(choice_box)
	for index in range(2):
		var button = RewardChoiceCard.new().configure(str(index + 1))
		button.pressed.connect(_on_supply_pressed.bind(index))
		choice_box.add_child(button)
		supply_buttons.append(button)
		supply_card_roles.append(button.role_label)
		supply_card_titles.append(button.title_label)
		supply_card_contents.append(button.contents)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size.y = 28.0
	box.add_child(footer)
	var controls_hint := _make_label("← / → move   •   Enter choose   •   E peek", "caption")
	controls_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(controls_hint)
	supply_resume_hint = _make_label("Nothing moves while you decide", "eyebrow")
	footer.add_child(supply_resume_hint)

	supply_peek_hud = PanelContainer.new()
	supply_peek_hud.custom_minimum_size = Vector2(430.0, 70.0)
	supply_peek_hud.mouse_filter = Control.MOUSE_FILTER_STOP
	supply_peek_hud.visible = false
	supply_peek_hud.z_index = 81
	supply_peek_hud.theme_type_variation = "SurfacePeekHUD"
	root.add_child(supply_peek_hud)
	var peek_row := HBoxContainer.new()
	peek_row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	supply_peek_hud.add_child(peek_row)
	var peek_glyph: Control = Glyph.new().configure("eye", ThemeSystem.COLOR.accent, false)
	peek_glyph.custom_minimum_size = Vector2(44.0, 44.0)
	peek_row.add_child(peek_glyph)
	var peek_copy := VBoxContainer.new()
	peek_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	peek_copy.alignment = BoxContainer.ALIGNMENT_CENTER
	peek_copy.add_theme_constant_override("separation", 0)
	peek_row.add_child(peek_copy)
	var peek_eyebrow := _make_label("MEADOW PAUSED", "eyebrow_on_dark")
	peek_copy.add_child(peek_eyebrow)
	var peek_label := _make_label("Inspect your ecosystem", "text_on_dark")
	peek_copy.add_child(peek_label)
	supply_return_button = _make_button("Back to rewards   E", Vector2(142.0, 44.0), "quiet")
	supply_return_button.tooltip_text = "Return to your supply choices"
	supply_return_button.pressed.connect(_on_supply_peek_pressed)
	peek_row.add_child(supply_return_button)

func _build_toast() -> void:
	toast_panel = _make_panel(Vector2(420.0, 70.0), "SurfaceToast")
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	root.add_child(toast_panel)
	toast_label = _make_label("A new chapter begins", "body_large")
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toast_panel.add_child(toast_label)

func _build_debug_panel() -> void:
	debug_panel = _make_panel(Vector2(470.0, 220.0), "SurfaceDebug")
	debug_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_panel.visible = false
	root.add_child(debug_panel)
	debug_label = _make_label("Debug", "debug")
	debug_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debug_panel.add_child(debug_label)

func _build_critical_panel() -> void:
	critical_panel = _make_panel(Vector2(460.0, 82.0), "SurfaceDanger")
	critical_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	critical_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	critical_panel.visible = false
	root.add_child(critical_panel)
	critical_label = _make_label("The rabbit lineage is fading\nPlace rabbits or choose a recovery supply.", "danger")
	critical_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	critical_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	critical_panel.add_child(critical_label)

func _build_ending_overlay() -> void:
	ending_overlay = ColorRect.new()
	ending_overlay.color = Color(ThemeSystem.COLOR.scrim.r, ThemeSystem.COLOR.scrim.g, ThemeSystem.COLOR.scrim.b, 0.52)
	ending_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ending_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ending_overlay.visible = false
	root.add_child(ending_overlay)
	ending_panel = _make_panel(Vector2(560.0, 324.0), "SurfaceElevated")
	ending_panel.set_anchors_preset(Control.PRESET_CENTER)
	ending_overlay.add_child(ending_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.large)
	ending_panel.add_child(box)
	var glyph: Control = Glyph.new().configure("leaf", ThemeSystem.COLOR.moss)
	glyph.custom_minimum_size = Vector2(52.0, 52.0)
	box.add_child(glyph)
	ending_title = _make_label("Ecosystem Established", "h1")
	ending_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ending_title)
	ending_body = _make_label("The ecosystem endures.", "body")
	ending_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ending_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ending_body.custom_minimum_size = Vector2(490.0, 78.0)
	box.add_child(ending_body)
	var button_box := HBoxContainer.new()
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	button_box.add_theme_constant_override("separation", ThemeSystem.SPACE.medium)
	box.add_child(button_box)
	continue_button = _make_button("Keep observing", Vector2(186.0, 44.0), "primary")
	continue_button.pressed.connect(_on_continue_pressed)
	button_box.add_child(continue_button)
	new_ecosystem_button = _make_button("New ecosystem", Vector2(174.0, 44.0), "secondary")
	new_ecosystem_button.pressed.connect(_on_new_ecosystem_pressed)
	button_box.add_child(new_ecosystem_button)

func _make_panel(minimum_size: Vector2, surface: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.theme_type_variation = surface
	return panel

func _make_label(text_value: String, role: String) -> Label:
	var label := Label.new()
	label.text = text_value
	var variations := {
		"display": "Display",
		"h1": "HeadingOne",
		"h1_danger": "HeadingOneDanger",
		"h2": "HeadingTwo",
		"h3": "HeadingThree",
		"body_large": "BodyLarge",
		"body": "Body",
		"body_secondary": "BodySecondary",
		"label_strong": "LabelStrong",
		"label_secondary": "LabelSecondary",
		"label_success": "LabelSuccess",
		"label_warning": "LabelWarning",
		"label_danger": "LabelDanger",
		"caption": "Caption",
		"caption_success": "CaptionSuccess",
		"caption_warning": "CaptionWarning",
		"caption_accent": "CaptionAccent",
		"eyebrow": "Eyebrow",
		"eyebrow_accent": "EyebrowAccent",
		"text_on_dark": "TextOnDark",
		"eyebrow_on_dark": "EyebrowOnDark",
		"numeric": "Numeric",
		"danger": "DangerText",
		"debug": "DebugText",
	}
	assert(variations.has(role), "Unknown Biome Bloom typography role: %s" % role)
	label.theme_type_variation = str(variations.get(role, "Body"))
	return label

func _make_button(text_value: String, minimum_size: Vector2, role: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_ALL
	button.theme_type_variation = {
		"primary": "PrimaryButton",
		"secondary": "SecondaryButton",
		"quiet": "QuietButton",
		"dark": "CompactButton",
		"compact": "CompactButton",
		"icon": "IconButton",
	}.get(role, "SecondaryButton")
	return button

func _make_peek_button(text_value: String, minimum_size: Vector2, dark: bool) -> Button:
	return IconTextButton.new().configure(text_value, minimum_size, dark)

func _layout_interface() -> void:
	if root == null:
		return
	var viewport_size := root.size
	var compact := viewport_size.x < 1030.0
	objective_panel.custom_minimum_size = Vector2(410.0, 0.0)
	objective_panel.reset_size()
	objective_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	objective_panel.position = Vector2(20.0, 20.0)
	population_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var population_x := maxf(
		(viewport_size.x - POPULATION_PANEL_SIZE.x) * 0.5,
		objective_panel.position.x + objective_panel.size.x + ThemeSystem.SPACE.large
	)
	population_panel.position = Vector2(population_x, 20.0) if not compact else Vector2(20.0, objective_panel.position.y + objective_panel.size.y + ThemeSystem.SPACE.medium)
	supply_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	supply_panel.position = Vector2(viewport_size.x - 307.0, 20.0)
	restart_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	restart_button.position = Vector2(viewport_size.x - 64.0, 31.0)
	inventory_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	inventory_panel.position = Vector2((viewport_size.x - inventory_width) * 0.5, viewport_size.y - 128.0) if not compact else Vector2(20.0, viewport_size.y - 128.0)
	placement_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	placement_hint.position = Vector2(inventory_panel.position.x + (inventory_width - 340.0) * 0.5, inventory_panel.position.y - 50.0)
	speed_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	speed_panel.position = Vector2(viewport_size.x - 258.0, viewport_size.y - 82.0)
	if viewport_size.x < 840.0:
		speed_panel.position = Vector2(viewport_size.x - 248.0, 95.0)
	toast_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toast_panel.position = Vector2((viewport_size.x - 420.0) * 0.5, 98.0)
	debug_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	debug_panel.position = Vector2(18.0, viewport_size.y - 238.0)
	critical_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	critical_panel.position = Vector2((viewport_size.x - 460.0) * 0.5, 176.0)
	supply_sheet.set_anchors_preset(Control.PRESET_TOP_LEFT)
	supply_sheet.position = Vector2((viewport_size.x - SUPPLY_SHEET_SIZE.x) * 0.5, (viewport_size.y - SUPPLY_SHEET_SIZE.y) * 0.5)
	supply_peek_hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	supply_peek_hud.position = Vector2(viewport_size.x - 448.0, 92.0)
	ending_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ending_panel.position = Vector2((viewport_size.x - 560.0) * 0.5, (viewport_size.y - 324.0) * 0.5)

func refresh() -> void:
	if systems == null:
		return
	_refresh_population()
	_refresh_inventory()
	_refresh_speeds()
	_refresh_objective()
	_refresh_supply()
	critical_panel.visible = systems.run_director.run_state == RunDirector.STATE_CRITICAL

func _refresh_population() -> void:
	for kind in ["rabbit", "fox"]:
		var count := systems.simulation.population(kind)
		var label: Label = population_labels[kind]
		label.text = str(count)
		if last_populations[kind] >= 0 and count != last_populations[kind]:
			_pulse_control(label, count > last_populations[kind])
		last_populations[kind] = count
	_refresh_rabbit_hunger()

func _refresh_rabbit_hunger() -> void:
	var summary: Dictionary = systems.simulation.hunger_summary("rabbit")
	var state := str(summary["state"])
	var starving_count := int(summary["starving_count"])
	if rabbit_loss_notice_time > 0.0:
		rabbit_hunger_label.text = "%d starved · add food" % rabbit_starvation_losses
		rabbit_hunger_label.theme_type_variation = "LabelDanger"
		rabbit_hunger_label.tooltip_text = "Starvation caused the population drop. Place carrot patches or berry bushes near the remaining rabbits."
	elif int(summary["population"]) == 0:
		rabbit_hunger_label.text = "No rabbits yet"
		rabbit_hunger_label.theme_type_variation = "LabelSecondary"
		rabbit_hunger_label.tooltip_text = "Place rabbits near carrot patches or berry bushes so food is within reach."
	elif state == "starving":
		rabbit_hunger_label.text = "%d %s starving" % [starving_count, "rabbit" if starving_count == 1 else "rabbits"]
		rabbit_hunger_label.theme_type_variation = "LabelDanger"
		rabbit_hunger_label.tooltip_text = "Urgent: place carrot patches or berry bushes near the marked rabbits."
	elif state == "warning":
		var unserved_count := int(summary["unserved_count"])
		rabbit_hunger_label.text = "%d need nearby food" % unserved_count
		rabbit_hunger_label.theme_type_variation = "LabelWarning"
		rabbit_hunger_label.tooltip_text = "These rabbits cannot find usable forage nearby. Place carrot patches or berry bushes near their warning rings."
	elif state == "foraging":
		var warning_count := int(summary["warning_count"])
		rabbit_hunger_label.text = "%d finding food" % warning_count
		rabbit_hunger_label.theme_type_variation = "LabelSecondary"
		rabbit_hunger_label.tooltip_text = "Hungry rabbits have found forage and are moving toward it."
	else:
		rabbit_hunger_label.text = "Well fed"
		rabbit_hunger_label.theme_type_variation = "LabelSuccess"
		rabbit_hunger_label.tooltip_text = "Hunger warnings appear here before rabbits begin starving."
	var previous_rank := _hunger_state_rank(last_rabbit_hunger_state)
	var current_rank := _hunger_state_rank(state)
	if not last_rabbit_hunger_state.is_empty() and (current_rank > previous_rank or starving_count > last_rabbit_starving_count):
		_pulse_control(rabbit_hunger_label, false)
	last_rabbit_hunger_state = state
	last_rabbit_starving_count = starving_count

func _hunger_state_rank(state: String) -> int:
	return {"safe": 0, "foraging": 1, "warning": 2, "starving": 3}.get(state, 0)

func _refresh_inventory() -> void:
	var unlocked_count := 0
	var selected_item := ""
	for item in inventory_buttons:
		var count: int = systems.inventory.get(item, 0)
		var button = inventory_buttons[item]
		var unlocked := systems.run_director.is_unlocked(item)
		button.visible = unlocked
		if unlocked:
			unlocked_count += 1
		var selected: bool = systems.selected_item == item
		if selected:
			selected_item = item
		button.set_inventory_state(count, selected, count <= 0 or systems.supply_pending)
		if inventory_counts.has(item) and inventory_counts[item] != count:
			_pulse_control(inventory_count_labels[item], count > inventory_counts[item])
		inventory_counts[item] = count
	var new_width := 32.0 + float(unlocked_count) * 164.0 + float(maxi(0, unlocked_count - 1)) * float(ThemeSystem.SPACE.small)
	if not is_equal_approx(new_width, inventory_width):
		inventory_width = new_width
		inventory_panel.custom_minimum_size.x = inventory_width
		inventory_panel.size.x = inventory_width
		_layout_interface.call_deferred()
	placement_hint.visible = not selected_item.is_empty() and not systems.supply_pending
	if not selected_item.is_empty():
		placement_hint_label.text = "Placing %s  •  click the meadow" % ITEM_LABELS[selected_item]

func _refresh_speeds() -> void:
	for speed in speed_buttons:
		var selected: bool = is_equal_approx(float(speed), systems.simulation_speed)
		var button: Button = speed_buttons[speed]
		button.disabled = systems.supply_pending
		button.tooltip_text = "Supplies have paused the meadow" if systems.supply_pending else ("Pause" if is_zero_approx(float(speed)) else "Run at %s speed" % button.text)
		button.theme_type_variation = "CompactButtonSelected" if selected else "CompactButton"
	restart_button.disabled = systems.supply_pending

func _refresh_objective() -> void:
	var state: String = systems.run_director.run_state
	if state == RunDirector.STATE_SANDBOX:
		objective_eyebrow.text = "FIELD NOTES COMPLETE"
		objective_title.text = "A living ecosystem"
		objective_body.text = "The habitat continues at its own rhythm."
		_hide_objective_mechanics()
		_set_objective_coach("Keep observing the food web.", "Place, watch, and learn from the ecosystem at its own rhythm.", "leaf")
		_update_objective_layout("sandbox")
		return
	var objective := systems.current_objective()
	if objective.is_empty():
		return
	var progress := systems.current_objective_progress()
	objective_eyebrow.text = "CHECKPOINT %d OF %d" % [systems.run_director.milestone_index + 1, systems.run_director.milestones.size()]
	objective_title.text = objective["title"]
	objective_body.text = str(objective.get("summary", "Build an ecosystem that can hold together."))
	_hide_objective_mechanics()
	var coach := _qualitative_objective_coach(str(objective["id"]), str(progress["phase"]), state)
	_set_objective_coach(str(coach["title"]), str(coach["detail"]), str(coach["kind"]))
	objective_coach_detail.text += "\nNEXT · %s" % str(objective.get("teaser", "Keep watching the web."))
	_update_objective_layout("qualitative:%s:%s" % [str(objective["id"]), str(progress["phase"])])

func _qualitative_objective_coach(objective_id: String, phase: String, run_state: String) -> Dictionary:
	if run_state == RunDirector.STATE_CRITICAL:
		return {"title": "The rabbit lineage needs care.", "detail": "Restore a healthy breeding group and keep food within reach.", "kind": "rabbit"}
	if phase == "starving":
		return {"title": "Food is out of reach.", "detail": "Add forage near the animals under pressure and let them recover.", "kind": "carrot_patch"}
	if phase == "declining":
		return {"title": "The web is losing ground.", "detail": "Ease predator pressure and reinforce the rabbit refuges.", "kind": "carrot_patch"}
	if phase == "low":
		return {"title": "The ecosystem is still fragile.", "detail": "Strengthen the living populations before asking more of the web.", "kind": "rabbit"}
	if phase == "stabilizing":
		return {"title": "The pattern is taking hold.", "detail": "Give the ecosystem room to settle without disrupting it.", "kind": "leaf"}
	match objective_id:
		"founders_forage":
			return {"title": "Help every founder discover forage.", "detail": "Place food close enough for the founding rabbits to reach it.", "kind": "carrot_patch"}
		"first_new_life", "life_returns":
			return {"title": "Make room for new life.", "detail": "Keep adult rabbits together, well fed, and undisturbed.", "kind": "rabbit"}
		"next_generation":
			return {"title": "Support the young generation.", "detail": "Let a rabbit born here grow and find food for itself.", "kind": "rabbit"}
		"first_hunt":
			return {"title": "Let predation begin naturally.", "detail": "Keep a fox near healthy prey and wait for a successful hunt.", "kind": "fox"}
		"two_safe_havens":
			return {"title": "Create two true refuges.", "detail": "Separate viable rabbit groups and give each group reachable forage.", "kind": "rabbit"}
		"predators_find_place":
			return {"title": "Help both predators find their place.", "detail": "Let each fox feed while the rabbit colony continues to renew.", "kind": "fox"}
		"living_ecosystem":
			return {"title": "Watch for a living rhythm.", "detail": "Let renewal and successful hunts alternate while the whole web stays healthy.", "kind": "leaf"}
	return {"title": "Watch the ecosystem.", "detail": "Respond to what the living web needs.", "kind": "leaf"}

func _hide_objective_mechanics() -> void:
	objective_requirements_heading.visible = false
	for row in objective_goal_rows.values():
		row.visible = false
	objective_evidence_row.visible = false
	objective_evidence.visible = false
	objective_steps_box.visible = false
	objective_trend_row.visible = false
	objective_progress_row.visible = false
	objective_coach_panel.visible = true
	objective_progress_target = 0.0

func _refresh_evidence_requirement(progress: Dictionary) -> void:
	var sequence: Array = progress["sequence"]
	var birth_target := int(progress["birth_target"])
	var hunt_target := int(progress["hunt_target"])
	if not sequence.is_empty():
		var sequence_progress := int(progress["sequence_progress"])
		objective_steps_box.visible = true
		objective_evidence_title.text = "COMPLETE IN ORDER"
		if bool(progress["sequence_completed"]):
			objective_evidence_value.text = "COMPLETE"
			objective_evidence_value.theme_type_variation = "CaptionSuccess"
			objective_evidence.text = "Cycle complete — it stays complete while you hold the balance."
		elif bool(progress["sequence_started"]):
			objective_evidence_value.text = "%s left" % _format_short_time(float(progress["sequence_time_remaining"]))
			objective_evidence_value.theme_type_variation = "CaptionAccent"
			objective_evidence.text = "Complete the highlighted step. Other events won't reset the cycle."
		else:
			objective_evidence_value.text = "%s window" % _format_short_time(float(progress["evidence_window"]))
			objective_evidence_value.theme_type_variation = "Caption"
			objective_evidence.text = "The timer starts when the first highlighted event happens."
		for index in range(objective_steps.size()):
			var visible := index < sequence.size()
			objective_steps[index]["panel"].visible = visible
			if visible:
				_refresh_objective_step(index, str(sequence[index]), sequence, sequence_progress)
		return
	objective_steps_box.visible = birth_target > 0 or hunt_target > 0
	for step in objective_steps:
		step["panel"].visible = false
	if birth_target > 0 or hunt_target > 0:
		if birth_target > 0 and hunt_target == 0:
			objective_evidence_title.text = "PROVE THE COLONY"
			objective_evidence_value.text = "%d / %d" % [int(progress["birth_count"]), birth_target]
			objective_evidence.text = "Only a natural birth counts — placing a rabbit does not."
			objective_steps[0]["panel"].visible = true
			_refresh_objective_step(0, "birth", ["birth"], 1 if bool(progress["evidence_met"]) else 0)
		elif hunt_target > 0 and birth_target == 0:
			objective_evidence_title.text = "PROVE PREDATION"
			objective_evidence_value.text = "%d / %d" % [int(progress["hunt_count"]), hunt_target]
			objective_evidence.text = "A chase does not count; a fox must catch a living rabbit."
			objective_steps[0]["panel"].visible = true
			_refresh_objective_step(0, "hunt", ["hunt"], 1 if bool(progress["evidence_met"]) else 0)
		else:
			objective_evidence_title.text = "PROVE THE FOOD WEB"
			objective_evidence_value.text = "%d/%d · %d/%d" % [int(progress["birth_count"]), birth_target, int(progress["hunt_count"]), hunt_target]
			objective_evidence.text = "Natural births and successful hunts both count."
		objective_evidence_value.theme_type_variation = "CaptionSuccess" if bool(progress["evidence_met"]) else "Caption"
		return
	objective_evidence_row.visible = false
	objective_evidence.visible = false

func _refresh_objective_step(index: int, event_type: String, sequence: Array, progress: int) -> void:
	var step: Dictionary = objective_steps[index]
	var step_state := "complete" if index < progress else ("current" if index == progress else "future")
	step["panel"].theme_type_variation = "ObjectiveStep%s" % step_state.capitalize()
	step["marker"].text = "✓" if step_state == "complete" else str(index + 1)
	step["marker"].theme_type_variation = "LabelSuccess" if step_state == "complete" else ("LabelWarning" if step_state == "current" else "LabelSecondary")
	step["glyph"].configure("fox" if event_type == "hunt" else "rabbit", Color.TRANSPARENT, false)
	step["glyph"].set_muted(step_state == "future")
	step["title"].text = _sequence_step_title(event_type, index, sequence)
	step["title"].theme_type_variation = "LabelSuccess" if step_state == "complete" else ("LabelStrong" if step_state == "current" else "LabelSecondary")
	step["helper"].text = _event_helper(event_type, index, sequence)
	step["helper"].visible = step_state == "current"
	step["state"].text = "DONE" if step_state == "complete" else ("NEXT" if step_state == "current" else "")
	step["state"].theme_type_variation = "CaptionSuccess" if step_state == "complete" else "CaptionAccent"

func _sequence_step_title(event_type: String, index: int, sequence: Array) -> String:
	var occurrence := 0
	for prior in range(index + 1):
		if str(sequence[prior]) == event_type:
			occurrence += 1
	if event_type == "birth":
		return "A baby rabbit is born" if occurrence == 1 else "Another baby rabbit is born"
	if event_type == "hunt":
		return "Fox catches a rabbit" if occurrence == 1 else "Fox catches another rabbit"
	return event_type.capitalize()

func _event_helper(event_type: String, index: int, sequence: Array) -> String:
	if event_type == "birth":
		return "Natural births count; placed rabbits don't."
	if event_type == "hunt":
		var has_prior_hunt := false
		for prior in range(index):
			if str(sequence[prior]) == "hunt":
				has_prior_hunt = true
		if has_prior_hunt:
			return "A fox must catch again while enough rabbits survive."
		return "A chase counts only when the fox catches a rabbit."
	return "Wait for this ecosystem event to happen naturally."

func _objective_coach(progress: Dictionary, run_state: String) -> Dictionary:
	if run_state == RunDirector.STATE_CRITICAL:
		return {"title": "Recover the rabbit colony first.", "detail": "Place rabbits or choose a recovery supply before continuing this chapter.", "kind": "rabbit"}
	if not bool(progress["trend_met"]):
		return {"title": "Pause new hunts and rebuild.", "detail": "Add forage and help the rabbit population recover from its rapid drop.", "kind": "carrot_patch"}
	var rabbit_missing := int(progress["rabbit_target"]) - int(progress["rabbit_count"])
	if rabbit_missing > 0:
		return {"title": "Build the colony to %d rabbits." % int(progress["rabbit_target"]), "detail": "Place %d more %s near plentiful carrots or berries." % [rabbit_missing, "rabbit" if rabbit_missing == 1 else "rabbits"], "kind": "rabbit"}
	var fox_missing := int(progress["fox_target"]) - int(progress["fox_count"])
	if fox_missing > 0:
		return {"title": "Place %d %s near the colony." % [fox_missing, "fox" if fox_missing == 1 else "foxes"], "detail": "Foxes hunt when hungry; keep the rabbit population safely above its target.", "kind": "fox"}
	var sequence: Array = progress["sequence"]
	var sequence_progress := int(progress["sequence_progress"])
	if not sequence.is_empty() and sequence_progress < sequence.size():
		var event_type := str(sequence[sequence_progress])
		return {
			"title": "Help the rabbits produce offspring." if event_type == "birth" else "Wait for a fox to catch a rabbit.",
			"detail": "Keep two adult, well-fed rabbits together near carrots or berries. Placed rabbits don't count." if event_type == "birth" else ("Let a fox catch one more rabbit, but keep the colony above its target." if _sequence_has_prior_event(sequence, sequence_progress, "hunt") else "Keep a fox near a healthy group of rabbits and wait for it to catch one."),
			"kind": "rabbit" if event_type == "birth" else "fox",
		}
	if int(progress["birth_count"]) < int(progress["birth_target"]):
		return {"title": "Help the rabbits produce offspring.", "detail": "Keep two adult, well-fed rabbits together near carrots or berries. Placed rabbits don't count.", "kind": "rabbit"}
	if int(progress["hunt_count"]) < int(progress["hunt_target"]):
		return {"title": "Wait for a fox to catch a rabbit.", "detail": "A chase alone does not count as a successful hunt.", "kind": "fox"}
	var hold_remaining := ceili(float(progress["stability_target"]) - float(progress["stability_elapsed"]))
	return {"title": "Keep every condition checked.", "detail": "Hold the ecosystem steady for %d more simulation seconds." % maxi(0, hold_remaining), "kind": "leaf"}

func _set_objective_coach(title: String, detail: String, kind: String) -> void:
	objective_teaser.text = title
	objective_coach_detail.text = detail
	objective_coach_glyph.configure(kind, Color.TRANSPARENT, false)

func _sequence_has_prior_event(sequence: Array, before_index: int, event_type: String) -> bool:
	for index in range(before_index):
		if str(sequence[index]) == event_type:
			return true
	return false

func _hold_heading(objective_id: String, has_sequence: bool, active: bool) -> String:
	if active:
		if objective_id == "establish":
			return "HOLDING THE COLONY"
		if objective_id == "living_ecosystem":
			return "HOLDING THE FOOD WEB"
		return "HOLDING THE BALANCE"
	if objective_id == "establish":
		return "THEN HOLD THE COLONY"
	if objective_id == "balance":
		return "THEN HOLD THE BALANCE"
	return "THEN HOLD THE FOOD WEB" if has_sequence else "THEN HOLD EVERY GOAL"

func _hold_locked_reason(progress: Dictionary) -> String:
	if not bool(progress["evidence_met"]):
		return "Starts when the cycle above is complete." if not progress["sequence"].is_empty() else "Starts when the natural birth above is complete."
	if not bool(progress["populations_met"]):
		return "Starts when both populations reach their targets."
	if not bool(progress["trend_met"]):
		return "Reset because the rabbit population began dropping."
	return "Starts when every goal is checked."

func _format_short_time(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	if total < 60:
		return "%d sec" % total
	return "%d:%02d" % [floori(float(total) / 60.0), total % 60]

func _refresh_sequence_feedback(objective_id: String, progress: Dictionary) -> void:
	var sequence: Array = progress["sequence"]
	var current := int(progress["sequence_progress"])
	if objective_id != last_objective_id:
		last_objective_id = objective_id
		last_sequence_progress = current
		return
	if sequence.is_empty():
		last_sequence_progress = 0
		return
	if current > last_sequence_progress:
		var completed_index := mini(current - 1, sequence.size() - 1)
		show_toast("%d of %d · %s" % [current, sequence.size(), _sequence_step_title(str(sequence[completed_index]), completed_index, sequence)], 2.0)
	elif current < last_sequence_progress and not bool(progress["sequence_completed"]):
		show_toast("Cycle window ended · begin again with the first step", 2.8)
	last_sequence_progress = current

func _update_objective_layout(mode: String) -> void:
	if objective_layout_mode == mode:
		return
	objective_layout_mode = mode
	_layout_interface.call_deferred()

func _set_requirement_state(check: Label, value: Label, complete: bool) -> void:
	check.text = "✓" if complete else "○"
	check.theme_type_variation = "LabelSuccess" if complete else "LabelSecondary"
	value.theme_type_variation = "LabelSuccess" if complete else "LabelStrong"

func _refresh_supply() -> void:
	if systems.supply_pending:
		supply_countdown.text = "Supplies are ready"
		supply_progress.value = 100.0
		supply_panel.theme_type_variation = "SurfaceCallout"
	else:
		var remaining := ceili(systems.supply_time_remaining)
		supply_countdown.text = "New supplies in %d" % remaining
		var interval: float = systems.config["supply"]["interval"]
		supply_progress.value = clampf((1.0 - systems.supply_time_remaining / interval) * 100.0, 0.0, 100.0)
		supply_panel.theme_type_variation = "SurfaceInformation"

func process_visual(delta: float) -> void:
	if restart_confirmation_time > 0.0:
		restart_confirmation_time -= delta
		if restart_confirmation_time <= 0.0:
			restart_button.text = "↻"
			restart_button.tooltip_text = "Restart ecosystem (press twice to confirm)"
	if toast_time > 0.0:
		toast_time -= delta
		var fade := clampf(toast_time / 0.35, 0.0, 1.0) if toast_time < 0.35 else 1.0
		toast_panel.modulate = Color(1.0, 1.0, 1.0, fade)
		if toast_time <= 0.0:
			toast_panel.visible = false
	if rabbit_loss_notice_time > 0.0:
		rabbit_loss_notice_time = maxf(0.0, rabbit_loss_notice_time - delta)
		if is_zero_approx(rabbit_loss_notice_time):
			rabbit_starvation_losses = 0
	objective_progress.value = lerpf(objective_progress.value, objective_progress_target, 1.0 - exp(-delta * 7.0))
	refresh()

func show_supply_choices(choices: Array) -> void:
	var reward_was_open := supply_overlay.visible or supply_peek_hud.visible
	for index in range(2):
		var visible := index < choices.size()
		supply_buttons[index].visible = visible
		supply_buttons[index].disabled = false
		supply_buttons[index].modulate = Color.WHITE
		supply_buttons[index].scale = Vector2.ONE
		supply_buttons[index].size_flags_horizontal = Control.SIZE_SHRINK_CENTER if choices.size() == 1 else Control.SIZE_EXPAND_FILL
		if not visible:
			continue
		var bundle: Dictionary = choices[index]
		supply_card_titles[index].text = str(bundle["name"])
		supply_card_roles[index].text = _bundle_role(bundle["items"]).to_upper()
		supply_buttons[index].tooltip_text = "%s — %s" % [bundle["name"], _bundle_role(bundle["items"])]
		_clear_children(supply_card_contents[index])
		for item in bundle["items"]:
			supply_card_contents[index].add_child(_make_supply_item(item, int(bundle["items"][item])))
	supply_title.text = "A lifeline arrives" if systems.is_critical() else "Meadow Mail!"
	supply_subtitle.text = "Your meadow is safe while you choose what helps it recover." if systems.is_critical() else "Choose one bundle for your satchel. Take all the time you need."
	supply_resume_hint.text = "You were already paused — it will stay paused" if is_zero_approx(systems.supply_resume_speed) else "Resumes at %s after your choice" % _speed_name(systems.supply_resume_speed)
	supply_claiming = false
	if reward_was_open:
		return
	supply_peeking = false
	supply_peek_hud.visible = false
	supply_overlay.visible = true
	supply_burst.visible = true
	supply_burst.restart()
	var target_color: Color = ThemeSystem.COLOR.scrim
	supply_overlay.color = Color(target_color.r, target_color.g, target_color.b, 0.0)
	supply_sheet.modulate = Color(1.0, 1.0, 1.0, 0.0)
	supply_sheet.visible = true
	var target := Vector2((root.size.x - SUPPLY_SHEET_SIZE.x) * 0.5, (root.size.y - SUPPLY_SHEET_SIZE.y) * 0.5)
	supply_sheet.position = target + Vector2(0.0, 22.0)
	supply_sheet.pivot_offset = SUPPLY_SHEET_SIZE * 0.5
	supply_sheet.scale = Vector2.ONE * 0.94
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(supply_overlay, "color", target_color, 0.18)
	tween.tween_property(supply_sheet, "position", target, 0.36).set_delay(0.06)
	tween.tween_property(supply_sheet, "scale", Vector2.ONE, 0.36).set_delay(0.06)
	tween.tween_property(supply_sheet, "modulate", Color.WHITE, 0.24).set_delay(0.08)
	if not choices.is_empty():
		supply_focus_index = 0
		supply_buttons[0].grab_focus.call_deferred()

func toggle_supply_peek() -> void:
	if systems == null or not systems.supply_pending or supply_claiming:
		return
	_set_supply_peeking(not supply_peeking)

func choose_supply_shortcut(index: int) -> void:
	if supply_peeking or supply_claiming or index < 0 or index >= supply_buttons.size() or not supply_buttons[index].visible:
		return
	_on_supply_pressed(index)

func _set_supply_peeking(peeking: bool) -> void:
	if peeking == supply_peeking:
		return
	if peeking:
		for index in range(supply_buttons.size()):
			if supply_buttons[index].has_focus():
				supply_focus_index = index
		supply_peeking = true
		supply_peek_hud.modulate = Color(1.0, 1.0, 1.0, 0.0)
		supply_peek_hud.visible = true
		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(supply_sheet, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.12)
		tween.tween_property(supply_overlay, "color:a", 0.0, 0.14)
		tween.tween_property(supply_peek_hud, "modulate", Color.WHITE, 0.14)
		tween.chain().tween_callback(func() -> void:
			if supply_peeking:
				supply_overlay.visible = false
		)
	else:
		supply_peeking = false
		supply_burst.visible = false
		supply_overlay.visible = true
		supply_overlay.color.a = 0.0
		supply_sheet.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var tween := create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(supply_overlay, "color:a", 0.78, 0.15)
		tween.tween_property(supply_sheet, "modulate", Color.WHITE, 0.15)
		tween.tween_property(supply_peek_hud, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.10)
		tween.chain().tween_callback(func() -> void:
			if not supply_peeking:
				supply_peek_hud.visible = false
				if supply_focus_index < supply_buttons.size() and supply_buttons[supply_focus_index].visible:
					supply_buttons[supply_focus_index].grab_focus()
		)

func _make_supply_item(item: String, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(150.0, 98.0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph: Control = Glyph.new().configure(item, Color.TRANSPARENT, false)
	glyph.custom_minimum_size = Vector2(72.0, 72.0)
	row.add_child(glyph)
	var copy := VBoxContainer.new()
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	row.add_child(copy)
	var quantity := _make_label("×%d" % count, "h1")
	quantity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	copy.add_child(quantity)
	var name := _make_label(ITEM_LABELS[item].to_upper(), "eyebrow")
	copy.add_child(name)
	return row

func _bundle_role(items: Dictionary) -> String:
	if int(items.get("fox", 0)) > 0 and int(items.get("rabbit", 0)) > 0:
		return "Balance the food web"
	if int(items.get("fox", 0)) > 0:
		return "Steady the food web"
	if int(items.get("rabbit", 0)) >= 2:
		return "Rebuild the colony"
	if int(items.get("berry_bush", 0)) >= 2:
		return "Build a lasting refuge"
	if int(items.get("rabbit", 0)) > 0:
		return "Add rabbits and forage"
	return "Grow fresh food"

func _speed_name(speed: float) -> String:
	return "%d×" % int(speed)

func _bundle_summary(items: Dictionary) -> String:
	var parts: Array[String] = []
	for item in items:
		parts.append("+%d %s" % [int(items[item]), ITEM_LABELS[item]])
	return "  •  ".join(parts)

func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _pulse_control(control: Control, increased: bool) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2.ONE
	var color: Color = ThemeSystem.COLOR.moss if increased else ThemeSystem.COLOR.danger
	control.modulate = color.lightened(0.18)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE * 1.18, 0.12)
	tween.parallel().tween_property(control, "modulate", Color.WHITE, 0.30)
	tween.tween_property(control, "scale", Vector2.ONE, 0.18)

func _on_inventory_pressed(item: String) -> void:
	inventory_selected.emit(item)

func _on_speed_pressed(speed: float) -> void:
	speed_selected.emit(speed)

func _on_supply_pressed(index: int) -> void:
	if supply_claiming or supply_peeking or not systems.supply_pending:
		return
	supply_claiming = true
	for button_index in range(supply_buttons.size()):
		var button: Button = supply_buttons[button_index]
		button.disabled = true
		if button.visible and button_index != index:
			button.modulate = Color(1.0, 1.0, 1.0, 0.42)
	var chosen: Button = supply_buttons[index]
	chosen.pivot_offset = chosen.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(chosen, "scale", Vector2.ONE * 1.025, 0.12)
	tween.parallel().tween_property(chosen, "modulate", ThemeSystem.COLOR.accent_soft, 0.12)
	tween.tween_interval(0.12)
	tween.tween_callback(_commit_supply_choice.bind(index))

func _commit_supply_choice(index: int) -> void:
	supply_selected.emit(index)
	supply_overlay.visible = false
	supply_peek_hud.visible = false
	supply_peeking = false
	supply_claiming = false

func _on_supply_peek_pressed() -> void:
	toggle_supply_peek()

func _on_supply_claimed(bundle: Dictionary) -> void:
	show_toast("%s tucked into your satchel  •  %s" % [bundle["name"], _bundle_summary(bundle["items"])], 3.0)

func _on_milestone_completed(_index: int, milestone_id: String, message: String) -> void:
	var milestone := systems.run_director.milestone_by_id(milestone_id)
	var tier := str(milestone.get("tier", "minor"))
	if tier == "major":
		show_toast("MEADOW MILESTONE · %s" % message, 4.2, true)
		_pulse_control(objective_panel, true)
	elif tier == "final":
		show_toast(message, 3.3, true)
	else:
		show_toast(message, 2.6)

func _on_critical_started() -> void:
	critical_panel.visible = true
	show_toast("The rabbit lineage needs care", 2.8)

func _on_critical_recovered() -> void:
	critical_panel.visible = false
	show_toast("The colony is finding its feet", 2.8)

func _on_entity_removed(kind: String, _entity_id: int, _position: Vector2, cause: String) -> void:
	if kind != "rabbit" or cause != "starvation":
		return
	if rabbit_loss_notice_time <= 0.0:
		rabbit_starvation_losses = 0
	rabbit_starvation_losses += 1
	rabbit_loss_notice_time = 5.0
	_pulse_control(rabbit_hunger_label, false)

func _on_run_failed(recap: String) -> void:
	critical_panel.visible = false
	ending_title.text = "The meadow fell quiet"
	ending_title.theme_type_variation = "HeadingOneDanger"
	ending_body.text = "%s\n\nWhat happened here can guide the next ecosystem." % recap
	continue_button.visible = false
	new_ecosystem_button.visible = true
	ending_overlay.visible = true

func _on_run_completed() -> void:
	critical_panel.visible = false
	ending_title.text = "Ecosystem Established"
	ending_title.theme_type_variation = "HeadingOne"
	ending_body.text = "A living web of %d rabbits and %d foxes has taken hold.\n\nThis field chapter is complete." % [systems.simulation.population("rabbit"), systems.simulation.population("fox")]
	continue_button.visible = true
	new_ecosystem_button.visible = true
	ending_overlay.visible = true

func show_toast(message: String, duration: float = 2.4, emphasized: bool = false) -> void:
	toast_label.text = message
	toast_label.theme_type_variation = "HeadingThree" if emphasized else "BodyLarge"
	toast_panel.theme_type_variation = "SurfaceToastMajor" if emphasized else "SurfaceToast"
	toast_time = duration
	toast_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var target := Vector2((root.size.x - 420.0) * 0.5, 98.0)
	toast_panel.position = target + Vector2(0.0, -18.0)
	toast_panel.visible = true
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(toast_panel, "position", target, 0.34)
	tween.tween_property(toast_panel, "modulate", Color.WHITE, 0.20)

func _on_restart_pressed() -> void:
	if restart_confirmation_time > 0.0:
		restart_requested.emit()
		return
	restart_confirmation_time = 3.0
	restart_button.text = "!"
	restart_button.tooltip_text = "Click again to begin a new ecosystem"

func _on_continue_pressed() -> void:
	continue_requested.emit()
	ending_overlay.visible = false

func _on_new_ecosystem_pressed() -> void:
	restart_requested.emit()

func set_debug_visible(enabled: bool) -> void:
	debug_panel.visible = enabled

func update_debug(text_value: String) -> void:
	debug_label.text = text_value
