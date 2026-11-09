class_name DogRig
extends Node3D

## El esqueleto del moloso: 21 huesos hechos por codigo, con las piezas atadas a ellos y
## seis animaciones (IDLE, WALK, RUN, BITE, DOWN y GET_UP).
##
## No hay ningun rig de cuadrúpedo en el proyecto y la regla sigue siendo "cero assets
## externos", asi que el rig entero es codigo. El atado es del mismo estilo que el
## vestuario de Rito (BoneAttachment3D, sin skinning): cada pieza cuelga de su hueso y la
## animacion mueve la pieza entera.
##
## El perro mira a +Z: el hocico va hacia delante y la cola hacia atras.

const SKELETON_NAME := "Skeleton3D"

const MeshFactoryScript := preload("res://scripts/world/mesh_factory.gd")

## Los 21 huesos. La posicion de cada uno es en el espacio del perro (pies en el origen),
## y el reposo de cada hueso es la diferencia con su padre.
const BONES: Array = [
	{"name": "root", "parent": "", "pos": Vector3(0, 0, 0)},
	{"name": "hips", "parent": "root", "pos": Vector3(0, 0.48, 0)},
	{"name": "spine", "parent": "hips", "pos": Vector3(0, 0.50, 0.12)},
	{"name": "chest", "parent": "spine", "pos": Vector3(0, 0.52, 0.26)},
	{"name": "neck", "parent": "chest", "pos": Vector3(0, 0.60, 0.44)},
	{"name": "head", "parent": "neck", "pos": Vector3(0, 0.66, 0.58)},
	{"name": "ear.L", "parent": "head", "pos": Vector3(0.10, 0.70, 0.52)},
	{"name": "ear.R", "parent": "head", "pos": Vector3(-0.10, 0.70, 0.52)},
	{"name": "tail", "parent": "hips", "pos": Vector3(0, 0.62, -0.44)},
	{"name": "leg.FL.upper", "parent": "hips", "pos": Vector3(0.14, 0.48, 0.26)},
	{"name": "leg.FL.lower", "parent": "leg.FL.upper", "pos": Vector3(0.14, 0.22, 0.26)},
	{"name": "leg.FL.foot", "parent": "leg.FL.lower", "pos": Vector3(0.14, 0.03, 0.29)},
	{"name": "leg.FR.upper", "parent": "hips", "pos": Vector3(-0.14, 0.48, 0.26)},
	{"name": "leg.FR.lower", "parent": "leg.FR.upper", "pos": Vector3(-0.14, 0.22, 0.26)},
	{"name": "leg.FR.foot", "parent": "leg.FR.lower", "pos": Vector3(-0.14, 0.03, 0.29)},
	{"name": "leg.BL.upper", "parent": "hips", "pos": Vector3(0.14, 0.48, -0.24)},
	{"name": "leg.BL.lower", "parent": "leg.BL.upper", "pos": Vector3(0.14, 0.22, -0.24)},
	{"name": "leg.BL.foot", "parent": "leg.BL.lower", "pos": Vector3(0.14, 0.03, -0.21)},
	{"name": "leg.BR.upper", "parent": "hips", "pos": Vector3(-0.14, 0.48, -0.24)},
	{"name": "leg.BR.lower", "parent": "leg.BR.upper", "pos": Vector3(-0.14, 0.22, -0.24)},
	{"name": "leg.BR.foot", "parent": "leg.BR.lower", "pos": Vector3(-0.14, 0.03, -0.21)},
]

