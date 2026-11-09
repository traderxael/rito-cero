extends SceneTree

## Arnes del jefe de la cueva: mas vida y dano que un bandido, no suma a las bajas de
## bandidos, y al caer entrega recompensa y cierra el objetivo del Praetorian.

const BossNpcScript := preload("res://scripts/npc/boss_npc.gd")
const HostileNpcScript := preload("res://scripts/npc/hostile_npc.gd")
const ProgressionScript := preload("res://scripts/missions/progression.gd")
const RitoScript := preload("res://scripts/player/rito.gd")
const RitoCombatScript := preload("res://scripts/player/rito_combat.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const EXPECTED_CHECKS := 15
const SAVE_PATH := "user://ritocero_save_v1.json"

## Terreno falso: el NPC solo lo usa para sortear waypoints, y aqui no hay superficie.
class FakeData:
	extends RefCounted
	func get_height(_position: Vector3) -> float:
		return 0.0

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_borrar_guardado()
	_test_stats()
	await _test_boss_defeat()
	_borrar_guardado()
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


func _borrar_guardado() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _test_stats() -> void:
	var data := FakeData.new()
	var bandido: CharacterBody3D = HostileNpcScript.new()
	root.add_child(bandido)
	bandido.call("setup", data, Vector3(0, 0, 0), 0.0, null)
	await process_frame
	_check(is_equal_approx(float(bandido.get("max_health")), 60.0), "un bandido tiene 60 de vida")
	_check(is_equal_approx(float(bandido.get("attack_damage")), 12.0), "un bandido pega 12")
	_check(bool(bandido.get("counts_as_kill")), "un bandido cuenta como baja de bandidos")

	var boss: CharacterBody3D = BossNpcScript.new()
	root.add_child(boss)
	boss.call("setup_boss", data, Vector3(0, 0, 30), 0.0, null)
	await process_frame
	_check(is_equal_approx(float(boss.get("max_health")), 320.0), "el Praetorian tiene 320 de vida")
	_check(is_equal_approx(float(boss.get("attack_damage")), 28.0), "el Praetorian pega 28")
	_check(is_equal_approx(float(boss.get("body_scale")), 1.35), "el Praetorian es mas grande")
	_check(not bool(boss.get("counts_as_kill")),
		"el Praetorian no cuenta como baja de bandidos")
	_check(boss.has_signal("boss_defeated"), "el jefe avisa cuando cae")


func _test_boss_defeat() -> void:
	var data := FakeData.new()
	var prog: Node = ProgressionScript.new()
	root.add_child(prog)
	prog.call("setup", null, {})

	var boss: CharacterBody3D = BossNpcScript.new()
	root.add_child(boss)
	boss.call("setup_boss", data, Vector3(0, 0, 30), 0.0, null)
	await process_frame

	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	rito.add_child(combatant)
	await process_frame
	combatant.setup(100.0, 0.0)
	rito.bind_combatant(combatant, Vector3.ZERO)
	var attack: RitoCombat = RitoCombatScript.new()
	rito.add_child(attack)
	attack.setup(rito)

	var defeated := {"n": 0}
	boss.connect("boss_defeated", func():
		defeated["n"] += 1)

	var boss_combatant = boss.get_node("Combatant")
	boss_combatant.take_damage(9999.0, Vector3.ZERO)
	await process_frame
	_check(defeated["n"] == 1, "el jefe emite boss_defeated al morir")
	_check(int(prog.get("coins")) == 150, "vencer al jefe da 150 denarios")
	_check(int(prog.call("panis_count")) == 2, "vencer al jefe da 2 panis")

	var tracker = prog.get("boss_tracker")
	_check(tracker != null and bool(tracker.call("is_completed")),
		"el objetivo del Praetorian queda completado")
	_check(int(prog.call("boss_progress")) == 1, "el progreso del jefe es 1/1")

	# El tajo del jugador contra el jefe no debe sumar baja de bandido.
	var before := int(attack.get("kills"))
	attack.call("_on_landed", boss, 34.0)
	_check(int(attack.get("kills")) == before,
		"matar al jefe no suma una baja de bandidos")

	# Un bandido normal si cuenta.
	var bandido: CharacterBody3D = HostileNpcScript.new()
	root.add_child(bandido)
	bandido.call("setup", data, Vector3(0, 0, 12), 0.0, null)
	await process_frame
	bandido.get_node("Combatant").take_damage(9999.0, Vector3.ZERO)
	attack.call("_on_landed", bandido, 34.0)
	_check(int(attack.get("kills")) == before + 1, "matar a un bandido si suma baja")
