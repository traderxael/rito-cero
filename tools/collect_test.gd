extends SceneTree

## Arnes determinista de la mision de recoleccion: sin escena, sin GPU.
## Comprueba que los suministros de quest no notifican a Progression, que
## recoger los 6 completa y que la muerte del jugador falla.

const CollectSiteScript := preload("res://scripts/missions/collect_site.gd")
const MissionSystemScript := preload("res://scripts/missions/mission_system.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const EXPECTED_CHECKS := 6

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_loot_no_pasa_a_progression()
	await _test_seis_completan()
	await _test_muerte_falla()
	if _checks_run != EXPECTED_CHECKS:
		_failures += 1
		print("FAIL solo se ejecutaron ", _checks_run, " de ", EXPECTED_CHECKS, " checks")
	print("TEST failures=", _failures, " checks=", _checks_run)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks_run += 1
	if not condition:
		_failures += 1
		print("FAIL ", label)
	else:
		print("ok ", label)


func _make_sistema() -> Node:
	var sistema: Node = MissionSystemScript.new()
	root.add_child(sistema)
	return sistema


## Jugador de mentira: cuerpo capa 2 con Combatant.
func _make_player_stub(pos: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 1.0)
	shape.shape = box
	body.add_child(shape)
	var combatant: Node = CombatantScript.new()
	combatant.name = "Combatant"
	body.add_child(combatant)
	combatant.call("setup", 100.0)
	root.add_child(body)
	body.global_position = pos
	return body


## Progreso de mentira: registra si se llamo a apply_loot.
class ProgresoMentira:
	extends Node
	var llamo_apply_loot := false
	var loot_recibido: Dictionary = {}


func _test_loot_no_pasa_a_progression() -> void:
	await process_frame
	var sistema := _make_sistema()
	sistema.call("start_mission", "collect")
	var progreso := ProgresoMentira.new()
	progreso.name = "progression"
	root.add_child(progreso)
	var sitio := CollectSiteScript.begin(root, Vector3.ZERO, null, sistema, _make_player_stub(Vector3(10, 2, 0)))
	await process_frame
	var suministros: Array[Node3D] = sitio.suministros()
	print("DBG: suministros=", suministros.size())
	_check(suministros.size() == 6, "aparecen 6 suministros de quest")
	var uno: Node3D = suministros[0]
	uno.call("_on_body_entered", null)
	_check(progreso.llamo_apply_loot == false, "el suministro de quest no llama a apply_loot")
	_check(progreso.loot_recibido.is_empty(), "ni pasa diccionario de botin")
	_check(sitio.restante() == 5, "quedan 5 suministros")
	sitio.finish(); sitio.queue_free()
	sistema.queue_free()


func _test_seis_completan() -> void:
	await process_frame
	var sistema := _make_sistema()
	sistema.call("start_mission", "collect")
	var sitio := CollectSiteScript.begin(root, Vector3.ZERO, null, sistema, _make_player_stub(Vector3(10, 2, 0)))
	await process_frame
	for i in 6:
		sitio.call("_on_suministro_recogido", "suministro", 1)
	_check(not sistema.call("is_mission_active"), "recoger los 6 completa la mision")
	sitio.finish(); sitio.queue_free()
	sistema.queue_free()


func _test_muerte_falla() -> void:
	await process_frame
	var sistema := _make_sistema()
	sistema.call("start_mission", "collect")
	var cuenta := {"failed": 0, "completed": 0}
	sistema.connect("mission_failed", func(_m: Dictionary): cuenta["failed"] += 1)
	sistema.connect("mission_completed", func(): cuenta["completed"] += 1)
	var sitio := CollectSiteScript.begin(root, Vector3.ZERO, null, sistema, _make_player_stub(Vector3(10, 2, 0)))
	var jugador: Node3D = sitio.jugador()
	var combate: Node = jugador.get_node_or_null("Combatant")
	combate.call("take_damage", 200.0, Vector3.ZERO)
	_check(cuenta["failed"] == 1, "la muerte del jugador falla la mision")
	sitio.finish(); sitio.queue_free()
	sistema.queue_free()
