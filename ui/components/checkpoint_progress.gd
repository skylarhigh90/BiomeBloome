class_name BiomeCheckpointProgress
extends VBoxContainer

signal details_toggled(open: bool)

const Glyph = preload("res://ui/entity_glyph.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")

var goals_heading: Label
var status_heading: Label
var details_button: Button
var rows_box: VBoxContainer
var keep_heading_row: HBoxContainer
var keep_heading: Label
var keep_status_heading: Label
var keep_rows_box: VBoxContainer
var finish_heading_row: HBoxContainer
var finish_heading: Label
var finish_status_heading: Label
var finish_rows_box: VBoxContainer
var goal_rows: Dictionary = {}
var hint_label: Label
var progress_bar: ProgressBar
var next_heading: Label
var next_label: Label
var next_detail_label: Label
var details_box: VBoxContainer
var details_heading: Label
var details_scroll: ScrollContainer
var details_detail: Label
var details_teaser: Label

func configure() -> BiomeCheckpointProgress:
	add_theme_constant_override("separation", ThemeSystem.SPACE.small)

	var heading_row := HBoxContainer.new()
	heading_row.alignment = BoxContainer.ALIGNMENT_END
	heading_row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	add_child(heading_row)
	goals_heading = _label("DO THIS", "Eyebrow")
	goals_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(goals_heading)
	status_heading = _label("STATUS", "Eyebrow")
	status_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_heading.custom_minimum_size.x = 84.0
	heading_row.add_child(status_heading)
	details_button = Button.new()
	details_button.text = "Need a hint?"
	details_button.theme_type_variation = "CheckpointInfoButton"
	details_button.custom_minimum_size = Vector2(104.0, 32.0)
	details_button.focus_mode = Control.FOCUS_ALL
	details_button.pressed.connect(_toggle_details)
	heading_row.add_child(details_button)

	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	add_child(rows_box)

	keep_heading_row = _section_heading("KEEP", "STATUS")
	add_child(keep_heading_row)
	keep_heading = keep_heading_row.get_child(0)
	keep_status_heading = keep_heading_row.get_child(1)
	keep_rows_box = VBoxContainer.new()
	keep_rows_box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	add_child(keep_rows_box)

	finish_heading_row = _section_heading("FINISH", "PROGRESS")
	add_child(finish_heading_row)
	finish_heading = finish_heading_row.get_child(0)
	finish_status_heading = finish_heading_row.get_child(1)
	finish_rows_box = VBoxContainer.new()
	finish_rows_box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	add_child(finish_rows_box)

	hint_label = _label("", "Caption")
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.visible = false
	add_child(hint_label)

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
	next_detail_label = _label("", "Caption")
	next_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_detail_label.visible = false
	add_child(next_detail_label)

	details_box = VBoxContainer.new()
	details_box.visible = false
	details_box.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	add_child(details_box)
	var divider_details := HSeparator.new()
	divider_details.theme_type_variation = "CheckpointDivider"
	divider_details.custom_minimum_size.y = ThemeSystem.SPACE.small
	details_box.add_child(divider_details)
	details_heading = _label("A LITTLE NUDGE", "Eyebrow")
	details_box.add_child(details_heading)
	details_scroll = ScrollContainer.new()
	# Let a short hint stay short. The scroll container still protects the card
	# if authored guidance grows beyond the available space.
	details_scroll.custom_minimum_size = Vector2(0.0, 0.0)
	details_scroll.custom_maximum_size.y = 120.0
	details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_box.add_child(details_scroll)
	details_detail = _label("", "BodySecondary")
	details_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.add_child(details_detail)
	details_teaser = _label("", "Caption")
	details_teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_box.add_child(details_teaser)
	return self

func set_goals(rows: Array[Dictionary]) -> void:
	var incoming_ids: Array[String] = []
	for row in rows:
		incoming_ids.append("%s@%s" % [str(row["id"]), str(row.get("section", "do_this"))])
	if incoming_ids != _current_row_ids():
		_rebuild_rows(rows)
	for row in rows:
		_update_row(row)

func set_hint(text_value: String) -> void:
	hint_label.text = text_value
	hint_label.visible = not text_value.is_empty()

func set_hold_progress(ratio: float, semantic_state: String, visible: bool = true) -> void:
	progress_bar.visible = visible
	progress_bar.value = clampf(ratio * 100.0, 0.0, 100.0)
	progress_bar.theme_type_variation = _progress_variation(semantic_state)

func set_next(text_value: String, detail: String = "") -> void:
	next_label.text = text_value
	next_label.tooltip_text = detail
	next_detail_label.text = detail
	next_detail_label.visible = not detail.is_empty()

func set_details(summary: String, detail: String, teaser: String) -> void:
	# Kept as a small compatibility wrapper for callers from the first checklist
	# iteration. The checkpoint UI now presents a nudge, not a rules glossary.
	set_guidance(detail if not detail.is_empty() else summary, teaser)

