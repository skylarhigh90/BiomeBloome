class_name BiomeCheckpointProgress
extends VBoxContainer

signal details_toggled(open: bool)

const Glyph = preload("res://ui/entity_glyph.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")
const VALUE_WIDTH := 112.0

var info_row: HBoxContainer
var details_button: Button
var rows_box: VBoxContainer
var goal_rows: Dictionary = {}
var progress_bar: ProgressBar
var next_heading: Label
var next_label: Label
var next_detail_label: Label
var details_box: VBoxContainer
var details_heading: Label
var details_title: Label
var details_behavior: Label
var details_detail: Label
var details_teaser: Label
var guide_overview := ""
var guide_teaser := ""
var goal_help: Dictionary = {}
var selected_help_id := ""

func configure() -> BiomeCheckpointProgress:
	add_theme_constant_override("separation", ThemeSystem.SPACE.small)

	info_row = HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	info_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_button = Button.new()
	details_button.text = "How progress works"
	details_button.theme_type_variation = "CheckpointInfoButton"
	details_button.custom_minimum_size = Vector2(0.0, 36.0)
	details_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	details_button.focus_mode = Control.FOCUS_ALL
	details_button.pressed.connect(_toggle_details)
	info_row.add_child(details_button)

	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(rows_box)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 8.0
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.show_percentage = false
	progress_bar.theme_type_variation = "ProgressCheckpoint"
	add_child(progress_bar)

	var divider := HSeparator.new()
	divider.theme_type_variation = "CheckpointDivider"
	divider.custom_minimum_size.y = ThemeSystem.SPACE.small
	add_child(divider)
	next_heading = _label("NEXT MOVE · UPDATES LIVE", "Eyebrow")
	add_child(next_heading)
	next_label = _label("Watch the ecosystem.", "Body")
	next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(next_label)
	next_detail_label = _label("", "BodySecondary")
	next_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_detail_label.visible = false
	add_child(next_detail_label)
	add_child(info_row)

	details_box = VBoxContainer.new()
	details_box.visible = false
	details_box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	add_child(details_box)
	var divider_details := HSeparator.new()
	divider_details.theme_type_variation = "CheckpointDivider"
	divider_details.custom_minimum_size.y = ThemeSystem.SPACE.small
	details_box.add_child(divider_details)
	details_heading = _label("CHECKPOINT GUIDE", "Eyebrow")
	details_box.add_child(details_heading)
	details_title = _label("How progress works", "LabelStrong")
	details_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_box.add_child(details_title)
	details_behavior = _label("", "EyebrowAccent")
	details_behavior.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_behavior.visible = false
	details_box.add_child(details_behavior)
	details_detail = _label("", "BodySecondary")
	details_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_box.add_child(details_detail)
	details_teaser = _label("", "Caption")
	details_teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_box.add_child(details_teaser)
	return self

func set_goals(rows: Array[Dictionary]) -> void:
	var incoming_ids: Array[String] = []
	for row in rows:
		incoming_ids.append(str(row["id"]))
	if incoming_ids != _current_row_ids():
		_rebuild_rows(rows)
	for row in rows:
		_update_row(row)

func set_next(text_value: String, detail: String = "") -> void:
	next_label.text = text_value
	next_label.tooltip_text = detail
	next_detail_label.text = detail
	next_detail_label.visible = not detail.is_empty()

func set_details(summary: String, detail: String, teaser: String) -> void:
	set_guidance(detail if not detail.is_empty() else summary, teaser)

func set_guidance(guidance: String, teaser: String = "") -> void:
	set_goal_guide(guidance, {}, teaser)

## Checkpoint guidance is reference material, not reactive coaching. Entries are
## keyed by rendered goal ID so every row can explain itself regardless of which
## goal currently blocks progress.
func set_goal_guide(overview: String, entries: Dictionary, teaser: String = "") -> void:
	guide_overview = overview
	guide_teaser = teaser
	goal_help = entries.duplicate(true)
	if not selected_help_id.is_empty() and not goal_help.has(selected_help_id):
		selected_help_id = ""
	_sync_help_buttons()
	if details_box.visible:
		_render_details()
	details_button.visible = not guide_overview.is_empty() or not goal_help.is_empty()
	info_row.visible = details_button.visible
	details_button.tooltip_text = "A stable guide to goal rules and which progress can change."
	if not details_button.visible:
		set_details_open(false)

func set_details_open(open: bool) -> void:
	open = open and details_button.visible
	if details_box.visible == open:
		return
	details_box.visible = open
	if open:
		_render_details()
	details_button.text = "Hide checkpoint guide" if open else "How progress works"
	details_toggled.emit(open)

func _toggle_details() -> void:
	if details_box.visible:
		set_details_open(false)
		return
	selected_help_id = ""
	set_details_open(true)

