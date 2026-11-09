extends CanvasLayer

const SHEET_TEXTURE := "res://assets/rito_sheet.png"
const FADE_DELAY := 5.0
const FADE_DURATION := 1.4

var _root: Control
var _elapsed := 0.0
var _fading := false


func setup(_player: Node) -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := ColorRect.new()
	panel.color = Color(0.08, 0.07, 0.06, 0.55)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = 380
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(SHEET_TEXTURE):
		portrait.texture = load(SHEET_TEXTURE)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.offset_left = 18
	portrait.offset_top = 18
	portrait.offset_right = -18
	portrait.offset_bottom = -120
	panel.add_child(portrait)

	var title := Label.new()
	title.text = "RITO CERO"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.68))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	title.offset_top = -104
	title.offset_bottom = -62
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Campo de la antigua Roma"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.80, 0.73, 0.60))
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle.offset_top = -62
	subtitle.offset_bottom = -30
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(subtitle)

	var controls := Label.new()
	controls.text = "WASD mover   ·   Shift correr   ·   Espacio saltar   ·   Ratón mirar   ·   Clic capturar   ·   F esquiva   ·   C silbar   ·   Esc liberar"
	controls.add_theme_font_size_override("font_size", 17)
	controls.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	controls.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	controls.add_theme_constant_override("shadow_offset_x", 1)
	controls.add_theme_constant_override("shadow_offset_y", 1)
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	controls.offset_top = -46
	controls.offset_bottom = -12
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(controls)


func _process(delta: float) -> void:
	if _fading:
		return
	_elapsed += delta
	if _elapsed >= FADE_DELAY:
		_fading = true
		var tween := create_tween()
		tween.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
