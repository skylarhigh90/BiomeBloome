class_name EntityGlyph
extends Control

var kind := "rabbit"
var accent := Color("#6f9b5c")
var show_backplate := true
var muted := false

func configure(p_kind: String, p_accent: Color = Color.TRANSPARENT, p_backplate: bool = true) -> EntityGlyph:
	kind = p_kind
	accent = _default_accent(kind) if p_accent == Color.TRANSPARENT else p_accent
	show_backplate = p_backplate
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self

func set_muted(value: bool) -> void:
	muted = value
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var unit := minf(size.x, size.y) / 48.0
	var alpha := 0.38 if muted else 1.0
	if show_backplate:
		draw_circle(center, minf(size.x, size.y) * 0.46, Color(accent.r, accent.g, accent.b, 0.18 * alpha))
	draw_set_transform(center, 0.0, Vector2.ONE * unit)
	match kind:
		"rabbit":
			_draw_rabbit(alpha)
		"fox":
			_draw_fox(alpha)
		"carrot_patch":
			_draw_carrot_patch(alpha)
		"berry_bush":
			_draw_berry_bush(alpha)
		"supply":
			_draw_supply(alpha)
		"leaf":
			_draw_leaf(alpha)
		"eye":
			_draw_eye(alpha)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_rabbit(alpha: float) -> void:
	var shadow := Color(0.12, 0.18, 0.14, 0.14 * alpha)
	var fur := Color(0.98, 0.95, 0.86, alpha)
	var outline := Color(0.20, 0.28, 0.23, alpha)
	_draw_oval(Vector2(-1.0, 13.0), Vector2(14.0, 4.2), shadow)
	draw_colored_polygon(PackedVector2Array([Vector2(1.0, -7.0), Vector2(2.5, -21.0), Vector2(7.0, -8.0)]), fur)
	draw_colored_polygon(PackedVector2Array([Vector2(-5.0, -7.0), Vector2(-7.0, -20.0), Vector2(-1.0, -8.0)]), fur.darkened(0.04))
	draw_line(Vector2(2.7, -10.0), Vector2(3.2, -17.0), Color(0.84, 0.56, 0.60, 0.7 * alpha), 1.4, true)
	draw_circle(Vector2(-3.0, 3.0), 10.5, outline)
	draw_circle(Vector2(-3.0, 2.0), 9.0, fur)
	draw_circle(Vector2(5.0, -1.5), 6.6, fur.lightened(0.04))
	draw_circle(Vector2(8.0, -3.5), 1.2, outline)
	draw_circle(Vector2(-12.0, 3.0), 3.5, Color(1.0, 1.0, 0.98, alpha))

func _draw_fox(alpha: float) -> void:
	var orange := Color(0.88, 0.39, 0.20, alpha)
	var cream := Color(0.98, 0.86, 0.69, alpha)
	var dark := Color(0.22, 0.25, 0.22, alpha)
	_draw_oval(Vector2(-1.0, 13.0), Vector2(15.0, 4.0), Color(0.12, 0.18, 0.14, 0.15 * alpha))
	draw_circle(Vector2(-9.0, 5.0), 8.0, orange.darkened(0.11))
	draw_circle(Vector2(-15.0, 8.0), 4.0, cream)
	draw_colored_polygon(PackedVector2Array([Vector2(-8.0, -2.0), Vector2(-7.0, -15.0), Vector2(0.0, -6.0)]), orange.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(2.0, -5.0), Vector2(8.0, -15.0), Vector2(10.0, -2.0)]), orange.darkened(0.08))
	draw_circle(Vector2(1.0, 2.0), 11.0, orange)
	draw_colored_polygon(PackedVector2Array([Vector2(-5.0, 2.0), Vector2(14.0, 6.0), Vector2(4.0, 12.0)]), cream)
	draw_circle(Vector2(14.0, 6.0), 1.6, dark)
	draw_circle(Vector2(5.0, -1.0), 1.2, dark)

