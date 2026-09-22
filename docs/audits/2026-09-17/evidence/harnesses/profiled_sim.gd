extends "res://simulation/ecosystem_simulation.gd"
var audit_times = {}
func record(key: String, started: int) -> void:
	var elapsed = Time.get_ticks_usec()-started
	audit_times[key]=float(audit_times.get(key,0.0))+elapsed
func _regenerate_plants(delta: float) -> void:
	var start=Time.get_ticks_usec()
	super._regenerate_plants(delta)
	record("regenerate",start)
func rebuild_spatial_index() -> void:
	var start=Time.get_ticks_usec()
	super.rebuild_spatial_index()
	record("spatial",start)
func _rebuild_rabbit_shared_food_vision() -> void:
	var start=Time.get_ticks_usec()
	super._rebuild_rabbit_shared_food_vision()
	record("social_vision",start)
func _update_rabbit(rabbit: Dictionary, delta: float) -> bool:
	var start=Time.get_ticks_usec()
	var result=super._update_rabbit(rabbit,delta)
	record("rabbit_updates",start)
	return result
func _update_fox(fox: Dictionary, delta: float) -> bool:
	var start=Time.get_ticks_usec()
	var result=super._update_fox(fox,delta)
	record("fox_updates",start)
	return result
func _habitat_steering(position: Vector2, prefers_forest: bool, sample_phase: float=0.0) -> Vector2:
	var start=Time.get_ticks_usec()
	var result=super._habitat_steering(position,prefers_forest,sample_phase)
	record("nested_habitat_steering",start)
	return result
func ground_route(position: Vector2, target: Vector2, maximum_distance: float=INF) -> Dictionary:
	var start=Time.get_ticks_usec()
	var result=super.ground_route(position,target,maximum_distance)
	record("nested_ground_route",start)
	return result
