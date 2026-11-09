extends Node

## Escala de render adaptativa. Si el juego no llega al objetivo, baja la resolucion
## 3D antes que perder frames; si sobra margen, la sube. Con histeresis y un tiempo
## minimo entre cambios, porque reescalar el framebuffer da un tirón.

const DevVariantsScript := preload("res://scripts/dev/variants.gd")

const STEPS := [0.85, 0.75, 0.6, 0.5, 0.4]
const DOWN_FPS := 24.0
const UP_FPS := 57.0
const DOWN_SECONDS := 2.0
const UP_SECONDS := 6.0
const COOLDOWN := 3.0
const SAMPLE_WINDOW := 1.0

var _step := 1
var _elapsed := 0.0
var _low_time := 0.0
var _high_time := 0.0
var _cooldown := 0.0
var _samples: Array[float] = []
var _manual := false


func _ready() -> void:
	var scale := DevVariantsScript.render_scale(DevVariantsScript.current())
	for i in STEPS.size():
		if is_equal_approx(STEPS[i], scale):
			_step = i
			break
	_apply()


func _process(delta: float) -> void:
	if _manual or DevVariantsScript.is_explicit():
		return
	_elapsed += delta
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _elapsed < SAMPLE_WINDOW:
		return
	_elapsed = 0.0

	_samples.append(Engine.get_frames_per_second())
	if _samples.size() > 5:
		_samples.pop_front()
	var average := 0.0
	for value in _samples:
		average += value
	average /= _samples.size()

	if average < DOWN_FPS:
		_low_time += SAMPLE_WINDOW
		_high_time = 0.0
	elif average > UP_FPS:
		_high_time += SAMPLE_WINDOW
		_low_time = 0.0
	else:
		_low_time = 0.0
		_high_time = 0.0

	if _cooldown > 0.0:
		return
	if _low_time >= DOWN_SECONDS and _step < STEPS.size() - 1:
		_step += 1
		_apply()
		_reset_timers()
	elif _high_time >= UP_SECONDS and _step > 0:
		_step -= 1
		_apply()
		_reset_timers()


func _reset_timers() -> void:
	_low_time = 0.0
	_high_time = 0.0
	_cooldown = COOLDOWN
	_samples.clear()


func _apply() -> void:
	get_viewport().scaling_3d_scale = STEPS[_step]


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_quality"):
		return
	if _manual:
		_manual = false
		_reset_timers()
		print("QUALITY auto escala=%.2f" % STEPS[_step])
		return
	_manual = true
	_step = (_step + 1) % STEPS.size()
	_apply()
	print("QUALITY manual escala=%.2f" % STEPS[_step])
