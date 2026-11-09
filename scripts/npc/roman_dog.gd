class_name RomanDog
extends CharacterBody3D

## El moloso: perro romano de combate que acompana a Rito. Reutiliza la evitancia por
## raycast del patrullero, pero no patrulla: sigue al amo y muerde a los bandidos.
##
## Tiene esqueleto propio (21 huesos, scripts/npc/dog_rig.gd) con las seis animaciones de
## pelea: respiration, ciclo de patas en diagonal, carrera, mordida, tumbo y levantarse.
##
## No muere. Si le bajan la vida a cero se tumba de verdad: el visual se va a un
## RigidBody3D que rueda por el suelo, y al cabo de un momento el perro se levanta. Un
## compañero que puede morir deja al jugador sin acompanante en mitad de una pelea.

const DogRigScript := preload("res://scripts/npc/dog_rig.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const GRAVITY := 26.0
const FOLLOW_SPEED := 7.0
const FOLLOW_MIN := 2.2
const FOLLOW_MAX := 3.6

## Rito corre a 12 m/s. Si el moloso sigue a 7, se queda atras para siempre y el
## amo desaparece: cuando la distancia se pasa, el perro corre mas rapido que el
## sprint y recupera el terreno perdido. El umbral es corto a proposito (5 m):
## con 8 m el perro se frenaba a velocidad de paseo justo cuando el jugador
## corria, y se quedaba clavado a siete metros sin llegar nunca.
const CATCHUP_DISTANCE := 5.0
const CATCHUP_SPEED := 15.5

## El silbido: el moloso deja lo que sea y vuelve con su amo.
const CALL_DURATION := 6.0
const CHASE_RANGE := 14.0
const LOSE_RANGE := 20.0
const BITE_RANGE := 1.3
const BITE_DAMAGE := 18.0
const BITE_COOLDOWN := 1.0
const CHASE_SPEED := 8.5
const SENSE_INTERVAL := 0.4
const OBSTACLE_DISTANCE := 3.0

## Vida del moloso. Al llegar a cero se tumba, no muere.
const MAX_HEALTH := 60.0

## Capa propia: el volumen de ataque de Rito (máscara 4) no la alcanza, y el del bandido
## (máscara 2 | 16) si. Colisiona con el terreno y con Rito, para no meterse dentro de
## su amo.
const OWN_LAYER := 16
const OWN_MASK := 1 | 2

## El cuerpo rigido del trompeco: capa 32, colisiona solo con el terreno.
const TUMBLE_LAYER := 32
const TUMBLE_MASK := 1
const TUMBLE_SECONDS := 1.4
const TUMBLE_IMPULSE := 4.0
const TUMBLE_LIFT := 1.8

signal killed(target: Node)

var state := "FOLLOW"

var _player: Node3D
var _model: Node3D
var _rig: DogRig
var _combatant: Combatant
var _target: Node3D
var _sense_until := 0.0
var _bite_ready := 0.0
var _tumble_body: RigidBody3D
var _tumble_until := 0.0
## El clip de levantarse no se interrumpe: si se cambiara por el de andar a mitad, los
## huesos que ese clip no toca se quedarian tumbados y el perro no se levantaria.
var _get_up_until := 0.0

## Hasta cuando dura el efecto del silbido: el moloso vuelve con su amo a toda
## velocidad durante estos segundos.
var _called_until := 0.0


func setup(player: Node3D) -> void:
	_player = player
	collision_layer = OWN_LAYER
	collision_mask = OWN_MASK
	floor_snap_length = 0.4

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.22
	capsule.height = 0.72
	shape.shape = capsule
	shape.position = Vector3(0, 0.42, 0)
	add_child(shape)

	_combatant = CombatantScript.new()
	_combatant.name = "Combatant"
	add_child(_combatant)
	_combatant.setup(MAX_HEALTH)
	_combatant.died.connect(_on_knocked_down)

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)

	_rig = DogRigScript.new()
	_rig.name = "Rig"
	_model.add_child(_rig)
	_rig.build()
	_rig.play("IDLE")


