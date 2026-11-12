extends SceneTree

## Arnes determinista de la horda del coliseo: prueba logica de oleadas,
## racha por oleada y fin de horda sobre MissionSystem.

const MissionSystemScript := preload("res://scripts/missions/mission_system.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const EXPECTED_CHECKS := 0

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_oleadas_escalan()
	_test_muerte_termina_horda()
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


## La cuenta de oleadas avanza y la racha suma por oleada.
func _test_oleadas_escalan() -> void:
	await process_frame
	var sistema: Node = _make_sistema()
	sistema.set("level", 1)
	var objetivo := Node3D.new()
	root.add_child(objetivo)
	var combatant: Node = CombatantScript.new()
	combatant.name = "Combatant"
	objetivo.add_child(combatant)
	combatant.call("setup", 100.0)

	sistema.call("start_horde")
	_check(sistema.get("horde_active"), "horda activa al iniciar")

	sistema.call("horde_wave_cleared", 1)
	_check(sistema.call("get_streak") == 1, "racha = 1 tras oleada 1")
	_check(sistema.call("get_best_streak") == 1, "mejor racha = 1 tras oleada 1")

	sistema.call("horde_wave_cleared", 2)
	_check(sistema.call("get_streak") == 2, "racha = 2 tras oleada 2")
	_check(sistema.call("get_best_streak") == 2, "mejor racha = 2 tras oleada 2")

	sistema.queue_free()
	objetivo.queue_free()


## La muerte del jugador termina la horda.
func _test_muerte_termina_horda() -> void:
	await process_frame
	var sistema: Node = _make_sistema()
	sistema.set("level", 1)
	var objetivo := Node3D.new()
	root.add_child(objetivo)
	var combatant: Node = CombatantScript.new()
	combatant.name = "Combatant"
	objetivo.add_child(combatant)
	combatant.call("setup", 100.0)

	sistema.call("start_horde")
	_check(sistema.get("horde_active"), "horda activa al iniciar")

	sistema.call("horde_wave_cleared", 1)
	_check(sistema.call("get_streak") == 1, "racha = 1 tras oleada 1")

	combatant.call("take_damage", 200.0, Vector3.ZERO)
	await process_frame
	_check(not sistema.get("horde_active"), "horda terminada tras muerte del jugador")

	objetivo.queue_free()
	sistema.queue_free()


