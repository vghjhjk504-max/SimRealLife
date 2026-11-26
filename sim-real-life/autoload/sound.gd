extends Node
# Весь звук синтезируется при старте — выстрелы, хиты, респавн. Ассетов ноль.

signal mute_changed(muted: bool)

const RATE := 22050
var streams: Dictionary = {}
var muted := false
var _voices: Array[AudioStreamPlayer] = []
var _vi := 0

func _ready() -> void:
	_build_all()
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)

func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	mute_changed.emit(muted)

func play(name: StringName, volume_db := 0.0) -> void:
	if not streams.has(name):
		return
	var p := _voices[_vi]
	_vi = (_vi + 1) % _voices.size()
	p.stream = streams[name]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.94, 1.06)
	p.play()

func play3d(name: StringName, host: Node, pos: Vector3, volume_db := 0.0) -> void:
	if not streams.has(name):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = streams[name]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.94, 1.06)
	p.unit_size = 12.0
	p.max_distance = 70.0
	host.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

func _noise() -> float:
	return randf() * 2.0 - 1.0

func _synth(dur: float, f: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v := clampi(int(f.call(t, dur) * 32767.0), -32768, 32767)
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav

func _build_all() -> void:
	streams[&"pistol"] = _synth(0.22, func(t, _d):
		return (_noise() * 0.65 + sin(t * 150.0 * TAU) * 0.5) * exp(-t * 26.0) * 0.9)
	streams[&"rifle"] = _synth(0.15, func(t, _d):
		return (_noise() * 0.7 + sin(t * 190.0 * TAU) * 0.4) * exp(-t * 40.0) * 0.85)
	streams[&"swing"] = _synth(0.16, func(t, d):
		return _noise() * sin(PI * t / d) * 0.35)
	streams[&"hit"] = _synth(0.08, func(t, _d):
		return (sin(t * 950.0 * TAU) * 0.6 + _noise() * 0.25) * exp(-t * 55.0))
	streams[&"kill"] = _synth(0.16, func(t, _d):
		return sin(t * (1300.0 + t * 2500.0) * TAU) * exp(-t * 18.0) * 0.5)
	streams[&"hurt"] = _synth(0.28, func(t, _d):
		return sin(t * (130.0 - t * 120.0) * TAU) * exp(-t * 11.0) * 0.7)
	streams[&"death"] = _synth(0.7, func(t, _d):
		return (sin(t * (200.0 - t * 180.0) * TAU) * 0.6 + _noise() * 0.15) * exp(-t * 4.5))
	streams[&"reload"] = _synth(0.32, func(t, _d):
		var a := exp(-(t - 0.02) * 90.0) if t > 0.02 else 0.0
		var b := exp(-(t - 0.2) * 70.0) if t > 0.2 else 0.0
		return _noise() * (a + b) * 0.5)
	streams[&"switch"] = _synth(0.07, func(t, _d):
		return sin(t * 620.0 * TAU) * exp(-t * 45.0) * 0.35)
	streams[&"empty"] = _synth(0.05, func(t, _d):
		return sin(t * 1250.0 * TAU) * exp(-t * 80.0) * 0.25)
	streams[&"respawn"] = _synth(0.45, func(t, _d):
		var f := 330.0 if t < 0.15 else (415.0 if t < 0.3 else 495.0)
		return sin(t * f * TAU) * exp(-fmod(t, 0.15) * 9.0) * 0.4)
		