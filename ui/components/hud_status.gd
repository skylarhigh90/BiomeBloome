class_name BiomeHUDStatus
extends VBoxContainer

const ThemeSystem = preload("res://ui/theme/biome_theme.gd")

var category_label: Label
var primary_label: Label
var secondary_label: Label

func configure(category: String, primary: String, secondary: String = "") -> BiomeHUDStatus:
	add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	category_label = Label.new()
	category_label.text = category
	category_label.theme_type_variation = "Eyebrow"
	add_child(category_label)
	primary_label = Label.new()
	primary_label.text = primary
	primary_label.theme_type_variation = "LabelStrong"
	primary_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(primary_label)
	secondary_label = Label.new()
	secondary_label.text = secondary
	secondary_label.theme_type_variation = "Caption"
	secondary_label.visible = not secondary.is_empty()
	add_child(secondary_label)
	return self

func set_status(primary: String, secondary: String = "") -> void:
	primary_label.text = primary
	secondary_label.text = secondary
	secondary_label.visible = not secondary.is_empty()