func set_guidance(guidance: String, teaser: String = "") -> void:
	details_detail.text = guidance
	details_detail.visible = not guidance.is_empty()
	details_teaser.text = "LOOK FOR · %s" % teaser if not teaser.is_empty() else ""
	details_teaser.visible = not teaser.is_empty()
	details_button.visible = not guidance.is_empty()
	details_button.tooltip_text = guidance
	if guidance.is_empty():
		set_details_open(false)

func set_details_open(open: bool) -> void:
	open = open and details_button.visible
	if details_box.visible == open:
		return
	details_box.visible = open
	details_button.text = "Hide hint" if open else "Need a hint?"
	if open:
		details_scroll.scroll_vertical = 0
	details_toggled.emit(open)

func _toggle_details() -> void:
	set_details_open(not details_box.visible)

func _rebuild_rows(rows: Array[Dictionary]) -> void:
	for section_box in [rows_box, keep_rows_box, finish_rows_box]:
		for child in section_box.get_children():
			child.free()
	goal_rows.clear()
	var section_counts := {"do_this": 0, "keep": 0, "finish": 0}
	for row_data in rows:
		var row_id := str(row_data["id"])
		var section := str(row_data.get("section", "do_this"))
		if not section_counts.has(section):
			section = "do_this"
		section_counts[section] += 1
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 26.0
		row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
		_section_box(section).add_child(row)

		var marker := _label("○", "LabelSecondary")
		marker.custom_minimum_size.x = 18.0
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(marker)

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

		var value := _label(str(row_data.get("value", "")), "LabelStrong")
		value.custom_minimum_size.x = 84.0
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
		goal_rows[row_id] = {
			"container": row,
			"section": section,
			"marker": marker,
			"glyph": glyph,
			"title": title,
			"value": value,
		}
	rows_box.visible = section_counts["do_this"] > 0
	goals_heading.visible = rows_box.visible
	status_heading.visible = rows_box.visible
	keep_heading_row.visible = section_counts["keep"] > 0
	keep_rows_box.visible = keep_heading_row.visible
	finish_heading_row.visible = section_counts["finish"] > 0
	finish_rows_box.visible = finish_heading_row.visible

func _update_row(row_data: Dictionary) -> void:
	var row_id := str(row_data["id"])
	if not goal_rows.has(row_id):
		return
	var controls: Dictionary = goal_rows[row_id]
	var state := str(row_data.get("state", "normal"))
	var complete := bool(row_data.get("complete", state == "success"))
	var marker_style := str(row_data.get("marker_style", "check"))
	if row_data.has("marker_text"):
		controls["marker"].text = str(row_data["marker_text"])
	elif marker_style == "status":
		controls["marker"].text = "!" if state == "danger" else "●"
	else:
		controls["marker"].text = "✓" if complete else ("!" if state == "danger" else "○")
	controls["marker"].theme_type_variation = _label_variation(state, false)
	controls["title"].text = str(row_data.get("label", "Goal"))
	controls["title"].theme_type_variation = "LabelStrong"
	controls["value"].text = str(row_data.get("value", ""))
	controls["value"].theme_type_variation = _label_variation(state, true)
	var tooltip := str(row_data.get("tooltip", ""))
	controls["container"].tooltip_text = tooltip
	controls["title"].tooltip_text = tooltip
	controls["value"].tooltip_text = tooltip
	if controls["glyph"] != null:
		controls["glyph"].set_muted(false)

func _current_row_ids() -> Array[String]:
	var ids: Array[String] = []
	for section in ["do_this", "keep", "finish"]:
		for child in _section_box(section).get_children():
			for row_id in goal_rows:
				if goal_rows[row_id]["container"] == child:
					ids.append("%s@%s" % [str(row_id), section])
					break
	return ids

func _section_box(section: String) -> VBoxContainer:
	if section == "keep":
		return keep_rows_box
	if section == "finish":
		return finish_rows_box
	return rows_box

func _section_heading(title_text: String, status_text: String) -> HBoxContainer:
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	var title := _label(title_text, "Eyebrow")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var status := _label(status_text, "Eyebrow")
	status.custom_minimum_size.x = 84.0
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(status)
	return heading

func _label(text_value: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.theme_type_variation = variation
	return label

func _label_variation(state: String, value: bool) -> String:
	match state:
		"success":
			return "LabelSuccess"
		"warning":
			return "LabelWarning"
		"danger":
			return "LabelDanger"
	return "LabelStrong" if value else "LabelSecondary"

func _progress_variation(state: String) -> String:
	return {
		"success": "ProgressCheckpointSuccess",
		"warning": "ProgressCheckpointWarning",
		"danger": "ProgressCheckpointDanger",
	}.get(state, "ProgressCheckpoint")
