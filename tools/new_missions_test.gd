extends SceneTree

## Arnes determinista del progreso generalizado y las plantillas nuevas:
## escolta, recoleccion y contrarreloj, y el camino register_progress que
## sustituye a kills_done como contador de mision.

const MissionDataScript := preload("res://scripts/missions/mission_data.gd")
const MissionSystemScript := preload("res://scripts/missions/mission_system.gd")
const EscortSiteScript := preload("res://scripts/missions/escort_site.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const EXPECTED_CHECKS := 14

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_plantillas_nuevas()
	_test_progreso_generalizado()
	_test_escolta()
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


func _test_plantillas_nuevas() -> void:
	_check(MissionDataScript.make_instance("escort", 1).get("targets") == 1, "escolta: 1 objetivo")
	_check(MissionDataScript.make_instance("escort", 1).get("progress") == 0, "escolta: progreso empieza en 0")
	_check(not MissionDataScript.make_instance("escort", 1).has("kills_done"), "sin clave kills_done")
	_check(MissionDataScript.make_instance("collect", 1).get("targets") == 6, "recoleccion: 6 suministros")
	_check(MissionDataScript.make_instance("timed", 1).get("targets") == 4, "contrarreloj: 4 bandidos en nivel 1")
	_check(MissionDataScript.make_instance("timed", 1).get("time_limit") == 90, "contrarreloj: 90 segundos")
	_check(MissionDataScript.make_instance("timed", 9).get("targets") == 4, "contrarreloj no escala objetivos")
	_check(MissionDataScript.make_instance("bandit_purge", 3).get("targets") == 4, "purga escala 4 + nivel / 4")
	_check(MissionDataScript.make_instance("bandit_purge", 3).get("progress") == 0, "purga: progreso empieza en 0")


## Jugador de mentira para la escolta: cuerpo en la capa 2 (como Rito).
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


func _test_progreso_generalizado() -> void:
	var sistema := MissionSystemScript.new()
	root.add_child(sistema)
	var cuenta := {"n": 0}
	sistema.connect("mission_completed", func(_m: Dictionary, _r: Dictionary): cuenta["n"] += 1)
	sistema.call("start_mission", "bandit_purge")
	_check(cuenta["n"] == 0, "al arrancar la mision no se completa")
	sistema.call("register_progress", 2)
	_check(cuenta["n"] == 0, "register_progress avanza sin completar")
	sistema.call("register_progress", 2)
	_check(cuenta["n"] == 1, "al alcanzar los objetivos se completa una vez")
	sistema.call("complete_mission")
	_check(cuenta["n"] == 1, "complete_mission sin activa no paga dos veces")
	sistema.call("register_mission_kill")
	_check(cuenta["n"] == 1, "register_mission_kill sin activa no paga")
	sistema.queue_free()


func _test_escolta() -> void:
	await process_frame
	var sistema := MissionSystemScript.new()
	root.add_child(sistema)
	sistema.level = 1
	sistema.call("start_mission", "escort")
	var cuenta := {"failed": 0, "completed": 0}
	sistema.connect("mission_failed", func(_m: Dictionary): cuenta["failed"] += 1)
	sistema.connect("mission_completed", func(_m: Dictionary, _r: Dictionary): cuenta["completed"] += 1)
	var target := _make_player_stub(Vector3(0, 2, 0))
	var sitio := EscortSiteScript.begin(root, sistema, target, Vector3(0, 2, 0), Vector3(5, 2, 0), null)
	var escolta: Node3D = sitio.escort()
	_check(escolta != null, "se crea el escolta")
	_check(escolta.is_in_group("companions"), "el escolta va en el grupo companions")
	_check(int(escolta.get("_waypoint_index")) == 0, "el escolta empieza en el waypoint 0")
	# La muerte del escolta falla la mision
	var combate: Node = escolta.get_node_or_null("Combatant")
	combate.call("take_damage", 200.0, Vector3.ZERO)
	_check(cuenta["failed"] == 1, "la muerte del escolta falla la mision")
	_check(cuenta["completed"] == 0, "no se paga si el escolta muere")
	sitio.finish(); sitio.queue_free()
	sistema.queue_free()
	target.queue_free()
	# Una segunda escolta que llega al destino completa la mision
	var sistema2 := MissionSystemScript.new()
	root.add_child(sistema2)
	sistema2.level = 1
	sistema2.call("start_mission", "escort")
	sistema2.connect("mission_completed", func(_m: Dictionary, _r: Dictionary): cuenta["completed"] += 1)
	var target2 := _make_player_stub(Vector3(0, 2, 0))
	var sitio2 := EscortSiteScript.begin(root, sistema2, target2, Vector3(0, 2, 0), Vector3(5, 2, 0), null)
	sistema2.call("register_progress", 1)
	_check(cuenta["completed"] == 1, "llegar al destino completa la mision")
	sitio2.finish(); sitio2.queue_free()
	sistema2.queue_free()
	target2.queue_free()
