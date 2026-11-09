class_name Combatant
extends Node

## Dueño único de la vida de quien lo lleva. Ni el jugador ni los NPCs deciden solos cuánto
## les queda: todo pasa por aquí, y las reglas de reentrancia se comprueban aquí.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source_position: Vector3)
signal died(source_position: Vector3)

var max_health := 100.0
var health := 100.0
var _dead := false
var _invulnerable_until := 0.0


func setup(p_max_health: float, invulnerable_seconds: float = 0.0) -> void:
	max_health = p_max_health
	health = p_max_health
	_dead = false
	_invulnerable_until = _now() + invulnerable_seconds
	health_changed.emit(health, max_health)


func take_damage(amount: float, source_position: Vector3) -> void:
	if _dead or amount <= 0.0:
		return
	if _now() < _invulnerable_until:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, source_position)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_dead = true
		died.emit(source_position)


## Curacion parcial (pociones). No revive: si esta muerto, sigue muerto.
func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func heal_full(invulnerable_seconds: float = 0.0) -> void:
	health = max_health
	_dead = false
	_invulnerable_until = _now() + invulnerable_seconds
	health_changed.emit(health, max_health)


func make_invulnerable(seconds: float) -> void:
	_invulnerable_until = _now() + seconds


func is_alive() -> bool:
	return not _dead


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
