extends SceneTree

## Arnes determinista de los cooldowns persistentes: sin escena, sin GPU.
## Comprueba que el cooldown sobrevive a la recarga (tiempo unix), que los
## expirados se descartan y que un save viejo o corrupto no deja cooldowns
## fantasma.

const MissionSystemScript := preload("res://scripts/missions/mission_system.gd")

const EXPECTED_CHECKS := 9

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_cooldown_basico()
	_test_available_con_cooldown()
	_test_salvado_y_recargado()
	_test_expirado_y_basura()
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


func _make() -> Node:
	var system: Node = MissionSystemScript.new()
	root.add_child(system)
	return system


func _in_cooldown(system: Node, id: String) -> bool:
	return bool(system.call("_in_cooldown", id))


func _unix() -> float:
	return float(Time.get_unix_time_from_system())


func _test_cooldown_basico() -> void:
	var system := _make()
	_check(not _in_cooldown(system, "bandit_purge"), "un sistema nuevo no tiene cooldowns")
	system.set("_cooldowns", {"bandit_purge": _unix() + 50.0})
	_check(_in_cooldown(system, "bandit_purge"), "con timestamp futuro el id esta en cooldown")


func _test_available_con_cooldown() -> void:
	var system := _make()
	system.set("_cooldowns", {"bandit_purge": _unix() + 50.0})
	var ids: Array = []
	for mision in system.call("available_missions"):
		ids.append(str(mision.get("id", "")))
	_check(not ids.has("bandit_purge"), "la purga en cooldown no sale en el tablero")
	_check(ids.has("city_defense"), "la defensa sigue disponible con la purga en cooldown")


func _test_salvado_y_recargado() -> void:
	var system := _make()
	system.set("_cooldowns", {"bandit_purge": _unix() + 50.0})
	var guardado: Dictionary = system.call("current_save")
	_check(float(guardado.get("cooldowns", {}).get("bandit_purge", 0.0)) > _unix(),
		"el guardado trae el cooldown en el futuro")
	var system2 := _make()
	system2.call("apply_save", guardado)
	_check(_in_cooldown(system2, "bandit_purge"), "tras recargar el cooldown sigue activo")


func _test_expirado_y_basura() -> void:
	var system := _make()
	system.call("apply_save", {"cooldowns": {"x": _unix() - 10.0}})
	_check(not _in_cooldown(system, "x"), "un cooldown expirado no bloquea")
	system.call("apply_save", {})
	_check(not _in_cooldown(system, "x"), "apply_save vacio limpia los cooldowns")
	var system2 := _make()
	system2.call("apply_save", {"cooldowns": "basura"})
	_check(not _in_cooldown(system2, "x"), "cooldowns de tipo erroneo degradan sin crash")
