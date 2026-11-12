extends SceneTree

## Arnes determinista de contratos escalables: sin escena, sin GPU.
## Comprueba que las plantillas de contrato tienen min_level, mutadores y
## recompensa x1.5, y que los mutators se aplican al spawnear enemigos.

const MissionDataScript := preload("res://scripts/missions/mission_data.gd")
const BanditCampScript := preload("res://scripts/missions/bandit_camp.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const EXPECTED_CHECKS := 10

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_plantillas_contrato()
	_test_recompensa_por_contrato()
	_test_mutators_en_spawn()
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


func _test_plantillas_contrato() -> void:
	var p: Dictionary = MissionDataScript.make_instance("bandit_purge_contract", 10)
	_check(p.get("min_level") == 10, "contrato purga: nivel minimo 10")
	_check(p.has("mutators"), "contrato purga: trae mutators")
	_check(p.get("reward_mult") == 1.5, "contrato purga: recompensa x1.5")
	var d: Dictionary = MissionDataScript.make_instance("city_defense_contract", 10)
	_check(d.get("min_level") == 10, "contrato defensa: nivel minimo 10")
	_check(d.get("reward_mult") == 1.5, "contrato defensa: recompensa x1.5")


func _test_recompensa_por_contrato() -> void:
	var p: Dictionary = MissionDataScript.make_instance("bandit_purge_contract", 10)
	_check(p.get("xp") > 60, "contrato purga: xp aumentó por nivel y multiplicador")
	var coins: Array = p.get("coins")
	_check(coins.size() == 2 and coins[0] > 30 and coins[1] > 60, "contrato purga: monedas aumentaron por nivel y multiplicador")


func _test_mutators_en_spawn() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var mutators: Dictionary = {"health": 1.5, "damage": 1.25, "speed": 1.15}
	var b := BanditCampScript.spawn_bandit(root, Vector3.ZERO, 0.0, null, target, "bandit", null, mutators)
	_check(b.get("max_health") == 90.0, "mutador health: vida 90 (60 x 1.5)")
	_check(b.get("attack_damage") == 15.0, "mutador damage: dano 15 (12 x 1.25)")
	_check(abs(b.get("chase_speed") - 3.91) < 0.01, "mutador speed: velocidad 3.91 (3.4 x 1.15)")
	b.queue_free()
	target.queue_free()
