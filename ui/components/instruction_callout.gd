class_name BiomeInstructionCallout
extends PanelContainer

const Glyph = preload("res://ui/entity_glyph.gd")
const ThemeSystem = preload("res://ui/theme/biome_theme.gd")

var glyph: Control
var eyebrow_label: Label
var title_label: Label
var detail_label: Label

func configure(eyebrow: String, title: String, detail: String, kind: String = "leaf") -> BiomeInstructionCallout:
	theme_type_variation = "SurfaceCallout"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeSystem.SPACE.medium)
	add_child(row)
	glyph = Glyph.new().configure(kind, Color.TRANSPARENT, false)
	glyph.custom_minimum_size = Vector2(38.0, 38.0)
	row.add_child(glyph)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	row.add_child(copy)
	eyebrow_label = Label.new()
	eyebrow_label.text = eyebrow
	eyebrow_label.theme_type_variation = "EyebrowAccent"
	copy.add_child(eyebrow_label)
	title_label = Label.new()
	title_label.text = title
	title_label.theme_type_variation = "BodyLarge"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(title_label)
	detail_label = Label.new()
	detail_label.text = detail
	detail_label.theme_type_variation = "BodySecondary"
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(detail_label)
	return self

func set_content(title: String, detail: String, kind: String) -> void:
	title_label.text = title
	detail_label.text = detail
	glyph.configure(kind, Color.TRANSPARENT, false)
