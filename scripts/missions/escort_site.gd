class_name EscortSite
extends Node3D

## Sitio de la mision de escolta: un aliado recorre una ruta de waypoints desde
## el origen hasta el destino. Dos emboscadas aparecen por el camino. Si el
## escolta o el jugador caen, la mision falla; si el escolta llega, se completa.

const BanditCampScript := preload("res://scripts/missions/bandit_camp.gd")
const EscortNpcScript := preload("res://scripts/npc/escort_npc.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const WAYPOINTS := 8
const AMBUSH_RADIUS := 10.0
const AMBUSH_BANDITS := 3

var _escort: Node3D
var _system: MissionSystem
var _terrain: Variant
var _objetivo: Node3D
var _terminado := false
var _emboscadas: Array = []
var _bandidos: Array = []
var _waypoints: Array[Vector3] = []


static func begin(parent: Node, system: MissionSystem, target: Node3D, origin: Vector3,
		destination: Vector3, terrain: Variant) -> Node3D:
	var sitio := EscortSite.new()
	sitio.name = "EscortSite"
	parent.add_child(sitio)
	sitio._system = system
	sitio._terrain = terrain
	sitio._objetivo = target
	sitio._conectar_muerte(target)
	sitio._waypoints = sitio._build_waypoints(origin, destination, terrain)
	sitio._escort = EscortNpcScript.new()
	sitio._escort.name = "Escolta"
	parent.add_child(sitio._escort)
	sitio._escort.call("setup", target, sitio._waypoints)
	sitio._escort.connect("arrived", Callable(sitio, "_on_arrived"))
	sitio._escort.connect("died", Callable(sitio, "_on_escort_died"))
	return sitio


## Waypoints en linea recta del origen al destino, con la altura del terreno.
func _build_waypoints(origin: Vector3, destination: Vector3, terrain: Variant) -> Array[Vector3]:
	var data: Variant = terrain.get_data() if terrain != null else null
	var waypoints: Array[Vector3] = []
	for i in WAYPOINTS:
		var t := float(i) / float(WAYPOINTS - 1)
		var pos := origin.lerp(destination, t)
		if data != null:
			var height: float = data.get_height(Vector3(pos.x, 0.0, pos.z))
			if not is_nan(height):
				pos.y = height
		waypoints.append(pos)
	return waypoints


func _process(delta: float) -> void:
	if _terminado or _escort == null:
		return
	_check_ambush()


## Lanza una emboscada cuando el escolta sale de los waypoints 3 y 6 (1-based),
## es decir cuando su indice de waypoint actual llega a 3 o 6 (0-based).
func _check_ambush() -> void:
	if _escort == null:
		return
	var idx := int(_escort.get("_waypoint_index"))
	var target := -1
	if idx == 3:
		target = 2
	elif idx == 6:
		target = 5
	if target < 0 or target in _emboscadas:
		return
	_emboscadas.append(target)
	_spawn_ambush(target)


func _spawn_ambush(waypoint_index: int) -> void:
	if _escort == null or _system == null:
		return
	var center := _escort.global_position
	var datos: Variant = _terrain.get_data() if _terrain != null else null
	var nivel := _system.level
	var conteo := AMBUSH_BANDITS
	if nivel >= 5:
		conteo += 1
	for i in conteo:
		var angulo := TAU * float(i) / float(conteo)
		var offset := Vector3(cos(angulo), 0.0, sin(angulo)) * 4.0
		var posicion := center + offset
		if datos != null:
			var h: float = datos.get_height(Vector3(posicion.x, 0.0, posicion.z))
			if not is_nan(h):
				posicion.y = h
		var bandido := BanditCampScript.spawn_bandit(self, posicion, angulo, _terrain,
				_escort, "bandit", _objetivo)
		(bandido.get_node("Combatant") as CombatantScript).died.connect(Callable(self, "_on_ambusher_died"))
		_bandidos.append(bandido)


## El escolta llego al destino: completa la mision.
func _on_arrived() -> void:
	if _terminado:
		return
	_system.register_progress(1)


## El escolta cayo: la mision falla.
func _on_escort_died(_source_position: Vector3) -> void:
	if _terminado:
		return
	_terminado = true
	_system.fail_mission()
	finish()


## Un emboscador cayo: nada especial.
func _on_ambusher_died(_source_position: Vector3) -> void:
	pass


## Si el jugador cae, la mision falla.
func _conectar_muerte(objetivo: Node3D) -> void:
	if objetivo == null:
		return
	var combatiente: Variant = objetivo.get("combatant")
	if combatiente != null and (combatiente as Node).has_signal("died"):
		(combatiente as Node).connect("died", Callable(self, "_on_player_died"))


func _on_player_died(_source_position: Vector3) -> void:
	if _terminado:
		return
	_terminado = true
	_system.fail_mission()
	finish()


## Cierre sin recompensa: libera al escolta y a los emboscadores vivos.
func finish() -> void:
	_terminado = true
	if _escort != null and is_instance_valid(_escort):
		_escort.queue_free()
	_escort = null
	for bandido in _bandidos:
		if is_instance_valid(bandido):
			bandido.queue_free()
	_bandidos.clear()
	_emboscadas.clear()


## Numero de emboscadas lanzadas (solo tests).
func ambush_count() -> int:
	return _emboscadas.size()


## El escolta (solo tests).
func escort() -> Node3D:
	return _escort
