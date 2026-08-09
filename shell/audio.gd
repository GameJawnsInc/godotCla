extends Node
## Procedural audio: every sound is synthesized at boot from code — no binary
## assets, fully diffable, same philosophy as the SVG art. SFX are tiny
## sine/noise gestures; the music is a warm four-chord pad loop with a soft
## arpeggio and wind, rendered once on a background thread and looped.

const RATE := 22050

var sfx_on := true
var music_on := true

var _players: Array = []
var _pi := 0
var _music_player: AudioStreamPlayer
var _bank := {}
var _music_thread: Thread
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -14.0
	add_child(_music_player)
	# restart from the player side - in-stream WAV loop points crashed the
	# Android audio driver at the wrap
	_music_player.finished.connect(_on_music_finished)
	build_bank()
	if is_inside_tree():
		_music_thread = Thread.new()
		_music_thread.start(_render_music)


func _exit_tree() -> void:
	if _music_thread != null and _music_thread.is_started():
		_music_thread.wait_to_finish()


func play(id: String) -> void:
	if not sfx_on or not is_inside_tree() or not _bank.has(id):
		return
	var p: AudioStreamPlayer = _players[_pi]
	_pi = (_pi + 1) % _players.size()
	p.stream = _bank[id]
	p.volume_db = -7.0
	p.play()


func _on_music_finished() -> void:
	if music_on and _music_player.stream != null:
		_music_player.play()


func set_music(on: bool) -> void:
	music_on = on
	if _music_player == null:
		return
	if on and _music_player.stream != null and not _music_player.playing:
		_music_player.play()
	elif not on:
		_music_player.stop()


# --- synthesis ----------------------------------------------------------------

func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.data = bytes
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	return s


