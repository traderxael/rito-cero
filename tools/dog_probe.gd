extends SceneTree

## Sonda del rig del moloso: comprueba los 21 huesos, que las piezas esten atadas a su
## hueso y que la animacion mueva el esqueleto de verdad.
##
## El fallo que huntza es el de las piezas: si el BoneAttachment3D no encuentra su hueso,
## todas las piezas se quedan en el origen y el perro aparece como un monton de cajas en
## el suelo. Por eso la sonda imprime la posicion global de cada pieza, no solo un "ok".

const DogRigScript := preload("res://scripts/npc/dog_rig.gd")

const EXPECTED_BONES := 21


func _init() -> void:
	var failures := 0

	var rig = DogRigScript.new()
	root.add_child(rig)
	rig.build()
	await process_frame
	await process_frame

	print("RIG huesos=", rig.bone_count())
	if rig.bone_count() != EXPECTED_BONES:
		print("FAIL se esperaban ", EXPECTED_BONES, " huesos")
		failures += 1
	else:
		print("ok el rig tiene 21 huesos")

	# Los repos: si no estan, todas las piezas se quedan en el origen.
	print("--- huesos ---")
	for i in rig.skeleton.get_bone_count():
		print("  ", rig.skeleton.get_bone_name(i),
			" padre=", rig.skeleton.get_bone_parent(i),
			" rest=", rig.skeleton.get_bone_rest(i).origin,
			" rest_global=", rig.skeleton.get_bone_global_rest(i).origin,
			" pose_global=", rig.skeleton.get_bone_global_pose(i).origin)

	# La posicion global de cada pieza: tiene que estar en el sitio del hueso que la
	# lleva, y no en el origen.
	print("--- piezas ---")
	for child in rig.skeleton.get_children():
		var attachment := child as BoneAttachment3D
		if attachment == null:
			continue
		var instance := attachment.get_child(0) as MeshInstance3D
		if instance == null:
			print("  ", attachment.bone_name, " SIN MALLA")
			failures += 1
			continue
		print("  ", attachment.bone_name,
			" pieza=", instance.global_position,
			" hueso=", attachment.global_position,
			" desvio=%.3f" % instance.global_position.distance_to(attachment.global_position))

	# La animacion tiene que mover el esqueleto: si los clips no se aplican, el perro se
	# queda de statue.
	var head: int = rig.skeleton.find_bone("head")
	var before: Vector3 = rig.skeleton.get_bone_global_pose(head).origin
	rig.play("WALK")
	for i in 30:
		await process_frame
	var after: Vector3 = rig.skeleton.get_bone_global_pose(head).origin
	print("RIG cabeza antes=", before, " despues=", after)
	if before.distance_to(after) < 0.005:
		print("FAIL la animacion no mueve el esqueleto")
		failures += 1
	else:
		print("ok la animacion mueve el esqueleto")

	for clip in ["IDLE", "WALK", "RUN", "BITE", "DOWN", "GET_UP"]:
		if rig.player == null or not rig.player.has_animation(clip):
			print("FAIL falta la animacion ", clip)
			failures += 1
		else:
			var animation: Animation = rig.player.get_animation(clip)
			print("RIG clip ", clip, " duracion=%.3f pistas=%d" % [animation.length, animation.get_track_count()])

	print("RIG failures=", failures)
	quit(1 if failures > 0 else 0)
