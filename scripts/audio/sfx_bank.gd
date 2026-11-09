class_name SfxBank
extends RefCounted

## Banco de efectos generado por codigo: ningun asset de audio externo. Cada efecto es
## una forma de onda sintetizada en un AudioStreamWAV de 16 bits y 22050 Hz, con semilla
## fija por nombre para que los tests sean deterministas.
##
## En el export web el audio se desbloquea con el primer gesto del usuario (el clic que
## captura el raton del boot overlay ya cuenta), asi que no hace falta espera extra.

const MIX_RATE := 22050

const NAMES: Array[String] = [
	"swing", "swing_heavy", "throw", "hit", "heavy_hit", "kill", "hurt",
	"dodge", "step", "bark", "enemy_hit", "enemy_die", "death", "ui", "pickup", "wind",
	"critical",
]

static var _cache: Dictionary = {}


static func get_stream(name: String) -> AudioStreamWAV:
	if _cache.has(name):
		return _cache[name]
	var stream: AudioStreamWAV
	match name:
		"swing":
			stream = _whoosh(0.18, 350.0, 1500.0, 0.50, name)
		"swing_heavy":
			stream = _whoosh(0.30, 220.0, 950.0, 0.60, name)
		"throw":
			stream = _whoosh(0.32, 1600.0, 480.0, 0.45, name)
		"hit":
			stream = _thud(0.16, 100.0, 30.0, 0.90, 0.40, name)
		"heavy_hit":
			stream = _thud(0.28, 62.0, 16.0, 1.00, 0.60, name)
		"kill":
			stream = _fall(0.45, 150.0, 35.0, 0.90, name)
		"hurt":
			stream = _thud(0.20, 150.0, 24.0, 0.70, 0.50, name)
		"dodge":
			stream = _whoosh(0.26, 480.0, 1250.0, 0.32, name)
		"step":
			stream = _step(name)
		"bark":
			stream = _bark(name)
		"enemy_hit":
			stream = _thud(0.16, 130.0, 28.0, 0.80, 0.40, name)
		"enemy_die":
			stream = _fall(0.60, 320.0, 55.0, 0.80, name)
		"death":
			stream = _fall(0.90, 220.0, 38.0, 0.90, name)
		"ui":
			stream = _click(name)
		"pickup":
			stream = _pickup(name)
		"critical":
			stream = _thud(0.36, 48.0, 22.0, 1.20, 0.62, name)
		"wind":
			stream = _wind(name)
		_:
			stream = _click(name)
	_cache[name] = stream
	return stream


static func _rng(seed_name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sfx:" + seed_name)
	return rng


static func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream


## Barrido de ruido modulado en frecuencia: la forma basica de un whoosh.
static func _whoosh(seconds: float, f0: float, f1: float, amp: float, seed_name: String) -> AudioStreamWAV:
	var rng := _rng(seed_name)
	var count := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		phase += TAU * lerpf(f0, f1, t) / MIX_RATE
		var env := pow(sin(PI * t), 1.3)
		samples[i] = rng.randf_range(-1.0, 1.0) * env * (0.55 + 0.45 * sin(phase)) * amp
	return _to_wav(samples)


## Golpe seco: seno grave con decaimiento exponencial mas un golpe de ruido.
static func _thud(seconds: float, freq: float, decay: float, amp: float, noise_amp: float, seed_name: String) -> AudioStreamWAV:
	var rng := _rng(seed_name)
	var count := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		phase += TAU * freq / MIX_RATE
		var env := exp(-t * decay)
		samples[i] = (sin(phase) * amp + rng.randf_range(-1.0, 1.0) * noise_amp * exp(-t * decay * 2.0)) * env
	return _to_wav(samples)


## Caida en picado de frecuencia: muerte o remate.
static func _fall(seconds: float, f0: float, f1: float, amp: float, seed_name: String) -> AudioStreamWAV:
	var rng := _rng(seed_name)
	var count := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		phase += TAU * lerpf(f0, f1, t * t) / MIX_RATE
		var env := exp(-t * 4.0) * (1.0 - t * 0.6)
		samples[i] = (sin(phase) * amp + rng.randf_range(-1.0, 1.0) * 0.3 * env) * env
	return _to_wav(samples)


static func _step(seed_name: String) -> AudioStreamWAV:
	var rng := _rng(seed_name)
	var count := int(0.07 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		phase += TAU * 260.0 / MIX_RATE
		samples[i] = (rng.randf_range(-1.0, 1.0) * 0.35 + sin(phase) * 0.18) * exp(-t * 85.0)
	return _to_wav(samples)


## Ladrido: dos pulsos de onda cuadrada distorsionada con un hueco entre medias.
static func _bark(seed_name: String) -> AudioStreamWAV:
	var rng := _rng(seed_name)
	var count := int(0.30 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		phase += TAU * 185.0 / MIX_RATE
		var pulse := 0.0
		if t < 0.09:
			pulse = exp(-t * 30.0)
		elif t > 0.15 and t < 0.24:
			pulse = exp(-(t - 0.15) * 30.0)
		var wave := tanh(sin(phase) * 3.0)
		samples[i] = wave * pulse * 0.8 + rng.randf_range(-1.0, 1.0) * pulse * 0.15
	return _to_wav(samples)


static func _click(_seed_name: String) -> AudioStreamWAV:
	var count := int(0.05 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		phase += TAU * 880.0 / MIX_RATE
		samples[i] = sin(phase) * exp(-t * 90.0) * 0.5
	return _to_wav(samples)


## Recogida de botin: dos tonos ascendentes cortos, tipo "ding" de moneda.
static func _pickup(seed_name: String) -> AudioStreamWAV:
	var rng := _rng(seed_name)
	var count := int(0.22 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var freq := 660.0 if t < 0.10 else 990.0
		phase += TAU * freq / MIX_RATE
		var env := exp(-t * 18.0)
		samples[i] = sin(phase) * env * 0.55 + rng.randf_range(-1.0, 1.0) * env * 0.08
	return _to_wav(samples)


## Viento ambiente en loop: ruido rosa aproximado con ventana suave en los extremos
## para que el bucle no cruja al volver al principio.
static func _wind(seed_name: String) -> AudioStreamWAV:
	var rng := _rng(seed_name)
	var count := int(2.5 * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var low := 0.0
	var fade := int(0.05 * MIX_RATE)
	for i in count:
		low = low * 0.97 + rng.randf_range(-1.0, 1.0) * 0.03
		var edge := 1.0
		if i < fade:
			edge = float(i) / float(fade)
		elif i > count - fade:
			edge = float(count - i) / float(fade)
		samples[i] = low * 6.0 * edge * 0.6
	return _to_wav(samples, true)
