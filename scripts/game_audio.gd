extends Node
## Original synthesized arcade score and feedback. No files, network, recording,
## or master-bus edits. Audio remains opt-in through the player's Sound button.

const SAMPLE_RATE: int = 22050
const VOICE_COUNT: int = 6
const EFFECT_PEAK: float = 0.105
const MUSIC_PEAK: float = 0.105
const MUSIC_STEP_SECONDS: float = 0.25 # 120 BPM, eight steps per bar.
const MUSIC_STEPS: int = 32
const CUE_ALIASES: Dictionary = {
	"incorrect": "wrong", "menu": "click", "pop": "kill", "shot": "shoot",
	"target_destroyed": "boss", "pulse": "dash", "win": "finish"
}
const CUE_INTERVAL_MS: Dictionary = {
	"shoot": 85, "impact": 80, "kill": 60, "streak": 750, "pulse_ready": 500
}
const CUE_PRIORITY: Dictionary = {
	"shoot": 0, "impact": 0, "kill": 1, "click": 1,
	"hit": 3, "dash": 3, "correct": 3, "wrong": 3,
	"boss": 4, "finish": 4, "revive": 4, "upgrade": 4
}

# Multiple scene/test instances reuse immutable synthesis. The longer score is
# prepared one eighth-note per frame, rather than blocking scene startup.
static var _cached_effects: Dictionary = {}
static var _cached_music: AudioStreamWAV
static var _music_pcm: PackedByteArray = PackedByteArray()
static var _music_step: int = 0

var muted: bool = true:
	set(value):
		muted = value
		if muted:
			_stop_effects()
		_update_combat()

var music_enabled: bool = true:
	set(value):
		music_enabled = value
		_update_combat()

var effects_enabled: bool = true:
	set(value):
		effects_enabled = value
		if not effects_enabled:
			_stop_effects()

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_priorities: Array[int] = []
var _combat_player: AudioStreamPlayer
var _combat_active: bool = false
var _paused: bool = false
var _next_voice: int = 0
var _cue_times: Dictionary = {}
var _variation: int = 0


func _ready() -> void:
	# Keep caches for scene changes, then release their engine resources at exit.
	if not get_tree().root.tree_exiting.is_connected(_release_cache):
		get_tree().root.tree_exiting.connect(_release_cache, CONNECT_ONE_SHOT)
	if _cached_effects.is_empty():
		_build_effects()
	_streams = _cached_effects
	for index: int in range(VOICE_COUNT):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "EffectVoice%d" % index
		add_child(voice)
		_voices.append(voice)
		_voice_priorities.append(-1)
	_combat_player = AudioStreamPlayer.new()
	_combat_player.name = "OrbitalSoundtrack"
	_combat_player.stream = _cached_music
	add_child(_combat_player)
	set_process(_cached_music == null)
	_update_combat()


static func _release_cache() -> void:
	_cached_effects.clear()
	_cached_music = null
	_music_pcm = PackedByteArray()
	_music_step = 0


func _process(_delta: float) -> void:
	if _cached_music == null:
		_music_pcm.append_array(_make_music_step(_music_step))
		_music_step += 1
		if _music_step == MUSIC_STEPS:
			_cached_music = _pcm_stream(_music_pcm, true)
			_music_pcm = PackedByteArray()
	if _cached_music != null:
		_combat_player.stream = _cached_music
		set_process(false)
		_update_combat()


func play(cue: String) -> void:
	if muted or not effects_enabled or _paused or _voices.is_empty():
		return
	var key: String = String(CUE_ALIASES.get(cue, cue))
	if not _streams.has(key):
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_cue_times.get(key, -10000)) < int(CUE_INTERVAL_MS.get(key, 0)):
		return
	var priority: int = int(CUE_PRIORITY.get(key, 2))
	var selected: int = -1
	var lowest_priority: int = 100
	for offset: int in range(VOICE_COUNT):
		var index: int = (_next_voice + offset) % VOICE_COUNT
		if not _voices[index].playing:
			selected = index
			break
		if _voice_priorities[index] <= priority and _voice_priorities[index] < lowest_priority:
			selected = index
			lowest_priority = _voice_priorities[index]
	if selected < 0:
		return # Rapid fire never steals an important reward or warning cue.
	_cue_times[key] = now
	_next_voice = (selected + 1) % VOICE_COUNT
	_voice_priorities[selected] = priority
	var voice: AudioStreamPlayer = _voices[selected]
	voice.stop()
	voice.stream = _streams[key] as AudioStreamWAV
	voice.pitch_scale = 1.0
	if key in ["shoot", "impact", "kill"]:
		voice.pitch_scale = [0.96, 1.0, 1.045, 1.02][_variation % 4]
		_variation += 1
	voice.play()


