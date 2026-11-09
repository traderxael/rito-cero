extends Node

const OUTPUT := "user://shot.png"
const DevVariantsScript := preload("res://scripts/dev/variants.gd")


func _ready() -> void:
	var main: Node = $Main
	var args := OS.get_cmdline_user_args()
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node3D = main.get_node("Player")

	for i in 200:
		await get_tree().process_frame

	if args.has("--face"):
		player.get_node("CameraYaw").rotation.y = PI
		var camera: Camera3D = player.get("camera")
		camera.position = Vector3(0, 0, 1.1)
		camera.fov = 40.0
		for i in 60:
			await get_tree().process_frame

	if args.has("--night"):
		var day_night: Node = main.get_node("DayNight")
		day_night.set("_time", 0.78)
		day_night.call("_apply")
		for i in 40:
			await get_tree().process_frame

	var variant := DevVariantsScript.current()
	print("SHOT variant=", DevVariantsScript.label(variant))
	for entry in main.get_node("Structures").get("points_of_interest"):
		print("SHOT POI ", entry["name"], " en ", entry["position"])
	var npcs := 0
	for child in main.get_node("Structures").get_children():
		if child.get_class() == "CharacterBody3D":
			npcs += 1
			print("SHOT NPC ", child.name, " en ", child.global_position)
	print("SHOT npcs=", npcs)

	if args.has("--ruins"):
		var pois: Array = main.get_node("Structures").get("points_of_interest")
		if not pois.is_empty():
			var target: Vector3 = pois[0]["position"] - Vector3(0, 3.2, 0)
			var data = main.get_node("World").get("terrain").call("get_data")
			var approach := Vector3(target.x - player.global_position.x, 0.0, target.z - player.global_position.z)
			approach = approach.normalized()
			var stand := target - approach * 11.0
			stand.y = float(data.get_height(stand)) + 0.2
			player.global_position = stand
			var flat := target - stand
			player.get_node("CameraYaw").rotation.y = atan2(-flat.x, -flat.z)
			player.get("model").rotation.y = atan2(flat.x, flat.z)
			player.get("camera_pitch").rotation.x = -0.06
			for i in 40:
				await get_tree().process_frame

	if args.has("--weapon"):
		# El arma cuelga del esqueleto, no del holder: sin esta linea la unica prueba de que
		# existe es buscarla a ojo en una captura de 1280x720.
		var weapons: Node = player.get("weapons")
		print("SHOT weapons=", weapons)
		if weapons != null:
			var attachments: Array = weapons.get("_attachments")
			for i in attachments.size():
				var attachment: Node3D = attachments[i]
				var instance: MeshInstance3D = attachment.get_child(0)
				print("SHOT arma[", i, "] visible=", attachment.visible,
					" hueso=", attachment.global_position,
					" punta=", attachment.global_transform * Vector3(0, 0, instance.mesh.get_aabb().size.z),
					" tris=", instance.mesh.get_surface_count())
		player.get_node("CameraYaw").rotation.y = PI * 0.5
		var camera: Camera3D = player.get("camera")
		camera.position = Vector3(0, 0, 2.6)
		camera.fov = 45.0
		for i in 40:
			await get_tree().process_frame

	if args.has("--fight"):
		# Prueba de extremo a extremo de la IA: teletransporta a Rito junto al primer NPC y
		# deja que transcurra el aggro, la persecucion y el golpe. Sin esto, el estado
		# "hostil" solo esta demostrado en el arnes unitario.
		var structures := main.get_node("Structures")
		var foe: Node3D = null
		for child in structures.get_children():
			if child.get_class() == "CharacterBody3D":
				foe = child
				break
		if foe != null:
			player.global_position = foe.global_position + Vector3(2.0, 0.2, 0.0)
			var fight_camera: Camera3D = player.get("camera")
			fight_camera.position = Vector3(0, 0, 3.4)
			var nearest := 999.0
			var foe_state := ""
			var hits := [0]
			var player_combatant: Combatant = player.get_node_or_null("Combatant")
			player_combatant.damaged.connect(func(_a, _p): hits[0] += 1)
			for i in 600:
				await get_tree().process_frame
				nearest = minf(nearest, player.global_position.distance_to(foe.global_position))
				foe_state = str(foe.get("state"))
			print("FIGHT estado_npc=", foe_state,
				" distancia_min=%.2f" % nearest,
				" golpes=", hits[0],
				" hp_rito=", player_combatant.health,
				" hp_npc=", foe.get_node("Combatant").get("health"),
				" vivo=", player_combatant.is_alive())

			# Y en el sentido inverso, en el mundo real: el arnes unitario fija
			# model.rotation.y = 0 a mano, asi que solo aqui se comprueba que el volumen del
			# jugador apunta hacia donde mira Rito.
			var to_foe := foe.global_position - player.global_position
			player.get("model").rotation.y = atan2(to_foe.x, to_foe.z)
			var combat := player.get_node_or_null("Combat")
			for i in 4:
				combat.call("_try_attack", false)
				for j in 50:
					await get_tree().process_frame
			print("FIGHT hp_npc=", foe.get_node("Combatant").get("health"),
				" estado_npc=", str(foe.get("state")),
				" bajas=", combat.get("kills"))
		else:
			print("FIGHT sin NPC")

	if args.has("--attack") or args.has("--spear"):
		# Pose de calibracion del §4.6: a mitad de la ventana de dano, con la camara de lado
		# para ver el brazo. 18 frames son ~0,30 s, dentro de la ventana del gladius
		# (0,19-0,42) y dentro de la de la lanza (0,26-0,52).
		var combat := player.get_node_or_null("Combat")
		if args.has("--spear"):
			combat.call("_switch", 1)
		player.get_node("CameraYaw").rotation.y = PI * 0.5
		var attack_camera: Camera3D = player.get("camera")
		attack_camera.position = Vector3(0, 0, 3.2)
		attack_camera.fov = 45.0
		for i in 6:
			await get_tree().process_frame
		_report_alignment(player, combat, "reposo")
		combat.call("_try_attack", false)
		for i in 18:
			await get_tree().process_frame
		_report_alignment(player, combat, "golpe")
		print("ATTACK bloqueado=", player.call("is_locked"),
			" swing=", combat.get("_volume").call("is_swinging"))

	if args.has("--arsenal"):
		# El menu de arsenal abierto: hay que ver las tres armas con sus cifras.
		var arsenal := main.get_node_or_null("Arsenal")
		if arsenal != null:
			arsenal.call("open")
			for i in 20:
				await get_tree().process_frame
			print("SHOT arsenal_abierto=", arsenal.call("is_open"))
		else:
			print("SHOT sin menu de arsenal")

	if args.has("--board"):
		# Tablero de misiones abierto (T14): lista de misiones + recompensas.
		var tablero := main.get_node_or_null("MissionBoard")
		if tablero != null:
			tablero.call("open")
			for i in 20:
				await get_tree().process_frame
			print("SHOT tablero_abierto=", tablero.call("is_open"))
		else:
			print("SHOT sin tablero")

	if args.has("--tech"):
		# Arbol de tecnologia abierto (T14): nodos por denarios.
		var tech := main.get_node_or_null("TechMenu")
		if tech != null:
			# Denarios de sobra para ver los botones habilitados.
			var sistema := main.get_node_or_null("Missions")
			if sistema != null:
				sistema.set("coins", 2000.0)
			tech.call("open")
			for i in 20:
				await get_tree().process_frame
			print("SHOT tech_abierto=", tech.call("is_open"))
		else:
			print("SHOT sin TechMenu")

	if args.has("--mission"):
		# Mision bandit_purge activa (T14): HUD con contador + minimapa.
		var sistema := main.get_node_or_null("Missions")
		if sistema != null:
			var ok: bool = bool(sistema.call("start_mission", "bandit_purge"))
			for i in 60:
				await get_tree().process_frame
			print("SHOT mision_iniciada=", ok, " activa=", sistema.call("is_mission_active"))
		else:
			print("SHOT sin Missions")

	if args.has("--dog") or args.has("--dogrun") or args.has("--dogbite") or args.has("--dogdown"):
		# El moloso al lado de Rito. La camara del jugador la reposiciona su controlador en
		# cada frame, asi que para el encuadre se crea una camara propia y se deja activa.
		var dog := main.get_node_or_null("Dog")
		if dog == null:
			print("SHOT sin moloso")
		else:
			var foe := _first_npc(main)
			var camera_frames := 90
			if args.has("--dogrun") and foe != null:
				dog.set("_target", foe)
				dog.set("state", "CHASE")
				dog.global_position = foe.global_position + Vector3(8.0, 0.0, 0.0)
				await _wait_ms(400)
				camera_frames = 30
			elif args.has("--dogbite") and foe != null:
				dog.set("_target", foe)
				dog.global_position = foe.global_position + Vector3(0.9, 0.0, 0.0)
				dog.set("state", "BITE")
				await _wait_ms(250)
				camera_frames = 24
			elif args.has("--dogdown"):
				var dog_combatant: Combatant = dog.get_node_or_null("Combatant")
				if dog_combatant != null:
					dog_combatant.take_damage(999.0, dog.global_position + Vector3(0, 0, 2))
				await _wait_ms(450)
				camera_frames = 20
			else:
				await _wait_ms(300)

			var dog_camera := Camera3D.new()
			main.add_child(dog_camera)
			dog_camera.current = true
			dog_camera.fov = 45.0
			for i in camera_frames:
				dog_camera.global_position = dog.global_position + Vector3(1.9, 1.25, 1.9)
				dog_camera.look_at(dog.global_position + Vector3(0, 0.45, 0), Vector3.UP)
				await get_tree().process_frame
			var dog_model := dog.get_node_or_null("Model")
			var dog_rig := dog.get_node_or_null("Model/Rig")
			print("SHOT dog=", dog.global_position, " estado=", str(dog.get("state")),
				" dist=%.2f" % player.global_position.distance_to(dog.global_position),
				" xz=%.2f" % Vector2(dog.global_position.x - player.global_position.x,
					dog.global_position.z - player.global_position.z).length(),
				" visible=", dog.visible,
				" modelo=", dog_model.global_position if dog_model != null else "SIN MODELO",
				" huesos=", dog_rig.call("bone_count") if dog_rig != null else 0,
				" animacion=", str(dog_rig.call("current_animation")) if dog_rig != null else "SIN RIG")

	if args.has("--dead"):
		# Rito muerto: la animacion de muerte cae y la fisica toma el relevo a los 1,5 s.
		# La captura se hace por reloj, no por fotogramas: el respawn llega a los 3,2 s y
		# con la maquina lenta se lo habria pasado.
		var player_combatant: Combatant = player.get_node_or_null("Combatant")
		if player_combatant != null:
			player_combatant.take_damage(999.0, player.global_position + Vector3(0, 0, 2.0))
		await _wait_ms(2200)
		var corpse_camera := Camera3D.new()
		main.add_child(corpse_camera)
		corpse_camera.current = true
		corpse_camera.fov = 45.0
		for i in 40:
			corpse_camera.global_position = player.global_position + Vector3(2.6, 1.9, -2.6)
			corpse_camera.look_at(player.global_position + Vector3(0, 0.3, 0), Vector3.UP)
			await get_tree().process_frame
		print("SHOT corpse ragdoll=", player.call("is_ragdoll_active"),
			" vivo=", player.call("is_alive"))

	if args.has("--throw"):
		# El pilum: primero en la mano, despues en vuelo. El proyectil sale a 26 m/s, asi
		# que a los 10 fotogramas ya esta a mas de 4 m del jugador.
		var combat := player.get_node_or_null("Combat")
		if combat != null:
			combat.call("switch_weapon", 1)
			for i in 10:
				await get_tree().process_frame
			print("SHOT arma=", combat.get("weapon_index"),
				" modo=", combat.get("weapon_index"))
			player.get_node("CameraYaw").rotation.y = PI * 0.5
			# El modelo mira a +Z, que es perpendicular a la vista: el pilum cruza el
			# encuadre en vez de salirse hacia delante.
			player.get("model").rotation.y = 0.0
			var throw_camera: Camera3D = player.get("camera")
			throw_camera.fov = 60.0
			for i in 6:
				await get_tree().process_frame
			# Dos capturas: el pilum en la mano y el pilum en vuelo.
			await RenderingServer.frame_post_draw
			var hand_image := get_viewport().get_texture().get_image()
			hand_image.save_png("user://shot_pilum_mano.png")
			combat.call("_try_attack", false)
			for i in 5:
				await get_tree().process_frame
			var flying := player.get_parent().get_node_or_null("Pilum")
			print("SHOT pilum en vuelo en=", flying.global_position if flying != null else "NO EXISTE")

	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var suffix := "ruins" if args.has("--ruins") else DevVariantsScript.label(variant)
	if args.has("--night"):
		suffix += "_night"
	if args.has("--weapon"):
		suffix += "_weapon"
	if args.has("--attack"):
		suffix += "_attack"
	if args.has("--spear"):
		suffix += "_spear"
	if args.has("--arsenal"):
		suffix += "_arsenal"
	if args.has("--board"):
		suffix += "_board"
	if args.has("--tech"):
		suffix += "_tech"
	if args.has("--mission"):
		suffix += "_mission"
	if args.has("--dog"):
		suffix += "_dog"
	if args.has("--dogrun"):
		suffix += "_dogrun"
	if args.has("--dogbite"):
		suffix += "_dogbite"
	if args.has("--dogdown"):
		suffix += "_dogdown"
	if args.has("--dead"):
		suffix += "_dead"
	if args.has("--throw"):
		suffix += "_throw"
	var output := "user://shot_%s.png" % suffix
	var error := image.save_png(output)
	print("SHOT saved=", error, " path=", ProjectSettings.globalize_path(output))
	print("SHOT fps=", Engine.get_frames_per_second(), " player=", player.global_position)
	get_tree().quit()


