class_name MissionData
extends RefCounted

## Plantillas de mision del nucleo de progresion. Es dato puro: la instancia concreta
## la fabrica make_instance escalando con el nivel del jugador, y MissionSystem la
## ejecuta. El botin NO vive aqui: lo tira LootTable al completar.

## Dos misiones de tablero: la purga de bandidos (mata N) y la defensa de la
## ciudad (aguanta oleadas hasta N bajas). La tercera es el evento de mundo
## world_event (campamento en el Muro): oculta, fuera del tablero, solo lo
## arranca WorldEvent por timer con start_mission directo. Las monedas viajan
## como banda [min, max]; la recompensa paga el techo de la banda mas el botin.
const TEMPLATES := {
	"bandit_purge": {
		"type": "purge",
		"title": "Purga de bandidos",
		"brief": "Limpia la columna de bandidos que asalta el camino.",
		"xp": 60,
		"coins": [30, 60],
		"targets": 4,
		"poi": "columna",
	},
	"city_defense": {
		"type": "defense",
		"title": "Defensa de la ciudad",
		"brief": "Aguanta las oleadas contra las ruinas y no dejes pasar a los asaltantes.",
		"xp": 150,
		"coins": [80, 140],
		"targets": 18,
		"poi": "ruinas",
		"waves": [4, 6, 8],
	},
	"world_event": {
		"type": "event",
		"title": "Campamento en el Muro",
		"brief": "Un campamento de bandidos acampa junto al Muro: límpialos.",
		"xp": 80,
		"coins": [40, 80],
		"targets": 3,
		"poi": "muro",
		"hidden": true,
	},
	"escort": {
		"type": "escort",
		"title": "Escolta al superviviente",
		"brief": "Acompaña al superviviente desde las ruinas hasta la cueva. Si cae, la misión falla.",
		"xp": 120,
		"coins": [60, 100],
		"targets": 1,
		"poi": "ruinas",
	},
	"collect": {
		"type": "collect",
		"title": "Recolección de suministros",
		"brief": "Recoge los suministros dispersos junto al Muro mientras los bandidos hostigan.",
		"xp": 100,
		"coins": [50, 90],
		"targets": 6,
		"poi": "muro",
	},
	"timed": {
		"type": "timed",
		"title": "Purga contrarreloj",
		"brief": "Limpia la Columna rota antes de que acabe el tiempo.",
		"xp": 90,
		"coins": [40, 70],
		"targets": 4,
		"poi": "columna",
		"time_limit": 90,
	},
}


## Instancia escalada de una plantilla al nivel dado: la purga pide mas objetivos
## (4 + level / 4) y la defensa no escala objetivos; XP y banda de monedas suben un
## 15% por nivel a partir del 1. Un id desconocido no produce instancia.
static func make_instance(id: String, level: int) -> Dictionary:
	if not TEMPLATES.has(id):
		return {}
	var plantilla: Dictionary = TEMPLATES[id]
	var factor := 1.0 + 0.15 * float(level - 1)
	var banda: Array = plantilla["coins"]
	var inst := {
		"id": id,
		"type": str(plantilla["type"]),
		"title": str(plantilla["title"]),
		"brief": str(plantilla["brief"]),
		"xp": roundi(int(plantilla["xp"]) * factor),
		"coins": [roundi(int(banda[0]) * factor), roundi(int(banda[1]) * factor)],
		"targets": int(plantilla["targets"]),
		"poi": str(plantilla["poi"]),
		"progress": 0,
	}
	if str(plantilla["type"]) == "purge":
		inst["targets"] = 4 + level / 4
	if plantilla.has("waves"):
		inst["waves"] = (plantilla["waves"] as Array).duplicate()
	if plantilla.has("hidden"):
		inst["hidden"] = bool(plantilla["hidden"])
	if plantilla.has("time_limit"):
		inst["time_limit"] = int(plantilla["time_limit"])
	return inst


## True si el id es una plantilla oculta (solo world_event): sale de
## available_missions y del tablero, pero start_mission la acepta igual
## porque WorldEvent la arranca directo por timer.
static func is_hidden(id: String) -> bool:
	if not TEMPLATES.has(id):
		return false
	return bool((TEMPLATES[id] as Dictionary).get("hidden", false))
