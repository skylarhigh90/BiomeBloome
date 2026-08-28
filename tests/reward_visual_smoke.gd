extends SceneTree

const Config = preload("res://config/game_config.gd")
const Systems = preload("res://game/game_systems.gd")
const HUD = preload("res://ui/game_hud.gd")

var hud
var systems
var frames := 0
var peek_mode := false

func _initialize() -> void:
	peek_mode = "peek" in OS.get_cmdline_user_args()
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

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		hud.show_supply_choices(systems.supply_choices)
	if frames == 12 and peek_mode:
		hud.toggle_supply_peek()
	if frames >= 24:
		var reward_valid: bool = hud.supply_overlay.visible and hud.supply_sheet.visible and hud.supply_buttons[0].visible and hud.supply_buttons[1].visible and hud.supply_title.text == "Meadow Mail!"
		var peek_valid: bool = hud.supply_peeking and hud.supply_peek_hud.visible and systems.is_paused()
		var valid: bool = peek_valid if peek_mode else reward_valid
		print("Reward visual smoke passed: %s rendered." % ("paused meadow peek" if peek_mode else "Meadow Mail overlay and both supply choices") if valid else "Reward visual smoke failed.")
		quit(0 if valid else 1)
	return false