## Espera por reloj, no por fotogramas: el banco y la maquina del usuario no van al
## mismo ritmo, y una espera por fotogramas se comeria el momento que hay que capturar.
func _wait_ms(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## El primer bandido del valle, para poner al moloso a correr o a morder.
func _first_npc(main: Node) -> Node3D:
	var structures := main.get_node_or_null("Structures")
	if structures == null:
		return null
	for child in structures.get_children():
		if child.get_class() == "CharacterBody3D":
			return child
	return null


## Coseno entre el eje del arma y el frente del personaje, medido en la puntera. A ojo no se
## juzga: el hueso de la mano cambia de orientacion con cada animacion, y el giro del agarre
## vive en la instancia del mesh, no en el hueso.
func _report_alignment(player: Node3D, combat: Node, label: String) -> void:
	var facing: Vector3 = (player.get("model") as Node3D).global_transform.basis.z
	for attachment in _hand_attachments(player):
		if not attachment.visible:
			continue
		var instance: MeshInstance3D = attachment.get_child(0)
		var length: float = instance.mesh.get_aabb().size.z
		var tip := instance.global_transform * Vector3(0, 0, length)
		var toward := tip - player.global_position
		toward.y = 0.0
		print("ATTACK %s arma=%d alineacion=%.2f punta_y=%.2f mano_y=%.2f" % [
			label, combat.get("weapon_index"), facing.normalized().dot(toward.normalized()),
			tip.y, attachment.global_position.y])


func _hand_attachments(root: Node) -> Array[BoneAttachment3D]:
	var found: Array[BoneAttachment3D] = []
	for node in _descendants(root):
		var attachment := node as BoneAttachment3D
		if attachment != null and attachment.bone_name == "DEF-hand.R":
			found.append(attachment)
	return found


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result
