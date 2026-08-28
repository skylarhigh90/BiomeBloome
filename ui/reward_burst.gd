class_name RewardBurst
extends Control

var animation_time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

func _process(delta: float) -> void:
	if not visible:
		return
	animation_time = minf(animation_time + delta, 1.2)
	queue_redraw()
	if animation_time >= 1.2:
		set_process(false)

func restart() -> void:
	animation_time = 0.0
	set_process(true)
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.46)
	var gold := Color("#f3c75d")
	var mint := Color("#a9d59f")
	for index in range(18):
		var angle := TAU * float(index) / 18.0 + animation_time * 0.025
		var pulse := sin(animation_time * 1.7 + float(index) * 0.9) * 9.0
		var start := center + Vector2.from_angle(angle) * (278.0 + pulse)
		var finish := center + Vector2.from_angle(angle) * (336.0 + pulse)
		draw_line(start, finish, Color(gold.r, gold.g, gold.b, 0.13), 3.0, true)
	for index in range(14):
		var phase := float(index) * 2.173
		var radius := 310.0 + float((index * 37) % 92)
		var drift := sin(animation_time * 0.8 + phase) * 8.0
		var point := center + Vector2.from_angle(phase + animation_time * (0.008 if index % 2 == 0 else -0.006)) * (radius + drift)
		var sparkle_size := 3.0 + float(index % 3)
		var color := gold if index % 2 == 0 else mint
		color.a = 0.42 + sin(animation_time * 2.0 + phase) * 0.10
		draw_line(point - Vector2(sparkle_size, 0.0), point + Vector2(sparkle_size, 0.0), color, 1.8, true)
		draw_line(point - Vector2(0.0, sparkle_size), point + Vector2(0.0, sparkle_size), color, 1.8, true)
