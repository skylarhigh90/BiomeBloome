class_name AnimalArt
extends RefCounted

## Small, continuously rotatable overhead rigs. The caller owns the world
## transform, ground shadow and gameplay indicators; +X is the animal's nose.
## All articulation uses the supplied simulation presentation clock/phase.

const INK := Color("#5e6251")
const FOX_INK := Color("#714f3d")
const EYE := Color("#303c31")
const CREAM := Color("#f6edda")
const PAW := Color("#574f40")


static func draw_rabbit(canvas: Node2D, animal: Dictionary, pose: Dictionary, body_color: Color) -> void:
	var phase := float(pose.get("phase", 0.0)) * TAU
	var moving := clampf(float(pose.get("move", 0.0)), 0.0, 1.0)
	var time := float(pose.get("time", 0.0))
	var behavior := str(animal.get("behavior", "observe"))
	var resting := behavior in ["loaf", "socialize", "rest"]
	var eating := behavior == "eat"
	var watching := behavior == "observe"
	var identity := float(animal.get("id", 0)) * 1.73
	var quiet := 1.0 - moving
	var breath := sin(time * 2.2 + identity) * 0.10 * quiet
	var chew := sin(time * 12.0 + identity) * 0.34 if eating else 0.0
	var shade := body_color.lerp(Color("#b8bba2"), 0.36)
	var highlight := body_color.lerp(Color("#fffaf0"), 0.54)
	var outline := body_color.lerp(INK, 0.62)
	var flight := sin(clampf((fposmod(float(pose.get("phase", 0.0)), 1.0) - 0.15) / 0.70, 0.0, 1.0) * PI)

	# Rabbits propel themselves with a paired hind-leg push, then reach their
	# front paws forward to land. Tucking the feet in flight changes silhouette.
	for side in [-1.0, 1.0]:
		var hind := Vector2(-4.2 - sin(phase) * moving * 2.3, side * (5.0 + (1.0 - flight) * moving * 1.5))
		var front := Vector2(4.1 + cos(phase + 1.5) * moving * 2.5, side * (3.9 + (1.0 - flight) * moving * 1.0))
		if resting:
			hind = hind.lerp(Vector2(-3.0, side * 4.9), quiet)
			front = front.lerp(Vector2(3.5, side * 3.4), quiet)
		_leg(canvas, Vector2(-3.2, side * 3.7), hind, Vector2(2.6, 1.4), shade, outline, side * 0.10)
		_leg(canvas, Vector2(2.4, side * 2.8), front, Vector2(1.9, 1.12), body_color, outline, side * 0.06)

	_ellipse(canvas, Vector2(-9.2, 0.1), Vector2(2.8, 2.65), shade, outline, 0.55)
	_ellipse(canvas, Vector2(-9.7, -0.3), Vector2(2.35, 2.05), highlight)
	_shape(canvas, PackedVector2Array([
		Vector2(-8.3, -3.7), Vector2(-4.7, -6.2 - breath), Vector2(0.0, -5.8),
		Vector2(4.5, -3.7), Vector2(6.3, -0.1), Vector2(4.3, 3.9),
		Vector2(-0.2, 5.9 + breath), Vector2(-5.5, 5.8), Vector2(-8.6, 2.5),
	]), body_color, outline, 0.65)
	# A single broad haunch and shoulder highlight remain readable at game size.
	_shape(canvas, PackedVector2Array([
		Vector2(-7.7, 1.0), Vector2(-4.7, 3.5), Vector2(0.5, 4.3),
		Vector2(3.7, 2.9), Vector2(1.9, 5.0), Vector2(-3.0, 5.3), Vector2(-6.9, 3.7),
	]), shade)
	_ellipse(canvas, Vector2(-3.9, -1.8 - breath), Vector2(3.8, 2.55), highlight, Color.TRANSPARENT, 0.0, -0.12)

	# The ears attach behind the head and point back, as an overhead animal's
	# ears should. Rest lays them over the shoulders; vigilance fans them out.
	for side in [-1.0, 1.0]:
		var twitch := sin(time * 2.1 + identity + side) * 0.16 * quiet
		var ear_root := Vector2(4.7, side * 2.0)
		var ear_tip := Vector2(-2.6 - moving * 1.4, side * (8.1 - moving * 1.15 + twitch))
		if resting:
			ear_tip = ear_tip.lerp(Vector2(-4.9, side * 4.65), quiet)
		elif watching:
			ear_tip = ear_tip.lerp(Vector2(1.0, side * 10.2), quiet)
		elif eating:
			ear_tip = ear_tip.lerp(Vector2(-3.8, side * 6.2), quiet)
		_leaf(canvas, ear_root, ear_tip, side * 0.3, 1.65, body_color, outline, 0.55)
		_leaf(canvas, ear_root.lerp(ear_tip, 0.23), ear_root.lerp(ear_tip, 0.84), side * 0.10, 0.61, Color("#d5b5a4"))

	var head := Vector2(5.4 + ((0.75 + chew) * quiet if eating else 0.0), 0.0)
	_shape(canvas, PackedVector2Array([
		head + Vector2(-3.3, -2.8), head + Vector2(0.1, -4.2), head + Vector2(3.2, -2.8),
		head + Vector2(5.1, -0.9), head + Vector2(5.1, 0.9), head + Vector2(3.1, 2.9),
		head + Vector2(-0.5, 4.0), head + Vector2(-3.3, 2.5),
	]), body_color, outline, 0.60)
	_ellipse(canvas, head + Vector2(0.3, -0.8), Vector2(2.9, 2.55), highlight)
	_ellipse(canvas, head + Vector2(3.1, 0.0), Vector2(1.9, 1.7), highlight)
	for side in [-1.0, 1.0]:
		var eye := head + Vector2(2.05, side * 2.15)
		if resting:
			canvas.draw_line(eye + Vector2(-0.8, -side * 0.12), eye + Vector2(0.6, side * 0.14), EYE, 0.75, true)
		else:
			_ellipse(canvas, eye, Vector2(0.79, 0.70), EYE)
			canvas.draw_circle(eye + Vector2(0.12, -0.17), 0.20, CREAM)
	_ellipse(canvas, head + Vector2(5.05, 0.0), Vector2(0.68, 0.73), Color("#ac8978"))
	if eating:
		var mouth := head + Vector2(5.5, 0.3)
		canvas.draw_line(mouth, mouth + Vector2(3.0, -1.7 + chew), Color("#65804e"), 0.8, true)
		_leaf(canvas, mouth + Vector2(1.4, -0.9), mouth + Vector2(3.6, -2.0 + chew), 0.1, 0.65, Color("#8a9e60"))