## Las piezas y el hueso al que se atan. La malla va dibujada en el espacio de su hueso,
## asi que solo hace falta el desplazamiento dentro de ese hueso y, para las orejas, el
## abatido lateral.
const PIECES: Array = [
	{"bone": "hips", "mesh": "torso", "offset": Vector3(0, 0.02, 0)},
	{"bone": "chest", "mesh": "chest", "offset": Vector3.ZERO},
	{"bone": "neck", "mesh": "neck", "offset": Vector3.ZERO},
	{"bone": "head", "mesh": "head", "offset": Vector3.ZERO},
	{"bone": "ear.L", "mesh": "ear", "offset": Vector3.ZERO, "rot": Vector3(0, 0, -0.25)},
	{"bone": "ear.R", "mesh": "ear", "offset": Vector3.ZERO, "rot": Vector3(0, 0, 0.25)},
	{"bone": "tail", "mesh": "tail", "offset": Vector3.ZERO},
	{"bone": "leg.FL.upper", "mesh": "leg_upper", "offset": Vector3.ZERO},
	{"bone": "leg.FL.lower", "mesh": "leg_lower", "offset": Vector3.ZERO},
	{"bone": "leg.FL.foot", "mesh": "leg_paw", "offset": Vector3.ZERO},
	{"bone": "leg.FR.upper", "mesh": "leg_upper", "offset": Vector3.ZERO},
	{"bone": "leg.FR.lower", "mesh": "leg_lower", "offset": Vector3.ZERO},
	{"bone": "leg.FR.foot", "mesh": "leg_paw", "offset": Vector3.ZERO},
	{"bone": "leg.BL.upper", "mesh": "leg_upper", "offset": Vector3.ZERO},
	{"bone": "leg.BL.lower", "mesh": "leg_lower", "offset": Vector3.ZERO},
	{"bone": "leg.BL.foot", "mesh": "leg_paw", "offset": Vector3.ZERO},
	{"bone": "leg.BR.upper", "mesh": "leg_upper", "offset": Vector3.ZERO},
	{"bone": "leg.BR.lower", "mesh": "leg_lower", "offset": Vector3.ZERO},
	{"bone": "leg.BR.foot", "mesh": "leg_paw", "offset": Vector3.ZERO},
]

## Las cuatro patas y su fase en el ciclo. El ciclo va en diagonal: el delantero
## izquierdo va con el trasero derecho, y el delantero derecho con el trasero izquierdo.
const LEGS := ["FL", "FR", "BL", "BR"]
const LEG_PHASE := {"FL": 0.0, "BR": 0.0, "FR": PI, "BL": PI}

## Duraciones de las animaciones, en segundos.
const IDLE_LENGTH := 2.4
const WALK_LENGTH := 0.9
const RUN_LENGTH := 0.55
const BITE_LENGTH := 0.6
const DOWN_LENGTH := 0.45
const GET_UP_LENGTH := 0.8

## Amplitud del ciclo de patas: andando y corriendo.
const WALK_SWING := 0.42
const RUN_SWING := 0.68

## Cuantas muestras se guardan por ciclo. Godot interpola entre ellas.
const SAMPLES := 9

var skeleton: Skeleton3D
var player: AnimationPlayer

var _meshes: Dictionary = {}
var _current := ""
## El reposo local de cada hueso. En Godot 4 la pose de un hueso es la transformada
## ABSOLUTA dentro de su padre, no una desviacion: una pista de posicion tiene que
## escribir el reposo del hueso mas el desplazamiento, o el hueso se va al origen.
var _rest_position: Dictionary = {}


## Monta el esqueleto, las piezas y las animaciones. Se llama una vez, al crear el perro.
func build() -> void:
	_build_skeleton()
	_build_pieces()
	_build_animations()


func _build_skeleton() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = SKELETON_NAME
	add_child(skeleton)

	var positions: Dictionary = {}
	for spec: Dictionary in BONES:
		var index := skeleton.add_bone(str(spec["name"]))
		var parent := str(spec["parent"])
		var local: Vector3 = spec["pos"]
		if parent == "":
			skeleton.set_bone_parent(index, -1)
			skeleton.set_bone_rest(index, Transform3D(Basis(), local))
		else:
			local = spec["pos"] - positions[parent]
			skeleton.set_bone_parent(index, skeleton.find_bone(parent))
			skeleton.set_bone_rest(index, Transform3D(Basis(), local))
		positions[str(spec["name"])] = spec["pos"]
		_rest_position[str(spec["name"])] = local

	# El reposo de un hueso no cambia su pose: la pose nace en identidad y hay que
	# devolverla al reposo. Sin esto, el BoneAttachment3D de cada pieza se queda en el
	# origen y el perro aparece como un monton de cajas en el suelo.
	skeleton.reset_bone_poses()


