class_name AttackVolume
extends Area3D

## Ventana de impacto del cuerpo a cuerpo. No es un raycast por frame: a 40 FPS un tajo
## rapido puede saltarse un objetivo. El area vive siempre montada y lo que se abre y se
## cierra es la ventana de dano, porque reencender monitoring no vuelve a reportar a los
## cuerpos que ya estaban dentro y ese es el caso mas comun del combate. Un mismo swing no
## golpea dos veces al mismo objetivo.

signal landed(target: Node, damage: float, was_stunned: bool)

var _damage := 0.0
var _source: Node3D
var _hit: Array[RID] = []
var _started_at := 0.0
var _open_at := 0.0
var _close_at := 0.0
var _swinging := false
var _open := false
var _shape: CollisionShape3D


## reach y radius en metros; target_mask son las capas de quien puede recibir el golpe.
## Se llama desde aqui y no desde _ready: el estado de monitoring tiene que quedar fijado
## antes de que begin_swing lo reescriba, y _ready llega con un orden diferido respecto a la
## llamada que añade el nodo al arbol. Idempotente porque se vuelve en cada cambio de arma:
## si anadiera una forma nueva cada vez, el personaje acabaria con un volumen por arma.
func setup(reach: float, radius: float, target_mask: int) -> void:
	collision_layer = 8
	collision_mask = target_mask
	if _shape == null:
		monitoring = true
		monitorable = false
		_shape = CollisionShape3D.new()
		add_child(_shape)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_shape.shape = sphere
	# El volumen es hijo del nodo Model del personaje, y el maniqui mira a +Z: el frente es
	# +Z, no -Z como en el resto de Godot. El 1,2 de altura es el pecho del objetivo.
	_shape.position = Vector3(0, 1.2, reach)


func begin_swing(damage: float, source: Node3D, open_at: float, close_at: float, clip_length: float) -> void:
	_damage = damage
	_source = source
	_hit.clear()
	_swinging = true
	_started_at = _now()
	_open_at = _started_at + clip_length * open_at
	_close_at = _started_at + clip_length * close_at
	_open = false
	if clip_length * open_at <= 0.0:
		_open = true


func end_swing() -> void:
	_swinging = false
	_open = false


func is_swinging() -> bool:
	return _swinging


## Se barre en lugar de escuchar body_entered: un NPC que ya esta pegado cuando la ventana
## se abre nunca "entra", y ese es el caso mas comun de todo el combate.
func _process(_delta: float) -> void:
	if not _swinging:
		return
	var now := _now()
	if now >= _close_at:
		end_swing()
		return
	if not _open:
		if now >= _open_at:
			_open = true
		else:
			return
	for body in get_overlapping_bodies():
		_try_hit(body)


func _try_hit(body: PhysicsBody3D) -> void:
	var rid := body.get_rid()
	if _hit.has(rid):
		return
	var combatant := body.get_node_or_null("Combatant") as Combatant
	if combatant == null or not combatant.is_alive():
		return
	_hit.append(rid)
	# El critico se decide con el estado ANTERIOR al golpe: el bandido entra en STUN
	# dentro de take_damage, asi que leerlo despues convertiria cada impacto en critico.
	var was_stunned := _state_is_stunned(body)
	combatant.take_damage(_damage, _source.global_position if _source != null else global_position)
	landed.emit(body, _damage, was_stunned)


func _state_is_stunned(body: Node) -> bool:
	var state = body.get("state")
	return state != null and str(state) == "STUN"


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
