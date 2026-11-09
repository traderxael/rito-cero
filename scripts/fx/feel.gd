class_name Feel
extends Node

## Game feel global: hit-stop (congelar el tiempo unos milisegundos en un impacto fuerte)
## y screen shake (la camara de Rito lee camera_offset() cada frame). Vive en el grupo
## "feel"; los tests headless que no lo montan simplemente no lo encuentran y el juego
## sigue igual.
##
## El reloj de ambos efectos es Time.get_ticks_msec() y no el delta del proceso: con
## time_scale a 0,06 los deltas se hacen enormes de esperar y el hit-stop nunca acabaria.

const HIT_STOP_SCALE := 0.06
const MAX_SHAKE := 0.6

## Tipos de impacto para efectos variados
const IMPACT_TYPE_NORMAL := "normal"
const IMPACT_TYPE_STRONG := "strong"
const IMPACT_TYPE_CRITICAL := "critical"

var _fx: ImpactFx
var _restore_at := -1.0
var _shake_until := 0.0
var _shake_seconds := 0.01
var _shake_amount := 0.0


func _ready() -> void:
	add_to_group("feel")


func setup(fx: ImpactFx) -> void:
	_fx = fx


func hit_stop(seconds: float, impact_type: String = IMPACT_TYPE_NORMAL) -> void:
	var stop_time := seconds
	var shake_delta := 0.0
	var shake_seconds := 0.0

	if impact_type == IMPACT_TYPE_STRONG:
		stop_time = seconds * 1.5
		shake_delta = 0.2
		shake_seconds = 0.15
	elif impact_type == IMPACT_TYPE_CRITICAL:
		stop_time = seconds * 2.0
		shake_delta = 0.4
		shake_seconds = 0.25

	Engine.time_scale = HIT_STOP_SCALE
	_restore_at = _now() + stop_time
	# El impacto normal no toca el shake en curso: solo el tipado lo modifica. La ventana
	# cubre al menos la duracion del shake para que no empiece a decaer antes de tiempo.
	if impact_type != IMPACT_TYPE_NORMAL:
		_shake_amount = minf(_shake_amount + shake_delta, MAX_SHAKE)
		_shake_seconds = shake_seconds
		_shake_until = _now() + maxf(stop_time, shake_seconds)


func shake(amount: float, seconds: float) -> void:
	_shake_amount = minf(_shake_amount + amount, MAX_SHAKE)
	_shake_seconds = seconds
	_shake_until = _now() + seconds


## Offset aleatorio que decae linealmente con el tiempo restante del shake. La camara lo
## suma a su posicion final; cuando el shake caduca devuelve cero exacto.
func camera_offset() -> Vector3:
	if _now() >= _shake_until or _shake_amount <= 0.0:
		return Vector3.ZERO
	var t := clampf((_shake_until - _now()) / maxf(_shake_seconds, 0.01), 0.0, 1.0)
	var magnitude := _shake_amount * t
	return Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * magnitude


func impact(at: Vector3, color: Color, big := false) -> void:
	if _fx != null:
		_fx.burst(at, color, big)


func is_frozen() -> bool:
	return _now() < _restore_at


func _process(_delta: float) -> void:
	if _restore_at > 0.0 and _now() >= _restore_at:
		Engine.time_scale = 1.0
		_restore_at = -1.0


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
