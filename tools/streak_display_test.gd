extends SceneTree

## Arnes determinista de la racha visible: sin escena, sin GPU. Comprueba que el
## HUD muestra la racha actual y la mejor al recibir streak_changed, y que la
## pausa muestra el bloque de estadisticas (nivel, denarios, racha, mejor).

const HudScript := preload("res://scripts/ui/hud.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const MissionSystemScript := preload("res://scripts/missions/mission_system.gd")

const EXPECTED_CHECKS := 6

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_hud_muestra_la_racha()
	await _test_pausa_muestra_estadisticas()
	paused = false
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


func _make() -> Dictionary:
	var system: Node = MissionSystemScript.new()
	root.add_child(system)
	var hud: CanvasLayer = HudScript.new()
	root.add_child(hud)
	hud.call("bind_mission_system", system)
	var pausa: CanvasLayer = PauseMenuScript.new()
	root.add_child(pausa)
	pausa.call("setup", system)
	await process_frame
	return {"system": system, "hud": hud, "pausa": pausa}


func _test_hud_muestra_la_racha() -> void:
	var ctx := await _make()
	var hud: CanvasLayer = ctx["hud"]
	var system: Node = ctx["system"]
	_check(str(hud.call("streak_label_text")) == "Racha: 0 · Mejor: 0",
		"la etiqueta de racha nace en cero")
	system.emit_signal("streak_changed", 3, 7)
	_check(str(hud.call("streak_label_text")) == "Racha: 3 · Mejor: 7",
		"el HUD muestra la racha actual y la mejor")
	system.emit_signal("streak_changed", 0, 7)
	_check(str(hud.call("streak_label_text")) == "Racha: 0 · Mejor: 7",
		"al resetear la racha la etiqueta refleja el cero")


func _test_pausa_muestra_estadisticas() -> void:
	var ctx := await _make()
	var pausa: CanvasLayer = ctx["pausa"]
	var system: Node = ctx["system"]
	system.set("level", 2)
	system.set("coins", 123)
	system.set("current_streak", 3)
	system.set("best_streak", 7)
	pausa.call("toggle")
	var stats := str(pausa.call("stats_text"))
	_check(stats.contains("Nivel 2"), "la pausa muestra el nivel")
	_check(stats.contains("Denarios: 123"), "la pausa muestra los denarios")
	_check(stats.contains("Racha: 3") and stats.contains("Mejor: 7"),
		"la pausa muestra la racha y la mejor")
