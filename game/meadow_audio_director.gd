class_name MeadowAudioDirector
extends Node

const SAMPLE_RATE := 22050
const EVENT_PLAYER_COUNT := 6

var systems: GameSystems
var enabled := false
var ambience_player: AudioStreamPlayer
var event_players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var next_player := 0

func setup(p_systems: GameSystems) -> void:
	systems = p_systems
	_build_players()
	_build_streams()
	systems.placement_succeeded.connect(_on_placement_succeeded)
	systems.transplant_succeeded.connect(func(_plant_id: int, _item: String, _position: Vector2) -> void: _play("transplant"))
	systems.ecology_story_added.connect(_on_story_added)
	systems.supply_ready.connect(func(_choices: Array) -> void: _play("supply"))
	systems.supply_claimed.connect(func(_bundle: Dictionary) -> void: _play("claim"))
	systems.milestone_completed.connect(func(_index: int, _id: String, _message: String) -> void: _play("milestone"))
	systems.critical_started.connect(func() -> void: _play("warning"))
	systems.critical_recovered.connect(func() -> void: _play("recover"))
	systems.run_completed.connect(func() -> void: _play("complete"))
	if enabled:
		ambience_player.play.call_deferred()

func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		if not ambience_player.playing:
			ambience_player.play.call_deferred()
	else:
		ambience_player.stop()
		for player in event_players:
			player.stop()

func _build_players() -> void:
	ambience_player = AudioStreamPlayer.new()
	ambience_player.name = "MeadowAmbience"
	ambience_player.volume_db = -23.0
	add_child(ambience_player)
	for index in range(EVENT_PLAYER_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "EventVoice%d" % (index + 1)
		player.volume_db = -11.0
		add_child(player)
		event_players.append(player)

func _build_streams() -> void:
	streams = {
		"place_animal": _make_tone([520.0, 780.0], 0.13, 0.34, 0.03),
		"place_plant": _make_tone([330.0, 440.0], 0.16, 0.29, 0.05),
		"birth": _make_tone([660.0, 880.0, 1100.0], 0.24, 0.28, 0.05),
		"first_meal": _make_tone([470.0, 705.0], 0.18, 0.26, 0.02),
		"hunt": _make_tone([185.0, 247.0], 0.22, 0.34, 0.03),
		"transplant": _make_tone([294.0, 392.0, 494.0], 0.30, 0.28, 0.07),
		"supply": _make_tone([392.0, 523.0, 659.0], 0.42, 0.25, 0.10),
		"claim": _make_tone([523.0, 659.0], 0.22, 0.26, 0.04),
		"milestone": _make_tone([392.0, 494.0, 659.0, 784.0], 0.64, 0.24, 0.14),
		"warning": _make_tone([196.0, 174.0], 0.48, 0.28, 0.12),
		"recover": _make_tone([330.0, 440.0, 587.0], 0.42, 0.23, 0.10),
		"complete": _make_tone([330.0, 440.0, 523.0, 659.0, 784.0], 1.0, 0.20, 0.22),
	}
	ambience_player.stream = _make_ambience()

func _make_tone(frequencies: Array, duration: float, amplitude: float, attack: float) -> AudioStreamWAV:
	var sample_count := maxi(1, roundi(duration * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in range(sample_count):
		var time := float(index) / float(SAMPLE_RATE)
		var progress := float(index) / float(sample_count)
		var envelope := minf(1.0, time / maxf(0.001, attack)) * pow(1.0 - progress, 1.7)
		var sample := 0.0
		for frequency in frequencies:
			sample += sin(TAU * float(frequency) * time)
		sample = sample / maxf(1.0, float(frequencies.size())) * amplitude * envelope
		_write_sample(data, index, sample)
	return _wave_from_data(data)

func _make_ambience() -> AudioStreamWAV:
	var duration := 4.0
	var sample_count := roundi(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var noise := 0.0
	var random := RandomNumberGenerator.new()
	random.seed = 90741
	for index in range(sample_count):
		var time := float(index) / float(SAMPLE_RATE)
		noise = lerpf(noise, random.randf_range(-1.0, 1.0), 0.012)
		var wind := noise * (0.35 + 0.16 * sin(TAU * 0.13 * time))
		var leaves := sin(TAU * 92.0 * time) * sin(TAU * 0.31 * time) * 0.04
		var bird := 0.0
		for start in [0.72, 2.58]:
			var local := time - float(start)
			if local >= 0.0 and local <= 0.24:
				bird += sin(TAU * (920.0 + local * 720.0) * local) * sin(local / 0.24 * PI) * 0.18
		_write_sample(data, index, (wind * 0.15 + leaves + bird) * 0.55)
	var wave := _wave_from_data(data)
	wave.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wave.loop_begin = 0
	wave.loop_end = sample_count
	return wave

func _wave_from_data(data: PackedByteArray) -> AudioStreamWAV:
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = SAMPLE_RATE
	wave.stereo = false
	wave.data = data
	return wave

func _write_sample(data: PackedByteArray, index: int, value: float) -> void:
	var signed_value := clampi(roundi(clampf(value, -1.0, 1.0) * 32767.0), -32768, 32767)
	var encoded := signed_value if signed_value >= 0 else signed_value + 65536
	data[index * 2] = encoded & 0xff
	data[index * 2 + 1] = (encoded >> 8) & 0xff

func _play(key: String) -> void:
	if not enabled or not streams.has(key):
		return
	var player := event_players[next_player]
	next_player = (next_player + 1) % event_players.size()
	player.stream = streams[key]
	player.play()

func _on_placement_succeeded(item: String, _entity_id: int, _position: Vector2) -> void:
	_play("place_animal" if item in ["rabbit", "fox"] else "place_plant")

func _on_story_added(story: Dictionary) -> void:
	match str(story.get("type", "")):
		"birth":
			_play("birth")
		"first_meal":
			_play("first_meal")
		"hunt":
			_play("hunt")