func set_combat(active: bool) -> void:
	_combat_active = active
	_update_combat()


func set_paused(active: bool) -> void:
	_paused = active
	if active:
		_stop_effects()
	_update_combat()


func _stop_effects() -> void:
	for voice: AudioStreamPlayer in _voices:
		voice.stop()


func _update_combat() -> void:
	if not is_instance_valid(_combat_player):
		return
	if _combat_active and not muted and music_enabled and not _paused:
		if _combat_player.stream != null and not _combat_player.playing:
			_combat_player.play()
	else:
		_combat_player.stop()


func _build_effects() -> void:
	_cached_effects["correct"] = _make_chime([523.25, 659.25, 1046.5], 0.085, 0.083)
	_cached_effects["wrong"] = _make_chime([246.94, 220.0, 196.0], 0.11, 0.073)
	_cached_effects["bonus"] = _make_chime([659.25, 783.99, 1046.5, 1318.51, 1567.98], 0.082, 0.095)
	_cached_effects["upgrade"] = _make_chime([392.0, 523.25, 659.25, 783.99, 1046.5], 0.095, 0.10)
	_cached_effects["finish"] = _make_chime([523.25, 659.25, 783.99, 1046.5, 0.0, 783.99, 1046.5, 1318.51], 0.13, EFFECT_PEAK)
	_cached_effects["click"] = _make_chime([880.0, 1320.0], 0.021, 0.041)
	_cached_effects["lock"] = _make_chime([220.0, 0.0, 440.0, 880.0], 0.08, 0.087)
	_cached_effects["revive"] = _make_chime([261.63, 392.0, 523.25, 783.99, 1046.5], 0.11, 0.10)
	_cached_effects["pulse_ready"] = _make_chime([783.99, 1046.5], 0.09, 0.070)
	_cached_effects["streak"] = _make_chime([659.25, 987.77, 1318.51], 0.055, 0.074)
	_cached_effects["shoot"] = _make_sweep(1420.0, 290.0, 0.095, 0.015, 0.041, 11)
	_cached_effects["impact"] = _make_sweep(410.0, 105.0, 0.10, 0.55, 0.060, 21)
	_cached_effects["kill"] = _make_sweep(175.0, 44.0, 0.26, 0.72, 0.083, 31)
	_cached_effects["hit"] = _make_sweep(185.0, 49.0, 0.34, 0.32, 0.095, 41)
	_cached_effects["dash"] = _make_sweep(130.0, 960.0, 0.40, 0.65, 0.10, 51)
	_cached_effects["launch"] = _make_sweep(64.0, 640.0, 0.72, 0.36, 0.085, 61)
	_cached_effects["boss"] = _make_sweep(100.0, 30.0, 0.78, 0.85, EFFECT_PEAK, 71)


func _make_chime(notes: Array, note_seconds: float, peak: float) -> AudioStreamWAV:
	# Bell fundamentals, a soft octave and inharmonic sparkle have short tails
	# that overlap the next note instead of a sequence of isolated sine beeps.
	var count: int = int((note_seconds * notes.size() + 0.20) * SAMPLE_RATE)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(count)
	for note_index: int in range(notes.size()):
		var frequency: float = float(notes[note_index])
		if frequency <= 0.0:
			continue
		var duration: float = note_seconds + 0.20
		var start: int = int(note_index * note_seconds * SAMPLE_RATE)
		for i: int in range(mini(count - start, int(duration * SAMPLE_RATE))):
			var t: float = float(i) / SAMPLE_RATE
			var env: float = minf(t / 0.005, 1.0) * exp(-t * 15.0) * minf((duration - t) / 0.04, 1.0)
			var phase: float = TAU * frequency * t
			var tone: float = sin(phase) + 0.30 * sin(phase * 2.0) + 0.12 * sin(phase * 3.005)
			samples[start + i] += tone * env
	return _pcm_stream(_encode_normalized(samples, peak))


