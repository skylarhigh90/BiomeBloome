class_name BiomeHUDStat
extends HBoxContainer

const Glyph = preload("res://ui/entity_glyph.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")

var glyph: Control
var value_label: Label

func configure(kind: String, initial_value: String = "0") -> BiomeHUDStat:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	glyph = Glyph.new().configure(kind, Color.TRANSPARENT, false)
	glyph.custom_minimum_size = Vector2(34.0, 34.0)
	add_child(glyph)
	value_label = Label.new()
	value_label.text = initial_value
	value_label.theme_type_variation = "Numeric"
	value_label.custom_minimum_size.x = 42.0
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(value_label)
	return self

func set_value(value: String) -> void:
	value_label.text = value
