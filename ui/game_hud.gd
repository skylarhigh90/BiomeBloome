class_name GameHUD
extends CanvasLayer

signal inventory_selected(item: String)
signal speed_selected(speed: float)
signal supply_selected(index: int)
signal restart_requested
signal continue_requested
signal animal_follow_requested(kind: String, entity_id: int)
signal animal_inspected(kind: String, entity_id: int)
signal animal_inspector_closed
signal remove_food_requested
signal undo_requested
signal transplant_requested
signal audio_toggled

const Glyph = preload("res://ui/entity_glyph.gd")
const RewardBurst = preload("res://ui/reward_burst.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")
const HUDStat = preload("res://ui/components/hud_stat.gd")
const HUDStatus = preload("res://ui/components/hud_status.gd")
const CheckpointProgress = preload("res://ui/components/checkpoint_progress.gd")
const MAX_CHECKPOINT_GOAL_ROWS := 5
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
var objective_progress_view
var objective_layout_mode := ""
var displayed_objective_id := ""

var population_panel: PanelContainer
var population_labels: Dictionary = {}
var last_populations := {"rabbit": -1, "fox": -1}
var rabbit_hunger_label: Label
var last_rabbit_hunger_state := ""
var last_rabbit_starving_count := -1
var rabbit_loss_notice_time := 0.0
var rabbit_loss_notice := ""
var rabbit_loss_detail := ""

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
var remove_food_button: Button
var undo_button: Button
var transplant_button: Button

var story_panel: PanelContainer
var story_labels: Array[Label] = []
var family_status_label: Label
var family_detail_label: Label
var family_inspect_button: Button
var last_loss_button: Button
var journal_button: Button
var journal_panel: PanelContainer
var journal_entries: VBoxContainer
var journal_note_label: Label
var journal_open := false
var animal_panel: PanelContainer
var animal_glyph: Control
var animal_name_label: Label
var animal_status_label: Label
var animal_activity_label: Label
var animal_family_label: Label
var animal_history_label: Label
var animal_life_label: Label
var animal_birth_label: Label
var animal_birth_detail_label: Label
var _inspection_birth_status: Dictionary = {}
var _inspection_sample_time := -INF
var _inspection_revision := -1
var animal_follow_button: Button
var animal_close_button: Button
var inspected_animal_kind := ""
var inspected_animal_id := -1
var followed_animal_kind := ""
var followed_animal_id := -1
var audio_button: Button

var speed_panel: PanelContainer
var speed_buttons: Dictionary = {}

var supply_overlay: ColorRect
var supply_burst: Control
var supply_sheet: PanelContainer
var supply_title: Label
var supply_subtitle: Label
var supply_peek_button: Button
var supply_peek_hud: PanelContainer
var supply_return_button: Button
var supply_buttons: Array = []
var supply_card_titles: Array = []
var supply_card_roles: Array = []
var supply_card_contents: Array = []
var supply_peeking := false
var supply_claiming := false
var supply_focus_index := -1

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
	systems.ecology_story_added.connect(_on_ecology_story_added)
	systems.undo_state_changed.connect(refresh)
	systems.tool_state_changed.connect(refresh)
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
	_build_story_feed()
	_build_animal_inspector()
	_build_inventory_satchel()
	_build_time_controls()
	_build_supply_overlay()
	_build_toast()
	_build_debug_panel()
	_build_critical_panel()
	_build_ending_overlay()
	root.resized.connect(_layout_interface)

func _build_objective_card() -> void:
	objective_panel = _make_panel(Vector2(360.0, 0.0), "SurfaceStandard")
	root.add_child(objective_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	objective_panel.add_child(box)

	objective_eyebrow = _make_label("MILESTONE 01", "eyebrow")
	box.add_child(objective_eyebrow)
	objective_title = _make_label("Grow a self-sustaining rabbit colony", "h3")
	objective_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective_title)
	objective_body = _make_label("Raise a new generation and keep the colony stable.", "label_secondary")
	objective_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective_body)
	objective_progress_view = CheckpointProgress.new().configure()
	objective_progress_view.details_toggled.connect(_on_objective_details_toggled)
	box.add_child(objective_progress_view)

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

	audio_button = _make_button("♪", Vector2(44.0, 44.0), "icon")
	audio_button.tooltip_text = "Mute meadow sounds"
	audio_button.pressed.connect(func() -> void: audio_toggled.emit())
	root.add_child(audio_button)

