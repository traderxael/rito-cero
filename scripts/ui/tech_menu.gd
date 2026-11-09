class_name TechMenu
extends CanvasLayer

## Árbol de tecnología: las nueve mejoras agrupadas por rama (Agua, Comida,
## Armas). Se abre con T y se cierra con T o Esc.
##
## El menú no guarda qué se compró: solo lee MissionSystem (has_tech/coins) y
## compra con buy_tech. El estado se repinta con tech_changed/coins_changed,
## así que una compra desde otro sitio también deja los botones correctos.
## El mundo no se detiene: es una pausa blanda como el tablero. Se suelta el
## ratón para poder apuntar con él y el input de combate se ignora mientras el
## panel está abierto.

const VIEW_WIDTH := 1280.0
const VIEW_HEIGHT := 720.0
const PANEL_WIDTH := 860.0
const PANEL_HEIGHT := 600.0
const PANEL_TOP := 60.0
const HEADER_HEIGHT := 24.0
const ROW_HEIGHT := 40.0
const ROW_GAP := 6.0
const BUTTON_WIDTH := 340.0

const ACCENT := Color(0.95, 0.88, 0.70)
const TEXT := Color(0.88, 0.84, 0.74)
const DIM := Color(0.68, 0.64, 0.56)
const PANEL_BG := Color(0.06, 0.05, 0.04, 0.93)
const ROW_BG := Color(0.14, 0.13, 0.11, 0.9)

var _sistema: MissionSystem
var _combate: Node
var _root: Control
var _rows_host: Control
var _coins_label: Label
var _buttons: Dictionary = {}
var _open := false
var _mouse_was_captured := false


func setup(system: MissionSystem, combat: Node) -> void:
	_sistema = system
	_combate = combat
	layer = 6
	_build()
	if _sistema != null:
		_connect(_sistema, "tech_changed", Callable(self, "_on_tech_changed"))
		_connect(_sistema, "coins_changed", Callable(self, "_on_coins_changed"))
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


## Botón de un nodo concreto, o null si no existe en la tabla.
func button_for(node_id: String) -> Button:
	return _buttons.get(node_id) as Button


func buy(node_id: String) -> bool:
	if _sistema == null:
		return false
	var ok := bool(_sistema.call("buy_tech", node_id))
	_refresh()
	return ok


func coins_label_text() -> String:
	if _coins_label == null:
		return ""
	return _coins_label.text


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

	var title := _make_label("ÁRBOL DE TECNOLOGÍA", 26, ACCENT)
	title.position = Vector2(26, 18)
	panel.add_child(title)

	var hint := _make_label("T o Esc para cerrar", 14, DIM)
	hint.position = Vector2(26, 56)
	panel.add_child(hint)

	_coins_label = _make_label("Denarios: 0", 16, TEXT)
	_coins_label.position = Vector2(26, 84)
	panel.add_child(_coins_label)

	_rows_host = Control.new()
	_rows_host.position = Vector2(20, 116)
	_rows_host.size = Vector2(PANEL_WIDTH - 40, PANEL_HEIGHT - 136)
	_rows_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_rows_host)
	_rebuild_rows()


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
	for rama in TechTree.branches():
		var header := _make_label(str(rama).to_upper(), 16, ACCENT)
		header.position = Vector2(0, cursor)
		header.size = Vector2(PANEL_WIDTH - 40, HEADER_HEIGHT)
		_rows_host.add_child(header)
		cursor += HEADER_HEIGHT + 4.0
		for nodo in TechTree.nodes_in_branch(str(rama)):
			_build_row(cursor, nodo as Dictionary)
			cursor += ROW_HEIGHT + ROW_GAP


func _build_row(y: float, nodo: Dictionary) -> void:
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
	btn.text = _button_text(nodo)
	btn.position = Vector2(8, 3)
	btn.size = Vector2(BUTTON_WIDTH, ROW_HEIGHT - 6)
	btn.pressed.connect(_on_button_pressed.bind(str(nodo["id"])))
	row.add_child(btn)
	_buttons[str(nodo["id"])] = btn

	var desc := _make_label(str(nodo["desc"]), 13, TEXT)
	desc.position = Vector2(8 + BUTTON_WIDTH + 12, 4)
	desc.size = Vector2(PANEL_WIDTH - 40 - BUTTON_WIDTH - 20, ROW_HEIGHT - 8)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(desc)


func _button_text(nodo: Dictionary) -> String:
	var nombre := str(nodo["nombre"])
	var coste := int(nodo["coste"])
	if _sistema != null and _sistema.has_tech(str(nodo["id"])):
		return "%s — %d denarios (COMPRADA)" % [nombre, coste]
	return "%s — %d denarios" % [nombre, coste]


func _refresh() -> void:
	if _root == null or _rows_host == null:
		return
	if _sistema == null:
		return
	if _coins_label != null:
		_coins_label.text = "Denarios: %d" % _sistema.coins
	for nodo in TechTree.NODES:
		var btn := _buttons.get(str(nodo["id"])) as Button
		if btn == null:
			continue
		var coste := int(nodo["coste"])
		var comprada := _sistema.has_tech(str(nodo["id"]))
		btn.disabled = comprada or _sistema.coins < coste
		btn.text = _button_text(nodo)


func _on_button_pressed(node_id: String) -> void:
	buy(node_id)


func _on_tech_changed(_node_id: String) -> void:
	_refresh()


func _on_coins_changed(_coins: int) -> void:
	_refresh()


func _on_dim_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("tech_tree"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
