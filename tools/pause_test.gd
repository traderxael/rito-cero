extends SceneTree

## Arnes del menu de pausa dura (Esc): congela el arbol salvo el propio menu, suelta
## el raton y alterna con ui_cancel.

const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")

const EXPECTED_CHECKS := 10

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_pause()
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


func _test_pause() -> void:
	var pause: CanvasLayer = PauseMenuScript.new()
	root.add_child(pause)
	await process_frame
	_check(pause.process_mode == Node.PROCESS_MODE_ALWAYS, "el menu sobrevive a la pausa")
	_check(not pause.call("is_open"), "empieza cerrado")
	_check(not pause.get("_root").visible, "el panel empieza oculto")

	pause.call("toggle")
	_check(paused, "toggle congela el arbol")
	_check(pause.call("is_open") and pause.get("_root").visible, "toggle abre el menu")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "la pausa suelta el raton")

	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	pause._unhandled_input(esc)
	_check(not paused and not pause.call("is_open"), "Esc cierra la pausa")
	pause._unhandled_input(esc)
	_check(paused, "Esc de nuevo vuelve a pausar")
	pause.call("toggle")
	_check(not paused, "toggle manual la cierra otra vez")
	_check(pause.has_signal("restart_requested"), "existe la senal de reinicio")