static func draw_fox(canvas: Node2D, animal: Dictionary, pose: Dictionary, body_color: Color) -> void:
	var phase := float(pose.get("phase", 0.0)) * TAU
	var moving := clampf(float(pose.get("move", 0.0)), 0.0, 1.0)
	var time := float(pose.get("time", 0.0))
	var capture := clampf(float(pose.get("capture", 0.0)), 0.0, 1.0)
	var behavior := str(animal.get("behavior", "observe"))
	var resting := behavior in ["loaf", "socialize", "rest"]
	var eating := behavior == "eat" or capture > 0.08
	var hunting := behavior == "hunt"
	var identity := float(animal.get("id", 0)) * 1.37
	var quiet := 1.0 - moving
	var sway := sin(time * 1.65 + identity) * quiet * 0.65 + sin(phase + 0.7) * moving * 1.6
	var shade := body_color.lerp(Color("#8f563b"), 0.35)
	var highlight := body_color.lerp(Color("#efb378"), 0.34)
	var outline := body_color.lerp(FOX_INK, 0.72)
	var fur_cream := CREAM.lerp(body_color, 0.10)

	# A broad, tapered tail is one clear shape, with the pale tip following the
	# same centre line. It counter-swings against the alternating footfalls.
	var tail_root := Vector2(-6.4, 0.0)
	var tail_bend := Vector2(-12.4, 1.4 + sway)
	var tail_tip := Vector2(-20.2, 2.2 + sway * 1.4)
	if resting:
		tail_bend = tail_bend.lerp(Vector2(-15.0, 1.5), quiet)
		tail_tip = tail_tip.lerp(Vector2(-13.0, 8.4), quiet)
	_tail(canvas, tail_root, tail_bend, tail_tip, shade, fur_cream, outline)

	# Diagonal pairs form the fox's trot. The feet extend beyond the torso so
	# travel never reads as a rigid icon sliding across the habitat.
	for side in [-1.0, 1.0]:
		var side_phase := phase + (PI if side < 0.0 else 0.0)
		var rear_swing := sin(side_phase) * moving
		var front_swing := sin(side_phase + PI) * moving
		var rear := Vector2(-4.9 + rear_swing * 3.1, side * (5.0 + absf(rear_swing) * 0.8))
		var front := Vector2(4.2 + front_swing * 3.4 + capture * 1.2, side * (4.3 + absf(front_swing) * 0.75))
		if resting:
			rear = rear.lerp(Vector2(-3.8, side * 4.5), quiet)
			front = front.lerp(Vector2(4.9, side * 3.8), quiet)
		_leg(canvas, Vector2(-3.8, side * 3.6), rear, Vector2(2.05, 1.15), shade, outline, side * 0.15)
		_ellipse(canvas, rear + Vector2(0.9, 0.0), Vector2(1.25, 1.05), PAW, Color.TRANSPARENT, 0.0, side * 0.15)
		_leg(canvas, Vector2(2.2, side * 2.9), front, Vector2(1.8, 1.0), body_color, outline, side * 0.1)
		_ellipse(canvas, front + Vector2(0.7, 0.0), Vector2(1.15, 0.95), PAW)

	_shape(canvas, PackedVector2Array([
		Vector2(-8.0, -2.7), Vector2(-4.7, -5.2), Vector2(0.0, -4.9),
		Vector2(5.0, -3.3), Vector2(7.0, -0.2), Vector2(5.0, 3.3),
		Vector2(-0.4, 5.0), Vector2(-5.4, 4.8), Vector2(-8.2, 2.0),
	]), body_color, outline, 0.7)
	_shape(canvas, PackedVector2Array([
		Vector2(-7.0, 1.3), Vector2(-3.4, 3.1), Vector2(2.8, 2.5),
		Vector2(4.7, 3.1), Vector2(0.1, 4.4), Vector2(-4.8, 4.3),
	]), shade)
	_shape(canvas, PackedVector2Array([
		Vector2(-6.4, -1.7), Vector2(-3.4, -3.7), Vector2(1.2, -3.4),
		Vector2(3.8, -1.9), Vector2(-0.9, -1.5), Vector2(-4.8, -0.4),
	]), highlight)

	var head := Vector2(6.1 + capture * 1.25 + (sin(time * 10.0 + identity) * 0.18 if eating else 0.0), 0.0)
	# Short dark-backed triangular ears and pale cheeks distinguish the fox
	# from the rabbit at both adult and juvenile scale.
	for side in [-1.0, 1.0]:
		var ear_tip := head + Vector2(-1.7 - (1.0 if hunting else 0.0), side * (7.0 - capture * 0.8))
		_shape(canvas, PackedVector2Array([
			head + Vector2(-2.7, side * 2.6), ear_tip,
			head + Vector2(2.4, side * 3.9),
		]), shade, outline, 0.65, 2)
		_shape(canvas, PackedVector2Array([
			head + Vector2(-1.5, side * 3.6), ear_tip.lerp(head, 0.20),
			head + Vector2(0.9, side * 3.9),
		]), PAW, Color.TRANSPARENT, 0.0, 2)

	_shape(canvas, PackedVector2Array([
		head + Vector2(-3.1, -2.8), head + Vector2(0.2, -4.7), head + Vector2(3.7, -3.2),
		head + Vector2(8.0, -0.65), head + Vector2(8.0, 0.65), head + Vector2(3.7, 3.2),
		head + Vector2(0.2, 4.7), head + Vector2(-3.1, 2.8),
	]), highlight, outline, 0.65)
	for side in [-1.0, 1.0]:
		_shape(canvas, PackedVector2Array([
			head + Vector2(-0.4, side * 4.0), head + Vector2(2.3, side * 3.0),
			head + Vector2(4.1, side * 1.35), head + Vector2(7.5, side * 0.55),
			head + Vector2(3.8, side * 2.65), head + Vector2(1.0, side * 4.1),
		]), fur_cream)
		var eye := head + Vector2(2.8, side * 2.15)
		if resting or eating:
			canvas.draw_line(eye + Vector2(-0.65, side * 0.25), eye + Vector2(0.75, -side * 0.15), EYE, 0.8, true)
		else:
			_ellipse(canvas, eye, Vector2(0.83, 0.69), EYE, Color.TRANSPARENT, 0.0, -side * 0.2)
			canvas.draw_circle(eye + Vector2(0.14, -0.15), 0.18, fur_cream)
	_ellipse(canvas, head + Vector2(7.9, 0.0), Vector2(1.10, 0.85), EYE)


