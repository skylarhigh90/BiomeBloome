class_name ForageArt
extends RefCounted

## Illustrated forage, authored in the same overhead vocabulary as AnimalArt
## and HabitatArt. The caller owns transforms, ground shadows and site quality.
## Stock changes the edible parts; recovery never displays mature food.

const LEAF_EDGE := Color("#4e6b49")
const LEAF_MAIN := Color("#708953")
const LEAF_LIGHT := Color("#a0b676")
const SHOOT := Color("#b8cc83")
const SOIL := Color("#927454")
const SOIL_EDGE := Color("#7b654d")
const STEM := Color("#776c4b")
const BERRY := Color("#b45265")
const BERRY_EDGE := Color("#80505a")

static var _leaf_outline := PackedVector2Array()
static var _root_outline := PackedVector2Array()
static var _soil_outline := PackedVector2Array()
static var _berry_canopy := PackedVector2Array()
static var _circle := PackedVector2Array()


static func draw_carrot(canvas: Node2D, stock_ratio: float, ecology_state: String, entity_id: int, time: float) -> void:
	_ensure_geometry()
	var recovering := ecology_state == "recovering"
	var depleted := ecology_state == "depleted"
	_polygon(canvas, _soil_outline, SOIL if not depleted else SOIL.lerp(Color("#a38a69"), 0.24), SOIL_EDGE, 0.55)
	# Quiet soil marks are part of the bed, not a stock-dependent habitat ring.
	canvas.draw_line(Vector2(-7.8, 4.7), Vector2(-4.9, 5.1), Color("#ad916a"), 0.65, true)
	canvas.draw_line(Vector2(5.2, -2.8), Vector2(8.1, -2.2), Color("#79634a"), 0.65, true)
	var sway := sin(time * 1.3 + float(entity_id) * 1.19) * 0.22
	if depleted or recovering:
		for index in range(3):
			var center := Vector2(-6.0 + float(index) * 6.0, 0.8 + float(index % 2) * 1.2)
			_ellipse(canvas, center + Vector2(0.0, 0.7), Vector2(2.1, 0.85), SOIL_EDGE)
			if depleted:
				canvas.draw_line(center, center + Vector2(0.2, -2.5), STEM, 1.15, true)
				canvas.draw_line(center + Vector2(0.1, -1.2), center + Vector2(-1.2, -2.2), STEM, 0.8, true)
				canvas.draw_line(center + Vector2(-0.5, -2.5), center + Vector2(0.8, -2.5), Color("#a7aa75"), 0.7, true)
			else:
				var top := center + Vector2(sway, -1.9 - float(index % 2) * 0.6)
				canvas.draw_line(center, top, LEAF_MAIN, 0.8, true)
				_leaf(canvas, top, top + Vector2(-2.5, -2.1), 1.0, LEAF_LIGHT, LEAF_EDGE, 0.35)
				_leaf(canvas, top, top + Vector2(2.7, -1.8), 1.15, SHOOT, LEAF_EDGE, 0.35)
		return

	var count := 4 if ecology_state == "abundant" else (3 if ecology_state == "healthy" else (2 if stock_ratio >= 0.20 else 1))
	var roots: Array[Vector2] = []
	match count:
		1:
			roots = [Vector2(0.0, -0.6)]
		2:
			roots = [Vector2(-4.5, -0.7), Vector2(4.5, 0.0)]
		3:
			roots = [Vector2(-6.3, -0.9), Vector2(0.0, 0.1), Vector2(6.3, -0.5)]
		_:
			roots = [Vector2(-7.4, -1.0), Vector2(-2.5, 0.2), Vector2(2.5, -1.2), Vector2(7.4, 0.2)]
	for index in range(count):
		var top: Vector2 = roots[index]
		var lean := (float(index % 2) * 2.0 - 1.0) * 0.10
		var tone := float(posmod(entity_id + index, 3)) / 2.0
		var root_color := Color("#d9894c").lerp(Color("#e4a15e"), tone)
		var root_points := _map(_root_outline, top, Vector2(1.0, 0.0).rotated(lean), Vector2(0.0, 1.0).rotated(lean))
		_polygon(canvas, root_points, root_color, Color("#a77446"), 0.5)
		canvas.draw_line(top + Vector2(-0.7, 1.2), top + Vector2(-0.2, 4.8), Color("#efbb78"), 0.85, true)
		canvas.draw_line(top + Vector2(0.3, 2.1), top + Vector2(1.4, 1.9), Color("#b77b44"), 0.55, true)
		var leaf_root := top + Vector2(0.0, -0.9)
		for sprig in range(3):
			var direction := Vector2(float(sprig - 1) * 2.8 + sway, -5.6 - float(sprig % 2) * 1.8)
			var tip := leaf_root + direction
			var green := LEAF_MAIN.lerp(LEAF_LIGHT, float(sprig) * 0.23)
			canvas.draw_line(leaf_root, tip, green, 0.7, true)
			# A compound leaf reads as carrot foliage at the actual 30 px size.
			_leaf(canvas, leaf_root.lerp(tip, 0.30), leaf_root.lerp(tip, 0.76) + Vector2(-1.35, 0.0), 0.86, green)
			_leaf(canvas, leaf_root.lerp(tip, 0.48), tip + Vector2(1.0, 0.0), 0.94, green)


