class_name SlingerNpc
extends "res://scripts/npc/hostile_npc.gd"

## Hondero: enemigo a distancia. Mantiene al jugador entre 8 y 14 m (si se acerca,
## retrocede; si se aleja, lo persigue) y lanza piedras cuando esta en su banda.
## Reusa el maniqui, el esqueleto y las animaciones del bandido base.

const ProjectileScript := preload("res://scripts/combat/projectile.gd")

const SLINGER_HEALTH := 35.0
const SLINGER_DAMAGE := 10.0
const SLINGER_SPEED := 3.0

## Banda de tiro: por debajo de PREFERRED_MIN retrocede, por encima de
## PREFERRED_MAX avanza, y entre ambas se queda y lanza.
const PREFERRED_MIN := 8.0
const PREFERRED_MAX := 14.0
const THROW_COOLDOWN := 2.5
const STONE_SPEED := 26.0
const STONE_RANGE := 30.0
## Terreno, Rito y moloso: las piedras chocan contra el terreno y no atraviesan
## colinas.
const STONE_MASK := 1 | 2 | 16


func setup_slinger(data, center: Vector3, angle: float, target: Node3D = null, player: Node3D = null) -> void:
	max_health = SLINGER_HEALTH
	attack_damage = SLINGER_DAMAGE
	chase_speed = SLINGER_SPEED
	super.setup(data, center, angle, target, player)


func _physics_process(delta: float) -> void:
	if state == "DEAD":
		_corpse_until -= delta
		if _corpse_until <= 0.0:
			queue_free()
		return

	if state == "STUN":
		if _now() >= _stun_until:
			state = "AGGRO"
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	if _target == null or not is_instance_valid(_target):
		super._physics_process(delta)
		return

	var distance := global_position.distance_to(_target.global_position)
	if distance < PREFERRED_MIN:
		_kite_away(delta)
	elif distance > PREFERRED_MAX:
		_chase(_flat_direction_to_target(), delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_face(_flat_direction_to_target())
		_play("Idle")
		_try_attack()
	_apply_gravity(delta)
	move_and_slide()


## Retrocede manteniendo el objetivo delante: huir del cuerpo a cuerpo es su
## unica defensa.
func _kite_away(_delta: float) -> void:
	var away := _flat_direction_to_target() * -1.0
	velocity.x = away.x * chase_speed
	velocity.z = away.z * chase_speed
	_face(_flat_direction_to_target())
	_play("Walk")


## El ataque del hondero no es melee: lanza una piedra. El volumen de ataque del
## cuerpo queda sin abrir (no lo usa); el proyectil hace el dano.
func _try_attack() -> void:
	if _now() < _attack_ready:
		return
	_attack_ready = _now() + THROW_COOLDOWN
	_play("Punch_Cross")
	var direction := _flat_direction_to_target()
	var origin := global_position + Vector3(0, 1.4, 0)
	var projectile := ProjectileScript.new()
	projectile.name = "Stone"
	var host := get_parent()
	if host == null:
		host = get_tree().current_scene
	if host != null:
		host.add_child(projectile)
		projectile.setup(origin, direction, attack_damage, STONE_SPEED, STONE_RANGE,
			STONE_MASK, WeaponScript.make_stone())
		var sfx := _sfx()
		if sfx != null:
			sfx.call("play", "throw", global_position, -8.0)
