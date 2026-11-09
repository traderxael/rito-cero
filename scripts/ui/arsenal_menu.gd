extends CanvasLayer

## Menu de arsenal: las cinco armas del catalogo con sus numeros. Se abre con Tab o B.
##
## Equipar desde aqui no es un adorno: cambia la malla que cuelga de la mano, el alcance
## del volumen de ataque y el dano. El menu solo decide; el cambio lo aplica el combate.
## Las dos armas nuevas del arbol (pugio e hispaniense) nacen bloqueadas: sin su
## tecnologia de armeria se ven marcadas y no se pueden equipar.
##
## El mundo no se detiene: es una pausa blanda. Se suelta el raton para poder apuntar con
## el, y el input de combate se ignora mientras el panel esta abierto.

const WeaponScript := preload("res://scripts/combat/weapon.gd")

const VIEW_WIDTH := 1280.0
const VIEW_HEIGHT := 720.0
const PANEL_WIDTH := 660.0
const PANEL_HEIGHT := 640.0
const ROW_HEIGHT := 100.0
const ROW_GAP := 8.0
const PANEL_TOP := 50.0

const ACCENT := Color(0.95, 0.88, 0.70)
const TEXT := Color(0.88, 0.84, 0.74)
const DIM := Color(0.68, 0.64, 0.56)
const PANEL_BG := Color(0.06, 0.05, 0.04, 0.93)
const ROW_BG := Color(0.14, 0.13, 0.11, 0.9)
const ROW_HOVER := Color(0.24, 0.20, 0.15, 0.95)
const EQUIPPED_BAR := Color(0.72, 0.52, 0.22)

var _rito: Node3D
var _combat: Node
var _root: Control
var _rows: Array[Control] = []
var _row_bars: Array[ColorRect] = []
var _row_backgrounds: Array[ColorRect] = []
var _row_marks: Array[Label] = []
var _selected := 0
var _open := false
var _mouse_was_captured := false
## Puerta de desbloqueo: Callable(id de arma) -> bool. Si no se pasa, las armas sin
## tecnologia en Weapon.unlock_tech nacen desbloqueadas y las demas bloqueadas.
var _unlock_check: Callable


func setup(rito: Node3D, combat: Node, unlock_check: Callable = Callable()) -> void:
	_rito = rito
	_combat = combat
	_unlock_check = unlock_check
	layer = 6
	_build()
	if _combat != null and _combat.has_signal("weapon_selected"):
		_combat.connect("weapon_selected", Callable(self, "_on_weapon_selected"))
	_refresh()


## El desbloqueo se puede pasar en setup o fijarse despues (main lo hace cuando el
## MissionSystem ya existe): en ambos casos se repinta el panel.
func set_unlock_check(unlock_check: Callable) -> void:
	_unlock_check = unlock_check
	_refresh()


## La armeria manda: con chequeo, el arma se desbloquea si el sistema dice que si;
## sin chequeo, solo las armas sin tecnologia vienen desbloqueadas de base.
func is_weapon_unlocked(index: int) -> bool:
	if index < 0 or index >= WeaponScript.count():
		return false
	var id := str(WeaponScript.get_weapon(index)["id"])
	if _unlock_check.is_valid():
		return bool(_unlock_check.call(id))
	return str(WeaponScript.unlock_tech(id)).is_empty()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_mouse_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	if _rito != null:
		_rito.call("set_capture_blocked", true)
	if _combat != null:
		_combat.call("set_input_enabled", false)
	_refresh()
	_click()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if _rito != null:
		_rito.call("set_capture_blocked", false)
	if _combat != null:
		_combat.call("set_input_enabled", true)
	if _mouse_was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_click()


func equip(index: int) -> void:
	if _combat == null:
		return
	if index < 0 or index >= WeaponScript.count():
		return
	if not is_weapon_unlocked(index):
		return
	_combat.call("switch_weapon", index)
	_click()


func _click() -> void:
	if not is_inside_tree():
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_local", "ui", -12.0)


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
	border.position = Vector2(0, 0)
	border.size = Vector2(PANEL_WIDTH, 3)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(border)

	var title := _make_label("ARSENAL ROMANO", 26, ACCENT)
	title.position = Vector2(26, 18)
	panel.add_child(title)

	var hint := _make_label("1-5 o clic para equipar  ·  Tab o B para cerrar", 14, DIM)
	hint.position = Vector2(26, 56)
	panel.add_child(hint)

	for i in WeaponScript.count():
		_build_row(panel, i)


