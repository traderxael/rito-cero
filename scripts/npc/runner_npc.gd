class_name RunnerNpc
extends "res://scripts/npc/hostile_npc.gd"

## Corredor: enemigo rapido y fragil que flanquea. Lejos del objetivo entra en
## diagonal (45° por el mismo lado) y a menos de 6 m va directo a por el. Pega
## poco, pero muy seguido.

const RUNNER_HEALTH := 30.0
const RUNNER_DAMAGE := 8.0
const RUNNER_SPEED := 4.6
const RUNNER_SCALE := 0.95

## Cadencia del corredor: casi el doble que la del bandido base.
const ATTACK_COOLDOWN_R := 1.0
## A esta distancia deja de flanquear y va directo.
const DIRECT_RANGE := 6.0


func setup_runner(data, center: Vector3, angle: float, target: Node3D = null, player: Node3D = null) -> void:
	max_health = RUNNER_HEALTH
	attack_damage = RUNNER_DAMAGE
	chase_speed = RUNNER_SPEED
	body_scale = RUNNER_SCALE
	super.setup(data, center, angle, target, player)


## Flanqueo: en diagonal con el objetivo lejos, directo con el cerca.
func _flat_direction_to_target() -> Vector3:
	var directa := super._flat_direction_to_target()
	if _target == null or not is_instance_valid(_target):
		return directa
	if global_position.distance_to(_target.global_position) > DIRECT_RANGE:
		return directa.rotated(Vector3.UP, PI / 4)
	return directa


## Ataque rapido sin empujon: mismo esquema que el bandido base, cadencia 1,0 s.
func _try_attack() -> void:
	if _now() < _attack_ready:
		return
	_attack_ready = _now() + ATTACK_COOLDOWN_R
	_play("Sword_Attack", ATTACK_ANIM_SPEED)
	var clip_length := 0.5
	if _anim != null and _anim.has_animation("Sword_Attack"):
		clip_length = _anim.get_animation("Sword_Attack").length / ATTACK_ANIM_SPEED
	_swing_until = _now() + clip_length
	_volume.begin_swing(attack_damage, self, 0.25, 0.55, clip_length, ATTACK_WINDUP)
	var sfx := _sfx()
	if sfx != null:
		sfx.call("play", "swing", global_position, -12.0)
