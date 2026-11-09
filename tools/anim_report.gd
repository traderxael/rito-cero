extends SceneTree

## Volcado de la libreria del maniqui: las duraciones reales deciden las fracciones
## de la ventana de impacto, no la documentacion del pack.

const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"
const CLAVELES := [
	"Sword_Idle", "Sword_Attack", "Sword_Attack_RM",
	"Punch_Jab", "Punch_Cross", "Punch_Enter",
	"Hit_Chest", "Hit_Head", "Death01",
	"Idle_Loop", "Walk_Loop", "Sprint_Loop", "Jog_Fwd",
]


func _init() -> void:
	var packed := load(MANNEQUIN_SCENE) as PackedScene
	if packed == null:
		print("ERROR no se puede instanciar ", MANNEQUIN_SCENE)
		quit(1)
		return
	var mannequin := packed.instantiate() as Node3D
	root.add_child(mannequin)
	var player := _find_player(mannequin)
	if player == null:
		print("ERROR no hay AnimationPlayer en la escena")
		quit(1)
		return
	var names := player.get_animation_list()
	names.sort()
	print("ANIM-COUNT ", names.size())
	for name in names:
		print("ANIM ", name, " len=", "%.4f" % player.get_animation(name).length)
	print("--- claveles ---")
	for name in CLAVELES:
		var tiene := player.has_animation(name)
		print("CLAVE ", name, " existe=", tiene,
			" len=", ("%.4f" % player.get_animation(name).length) if tiene else "-1.0000")
	_report_huesos(mannequin)
	await _report_poses(mannequin)
	quit()


## La pose real de un clip decide como se engancha la fisica: si la animacion de muerte
## termina tumbada, el ragdoll solo tiene que sujetar el cuerpo en el suelo; si termina
## de pie, el ragdoll necesita un empujon para que el corpse se derrumbe.
func _report_poses(mannequin: Node3D) -> void:
	var player := _find_player(mannequin)
	var skeleton := _find_skeleton(mannequin)
	if player == null or skeleton == null:
		print("POSE no hay AnimationPlayer o Skeleton3D")
		return
	print("ARBOL ", _tree(mannequin))
	var hips := skeleton.find_bone("DEF-hips")
	var head := skeleton.find_bone("DEF-head")
	var skeleton_path := skeleton.get_path()
	if hips < 0 or head < 0:
		print("POSE faltan los huesos DEF-hips o DEF-head")
		return
	for clip in ["Death01", "Roll", "Push", "Hit_Head", "Jump_Land"]:
		if not player.has_animation(clip):
			print("POSE ", clip, " no existe")
			continue
		var length := player.get_animation(clip).length
		print("POSE ", clip, " duracion=%.3f" % length)
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var t := length * fraction
			player.play(clip)
			player.seek(t, true)
			player.advance(0.0)
			await process_frame
			print("  t=%.3f pelvis_y=%.3f cabeza_y=%.3f" % [
				t,
				skeleton.get_bone_global_pose(hips).origin.y,
				skeleton.get_bone_global_pose(head).origin.y])
	_report_tracks(player, "Death01", skeleton_path)


func _tree(node: Node) -> String:
	var names: Array = []
	for child in node.get_children():
		names.append("%s(%s)" % [child.name, child.get_class()])
	return " > ".join(names)


## Las pistas dicen a que nodo apuntan. Si apuntan a otro esqueleto, la pose se esta
## midiendo en el sitio equivocado.
func _report_tracks(player: AnimationPlayer, clip: String, skeleton_path: NodePath) -> void:
	if not player.has_animation(clip):
		return
	var animation := player.get_animation(clip)
	print("PISTAS ", clip, "=", animation.get_track_count())
	for i in animation.get_track_count():
		var path := animation.track_get_path(i)
		var type := animation.track_get_type(i)
		print("  ", type, " ", path)
		if i > 5:
			print("  ...")
			break
	print("  root_node=", player.root_node, " esqueleto=", skeleton_path)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _report_huesos(root_node: Node) -> void:
	# Las manos son el punto de montaje del arma y la antorcha: si el nombre no esta, el
	# BoneAttachment3D se queda silenciosamente anclado al origen y el arma flota en el torso.
	for node in _descendants(root_node):
		if not (node is Skeleton3D):
			continue
		var skeleton := node as Skeleton3D
		for bone_name in ["DEF-hand.R", "DEF-hand.L", "DEF-spine.001", "DEF-head"]:
			print("BONE ", bone_name, " idx=", skeleton.find_bone(bone_name))
		return


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
