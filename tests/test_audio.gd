extends SceneTree
## Audio lifecycle, peak headroom, deterministic synthesis and feedback priority.
const GameAudio = preload("res://scripts/game_audio.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func playing_effects(audio: Node) -> int:
	var count: int = 0
	for voice: AudioStreamPlayer in audio._voices:
		if voice.playing:
			count += 1
	return count

func pcm_peak(bytes: PackedByteArray) -> float:
	var maximum: int = 0
	for index: int in range(0, bytes.size(), 2):
		maximum = maxi(maximum, absi(bytes.decode_s16(index)))
	return float(maximum) / 32767.0

func _run() -> void:
	var bus_count: int = AudioServer.bus_count
	var master_volume: float = AudioServer.get_bus_volume_db(0)
	seed(991)
	var expected_random: float = randf()
	seed(991)
	var start: int = Time.get_ticks_usec()
	var audio: Node = GameAudio.new()
	root.add_child(audio)
	audio.set_process(false)
	var effect_build_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	check(is_equal_approx(expected_random, randf()), "Synthesis does not consume gameplay randomness")
	check(audio.muted, "Starts muted")
	check(audio.music_enabled and audio.effects_enabled, "Both channels available when player enables sound")
	check(playing_effects(audio) == 0 and not audio._combat_player.playing, "No startup audio")
	audio.set_combat(true)
	audio.play("launch")
	check(playing_effects(audio) == 0, "Muted launch remains silent")
	var total_bytes: int = 0
	for cue: String in audio._streams:
		var stream: AudioStreamWAV = audio._streams[cue]
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050 and not stream.stereo, cue + " uses mobile-size PCM")
		check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, cue + " is a one-shot")
		check(stream.get_length() > 0.04 and stream.get_length() < 1.5, cue + " has a bounded duration")
		var peak: float = pcm_peak(stream.data)
		check(peak > 0.025 and peak <= GameAudio.EFFECT_PEAK + 0.0001, cue + " has audible non-clipping PCM")
		check(absf(float(stream.data.decode_s16(0))) <= 1.0 and absf(float(stream.data.decode_s16(stream.data.size() - 2))) < 10.0, cue + " has click-safe endpoints")
		total_bytes += stream.data.size()
	var maximum_step_ms: float = 0.0
	for step: int in range(GameAudio.MUSIC_STEPS):
		start = Time.get_ticks_usec()
		audio._process(0.0)
		maximum_step_ms = maxf(maximum_step_ms, (Time.get_ticks_usec() - start) / 1000.0)
	var music: AudioStreamWAV = audio._combat_player.stream
	check(music != null, "Incremental preparation finishes a score")
	check(music.get_length() > 7.9 and music.get_length() < 8.1, "Four-bar 120 BPM score")
	check(music.loop_mode == AudioStreamWAV.LOOP_FORWARD and music.loop_begin == 0 and music.loop_end * 2 == music.data.size(), "Score loops exactly its sample span")
	check(pcm_peak(music.data) > 0.03 and pcm_peak(music.data) <= GameAudio.MUSIC_PEAK, "Score is non-silent and bounded")
	check(GameAudio.EFFECT_PEAK * GameAudio.VOICE_COUNT + GameAudio.MUSIC_PEAK < 0.8, "Worst-case overlap retains master headroom")
	check(total_bytes + music.data.size() < 1000000, "Cached PCM stays under 1 MB")
	check(not audio._combat_player.playing, "Finished score preparation does not override mute")
	check(not audio.is_processing(), "No ongoing synthesis work after preparation")
	audio.muted = false
	check(audio._combat_player.playing, "Enabled sound starts score for active combat")
	audio.play("launch")
	check(playing_effects(audio) == 1, "Launch plays")
	audio.effects_enabled = false
	check(playing_effects(audio) == 0 and audio._combat_player.playing, "Effects toggle silences effects and preserves music")
	audio.play("correct")
	check(playing_effects(audio) == 0, "Effects disabled blocks new cues")
	audio.music_enabled = false
	check(not audio._combat_player.playing, "Independent music toggle stops score")
	audio.effects_enabled = true
	audio.play("pulse")
	check(playing_effects(audio) == 1, "Pulse alias works with music disabled")
	audio.music_enabled = true
	check(audio._combat_player.playing, "Music can resume independently")
	audio.set_paused(true)
	check(playing_effects(audio) == 0 and not audio._combat_player.playing, "Pause stops music and transient effects")
	audio.play("hit")
	check(playing_effects(audio) == 0, "No feedback starts during pause")
	audio.set_paused(false)
	check(audio._combat_player.playing and playing_effects(audio) == 0, "Resume restarts active score without stale effects")
	audio.set_combat(false)
	check(not audio._combat_player.playing, "Leaving combat stops score")
	for cue: String in ["shot", "impact", "kill", "target_destroyed", "streak", "pulse", "pulse_ready", "incorrect", "menu", "pop", "win"]:
		audio._stop_effects()
		audio._cue_times.clear()
		audio.play(cue)
		check(playing_effects(audio) == 1, cue + " routes to its sound")
	audio._stop_effects()
	audio._cue_times.clear()
	audio.play("shoot")
	for i: int in range(100):
		audio.play("shot")
	check(playing_effects(audio) == 1, "Aliased rapid shots share the rate limiter")
	audio._stop_effects()
	for i: int in range(GameAudio.VOICE_COUNT):
		audio.play("upgrade")
	check(playing_effects(audio) == GameAudio.VOICE_COUNT, "Voice pool has a fixed upper bound")
	audio._cue_times.clear()
	audio.play("shoot")
	var upgrades_preserved: bool = true
	for voice: AudioStreamPlayer in audio._voices:
		upgrades_preserved = upgrades_preserved and voice.stream == audio._streams["upgrade"]
	check(upgrades_preserved, "Shots cannot steal reward voices")
	audio.muted = true
	check(playing_effects(audio) == 0 and not audio._combat_player.playing, "Master mute immediately silences every channel")
	start = Time.get_ticks_usec()
	var second: Node = GameAudio.new()
	root.add_child(second)
	var cached_setup_ms: float = (Time.get_ticks_usec() - start) / 1000.0
	check(second._streams["correct"] == audio._streams["correct"] and second._combat_player.stream == music, "New scenes reuse synthesized resources")
	check(not second.is_processing(), "Cached instances do not synthesize again")
	check(AudioServer.bus_count == bus_count and AudioServer.get_bus_volume_db(0) == master_volume, "No project audio bus changes")
	print("Audio cache: %d bytes. Effects %.1f ms; maximum music slice %.1f ms; cached scene %.1f ms." % [total_bytes + music.data.size(), effect_build_ms, maximum_step_ms, cached_setup_ms])
	audio.free()
	second.free()
	# Let the audio server retire stopped playback references before engine exit.
	await create_timer(0.5).timeout
	if failures.is_empty():
		print("PASS: %d audio checks" % checks)
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		print("FAIL: %d/%d audio checks" % [failures.size(), checks])
		quit(1)

