class_name Weapon
extends RefCounted

## Catalogo de las armas romanas: parametros de combate y malla. Los numeros viven aqui
## para que la calibracion sea una edicion de una tabla y no una busqueda por cuatro
## archivos. Cada fila es autocontenida: el indice de la fila es el que usan las teclas
## 1-5 y el menu de arsenal.
##
## Antes eran arrays paralelos (REACH[0], DAMAGE[0], ...): anadir un arma obligaba a tocar
## siete listas, y un indice desalineado se manifestaba como "el arma 3 hace el dano del
## arma 1". Con una fila, un arma nueva es una fila y su geometria.

const MeshFactoryScript := preload("res://scripts/world/mesh_factory.gd")

const MODE_MELEE := "melee"
const MODE_THROW := "throw"

const BLADE := Color(0.78, 0.80, 0.84)
const BLADE_EDGE := Color(0.88, 0.90, 0.93)
const BRONZE := Color(0.62, 0.45, 0.20)
const GRIP := Color(0.30, 0.20, 0.12)
const SHAFT := Color(0.45, 0.33, 0.18)
const SPEAR_TIP := Color(0.72, 0.74, 0.78)
const IRON := Color(0.40, 0.42, 0.47)
const IRON_DARK := Color(0.26, 0.28, 0.32)

## El arsenal. "reach" es el alcance del cuerpo a cuerpo; en modo lanzamiento es la
## distancia maxima de vuelo. "window_open" y "window_close" son fracciones del clip de
## animacion, como en el combate heredado.
const CATALOG: Array = [
	{
		"id": "gladius",
		"name": "Gladius",
		"role": "Cuerpo a cuerpo",
		"mode": MODE_MELEE,
		"damage": 34.0,
		"reach": 2.2,
		"cooldown": 0.55,
		"window_open": 0.25,
		"window_close": 0.55,
		"radius": 0.75,
		"anim_speed": 2.0,
		"grip_rot_x": -0.35,
		"mesh": "gladius",
		"summary": "Espada corta de la infantería: rápida, fiable y siempre a mano.",
	},
	{
		"id": "pilum",
		"name": "Pilum",
		"role": "Lanzamiento",
		"mode": MODE_THROW,
		"damage": 40.0,
		"reach": 26.0,
		"cooldown": 1.45,
		"speed": 26.0,
		"anim_speed": 1.2,
		"grip_rot_x": -0.92,
		"mesh": "pilum",
		"summary": "Jabalina de hierro: alcanza muy lejos, pero tarda en volver a estar lista.",
	},
	{
		"id": "spatha",
		"name": "Spatha",
		"role": "Cuerpo a cuerpo",
		"mode": MODE_MELEE,
		"damage": 58.0,
		"reach": 2.6,
		"cooldown": 0.80,
		"window_open": 0.25,
		"window_close": 0.55,
		"radius": 0.70,
		"anim_speed": 1.6,
		"grip_rot_x": -0.35,
		"mesh": "spatha",
		"summary": "Hoja larga de la caballería: golpe lento y mucho más daño.",
	},
	{
		"id": "pugio",
		"name": "Pugio",
		"role": "Cuerpo a cuerpo",
		"mode": MODE_MELEE,
		"damage": 22.0,
		"reach": 1.6,
		"cooldown": 0.35,
		"window_open": 0.25,
		"window_close": 0.55,
		"radius": 0.55,
		"anim_speed": 2.4,
		"grip_rot_x": -0.35,
		"mesh": "pugio",
		"summary": "Puñal del legionario: casi una extensión del puño.",
	},
	{
		"id": "hispaniens",
		"name": "Hispaniense",
		"role": "Cuerpo a cuerpo",
		"mode": MODE_MELEE,
		"damage": 48.0,
		"reach": 2.4,
		"cooldown": 0.65,
		"window_open": 0.25,
		"window_close": 0.55,
		"radius": 0.70,
		"anim_speed": 1.9,
		"grip_rot_x": -0.35,
		"mesh": "hispaniens",
		"summary": "La espada que plagiaron los romanos de los celtíberos.",
	},
]


