class_name TechTree
extends RefCounted

## Árbol de tecnología: las nueve mejoras que se compran con denarios de mision.
## Es dato puro como MissionData y LootTable: MissionSystem guarda la propiedad
## (buy_tech/has_tech) y el menú solo pinta esta tabla. Los costes de aqui y de
## MissionSystem.TECH_COSTS son la misma tabla copiada: si se cambia una, hay que
## cambiar la otra para que el menú no prometa un precio que el sistema cobra distinto.
## Total 1000 denarios (60+60+80+100+100+120+80+150+250), no 1080 del plan.
const NODES: Array[Dictionary] = [
	{"id": "pozo", "rama": "Agua", "coste": 60, "nombre": "Pozo de agua", "desc": "+25 % aqua en recompensas de mision"},
	{"id": "acequia", "rama": "Comida", "coste": 60, "nombre": "Acequia", "desc": "+25 % panis en recompensas de mision"},
	{"id": "salazon", "rama": "Comida", "coste": 80, "nombre": "Salazon", "desc": "Desbloquea Sal: 1 panis + 10 denarios → 1 sal (+15 HP en panis)"},
	{"id": "granero", "rama": "Comida", "coste": 100, "nombre": "Granero", "desc": "Los panis de mision dan +1 unidad"},
	{"id": "molino", "rama": "Comida", "coste": 100, "nombre": "Molino de agua", "desc": "El panis cura +50 % (52 HP)"},
	{"id": "bodega", "rama": "Comida", "coste": 120, "nombre": "Bodega de nieve", "desc": "El helado cura el doble (30 HP)"},
	{"id": "armeria1", "rama": "Armas", "coste": 80, "nombre": "Pugio romano", "desc": "Desbloquea puñal: 22 daño, 1,6 m, cadencia 0,35 s"},
	{"id": "armeria2", "rama": "Armas", "coste": 150, "nombre": "Gladio hispaniense", "desc": "Desbloquea hispaniense: 48 daño, 2,4 m, cadencia 0,65 s"},
	{"id": "armeria3", "rama": "Armas", "coste": 250, "nombre": "Templado de Toledo", "desc": "El gladius hace +30 % de daño permanente"},
]


static func by_id(id: String) -> Dictionary:
	for nodo in NODES:
		if str(nodo["id"]) == id:
			return nodo
	return {}


static func cost_of(id: String) -> int:
	var nodo := by_id(id)
	if nodo.is_empty():
		return 0
	return int(nodo["coste"])


static func total_cost() -> int:
	var suma := 0
	for nodo in NODES:
		suma += int(nodo["coste"])
	return suma


static func branches() -> Array:
	var ramas: Array = []
	for nodo in NODES:
		var rama := str(nodo["rama"])
		if not ramas.has(rama):
			ramas.append(rama)
	return ramas


static func nodes_in_branch(rama: String) -> Array:
	var lista: Array = []
	for nodo in NODES:
		if str(nodo["rama"]) == rama:
			lista.append(nodo)
	return lista
