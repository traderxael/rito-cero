extends SceneTree

## Sonda del ragdoll: comprueba que el simulador se monta, que todas las capsulas tienen
## forma valida y que el corpse se queda tumbado en el suelo.
##
## La prueba sigue el flujo real del juego: se reproduce la animacion de muerte hasta
## que el cuerpo esta tumbado, se enciende el ragdoll sobre esa pose y se mide que el
## cuerpo NO se hunde en el suelo ni se queda flotando, y que el esqueleto sigue a los
## cuerpos (si el esqueleto no los siguiera, el corpse se moveria pero la malla no).

const RitoScript := preload("res://scripts/player/rito.gd")
const RagdollScript := preload("res://scripts/combat/ragdoll.gd")

const EXPECTED_BODIES := 17

## Momento de la animacion de muerte en el que el cuerpo ya esta en el suelo.
const DEATH_MOMENT := 1.5

## El cuerpo tumbado debe quedarse en esta banda de altura del suelo.
const MIN_LYING_Y := -0.05
const MAX_LYING_Y := 0.45


func _init() -> void:
	var failures := 0
	_add_floor()

	var rito = RitoScript.new()
	root.add_child(rito)
	await process_frame

	var skeleton := _find_skeleton(rito)
	if skeleton == null:
		print("FAIL no hay esqueleto")
		quit(1)
		return

	# El cuerpo cae de pie y termina tumbado: se reproduce la muerte hasta ese punto.
	var player: AnimationPlayer = rito.animation_player
	if player != null and player.has_animation("Death01"):
		player.play("Death01")
		player.seek(DEATH_MOMENT, true)
		player.advance(0.0)
	await process_frame
	await process_frame

	var hips := skeleton.find_bone("DEF-hips")
	var head := skeleton.find_bone("DEF-head")
	print("RAGDOLL pose_al_morrir pelvis_y=%.3f cabeza_y=%.3f" % [
		skeleton.get_bone_global_pose(hips).origin.y,
		skeleton.get_bone_global_pose(head).origin.y])
	if skeleton.get_bone_global_pose(hips).origin.y > 0.5:
		print("FAIL el cuerpo deberia estar tumbado antes de encender la fisica")
		failures += 1
	else:
		print("ok el cuerpo esta tumbado antes del ragdoll")

	var bones := RagdollScript.attach(skeleton)
	print("RAGDOLL cuerpos=", bones.size())
	if bones.size() != EXPECTED_BODIES:
		print("FAIL se esperaban ", EXPECTED_BODIES, " cuerpos y hay ", bones.size())
		failures += 1
	else:
		print("ok el esqueleto tiene 17 cuerpos fisicos")

	var shapes := 0
	var bad_shape := 0
	for node in bones:
		var bone := node as PhysicalBone3D
		if bone == null:
			continue
		for sub in bone.get_children():
			var shape := sub as CollisionShape3D
			if shape != null and shape.shape != null:
				shapes += 1
				var capsule := shape.shape as CapsuleShape3D
				if capsule == null or capsule.radius <= 0.0 or capsule.height <= 0.0:
					bad_shape += 1
	print("RAGDOLL formas=", shapes, " formas_invalidas=", bad_shape)
	if shapes != EXPECTED_BODIES or bad_shape > 0:
		print("FAIL cada cuerpo deberia tener una capsula valida")
		failures += 1
	else:
		print("ok cada cuerpo tiene su capsula")

	# Los huesos tiene que quedar atados a los huesos del esqueleto.
	var unbound := 0
	for node in bones:
		var bone := node as PhysicalBone3D
		if bone != null and bone.get_bone_id() < 0:
			unbound += 1
	print("RAGDOLL sin_atar=", unbound)
	if unbound > 0:
		print("FAIL hay cuerpos sin atar a su hueso")
		failures += 1
	else:
		print("ok todos los cuerpos estan atados a su hueso")

	# La animacion se para: si sigue, pelea con la fisica por las poses de los huesos.
	# keep_state=true deja la pose como esta: con false, stop() devuelve el esqueleto a
	# la pose de reposo y el corpse se levanta.
	if player != null:
		player.stop(true)
	_report(skeleton, bones, "tras_parar_la_animacion")
	RagdollScript.activate(skeleton, bones)
	print("RAGDOLL simulando=", RagdollScript.is_running(bones))
	if not RagdollScript.is_running(bones):
		print("FAIL la simulacion no arranco")
		failures += 1
	_report(skeleton, bones, "tras_encender")

	for i in 120:
		await physics_frame
	_report(skeleton, bones, "tras_120_fotogramas")

	var hips_y := skeleton.get_bone_global_pose(hips).origin.y
	var head_y := skeleton.get_bone_global_pose(head).origin.y
	print("RAGDOLL despues pelvis_y=%.3f cabeza_y=%.3f" % [hips_y, head_y])
	if hips_y < MIN_LYING_Y or hips_y > MAX_LYING_Y:
		print("FAIL el corpse no se quedo en el suelo")
		failures += 1
	else:
		print("ok el corpse se quedo tumbado en el suelo")

	# El esqueleto tiene que seguir a los cuerpos: si no, la malla se queda en la pose
	# de la animacion mientras la fisica mueve los cuerpos por debajo.
	var body_y := 0.0
	for node in bones:
		var bone := node as PhysicalBone3D
		if bone != null and str(bone.bone_name) == "DEF-hips":
			body_y = bone.global_position.y
	var drift := absf(hips_y - body_y)
	print("RAGDOLLOW esqueleto=%.3f cuerpo=%.3f desvio=%.3f" % [hips_y, body_y, drift])
	if drift > 0.2:
		print("FAIL el esqueleto no sigue a los cuerpos")
		failures += 1
	else:
		print("ok el esqueleto sigue a los cuerpos")

	RagdollScript.deactivate(skeleton)
	await physics_frame
	if RagdollScript.is_running(bones):
		print("FAIL el simulador sigue activo")
		failures += 1
	else:
		print("ok el simulador se apaga")

	print("RAGDOLL failures=", failures)
	quit(1 if failures > 0 else 0)


## Imprime la altura de la pelvis segun el esqueleto y segun el cuerpo fisico: si se
## separan, el esqueleto no esta siguiendo a los cuerpos.
func _report(skeleton: Skeleton3D, bones: Array, momento: String) -> void:
	var hips := skeleton.find_bone("DEF-hips")
	var pose_y := skeleton.get_bone_global_pose(hips).origin.y
	var body_y := 0.0
	var body_found := false
	for node in bones:
		var bone := node as PhysicalBone3D
		if bone != null and str(bone.bone_name) == "DEF-hips":
			body_y = bone.global_position.y
			body_found = true
	print("  [", momento, "] esqueleto_pelvis=%.3f cuerpo_pelvis=%.3f animate=%s" % [
		pose_y, body_y, skeleton.animate_physical_bones])


## Un suelo para que el cuerpo caiga y se pose sobre el, en vez de caerse al vacio.
func _add_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Suelo"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.position = Vector3(0, -0.5, 0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