## Sine sweep f0->f1, power-decay envelope, optional 2nd harmonic; adds into
## buf (wrapping when wrap=true so music loops stay seamless).
func _tone(buf: PackedFloat32Array, start_s: float, dur: float, f0: float, f1: float, vol: float, decay := 2.0, harm := 0.0, wrap := false) -> void:
	var n0 := int(start_s * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(f0, f1, t) / RATE
		var env := pow(1.0 - t, decay) * vol
		var v := sin(phase) * env + (sin(phase * 2.0) * env * harm)
		var idx := n0 + i
		if wrap:
			idx = idx % buf.size()
		elif idx >= buf.size():
			break
		buf[idx] += v


## Brown-ish noise burst with decay envelope; higher `smooth` = darker.
func _noise(buf: PackedFloat32Array, start_s: float, dur: float, vol: float, decay := 2.0, wrap := false, smooth := 0.94) -> void:
	var n0 := int(start_s * RATE)
	var n := int(dur * RATE)
	var prev := 0.0
	for i in n:
		var t := float(i) / n
		prev = prev * smooth + (_rng.randf() * 2.0 - 1.0) * (1.0 - smooth) * 5.0
		var idx := n0 + i
		if wrap:
			idx = idx % buf.size()
		elif idx >= buf.size():
			break
		buf[idx] += prev * pow(1.0 - t, decay) * vol


## Sustained pad note: slow attack and release, gentle harmonic, wraps.
func _pad(buf: PackedFloat32Array, start_s: float, dur: float, f: float, vol: float) -> void:
	var n0 := int(start_s * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		var ts := float(i) / RATE
		phase += TAU * f / RATE
		var env := minf(ts / 0.5, 1.0) * minf((dur - ts) / 0.8, 1.0) * vol
		buf[(n0 + i) % buf.size()] += (sin(phase) + sin(phase * 2.0) * 0.25 + sin(phase * 3.0) * 0.08) * env


func _mk(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


## The whole SFX bank, each a tiny synthesized gesture.
func build_bank() -> void:
	var b: PackedFloat32Array

	b = _mk(0.05)  # UI tap
	_tone(b, 0.0, 0.05, 900, 700, 0.25, 3.0)
	_bank["tap"] = _wav(b)

	b = _mk(0.09)  # footstep
	_tone(b, 0.0, 0.09, 170, 110, 0.28, 2.5)
	_bank["step"] = _wav(b)

	b = _mk(0.12)  # strike lands
	_noise(b, 0.0, 0.06, 0.4, 2.0)
	_tone(b, 0.0, 0.12, 240, 150, 0.5, 2.0, 0.4)
	_bank["hit"] = _wav(b)

	b = _mk(0.22)  # player takes damage
	_tone(b, 0.0, 0.22, 320, 130, 0.5, 1.6, 0.5)
	_noise(b, 0.0, 0.1, 0.25, 2.0)
	_bank["hurt"] = _wav(b)

	b = _mk(0.16)  # enemy destroyed
	_noise(b, 0.0, 0.12, 0.45, 1.8)
	_tone(b, 0.02, 0.14, 500, 180, 0.35, 2.0)
	_bank["kill"] = _wav(b)

	b = _mk(0.2)  # ability cast
	_tone(b, 0.0, 0.14, 660, 660, 0.3, 2.0)
	_tone(b, 0.05, 0.15, 990, 990, 0.25, 2.0)
	_bank["cast"] = _wav(b)

	b = _mk(0.28)  # cleanse sparkle (rising)
	_tone(b, 0.0, 0.1, 523, 523, 0.25, 2.0)
	_tone(b, 0.08, 0.1, 784, 784, 0.25, 2.0)
	_tone(b, 0.16, 0.12, 1047, 1047, 0.28, 2.0)
	_bank["sparkle"] = _wav(b)

	b = _mk(0.25)  # heal
	_tone(b, 0.0, 0.25, 392, 392, 0.22, 1.6)
	_tone(b, 0.04, 0.2, 494, 494, 0.18, 1.6)
	_bank["heal"] = _wav(b)

	b = _mk(0.18)  # bloom / purchase
	_tone(b, 0.0, 0.08, 1319, 1319, 0.28, 2.5)
	_tone(b, 0.07, 0.1, 1760, 1760, 0.24, 2.5)
	_bank["coin"] = _wav(b)

	b = _mk(0.45)  # descend the stairs
	_tone(b, 0.0, 0.45, 400, 120, 0.3, 1.4, 0.3)
	_noise(b, 0.1, 0.3, 0.15, 1.5)
	_bank["descend"] = _wav(b)

	b = _mk(0.3)  # dragged / mechanical yank
	_tone(b, 0.0, 0.3, 520, 240, 0.3, 1.5, 0.7)
	_bank["drag"] = _wav(b)

	b = _mk(0.35)  # vent reinforcement / dark rumble
	_noise(b, 0.0, 0.35, 0.35, 1.4)
	_tone(b, 0.0, 0.3, 120, 80, 0.3, 1.5)
	_bank["vent"] = _wav(b)

	b = _mk(0.5)  # smog dims / chokes
	_tone(b, 0.0, 0.5, 150, 90, 0.3, 1.2, 0.5)
	_noise(b, 0.0, 0.4, 0.2, 1.2)
	_bank["dim"] = _wav(b)

	b = _mk(0.5)  # boss phase horn
	_tone(b, 0.0, 0.5, 110, 110, 0.4, 1.2, 0.6)
	_tone(b, 0.05, 0.45, 165, 160, 0.3, 1.3, 0.4)
	_bank["boss"] = _wav(b)

	b = _mk(0.8)  # death
	_tone(b, 0.0, 0.8, 220, 90, 0.4, 1.2, 0.5)
	_tone(b, 0.2, 0.6, 174, 80, 0.3, 1.3)
	_bank["death"] = _wav(b)

	b = _mk(0.9)  # win fanfare
	_tone(b, 0.0, 0.25, 523, 523, 0.3, 1.5, 0.3)
	_tone(b, 0.22, 0.25, 659, 659, 0.3, 1.5, 0.3)
	_tone(b, 0.44, 0.45, 784, 784, 0.35, 1.2, 0.3)
	_bank["win"] = _wav(b)


func _render_music() -> void:
	call_deferred("_music_ready", render_music_stream())


## 12-second seamless four-chord ambient loop (rendered off the main thread
## in play; called directly by the test suite).
func render_music_stream() -> AudioStreamWAV:
	var chords := [[48, 55, 60, 64], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]]
	var cd := 3.0
	var buf := _mk(cd * chords.size())
	for ci in chords.size():
		var t0 := ci * cd
		for m in chords[ci]:
			_pad(buf, t0, cd + 0.8, 440.0 * pow(2.0, (m - 69) / 12.0), 0.05)
		for k in 8:
			var m2: int = chords[ci][(k * 3) % chords[ci].size()] + 12
			_tone(buf, t0 + k * cd / 8.0, 0.3, 440.0 * pow(2.0, (m2 - 69) / 12.0),
				440.0 * pow(2.0, (m2 - 69) / 12.0), 0.075, 3.0, 0.25, true)
	# wind bed: very quiet, very dark
	_noise(buf, 0.0, cd * chords.size(), 0.006, 0.001, true, 0.99)
	return _wav(buf)


func _music_ready(stream: AudioStreamWAV) -> void:
	_music_player.stream = stream
	if music_on:
		_music_player.play()