static func _tail(canvas: Node2D, root: Vector2, bend: Vector2, tip: Vector2, color: Color, tip_color: Color, outline: Color) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in range(13):
		var t := float(index) / 12.0
		var center := root * pow(1.0 - t, 2.0) + bend * (2.0 * (1.0 - t) * t) + tip * t * t
		var tangent := ((bend - root) * (1.0 - t) + (tip - bend) * t).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var width := (sin(t * PI) * 2.9 + (1.0 - t) * 1.45) * (1.0 - pow(t, 8.0))
		left.append(center + normal * width)
		right.append(center - normal * width)
	var contour := left.duplicate()
	for index in range(right.size() - 2, -1, -1):
		contour.append(right[index])
	canvas.draw_colored_polygon(contour, color)
	var pale := PackedVector2Array()
	for index in range(8, left.size()):
		pale.append(left[index])
	for index in range(right.size() - 2, 7, -1):
		pale.append(right[index])
	pale.append(left[8].lerp(right[8], 0.5) + Vector2(0.8, 0.0))
	canvas.draw_colored_polygon(pale, tip_color)
	contour.append(contour[0])
	canvas.draw_polyline(contour, outline, 0.65, true)


static func _leg(canvas: Node2D, root: Vector2, foot: Vector2, size: Vector2, color: Color, outline: Color, angle: float) -> void:
	canvas.draw_line(root, foot, outline, size.y * 2.0 + 0.8, true)
	canvas.draw_line(root, foot, color, size.y * 2.0, true)
	_ellipse(canvas, foot, size, color, outline, 0.5, angle)


