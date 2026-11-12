class_name CollectSite
extends Node3D

## Sitio de la mision de recoleccion: 6 suministros de quest dispersos en un
## anillo alrededor de un POI, con 4 bandidos hostigando mientras tanto. Si
## el jugador muere, la mision falla; al recoger los 6, se completa.

const BanditCampScript := preload("res://scripts/missions/bandit_camp.gd")
const PickupScript := preload("res://scripts/missions/pickup.gd")

const SUMINISTROS := 6
const RADIO_SUMINISTROS := 20.0
const BANDIDOS := 4
const RADIO_BANDIDOS := 14.0

var _suministros: Array[Node3D] = []
var _bandidos: Array[Node3D] = []
var _sistema: MissionSystem
var _terrain: Variant
var _objetivo: Node3D
var _terminado := false


static func begin(parent: Node, center: Vector3, terrain: Variant, system: MissionSystem, target: Node3D) -> Node3D:
	var sitio := CollectSite.new()
	sitio.name = "CollectSite"
	parent.add_child(sitio)
	sitio._sistema = system
	sitio._terrain = terrain
	sitio._objetivo = target
	sitio._conectar_muerte(target)
	var datos: Variant = terrain.get_data() if terrain != null else null
	for i in SUMINISTROS:
		var angulo := TAU * float(i) / float(SUMINISTROS)
		var offset := Vector3(cos(angulo), 0.0, sin(angulo)) * RADIO_SUMINISTROS
		var posicion := center + offset
		if datos != null:
			var h: float = datos.get_height(Vector3(posicion.x, 0.0, posicion.z))
			if not is_nan(h):
				posicion.y = h
		var suma: Node3D = PickupScript.new()
		suma.name = "Suministro"
		suma.call("setup", "suministro", 1, true)
		suma.global_position = posicion
		suma.connect("collected", Callable(sitio, "_on_suministro_recogido"))
		parent.add_child(suma)
		sitio._suministros.append(suma)
	for i in BANDIDOS:
		var angulo := TAU * float(i) / float(BANDIDOS)
		var offset := Vector3(cos(angulo), 0.0, sin(angulo)) * RADIO_BANDIDOS
		var posicion := center + offset
		if datos != null:
			var h: float = datos.get_height(Vector3(posicion.x, 0.0, posicion.z))
			if not is_nan(h):
				posicion.y = h
		var bandido := BanditCampScript.spawn_bandit(sitio, posicion, angulo, terrain, target, "bandit")
		sitio._bandidos.append(bandido)
	return sitio


## Un suministro recogido: suma progreso y, si son todos, completa.
func _on_suministro_recogido(_id: String, _amount: int) -> void:
	if _terminado:
		return
	if _suministros.is_empty():
		return
	_suministros.pop_back()
	_sistema.register_progress(1)
	if _suministros.is_empty():
		_completar()


## Todos los suministros recogidos: completa la mision.
func _completar() -> void:
	if _terminado:
		return
	_terminado = true
	_sistema.register_progress(1)


## Cantidad de suministros pendientes (solo tests).
func restante() -> int:
	return _suministros.size()


## Lista de suministros (solo tests).
func suministros() -> Array[Node3D]:
	return _suministros.duplicate()


## La muerte del jugador falla la mision.
func _conectar_muerte(objetivo: Node3D) -> void:
	if objetivo == null:
		return
	var combatiente: Node = objetivo.get_node_or_null("Combatant")
	if combatiente != null and combatiente.has_signal("died"):
		combatiente.connect("died", Callable(self, "_on_player_died"))


func _on_player_died(_source_position: Vector3) -> void:
	if _terminado:
		return
	_terminado = true
	_sistema.fail_mission()
	finish()


## Cierre sin recompensa: libera los suministros y bandidos vivos.
func finish() -> void:
	_terminado = true
	for suma in _suministros:
		if is_instance_valid(suma):
			suma.queue_free()
	_suministros.clear()
	for bandido in _bandidos:
		if is_instance_valid(bandido):
			bandido.queue_free()
	_bandidos.clear()


## El jugador controlado (solo tests).
func jugador() -> Node3D:
	return _objetivo