func _make_sweep(start_hz: float, end_hz: float, seconds: float, noise_mix: float, peak: float, seed_value: int) -> AudioStreamWAV:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var count: int = int(seconds * SAMPLE_RATE)
	samples.resize(count)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value # Never consume the gameplay random-number sequence.
	var phase: float = 0.0
	var filtered_noise: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var position: float = float(i) / maxi(1, count - 1)
		var frequency: float = lerpf(start_hz, end_hz, sqrt(position))
		phase += TAU * frequency / SAMPLE_RATE
		filtered_noise = lerpf(filtered_noise, rng.randf_range(-1.0, 1.0), 0.34)
		var env: float = minf(t / 0.008, 1.0) * pow(1.0 - position, 1.6)
		var tone: float = sin(phase) * 0.70 + sin(phase * 2.01) * 0.18
		samples[i] = lerpf(tone, filtered_noise * 2.2, noise_mix) * env
	return _pcm_stream(_encode_normalized(samples, peak))


func _make_music_step(step: int) -> PackedByteArray:
	var count: int = int(MUSIC_STEP_SECONDS * SAMPLE_RATE)
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(count * 2)
	var roots: Array[float] = [130.8128, 103.8262, 155.5635, 116.5409]
	var root_hz: float = roots[step / 8]
	var minor: bool = step < 8
	var third_ratio: float = pow(2.0, (3.0 if minor else 4.0) / 12.0)
	var arp_ratios: Array[float] = [2.0, 3.0, 4.0, 3.0, 2.0 * third_ratio, 3.0, 4.0, 6.0]
	var arp_hz: float = root_hz * arp_ratios[step % 8]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 900 + step
	var previous_noise: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var position: float = float(i) / maxi(1, count - 1)
		var edge: float = minf(t / 0.004, 1.0) * minf((MUSIC_STEP_SECONDS - t) / 0.009, 1.0)
		var pad_env: float = sin(PI * position) * 0.010
		var pad: float = (sin(TAU * root_hz * t) + sin(TAU * root_hz * third_ratio * t) + sin(TAU * root_hz * 1.4983 * t)) * pad_env
		var bass_hz: float = root_hz * (0.5 if step % 8 != 7 else 0.75)
		var bass: float = (sin(TAU * bass_hz * t) + 0.18 * sin(TAU * bass_hz * 2.0 * t)) * exp(-t * 8.0) * 0.021
		var arp: float = (sin(TAU * arp_hz * t) + 0.18 * sin(TAU * arp_hz * 2.0 * t)) * exp(-t * 18.0) * 0.013
		var noise: float = rng.randf_range(-1.0, 1.0)
		var high_noise: float = (noise - previous_noise) * 0.5
		previous_noise = noise
		var hat: float = high_noise * exp(-t * (65.0 if step % 2 == 0 else 36.0)) * 0.017
		var drum: float = 0.0
		if step % 2 == 0:
			# Integrating a falling frequency makes a round kick, not a click.
			var kick_phase: float = TAU * (45.0 * t + 90.0 * (1.0 - exp(-t * 35.0)) / 35.0)
			drum += sin(kick_phase) * exp(-t * 20.0) * 0.035
		if step % 4 == 2:
			drum += (noise * 0.65 + sin(TAU * 180.0 * t) * 0.35) * exp(-t * 24.0) * 0.025
		var sample: float = clampf((pad + bass + arp + hat + drum) * edge, -MUSIC_PEAK, MUSIC_PEAK)
		_write_sample(pcm, i, sample)
	return pcm


func _encode_normalized(samples: PackedFloat32Array, peak: float) -> PackedByteArray:
	var maximum: float = 0.001
	for value: float in samples:
		maximum = maxf(maximum, absf(value))
	var gain: float = minf(peak, EFFECT_PEAK) / maximum
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index: int in range(samples.size()):
		_write_sample(pcm, index, samples[index] * gain)
	return pcm


func _write_sample(pcm: PackedByteArray, index: int, sample: float) -> void:
	var signed_sample: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
	pcm[index * 2] = signed_sample & 0xff
	pcm[index * 2 + 1] = (signed_sample >> 8) & 0xff


func _pcm_stream(pcm: PackedByteArray, looped: bool = false) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = pcm.size() / 2
	return stream