func _build_pieces() -> void:
	_meshes = {
		"torso": MeshFactoryScript.make_dog_torso(),
		"chest": MeshFactoryScript.make_dog_chest(),
		"neck": MeshFactoryScript.make_dog_neck(),
		"head": MeshFactoryScript.make_dog_head(),
		"ear": MeshFactoryScript.make_dog_ear(),
		"tail": MeshFactoryScript.make_dog_tail(),
		"leg_upper": MeshFactoryScript.make_dog_leg_upper(),
		"leg_lower": MeshFactoryScript.make_dog_leg_lower(),
		"leg_paw": MeshFactoryScript.make_dog_leg_paw(),
	}

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	for spec: Dictionary in PIECES:
		var attachment := BoneAttachment3D.new()
		attachment.name = "Pieza_" + str(spec["bone"])
		attachment.bone_name = str(spec["bone"])
		skeleton.add_child(attachment)
		var instance := MeshInstance3D.new()
		instance.mesh = _meshes[str(spec["mesh"])]
		instance.material_override = material
		var rotation: Vector3 = spec.get("rot", Vector3.ZERO)
		instance.transform = Transform3D(Basis.from_euler(rotation), spec["offset"])
		attachment.add_child(instance)


func _build_animations() -> void:
	player = AnimationPlayer.new()
	player.name = "AnimationPlayer"
	# Las pistas apuntan a "Skeleton3D:hueso", asi que la raiz del reproductor tiene que
	# ser el nodo que contiene al esqueleto.
	player.root_node = NodePath("..")
	add_child(player)

	var library := AnimationLibrary.new()
	player.add_animation_library("", library)
	library.add_animation("IDLE", _build_idle())
	library.add_animation("WALK", _build_gait(WALK_LENGTH, WALK_SWING, 0.025))
	library.add_animation("RUN", _build_gait(RUN_LENGTH, RUN_SWING, 0.045))
	library.add_animation("BITE", _build_bite())
	library.add_animation("DOWN", _build_down())
	library.add_animation("GET_UP", _build_get_up())


## Reproduce una animacion por su nombre de estado. Si es la misma que ya suena, no
## reinicia el clip: reiniciarlo cada frame congelaria la animacion en su primer
## fotograma.
func play(state: String, blend: float = 0.15) -> void:
	if player == null or state == "" or state == _current:
		return
	if not player.has_animation(state):
		return
	_current = state
	player.play(state, blend)


func current_animation() -> String:
	return _current


func bone_count() -> int:
	if skeleton == null:
		return 0
	return skeleton.get_bone_count()


# --- Construccion de las animaciones -------------------------------------------------

## Una pose es un diccionario hueso -> {pos, rot}: el desplazamiento y el giro sobre la
## pose de reposo. Los huesos que no aparecen se quedan donde estan.
func _build_idle() -> Animation:
	var keys: Array = []
	var samples := 6
	for i in samples:
		var t := IDLE_LENGTH * float(i) / float(samples)
		var phase := TAU * t / IDLE_LENGTH
		var pose: Dictionary = {}
		pose["chest"] = {"pos": Vector3(0, 0.012 * sin(phase * 2.0), 0)}
		pose["head"] = {"rot": Vector3(0.04 * sin(phase + 0.6), 0, 0)}
		pose["tail"] = {"rot": Vector3(0, 0.30 * sin(phase * 3.0), 0)}
		pose["ear.L"] = {"rot": Vector3(0, 0, 0.05 * sin(phase * 1.5))}
		pose["ear.R"] = {"rot": Vector3(0, 0, -0.05 * sin(phase * 1.5))}
		keys.append({"time": t, "pose": pose})
	return _assemble(keys, IDLE_LENGTH, true)


