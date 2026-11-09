class_name Projectile
extends Node3D

## El pilum en vuelo. Unico proyectil del juego, y por eso vive aislado: no toca el
## esqueleto, ni las capas de colision, ni el AttackVolume de nadie.
##
## El raycast es del SEGMENTO QUE BARRE EL PILUM ENTERO, de la cola a la punta: un
## raycast a la punta pasaria por debajo de los cuerpos que el astil ya esta
## barreciendo, que es justo el fallo que se midio en el volumen de ataque del NPC hostil.

signal landed(target: Node, damage: float, was_stunned: bool)

const WeaponScript := preload("res://scripts/combat/weapon.gd")

## Terreno (1) y cuerpos de NPC (4). El jugador (2) queda fuera: el pilum sale de el.
const DEFAULT_MASK := 1 | 4

## Tiempo que el pilum se queda clavado en el terreno antes de retirarse solo.
const STUCK_SECONDS := 2.5

var _direction := Vector3(0, 0, 1)
var _speed := 26.0
var _damage := 40.0
var _max_distance := 26.0
var _mask := DEFAULT_MASK
var _half_length := 1.0
var _travelled := 0.0
var _stuck := false
var _stuck_until := 0.0


## La mano es el punto de partida, no el centro del pilum: el astil sale de la mano hacia
## delante, igual que en la mano de Rito.
func setup(hand_position: Vector3, direction: Vector3, damage: float, speed: float, max_distance: float, mask: int = DEFAULT_MASK) -> void:
	_direction = direction.normalized()
	_damage = damage
	_speed = speed
	_max_distance = max_distance
	_mask = mask
	_build_visual()
	_orient(_direction)
	global_position = hand_position + _direction * _half_length


## La malla del pilum viene con el agarre en el origen; aqui se centra en su punto medio,
## de modo que el nodo del proyectil esta en el centro del astil y la punta queda a media
## longitud por delante.
func _build_visual() -> void:
	var mesh := WeaponScript.make_pilum()
	var aabb := mesh.get_aabb()
	_half_length = aabb.size.z * 0.5

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.z = -aabb.get_center().z
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.5
	material.metallic = 0.4
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	instance.material_override = material
	add_child(instance)


## El arma vuela con su +Z hacia delante, que es la convencion del modelo del personaje.
## Se construye la base a mano porque looking_at apunta el -Z, al reves de lo que quiere
## la malla.
func _orient(direction: Vector3) -> void:
	var forward := direction.normalized()
	var right := Vector3.UP.cross(forward)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := forward.cross(right).normalized()
	basis = Basis(right, up, forward)


func _physics_process(delta: float) -> void:
	if _stuck:
		if _now() >= _stuck_until:
			queue_free()
		return

	var step := _speed * delta
	# De la cola a la punta: el segmento que el pilum barre en este frame.
	var from := global_position - _direction * _half_length
	var to := global_position + _direction * (_half_length + step)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = _mask
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		_on_hit(hit["collider"], hit["position"])
		return

	global_position += _direction * step
	_travelled += step
	if _travelled >= _max_distance:
		queue_free()


func _on_hit(collider: Object, hit_position: Vector3) -> void:
	var combatant: Combatant = null
	if collider is Node:
		combatant = (collider as Node).get_node_or_null("Combatant") as Combatant

	if combatant != null and combatant.is_alive():
		var was_stunned := _state_is_stunned(collider as Node)
		combatant.take_damage(_damage, global_position)
		landed.emit(collider as Node, _damage, was_stunned)
		queue_free()
		return
	# Un Combatant ya muerto no recibe dano ni cuenta como baja: el pilum se clava
	# como si fuera terreno y se retira solo.

	# Terreno: el pilum se clava y se retira solo.
	global_position = hit_position - _direction * _half_length
	_stuck = true
	_stuck_until = _now() + STUCK_SECONDS


func _state_is_stunned(body: Node) -> bool:
	var state = body.get("state")
	return state != null and str(state) == "STUN"


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
