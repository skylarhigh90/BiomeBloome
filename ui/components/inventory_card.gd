class_name BiomeInventoryCard
extends Button

const Glyph = preload("res://ui/entity_glyph.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")

var item_kind := ""
var glyph: Control
var title_label: Label
var count_label: Label
var selected_mark: Label

func configure(kind: String, title: String, hint: String) -> BiomeInventoryCard:
	item_kind = kind
	text = ""
	theme_type_variation = "InventoryButton"
	custom_minimum_size = Vector2(164.0, 84.0)
	focus_mode = Control.FOCUS_ALL
	tooltip_text = hint
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", ThemeSystem.SPACE.medium)
	margin.add_theme_constant_override("margin_right", ThemeSystem.SPACE.small)
	margin.add_theme_constant_override("margin_top", ThemeSystem.SPACE.small)
	margin.add_theme_constant_override("margin_bottom", ThemeSystem.SPACE.small)
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	margin.add_child(row)
	glyph = Glyph.new().configure(kind)
	glyph.custom_minimum_size = Vector2(52.0, 52.0)
	row.add_child(glyph)
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	row.add_child(copy)
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	copy.add_child(title_row)
	title_label = Label.new()
	title_label.text = title
	title_label.theme_type_variation = "LabelStrong"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_label)
	selected_mark = Label.new()
	selected_mark.text = "✓"
	selected_mark.theme_type_variation = "EyebrowAccent"
	selected_mark.custom_minimum_size.x = 16.0
	selected_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selected_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selected_mark.visible = false
	title_row.add_child(selected_mark)
	count_label = Label.new()
	count_label.text = "×0"
	count_label.theme_type_variation = "Numeric"
	copy.add_child(count_label)
	return self

func set_inventory_state(count: int, selected: bool, unavailable: bool) -> void:
	disabled = unavailable
	self_modulate = Color(1.0, 1.0, 1.0, 0.58 if unavailable else 1.0)
	theme_type_variation = "InventoryButtonSelected" if selected else "InventoryButton"
	count_label.text = "×%d" % count
	selected_mark.visible = selected
	glyph.set_muted(unavailable)