## El ciclo de patas, en diagonal, con rebote del cuerpo. Es el mismo esqueleto con
## mas amplitud y mas frecuencia: correr es andar con prisa.
func _build_gait(length: float, swing: float, bob: float) -> Animation:
	var keys: Array = []
	for i in SAMPLES:
		var t := length * float(i) / float(SAMPLES)
		var phase := TAU * float(i) / float(SAMPLES)
		var pose: Dictionary = {}
		for leg: String in LEGS:
			var leg_phase: float = LEG_PHASE[leg] + phase
			var upper := swing * sin(leg_phase)
			var lower := -0.62 * swing * sin(leg_phase - 0.9)
			var foot := 0.34 * swing * sin(leg_phase - 1.6)
			pose["leg." + leg + ".upper"] = {"rot": Vector3(upper, 0, 0)}
			pose["leg." + leg + ".lower"] = {"rot": Vector3(lower, 0, 0)}
			pose["leg." + leg + ".foot"] = {"rot": Vector3(foot, 0, 0)}
		pose["hips"] = {"pos": Vector3(0, -bob + bob * cos(phase * 2.0), 0)}
		pose["tail"] = {"rot": Vector3(0, 0.22 * sin(phase), 0)}
		pose["head"] = {"rot": Vector3(0.03 * sin(phase * 2.0), 0, 0)}
		keys.append({"time": t, "pose": pose})
	return _assemble(keys, length, true)


## La mordida: agachazo, chasquido y vuelta. Es lo que hace visible la pelea.
func _build_bite() -> Animation:
	var crouch: Dictionary = {
		"hips": {"pos": Vector3(0, -0.05, 0)},
		"spine": {"rot": Vector3(0.16, 0, 0)},
		"chest": {"rot": Vector3(0.12, 0, 0)},
		"neck": {"rot": Vector3(0.10, 0, 0)},
		"head": {"rot": Vector3(0.18, 0, 0)},
		"tail": {"rot": Vector3(0, -0.25, 0)},
	}
	var snap: Dictionary = {
		"hips": {"pos": Vector3(0, -0.02, 0)},
		"spine": {"rot": Vector3(0.30, 0, 0)},
		"chest": {"rot": Vector3(0.26, 0, 0)},
		"neck": {"pos": Vector3(0, 0, 0.05), "rot": Vector3(-0.18, 0, 0)},
		"head": {"rot": Vector3(-0.30, 0, 0)},
		"tail": {"rot": Vector3(0, -0.30, 0)},
	}
	var recoil: Dictionary = {
		"hips": {"pos": Vector3(0, -0.01, 0)},
		"spine": {"rot": Vector3(0.10, 0, 0)},
		"chest": {"rot": Vector3(0.08, 0, 0)},
		"head": {"rot": Vector3(0.10, 0, 0)},
	}
	var keys: Array = [
		{"time": 0.0, "pose": {}},
		{"time": 0.16, "pose": crouch},
		{"time": 0.28, "pose": snap},
		{"time": 0.44, "pose": recoil},
		{"time": BITE_LENGTH, "pose": {}},
	]
	return _assemble(keys, BITE_LENGTH, false)


## El perro tumbado de lado, con las patas desmadejadas. El cuerpo baja y se ladea, y las
## patas se pliegan hacia el lado.
func _down_pose() -> Dictionary:
	var pose: Dictionary = {
		"root": {"pos": Vector3(0.12, -0.10, 0), "rot": Vector3(0, 0, 0.55)},
		"hips": {"pos": Vector3(0, -0.04, 0)},
		"spine": {"rot": Vector3(0, 0, 0.08)},
		"chest": {"rot": Vector3(0, 0, 0.08)},
		"neck": {"pos": Vector3(0, 0, -0.02), "rot": Vector3(0.20, 0, 0)},
		"head": {"rot": Vector3(0.30, 0.12, 0.15)},
		"ear.L": {"rot": Vector3(0.10, 0, 0)},
		"ear.R": {"rot": Vector3(0.10, 0, 0)},
		"tail": {"rot": Vector3(-0.40, 0, 0)},
	}
	for leg: String in LEGS:
		var side := 0.45 if leg.ends_with("L") else -0.45
		pose["leg." + leg + ".upper"] = {"rot": Vector3(-0.55, 0, side)}
		pose["leg." + leg + ".lower"] = {"rot": Vector3(0.70, 0, 0)}
		pose["leg." + leg + ".foot"] = {"rot": Vector3(0.20, 0, 0)}
	return pose


