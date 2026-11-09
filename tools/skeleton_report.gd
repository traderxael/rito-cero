extends SceneTree

## Informe del esqueleto del maniqui: nombres de los huesos, jerarquia y poses de reposo.
## El ragdoll se construye con estos nombres, asi que el informe es la entrada de esa
## pieza: si el hueso no existe, el hueso no se puede simular.

const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"


func _init() -> void:
	var packed: PackedScene = load(MANNEQUIN_SCENE)
	var mannequin: Node3D = packed.instantiate()
	root.add_child(mannequin)
	var skeleton := _find_skeleton(mannequin)
	if skeleton == null:
		print("SKELETON no encontrado")
		quit(1)
		return

	print("SKELETON huesos=", skeleton.get_bone_count())
	for i in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(i)
		var parent := skeleton.get_bone_parent(i)
		var rest := skeleton.get_bone_global_rest(i)
		print("BONE %02d %-22s padre=%-22s rest=(%.3f, %.3f, %.3f)" % [
			i, bone_name, skeleton.get_bone_name(parent) if parent >= 0 else "-",
			rest.origin.x, rest.origin.y, rest.origin.z])
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
