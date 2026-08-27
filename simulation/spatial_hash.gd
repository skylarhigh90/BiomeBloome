class_name SpatialHash
extends RefCounted

var cell_size: float
var cells: Dictionary = {}

func _init(p_cell_size: float = 96.0) -> void:
	cell_size = maxf(16.0, p_cell_size)

func clear() -> void:
	cells.clear()

func _cell_for(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))

func insert(kind: String, entity_id: int, position: Vector2) -> void:
	var key := _cell_for(position)
	if not cells.has(key):
		cells[key] = []
	cells[key].append({"kind": kind, "id": entity_id, "position": position})

func query(kind: String, center: Vector2, radius: float) -> Array:
	var found: Array = []
	var radius_squared := radius * radius
	var min_cell := _cell_for(center - Vector2.ONE * radius)
	var max_cell := _cell_for(center + Vector2.ONE * radius)
	for cell_x in range(min_cell.x, max_cell.x + 1):
		for cell_y in range(min_cell.y, max_cell.y + 1):
			var key := Vector2i(cell_x, cell_y)
			if not cells.has(key):
				continue
			for entry in cells[key]:
				if entry["kind"] == kind and center.distance_squared_to(entry["position"]) <= radius_squared:
					found.append(entry)
	return found
