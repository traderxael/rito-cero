extends SceneTree

## Arnes determinista de la variedad de enemigos: sin escena, sin GPU.
## Comprueba el chase_speed de instancia (base de hondero/bruto/corredor), la
## tabla de composicion por nivel y la fabrica de bandidos con mutadores.

const HOSTILE := preload("res://scripts/npc/hostile_npc.gd")
const BanditCampScript := preload("res://scripts/missions/bandit_camp.gd")

const EXPECTED_CHECKS := 8

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_chase_speed_instancia()
	_test_composition()
	await _test_spawn_bandit_kind_y_mutadores()
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


class StubData:
	extends RefCounted

	func get_height(position: Vector3) -> float:
		return position.y


func _target_at(pos: Vector3) -> Node3D:
	var target := Node3D.new()
	root.add_child(target)
	target.global_position = pos
	return target


func _test_chase_speed_instancia() -> void:
	await process_frame
	var target := _target_at(Vector3(10, 0, 0))
	var bandit: CharacterBody3D = HOSTILE.new()
	root.add_child(bandit)
	bandit.call("setup", StubData.new(), Vector3.ZERO, 0.0, target)
	_check(is_equal_approx(float(bandit.get("chase_speed")), 3.4), "chase_speed por defecto es 3,4")
	bandit.set("chase_speed", 4.6)
	bandit.call("_chase", Vector3(1, 0, 0), 1.0)
	_check(is_equal_approx(float(bandit.velocity.x), 4.6), "con chase_speed 4,6 persigue a 4,6")
	bandit.queue_free()


func _test_composition() -> void:
	var bajo: Array = BanditCampScript.composition(3, 4)
	_check(bajo.size() == 4 and bajo.count("bandit") == 4, "nivel 3: solo bandidos")
	var medio: Array = BanditCampScript.composition(6, 5)
	_check(medio.count("slinger") == 1 and medio.count("bandit") == 4, "nivel 6: 1 hondero y 4 bandidos")
	var alto: Array = BanditCampScript.composition(12, 8)
	_check(alto.count("slinger") == 2 and alto.count("brute") == 1 and alto.count("runner") == 1 and alto.count("bandit") == 4,
		"nivel 12: 2 honderos, 1 bruto, 1 corredor y 4 bandidos")


func _test_spawn_bandit_kind_y_mutadores() -> void:
	await process_frame
	var target := _target_at(Vector3(5, 0, 0))
	var generico: CharacterBody3D = BanditCampScript.spawn_bandit(root, Vector3.ZERO, 0.0, null, target, "bandit")
	_check(generico.get_script() == HOSTILE, "kind bandit crea un hostile_npc")
	generico.queue_free()
	var mutado: CharacterBody3D = BanditCampScript.spawn_bandit(root, Vector3.ZERO, 0.0, null, target, "bandit", null, {"health": 1.5})
	_check(is_equal_approx(float(mutado.get("max_health")), 90.0), "el mutador de vida deja max_health en 90")
	var combatiente: Node = mutado.get_node("Combatant")
	_check(is_equal_approx(float(combatiente.get("max_health")), 90.0), "el Combatant se re-setup con la vida multiplicada")
	mutado.queue_free()
