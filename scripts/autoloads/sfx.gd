extends Node

# Procedural audio SFX manager for Huebound
# All sounds generated from waveforms — no external files needed

var _players: Array[AudioStreamPlayer] = []
const MAX_PLAYERS := 12
const SAMPLE_RATE := 44100.0

var master_volume: float = 0.8 # 0.0 to 1.0
var sfx_volume: float = 0.8
var ambient_volume: float = 0.5
var muted: bool = false

func _ready() -> void:
	for i in range(MAX_PLAYERS):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)

func _get_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	# All busy — steal the oldest
	return _players[0]

# ─── Sound Generators ─────────────────────────────────────────────────────────

func play_place() -> void:
	# Soft thud + resonant tone — placing a node
	var samples = _generate_samples(0.15, func(t):
		var thud = sin(TAU * 80.0 * t) * exp(-t * 30.0)
		var tone = sin(TAU * 220.0 * t) * exp(-t * 15.0) * 0.3
		return (thud + tone) * 0.5
	)
	_play(samples, -6.0)

func play_delete() -> void:
	# Descending sweep — removing a node
	var samples = _generate_samples(0.2, func(t):
		var freq = lerp(400.0, 100.0, t / 0.2)
		return sin(TAU * freq * t) * exp(-t * 12.0) * 0.4
	)
	_play(samples, -8.0)

func play_connect() -> void:
	# Quick ascending snap — making a connection
	var samples = _generate_samples(0.12, func(t):
		var freq = lerp(300.0, 600.0, t / 0.12)
		return sin(TAU * freq * t) * exp(-t * 20.0) * 0.4
	)
	_play(samples, -8.0)

func play_disconnect() -> void:
	# Short descending blip
	var samples = _generate_samples(0.1, func(t):
		var freq = lerp(500.0, 200.0, t / 0.1)
		return sin(TAU * freq * t) * exp(-t * 25.0) * 0.3
	)
	_play(samples, -10.0)

func play_sell(value: float = 1.0) -> void:
	# Coin clink — pitch varies with value
	var base_freq = clampf(400.0 + value * 40.0, 400.0, 1200.0)
	var samples = _generate_samples(0.18, func(t):
		var main = sin(TAU * base_freq * t) * exp(-t * 18.0)
		var harmonic = sin(TAU * base_freq * 2.5 * t) * exp(-t * 25.0) * 0.3
		var click = sin(TAU * 3000.0 * t) * exp(-t * 200.0) * 0.2
		return (main + harmonic + click) * 0.35
	)
	_play(samples, -10.0)

func play_discovery() -> void:
	# Sparkle fanfare — ascending arpeggio
	var samples = _generate_samples(0.6, func(t):
		var note1 = sin(TAU * 523.0 * t) * exp(-t * 6.0) * (1.0 if t < 0.3 else 0.0)
		var note2 = sin(TAU * 659.0 * t) * exp(-(t - 0.1) * 6.0) * (1.0 if t > 0.1 and t < 0.4 else 0.0)
		var note3 = sin(TAU * 784.0 * t) * exp(-(t - 0.2) * 6.0) * (1.0 if t > 0.2 and t < 0.5 else 0.0)
		var shimmer = sin(TAU * 1568.0 * t) * exp(-(t - 0.3) * 4.0) * (1.0 if t > 0.3 else 0.0) * 0.15
		return (note1 + note2 + note3 + shimmer) * 0.25
	)
	_play(samples, -6.0)

func play_shop_buy() -> void:
	# Ka-ching — metallic ring
	var samples = _generate_samples(0.3, func(t):
		var ring = sin(TAU * 880.0 * t) * exp(-t * 8.0)
		var ring2 = sin(TAU * 1320.0 * t) * exp(-t * 10.0) * 0.5
		var click = sin(TAU * 4000.0 * t) * exp(-t * 150.0) * 0.3
		return (ring + ring2 + click) * 0.3
	)
	_play(samples, -6.0)

func play_unlock() -> void:
	# Grand unlock — rising chord
	var samples = _generate_samples(0.5, func(t):
		var base = sin(TAU * 330.0 * t) * exp(-t * 4.0)
		var third = sin(TAU * 415.0 * t) * exp(-(t - 0.05) * 4.0) * 0.8
		var fifth = sin(TAU * 495.0 * t) * exp(-(t - 0.1) * 4.0) * 0.6
		var octave = sin(TAU * 660.0 * t) * exp(-(t - 0.15) * 3.0) * 0.4
		return (base + third + fifth + octave) * 0.2
	)
	_play(samples, -4.0)

func play_ui_click() -> void:
	# Subtle click
	var samples = _generate_samples(0.05, func(t):
		var click = sin(TAU * 1000.0 * t) * exp(-t * 80.0)
		return click * 0.3
	)
	_play(samples, -12.0)

func play_ui_hover() -> void:
	# Very soft tick
	var samples = _generate_samples(0.03, func(t):
		return sin(TAU * 1500.0 * t) * exp(-t * 120.0) * 0.15
	)
	_play(samples, -16.0)

func play_error() -> void:
	# Buzzy rejection
	var samples = _generate_samples(0.15, func(t):
		var buzz = sin(TAU * 150.0 * t) * exp(-t * 15.0)
		var buzz2 = sin(TAU * 155.0 * t) * exp(-t * 15.0) * 0.8
		return (buzz + buzz2) * 0.3
	)
	_play(samples, -8.0)

func play_orb_produce() -> void:
	# Soft bubble pop
	var samples = _generate_samples(0.08, func(t):
		var freq = lerp(600.0, 400.0, t / 0.08)
		return sin(TAU * freq * t) * exp(-t * 30.0) * 0.2
	)
	_play(samples, -16.0)

# ─── Ambient Background ──────────────────────────────────────────────────────

var _ambient_player: AudioStreamPlayer = null

func start_ambient() -> void:
	pass # Ambient drone removed — everyone hated it

func stop_ambient() -> void:
	if _ambient_player:
		_ambient_player.stop()

# ─── Internal Helpers ─────────────────────────────────────────────────────────

func _generate_samples(duration: float, generator: Callable) -> PackedFloat32Array:
	var count = int(duration * SAMPLE_RATE)
	var samples = PackedFloat32Array()
	samples.resize(count)
	for i in range(count):
		var t = float(i) / SAMPLE_RATE
		samples[i] = clampf(generator.call(t), -1.0, 1.0)
	return samples

func _samples_to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(SAMPLE_RATE)
	stream.stereo = false
	
	var byte_data = PackedByteArray()
	byte_data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var val = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		byte_data[i * 2] = val & 0xFF
		byte_data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = byte_data
	return stream

func _play(samples: PackedFloat32Array, volume_db: float = -6.0) -> void:
	if muted or master_volume <= 0.0 or sfx_volume <= 0.0:
		return
	var player = _get_player()
	player.stream = _samples_to_stream(samples)
	player.volume_db = volume_db + linear_to_db(master_volume * sfx_volume)
	player.play()

func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)
	_update_ambient_volume()

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)

func set_ambient_volume(vol: float) -> void:
	ambient_volume = clampf(vol, 0.0, 1.0)
	_update_ambient_volume()

func set_muted(m: bool) -> void:
	muted = m
	_update_ambient_volume()

func _update_ambient_volume() -> void:
	if _ambient_player:
		if muted or master_volume <= 0.0 or ambient_volume <= 0.0:
			_ambient_player.volume_db = -80.0
		else:
			_ambient_player.volume_db = -18.0 + linear_to_db(master_volume * ambient_volume)
