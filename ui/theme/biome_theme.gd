class_name BiomeTheme
extends RefCounted

## Canonical semantic tokens and Godot Theme variations for supporting game UI.
## Complex controls should compose these variations instead of styling children.

const COLOR := {
	"text_primary": Color("#213d34"),
	"text_secondary": Color("#526b62"),
	"text_muted": Color("#718078"),
	"text_on_dark": Color("#fff9e9"),
	"surface_primary": Color("#f4ecd8"),
	"surface_secondary": Color("#ebe4d1"),
	"surface_elevated": Color("#fff9e9"),
	"surface_hud": Color(0.075, 0.17, 0.135, 0.96),
	"surface_hud_light": Color(0.96, 0.92, 0.82, 0.94),
	"forest": Color("#294b3d"),
	"forest_deep": Color("#17362d"),
	"moss": Color("#6e9957"),
	"grass": Color("#93b879"),
	"leaf": Color("#b9d99b"),
	"accent": Color("#e5ad45"),
	"accent_soft": Color("#fff0bd"),
	"accent_highlight": Color("#ffe7a3"),
	"info": Color("#4f8f92"),
	"info_surface": Color("#d8e9e6"),
	"success": Color("#4f7f52"),
	"warning": Color("#c8872f"),
	"danger": Color("#d96d52"),
	"danger_text": Color("#713e32"),
	"danger_surface": Color("#f7d4c4"),
	"debug_text": Color("#c6e7bd"),
	"border_subtle": Color(0.12, 0.25, 0.19, 0.16),
	"border_strong": Color(0.12, 0.25, 0.19, 0.30),
	"scrim": Color(0.027, 0.106, 0.078, 0.78),
}

const TYPE_SIZE := {
	"display": 40,
	"h1": 28,
	"h2": 24,
	"h3": 20,
	"body_large": 18,
	"body": 16,
	"label": 14,
	"caption": 13,
	"eyebrow": 13,
	"numeric": 24,
}

const SPACE := {
	"tiny": 4,
	"small": 8,
	"medium": 12,
	"large": 16,
	"section": 24,
	"major": 32,
}

