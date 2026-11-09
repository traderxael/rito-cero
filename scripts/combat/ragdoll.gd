class_name Ragdoll
extends RefCounted

## Ragdoll sobre el esqueleto del maniqui: un PhysicalBone3D por hueso y una capsula por
## hueso. Al morir Rito, los cuerpos se sueltan y el esqueleto los sigue.
##
## API de Godot 4.7 (leida del motor con la sonda tools/api_probe.gd, no de memoria):
##   - El hueso se ata por NOMBRE: la propiedad es bone_name (no aparece en el volcado
##     de la API de extension, pero existe en la instancia).
##   - physical_bones_start_simulation() recibe un Array[StringName] de NOMBRES de
##     hueso, no una lista de nodos.
##   - Los PhysicalBone3D tienen que ser hijos DIRECTOS del Skeleton3D: si cuelgan del
##     simulador, los bone_ids quedan a -1 y el esqueleto no los sigue.
##   - La simulacion la arranca el Skeleton3D, no el simulador.
##   - No hay junta de resorte: los tipos son NONE, PIN, CONE, HINGE, SLIDER y 6DOF.
##
## Los cuerpos se colocan sobre la POSE ACTUAL del esqueleto, no sobre la pose de
## reposo: la animacion de muerte "Death01" acaba con el cuerpo tumbado en el suelo
## (medido en tools/anim_report.gd: pelvis a 0,063 m y cabeza a 0,151 m a los 2,4 s), y
## el ragdoll tiene que quedarse con esa pose. Si se montaran sobre la pose de reposo,
## el corpse apareceria de pie y la fisica lo sostendia en el aire.
##
## Las capsulas NO tienen medidas inventadas: cada una se dimensiona midiendo la
## distancia entre las poses de dos huesos, y el radio se limita a la mitad de ese
## tramo para que dos capsulas vecinas no se solapen.

## Tipo de junta de cada hueso: "none" deja el cuerpo libre, "cone" es la articulacion
## de hombro y cadera (una bola con limites), y el resto de huesos forman la columna.
const BONES: Array = [
	{"bone": "DEF-hips", "to": "DEF-spine.001", "radius": 0.15, "joint": "none"},
	{"bone": "DEF-spine.001", "to": "DEF-spine.002", "radius": 0.12, "joint": "cone"},
	{"bone": "DEF-spine.002", "to": "DEF-spine.003", "radius": 0.12, "joint": "cone"},
	{"bone": "DEF-spine.003", "to": "DEF-neck", "radius": 0.11, "joint": "cone"},
	{"bone": "DEF-neck", "to": "DEF-head", "radius": 0.13, "joint": "cone"},
	{"bone": "DEF-shoulder.L", "to": "DEF-upper_arm.L", "radius": 0.07, "joint": "cone"},
	{"bone": "DEF-upper_arm.L", "to": "DEF-forearm.L", "radius": 0.06, "joint": "cone"},
	{"bone": "DEF-forearm.L", "to": "DEF-hand.L", "radius": 0.055, "joint": "cone"},
	{"bone": "DEF-shoulder.R", "to": "DEF-upper_arm.R", "radius": 0.07, "joint": "cone"},
	{"bone": "DEF-upper_arm.R", "to": "DEF-forearm.R", "radius": 0.06, "joint": "cone"},
	{"bone": "DEF-forearm.R", "to": "DEF-hand.R", "radius": 0.055, "joint": "cone"},
	{"bone": "DEF-thigh.L", "to": "DEF-shin.L", "radius": 0.085, "joint": "cone"},
	{"bone": "DEF-shin.L", "to": "DEF-foot.L", "radius": 0.065, "joint": "cone"},
	{"bone": "DEF-foot.L", "to": "DEF-toe.L", "radius": 0.05, "joint": "cone"},
	{"bone": "DEF-thigh.R", "to": "DEF-shin.R", "radius": 0.085, "joint": "cone"},
	{"bone": "DEF-shin.R", "to": "DEF-foot.R", "radius": 0.065, "joint": "cone"},
	{"bone": "DEF-foot.R", "to": "DEF-toe.R", "radius": 0.05, "joint": "cone"},
]

## Capa de los cuerpos rigidos: colisionan con el terreno y no empujan a nadie.
const BODY_LAYER := 32
const BODY_MASK := 1

## El nombre del hueso al que se ata cada cuerpo.
const META_BONE := "ragdoll_bone"
const META_TARGET := "ragdoll_target"
const META_RADIUS := "ragdoll_radius"


