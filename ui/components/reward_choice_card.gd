class_name BiomeRewardChoiceCard
extends Button

const ThemeSystem = preload("res://ui/theme/biome_theme.gd")

var role_label: Label
var title_label: Label
var contents: HBoxContainer

func configure(shortcut_text: String) -> BiomeRewardChoiceCard:
	text = ""
	theme_type_variation = "RewardChoiceButton"
	custom_minimum_size = Vector2(400.0, 258.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", ThemeSystem.SPACE.large)
	margin.add_theme_constant_override("margin_right", ThemeSystem.SPACE.large)
	margin.add_theme_constant_override("margin_top", ThemeSystem.SPACE.medium)
	margin.add_theme_constant_override("margin_bottom", ThemeSystem.SPACE.medium)
	add_child(margin)

	var manifest := VBoxContainer.new()
	manifest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	manifest.add_theme_constant_override("separation", ThemeSystem.SPACE.tiny)
	margin.add_child(manifest)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", ThemeSystem.SPACE.small)
	manifest.add_child(header)
	role_label = Label.new()
	role_label.text = "GROW FRESH FOOD"
	role_label.theme_type_variation = "Eyebrow"
	role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(role_label)
	var shortcut := Label.new()
	shortcut.text = shortcut_text
	shortcut.theme_type_variation = "ShortcutBadge"
	shortcut.custom_minimum_size = Vector2(26.0, 26.0)
	shortcut.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shortcut.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(shortcut)

	title_label = Label.new()
	title_label.text = "Meadow starters"
	title_label.theme_type_variation = "HeadingThree"
	manifest.add_child(title_label)

	var adds := Label.new()
	adds.text = "ADDS TO SATCHEL"
	adds.theme_type_variation = "Caption"
	manifest.add_child(adds)

	contents = HBoxContainer.new()
	contents.alignment = BoxContainer.ALIGNMENT_CENTER
	contents.add_theme_constant_override("separation", ThemeSystem.SPACE.medium)
	contents.custom_minimum_size.y = 102.0
	contents.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	manifest.add_child(contents)
	return self
