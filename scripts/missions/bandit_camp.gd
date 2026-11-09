class_name BanditCamp
extends Node3D

## Campamento de bandidos para la purga: crea N bandidos en anillo alrededor de un
## punto, cada baja suma a la mision activa y al caer el ultimo se paga y se libera.
## Los bandidos son hostile_npc reales (patrulladores con aggro del valley), solo
## que con tinte rojizo y grupo propio para distinguirlos del ambiente.

const HOSTILE_SCRIPT := preload("res://scripts/npc/hostile_npc.gd")

## Radio del anillo en metros y tinte rojizo HDR de los bandidos de mision.
const RING_RADIUS := 12.0
const BANDIT_TINT := Color(1.35, 0.55, 0.45)


## Dato de terreno plano: sin Terrain3D (tests headless) los waypoints del NPC
## patrullan a la altura del centro del campamento.
class FlatData:
	extends RefCounted

	func get_height(position: Vector3) -> float:
		return position.y


var _bandits: Array[Node3D] = []
var _remaining := 0
var _system: MissionSystem
var _finished := false
var _objetivo: Node3D


## Levanta el campamento de `count` bandidos alrededor de `center` con Y del terreno
## real (o del centro si no hay terreno). Cada muerte avisa al sistema de mision.
## El objetivo trae el Combatant de Rito para fallar la mision si el jugador cae
## a mitad de purga (igual que DefenseSite).
static func spawn(parent: Node, center: Vector3, count: int, terrain: Variant,
		system: MissionSystem, target: Node3D) -> Node3D:
	var camp := BanditCamp.new()
	camp.name = "BanditCamp"
	parent.add_child(camp)
	camp._system = system
	camp._objetivo = target
	camp._remaining = count
	camp._conectar_muerte(target)
	if count <= 0:
		return camp
	var data: Variant = terrain.get_data() if terrain != null else null
	for i in count:
		var angle := TAU * float(i) / float(count)
		var position := center + Vector3(cos(angle), 0.0, sin(angle)) * RING_RADIUS
		if data != null:
			var height: float = data.get_height(Vector3(position.x, 0.0, position.z))
			position.y = center.y if is_nan(height) else height
		var bandit := spawn_bandit(camp, position, angle, terrain, target)
		(bandit.get_node("Combatant") as Combatant).died.connect(Callable(camp, "_on_bandit_died"))
		camp._bandits.append(bandit)
	return camp


## Un bandido de mision: NPC hostil con el grupo mission_bandits y el tinte rojizo.
## Lo reusa el evento de mundo (Task 8): misma marca, otro escenario.
static func spawn_bandit(parent: Node, position: Vector3, angle: float, terrain: Variant,
		target: Node3D) -> Node3D:
	var data: Variant = FlatData.new()
	if terrain != null:
		data = terrain.get_data()
		if data == null:
			data = FlatData.new()
	var bandit: CharacterBody3D = HOSTILE_SCRIPT.new()
	bandit.name = "Bandit"
	parent.add_child(bandit)
	bandit.call("setup", data, position, angle, target)
	bandit.add_to_group("mission_bandits")
	bandit.call("set_tint", BANDIT_TINT)
	return bandit


## Cierre sin recompensa (fallo, abandono o desmontaje): libera a los vivos y los
## cadaveres pendientes. Las bajas posteriores ya no suman, el guardado no paga.
func finish() -> void:
	_finished = true
	for bandido in _bandits:
		if is_instance_valid(bandido):
			bandido.queue_free()
	_bandits.clear()


## Cada baja suma a la mision; al caer el ultimo paga la mision y libera el campamento.
func _on_bandit_died(_source_position: Vector3) -> void:
	if _finished or _system == null or not is_instance_valid(_system):
		return
	_remaining -= 1
	_system.register_mission_kill()
	if _remaining <= 0:
		_system.complete_mission()
		queue_free()


## Si el jugador cae a mitad de purga, la mision falla y el campamento se libera:
## el Combatant de Rito (accesible por el objetivo) emite died y aqui se puentea a
## fail_mission, igual que en DefenseSite. Si el objetivo no trae Combatant, el
## cableado de main cierra el sitio al fallar/abandonar/completar la mision.
func _conectar_muerte(objetivo: Node3D) -> void:
	if objetivo == null:
		return
	var combatiente: Variant = objetivo.get("combatant")
	if combatiente != null and (combatiente as Node).has_signal("died"):
		(combatiente as Node).connect("died", Callable(self, "_on_player_died"))


func _on_player_died(_source_position: Vector3) -> void:
	if _finished:
		return
	_finished = true
	if _system != null and is_instance_valid(_system):
		_system.fail_mission()
	queue_free()
