extends "res://tests/playtest_runner.gd"
func _initialize() -> void:
	var s = Systems.new(Config.make())
	var last_act = ""
	for tick in range(18000):
		if s.supply_pending: s.choose_supply(_choose_supply(s,"deliberate"))
		if tick % 10 == 0: _place_inventory(s,"deliberate")
		s.advance(0.1)
		var act = s.run_director.current_milestone_id()
		if act != last_act or tick % 1000 == 0:
			print("PROGRESSION t=%.1f act=%s r=%d f=%d plants=%d" % [s.simulation.simulation_time,act,s.simulation.rabbits.size(),s.simulation.foxes.size(),s.simulation.plants.size()])
			last_act = act
		if s.is_completed(): s.continue_observing()
		if s.is_game_over(): break
	quit()
