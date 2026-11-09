class_name SaveGame
extends RefCounted

## Persistencia del nucleo de progresion: un solo JSON plano con xp, nivel, monedas,
## inventario, tecnologias y rachas. En web vive en localStorage; en escritorio y
## headless, en un archivo de user://. Es estatico porque no guarda estado propio.
##
## La mision activa nunca se persiste: recargar a media mision la pierde, y ese es el
## diseno. Se elimina tanto al guardar como al leer para que un archivo viejo o
## manipulado tampoco la reintroduzca.

const KEY := "ritocero_save_v1"
const PATH := "user://ritocero_save_v1.json"

## Version del esquema. Se guarda como campo aditivo: los saves viejos sin el
## campo siguen cargando y apply_save valida cada valor antes de usarlo.
const VERSION := 2

## Unica clave prohibida en el archivo. El resto del dict se guarda tal cual: el
## guardado no impone un esquema cerrado a quien lo llama.
const FORBIDDEN_KEY := "active_mission"


static func save(data: Dictionary) -> bool:
	var limpio := data.duplicate(true)
	limpio.erase(FORBIDDEN_KEY)
	var ok := _write_text(JSON.stringify(limpio))
	if not ok:
		push_warning("SaveGame: no se pudo escribir el guardado")
	return ok


static func load() -> Dictionary:
	var texto := _read_text()
	if texto.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(texto) != OK:
		return {}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var limpio: Dictionary = parsed
	limpio.erase(FORBIDDEN_KEY)
	return limpio


static func _write_text(texto: String) -> bool:
	if OS.has_feature("web"):
		var window: Variant = JavaScriptBridge.get_interface("window")
		if window == null:
			return false
		var storage: Variant = window.localStorage
		if storage == null:
			return false
		storage.setItem(KEY, texto)
		return true
	var archivo := FileAccess.open(PATH, FileAccess.WRITE)
	if archivo == null:
		return false
	var escrito := archivo.store_string(texto)
	archivo = null
	return escrito


static func _read_text() -> String:
	if OS.has_feature("web"):
		var window: Variant = JavaScriptBridge.get_interface("window")
		if window == null:
			return ""
		var storage: Variant = window.localStorage
		if storage == null:
			return ""
		var texto: Variant = storage.getItem(KEY)
		if typeof(texto) != TYPE_STRING:
			return ""
		return texto
	if not FileAccess.file_exists(PATH):
		return ""
	return FileAccess.get_file_as_string(PATH)
