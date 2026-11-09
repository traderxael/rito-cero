extends SceneTree

## Sonda de la API de cuerpos rigidos de Godot 4.7. Esta clase cambio de forma entre
## versiones y no hay atajo: se lee del motor y se prueba.
##
## Lo que esta sonda deja fijado (API de 4.7, leida del motor):
##   - PhysicalBone3D.bone_name existe como propiedad, aunque el volcado de la API de
##     extension no la lista. El hueso se ata por NOMBRE, no por id.
##   - physical_bones_start_simulation() recibe un Array[StringName] de NOMBRES de
##     hueso, no una lista de nodos. Pasarle los nodos falla con "Cannot assign
##     contents of Array[Object] to Array[StringName]".
##   - El simulador expone active e influence, y is_simulating_physics().
##
## La pregunta que decide el diseno: en que disposicion quedan los cuerpos atados a
## un esqueleto de verdad. La prueba no es "la simulacion arranca" (eso arranca en las
## tres), sino "el esqueleto sigue a los cuerpos": si la cabeza del hueso cae cuando el
## cuerpo cae, el atado funciona.

const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"

## Cadena central: pelvis, primera vertebra, cuello y cabeza.
const CHAIN := ["DEF-hips", "DEF-spine.001", "DEF-neck", "DEF-head"]


func _init() -> void:
	var packed: PackedScene = load(MANNEQUIN_SCENE)
	var mannequin: Node3D = packed.instantiate()
	root.add_child(mannequin)
	var source := _find_skeleton(mannequin)
	if source == null:
		print("FAIL no hay esqueleto en el maniqui")
		quit(1)
		return
	print("huesos=", source.get_bone_count())

	await _case("A: huesos bajo el simulador, arranque por el simulador", source, "simulator")
	await _case("B: huesos bajo el esqueleto, arranque por el simulador", source, "skeleton")
	await _case("C: huesos bajo el esqueleto, arranque por el esqueleto", source, "skeleton_self")

	quit(0)


## Monta un esqueleto de prueba con la cadena de huesos y prueba una disposicion.
func _case(label: String, source: Skeleton3D, mode: String) -> void:
	var skeleton := _make_chain_skeleton(source, "Copia_" + label.substr(0, 1))
	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = "Simulador"
	skeleton.add_child(simulator)

	var names: Array[StringName] = []
	for bone_name in CHAIN:
		names.append(StringName(bone_name))
		var bone := PhysicalBone3D.new()
		bone.bone_name = bone_name
		bone.name = "PB_" + bone_name
		if mode == "simulator":
			simulator.add_child(bone)
		else:
			skeleton.add_child(bone)

	print("--- ", label, " ---")
	print("  simulador.esqueleto=", simulator.get_skeleton() != null)
	print("  skeleton.animate_physical_bones=", skeleton.animate_physical_bones)

	var before := _head_y(skeleton)
	if mode == "skeleton_self":
		skeleton.physical_bones_start_simulation(names)
	else:
		simulator.physical_bones_start_simulation(names)

	await physics_frame
	await physics_frame
	print("  simulando=", simulator.is_simulating_physics())
	print("  bone_ids=", _bone_ids(skeleton, simulator))
	print("  simula=", _simulating_flags(skeleton, simulator))

	for i in 40:
		await physics_frame

	var after := _head_y(skeleton)
	print("  cabeza antes=%.3f despues=%.3f  (Y global del hueso)", before, after)

	simulator.physical_bones_stop_simulation()
	skeleton.physical_bones_stop_simulation()


## Un esqueleto minimo con la cadena central y una pose de referencia.
func _make_chain_skeleton(source: Skeleton3D, node_name: String) -> Skeleton3D:
	var copy := Skeleton3D.new()
	copy.name = node_name
	for bone_name in CHAIN:
		copy.add_bone(bone_name)
	for i in range(1, CHAIN.size()):
		copy.set_bone_parent(i, i - 1)
	# La pelvis a 0,9 m y la cabeza a 1,55 m, como el maniqui.
	copy.set_bone_pose_position(0, Vector3(0, 0.9, 0))
	copy.set_bone_pose_position(3, Vector3(0, 1.55, 0))
	source.get_parent().add_child(copy)
	return copy


func _head_y(skeleton: Skeleton3D) -> float:
	var index := skeleton.find_bone("DEF-head")
	if index < 0:
		return -1.0
	return skeleton.get_bone_global_pose(index).origin.y


func _bone_ids(skeleton: Skeleton3D, simulator: PhysicalBoneSimulator3D) -> Array:
	var ids: Array = []
	for child in simulator.get_children():
		var bone := child as PhysicalBone3D
		if bone != null:
			ids.append(bone.get_bone_id())
	for child in skeleton.get_children():
		var bone := child as PhysicalBone3D
		if bone != null:
			ids.append(bone.get_bone_id())
	return ids


func _simulating_flags(skeleton: Skeleton3D, simulator: PhysicalBoneSimulator3D) -> Array:
	var flags: Array = []
	for child in simulator.get_children():
		var bone := child as PhysicalBone3D
		if bone != null:
			flags.append(bone.is_simulating_physics())
	for child in skeleton.get_children():
		var bone := child as PhysicalBone3D
		if bone != null:
			flags.append(bone.is_simulating_physics())
	return flags


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
