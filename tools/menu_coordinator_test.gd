extends SceneTree

## Arnes determinista del coordinador de menus blandos: sin escena, sin GPU.
## Comprueba que las cuatro teclas abren, cierran y cambian de menu sin que dos
## queden abiertos a la vez, y que Esc cierra el menu blando abierto y lo consume
## solo cuando lo habia (asi la pausa lo recibe en su _unhandled_input).

const MenuCoordinatorScript := preload("res://scripts/ui/menu_coordinator.gd")

const EXPECTED_CHECKS := 15

var _failures := 0
var _checks_run := 0

## Menu de mentira: solo el contrato que el coordinador necesita.
class MenuStub extends Node:
	var abierta := false
	func is_open() -> bool: return abierta
	func open() -> void: abierta = true
	func close() -> void: abierta = false
	func toggle() -> void: abierta = not abierta

## Pausa de mentira: el coordinador solo le pide is_open.
class PauseStub extends Node:
	var abierta := false
	func is_open() -> bool: return abierta


func _init() -> void:
	await _test_abre_y_cambia_de_menu()
	_test_close_top()
	_test_pausa_bloquea()
	await _test_esc()
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


## Un coordinador nuevo con los cuatro menus stub y la pausa stub. Se espera un
## frame: recien colgado del arbol su get_viewport() todavia es null.
func _make() -> Dictionary:
	var coordinator: Node = MenuCoordinatorScript.new()
	root.add_child(coordinator)
	var stubs := {
		"mission_board": MenuStub.new(),
		"tech_tree": MenuStub.new(),
		"inventory": MenuStub.new(),
		"arsenal_menu": MenuStub.new(),
	}
	for stub in stubs.values():
		root.add_child(stub)
	var pausa := PauseStub.new()
	root.add_child(pausa)
	coordinator.call("setup", stubs, pausa)
	return {"coordinator": coordinator, "stubs": stubs, "pausa": pausa}


func _esc() -> InputEventAction:
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	return esc


func _test_abre_y_cambia_de_menu() -> void:
	var ctx := _make()
	var coordinator: Node = ctx["coordinator"]
	var stubs: Dictionary = ctx["stubs"]
	coordinator.call("handle_action", "mission_board")
	_check((stubs["mission_board"] as MenuStub).abierta, "la tecla del tablero lo abre")
	_check(str(coordinator.call("open_id")) == "mission_board", "open_id es mission_board")
	_check(bool(coordinator.call("is_soft_open")), "is_soft_open es true con un menu abierto")

	coordinator.call("handle_action", "tech_tree")
	_check(not (stubs["mission_board"] as MenuStub).abierta, "tecnologia cierra el tablero")
	_check((stubs["tech_tree"] as MenuStub).abierta, "tecnologia se abre")

	coordinator.call("handle_action", "tech_tree")
	_check(not (stubs["tech_tree"] as MenuStub).abierta, "la misma tecla cierra el menu abierto")
	_check(str(coordinator.call("open_id")) == "", "sin menus abiertos open_id es vacio")
	_check(not bool(coordinator.call("is_soft_open")), "is_soft_open es false sin menus")


func _test_close_top() -> void:
	var ctx := _make()
	var coordinator: Node = ctx["coordinator"]
	var stubs: Dictionary = ctx["stubs"]
	_check(not bool(coordinator.call("close_top")), "close_top sin nada abierto es false")
	coordinator.call("handle_action", "inventory")
	_check(bool(coordinator.call("close_top")), "close_top con un menu abierto es true")
	_check(not (stubs["inventory"] as MenuStub).abierta, "close_top cierra el menu abierto")


func _test_pausa_bloquea() -> void:
	var ctx := _make()
	var coordinator: Node = ctx["coordinator"]
	var stubs: Dictionary = ctx["stubs"]
	var pausa: PauseStub = ctx["pausa"]
	pausa.abierta = true
	coordinator.call("handle_action", "mission_board")
	_check(not (stubs["mission_board"] as MenuStub).abierta, "con la pausa abierta las teclas no abren menus")


## Esc con un menu blando abierto: el coordinador lo cierra y consume el evento
## (marca el flag del viewport). Sin nada abierto no lo consume y lo deja pasar
## a la pausa, que lo abre en su _unhandled_input.
func _test_esc() -> void:
	var ctx := _make()
	var coordinator: Node = ctx["coordinator"]
	var stubs: Dictionary = ctx["stubs"]
	var pausa: PauseStub = ctx["pausa"]
	await process_frame
	coordinator.call("handle_action", "arsenal_menu")
	coordinator._input(_esc())
	_check(not (stubs["arsenal_menu"] as MenuStub).abierta, "Esc cierra el menu blando abierto")
	_check(not pausa.abierta, "sin menu blando el coordinador no consume Esc")
	pausa.abierta = true
	_check(pausa.is_open(), "la pausa puede abrirse con el Esc que dejo pasar el coordinador")