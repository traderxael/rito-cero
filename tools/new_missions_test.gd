extends SceneTree

## Arnes determinista del progreso generalizado y las plantillas nuevas:
## escolta, recoleccion y contrarreloj, y el camino register_progress que
## sustituye a kills_done como contador de mision.

const MissionDataScript := preload("res://scripts/missions/mission_data.gd")
const MissionSystemScript := preload("res://scripts/missions/mission_system.gd")

const EXPECTED_CHECKS := 15

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_plantillas_nuevas()
	_test_progreso_generalizado()
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


## Sistema con una mision activa (bandit_purge, nivel 1, 4 objetivos).
func _make_system() -> Dictionary:
	var system: Node = MissionSystemScript.new()
	root.add_child(system)
	var progresiones: Array = []
	var completados := 0
	system.connect("mission_progress", func(c: int, g: int):
		progresiones.append([c, g]))
	system.connect("mission_completed", func(_m: Dictionary, _r: Dictionary): completados += 1)
	return {"system": system, "progressed": progresiones, "completed_ref": completados}


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


func _test_progreso_generalizado() -> void:
	var ctx := _make_system()
	var system: Node = ctx["system"]
	var progresiones: Array = ctx["progressed"]
	var cuenta := {"n": 0}
	system.connect("mission_completed", func(_m: Dictionary, _r: Dictionary): cuenta["n"] += 1)
	system.call("start_mission", "bandit_purge")
	_check(cuenta["n"] == 0, "al arrancar la mision no se completa")
	system.call("register_progress", 2)
	_check(progresiones.size() == 1 and progresiones[0][0] == 2 and progresiones[0][1] == 4,
		"register_progress avisa progreso 2/4")
	system.call("register_progress", 2)
	_check(progresiones.size() == 2, "mission_progress se emite por cada avance")
	_check(cuenta["n"] == 1, "al alcanzar los objetivos se completa una vez")
	system.call("complete_mission")
	_check(cuenta["n"] == 1, "complete_mission sin activa no paga dos veces")
	system.call("register_mission_kill")
	_check(cuenta["n"] == 1, "register_mission_kill sin activa no paga")