const RADIUS := {
	"small": 8,
	"control": 12,
	"card": 18,
	"panel": 22,
	"pill": 28,
}

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = TYPE_SIZE.body
	_set_text_style(theme, "Display", TYPE_SIZE.display, COLOR.text_primary)
	_set_text_style(theme, "HeadingOne", TYPE_SIZE.h1, COLOR.text_primary)
	_set_text_style(theme, "HeadingTwo", TYPE_SIZE.h2, COLOR.text_primary)
	_set_text_style(theme, "HeadingThree", TYPE_SIZE.h3, COLOR.text_primary)
	_set_text_style(theme, "BodyLarge", TYPE_SIZE.body_large, COLOR.text_primary)
	_set_text_style(theme, "Body", TYPE_SIZE.body, COLOR.text_primary)
	_set_text_style(theme, "BodySecondary", TYPE_SIZE.body, COLOR.text_secondary)
	_set_text_style(theme, "LabelStrong", TYPE_SIZE.label, COLOR.text_primary)
	_set_text_style(theme, "LabelSecondary", TYPE_SIZE.label, COLOR.text_secondary)
	_set_text_style(theme, "Caption", TYPE_SIZE.caption, COLOR.text_muted)
	_set_text_style(theme, "Eyebrow", TYPE_SIZE.eyebrow, COLOR.moss.darkened(0.10))
	_set_text_style(theme, "EyebrowAccent", TYPE_SIZE.eyebrow, COLOR.accent.darkened(0.28))
	_set_text_style(theme, "TextOnDark", TYPE_SIZE.body, COLOR.text_on_dark)
	_set_text_style(theme, "EyebrowOnDark", TYPE_SIZE.eyebrow, COLOR.accent.lightened(0.16))
	_set_text_style(theme, "Numeric", TYPE_SIZE.numeric, COLOR.text_primary)
	_set_text_style(theme, "NumericOnDark", TYPE_SIZE.numeric, COLOR.text_on_dark)
	_set_text_style(theme, "DangerText", TYPE_SIZE.body, COLOR.danger_text)
	_set_text_style(theme, "DebugText", TYPE_SIZE.caption, COLOR.debug_text)
	_set_text_style(theme, "LabelSuccess", TYPE_SIZE.label, COLOR.success)
	_set_text_style(theme, "LabelWarning", TYPE_SIZE.label, COLOR.warning)
	_set_text_style(theme, "LabelDanger", TYPE_SIZE.label, COLOR.danger.darkened(0.16))
	_set_text_style(theme, "CaptionSuccess", TYPE_SIZE.caption, COLOR.success)
	_set_text_style(theme, "CaptionWarning", TYPE_SIZE.caption, COLOR.warning)
	_set_text_style(theme, "CaptionAccent", TYPE_SIZE.caption, COLOR.accent.darkened(0.28))
	_set_text_style(theme, "HeadingOneDanger", TYPE_SIZE.h1, COLOR.danger_text)
	_set_text_style(theme, "ShortcutBadge", TYPE_SIZE.caption, COLOR.text_secondary)
	theme.set_stylebox("normal", "ShortcutBadge", _shortcut_badge_style())

	_set_panel(theme, "SurfaceStandard", COLOR.surface_primary, RADIUS.panel, "standard")
	_set_panel(theme, "SurfaceElevated", COLOR.surface_elevated, RADIUS.panel, "elevated")
	_set_panel(theme, "SurfaceHUD", COLOR.surface_hud, RADIUS.card, "hud")
	_set_panel(theme, "SurfaceHUDLight", COLOR.surface_hud_light, RADIUS.pill, "standard")
	_set_panel(theme, "SurfaceInformation", COLOR.info_surface, RADIUS.card, "info")
	_set_panel(theme, "SurfaceCallout", COLOR.accent_soft, RADIUS.control, "accent")
	_set_panel(theme, "SurfaceDanger", COLOR.danger_surface, RADIUS.card, "danger")
	_set_panel(theme, "SurfaceToast", Color("#fff1bd"), RADIUS.panel, "accent")
	_set_panel(theme, "SurfaceToastMajor", Color("#ffe59a"), RADIUS.panel, "success")
	_set_panel(theme, "SurfaceDebug", Color(0.02, 0.06, 0.045, 0.94), RADIUS.control, "success")
	_set_reward_surfaces(theme)
	_set_objective_step_surfaces(theme)

	_set_button(theme, "PrimaryButton", COLOR.forest, COLOR.text_on_dark, COLOR.forest.lightened(0.10), COLOR.forest_deep)
	_set_button(theme, "SecondaryButton", Color("#e2e9d7"), COLOR.text_primary, COLOR.accent.lightened(0.25), COLOR.accent)
	_set_button(theme, "QuietButton", Color(0.95, 0.91, 0.81, 0.82), COLOR.text_primary, COLOR.surface_elevated, COLOR.accent_soft)
	_set_button(theme, "IconButton", Color(0.95, 0.91, 0.81, 0.82), COLOR.text_primary, COLOR.surface_elevated, COLOR.accent_soft)
	theme.set_font_size("font_size", "IconButton", 21)
	_set_button(theme, "CompactButton", Color("#28493c"), COLOR.text_on_dark, Color("#3c6852"), COLOR.accent)
	_set_button(theme, "CompactButtonSelected", COLOR.accent, COLOR.forest_deep, COLOR.accent.lightened(0.14), COLOR.accent.darkened(0.08))
	_set_inventory_button(theme, "InventoryButton", false)
	_set_inventory_button(theme, "InventoryButtonSelected", true)
	_set_reward_choice_button(theme)

	_set_progress(theme, "ProgressAccent", Color(0.20, 0.31, 0.25, 0.13), COLOR.accent, 5)
	_set_progress(theme, "ProgressInformation", Color(0.15, 0.34, 0.34, 0.14), COLOR.info, 4)
	return theme

static func _inventory_style(selected: bool, hovered: bool = false, unavailable: bool = false) -> StyleBoxFlat:
	var fill: Color = COLOR.accent_soft if selected else COLOR.surface_primary
	if hovered:
		fill = COLOR.surface_elevated if not selected else COLOR.accent_highlight
	if unavailable:
		fill = Color(0.66, 0.69, 0.61, 0.72)
	var style := _flat_style(fill, RADIUS.card)
	_set_border(style, COLOR.accent if selected else COLOR.border_subtle, 2 if selected else 1)
	style.shadow_color = Color(COLOR.accent.r, COLOR.accent.g, COLOR.accent.b, 0.25 if selected else 0.12)
	style.shadow_size = 7 if selected else 3
	style.shadow_offset = Vector2(0.0, 3.0)
	return style

