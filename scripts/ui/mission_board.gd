class_name MissionBoard
extends CanvasLayer

## Tablero de misiones: lista las disponibles, acepta una y abandona con
## confirmacion en dos pasos. Se abre con J y se cierra con J o Esc.
##
## El mundo no se detiene: es una pausa blanda. Se suelta el raton para poder
## apuntar con el, y el input de combate se ignora mientras el panel esta
## abierto. El tablero no emite senales: solo lee MissionSystem y refresca su
## vista con mission_started/progress/completed/abandoned mientras esta abierto.

const VIEW_WIDTH := 1280.0
const VIEW_HEIGHT := 720.0
const PANEL_WIDTH := 700.0
const PANEL_HEIGHT := 440.0
const ROW_HEIGHT := 64.0
const ROW_GAP := 8.0
const PANEL_TOP := 110.0

const ACCENT := Color(0.95, 0.88, 0.70)
const TEXT := Color(0.88, 0.84, 0.74)
const DIM := Color(0.68, 0.64, 0.56)
const PANEL_BG := Color(0.06, 0.05, 0.04, 0.93)
const ROW_BG := Color(0.14, 0.13, 0.11, 0.9)

var _sistema: MissionSystem
var _combate: Node
var _root: Control
var _active_label: Label
var _rows_host: Control
var _accept_buttons: Dictionary = {}
var _abandon_btn: Button
var _confirm_yes: Button
var _confirm_no: Button
var _activa: Dictionary = {}
var _confirming := false
var _open := false
var _mouse_was_captured := false


func setup(system: MissionSystem, combat: Node) -> void:
	_sistema = system
	_combate = combat
	layer = 6
	_build()
	_seed_active()
	if _sistema != null:
		_connect(_sistema, "mission_started", Callable(self, "_on_mission_started"))
		_connect(_sistema, "mission_progress", Callable(self, "_on_mission_progress"))
		_connect(_sistema, "mission_completed", Callable(self, "_on_mission_completed"))
		_connect(_sistema, "mission_failed", Callable(self, "_on_mission_failed"))
		_connect(_sistema, "mission_abandoned", Callable(self, "_on_mission_abandoned"))
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
	_confirming = false
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


## Ids de las misiones que MissionSystem lista como disponibles.
func available_ids() -> Array:
	var ids: Array = []
	if _sistema == null:
		return ids
	for mision in _sistema.available_missions():
		if mision is Dictionary:
			ids.append(str((mision as Dictionary).get("id", "")))
	return ids


## Texto de la mision activa, para pruebas y para la propia vista.
func active_label_text() -> String:
	if _active_label == null:
		return ""
	return _active_label.text


## Boton Aceptar de una mision concreta, o null si no se lista.
func accept_button(mission_id: String) -> Button:
	return _accept_buttons.get(mission_id) as Button


func abandon_button() -> Button:
	return _abandon_btn


func abandon_confirm_button() -> Button:
	return _confirm_yes


func abandon_cancel_button() -> Button:
	return _confirm_no


func accept(mission_id: String) -> bool:
	if _sistema == null:
		return false
	var ok := bool(_sistema.call("start_mission", mission_id))
	_refresh()
	return ok


func request_abandon() -> void:
	_confirming = true
	_apply_abandon_state()


func confirm_abandon() -> void:
	_confirming = false
	if _sistema != null:
		_sistema.call("abandon_mission")
	_refresh()


func cancel_abandon() -> void:
	_confirming = false
	_apply_abandon_state()


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


func _seed_active() -> void:
	if _sistema == null:
		return
	var raw = _sistema.get("_active")
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		_activa = (raw as Dictionary).duplicate(true)


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

	var title := _make_label("TABLERO DE MISIONES", 26, ACCENT)
	title.position = Vector2(26, 18)
	panel.add_child(title)

	var hint := _make_label("J o Esc para cerrar", 14, DIM)
	hint.position = Vector2(26, 56)
	panel.add_child(hint)

	var active_title := _make_label("MISIÓN ACTIVA", 16, ACCENT)
	active_title.position = Vector2(26, 92)
	panel.add_child(active_title)

	_active_label = _make_label("Sin misión activa", 16, TEXT)
	_active_label.position = Vector2(26, 118)
	panel.add_child(_active_label)

	_abandon_btn = Button.new()
	_abandon_btn.text = "Abandonar"
	_abandon_btn.position = Vector2(PANEL_WIDTH - 340, 110)
	_abandon_btn.size = Vector2(140, 32)
	_abandon_btn.pressed.connect(request_abandon)
	panel.add_child(_abandon_btn)

	_confirm_yes = Button.new()
	_confirm_yes.text = "Sí, abandonar"
	_confirm_yes.position = Vector2(PANEL_WIDTH - 340, 110)
	_confirm_yes.size = Vector2(160, 32)
	_confirm_yes.visible = false
	_confirm_yes.pressed.connect(confirm_abandon)
	panel.add_child(_confirm_yes)

	_confirm_no = Button.new()
	_confirm_no.text = "No"
	_confirm_no.position = Vector2(PANEL_WIDTH - 170, 110)
	_confirm_no.size = Vector2(70, 32)
	_confirm_no.visible = false
	_confirm_no.pressed.connect(cancel_abandon)
	panel.add_child(_confirm_no)

	var avail_title := _make_label("DISPONIBLES", 16, ACCENT)
	avail_title.position = Vector2(26, 160)
	panel.add_child(avail_title)

	_rows_host = Control.new()
	_rows_host.position = Vector2(20, 190)
	_rows_host.size = Vector2(PANEL_WIDTH - 40, PANEL_HEIGHT - 210)
	_rows_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_rows_host)


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