func _build_story_feed() -> void:
	story_panel = _make_panel(Vector2(306.0, 0.0), "SurfaceHUDLight")
	root.add_child(story_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	story_panel.add_child(box)
	var eyebrow := _make_label("RABBIT FAMILIES", "eyebrow")
	box.add_child(eyebrow)
	var rules := _make_label("Birth needs two fed adults together and spare forage for their young.", "caption")
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(rules)
	family_status_label = _make_label("Place your first rabbits", "label_strong")
	family_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(family_status_label)
	family_detail_label = _make_label("", "caption")
	family_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(family_detail_label)
	family_inspect_button = _make_button("Inspect rabbit", Vector2(0.0, 32.0), "quiet")
	family_inspect_button.pressed.connect(_inspect_family_watch)
	box.add_child(family_inspect_button)
	box.add_child(HSeparator.new())
	box.add_child(_make_label("MEADOW MOMENTS", "eyebrow"))
	for index in range(3):
		var label := _make_label("The meadow is waking up…" if index == 0 else "", "caption")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.max_lines_visible = 2
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.y = 24.0
		box.add_child(label)
		story_labels.append(label)
	last_loss_button = _make_button("Read last loss", Vector2(0.0, 36.0), "quiet")
	last_loss_button.visible = false
	last_loss_button.pressed.connect(_inspect_last_loss)
	box.add_child(last_loss_button)
	journal_button = _make_button("Life journal", Vector2(0.0, 36.0), "secondary")
	journal_button.pressed.connect(_open_life_journal)
	box.add_child(journal_button)
	_build_life_journal()

func _build_life_journal() -> void:
	journal_panel = _make_panel(Vector2(306.0, 420.0), "SurfaceElevated")
	journal_panel.visible = false
	root.add_child(journal_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	journal_panel.add_child(box)
	box.add_child(_make_label("LIFE JOURNAL", "eyebrow"))
	journal_note_label = _make_label("Meadow time · newest first\nBirths, warnings and causes of loss", "caption")
	box.add_child(journal_note_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	journal_entries = VBoxContainer.new()
	journal_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_entries.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	scroll.add_child(journal_entries)
	var close := _make_button("Back to the meadow", Vector2(0.0, 36.0), "secondary")
	close.pressed.connect(func() -> void:
		journal_open = false
		_refresh_life_panels()
	)
	box.add_child(close)

func _build_animal_inspector() -> void:
	animal_panel = _make_panel(Vector2(306.0, 238.0), "SurfaceElevated")
	animal_panel.visible = false
	root.add_child(animal_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	animal_panel.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	box.add_child(header)
	animal_glyph = Glyph.new().configure("rabbit", ThemeSystem.COLOR.moss)
	animal_glyph.custom_minimum_size = Vector2(48.0, 48.0)
	header.add_child(animal_glyph)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	header.add_child(heading)
	var eyebrow := _make_label("FIELD NOTE", "eyebrow_accent")
	heading.add_child(eyebrow)
	animal_name_label = _make_label("Clover", "h3")
	heading.add_child(animal_name_label)
	animal_close_button = _make_button("×", Vector2(36.0, 36.0), "icon")
	animal_close_button.tooltip_text = "Close field note"
	animal_close_button.pressed.connect(_on_animal_close_pressed)
	header.add_child(animal_close_button)
	animal_status_label = _make_label("Adult · Comfortable", "label_success")
	animal_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(animal_status_label)
	animal_life_label = _make_label("", "caption")
	animal_life_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(animal_life_label)
	animal_activity_label = _make_label("Exploring the meadow", "body")
	animal_activity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(animal_activity_label)
	animal_birth_label = _make_label("", "label_strong")
	animal_birth_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(animal_birth_label)
	animal_birth_detail_label = _make_label("", "caption")
	animal_birth_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(animal_birth_detail_label)
	animal_family_label = _make_label("Founder · no young yet", "label_secondary")
	animal_family_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(animal_family_label)
	animal_history_label = _make_label("Recently: Joined the meadow", "caption")
	animal_history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(animal_history_label)
	animal_follow_button = _make_button("Follow", Vector2(0.0, 38.0), "secondary")
	animal_follow_button.pressed.connect(_on_animal_follow_pressed)
	box.add_child(animal_follow_button)

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
	placement_hint = _make_panel(Vector2(620.0, 46.0), "SurfaceCallout")
	placement_hint.visible = false
	root.add_child(placement_hint)
	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	placement_hint.add_child(hint_row)
	placement_hint_label = _make_label("Placing Carrot patch  •  click the meadow", "label_strong")
	placement_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placement_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placement_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint_row.add_child(placement_hint_label)
	undo_button = _make_button("Undo", Vector2(92.0, 34.0), "quiet")
	undo_button.tooltip_text = "Return the last placement to your satchel"
	undo_button.pressed.connect(func() -> void: undo_requested.emit())
	hint_row.add_child(undo_button)
	remove_food_button = _make_button("Remove food", Vector2(118.0, 34.0), "quiet")
	remove_food_button.tooltip_text = "Permanently discard a food patch. No refund. Click a patch to remove it; Esc cancels."
	remove_food_button.pressed.connect(func() -> void: remove_food_requested.emit())
	hint_row.add_child(remove_food_button)
	transplant_button = _make_button("Transplant", Vector2(126.0, 34.0), "secondary")
	transplant_button.tooltip_text = "Move one existing plant to a better habitat"
	transplant_button.pressed.connect(func() -> void: transplant_requested.emit())
	hint_row.add_child(transplant_button)

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
	supply_subtitle = _make_label("Choose one bundle for your satchel.", "body")
	heading_copy.add_child(supply_subtitle)
	supply_peek_button = _make_peek_button("Peek", Vector2(132.0, 48.0), false)
	supply_peek_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	supply_peek_button.tooltip_text = "Peek"
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
	supply_return_button = _make_button("Back to choices", Vector2(142.0, 44.0), "quiet")
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
	objective_panel.custom_minimum_size = Vector2(360.0, 0.0)
	objective_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	objective_panel.position = Vector2(20.0, 20.0)
	objective_panel.size = objective_panel.get_combined_minimum_size()
	population_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var population_x := maxf(
		(viewport_size.x - POPULATION_PANEL_SIZE.x) * 0.5,
		objective_panel.position.x + objective_panel.size.x + ThemeSystem.SPACE.large
	)
	population_panel.position = Vector2(population_x, 20.0) if not compact else Vector2(20.0, objective_panel.position.y + objective_panel.size.y + ThemeSystem.SPACE.medium)
	supply_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	supply_panel.position = Vector2(viewport_size.x - 307.0, 20.0)
	audio_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	audio_button.position = Vector2(viewport_size.x - 359.0, 31.0)
	restart_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	restart_button.position = Vector2(viewport_size.x - 64.0, 31.0)
	story_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	story_panel.position = Vector2(viewport_size.x - 326.0, 170.0 if viewport_size.x < 840.0 else 98.0)
	story_panel.size = story_panel.get_combined_minimum_size()
	animal_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	animal_panel.position = story_panel.position
	animal_panel.size = animal_panel.get_combined_minimum_size()
	journal_panel.position = story_panel.position
	journal_panel.size = Vector2(306.0, maxf(260.0, minf(460.0, viewport_size.y - 202.0 - story_panel.position.y)))
	_refresh_life_panels()
	inventory_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	inventory_panel.position = Vector2((viewport_size.x - inventory_width) * 0.5, viewport_size.y - 128.0) if not compact else Vector2(20.0, viewport_size.y - 128.0)
	placement_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	placement_hint.position = Vector2(clampf(inventory_panel.position.x + (inventory_width - 620.0) * 0.5, 20.0, maxf(20.0, viewport_size.x - 640.0)), inventory_panel.position.y - 54.0)
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
	_refresh_story_feed()
	_refresh_tools()
	_refresh_animal_inspector()
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
		rabbit_hunger_label.text = rabbit_loss_notice
		rabbit_hunger_label.theme_type_variation = "LabelDanger"
		rabbit_hunger_label.tooltip_text = rabbit_loss_detail + " Open the Life journal for the full record."
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
		rabbit_hunger_label.tooltip_text = "These rabbits have not found usable reachable forage. Add carrot patches or berry bushes to the revealed meadow."
	elif state == "foraging":
		var warning_count := int(summary["warning_count"])
		rabbit_hunger_label.text = "%d finding food" % warning_count
		rabbit_hunger_label.theme_type_variation = "LabelSecondary"
		rabbit_hunger_label.tooltip_text = "Hungry rabbits have found forage and are moving toward it."
	else:
		rabbit_hunger_label.text = "Well fed"
		rabbit_hunger_label.theme_type_variation = "LabelSuccess"
		rabbit_hunger_label.tooltip_text = "No rabbits are in hunger distress. Birth also needs meals stored as energy, a ready companion, and spare forage. Inspect a rabbit to see its current needs."
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
	if not selected_item.is_empty() and not systems.transplant_mode:
		placement_hint_label.text = "Placing %s  •  move over the meadow" % ITEM_LABELS[selected_item]

func _refresh_tools() -> void:
	var removal_available := not systems.simulation.plants.is_empty() and not systems.is_game_over() and not systems.is_completed()
	remove_food_button.visible = removal_available or systems.remove_food_mode
	remove_food_button.disabled = systems.supply_pending
	remove_food_button.text = "Cancel" if systems.remove_food_mode else "Remove food"
	var undo_available := systems.can_undo_last_placement()
	var transplant_unlocked := systems.run_director.is_unlocked("transplant")
	undo_button.visible = undo_available and not systems.remove_food_mode
	if undo_available:
		var seconds := maxi(1, ceili(float(systems.last_placement.get("expires_at", 0.0)) - systems.real_time))
		undo_button.text = "Undo %ds" % seconds
	transplant_button.visible = transplant_unlocked and not systems.remove_food_mode
	transplant_button.disabled = systems.supply_pending or (systems.transplant_charges <= 0 and not systems.transplant_mode)
	transplant_button.text = "Cancel" if systems.transplant_mode else "Transplant ×%d" % systems.transplant_charges
	if systems.remove_food_mode:
		placement_hint_label.text = "Click food to remove · no refund"
	elif systems.transplant_mode:
		if systems.transplant_source_id == -1:
			placement_hint_label.text = "Transplant · choose an existing plant"
		else:
			var plant: Dictionary = systems.simulation.plants.get(systems.transplant_source_id, {})
			placement_hint_label.text = "Move %s · choose its new habitat" % ITEM_LABELS.get(str(plant.get("type", "carrot_patch")), "plant")
	elif systems.selected_item.is_empty() and (undo_available or transplant_unlocked or removal_available):
		placement_hint_label.text = "Click an animal for its story"
	placement_hint.visible = not systems.supply_pending and (not systems.selected_item.is_empty() or undo_available or transplant_unlocked or systems.transplant_mode or removal_available or systems.remove_food_mode)

func _refresh_story_feed() -> void:
	var watched := systems.family_watch()
	family_inspect_button.visible = not watched.is_empty()
	if watched.is_empty():
		family_status_label.text = "Place your first rabbits"
		family_detail_label.text = "Keep companions close to fresh food. Click any rabbit to see its needs."
	else:
		family_status_label.text = "%s · %s" % [watched["name"], watched["summary"]]
		family_detail_label.text = str(watched["detail"])
		family_inspect_button.text = "Inspect %s" % watched["name"]
	last_loss_button.visible = not systems.latest_loss.is_empty()
	if last_loss_button.visible:
		last_loss_button.text = "Last loss: %s · read why" % systems.latest_loss["name"]
		last_loss_button.tooltip_text = str(systems.latest_loss["description"])
	for index in range(story_labels.size()):
		var label: Label = story_labels[index]
		if index < systems.ecology_stories.size():
			var story: Dictionary = systems.ecology_stories[index]
			label.text = "%s · %s" % [_journal_time(float(story["time"])), str(story["description"])]
			label.tooltip_text = "%s\n%s" % [story["description"], story.get("detail", "")]
			label.theme_type_variation = "CaptionAccent" if index == 0 else "Caption"
		else:
			label.text = "The meadow is waking up…" if index == 0 else ""
	_refresh_life_panels()

func _refresh_life_panels() -> void:
	for index in range(story_labels.size()):
		story_labels[index].visible = root.size.x >= 840.0 or index < 2
	story_panel.visible = inspected_animal_id == -1 and not journal_open
	journal_panel.visible = journal_open
	animal_panel.visible = inspected_animal_id != -1 and not journal_open
	story_panel.size = story_panel.get_combined_minimum_size()
	animal_panel.size = animal_panel.get_combined_minimum_size()

func _inspect_family_watch() -> void:
	var watched := systems.family_watch()
	if not watched.is_empty(): show_animal("rabbit", int(watched["id"]))

func _inspect_last_loss() -> void:
	if not systems.latest_loss.is_empty():
		show_animal(str(systems.latest_loss["kind"]), int(systems.latest_loss["id"]))

func _journal_time(time: float) -> String:
	return "%d:%02d" % [floori(time / 60.0), floori(time) % 60]

func _open_life_journal() -> void:
	journal_open = true
	journal_note_label.text = "Meadow time · through %s\nBirths, warnings and causes of loss" % _journal_time(systems.simulation.simulation_time)
	_rebuild_life_journal()
	_refresh_life_panels()

func _rebuild_life_journal() -> void:
	_clear_children(journal_entries)
	if systems.ecology_stories.is_empty():
		journal_entries.add_child(_make_label("Your meadow's story begins here.", "caption"))
	for story in systems.ecology_stories:
		var label := _make_label("%s · %s" % [_journal_time(float(story["time"])), story["description"]], "label_strong")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		journal_entries.add_child(label)
		if not str(story.get("detail", "")).is_empty():
			var detail := _make_label(str(story["detail"]), "caption")
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			journal_entries.add_child(detail)
		var kind := str(story["kind"])
		var id := int(story["entity_id"])
		var living: bool = (systems.simulation.rabbits if kind == "rabbit" else systems.simulation.foxes).has(id)
		if living or not systems.simulation.death_snapshot(kind, id).is_empty():
			var inspect := _make_button("Read field note", Vector2(0.0, 30.0), "quiet")
			inspect.pressed.connect(show_animal.bind(kind, id))
			journal_entries.add_child(inspect)
		journal_entries.add_child(HSeparator.new())

func _refresh_animal_inspector() -> void:
	if inspected_animal_id == -1:
		animal_panel.visible = false
		return
	var snapshot := systems.simulation.animal_snapshot(inspected_animal_kind, inspected_animal_id, false)
	if snapshot.is_empty():
		snapshot = systems.simulation.death_snapshot(inspected_animal_kind, inspected_animal_id)
		if snapshot.is_empty():
			hide_animal()
			return
		_show_memorial(snapshot)
		return
	animal_panel.visible = not journal_open
	animal_follow_button.visible = true
	animal_name_label.text = str(snapshot["name"])
	animal_glyph.configure(inspected_animal_kind, ThemeSystem.COLOR.moss if inspected_animal_kind == "rabbit" else ThemeSystem.COLOR.accent)
	var hunger_state := str(snapshot["hunger_state"])
	animal_status_label.text = "%s · %s" % [snapshot["stage"], hunger_state]
	animal_status_label.theme_type_variation = "LabelDanger" if hunger_state == "Starving" else ("LabelWarning" if hunger_state in ["Needs food", "Looking for food"] else "LabelSuccess")
	animal_life_label.text = "Age %s · meadow time" % _journal_time(float(snapshot["age"]))
	if str(snapshot["stage"]) == "Elder":
		animal_life_label.text += "\nClock badge: nearing the end of a natural life. Food cannot stop aging."
		animal_life_label.theme_type_variation = "LabelWarning"
	else:
		animal_life_label.theme_type_variation = "Caption"
	if hunger_state == "Starving":
		animal_life_label.text += "\nAt risk of death without food. Bring fresh forage close." if inspected_animal_kind == "rabbit" else "\nAt risk of death without a successful hunt."
	animal_activity_label.text = str(snapshot["activity"])
	animal_birth_label.visible = inspected_animal_kind == "rabbit"
	animal_birth_detail_label.visible = inspected_animal_kind == "rabbit"
	if inspected_animal_kind == "rabbit":
		if systems.simulation.simulation_time - _inspection_sample_time >= 0.5 or _inspection_revision != systems.life_revision:
			_inspection_birth_status = systems.simulation.rabbit_birth_status(inspected_animal_id)
			_inspection_sample_time = systems.simulation.simulation_time
			_inspection_revision = systems.life_revision
		animal_birth_label.text = "Family · %s" % _inspection_birth_status.get("summary", "Checking needs")
		animal_birth_detail_label.text = str(_inspection_birth_status.get("detail", ""))
	var parent_names: Array = snapshot["parent_names"]
	var family := "Founder" if parent_names.is_empty() else "Young of %s" % " & ".join(parent_names)
	var offspring_count := int(snapshot["offspring_count"])
	if offspring_count > 0:
		family += " · %d %s" % [offspring_count, "young" if offspring_count == 1 else "young"]
	animal_family_label.text = family
	var life_count := int(snapshot["hunts"]) if inspected_animal_kind == "fox" else int(snapshot["meals"])
	var life_word := "hunts" if inspected_animal_kind == "fox" else "feeding visits"
	animal_history_label.text = "Recently: %s · %d %s" % [snapshot["recent_event"], life_count, life_word]
	var following := followed_animal_kind == inspected_animal_kind and followed_animal_id == inspected_animal_id
	animal_follow_button.text = "Stop following" if following else "Follow %s" % str(snapshot["name"])
	animal_panel.size = animal_panel.get_combined_minimum_size()

func _show_memorial(snapshot: Dictionary) -> void:
	animal_panel.visible = not journal_open
	animal_name_label.text = str(snapshot["name"])
	animal_glyph.configure(str(snapshot["kind"]), ThemeSystem.COLOR.moss if snapshot["kind"] == "rabbit" else ThemeSystem.COLOR.accent)
	var cause := str(snapshot["cause"])
	animal_status_label.text = {"age": "Died of old age", "starvation": "Died from starvation", "predation": "Caught by a fox"}.get(cause, "Died")
	animal_status_label.theme_type_variation = "LabelDanger"
	animal_life_label.text = "At %s · age %s in meadow time" % [_journal_time(float(snapshot["time"])), _journal_time(float(snapshot["age"]))]
	animal_life_label.theme_type_variation = "Caption"
	animal_activity_label.text = systems.death_explanation(cause, str(snapshot["kind"]))
	animal_birth_label.visible = false
	animal_birth_detail_label.visible = false
	animal_family_label.text = "%d young · %d feeding visits" % [int(snapshot.get("offspring_count", 0)), int(snapshot.get("meals", 0))] if snapshot["kind"] == "rabbit" else "%d young · %d hunts" % [int(snapshot.get("offspring_count", 0)), int(snapshot.get("hunts", 0))]
	animal_history_label.text = "This loss is recorded in the Life journal."
	animal_follow_button.visible = false
	animal_panel.size = animal_panel.get_combined_minimum_size()

func show_animal(kind: String, entity_id: int) -> void:
	journal_open = false
	if kind != inspected_animal_kind or entity_id != inspected_animal_id:
		_inspection_sample_time = -INF
	inspected_animal_kind = kind
	inspected_animal_id = entity_id
	_refresh_animal_inspector()
	_refresh_life_panels()
	animal_inspected.emit(kind, entity_id)

func hide_animal() -> void:
	inspected_animal_kind = ""
	inspected_animal_id = -1
	animal_panel.visible = false
	_refresh_life_panels()
	animal_inspector_closed.emit()

func set_followed_animal(kind: String, entity_id: int) -> void:
	followed_animal_kind = kind
	followed_animal_id = entity_id
	_refresh_animal_inspector()

func set_audio_enabled(enabled: bool) -> void:
	audio_button.text = "♪" if enabled else "×"
	audio_button.tooltip_text = "Mute meadow sounds" if enabled else "Turn meadow sounds on"

func set_placement_guidance(assessment: Dictionary) -> void:
	if assessment.is_empty() or systems.supply_pending:
		return
	var guidance := "%s · %s" % [str(assessment.get("title", "Choose a site")), str(assessment.get("detail", ""))]
	placement_hint_label.text = guidance
	placement_hint_label.tooltip_text = guidance

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
		if displayed_objective_id != "sandbox":
			objective_progress_view.set_details_open(false)
		displayed_objective_id = "sandbox"
		objective_eyebrow.text = "FIELD NOTES COMPLETE"
		objective_title.text = "A living ecosystem"
		objective_body.text = "The habitat continues at its own rhythm."
		var observation_goals: Array[Dictionary] = [{
			"id": "observation",
			"label": "Observe the living ecosystem",
			"value": "Ongoing",
			"kind": "leaf",
			"state": "success",
		}]
		objective_progress_view.set_goals(observation_goals)
		objective_progress_view.set_hold_progress(1.0, "success", false)
		objective_progress_view.set_guidance("")
		objective_progress_view.set_next("Follow the patterns that interest you.", "Place, watch, and learn from the ecosystem without another checkpoint to complete.")
		_update_objective_layout("sandbox")
		return
	var objective := systems.current_objective()
	if objective.is_empty():
		return
	var progress := systems.current_objective_progress()
	var objective_id := str(objective["id"])
	if displayed_objective_id != objective_id:
		displayed_objective_id = objective_id
		objective_progress_view.set_details_open(false)
	objective_eyebrow.text = "CHECKPOINT %d OF %d" % [systems.run_director.milestone_index + 1, systems.run_director.milestones.size()]
	objective_title.text = objective["title"]
	objective_body.text = str(objective.get("summary", "Build an ecosystem that can hold together."))
	var phase := str(progress["phase"])
	var coach := _qualitative_objective_coach(objective_id, phase, state)
	if state != RunDirector.STATE_CRITICAL:
		coach = _checkpoint_action(coach, progress)
	if state == RunDirector.STATE_CRITICAL:
		objective_body.text = "Restore a living breeding group before time runs out."
		var recovery_target := int(systems.run_director.progression["critical"]["recovery_population"])
		var rabbit_count := int(progress["rabbit_count"])
		objective_progress_view.set_goals([
			_goal_row("population_rabbit", "Rabbits", rabbit_count, recovery_target, "rabbit", rabbit_count >= recovery_target, "danger"),
		])
		objective_progress_view.set_hold_progress(0.0, "danger", false)
		objective_progress_view.set_guidance(
			"Bring food to the remaining rabbits and give them time to recover.",
			"Return to the current checkpoint once the lineage recovers."
		)
	else:
		var goal_rows := _checkpoint_goals(objective, progress)
		objective_progress_view.set_goal_guide(
			_checkpoint_guide_overview(objective),
			_checkpoint_goal_help(objective, goal_rows),
			str(objective.get("teaser", "Keep watching the web."))
		)
		objective_progress_view.set_goals(goal_rows)
		var hold_target := maxf(0.001, float(progress["stability_target"]))
		var hold_ratio := clampf(float(progress["stability_elapsed"]) / hold_target, 0.0, 1.0)
		var hold_state := "success" if hold_ratio >= 1.0 else ("warning" if bool(progress["hold_active"]) else _checkpoint_semantic_state(state, phase))
		objective_progress_view.set_hold_progress(hold_ratio, hold_state, true)
	objective_progress_view.set_next(str(coach["title"]), str(coach["detail"]))
	# The family panel carries the full explanation beside this compact view;
	# retain it as the next-step tooltip without pushing population into tools.
	if root.size.x < 1030.0 and objective_id == "first_family":
		objective_progress_view.next_detail_label.visible = false
	_update_objective_layout("goals:%s:%s" % [str(objective["id"]), phase])

func _checkpoint_goals(_objective: Dictionary, progress: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for configured_goal in progress.get("goals", []):
		var goal: Dictionary = configured_goal
		var goal_type := str(goal.get("type", ""))
		var met := bool(goal.get("met", false))
		if goal_type == "ordered_cycle":
			rows.append(_ordered_cycle_row(goal, progress, _objective))
			continue
		var row_id := str(goal.get("id", goal_type))
		var title := _player_goal_label(goal)
		var value := "%d/%d %s" % [int(goal.get("current", 0)), int(goal.get("target", 1)), _goal_unit(goal_type)]
		var state := "success" if met else str(goal.get("unmet_state", "warning"))
		if goal_type == "ecology_window":
			value = "B %d/%d · H %d/%d" % [int(goal.get("births", 0)), int(goal.get("birth_target", 0)), int(goal.get("hunts", 0)), int(goal.get("hunt_target", 0))]
		elif goal_type == "health":
			var health_status := str(goal.get("status", "fed"))
			value = {
				"fed": "Fed",
				"hungry": "Hungry",
				"starving": "Starving",
				"absent": "—",
			}.get(health_status, "—")
			state = {
				"fed": "success",
				"hungry": "warning",
				"starving": "danger",
				"absent": "normal",
			}.get(health_status, "normal")
		elif goal_type == "trend":
			var trend_status := str(goal.get("status", "stable" if met else "falling"))
			value = {
				"stable": "Stable",
				"under_pressure": "Under pressure",
				"falling": "Falling fast",
			}.get(trend_status, "Stable" if met else "Falling fast")
			state = {
				"stable": "success",
				"under_pressure": "warning",
				"falling": "danger",
			}.get(trend_status, "success" if met else "danger")
		var kind := str(goal.get("kind", ""))
		rows.append({
			"id": row_id,
			"label": title,
			"value": value,
			"kind": kind,
			"state": state,
			"tooltip": _goal_tooltip(_objective, row_id, str(goal.get("tooltip", ""))),
		})

	var hold_elapsed := float(progress["stability_elapsed"])
	var hold_target := float(progress["stability_target"])
	rows.append({
		"id": "hold",
		"label": "All goals together",
		"value": _format_hold_value(hold_elapsed, hold_target),
		"kind": "",
		"state": "success" if hold_elapsed + 0.0001 >= hold_target else ("warning" if bool(progress["hold_active"]) else "normal"),
		"tooltip": _goal_tooltip(_objective, "hold"),
	})
	# A compact checkpoint is a progression contract, not merely a visual crop.
	# Keep a defensive cap here for custom configs; production milestones are
	# tested to expose every blocker in five rows or fewer, including this hold.
	return rows.slice(0, MAX_CHECKPOINT_GOAL_ROWS)

func _ordered_cycle_row(goal: Dictionary, progress: Dictionary, objective: Dictionary) -> Dictionary:
	var sequence: Array = progress.get("sequence", [])
	var sequence_progress := int(progress.get("sequence_progress", 0))
	var sequence_completed := bool(progress.get("sequence_completed", false))
	var next_event := ""
	if not sequence_completed and sequence_progress < sequence.size():
		next_event = str(sequence[sequence_progress])
	var next_copy := "Cycle complete"
	if next_event == "birth":
		next_copy = "Next: rabbit birth"
	elif next_event == "hunt":
		next_copy = "Next: fox hunt"
	var value := "%d/%d · complete" % [int(goal.get("current", sequence_progress)), int(goal.get("target", sequence.size()))]
	if not sequence_completed:
		value = "%d/%d · %s next" % [int(goal.get("current", sequence_progress)), int(goal.get("target", sequence.size())), next_event]
	var row_id := str(goal.get("id", "cycle"))
	return {
		"id": row_id,
		"label": str(goal.get("label", "Food-web cycle")),
		"value": value,
		"kind": "rabbit" if next_event == "birth" else "fox",
		"state": "success" if sequence_completed else "warning",
		"tooltip": _goal_tooltip(objective, row_id, next_copy),
	}

func _goal_row(row_id: String, label_text: String, current: int, target: int, kind: String, complete: bool, incomplete_state: String = "normal") -> Dictionary:
	return {
		"id": row_id,
		"label": label_text,
		"value": "%d/%d %s" % [current, target, "rabbits" if kind == "rabbit" else "foxes"],
		"kind": kind,
		"state": "success" if complete else incomplete_state,
	}

func _goal_unit(goal_type: String) -> String:
	return {
		"founders_fed": "rabbits",
		"rabbit_birth": "births",
		"born_rabbit_fed": "rabbits",
		"safe_havens": "nurseries",
		"separated_birth_zones": "areas",
		"distinct_foxes_fed": "foxes",
		"prey_per_fox": "rabbits/fox",
		"rabbit_population": "rabbits",
		"fox_population": "foxes",
		"productive_forages": "types",
		"population_recovery": "rabbits",
	}.get(goal_type, "goals")

func _format_hold_value(elapsed: float, target: float) -> String:
	var current_seconds := maxi(0, ceili(elapsed))
	var target_seconds := maxi(0, ceili(target))
	if target_seconds < 60:
		return "%d/%d sec" % [current_seconds, target_seconds]
	return "%s/%s sec" % [_format_short_time(elapsed), _format_short_time(target)]

func _player_goal_label(goal: Dictionary) -> String:
	var goal_type := str(goal.get("type", ""))
	match goal_type:
		"founders_fed":
			return "Rabbits that ate"
		"rabbit_birth":
			return "Rabbit births"
		"born_rabbit_fed":
			return "Young fed + grown"
		"safe_havens":
			return "Nurseries"
		"separated_birth_zones":
			return "Separate birth areas"
		"distinct_foxes_fed":
			return "Foxes with a kill"
		"prey_per_fox":
			return "Rabbits per fox"
		"productive_forages":
			return "Productive forage"
		"population_recovery":
			return "Colony recovered"
		"ecology_window":
			return "Births + hunts together"
		"health":
			return "Rabbit hunger" if str(goal.get("kind", "")) == "rabbit" else "Fox hunger"
		"trend":
			return str(goal.get("label", "Colony stability"))
		"rabbit_population":
			return "Rabbits alive"
		"fox_population":
			return "Foxes alive"
	return str(goal.get("label", "The meadow keeps going"))

## The guide is static reference material. Only NEXT MOVE is reactive, which
## prevents an explanation from switching back to an earlier goal when a live
## nursery or living-animal count fluctuates.
func _checkpoint_guide_overview(objective: Dictionary) -> String:
	var universal := "Every row must be complete before the hold can run. Select ? beside any goal for its fixed definition. Live counts and living credit can fall; saved evidence stays for this checkpoint. NEXT MOVE is the only guidance that changes with the meadow."
	var checkpoint_note := str(objective.get("guide_intro", objective.get("guidance", "")))
	return universal if checkpoint_note.is_empty() else "%s\n\n%s" % [universal, checkpoint_note]

func _checkpoint_goal_help(objective: Dictionary, rows: Array[Dictionary]) -> Dictionary:
	var configured: Dictionary = objective.get("goal_help", {})
	var entries := {}
	for row in rows:
		var row_id := str(row.get("id", ""))
		if not configured.has(row_id):
			continue
		var entry: Dictionary = configured[row_id].duplicate(true)
		entry["title"] = str(row.get("label", "Goal"))
		entry["detail"] = _goal_help_detail(objective, row_id)
		entries[row_id] = entry
	return entries

func _goal_tooltip(objective: Dictionary, row_id: String, live_detail: String = "") -> String:
	var static_detail := _goal_help_detail(objective, row_id)
	if static_detail.is_empty():
		return live_detail
	return static_detail if live_detail.is_empty() else "%s\n\n%s" % [static_detail, live_detail]

func _goal_help_detail(objective: Dictionary, row_id: String) -> String:
	var configured: Dictionary = objective.get("goal_help", {})
	if not configured.has(row_id):
		return ""
	var entry: Dictionary = configured[row_id]
	var detail := str(entry.get("detail", ""))
	var window := float(objective.get("evidence_window", 0.0))
	if "{sequence_window}" in detail:
		detail = detail.replace("{sequence_window}", _format_rule_duration(window))
	return detail

func _format_rule_duration(seconds: float) -> String:
	var rounded_seconds := maxi(0, roundi(seconds))
	if rounded_seconds > 0 and rounded_seconds % 60 == 0:
		var minutes := rounded_seconds / 60
		return "%d %s" % [minutes, "minute" if minutes == 1 else "minutes"]
	return _format_short_time(seconds)

func _on_objective_details_toggled(_open: bool) -> void:
	objective_layout_mode = ""
	_layout_interface.call_deferred()

func _checkpoint_semantic_state(run_state: String, phase: String) -> String:
	if run_state == RunDirector.STATE_CRITICAL or phase in ["starving", "declining"]:
		return "danger"
	if run_state in [RunDirector.STATE_COMPLETED, RunDirector.STATE_SANDBOX] or phase == "stabilizing":
		return "success"
	return "warning" if phase in ["low", "evidence"] else "normal"

func _checkpoint_action(default_action: Dictionary, progress: Dictionary) -> Dictionary:
	var missing_rabbits := maxi(0, int(progress["rabbit_target"]) - int(progress["rabbit_count"]))
	# This checkpoint grows the colony through births. A generic population
	# deficit must not tell a player with an empty satchel to place more rabbits.
	if str(progress.get("milestone_id", "")) == "first_family" and int(progress["rabbit_count"]) >= 2:
		if int(progress["birth_count"]) < int(progress["birth_target"]) or missing_rabbits > 0:
			return _family_checkpoint_action(default_action)
	if missing_rabbits > 0:
		return {
			"title": "Bring %d more %s to the meadow." % [missing_rabbits, "rabbit" if missing_rabbits == 1 else "rabbits"],
			"detail": "Place them near food and watch where the colony begins to gather.",
			"kind": "rabbit",
		}
	var missing_foxes := maxi(0, int(progress["fox_target"]) - int(progress["fox_count"]))
	if missing_foxes > 0:
		return {
			"title": "Make room for %d more %s." % [missing_foxes, "fox" if missing_foxes == 1 else "foxes"],
			"detail": "Let the rabbit colony grow confident before adding more hunters.",
			"kind": "fox",
		}
	if str(progress.get("phase", "")) != "evidence":
		return default_action
	for configured in progress.get("criteria", []):
		var criterion: Dictionary = configured
		if bool(criterion.get("met", false)):
			continue
		match str(criterion.get("type", "")):
			"founders_fed":
				var missing := maxi(0, int(criterion.get("target", 1)) - int(criterion.get("current", 0)))
				return {"title": "Help %d more %s find food." % [missing, "rabbit" if missing == 1 else "rabbits"], "detail": "Keep reachable food close to the founding colony.", "kind": "rabbit"}
			"safe_havens":
				var missing := maxi(0, int(criterion.get("target", 1)) - int(criterion.get("current", 0)))
				var group_size := int(criterion.get("rabbits_per_group", 2))
				return {"title": "Build %d more %s." % [missing, "nursery" if missing == 1 else "nurseries"], "detail": "Each nursery needs at least %d rabbits gathered around usable nearby food, separate from the other nurseries." % group_size, "kind": "rabbit"}
			"separated_birth_zones":
				var missing := maxi(0, int(criterion.get("target", 1)) - int(criterion.get("current", 0)))
				return {"title": "Have births in %d more %s." % [missing, "area" if missing == 1 else "areas"], "detail": "Keep adult rabbits together near food in separate parts of the meadow.", "kind": "rabbit"}
			"born_rabbit_fed":
				var missing := maxi(0, int(criterion.get("target", 1)) - int(criterion.get("current", 0)))
				return {"title": "Help %d more young %s grow and eat." % [missing, "rabbit" if missing == 1 else "rabbits"], "detail": "Keep their group near food while the young rabbits grow.", "kind": "rabbit"}
			"rabbit_birth":
				return _family_checkpoint_action(default_action)
			"distinct_foxes_fed":
				var missing := maxi(0, int(criterion.get("target", 1)) - int(criterion.get("current", 0)))
				return {"title": "Let %d more %s kill a rabbit." % [missing, "fox" if missing == 1 else "foxes"], "detail": "Keep enough rabbits spread through the meadow for both the foxes and the colony.", "kind": "fox"}
			"prey_per_fox":
				var missing := maxi(0, int(criterion.get("target", 1)) - int(criterion.get("current", 0)))
				return {"title": "Raise rabbits per fox by %d." % missing, "detail": "Add food or pause before adding another fox.", "kind": "rabbit"}
			"productive_forages":
				var missing := maxi(0, int(criterion.get("target", 1)) - int(criterion.get("current", 0)))
				return {"title": "Establish %d more productive forage %s." % [missing, "type" if missing == 1 else "types"], "detail": "Use the placement quality label: Carrots favor open Meadow, while Berries favor woodland and Thicket margins.", "kind": "leaf"}
			"population_recovery":
				var missing := maxi(0, int(criterion.get("target", 1)) - int(criterion.get("current", 0)))
				return {"title": "Recover %d more %s." % [missing, "rabbit" if missing == 1 else "rabbits"], "detail": "Support births with stocked, reachable forage; the target is the population from the start of this act.", "kind": "rabbit"}
			"ecology_window":
				var birth_missing := maxi(0, int(criterion.get("birth_target", 0)) - int(criterion.get("births", 0)))
				var hunt_missing := maxi(0, int(criterion.get("hunt_target", 0)) - int(criterion.get("hunts", 0)))
				if int(criterion.get("rabbit_count", 0)) < int(criterion.get("rabbit_target", 0)):
					return {"title": "Rebuild the rabbit reserve.", "detail": "The living window needs at least %d rabbits before it can hold." % int(criterion.get("rabbit_target", 0)), "kind": "rabbit"}
				if int(criterion.get("fox_count", 0)) < int(criterion.get("fox_target", 0)):
					return {"title": "Restore two living foxes.", "detail": "Choose a fox supply only after the rabbit reserve is healthy.", "kind": "fox"}
				if birth_missing > 0:
					return {"title": "Support %d more recent rabbit %s." % [birth_missing, "birth" if birth_missing == 1 else "births"], "detail": "Keep adults near stocked forage; hunts may happen before or after births.", "kind": "rabbit"}
				if hunt_missing > 0:
					return {"title": "Support %d more recent fox %s." % [hunt_missing, "hunt" if hunt_missing == 1 else "hunts"], "detail": "Keep enough exposed prey for both foxes without weakening every nursery.", "kind": "fox"}
			"ordered_cycle":
				break
	var sequence: Array = progress["sequence"]
	var sequence_progress := int(progress["sequence_progress"])
	if not sequence.is_empty() and sequence_progress < sequence.size():
		var event_type := str(sequence[sequence_progress])
		var hunt_detail := "Protect the remaining colony so it can renew."
		if int(progress.get("rabbit_target", 0)) > 0:
			hunt_detail = "Keep at least %d rabbits alive so the colony can recover." % int(progress["rabbit_target"])
		return {
			"title": "Wait for 1 rabbit birth." if event_type == "birth" else "Let a fox kill 1 rabbit.",
			"detail": "Keep adult rabbits together near food." if event_type == "birth" else hunt_detail,
			"kind": "rabbit" if event_type == "birth" else "fox",
		}
	return default_action

func _family_checkpoint_action(fallback: Dictionary) -> Dictionary:
	var watched := systems.family_watch()
	if watched.is_empty(): return fallback
	var code := str(watched["code"])
	var detail := str(watched["detail"])
	if code in ["local_capacity", "world_capacity"]:
		detail = "Add productive forage near this home. Use the placement quality preview; waiting alone will not make room for young."
	elif code == "needs_meals":
		detail = "Keep forage near this rabbit. Repeated meals build the food reserves needed for young."
	elif code == "mate_not_ready":
		detail = "This rabbit is ready; a nearby adult still needs food or rest. Inspect the companion to see what is missing."
	return {"title": "%s · %s" % [watched["name"], watched["summary"]], "detail": detail, "kind": "carrot_patch" if code in ["local_capacity", "world_capacity", "local_food", "local_stock", "world_stock"] else "rabbit"}

func _qualitative_objective_coach(objective_id: String, phase: String, run_state: String) -> Dictionary:
	if run_state == RunDirector.STATE_CRITICAL:
		return {"title": "Save the rabbit colony.", "detail": "Bring food to the remaining rabbits and give them time to recover.", "kind": "rabbit"}
	if phase == "starving":
		return {"title": "Bring food closer.", "detail": "Help the animals under pressure find a meal, then wait.", "kind": "carrot_patch"}
	if phase == "declining":
		return {"title": "Give the meadow room to recover.", "detail": "Ease the pressure and support the rabbits before pushing ahead.", "kind": "carrot_patch"}
	if phase == "low":
		return {"title": "Strengthen the meadow first.", "detail": "Add a little life or food, then watch where the animals settle.", "kind": "rabbit"}
	if phase == "stabilizing":
		return {"title": "Let the pattern settle.", "detail": "The meadow is finding its balance; keep changes gentle.", "kind": "leaf"}
	match objective_id:
		"first_meal":
			return {"title": "Start the colony.", "detail": "Place four rabbits near food and help three different founders eat.", "kind": "rabbit"}
		"first_family":
			return {"title": "Raise the first family.", "detail": "Support two natural births and help one young rabbit grow and eat.", "kind": "rabbit"}
		"two_homes":
			return {"title": "Build two lasting homes.", "detail": "Use productive Carrots and Berries to support two separated rabbit groups.", "kind": "rabbit"}
		"nursery_network":
			return {"title": "Complete the nursery network.", "detail": "Keep the first two homes and establish one more separated nursery.", "kind": "rabbit"}
		"hunt_and_recover":
			return {"title": "Feed both foxes and recover.", "detail": "Hunts and births can happen in any order; restore the opening rabbit population.", "kind": "fox"}
		"living_balance":
			return {"title": "Hold a living balance.", "detail": "Keep births, hunts, nurseries, prey reserve, and forage health true in the same recent window.", "kind": "leaf"}
	return {"title": "Watch the ecosystem.", "detail": "Respond to what the living meadow needs.", "kind": "leaf"}

func _format_short_time(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	if total < 60:
		return "%d sec" % total
	return "%d:%02d" % [floori(float(total) / 60.0), total % 60]

func _update_objective_layout(mode: String) -> void:
	if objective_layout_mode == mode:
		return
	objective_layout_mode = mode
	_layout_interface.call_deferred()

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
	refresh()
	_fit_objective_panel_to_content()

func _fit_objective_panel_to_content() -> void:
	var content_size := objective_panel.get_combined_minimum_size()
	if objective_panel.size.is_equal_approx(content_size):
		return
	objective_panel.size = content_size
	if root.size.x < 1030.0:
		population_panel.position.y = objective_panel.position.y + objective_panel.size.y + ThemeSystem.SPACE.medium

func show_supply_choices(choices: Array) -> void:
	var reward_was_open := supply_overlay.visible or supply_peek_hud.visible
	for index in range(2):
		var visible := index < choices.size()
		supply_buttons[index].visible = visible
		supply_buttons[index].disabled = false
		supply_buttons[index].modulate = Color.WHITE
		supply_buttons[index].scale = Vector2.ONE
		supply_buttons[index].theme_type_variation = "RewardChoiceButton"
		if supply_buttons[index].has_focus():
			supply_buttons[index].release_focus()
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
	supply_subtitle.text = "Choose one bundle to help your meadow recover." if systems.is_critical() else "Choose one bundle for your satchel."
	supply_claiming = false
	if reward_was_open:
		return
	supply_peeking = false
	supply_peek_hud.visible = false
	supply_overlay.visible = true
	supply_burst.visible = true
	supply_burst.modulate = Color.WHITE
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
		supply_focus_index = -1

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
		supply_focus_index = -1
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
				if supply_focus_index >= 0 and supply_focus_index < supply_buttons.size() and supply_buttons[supply_focus_index].visible:
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
	var chosen: Button = supply_buttons[index]
	chosen.theme_type_variation = "RewardChoiceButtonChosen"
	chosen.pivot_offset = chosen.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(chosen, "scale", Vector2.ONE * 1.025, 0.12)
	for button_index in range(supply_buttons.size()):
		var button: Button = supply_buttons[button_index]
		if button.visible and button_index != index:
			tween.parallel().tween_property(button, "modulate", Color(1.0, 1.0, 1.0, 0.42), 0.12)
	tween.tween_interval(0.10)
	tween.tween_callback(_animate_supply_choice_out.bind(index))

func _animate_supply_choice_out(index: int) -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(supply_sheet, "position", supply_sheet.position - Vector2(0.0, 18.0), 0.28)
	tween.tween_property(supply_sheet, "scale", Vector2.ONE * 0.97, 0.28)
	tween.tween_property(supply_sheet, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.24)
	tween.tween_property(supply_burst, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.18)
	tween.tween_property(supply_overlay, "color:a", 0.0, 0.28).set_delay(0.04)
	tween.chain().tween_callback(_commit_supply_choice.bind(index))

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
	_pulse_control(objective_panel, true)
	if tier == "major":
		show_toast("MEADOW MILESTONE · %s" % message, 4.2, true)
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

func _on_entity_removed(kind: String, entity_id: int, _position: Vector2, cause: String) -> void:
	if kind == inspected_animal_kind and entity_id == inspected_animal_id:
		_refresh_animal_inspector()
	if kind == followed_animal_kind and entity_id == followed_animal_id:
		set_followed_animal("", -1)
	if kind != "rabbit" or cause not in ["starvation", "age", "predation"]:
		return
	rabbit_loss_notice = "−1 · %s" % {"starvation": "starvation", "age": "old age", "predation": "fox hunt"}[cause]
	rabbit_loss_detail = str(systems.latest_loss.get("description", "Rabbit lost")) + ". " + systems.death_explanation(cause)
	rabbit_loss_notice_time = 8.0
	_pulse_control(rabbit_hunger_label, false)

func _on_ecology_story_added(_story: Dictionary) -> void:
	_refresh_story_feed()
	_refresh_animal_inspector()
	# Keep the open journal stable while the reader scrolls or focuses a button.
	# Reopening takes a fresh snapshot of the recent history.

func _on_animal_close_pressed() -> void:
	hide_animal()

func _on_animal_follow_pressed() -> void:
	if inspected_animal_id != -1:
		animal_follow_requested.emit(inspected_animal_kind, inspected_animal_id)

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
