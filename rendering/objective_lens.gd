class_name ObjectiveLens
extends RefCounted

## Presentation lifecycle for semantic objective evidence. RunDirector supplies
## the truth; this class only diffs snapshots, animates marker visibility, and
## turns newly observed evidence records into short-lived feedback.

const MARKER_FADE_SPEED := 4.5
const MARKER_MOVE_SPEED := 5.0

var objective_id := ""
var evidence_revision := -1
var attention_markers: Dictionary = {}
var evidence_markers: Dictionary = {}
var feedback: Array = []
var seen_event_ids: Dictionary = {}

func update(snapshot: Dictionary, delta: float) -> void:
	var next_objective_id := str(snapshot.get("objective_id", ""))
	var next_evidence_revision := int(snapshot.get("evidence_revision", 0))
	if next_objective_id != objective_id or next_evidence_revision != evidence_revision:
		objective_id = next_objective_id
		evidence_revision = next_evidence_revision
		seen_event_ids.clear()

	var active := bool(snapshot.get("active", false))
	_sync_markers(attention_markers, snapshot.get("attention", []) if active else [])
	_sync_markers(evidence_markers, snapshot.get("evidence", []) if active else [])
	if active:
		_record_new_events(snapshot.get("events", []))
	_animate_markers(attention_markers, delta)
	_animate_markers(evidence_markers, delta)
	_update_feedback(delta)

func clear_immediately() -> void:
	objective_id = ""
	evidence_revision = -1
	attention_markers.clear()
	evidence_markers.clear()
	feedback.clear()
	seen_event_ids.clear()

func _sync_markers(markers: Dictionary, desired: Array) -> void:
	for marker in markers.values():
		marker["target_alpha"] = 0.0
	for item in desired:
		var data: Dictionary = item
		var marker_key := "%s:%d::%s" % [objective_id, evidence_revision, str(data.get("id", "marker"))]
		var target_position: Vector2 = data.get("position", Vector2.INF)
		if markers.has(marker_key):
			markers[marker_key]["data"] = data.duplicate(true)
			markers[marker_key]["target_alpha"] = 1.0
			markers[marker_key]["target_position"] = target_position
		else:
			markers[marker_key] = {
				"data": data.duplicate(true),
				"alpha": 0.0,
				"target_alpha": 1.0,
				"display_position": target_position,
				"target_position": target_position,
			}

func _animate_markers(markers: Dictionary, delta: float) -> void:
	for marker_key in markers.keys():
		var marker: Dictionary = markers[marker_key]
		marker["alpha"] = move_toward(float(marker["alpha"]), float(marker["target_alpha"]), maxf(0.0, delta) * MARKER_FADE_SPEED)
		var display_position: Vector2 = marker.get("display_position", Vector2.INF)
		var target_position: Vector2 = marker.get("target_position", display_position)
		if display_position != Vector2.INF and target_position != Vector2.INF:
			marker["display_position"] = display_position.lerp(target_position, 1.0 - exp(-maxf(0.0, delta) * MARKER_MOVE_SPEED))
		if float(marker["target_alpha"]) <= 0.0 and float(marker["alpha"]) <= 0.001:
			markers.erase(marker_key)

func _record_new_events(events: Array) -> void:
	for item in events:
		var data: Dictionary = item
		var event_key := "%s:%d::%s" % [objective_id, evidence_revision, str(data.get("id", "event"))]
		if seen_event_ids.has(event_key):
			continue
		seen_event_ids[event_key] = true
		feedback.append({
			"data": data.duplicate(true),
			"age": 0.0,
			"duration": 1.25 if str(data.get("state", "")) == "established" else 0.85,
		})

func _update_feedback(delta: float) -> void:
	for item in feedback:
		item["age"] += maxf(0.0, delta)
	for index in range(feedback.size() - 1, -1, -1):
		if float(feedback[index]["age"]) >= float(feedback[index]["duration"]):
			feedback.remove_at(index)