## Tecnologia que desbloquea cada arma nueva del arbol de armeria. Las tres de base
## (gladius, pilum, spatha) no piden nada: unlock_tech devuelve "" para ellas. El
## menu de arsenal y main leen esta tabla, no sucesos sueltos: una sola fuente.
const UNLOCK_TECH := {
	"pugio": "armeria1",
	"hispaniens": "armeria2",
}


static func unlock_tech(id: String) -> String:
	return str(UNLOCK_TECH.get(id, ""))


static func count() -> int:
	return CATALOG.size()


static func get_weapon(index: int) -> Dictionary:
	if index < 0 or index >= CATALOG.size():
		return CATALOG[0]
	return CATALOG[index]


static func index_of(id: String) -> int:
	for i in CATALOG.size():
		if CATALOG[i]["id"] == id:
			return i
	return 0


static func make_mesh(mesh_id: String) -> ArrayMesh:
	match mesh_id:
		"pilum":
			return make_pilum()
		"spatha":
			return make_spatha()
		"pugio":
			return make_pugio()
		"hispaniens":
			return make_hispaniens()
		_:
			return make_gladius()


static func make_gladius() -> ArrayMesh:
	var parts: Array = []

	var blade := BoxMesh.new()
	blade.size = Vector3(0.05, 0.10, 0.82)
	parts.append({
		"mesh": blade,
		"transform": Transform3D(Basis(), Vector3(0, 0, 0.46)),
		"color": BLADE,
		"top_color": BLADE_EDGE,
	})

	var guard := BoxMesh.new()
	guard.size = Vector3(0.17, 0.05, 0.05)
	parts.append({"mesh": guard, "transform": Transform3D(Basis(), Vector3(0, 0, 0.04)), "color": BRONZE})

	var grip := CylinderMesh.new()
	grip.top_radius = 0.022
	grip.bottom_radius = 0.026
	grip.height = 0.16
	grip.radial_segments = 6
	grip.rings = 1
	var grip_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({"mesh": grip, "transform": Transform3D(grip_basis, Vector3(0, 0, -0.06)), "color": GRIP})
	return MeshFactoryScript._merge(parts)


## Spatha: hoja larga, guarda con florete y empunadura larga. El detalle que la
## distingue del gladius a un vistazo es el florete, una disco en la guarda.
static func make_spatha() -> ArrayMesh:
	var parts: Array = []

	var blade := BoxMesh.new()
	blade.size = Vector3(0.055, 0.11, 1.15)
	parts.append({
		"mesh": blade,
		"transform": Transform3D(Basis(), Vector3(0, 0, 0.60)),
		"color": BLADE,
		"top_color": BLADE_EDGE,
	})

	var guard := BoxMesh.new()
	guard.size = Vector3(0.22, 0.055, 0.06)
	parts.append({"mesh": guard, "transform": Transform3D(Basis(), Vector3(0, 0, 0.02)), "color": BRONZE})

	var floret := CylinderMesh.new()
	floret.top_radius = 0.075
	floret.bottom_radius = 0.075
	floret.height = 0.035
	floret.radial_segments = 8
	floret.rings = 1
	var floret_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({"mesh": floret, "transform": Transform3D(floret_basis, Vector3(0, 0, 0.02)), "color": BRONZE})

	var grip := CylinderMesh.new()
	grip.top_radius = 0.022
	grip.bottom_radius = 0.028
	grip.height = 0.22
	grip.radial_segments = 6
	grip.rings = 1
	var grip_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({"mesh": grip, "transform": Transform3D(grip_basis, Vector3(0, 0, -0.11)), "color": GRIP})

	var pommel := SphereMesh.new()
	pommel.radius = 0.035
	pommel.height = 0.07
	pommel.radial_segments = 6
	pommel.rings = 3
	parts.append({"mesh": pommel, "transform": Transform3D(Basis(), Vector3(0, 0, -0.23)), "color": BRONZE})
	return MeshFactoryScript._merge(parts)


