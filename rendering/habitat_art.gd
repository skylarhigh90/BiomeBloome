class_name HabitatArt
extends RefCounted

## Overhead woodland art, authored at its actual gameplay size. Positions are
## ground centres, so a tree can cover an animal on every side of its crown.
## Shadows are a separate ground pass. Drawing restores the identity transform.

const MEADOW := Color("#98b77f")
const MEADOW_LIGHT := Color("#b5c998")
const WOODLAND_FLOOR := Color("#718d68")
const THICKET_FLOOR := Color("#7e9465")
const SHADOW := Color("#233e32")
const TREE_RADIUS := Vector2(28.0, 25.0)
const SHRUB_RADIUS := Vector2(13.0, 10.5)

static var _crowns: Array[Dictionary] = []
static var _shrubs: Array[Dictionary] = []
static var _tree_textures: Array[Texture2D] = []
static var _shrub_textures: Array[Texture2D] = []

static func tree_footprint(size_factor: float = 1.0) -> Vector2:
	return TREE_RADIUS * size_factor

static func shrub_footprint(size_factor: float = 1.0) -> Vector2:
	return SHRUB_RADIUS * size_factor

static func draw_shadow(canvas: Node2D, position: Vector2, radii: Vector2, alpha: float = 1.0) -> void:
	# Light consistently arrives from the upper left. Three restrained ellipses
	# make a soft edge without a texture matte or dozens of concentric rings.
	var centre := position + Vector2(3.2, 4.3)
	canvas.draw_set_transform(centre, 0.0, radii * Vector2(1.07, 0.98))
	canvas.draw_circle(Vector2.ZERO, 1.0, _tint(SHADOW, alpha * 0.035))
	canvas.draw_set_transform(centre, 0.0, radii * Vector2(0.97, 0.88))
	canvas.draw_circle(Vector2.ZERO, 1.0, _tint(SHADOW, alpha * 0.055))
	canvas.draw_set_transform(centre, 0.0, radii * Vector2(0.83, 0.76))
	canvas.draw_circle(Vector2.ZERO, 1.0, _tint(SHADOW, alpha * 0.085))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_tree(canvas: Node2D, position: Vector2, size_factor: float, tone: float, alpha: float = 1.0, critical: float = 0.0) -> void:
	_ensure_geometry()
	var variant := clampi(int(tone * 3.0), 0, 2)
	canvas.draw_set_transform(position, 0.0, Vector2.ONE * size_factor)
	# Composite the authored vector layers once, then fade the whole crown.
	# Per-polygon alpha would accumulate and obscure animals under its centre.
	var tint := Color.WHITE.lerp(Color("#c2ad8a"), clampf(critical, 0.0, 1.0) * 0.42)
	tint.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_texture_rect(_tree_textures[variant], Rect2(-32.0, -30.0, 64.0, 60.0), false, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_shrub(canvas: Node2D, position: Vector2, size_factor: float, tone: float, alpha: float = 1.0, critical: float = 0.0) -> void:
	_ensure_geometry()
	var variant := clampi(int(tone * 3.0), 0, 2)
	canvas.draw_set_transform(position, 0.0, Vector2.ONE * size_factor)
	var tint := Color.WHITE.lerp(Color("#c2ad8a"), clampf(critical, 0.0, 1.0) * 0.42)
	tint.a = clampf(alpha, 0.0, 1.0)
	canvas.draw_texture_rect(_shrub_textures[variant], Rect2(-15.0, -13.0, 30.0, 26.0), false, tint)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _tint(base: Color, alpha: float, critical: float = 0.0) -> Color:
	var color := base.lerp(Color("#9b8968"), clampf(critical, 0.0, 1.0) * 0.38)
	color.a = clampf(alpha, 0.0, 1.0)
	return color

static func _lobe(centre: Vector2, radii: Vector2, count: int, phase: float, depth: float = 0.085) -> PackedVector2Array:
	var points := PackedVector2Array()
	const STEPS := 64
	for index in range(STEPS + 1):
		var angle := float(index % STEPS) / float(STEPS) * TAU
		var edge := 1.0 + sin(angle * float(count) + phase) * depth
		edge += sin(angle * 3.0 - phase * 0.8) * 0.036
		points.append(centre + Vector2(cos(angle), sin(angle)) * radii * edge)
	return points

static func _arc(centre: Vector2, radii: Vector2, start: float, end: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(9):
		var angle := lerpf(start, end, float(index) / 8.0)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radii)
	return points

static func _soften(points: PackedVector2Array) -> PackedVector2Array:
	var rounded := PackedVector2Array()
	for index in range(points.size()):
		var point := points[index]
		var following := points[(index + 1) % points.size()]
		rounded.append(point.lerp(following, 0.10))
		rounded.append(point.lerp(following, 0.90))
	rounded.append(rounded[0])
	return rounded

static func _evergreen(variant: int) -> Dictionary:
	var outline := PackedVector2Array()
	var fans: Array[PackedVector2Array] = []
	var exposure: Array[float] = []
	var highlights: Array[PackedVector2Array] = []
	var count := 7 + variant
	var phase := -0.63 + float(variant) * 0.27
	var sector := TAU / float(count)
	var squash := Vector2(1.0 - float(variant) * 0.035, 0.87 + float(variant) * 0.035)
	var centre := Vector2(-1.6, -2.0)
	for index in range(count):
		var angle := phase + float(index) * sector
		var length := 27.0 + sin(float(index) * 2.4 + float(variant)) * 1.2
		# Alternating branch lengths avoid a regular badge-like radial silhouette.
		if index % 3 == 1:
			length -= 3.0
		for sample in [[-0.49, 0.51], [-0.36, 0.67], [-0.25, 0.62], [-0.24, 0.81], [-0.10, 0.75], [-0.022, 1.0], [0.035, 0.96], [0.13, 0.72], [0.28, 0.78], [0.24, 0.59], [0.40, 0.62]]:
			outline.append(Vector2.from_angle(angle + sector * float(sample[0])) * length * float(sample[1]) * squash)
		var along := Vector2.from_angle(angle)
		var across := along.orthogonal()
		var width := length * (0.27 - float(variant) * 0.015)
		var fan := PackedVector2Array([
			centre + along * 2.5 - across * 1.9,
			centre + along * length * 0.30 - across * width * 0.52,
			centre + along * length * 0.43 - across * width,
			centre + along * length * 0.71 - across * width * 0.45,
			centre + along * length * 0.91,
			centre + along * length * 0.70 + across * width * 0.28,
			centre + along * length * 0.43 + across * width * 0.63,
			centre + along * 2.0 + across * 1.3,
		])
		for point_index in range(fan.size()):
			fan[point_index] *= squash
		fans.append(_soften(fan))
		exposure.append(0.27 + maxf(0.0, -along.dot(Vector2(0.55, 0.83))) * 0.61)
		if index == count - 2 or index == count - 3:
			highlights.append(PackedVector2Array([
				(centre + along * length * 0.31 - across * 0.4) * squash,
				(centre + along * length * 0.48 - across * 0.7) * squash,
				(centre + along * length * 0.60 - across * 0.2) * squash,
			]))
	var body := PackedVector2Array()
	var upper_whorl := PackedVector2Array()
	for point in outline:
		body.append(point * 0.94 + Vector2(-0.6, -0.8))
		upper_whorl.append(point.rotated(0.19) * 0.59 + centre)
	return {
		"outline": _soften(outline),
		"body": _soften(body),
		"fans": fans,
		"exposure": exposure,
		"upper_whorl": _soften(upper_whorl),
		"leader": _soften(PackedVector2Array([
			Vector2(-4.5, -9.0), Vector2(-1.0, -5.0), Vector2(1.2, -3.0),
			Vector2(-0.3, -1.8), Vector2(0.3, 1.0), Vector2(-3.0, -0.2),
			Vector2(-4.8, -2.0), Vector2(-3.6, -4.1),
		])),
		"highlights": highlights,
	}

static func _svg_points(points: PackedVector2Array) -> String:
	var result := ""
	for point in points:
		result += "%.3f,%.3f " % [point.x, point.y]
	return result

static func _svg_shape(points: PackedVector2Array, color: Color) -> String:
	return '<polygon points="%s" fill="#%s"/>' % [_svg_points(points), color.to_html(false)]

static func _tree_texture(shapes: Dictionary, tone: float) -> Texture2D:
	var edge := Color("#3f6653").lerp(Color("#4a6b50"), tone)
	var main := Color("#577f64").lerp(Color("#648563"), tone)
	var upper := Color("#749571").lerp(Color("#829b72"), tone)
	var light := Color("#a6bc8e").lerp(Color("#b6c399"), tone)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="60" viewBox="-32 -30 64 60">'
	svg += _svg_shape(shapes["outline"], edge)
	svg += _svg_shape(shapes["body"], main)
	for index in range(shapes["fans"].size()):
		svg += _svg_shape(shapes["fans"][index], main.lerp(upper, float(shapes["exposure"][index])))
	svg += _svg_shape(shapes["upper_whorl"], main.lerp(upper, 0.68))
	svg += _svg_shape(shapes["leader"], upper.lerp(light, 0.35))
	for highlight in shapes["highlights"]:
		svg += '<polyline points="%s" fill="none" stroke="#%s" stroke-width="0.7" stroke-linecap="round" opacity="0.46"/>' % [_svg_points(highlight), light.to_html(false)]
	svg += '</svg>'
	return _composite_texture(svg)

static func _shrub_texture(shapes: Dictionary, tone: float) -> Texture2D:
	var edge := Color("#4d6748").lerp(Color("#596e4d"), tone)
	var main := Color("#70885b").lerp(Color("#7e9365"), tone)
	var light := Color("#a1b57f").lerp(Color("#b1bc88"), tone)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="30" height="26" viewBox="-15 -13 30 26">'
	svg += _svg_shape(shapes["outline"], edge)
	svg += _svg_shape(shapes["body"], main)
	for index in range(shapes["lobes"].size()):
		svg += _svg_shape(shapes["lobes"][index], main.lerp(light, 0.20 + float(index) * 0.13))
	for highlight in shapes["highlights"]:
		svg += '<polyline points="%s" fill="none" stroke="#%s" stroke-width="0.8" stroke-linecap="round" opacity="0.65"/>' % [_svg_points(highlight), light.to_html(false)]
	svg += '</svg>'
	return _composite_texture(svg)

static func _composite_texture(svg: String) -> Texture2D:
	var picture := Image.new()
	var result := picture.load_svg_from_string(svg, 4.0)
	assert(result == OK, "The authored habitat SVG must rasterize successfully.")
	picture.generate_mipmaps()
	return ImageTexture.create_from_image(picture)

static func _ensure_geometry() -> void:
	if not _crowns.is_empty():
		return
	for variant in range(3):
		var phase := float(variant) * 1.31
		_crowns.append(_evergreen(variant))
		_tree_textures.append(_tree_texture(_crowns[variant], float(variant) / 2.0))
		_shrubs.append({
			"outline": _lobe(Vector2.ZERO, Vector2(12.0, 9.4), 7 + variant, phase, 0.075),
			"body": _lobe(Vector2(-0.5, -1.0), Vector2(11.3, 8.5), 7 + variant, phase, 0.085),
			"lobes": [
				_lobe(Vector2(4.7, -0.6), Vector2(6.0, 5.2), 5, phase, 0.045),
				_lobe(Vector2(-5.0, -1.7), Vector2(6.2, 5.8), 5, phase + 1.0, 0.04),
				_lobe(Vector2(-0.5, -4.2), Vector2(5.5, 4.6), 5, phase + 2.0, 0.055),
			],
			"highlights": [
				_arc(Vector2(-5.2, -1.2), Vector2(3.8, 3.7), PI * 1.04, PI * 1.5),
				_arc(Vector2(0.0, -3.7), Vector2(3.0, 3.0), PI * 1.19, PI * 1.58),
			],
		})
		_shrub_textures.append(_shrub_texture(_shrubs[variant], float(variant) / 2.0))