func _refresh() -> void:
	if _root == null or _sistema == null:
		return
	_active_label.text = _active_text()
	_rebuild_rows()
	_apply_abandon_state()


func _active_text() -> String:
	if _activa.is_empty():
		return "Sin misión activa"
	var done := int(_activa.get("kills_done", 0))
	var targets := int(_activa.get("targets", 0))
	if str(_activa.get("type", "")) == "purge":
		return "Bandidos restantes: %d" % maxi(targets - done, 0)
	return "Defensa: %d/%d" % [done, targets]


func _rebuild_rows() -> void:
	for child in _rows_host.get_children():
		(child as Node).queue_free()
	_accept_buttons.clear()
	# Con una mision activa, start_mission devuelve false en silencio: pintar
	# "Aceptar" solo produce un boton muerto. El abandono sigue disponible abajo.
	if _sistema.is_mission_active():
		var aviso := _make_label("Termina o abandona la misión actual", 16, DIM)
		aviso.position = Vector2(0, 0)
		_rows_host.add_child(aviso)
		return
	var disponibles: Array = _sistema.available_missions()
	for index in disponibles.size():
		var mision: Dictionary = disponibles[index]
		_build_row(index, mision)


func _build_row(index: int, mision: Dictionary) -> void:
	var row := Control.new()
	row.position = Vector2(0, float(index) * (ROW_HEIGHT + ROW_GAP))
	row.size = Vector2(PANEL_WIDTH - 40, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_host.add_child(row)

	var background := ColorRect.new()
	background.color = ROW_BG
	background.size = row.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(background)

	var title_label := _make_label(str(mision.get("title", "")), 20, ACCENT)
	title_label.position = Vector2(16, 6)
	row.add_child(title_label)

	var brief_label := _make_label(str(mision.get("brief", "")), 13, TEXT)
	brief_label.position = Vector2(16, 32)
	row.add_child(brief_label)

	var reward_label := _make_label(_reward_text(mision), 13, DIM)
	reward_label.position = Vector2(16, 50)
	row.add_child(reward_label)

	var accept := Button.new()
	accept.text = "Aceptar"
	accept.position = Vector2(PANEL_WIDTH - 40 - 160, 16)
	accept.size = Vector2(140, 32)
	accept.pressed.connect(_on_accept_pressed.bind(str(mision.get("id", ""))))
	row.add_child(accept)
	_accept_buttons[str(mision.get("id", ""))] = accept


func _reward_text(mision: Dictionary) -> String:
	var banda: Array = mision.get("coins", [0, 0])
	var bajo := int(banda[0]) if banda.size() > 0 else 0
	var alto := int(banda[1]) if banda.size() > 1 else 0
	return "Recompensa estimada: %d XP · %d-%d denarios" % [
		int(mision.get("xp", 0)), bajo, alto]


func _apply_abandon_state() -> void:
	var has_active := not _activa.is_empty()
	_abandon_btn.text = "¿Abandonar?" if _confirming else "Abandonar"
	_abandon_btn.visible = has_active and not _confirming
	_confirm_yes.visible = has_active and _confirming
	_confirm_no.visible = has_active and _confirming


func _on_accept_pressed(mission_id: String) -> void:
	accept(mission_id)


func _on_mission_started(mision: Dictionary) -> void:
	_activa = mision.duplicate(true)
	if _open:
		_refresh()


func _on_mission_progress(current: int, goal: int) -> void:
	if not _activa.is_empty():
		_activa["kills_done"] = current
		_activa["targets"] = goal
	if _open:
		_refresh()


func _on_mission_completed(_mision: Dictionary, _recompensas: Dictionary) -> void:
	_activa = {}
	_confirming = false
	if _open:
		_refresh()


func _on_mission_abandoned(_mision: Dictionary) -> void:
	_activa = {}
	_confirming = false
	if _open:
		_refresh()


## Al fallar, el tablero tambien debe vaciarse: sin esta senal la activa quedaba
## obsoleta y la etiqueta no se refrescaba.
func _on_mission_failed(_mision: Dictionary) -> void:
	_activa = {}
	_confirming = false
	if _open:
		_refresh()


func _on_dim_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("mission_board"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
