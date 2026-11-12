class_name MenuCoordinator
extends Node

## Coordinador de los cuatro menus blandos (tablero, tecnologia, inventario y
## arsenal). Centraliza las teclas de apertura y el cierre por Esc para que los
## menus no se apilen: abrir uno cierra cualquier otro.
##
## La pausa dura no pasa por aqui: sigue escuchando Esc en su _unhandled_input.
## Por eso este nodo solo consume ui_cancel cuando habia un menu blando abierto;
## si no, el evento sigue su camino y la pausa lo recibe.

const ORDEN: Array[String] = ["mission_board", "tech_tree", "inventory", "arsenal_menu"]

## id de menu -> CanvasLayer con open()/close()/toggle()/is_open().
var _menus: Dictionary = {}
## Pausa dura (PROCESS_MODE_ALWAYS). Con ella abierta no se abren menus blandos.
var _pausa: Node


func _ready() -> void:
	# Recibe input con la pausa abierta: Esc debe poder cerrar un menu blando
	# aunque el arbol este congelado.
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(menus: Dictionary, pause: Node) -> void:
	_menus = {}
	for id in ORDEN:
		var menu: Node = menus.get(id) as Node
		if menu != null:
			_menus[id] = menu
	_pausa = pause


## Alterna el menu del id: si ya estaba abierto lo cierra, si no abre ese y
## cierra el que estuviera abierto. Con la pausa abierta no hace nada.
func handle_action(action: String) -> void:
	if not _menus.has(action) or _pausa_abierta():
		return
	var menu: Node = _menus[action]
	if bool(menu.call("is_open")):
		menu.call("close")
		return
	for id in _menus:
		if id != action:
			(_menus[id] as Node).call("close")
	menu.call("open")


## Cierra el menu blando abierto. Devuelve true si habia alguno (y el Esc debe
## consumirse); false si no habia nada que cerrar.
func close_top() -> bool:
	for id in ORDEN:
		if not _menus.has(id):
			continue
		var menu: Node = _menus[id]
		if bool(menu.call("is_open")):
			menu.call("close")
			return true
	return false


## Hay algun menu blando abierto.
func is_soft_open() -> bool:
	return not open_id().is_empty()


## Id del menu blando abierto, o "" si no hay ninguno.
func open_id() -> String:
	for id in ORDEN:
		if _menus.has(id) and bool((_menus[id] as Node).call("is_open")):
			return id
	return ""


func _pausa_abierta() -> bool:
	return _pausa != null and bool(_pausa.call("is_open"))


## Marca el evento como consumido. En el juego el viewport es la ventana; en un
## arnes headless colgado del SceneTree get_viewport() puede ser null, y hay que
## llegar a la ventana del arbol por SceneTree.root.
func _consumir() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
		return
	var tree := get_tree()
	if tree == null:
		return
	var ventana := tree.root as Window
	if ventana != null:
		ventana.set_input_as_handled()


func _input(event: InputEvent) -> void:
	for id in ORDEN:
		if event.is_action_pressed(id):
			handle_action(id)
			_consumir()
			return
	if event.is_action_pressed("ui_cancel") and close_top():
		_consumir()