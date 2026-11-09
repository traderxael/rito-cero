class_name GameInventory
extends RefCounted

## Inventario minimo del nucleo de misiones: solo conteo de items y curacion directa.
## Sin UI y sin multiplicadores: quien aplique tecnologias o mejoras aplica sus factores
## encima de este numero, nunca aqui. Es un RefCounted porque no vive en el arbol: el
## sistema de misiones lo guarda y lo serializa con to_dict/from_dict.

## Curacion fija de cada consumible (Modelo: catalogo). Un id fuera de esta tabla no es
## consumible: use_consumable no cura y no toca el recuento.
const CONSUMABLES := {
	"aqua": 20.0,
	"panis": 35.0,
	"pizza": 25.0,
	"gelatum": 15.0,
}

var items: Dictionary = {}


func add(id: String, n: int = 1) -> void:
	items[id] = count(id) + n


func remove(id: String, n: int = 1) -> bool:
	if not has(id, n):
		return false
	var remaining := count(id) - n
	if remaining <= 0:
		items.erase(id)
	else:
		items[id] = remaining
	return true


func count(id: String) -> int:
	return int(items.get(id, 0))


func has(id: String, n: int = 1) -> bool:
	return count(id) >= n


func to_dict() -> Dictionary:
	return items.duplicate()


func from_dict(data: Dictionary) -> void:
	items = data.duplicate()


## Consume una unidad y devuelve los HP que cura. Sin multiplicadores: el sistema de
## progresion los aplica sobre este resultado. Sin existencias o fuera del catalogo
## devuelve 0.0 sin tocar nada.
func use_consumable(id: String) -> float:
	if not CONSUMABLES.has(id) or not has(id):
		return 0.0
	remove(id)
	return float(CONSUMABLES[id])
