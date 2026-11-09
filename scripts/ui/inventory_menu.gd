class_name InventoryMenu
extends CanvasLayer

## Inventario de la partida: los consumibles de MissionSystem con sus recuentos.
## Se abre con I y se cierra con I o Esc.
##
## El menu no guarda nada: solo lee MissionSystem (inventory/coins/has_tech) y
## consume con use_item o craftea con craft_sal. El estado se repinta con
## inventory_changed/coins_changed/tech_changed, asi que un cambio desde otro sitio
## tambien deja los botones correctos. El mundo no se detiene: es una pausa blanda
## como el tablero. Se suelta el raton para poder apuntar con el y el input de
## combate se ignora mientras el panel esta abierto.

const VIEW_WIDTH := 1280.0
const VIEW_HEIGHT := 720.0
const PANEL_WIDTH := 660.0
const PANEL_HEIGHT := 560.0
const PANEL_TOP := 60.0
const ROW_HEIGHT := 52.0
const ROW_GAP := 8.0
const BUTTON_WIDTH := 340.0

const ACCENT := Color(0.95, 0.88, 0.70)
const TEXT := Color(0.88, 0.84, 0.74)
const DIM := Color(0.68, 0.64, 0.56)
const PANEL_BG := Color(0.06, 0.05, 0.04, 0.93)
const ROW_BG := Color(0.14, 0.13, 0.11, 0.9)

## Items visibles del inventario: los consumibles y la sal del crafteo. Los
## denarios van en la etiqueta de monedas, no como fila.
const ITEMS: Array[String] = ["panis", "aqua", "pizza", "gelatum", "sal"]

const NAMES := {
	"panis": "Panis",
	"aqua": "Agua",
	"pizza": "Pizza",
	"gelatum": "Gelatum",
	"sal": "Sal",
}

var _sistema: MissionSystem
var _combate: Node
var _root: Control
var _rows_host: Control
var _coins_label: Label
var _craft_btn: Button
var _buttons: Dictionary = {}
var _open := false
var _mouse_was_captured := false


func setup(system: MissionSystem, combat: Node) -> void:
	_sistema = system
	_combate = combat
	layer = 6
	_build()
	if _sistema != null:
		_connect(_sistema, "inventory_changed", Callable(self, "_on_changed"))
		_connect(_sistema, "coins_changed", Callable(self, "_on_changed"))
		_connect(_sistema, "tech_changed", Callable(self, "_on_changed"))
	_refresh()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open or _root == null:
		return
	_open = true
	_mouse_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	if _combate != null:
		_combate.call("set_input_enabled", false)
	_refresh()
	_click()


func close() -> void:
	if not _open:
		return
	_open = false
	if _root != null:
		_root.visible = false
	if _combate != null:
		_combate.call("set_input_enabled", true)
	if _mouse_was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_click()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func refresh() -> void:
	_refresh()


## Boton Usar de un item concreto, o null si no se lista.
func button_for(item_id: String) -> Button:
	return _buttons.get(item_id) as Button


func craft_sal_button() -> Button:
	return _craft_btn


func coins_label_text() -> String:
	if _coins_label == null:
		return ""
	return _coins_label.text


func use_item(item_id: String) -> bool:
	if _sistema == null:
		return false
	var ok := bool(_sistema.call("use_item", item_id))
	_refresh()
	return ok


func craft() -> bool:
	if _sistema == null:
		return false
	var ok := bool(_sistema.call("craft_sal"))
	_refresh()
	return ok


func _click() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var sfx := tree.get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_local", "ui", -12.0)


func _connect(source: Object, signal_name: String, target: Callable) -> void:
	if source.has_signal(signal_name) and not source.is_connected(signal_name, target):
		source.connect(signal_name, target)


func _build() -> void:
	_root = Control.new()
	_root.size = Vector2(VIEW_WIDTH, VIEW_HEIGHT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = Vector2(VIEW_WIDTH, VIEW_HEIGHT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	_root.add_child(dim)

	var panel := Control.new()
	panel.position = Vector2((VIEW_WIDTH - PANEL_WIDTH) * 0.5, PANEL_TOP)
	panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	var background := ColorRect.new()
	background.color = PANEL_BG
	background.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(background)

	var border := ColorRect.new()
	border.color = Color(0.45, 0.34, 0.18, 0.9)
	border.size = Vector2(PANEL_WIDTH, 3)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(border)

	var title := _make_label("INVENTARIO", 26, ACCENT)
	title.position = Vector2(26, 18)
	panel.add_child(title)

	var hint := _make_label("I o Esc para cerrar", 14, DIM)
	hint.position = Vector2(26, 56)
	panel.add_child(hint)

	_coins_label = _make_label("Denarios: 0", 16, TEXT)
	_coins_label.position = Vector2(26, 84)
	panel.add_child(_coins_label)

	_rows_host = Control.new()
	_rows_host.position = Vector2(20, 116)
	_rows_host.size = Vector2(PANEL_WIDTH - 40, PANEL_HEIGHT - 200)
	_rows_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_rows_host)
	_rebuild_rows()

	_craft_btn = Button.new()
	_craft_btn.text = "Crear sal (1 panis + 10 denarios)"
	_craft_btn.position = Vector2(20, PANEL_HEIGHT - 64)
	_craft_btn.size = Vector2(BUTTON_WIDTH, 44)
	_craft_btn.pressed.connect(craft)
	panel.add_child(_craft_btn)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _rebuild_rows() -> void:
	for child in _rows_host.get_children():
		(child as Node).queue_free()
	_buttons.clear()
	var cursor := 0.0
	for item_id in ITEMS:
		_build_row(cursor, item_id)
		cursor += ROW_HEIGHT + ROW_GAP


func _build_row(y: float, item_id: String) -> void:
	var row := Control.new()
	row.position = Vector2(0, y)
	row.size = Vector2(PANEL_WIDTH - 40, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_host.add_child(row)

	var background := ColorRect.new()
	background.color = ROW_BG
	background.size = row.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(background)

	var btn := Button.new()
	btn.text = _button_text(item_id)
	btn.position = Vector2(8, 3)
	btn.size = Vector2(BUTTON_WIDTH, ROW_HEIGHT - 6)
	btn.pressed.connect(_on_use_pressed.bind(item_id))
	row.add_child(btn)
	_buttons[item_id] = btn


func _button_text(item_id: String) -> String:
	var nombre := str(NAMES.get(item_id, item_id))
	var cantidad := 0 if _sistema == null else _sistema.inventory.count(item_id)
	if not _is_consumable(item_id):
		return "%s x %d" % [nombre, cantidad]
	return "%s x %d — Usar" % [nombre, cantidad]


func _is_consumable(item_id: String) -> bool:
	return GameInventory.CONSUMABLES.has(item_id)


func _refresh() -> void:
	if _root == null or _rows_host == null:
		return
	if _sistema == null:
		return
	if _coins_label != null:
		_coins_label.text = "Denarios: %d" % _sistema.coins
	for item_id in ITEMS:
		var btn := _buttons.get(item_id) as Button
		if btn == null:
			continue
		btn.text = _button_text(item_id)
		btn.disabled = _sistema.inventory.count(item_id) <= 0 or not _is_consumable(item_id)
	if _craft_btn != null:
		_craft_btn.disabled = not (_sistema.has_tech("salazon") and _sistema.inventory.has("panis") and _sistema.coins >= 10)


func _on_use_pressed(item_id: String) -> void:
	use_item(item_id)


func _on_changed(_arg: Variant = null) -> void:
	_refresh()


func _on_dim_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