## El silbido: el moloso deja la pelea y vuelve con su amo, aunque este lejos.
func call_to_player() -> void:
	if state == "DOWN":
		return
	_target = null
	state = "FOLLOW"
	_called_until = _now() + CALL_DURATION
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "bark", global_position, -4.0)


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return

	if state == "DOWN":
		_process_tumble(delta)
		return

	_apply_gravity(delta)
	match state:
		"FOLLOW":
			_follow(delta)
		"CHASE":
			_chase(delta)
		"BITE":
			_bite_state(delta)

	move_and_slide()
	_update_animation()


## El perro tumbado: su visual va en un cuerpo rigido que rueda, y el nodo del perro
## sigue al cuerpo para que no se separen.
func _process_tumble(_delta: float) -> void:
	if _tumble_body == null or not is_instance_valid(_tumble_body):
		return
	global_position = _tumble_body.global_position
	if _now() >= _tumble_until:
		_get_up()


func _get_up() -> void:
	if _tumble_body != null and is_instance_valid(_tumble_body):
		_tumble_body.queue_free()
	_tumble_body = null
	collision_layer = OWN_LAYER
	collision_mask = OWN_MASK
	if _rig != null:
		_rig.reparent(_model, true)
		_rig.transform = Transform3D.IDENTITY
		_rig.play("GET_UP", 0.05)
	_get_up_until = _now() + DogRigScript.GET_UP_LENGTH
	if _combatant != null:
		_combatant.heal_full()
	state = "FOLLOW"


func _follow(delta: float) -> void:
	if _sense_enemy():
		state = "CHASE"
		return
	# El objetivo no es el amo, sino el punto de escolta detras de el. Perseguir la
	# posicion del amo hacia al perro de largo: con la velocidad de catch-up (15,5
	# frente a los 12 del sprint) lo rebasaba y se alejaba por el otro lado.
	var target_point := _escort_point()
	var to_point := _flat_direction(target_point - global_position)
	var distance := _flat_distance(target_point - global_position)
	if distance > 0.4:
		# La velocidad depende de lo lejos que este: si Rito ha salido corriendo, el
		# moloso tiene que correr mas rapido que el sprint o se queda en el valle.
		var speed := FOLLOW_SPEED
		if distance > CATCHUP_DISTANCE or _now() < _called_until:
			speed = CATCHUP_SPEED
		_move_towards(to_point, speed, delta)
	else:
		_stop()


## El punto de escolta: detras del amo, a la distancia de acompanamiento. Si el amo
## gira, el punto gira con el.
func _escort_point() -> Vector3:
	var forward := Vector3.FORWARD
	var model = _player.get("model")
	if model is Node3D and is_instance_valid(model):
		forward = (model as Node3D).global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	return _player.global_position - forward.normalized() * FOLLOW_MAX