func set_hold_progress(ratio: float, semantic_state: String, visible: bool = true) -> void:
	progress_bar.visible = visible
	progress_bar.value = clampf(ratio * 100.0, 0.0, 100.0)
	progress_bar.theme_type_variation = _progress_variation(semantic_state)

func _rebuild_rows(rows: Array[Dictionary]) -> void:
	for child in rows_box.get_children():
		child.free()
	goal_rows.clear()
	for row_data in rows:
		var row_id := str(row_data["id"])
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 32.0
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
		rows_box.add_child(row)

		var kind := str(row_data.get("kind", ""))
		var glyph: Control
		if not kind.is_empty():
			glyph = Glyph.new().configure(kind, Color.TRANSPARENT, false)
			glyph.custom_minimum_size = Vector2(24.0, 24.0)
			row.add_child(glyph)

		var title := _label(str(row_data.get("label", "Goal")), "LabelStrong")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(title)

		var value := _label(str(row_data.get("value", "")), _label_variation(str(row_data.get("state", "normal"))))
		value.custom_minimum_size.x = VALUE_WIDTH
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(value)

		var help_button := Button.new()
		help_button.text = "?"
		help_button.theme_type_variation = "CheckpointInfoIconButton"
		help_button.custom_minimum_size = Vector2(28.0, 28.0)
		help_button.focus_mode = Control.FOCUS_ALL
		help_button.pressed.connect(_show_goal_help.bind(row_id))
		row.add_child(help_button)

		goal_rows[row_id] = {
			"container": row,
			"glyph": glyph,
			"title": title,
			"value": value,
			"help_button": help_button,
		}
	_sync_help_buttons()

func _update_row(row_data: Dictionary) -> void:
	var row_id := str(row_data["id"])
	if not goal_rows.has(row_id):
		return
	var controls: Dictionary = goal_rows[row_id]
	var state := str(row_data.get("state", "normal"))
	controls["title"].text = str(row_data.get("label", "Goal"))
	controls["title"].theme_type_variation = "LabelStrong"
	controls["value"].text = str(row_data.get("value", ""))
	controls["value"].theme_type_variation = _label_variation(state)
	var tooltip := str(row_data.get("tooltip", ""))
	controls["container"].tooltip_text = tooltip
	controls["title"].tooltip_text = tooltip
	controls["value"].tooltip_text = tooltip
	var help_button: Button = controls["help_button"]
	help_button.visible = goal_help.has(row_id)
	help_button.tooltip_text = "Explain %s" % str(row_data.get("label", "this goal"))
	if controls["glyph"] != null:
		controls["glyph"].set_muted(false)

func _sync_help_buttons() -> void:
	for row_id in goal_rows:
		var controls: Dictionary = goal_rows[row_id]
		var help_button: Button = controls["help_button"]
		help_button.visible = goal_help.has(str(row_id))
		if help_button.visible:
			help_button.tooltip_text = "Explain %s" % controls["title"].text

func _show_goal_help(row_id: String) -> void:
	if not goal_help.has(row_id):
		return
	if details_box.visible and selected_help_id == row_id:
		set_details_open(false)
		return
	selected_help_id = row_id
	_render_details()
	if details_box.visible:
		details_toggled.emit(true)
	else:
		set_details_open(true)

func _render_details() -> void:
	if not selected_help_id.is_empty() and goal_help.has(selected_help_id):
		var entry: Dictionary = goal_help[selected_help_id]
		details_heading.text = "GOAL EXPLAINER"
		details_title.text = str(entry.get("title", "Goal"))
		details_behavior.text = str(entry.get("behavior", ""))
		details_behavior.visible = not details_behavior.text.is_empty()
		details_detail.text = str(entry.get("detail", ""))
		details_teaser.visible = false
	else:
		details_heading.text = "CHECKPOINT GUIDE"
		details_title.text = "How progress works"
		details_behavior.text = ""
		details_behavior.visible = false
		details_detail.text = guide_overview
		details_teaser.text = "UP NEXT · %s" % guide_teaser if not guide_teaser.is_empty() else ""
		details_teaser.visible = not guide_teaser.is_empty()
	details_detail.visible = not details_detail.text.is_empty()

func _current_row_ids() -> Array[String]:
	var ids: Array[String] = []
	for child in rows_box.get_children():
		for row_id in goal_rows:
			if goal_rows[row_id]["container"] == child:
				ids.append(str(row_id))
				break
	return ids

func _label(text_value: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.theme_type_variation = variation
	return label

func _label_variation(state: String) -> String:
	match state:
		"success":
			return "LabelSuccess"
		"warning":
			return "LabelWarning"
		"danger":
			return "LabelDanger"
	return "LabelStrong"

func _progress_variation(state: String) -> String:
	return {
		"success": "ProgressCheckpointSuccess",
		"warning": "ProgressCheckpointWarning",
		"danger": "ProgressCheckpointDanger",
	}.get(state, "ProgressCheckpoint")
