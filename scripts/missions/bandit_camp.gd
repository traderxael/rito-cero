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
## kind elige el tipo (bandit, slinger, brute, runner); player es la referencia
## para el cambio de objetivo de las emboscadas; mutators aplica los
## multiplicadores de los contratos (vida, dano, velocidad).
static func spawn_bandit(parent: Node, position: Vector3, angle: float, terrain: Variant,
		target: Node3D, kind := "bandit", player: Node3D = null, mutators: Dictionary = {}) -> Node3D:
	var data: Variant = FlatData.new()
	if terrain != null:
		data = terrain.get_data()
		if data == null:
			data = FlatData.new()
	var script := _script_for(kind)
	var efectivo := kind
	if script == HOSTILE_SCRIPT and kind != "bandit":
		efectivo = "bandit"
	var bandit: CharacterBody3D = script.new()
	bandit.name = "Bandit"
	parent.add_child(bandit)
	if efectivo == "bandit":
		bandit.call("setup", data, position, angle, target, player)
	else:
		bandit.call("setup_" + efectivo, data, position, angle, target, player)
	if not mutators.is_empty():
		var vida := float(mutators.get("health", 1.0))
		var dano := float(mutators.get("damage", 1.0))
		var veloz := float(mutators.get("speed", 1.0))
		bandit.set("max_health", float(bandit.get("max_health")) * vida)
		bandit.set("attack_damage", float(bandit.get("attack_damage")) * dano)
		bandit.set("chase_speed", float(bandit.get("chase_speed")) * veloz)
		var combatiente: Node = bandit.get_node_or_null("Combatant")
		if combatiente != null:
			combatiente.call("setup", float(bandit.get("max_health")))
	bandit.add_to_group("mission_bandits")
	bandit.call("set_tint", BANDIT_TINT)
	return bandit


## Script de cada tipo de bandido. Si el archivo aun no existe (los tipos nuevos
## llegan en tasks siguientes), avisa y cae al bandido base.
static func _script_for(kind: String) -> Script:
	const PATHS := {
		"bandit": "res://scripts/npc/hostile_npc.gd",
		"slinger": "res://scripts/npc/slinger_npc.gd",
		"brute": "res://scripts/npc/brute_npc.gd",
		"runner": "res://scripts/npc/runner_npc.gd",
	}
	var ruta := str(PATHS.get(kind, ""))
	if ruta.is_empty() or not ResourceLoader.exists(ruta):
		push_warning("spawn_bandit: tipo '%s' sin script, se usa bandido" % kind)
		return HOSTILE_SCRIPT
	return load(ruta) as Script


## Composicion determinista de una partida segun el nivel: honderos desde el 5;
## brutos y corredores desde el 10 ("1 de cada 6" y "1 de cada 5", sin suelo: con
## lotes pequenos no aparecen). Bandidos primero, y nunca menos de uno.
static func composition(level: int, total: int) -> Array[String]:
	var tipos: Array[String] = []
	var honderos := 0
	var brutos := 0
	var corredores := 0
	if level >= 5:
		honderos = maxi(1, total / 4)
	if level >= 10:
		brutos = total / 6
		corredores = total / 5
	var bandidos := maxi(1, total - honderos - brutos - corredores)
	for i in bandidos:
		tipos.append("bandit")
	for i in honderos:
		tipos.append("slinger")
	for i in brutos:
		tipos.append("brute")
	for i in corredores:
		tipos.append("runner")
	return tipos


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
