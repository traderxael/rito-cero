extends SceneTree

## Arnes de la progresion (Fase 2): objetivo de 6 bajas, denarios, consumibles con E y
## curacion parcial. Sin escena ni terreno; el kill-sync usa el RitoCombat real.

const MissionTrackerScript := preload("res://scripts/missions/mission_tracker.gd")
const ProgressionScript := preload("res://scripts/missions/progression.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")
const RitoScript := preload("res://scripts/player/rito.gd")
const RitoCombatScript := preload("res://scripts/player/rito_combat.gd")

const EXPECTED_CHECKS := 33
const SAVE_PATH := "user://ritocero_save_v1.json"

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_borrar_guardado()
	_test_tracker()
	_test_heal()
	_test_progression_loot()
	await _test_kill_sync()
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


func _test_tracker() -> void:
	var tracker: MissionTracker = MissionTrackerScript.new()
	var counters := {"progress": 0, "completed": 0, "last_kills": -1, "last_goal": -1}
	tracker.progress_changed.connect(func(k, g):
		counters["progress"] += 1
		counters["last_kills"] = k
		counters["last_goal"] = g)
	tracker.completed.connect(func():
		counters["completed"] += 1)
	_check(tracker.kills == 0 and not tracker.is_completed(), "tracker nuevo: 0 bajas y sin completar")
	_check(tracker.goal == 6, "el objetivo son 6 bajas")
	for i in 5:
		tracker.add_kill()
	_check(tracker.kills == 5 and not tracker.is_completed(), "a las 5 bajas aun no se completa")
	_check(counters["progress"] == 5 and counters["last_kills"] == 5 and counters["last_goal"] == 6,
		"progress_changed avisa 5/6")
	tracker.add_kill()
	_check(tracker.is_completed(), "la 6a baja completa la mision")
	_check(counters["completed"] == 1, "completed se emite una vez")
	_check(tracker.label() == "Bajas: 6/6", "el label muestra 6/6")
	tracker.add_kill()
	_check(counters["completed"] == 1 and tracker.kills == 6, "la 7a baja no reemite completed")
	tracker.reset()
	_check(tracker.kills == 0 and not tracker.is_completed(), "reset vuelve a 0 sin completar")
	_check(counters["last_kills"] == 0 and counters["progress"] == 7, "reset emite progress 0/6")


func _test_heal() -> void:
	var c: Combatant = CombatantScript.new()
	c.setup(100.0)
	c.heal(30.0)
	_check(c.health == 100.0, "curar por encima del max queda en el max")
	c.take_damage(50.0, Vector3.ZERO)
	_check(c.health == 50.0, "take_damage deja 50 de vida")
	c.heal(20.0)
	_check(c.health == 70.0, "heal suma 20 y queda en 70")
	c.heal(999.0)
	_check(c.health == 100.0, "heal grande se limita al max")
	c.take_damage(999.0, Vector3.ZERO)
	_check(not c.is_alive(), "vida a 0 muere")
	c.heal(50.0)
	_check(not c.is_alive() and c.health == 0.0, "heal no revive")
	c.heal(-5.0)
	_check(c.health == 0.0, "heal negativo no hace nada")


func _test_progression_loot() -> void:
	var prog: Node = ProgressionScript.new()
	root.add_child(prog)
	var counters := {"coins_sig": 0, "inv_sig": 0, "healed": 0, "healed_amount": 0.0}
	prog.connect("coins_changed", func(_c):
		counters["coins_sig"] += 1)
	prog.connect("inventory_changed", func():
		counters["inv_sig"] += 1)
	prog.connect("healed", func(a):
		counters["healed"] += 1
		counters["healed_amount"] = a)
	prog.call("setup", null, {"coins": 45, "inventory": {"panis": 2}})
	_check(int(prog.get("coins")) == 45, "setup carga 45 denarios del guardado")
	_check(int(prog.call("panis_count")) == 2, "setup carga 2 panis del guardado")
	_check(counters["coins_sig"] >= 1 and counters["inv_sig"] >= 1, "setup emite coins e inventario")
	prog.call("apply_loot", {"denarii": 15})
	_check(int(prog.get("coins")) == 60, "apply_loot suma 15 denarios")
	prog.call("apply_loot", {"panis": 1})
	_check(int(prog.call("panis_count")) == 3, "apply_loot suma 1 panis")
	_check(counters["coins_sig"] >= 2 and counters["inv_sig"] >= 2, "apply_loot emite sus senales")
	var healed := float(prog.call("use_potion"))
	_check(is_equal_approx(healed, 35.0), "comer panis cura 35")
	_check(int(prog.call("panis_count")) == 2, "comer gasta un panis")
	_check(counters["healed"] == 1 and is_equal_approx(float(counters["healed_amount"]), 35.0),
		"healed emite 35")
	healed = float(prog.call("use_potion"))
	_check(is_equal_approx(healed, 35.0) and int(prog.call("panis_count")) == 1,
		"el segundo panis tambien cura y gasta")
	healed = float(prog.call("use_potion"))
	_check(is_equal_approx(healed, 35.0) and int(prog.call("panis_count")) == 0,
		"el tercer panis cierra el inventario")
	healed = float(prog.call("use_potion"))
	_check(is_equal_approx(healed, 0.0) and counters["healed"] == 3,
		"sin consumibles no cura ni emite")


func _test_kill_sync() -> void:
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

	var prog: Node = ProgressionScript.new()
	root.add_child(prog)
	var counters := {"completed": 0, "last_kills": -1}
	prog.connect("mission_completed", func():
		counters["completed"] += 1)
	prog.connect("mission_changed", func(k, _g):
		counters["last_kills"] = k)
	prog.call("setup", attack, {})
	for i in 6:
		attack.call("add_kill")
	var tracker = prog.get("tracker")
	_check(int(tracker.get("kills")) == 6 and bool(tracker.call("is_completed")),
		"6 bajas del combat completan la mision")
	_check(counters["completed"] == 1, "mission_completed se emite una vez")
	_check(counters["last_kills"] == 6, "mission_changed llega a 6")
	attack.call("add_kill")
	_check(counters["completed"] == 1 and int(tracker.get("kills")) == 6,
		"la 7a baja no rompe nada")
