class_name BiomeIconTextButton
extends Button

const Glyph = preload("res://ui/entity_glyph.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")

var glyph: Control
var content_label: Label

func configure(text_value: String, minimum_size: Vector2, dark: bool = false) -> BiomeIconTextButton:
	text = ""
	custom_minimum_size = minimum_size
	focus_mode = Control.FOCUS_ALL
	theme_type_variation = "CompactButton" if dark else "SecondaryButton"

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", ThemeSystem.SPACE.small)
	margin.add_theme_constant_override("margin_right", ThemeSystem.SPACE.medium)
	margin.add_theme_constant_override("margin_top", ThemeSystem.SPACE.tiny)
	margin.add_theme_constant_override("margin_bottom", ThemeSystem.SPACE.tiny)
	add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	margin.add_child(row)
	glyph = Glyph.new().configure("eye", ThemeSystem.COLOR.text_on_dark if dark else ThemeSystem.COLOR.forest, false)
	glyph.custom_minimum_size = Vector2(34.0, 34.0)
	row.add_child(glyph)
	content_label = Label.new()
	content_label.text = text_value
	content_label.theme_type_variation = "TextOnDark" if dark else "LabelStrong"
	content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(content_label)
	return self
