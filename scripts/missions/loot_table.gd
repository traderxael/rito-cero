class_name LootTable
extends RefCounted

## Tablas de botin escalonadas por nivel. Cada mision hace una sola tirada y recibe un
## diccionario id -> cantidad. Los denarios viajan bajo la clave "denarii" en ese mismo
## diccionario: el sistema de misiones los desvia al contador de monedas, no al
## inventario. Es estatico porque la tabla es dato puro y no guarda estado.

## Cada tramo abarca cinco niveles y el techo es el ultimo indice valido de TIERS.
## Los cortes del brief: 1..4 -> 0, 5..9 -> 1, 10 en adelante -> 2.
const LEVELS_PER_TIER := 5
const MAX_TIER := 2

## Cada entrada es {"id", "peso", "min", "max"}. Los pesos de cada tramo suman 100 y la
## cantidad se sortea entre min y max (iguales en los consumibles, banda en denarios).
## Un tramo sin "sal" es a proposito: la sal solo aparece a partir del tier 1.
const TIERS := [
	[
		{"id": "panis", "peso": 35, "min": 1, "max": 1},
		{"id": "aqua", "peso": 35, "min": 1, "max": 1},
		{"id": "denarii", "peso": 20, "min": 10, "max": 20},
		{"id": "pizza", "peso": 5, "min": 1, "max": 1},
		{"id": "gelatum", "peso": 5, "min": 1, "max": 1},
	],
	[
		{"id": "panis", "peso": 30, "min": 1, "max": 1},
		{"id": "aqua", "peso": 30, "min": 1, "max": 1},
		{"id": "sal", "peso": 15, "min": 1, "max": 1},
		{"id": "pizza", "peso": 10, "min": 1, "max": 1},
		{"id": "gelatum", "peso": 10, "min": 1, "max": 1},
		{"id": "denarii", "peso": 5, "min": 17, "max": 33},
	],
	[
		{"id": "panis", "peso": 25, "min": 1, "max": 1},
		{"id": "aqua", "peso": 25, "min": 1, "max": 1},
		{"id": "sal", "peso": 20, "min": 1, "max": 1},
		{"id": "pizza", "peso": 10, "min": 1, "max": 1},
		{"id": "gelatum", "peso": 10, "min": 1, "max": 1},
		{"id": "denarii", "peso": 10, "min": 30, "max": 50},
	],
]


## Tramo de botin que corresponde al nivel. Cortes del brief: 1..4 -> 0, 5..9 -> 1,
## 10 en adelante -> 2; el nivel 0 y cualquier negativo caen al suelo 0.
static func tier_for_level(level: int) -> int:
	return clampi(level / LEVELS_PER_TIER, 0, MAX_TIER)


## Una tirada: elige una entrada por peso y sortea su cantidad. Devuelve siempre una
## sola clave (id -> cantidad); se acumula con += en vez de sobrescribir para que una
## tabla futura con ids repetidos sume sus drops, y los denarios queden como cantidad
## unica.
static func roll(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var tabla: Array = TIERS[clampi(tier, 0, MAX_TIER)]
	var tirada := rng.randi_range(1, 100)
	var acumulado := 0
	for entrada in tabla:
		acumulado += int(entrada["peso"])
		if tirada <= acumulado:
			var id: String = entrada["id"]
			var cantidad := rng.randi_range(int(entrada["min"]), int(entrada["max"]))
			var botin := {}
			botin[id] = int(botin.get(id, 0)) + cantidad
			return botin
	return {}