static func _reward_choice_style(state: String) -> StyleBoxFlat:
	var fill: Color = COLOR.surface_primary
	var border: Color = COLOR.border_strong
	if state == "hover" or state == "focus":
		fill = Color("#fff3c9")
		border = COLOR.accent
	elif state == "pressed":
		fill = Color("#f5dda0")
		border = COLOR.accent.darkened(0.12)
	elif state == "disabled":
		fill = Color(COLOR.surface_secondary.r, COLOR.surface_secondary.g, COLOR.surface_secondary.b, 0.62)
		border = COLOR.border_subtle
	var style := _flat_style(fill, RADIUS.card)
	var active := state in ["hover", "focus", "pressed"]
	_set_border(style, border, 3 if active else 2)
	style.border_width_bottom = 5 if active else 3
	style.shadow_color = Color(0.03, 0.08, 0.055, 0.18 if active else 0.10)
	style.shadow_size = 9 if active else 5
	style.shadow_offset = Vector2(0.0, 5.0 if active else 3.0)
	return style

static func _objective_step_style(state: String) -> StyleBoxFlat:
	var fill := Color(0.18, 0.29, 0.23, 0.045)
	var border := Color(0.18, 0.29, 0.23, 0.10)
	if state == "current":
		fill = Color(COLOR.accent.r, COLOR.accent.g, COLOR.accent.b, 0.14)
		border = Color(COLOR.accent.r, COLOR.accent.g, COLOR.accent.b, 0.55)
	elif state == "complete":
		fill = Color(COLOR.moss.r, COLOR.moss.g, COLOR.moss.b, 0.11)
		border = Color(COLOR.moss.r, COLOR.moss.g, COLOR.moss.b, 0.34)
	var style := _flat_style(fill, RADIUS.small)
	_set_content_margins(style, 8, 5)
	_set_border(style, border, 1)
	style.border_width_left = 3 if state == "current" else 1
	return style

static func _set_text_style(theme: Theme, name: String, size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)
	theme.set_color("font_shadow_color", name, Color.TRANSPARENT)

static func _set_panel(theme: Theme, name: String, color: Color, radius: int, treatment: String) -> void:
	theme.set_type_variation(name, "PanelContainer")
	var style := _flat_style(color, radius)
	_set_content_margins(style, 16, 12)
	if treatment in ["standard", "elevated", "hud", "info", "accent", "danger", "success"]:
		style.shadow_color = Color(0.02, 0.07, 0.05, 0.26 if treatment == "elevated" else 0.20)
		style.shadow_size = 10 if treatment == "elevated" else 7
		style.shadow_offset = Vector2(0.0, 4.0)
	if treatment == "accent":
		_set_left_accent(style, COLOR.accent)
	elif treatment == "info":
		_set_left_accent(style, COLOR.info)
	elif treatment == "danger":
		_set_left_accent(style, COLOR.danger)
	elif treatment == "success":
		_set_left_accent(style, COLOR.success)
	theme.set_stylebox("panel", name, style)

static func _set_button(theme: Theme, name: String, normal_fill: Color, text_color: Color, hover_fill: Color, pressed_fill: Color) -> void:
	theme.set_type_variation(name, "Button")
	theme.set_font_size("font_size", name, TYPE_SIZE.label)
	theme.set_color("font_color", name, text_color)
	theme.set_color("font_hover_color", name, text_color)
	theme.set_color("font_pressed_color", name, COLOR.text_primary if name != "PrimaryButton" else COLOR.text_on_dark)
	theme.set_color("font_focus_color", name, text_color)
	theme.set_color("font_disabled_color", name, Color(text_color.r, text_color.g, text_color.b, 0.48))
	var normal := _control_style(normal_fill)
	var hover := _control_style(hover_fill)
	var pressed := _control_style(pressed_fill)
	var disabled := _control_style(Color(normal_fill.r, normal_fill.g, normal_fill.b, 0.48))
	theme.set_stylebox("normal", name, normal)
	theme.set_stylebox("hover", name, hover)
	theme.set_stylebox("pressed", name, pressed)
	theme.set_stylebox("focus", name, _focus_style(hover))
	theme.set_stylebox("disabled", name, disabled)

