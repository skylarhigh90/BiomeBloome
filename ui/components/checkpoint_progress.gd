class_name BiomeCheckpointProgress
extends VBoxContainer

signal details_toggled(open: bool)

const Glyph = preload("res://ui/entity_glyph.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")
const VALUE_WIDTH := 132.0

var info_row: HBoxContainer
var details_button: Button
var rows_box: VBoxContainer
var goal_rows: Dictionary = {}
var progress_bar: ProgressBar
var next_heading: Label
var next_label: Label
var next_detail_label: Label
var details_box: VBoxContainer
var details_detail: Label
var details_teaser: Label

func configure() -> BiomeCheckpointProgress:
	add_theme_constant_override("separation", ThemeSystem.SPACE.small)

	info_row = HBoxContainer.new()
	info_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	info_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_button = Button.new()
	details_button.text = "Need a hint?"
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
	next_heading = _label("TRY THIS", "Eyebrow")
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
	var details_heading := _label("A LITTLE NUDGE", "Eyebrow")
	details_box.add_child(details_heading)
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
	details_detail.text = guidance
	details_detail.visible = not guidance.is_empty()
	details_teaser.text = "LOOK FOR · %s" % teaser if not teaser.is_empty() else ""
	details_teaser.visible = not teaser.is_empty()
	details_button.visible = not guidance.is_empty()
	info_row.visible = details_button.visible
	details_button.tooltip_text = guidance
	if guidance.is_empty():
		set_details_open(false)

func set_details_open(open: bool) -> void:
	open = open and details_button.visible
	if details_box.visible == open:
		return
	details_box.visible = open
	details_button.text = "Hide hint" if open else "Need a hint?"
	details_toggled.emit(open)

func _toggle_details() -> void:
	set_details_open(not details_box.visible)

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

		goal_rows[row_id] = {
			"container": row,
			"glyph": glyph,
			"title": title,
			"value": value,
		}

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
	if controls["glyph"] != null:
		controls["glyph"].set_muted(false)

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