static func draw_berry(canvas: Node2D, stock_ratio: float, ecology_state: String, entity_id: int, time: float) -> void:
	_ensure_geometry()
	var depleted := ecology_state == "depleted"
	var recovering := ecology_state == "recovering"
	var sparse := ecology_state == "sparse"
	var identity := float(posmod(entity_id, 7)) * 0.07
	var sway := sin(time * 1.1 + float(entity_id) * 0.73) * 0.18
	var crown_scale := 0.69 if depleted else (0.78 if recovering else (0.88 if sparse else 1.0))
	# Trimmed woody forks remain visible after grazing. Recovery grows foliage
	# from these same anchors rather than substituting a fruit-like sparkle.
	for index in range(5):
		var angle := float(index) / 5.0 * TAU + identity - 0.35
		var direction := Vector2.from_angle(angle)
		var tip := direction * (7.0 if depleted else 8.6) * crown_scale
		canvas.draw_line(Vector2.ZERO, tip, Color("#62694a"), 1.5 if depleted else 1.2, true)
		var fork := tip * 0.69 + direction.rotated(0.8) * 2.0
		canvas.draw_line(tip * 0.47, fork, STEM, 0.85, true)
	if depleted:
		for index in range(3):
			var angle := float(index) / 3.0 * TAU + identity
			var root := Vector2.from_angle(angle) * 2.5
			_leaf(canvas, root, root + Vector2.from_angle(angle + 0.4) * 3.8, 1.3, Color("#87916b"), LEAF_EDGE, 0.4)
		return

	var base := LEAF_MAIN.lerp(LEAF_LIGHT, 0.35 if recovering else 0.0)
	_polygon(canvas, _map(_berry_canopy, Vector2.ZERO, Vector2(crown_scale, 0.0), Vector2(0.0, crown_scale)), base, LEAF_EDGE, 0.65)
	for index in range(8):
		var angle := float(index) / 8.0 * TAU + identity
		var root := Vector2.from_angle(angle) * (1.3 + float(index % 2) * 0.5) * crown_scale
		var length := (9.5 + float(index % 3) * 0.7) * crown_scale
		var tip := Vector2.from_angle(angle) * length + Vector2(sway, -0.7)
		var upper := maxf(0.0, -Vector2.from_angle(angle).dot(Vector2(0.6, 0.8)))
		var color := base.lerp(SHOOT if recovering else LEAF_LIGHT, 0.10 + upper * 0.55)
		_leaf(canvas, root, tip, (3.2 if recovering else 3.5) * crown_scale, color, LEAF_EDGE, 0.45)
		if index % 3 == 0:
			canvas.draw_line(root.lerp(tip, 0.22), root.lerp(tip, 0.76), color.lerp(LEAF_LIGHT, 0.50), 0.6, true)
	# New central leaves connect the radial clusters and keep the crown organic.
	_leaf(canvas, Vector2(1.6, 2.5) * crown_scale, Vector2(-3.8, -3.4) * crown_scale, 3.0 * crown_scale, LEAF_LIGHT if recovering else base.lerp(LEAF_LIGHT, 0.23), LEAF_EDGE, 0.35)
	if recovering:
		return
	var count := 7 if ecology_state == "abundant" else (4 if ecology_state == "healthy" else 2)
	var berry_positions: Array[Vector2] = [
		Vector2(-5.2, -3.8), Vector2(4.8, 2.8), Vector2(3.8, -5.1), Vector2(-3.5, 4.5),
		Vector2(0.0, -0.7), Vector2(-7.0, 1.1), Vector2(7.5, -1.6),
	]
	var berry_scale := 0.90 + clampf(stock_ratio, 0.0, 1.0) * 0.10
	for index in range(count):
		var center: Vector2 = berry_positions[index].rotated(identity) * crown_scale
		_ellipse(canvas, center, Vector2(1.75, 1.6) * berry_scale, BERRY, BERRY_EDGE, 0.4)
		_ellipse(canvas, center + Vector2(-0.45, -0.48), Vector2(0.54, 0.43), Color("#e09a98"))
		canvas.draw_line(center + Vector2(0.0, -1.25), center + Vector2(0.15, -1.8), LEAF_EDGE, 0.55, true)