static func _set_inventory_button(theme: Theme, name: String, selected: bool) -> void:
	theme.set_type_variation(name, "Button")
	theme.set_color("font_color", name, Color.TRANSPARENT)
	theme.set_color("font_hover_color", name, Color.TRANSPARENT)
	theme.set_color("font_pressed_color", name, Color.TRANSPARENT)
	theme.set_color("font_disabled_color", name, Color.TRANSPARENT)
	theme.set_stylebox("normal", name, _inventory_style(selected))
	theme.set_stylebox("hover", name, _inventory_style(selected, true))
	theme.set_stylebox("pressed", name, _inventory_style(true, true))
	theme.set_stylebox("focus", name, _focus_style(_inventory_style(selected, true)))
	theme.set_stylebox("disabled", name, _inventory_style(selected, false, true))

static func _set_reward_choice_button(theme: Theme) -> void:
	var name := "RewardChoiceButton"
	theme.set_type_variation(name, "Button")
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		theme.set_color(color_name, name, Color.TRANSPARENT)
	theme.set_stylebox("normal", name, _reward_choice_style("normal"))
	theme.set_stylebox("hover", name, _reward_choice_style("hover"))
	theme.set_stylebox("pressed", name, _reward_choice_style("pressed"))
	theme.set_stylebox("focus", name, _reward_choice_style("focus"))
	theme.set_stylebox("disabled", name, _reward_choice_style("disabled"))

static func _set_reward_surfaces(theme: Theme) -> void:
	theme.set_type_variation("SurfaceRewardSheet", "PanelContainer")
	var sheet := _flat_style(COLOR.surface_elevated, RADIUS.pill)
	_set_content_margins(sheet, SPACE.section, SPACE.large)
	sheet.content_margin_top = SPACE.section
	sheet.border_width_top = 3
	sheet.border_width_left = 1
	sheet.border_width_right = 1
	sheet.border_width_bottom = 1
	sheet.border_color = COLOR.accent
	sheet.shadow_color = Color(0.01, 0.035, 0.025, 0.58)
	sheet.shadow_size = 18
	sheet.shadow_offset = Vector2(0.0, 10.0)
	theme.set_stylebox("panel", "SurfaceRewardSheet", sheet)

	theme.set_type_variation("SurfaceRewardSeal", "PanelContainer")
	var seal := _flat_style(COLOR.accent_highlight, 43)
	_set_border(seal, COLOR.accent, 2)
	theme.set_stylebox("panel", "SurfaceRewardSeal", seal)

	theme.set_type_variation("SurfacePeekHUD", "PanelContainer")
	var peek := _flat_style(COLOR.surface_hud, RADIUS.panel)
	peek.content_margin_left = 14
	peek.content_margin_right = 10
	peek.content_margin_top = 9
	peek.content_margin_bottom = 9
	peek.border_width_left = 3
	peek.border_color = COLOR.accent
	peek.shadow_color = Color(0.01, 0.04, 0.03, 0.30)
	peek.shadow_size = 10
	peek.shadow_offset = Vector2(0.0, 5.0)
	theme.set_stylebox("panel", "SurfacePeekHUD", peek)

static func _set_objective_step_surfaces(theme: Theme) -> void:
	for state in ["future", "current", "complete"]:
		var variation := "ObjectiveStep%s" % state.capitalize()
		theme.set_type_variation(variation, "PanelContainer")
		theme.set_stylebox("panel", variation, _objective_step_style(state))

static func _shortcut_badge_style() -> StyleBoxFlat:
	var style := _flat_style(Color(COLOR.text_primary.r, COLOR.text_primary.g, COLOR.text_primary.b, 0.07), RADIUS.small)
	_set_content_margins(style, SPACE.small, SPACE.tiny)
	return style

static func _set_progress(theme: Theme, name: String, background: Color, fill: Color, radius: int) -> void:
	theme.set_type_variation(name, "ProgressBar")
	theme.set_stylebox("background", name, _flat_style(background, radius))
	theme.set_stylebox("fill", name, _flat_style(fill, radius))

static func _control_style(color: Color) -> StyleBoxFlat:
	var style := _flat_style(color, RADIUS.control)
	_set_content_margins(style, 12, 8)
	_set_border(style, COLOR.border_subtle, 1)
	return style

static func _focus_style(base: StyleBoxFlat) -> StyleBoxFlat:
	var style: StyleBoxFlat = base.duplicate()
	_set_border(style, COLOR.accent, 2)
	return style

static func _flat_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style

static func _set_content_margins(style: StyleBoxFlat, horizontal: int, vertical: int) -> void:
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical

static func _set_border(style: StyleBoxFlat, color: Color, width: int) -> void:
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.border_color = color

static func _set_left_accent(style: StyleBoxFlat, color: Color) -> void:
	style.border_width_left = 4
	style.border_color = color