func _build_row(panel: Control, index: int) -> void:
	var weapon: Dictionary = WeaponScript.get_weapon(index)

	var row := Control.new()
	row.position = Vector2(20, 92 + float(index) * (ROW_HEIGHT + ROW_GAP))
	row.size = Vector2(PANEL_WIDTH - 40, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(_on_row_input.bind(index))
	row.mouse_entered.connect(_on_row_hover.bind(index, true))
	row.mouse_exited.connect(_on_row_hover.bind(index, false))
	panel.add_child(row)

	var background := ColorRect.new()
	background.color = ROW_BG
	background.size = row.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(background)

	# Barra de acento: la del arma equipada es de bronce y la de las demas, transparente.
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0)
	bar.position = Vector2(0, 0)
	bar.size = Vector2(5, ROW_HEIGHT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	var name_label := _make_label(str(weapon["name"]).to_upper(), 24, ACCENT)
	name_label.position = Vector2(20, 10)
	row.add_child(name_label)

	var stats := "Daño %d  ·  Alcance %s  ·  Cadencia %s s" % [
		int(weapon["damage"]),
		_format_reach(weapon),
		_decimal(float(weapon["cooldown"]), 2)]
	var stats_label := _make_label(stats, 15, TEXT)
	stats_label.position = Vector2(20, 46)
	row.add_child(stats_label)

	var role := "%s  ·  %s" % [str(weapon["role"]), _mode_label(str(weapon["mode"]))]
	var role_label := _make_label(role, 14, DIM)
	role_label.position = Vector2(20, 70)
	row.add_child(role_label)

	var summary := _make_label(str(weapon["summary"]), 14, DIM)
	summary.position = Vector2(PANEL_WIDTH - 40 - 290, 18)
	summary.size = Vector2(290, 60)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(summary)

	var mark := _make_label("", 14, EQUIPPED_BAR)
	mark.position = Vector2(PANEL_WIDTH - 40 - 120, 70)
	mark.size = Vector2(120, 20)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(mark)

	_rows.append(row)
	_row_bars.append(bar)
	_row_backgrounds.append(background)
	_row_marks.append(mark)


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


func _format_reach(weapon: Dictionary) -> String:
	var reach := float(weapon["reach"])
	if str(weapon["mode"]) == WeaponScript.MODE_THROW:
		return "%s m de vuelo" % _decimal(reach, 0)
	return "%s m" % _decimal(reach, 1)


## Los decimales en español llevan coma.
func _decimal(value: float, decimals: int) -> String:
	return String.num(value, decimals).replace(".", ",")


func _mode_label(mode: String) -> String:
	if mode == WeaponScript.MODE_THROW:
		return "se lanza"
	return "tajo"


func _refresh() -> void:
	if _combat == null:
		return
	var current := int(_combat.get("weapon_index"))
	for i in _rows.size():
		var equipped := (i == current)
		_row_bars[i].color = EQUIPPED_BAR if equipped else Color(0, 0, 0, 0)
		if equipped:
			_row_marks[i].text = "EQUIPADA"
		elif not is_weapon_unlocked(i):
			_row_marks[i].text = "BLOQUEADA"
		else:
			_row_marks[i].text = ""
		if not equipped and i == _selected:
			_row_backgrounds[i].color = ROW_HOVER
		else:
			_row_backgrounds[i].color = ROW_BG


func _on_weapon_selected(_index: int) -> void:
	_refresh()


## La rueda cicla el arsenal y equipa al pasar: es el atajo que mas se usa cuando ya se
## sabe que hay cinco armas y solo importa la que se lleva en la mano. Salta las
## bloqueadas: sin tecnologia, su fila se respeta pero no se equipa.
func _cycle(step: int) -> void:
	var count := WeaponScript.count()
	if count == 0:
		return
	for intento in count:
		_selected = (_selected + step + count) % count
		if is_weapon_unlocked(_selected):
			break
	equip(_selected)


func _on_row_hover(index: int, entered: bool) -> void:
	if not _open or index >= _row_backgrounds.size():
		return
	_selected = index
	if entered:
		_row_backgrounds[index].color = ROW_HOVER
	elif int(_combat.get("weapon_index")) != index:
		_row_backgrounds[index].color = ROW_BG


func _on_row_input(event: InputEvent, index: int) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	_selected = index
	equip(index)


func _on_dim_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("arsenal_menu"):
		if _open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
		return

	if not _open:
		return

	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return

	for i in WeaponScript.count():
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			equip(i)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var wheel := event as InputEventMouseButton
		if wheel.pressed and wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
		elif wheel.pressed and wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)