## Pugio: hoja muy corta con una guarda sencilla. Es casi un puring de cinturon:
## la primera diferencia con el gladius es que cabe dentro de una mano.
static func make_pugio() -> ArrayMesh:
	var parts: Array = []

	var blade := BoxMesh.new()
	blade.size = Vector3(0.045, 0.09, 0.38)
	parts.append({
		"mesh": blade,
		"transform": Transform3D(Basis(), Vector3(0, 0, 0.22)),
		"color": BLADE,
		"top_color": BLADE_EDGE,
	})

	var guard := BoxMesh.new()
	guard.size = Vector3(0.15, 0.04, 0.05)
	parts.append({"mesh": guard, "transform": Transform3D(Basis(), Vector3(0, 0, 0.02)), "color": BRONZE})

	var grip := CylinderMesh.new()
	grip.top_radius = 0.022
	grip.bottom_radius = 0.026
	grip.height = 0.12
	grip.radial_segments = 6
	grip.rings = 1
	var grip_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({"mesh": grip, "transform": Transform3D(grip_basis, Vector3(0, 0, -0.05)), "color": GRIP})
	return MeshFactoryScript._merge(parts)


## Hispaniense: el gladius mas largo y ancho, como lo usaban los celtiberos antes
## de que los romanos lo copiaran. Sin el florete de la spatha: lo que se nota a
## un vistazo es la hoja, una tabla un poco mas ancha y larga que la del gladius.
static func make_hispaniens() -> ArrayMesh:
	var parts: Array = []

	var blade := BoxMesh.new()
	blade.size = Vector3(0.06, 0.12, 1.05)
	parts.append({
		"mesh": blade,
		"transform": Transform3D(Basis(), Vector3(0, 0, 0.56)),
		"color": BLADE,
		"top_color": BLADE_EDGE,
	})

	var guard := BoxMesh.new()
	guard.size = Vector3(0.20, 0.05, 0.05)
	parts.append({"mesh": guard, "transform": Transform3D(Basis(), Vector3(0, 0, 0.02)), "color": BRONZE})

	var grip := CylinderMesh.new()
	grip.top_radius = 0.022
	grip.bottom_radius = 0.027
	grip.height = 0.18
	grip.radial_segments = 6
	grip.rings = 1
	var grip_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({"mesh": grip, "transform": Transform3D(grip_basis, Vector3(0, 0, -0.09)), "color": GRIP})
	return MeshFactoryScript._merge(parts)


## Pilum: astil de madera con vastago de hierro y punta piramidal. El agarre esta en el
## origen de la malla, asi que el astil sale de la mano hacia delante (+Z).
static func make_pilum() -> ArrayMesh:
	var parts: Array = []

	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.024
	shaft.bottom_radius = 0.028
	shaft.height = 1.55
	shaft.radial_segments = 6
	shaft.rings = 1
	var shaft_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({"mesh": shaft, "transform": Transform3D(shaft_basis, Vector3(0, 0, 0.775)), "color": SHAFT})

	# Vastago de hierro: el mismo giro que el astil, para que siga la misma linea.
	var shank := CylinderMesh.new()
	shank.top_radius = 0.026
	shank.bottom_radius = 0.026
	shank.height = 0.55
	shank.radial_segments = 6
	shank.rings = 1
	parts.append({"mesh": shank, "transform": Transform3D(shaft_basis, Vector3(0, 0, 1.825)), "color": IRON})

	# La punta: el radio pequeno del cono (+Y) se gira a +Z para que apunte al frente.
	var tip := CylinderMesh.new()
	tip.top_radius = 0.001
	tip.bottom_radius = 0.045
	tip.height = 0.24
	tip.radial_segments = 6
	tip.rings = 1
	parts.append({
		"mesh": tip,
		"transform": Transform3D(shaft_basis, Vector3(0, 0, 2.22)),
		"color": IRON_DARK,
		"top_color": BLADE_EDGE,
	})

	# Punta trasera: el pilum tambien se usaba para sujetar el escudo.
	var butt := CylinderMesh.new()
	butt.top_radius = 0.001
	butt.bottom_radius = 0.035
	butt.height = 0.18
	butt.radial_segments = 6
	butt.rings = 1
	var butt_basis := Basis(Vector3.RIGHT, -PI * 0.5)
	parts.append({"mesh": butt, "transform": Transform3D(butt_basis, Vector3(0, 0, -0.09)), "color": IRON_DARK})
	return MeshFactoryScript._merge(parts)