static func _leaf(canvas: Node2D, root: Vector2, tip: Vector2, bend: float, width: float, color: Color, outline: Color = Color.TRANSPARENT, stroke: float = 0.0) -> void:
	var axis := (tip - root).normalized()
	var normal := Vector2(-axis.y, axis.x)
	var middle := root.lerp(tip, 0.53) + normal * bend
	_shape(canvas, PackedVector2Array([
		root - normal * width * 0.32, middle - normal * width,
		tip, middle + normal * width, root + normal * width * 0.32,
	]), color, outline, stroke)


static func _ellipse(canvas: Node2D, center: Vector2, radius: Vector2, color: Color, outline: Color = Color.TRANSPARENT, stroke: float = 0.0, angle: float = 0.0) -> void:
	var points := PackedVector2Array()
	for index in range(18):
		var theta := float(index) * TAU / 18.0
		points.append(center + Vector2(cos(theta) * radius.x, sin(theta) * radius.y).rotated(angle))
	canvas.draw_colored_polygon(points, color)
	if stroke > 0.0:
		points.append(points[0])
		canvas.draw_polyline(points, outline, stroke, true)


static func _shape(canvas: Node2D, knots: PackedVector2Array, color: Color, outline: Color = Color.TRANSPARENT, stroke: float = 0.0, subdivisions: int = 4) -> void:
	# Periodic Catmull–Rom contours give the illustration soft, authored curves
	# without depending on raster direction sheets or changing canvas transforms.
	var points := PackedVector2Array()
	var count := knots.size()
	for index in range(count):
		var a := knots[(index + count - 1) % count]
		var b := knots[index]
		var c := knots[(index + 1) % count]
		var d := knots[(index + 2) % count]
		for step in range(subdivisions):
			var t := float(step) / float(subdivisions)
			var t2 := t * t
			var t3 := t2 * t
			points.append((b * 2.0 + (c - a) * t + (a * 2.0 - b * 5.0 + c * 4.0 - d) * t2 + (-a + b * 3.0 - c * 3.0 + d) * t3) * 0.5)
	canvas.draw_colored_polygon(points, color)
	if stroke > 0.0:
		points.append(points[0])
		canvas.draw_polyline(points, outline, stroke, true)