## Monta el ragdoll sobre un esqueleto. Devuelve los huesos fisicos creados, o una lista
## vacia si el esqueleto no tiene los huesos necesarios.
##
## Los cuerpos se cuelgan del esqueleto y no de un simulador: en 4.7, si cuelgan del
## simulador, el simulador no encuentra el esqueleto (get_skeleton() devuelve null) y los
## cuerpos quedan sin atar.
static func attach(skeleton: Skeleton3D) -> Array:
	var created: Array = []
	if skeleton == null:
		return created

	for spec: Dictionary in BONES:
		var index := skeleton.find_bone(str(spec["bone"]))
		var target := skeleton.find_bone(str(spec["to"]))
		if index < 0 or target < 0:
			continue
		var bone := PhysicalBone3D.new()
		bone.name = "PB_" + str(spec["bone"])
		bone.bone_name = str(spec["bone"])
		bone.collision_layer = BODY_LAYER
		bone.collision_mask = BODY_MASK
		bone.joint_type = _joint_type(str(spec["joint"]))
		bone.set_meta(META_BONE, str(spec["bone"]))
		bone.set_meta(META_TARGET, str(spec["to"]))
		bone.set_meta(META_RADIUS, float(spec["radius"]))
		skeleton.add_child(bone)
		created.append(bone)
	_sync_to_pose(skeleton, created)
	return created


static func _joint_type(kind: String) -> int:
	if kind == "none":
		return PhysicalBone3D.JOINT_TYPE_NONE
	return PhysicalBone3D.JOINT_TYPE_CONE


## Coloca cada cuerpo en la pose actual de su hueso y redimensiona su capsula. Se llama
## al montar y al encender: si entre medias el esqueleto se ha movido, los cuerpos
## siguen al esqueleto en vez de quedarse en la pose de partida.
static func _sync_to_pose(skeleton: Skeleton3D, bones: Array) -> void:
	for node in bones:
		var bone := node as PhysicalBone3D
		if bone == null:
			continue
		var index := skeleton.find_bone(str(bone.get_meta(META_BONE)))
		var target := skeleton.find_bone(str(bone.get_meta(META_TARGET)))
		if index < 0 or target < 0:
			continue
		var from := skeleton.get_bone_global_pose(index)
		var to := skeleton.get_bone_global_pose(target)
		bone.transform = from
		_fit_capsule(bone, from, to, float(bone.get_meta(META_RADIUS)))


## La capsula cubre el tramo entre dos huesos: su centro esta a media distancia y su eje
## sigue la direccion del tramo. La direccion se pasa al espacio local del hueso, que es
## donde vive la forma. La altura es el tramo completo y el radio no pasa de la mitad de
## ese tramo, para que dos capsulas vecinas no se solapen y el cuerpo no se deshidrate.
static func _fit_capsule(bone: PhysicalBone3D, from: Transform3D, to: Transform3D, radius: float) -> void:
	var shape := _capsule_shape(bone)
	if shape == null:
		return
	var direction := to.origin - from.origin
	var length := direction.length()
	if length < 0.01:
		return
	var local := from.basis.orthonormalized().inverse() * direction
	var axis := local.normalized()
	var reference := Vector3.RIGHT
	if absf(axis.dot(Vector3.RIGHT)) > 0.9:
		reference = Vector3.FORWARD
	var side := reference.cross(axis).normalized()
	var forward := side.cross(axis).normalized()

	var capsule := shape.shape as CapsuleShape3D
	capsule.radius = minf(radius, length * 0.45)
	capsule.height = maxf(length, capsule.radius * 2.0)
	shape.transform = Transform3D(Basis(side, axis, forward), local * 0.5)


static func _capsule_shape(bone: PhysicalBone3D) -> CollisionShape3D:
	for child in bone.get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			return shape
	var shape := CollisionShape3D.new()
	shape.name = "Forma"
	shape.shape = CapsuleShape3D.new()
	bone.add_child(shape)
	return shape


## Enciende la simulacion. El esqueleto la arranca con la lista de NOMBRES de los
## huesos, no con los nodos.
static func activate(skeleton: Skeleton3D, bones: Array) -> void:
	if skeleton == null:
		return
	var names: Array[StringName] = []
	for node in bones:
		var bone := node as PhysicalBone3D
		if bone != null:
			names.append(StringName(bone.bone_name))
	if names.is_empty():
		return
	_sync_to_pose(skeleton, bones)
	skeleton.physical_bones_start_simulation(names)


static func deactivate(skeleton: Skeleton3D) -> void:
	if skeleton != null:
		skeleton.physical_bones_stop_simulation()


## Si la simulacion esta encendida. Se pregunta a los propios cuerpos, que son los que
## saben si se estan simulando.
static func is_running(bones: Array) -> bool:
	for node in bones:
		var bone := node as PhysicalBone3D
		if bone != null and bone.is_simulating_physics():
			return true
	return false


## La posicion de un hueso en el mundo, para medir si el cuerpo ha caido.
static func bone_position(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.ZERO
	return skeleton.get_bone_global_pose(index).origin