func _build_down() -> Animation:
	var keys: Array = [
		{"time": 0.0, "pose": {}},
		{"time": DOWN_LENGTH, "pose": _down_pose()},
	]
	return _assemble(keys, DOWN_LENGTH, false)


## Levantarse: de la pose tumbada a la de pie en 0,8 s. Los huesos que el tumbo movio
## tienen que volver a su sitio, asi que la pose final los escribe todos en cero.
func _build_get_up() -> Animation:
	var down := _down_pose()
	var base: Dictionary = {}
	for bone: String in down:
		base[bone] = {"pos": Vector3.ZERO, "rot": Vector3.ZERO}
	var keys: Array = [
		{"time": 0.0, "pose": down},
		{"time": GET_UP_LENGTH, "pose": base},
	]
	return _assemble(keys, GET_UP_LENGTH, false)


## Convierte una lista de poses en una animacion. Solo se crean pistas de los huesos que
## de verdad se mueven: una pista por hueso y por tipo, sin repetir.
func _assemble(keys: Array, length: float, loop: bool) -> Animation:
	var animation := Animation.new()
	animation.length = length
	if loop:
		animation.loop_mode = Animation.LOOP_LINEAR
	for entry: Dictionary in keys:
		var time := float(entry["time"])
		var pose: Dictionary = entry["pose"]
		for bone: String in pose:
			var data: Dictionary = pose[bone]
			if data.has("pos"):
				var index := _track(animation, bone, Animation.TYPE_POSITION_3D)
				# La pose de un hueso es absoluta: la pista escribe el reposo del hueso
				# mas el desplazamiento de la animacion.
				var rest: Vector3 = _rest_position.get(bone, Vector3.ZERO)
				animation.position_track_insert_key(index, time, rest + data["pos"])
			if data.has("rot"):
				var index := _track(animation, bone, Animation.TYPE_ROTATION_3D)
				animation.rotation_track_insert_key(index, time, Quaternion.from_euler(data["rot"]))
	# Cada clip define la pose ENTERA del perro: los huesos que el clip no mueve reciben
	# su valor de reposo al principio y al final. Sin esto, al cambiar de clip los huesos
	# que el nuevo no toca se quedan con la pose del anterior, y el perro se levanta a
	# medias o se queda con la cabeza gacha para siempre.
	var first: Dictionary = keys[0]["pose"]
	var last: Dictionary = keys[keys.size() - 1]["pose"]
	for spec: Dictionary in BONES:
		var bone := str(spec["name"])
		var rest: Vector3 = _rest_position.get(bone, Vector3.ZERO)
		if not first.has(bone):
			var index := _track(animation, bone, Animation.TYPE_POSITION_3D)
			animation.position_track_insert_key(index, 0.0, rest)
			var index2 := _track(animation, bone, Animation.TYPE_ROTATION_3D)
			animation.rotation_track_insert_key(index2, 0.0, Quaternion.IDENTITY)
		if not last.has(bone):
			var index3 := _track(animation, bone, Animation.TYPE_POSITION_3D)
			animation.position_track_insert_key(index3, length, rest)
			var index4 := _track(animation, bone, Animation.TYPE_ROTATION_3D)
			animation.rotation_track_insert_key(index4, length, Quaternion.IDENTITY)
	return animation


func _track(animation: Animation, bone: String, type: int) -> int:
	var path := NodePath(SKELETON_NAME + ":" + bone)
	for i in animation.get_track_count():
		if animation.track_get_type(i) == type and animation.track_get_path(i) == path:
			return i
	var index := animation.add_track(type)
	animation.track_set_path(index, path)
	return index
