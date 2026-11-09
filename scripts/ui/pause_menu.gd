extends CanvasLayer

## Pausa dura con Esc: congela el arbol de escena salvo este menu (PROCESS_MODE_ALWAYS)
## y suelta el raton para poder usar los botones. El arsenal (Tab/B) es pausa blanda y
## no pasa por aqui: solo consume ui_cancel cuando esta abierto.

signal restart_requested

const BG := Color(0.05, 0.04, 0.035, 0.82)
const ACCENT := Color(0.95, 0.88, 0.70)
const TEXT := Color(0.88, 0.84, 0.74)

var _root: Control
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	var title := Label.new()
	title.text = "PAUSA"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 150
	title.offset_bottom = 210
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)

	var resume_btn := _make_button("Reanudar (Esc)", 260.0)
	resume_btn.pressed.connect(_on_resume)
	_root.add_child(resume_btn)

	var restart_btn := _make_button("Reiniciar partida", 320.0)
	restart_btn.pressed.connect(_on_restart)
	_root.add_child(restart_btn)


func _make_button(text: String, y: float) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", TEXT)
	button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	button.offset_left = -110
	button.offset_right = 110
	button.offset_top = y
	button.offset_bottom = y + 44
	return button


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	_open = not _open
	apply_pause()


func apply_pause() -> void:
	get_tree().paused = _open
	_root.visible = _open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _open else Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _open


func _on_resume() -> void:
	if _open:
		toggle()


func _on_restart() -> void:
	get_tree().paused = false
	restart_requested.emit()
	get_tree().reload_current_scene()