func _chase(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		state = "FOLLOW"
		return
	var to_target := _target.global_position - global_position
	if _flat_distance(to_target) > LOSE_RANGE:
		_target = null
		state = "FOLLOW"
		return
	if _flat_distance(to_target) <= BITE_RANGE:
		state = "BITE"
		_bite()
		return
	_move_towards(_flat_direction(to_target), CHASE_SPEED, delta)


func _bite_state(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = null
		state = "FOLLOW"
		return
	var to_target := _target.global_position - global_position
	if _flat_distance(to_target) > BITE_RANGE * 1.6:
		state = "CHASE"
		return
	_face(_flat_direction(to_target))
	_stop()
	_bite()


## Busca el bandido mas cercano. La busqueda va con intervalo, no cada frame: son cuatro
## NPCs en el valle y el raycast de vision ya hace un trabajo parecido en el hostil.
func _sense_enemy() -> bool:
	if _now() < _sense_until:
		if _target != null and is_instance_valid(_target) and _is_live_hostile(_target):
			return true
		_target = null
		return false
	_sense_until = _now() + SENSE_INTERVAL

	var best: Node3D = null
	var best_distance := CHASE_RANGE
	for node in get_tree().get_nodes_in_group("hostiles"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		# Un cadaver sigue en el grupo durante CORPSE_SECONDS: sin este filtro el
		# moloso lo muerde y emite killed una y otra vez sobre el mismo muerto.
		if not _is_live_hostile(enemy):
			continue
		var distance := _flat_distance(enemy.global_position - global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	_target = best
	return _target != null


func _is_live_hostile(node: Node3D) -> bool:
	var combatant := node.get_node_or_null("Combatant") as Combatant
	return combatant != null and combatant.is_alive()


## El mordisco no usa volumen de ataque: el NPC hostil ya demostro que un volumen
## montado a 1,9 m pasa de largo a un objetivo que se ha colado dentro (distancia minima
## medida: 0,00 m y cero golpes en seis segundos de pelea).
func _bite() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _now() < _bite_ready:
		return
	var combatant := _target.get_node_or_null("Combatant") as Combatant
	if combatant == null:
		return
	if not combatant.is_alive():
		_target = null
		state = "FOLLOW"
		return
	_bite_ready = _now() + BITE_COOLDOWN
	var was_alive := combatant.is_alive()
	combatant.take_damage(BITE_DAMAGE, global_position)
	if _rig != null:
		_rig.play("BITE", 0.05)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "bark", global_position, -8.0)
	if was_alive and not combatant.is_alive():
		killed.emit(_target)
		_target = null
		state = "FOLLOW"


## Al bandido le bajan la vida a cero, el perro se tumba: el visual se reparenta a un
## cuerpo rigido que recibe el golpe y rueda por el suelo.
func _on_knocked_down(source_position: Vector3) -> void:
	if state == "DOWN":
		return
	state = "DOWN"
	velocity = Vector3.ZERO
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "hurt", global_position, -8.0)
	collision_layer = 0
	collision_mask = 0

	var body := RigidBody3D.new()
	body.name = "CuerpoTirado"
	body.collision_layer = TUMBLE_LAYER
	body.collision_mask = TUMBLE_MASK
	body.mass = 8.0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 0.72
	shape.shape = capsule
	shape.position = Vector3(0, 0.42, 0)
	body.add_child(shape)

	var host: Node = get_parent()
	if host == null:
		host = get_tree().current_scene
	host.add_child(body)
	body.global_position = global_position + Vector3(0, 0.2, 0)

	# El visual se va al cuerpo rigido. Se reparenta conservando la transformacion
	# global, y luego se vuelve a poner en su sitio al levantarse.
	if _rig != null:
		_rig.reparent(body, true)
		_rig.play("DOWN", 0.05)

	var away := global_position - source_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.FORWARD
	body.apply_central_impulse(away.normalized() * TUMBLE_IMPULSE + Vector3.UP * TUMBLE_LIFT)
	body.apply_torque_impulse(Vector3.RIGHT * TUMBLE_IMPULSE * 0.4)

	_tumble_body = body
	_tumble_until = _now() + TUMBLE_SECONDS


func _move_towards(direction: Vector3, speed: float, delta: float) -> void:
	if direction.length() < 0.01:
		_stop()
		return
	if _obstacle_ahead(direction):
		direction = direction.rotated(Vector3.UP, 1.2)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * speed, 9.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_face(direction)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _face(direction: Vector3) -> void:
	if _model != null and direction.length() > 0.01:
		_model.rotation.y = atan2(direction.x, direction.z)


## El estado del esqueleto decide el clip: quieto respira, andando y corriendo distinguen
## la velocidad, y la mordida tiene su propio clip.
func _update_animation() -> void:
	if _rig == null:
		return
	if state == "BITE":
		return
	# Mientras el perro se levanta, el clip manda.
	if _now() < _get_up_until:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if state == "CHASE":
		_rig.play("RUN")
	elif speed > 0.4:
		_rig.play("WALK")
	else:
		_rig.play("IDLE")


func _obstacle_ahead(direction: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.5, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * OBSTACLE_DISTANCE)
	query.collision_mask = 1
	return not space.intersect_ray(query).is_empty()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _flat_direction(to_target: Vector3) -> Vector3:
	var direction := to_target
	direction.y = 0.0
	return direction.normalized()


func _flat_distance(to_target: Vector3) -> float:
	var difference := to_target
	difference.y = 0.0
	return difference.length()


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