func _draw_carrot_patch(alpha: float) -> void:
	var soil := Color(0.38, 0.29, 0.17, 0.25 * alpha)
	var orange := Color(0.95, 0.39, 0.12, alpha)
	var orange_dark := Color(0.72, 0.24, 0.07, alpha)
	var leaf_dark := Color(0.20, 0.45, 0.25, alpha)
	var leaf_light := Color(0.38, 0.66, 0.29, alpha)
	_draw_oval(Vector2(0.0, 13.0), Vector2(18.0, 5.5), soil)
	# A single large exposed root reads as food even at the inventory's smallest size.
	draw_colored_polygon(PackedVector2Array([Vector2(-8.5, -3.0), Vector2(8.0, -3.8), Vector2(6.0, 5.0), Vector2(0.5, 18.0), Vector2(-5.4, 5.5)]), orange_dark)
	draw_colored_polygon(PackedVector2Array([Vector2(-6.8, -2.4), Vector2(6.3, -3.0), Vector2(4.7, 4.3), Vector2(0.4, 14.9), Vector2(-4.0, 4.8)]), orange)
	draw_line(Vector2(-4.6, 2.2), Vector2(2.0, 1.4), Color(1.0, 0.68, 0.32, 0.78 * alpha), 1.4, true)
	draw_line(Vector2(-2.7, 7.0), Vector2(2.7, 6.3), Color(0.72, 0.22, 0.07, 0.55 * alpha), 1.2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-2.5, -3.0), Vector2(-13.0, -17.0), Vector2(-5.0, -5.2)]), leaf_dark)
	draw_colored_polygon(PackedVector2Array([Vector2(-1.0, -3.0), Vector2(0.5, -20.0), Vector2(4.0, -4.0)]), leaf_light)
	draw_colored_polygon(PackedVector2Array([Vector2(1.0, -3.0), Vector2(13.0, -15.0), Vector2(5.0, -3.8)]), leaf_dark.lightened(0.08))

func _draw_berry_bush(alpha: float) -> void:
	var leaf_dark := Color(0.20, 0.42, 0.28, alpha)
	var leaf_light := Color(0.29, 0.53, 0.33, alpha)
	_draw_oval(Vector2(0.0, 14.0), Vector2(17.0, 4.5), Color(0.12, 0.18, 0.13, 0.15 * alpha))
	for index in range(7):
		var angle := float(index) / 7.0 * TAU
		var position := Vector2.from_angle(angle) * Vector2(8.0, 6.0)
		draw_circle(position, 7.0, leaf_dark.lerp(leaf_light, float(index % 2)))
	for position in [Vector2(-8.0, -1.0), Vector2(0.0, -7.0), Vector2(8.0, 0.0), Vector2(-2.0, 5.0), Vector2(7.0, 7.0)]:
		draw_circle(position, 2.4, Color(0.60, 0.19, 0.37, alpha))
		draw_circle(position + Vector2(-0.6, -0.7), 0.7, Color(1.0, 0.76, 0.78, 0.75 * alpha))

func _draw_supply(alpha: float) -> void:
	var paper := Color(0.95, 0.84, 0.58, alpha)
	var seam := Color(0.43, 0.34, 0.20, alpha)
	draw_colored_polygon(PackedVector2Array([Vector2(-15.0, -10.0), Vector2(15.0, -10.0), Vector2(12.0, 14.0), Vector2(-12.0, 14.0)]), paper)
	draw_line(Vector2(-15.0, -10.0), Vector2(0.0, 1.0), seam, 1.5, true)
	draw_line(Vector2(15.0, -10.0), Vector2(0.0, 1.0), seam, 1.5, true)
	draw_circle(Vector2(0.0, 2.0), 4.2, Color(0.32, 0.56, 0.34, alpha))
	draw_line(Vector2(0.0, 5.0), Vector2(5.0, -3.0), Color(0.92, 0.86, 0.63, alpha), 1.2, true)

func _draw_leaf(alpha: float) -> void:
	var leaf := Color(accent.r, accent.g, accent.b, alpha)
	draw_colored_polygon(PackedVector2Array([Vector2(-14.0, 8.0), Vector2(-10.0, -9.0), Vector2(12.0, -14.0), Vector2(15.0, 3.0), Vector2(3.0, 15.0)]), leaf)
	draw_line(Vector2(-9.0, 9.0), Vector2(10.0, -10.0), leaf.lightened(0.42), 1.8, true)

func _draw_eye(alpha: float) -> void:
	var outline := Color(accent.r, accent.g, accent.b, alpha)
	var fill := Color(1.0, 0.98, 0.89, 0.92 * alpha)
	var points := PackedVector2Array()
	for index in range(13):
		var t := float(index) / 12.0
		points.append(Vector2(lerpf(-18.0, 18.0, t), -sin(t * PI) * 9.0))
	for index in range(12, -1, -1):
		var t := float(index) / 12.0
		points.append(Vector2(lerpf(-18.0, 18.0, t), sin(t * PI) * 9.0))
	draw_colored_polygon(points, fill)
	draw_polyline(points, outline, 2.0, true)
	draw_circle(Vector2.ZERO, 6.8, outline)
	draw_circle(Vector2(-1.8, -2.0), 2.0, Color(1.0, 0.97, 0.79, 0.90 * alpha))

func _draw_oval(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := float(index) / 24.0 * TAU
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)

func _default_accent(value: String) -> Color:
	match value:
		"rabbit":
			return Color("#d59a65")
		"fox":
			return Color("#df6d3f")
		"carrot_patch":
			return Color("#dc7a32")
		"berry_bush":
			return Color("#9d5270")
		"supply":
			return Color("#4c8c91")
		"eye":
			return Color("#234137")
	return Color("#6f9b5c")
