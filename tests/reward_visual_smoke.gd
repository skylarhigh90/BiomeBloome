extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")
const HUD = preload("res://ui/game_hud.gd")

var hud
var systems
var frames := 0
var peek_mode := false
var choose_mode := false
var choice_highlight_valid := false
var choose_elapsed := 0.0

func _initialize() -> void:
	peek_mode = "peek" in OS.get_cmdline_user_args()
	choose_mode = "choose" in OS.get_cmdline_user_args()
	var backdrop := ColorRect.new()
	backdrop.color = Color("#527b51")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	systems = Systems.new(Config.make().duplicate(true))
	systems.supply_pending = true
	systems.supply_resume_speed = 2.0
	systems.simulation_speed = 0.0
	systems.supply_choices = [
		{"name": "Berry refuge", "items": {"rabbit": 1, "berry_bush": 1}},
		{"name": "Fresh harvest", "items": {"carrot_patch": 2, "berry_bush": 1}},
	]
	hud = HUD.new()
	root.add_child(hud)
	hud.setup(systems)

func _process(delta: float) -> bool:
	frames += 1
	if frames == 2:
		hud.show_supply_choices(systems.supply_choices)
	if frames == 12 and peek_mode:
		hud.toggle_supply_peek()
	if frames == 12 and choose_mode:
		hud.choose_supply_shortcut(1)
	if choose_mode and frames > 12:
		choose_elapsed += delta
	if choose_mode and not choice_highlight_valid and choose_elapsed >= 0.05:
		choice_highlight_valid = (
			hud.supply_claiming
			and hud.supply_overlay.visible
			and hud.supply_buttons[1].theme_type_variation == "RewardChoiceButtonChosen"
			and hud.supply_buttons[0].theme_type_variation == "RewardChoiceButton"
		)
	if choose_mode and choose_elapsed >= 0.75:
		var valid: bool = choice_highlight_valid and not hud.supply_overlay.visible and not hud.supply_claiming
		print(
			"Reward choice interaction passed: chosen bundle highlighted before the sheet exited."
			if valid
			else "Reward choice interaction failed: highlight=%s overlay=%s claiming=%s variation=%s" % [choice_highlight_valid, hud.supply_overlay.visible, hud.supply_claiming, hud.supply_buttons[1].theme_type_variation]
		)
		quit(0 if valid else 1)
		return false
	if frames >= 24 and not choose_mode:
		var reward_valid: bool = (
			hud.supply_overlay.visible
			and hud.supply_sheet.visible
			and hud.supply_buttons[0].visible
			and hud.supply_buttons[1].visible
			and not hud.supply_buttons[0].has_focus()
			and not hud.supply_buttons[1].has_focus()
			and hud.supply_buttons[0].theme_type_variation == "RewardChoiceButton"
			and hud.supply_buttons[1].theme_type_variation == "RewardChoiceButton"
			and hud.supply_title.text == "Meadow Mail!"
			and hud.supply_subtitle.text == "Choose one bundle for your satchel."
			and hud.supply_peek_button.content_label.text == "Peek"
		)
		var peek_valid: bool = hud.supply_peeking and hud.supply_peek_hud.visible and systems.is_paused()
		var valid: bool = peek_valid if peek_mode else reward_valid
		print("Reward visual smoke passed: %s rendered." % ("paused meadow peek" if peek_mode else "Meadow Mail overlay and both supply choices") if valid else "Reward visual smoke failed.")
		quit(0 if valid else 1)
	return false