static func _leaf(canvas: Node2D, root: Vector2, tip: Vector2, width: float, color: Color, outline: Color = Color.TRANSPARENT, stroke: float = 0.0) -> void:
	var along := tip - root
	var across := along.normalized().orthogonal() * width
	_polygon(canvas, _map(_leaf_outline, root, along, across), color, outline, stroke)


static func _ellipse(canvas: Node2D, center: Vector2, radii: Vector2, color: Color, outline: Color = Color.TRANSPARENT, stroke: float = 0.0) -> void:
	_polygon(canvas, _map(_circle, center, Vector2(radii.x, 0.0), Vector2(0.0, radii.y)), color, outline, stroke)


static func _map(points: PackedVector2Array, origin: Vector2, along: Vector2, across: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(origin + along * point.x + across * point.y)
	return result


static func _polygon(canvas: Node2D, points: PackedVector2Array, color: Color, outline: Color = Color.TRANSPARENT, stroke: float = 0.0) -> void:
	canvas.draw_colored_polygon(points, color)
	if stroke > 0.0:
		var edge := points.duplicate()
		edge.append(edge[0])
		canvas.draw_polyline(edge, outline, stroke, true)


static func _smooth(knots: PackedVector2Array, subdivisions: int = 4) -> PackedVector2Array:
	var result := PackedVector2Array()
	var count := knots.size()
	for index in range(count):
		var a := knots[(index + count - 1) % count]
		var b := knots[index]
		var c := knots[(index + 1) % count]
		var d := knots[(index + 2) % count]
		for step in range(subdivisions):
			var t := float(step) / float(subdivisions)
			result.append((b * 2.0 + (c - a) * t + (a * 2.0 - b * 5.0 + c * 4.0 - d) * t * t + (-a + b * 3.0 - c * 3.0 + d) * t * t * t) * 0.5)
	return result


static func _ensure_geometry() -> void:
	if not _leaf_outline.is_empty():
		return
	_leaf_outline = _smooth(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.32, -0.77), Vector2(0.63, -0.80),
		Vector2(1.0, 0.0), Vector2(0.60, 0.82), Vector2(0.28, 0.66),
	]))
	_root_outline = _smooth(PackedVector2Array([
		Vector2(-1.8, -0.7), Vector2(1.8, -0.7), Vector2(1.85, 1.8),
		Vector2(0.1, 6.6), Vector2(-1.5, 2.9),
	]))
	_soil_outline = _smooth(PackedVector2Array([
		Vector2(-11.4, -0.7), Vector2(-7.9, -4.0), Vector2(-1.3, -4.4),
		Vector2(6.4, -3.8), Vector2(11.5, -0.7), Vector2(10.7, 5.0),
		Vector2(5.2, 7.3), Vector2(-2.7, 7.5), Vector2(-10.0, 5.8),
	]))
	_berry_canopy = _smooth(PackedVector2Array([
		Vector2(-10.7, -1.8), Vector2(-6.0, -8.2), Vector2(0.0, -9.3),
		Vector2(7.2, -6.6), Vector2(10.7, 0.3), Vector2(6.5, 7.6),
		Vector2(-1.6, 9.2), Vector2(-8.8, 5.4),
	]))
	for index in range(16):
		_circle.append(Vector2.from_angle(float(index) * TAU / 16.0))
