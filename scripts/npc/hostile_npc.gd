extends "res://scripts/npc/roman_npc.gd"

## NPC hostil: hereda la fisica y la evitacion por raycast del patrullador y le anade aggro,
## persecucion, ataque, golpe recibido y muerte. Sin NavMesh a proposito: el horneado en
## runtime es sincrono y en el export web sin hilos congelaria el juego.

const CombatantScript := preload("res://scripts/combat/combatant.gd")
const AttackVolumeScript := preload("res://scripts/combat/attack_volume.gd")
const WeaponScript := preload("res://scripts/combat/weapon.gd")
const PickupScript := preload("res://scripts/missions/pickup.gd")
const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"

const AGGRO_RANGE := 22.0
const LOSE_RANGE := 40.0
const ATTACK_RANGE := 1.9
const ATTACK_COOLDOWN := 1.4
const CHASE_SPEED := 3.4
const STUN_SECONDS := 0.35
const CORPSE_SECONDS := 8.0
const MAX_HEALTH := 60.0
const NPC_DAMAGE := 12.0
const SENSE_INTERVAL := 0.5

## Cada segundo ataque es un empujon: menos dano, pero mete a Rito en el aire.
const PUSH_EVERY := 2
const PUSH_DAMAGE := 6.0
const PUSH_STRENGTH := 9.0
## El clip Push dura 2,67 s. A esta velocidad dura algo mas de un segundo y el tajo
## cae en un momento razonable.
const PUSH_ANIM_SPEED := 1.5
## El ataque se lee: el volumen de dano no se abre hasta pasado este windup.
const ATTACK_WINDUP := 0.35
const ATTACK_ANIM_SPEED := 0.7

var state := "PATROL"

## Ajustables por las subclases: el Praetorian sube vida, dano y cuerpo desde aqui.
var max_health := MAX_HEALTH
var attack_damage := NPC_DAMAGE
var body_scale := 1.0
## Velocidad de persecucion: el bruto la baja y el corredor la sube desde aqui.
var chase_speed := CHASE_SPEED

## False en quien no es bandido (el jefe): su muerte no suma al objetivo de bandidos.
var counts_as_kill := true

var _target: Node3D
## Referencia al jugador para el cambio de objetivo: los bandidos de emboscada
## pueden preferir al escolta, pero si el jugador se acerca y les pega, pasan
## a perseguirlo a el. Sin ella, vale el propio objetivo.
var _player_ref: Node3D
var _combatant: Combatant
var _volume: AttackVolume
var _model: Node3D
var _anim: AnimationPlayer
var _attack_ready := 0.0
var _attack_count := 0
var _swing_until := 0.0
var _stun_until := 0.0
var _sense_until := 0.0
var _corpse_until := 0.0
var _current_anim := ""
var _body_material: StandardMaterial3D


## Tinte rojizo de los bandidos de mision: la purga se distingue a distancia.
## Tras setup() el material del arma existe; si aun no, no-op (el tinte se aplica
## despues del setup, como hace BanditCamp).
func set_tint(color: Color) -> void:
	if _body_material != null:
		_body_material.albedo_color = color


## Con el objetivo opcional: GDScript exige que la firma del hijo sea compatible con la del
## padre, y un cuarto argumento obligatorio la rompe. El quinto (player) es opcional y solo
## lo usan las emboscadas: sin el, vale el propio objetivo.
func setup(data, center: Vector3, angle: float, target: Node3D = null, player: Node3D = null) -> void:
	_target = target
	_player_ref = player if player != null else target
	super.setup(data, center, angle)

	# El moloso busca enemigos por este grupo: es la unica forma de que un companero
	# encuentre a los bandidos sin que cada NPC tenga que registrarse a mano.
	add_to_group("hostiles")

	_combatant = CombatantScript.new()
	_combatant.name = "Combatant"
	add_child(_combatant)
	_combatant.setup(max_health)
	_combatant.damaged.connect(_on_damaged)
	_combatant.died.connect(_on_died)

	_build_visual()
	_build_volume()


func _build_visual() -> void:
	# Se libera la malla fusionada del patrullador en vez de ocultarla: el motivo de cambiar
	# a un maniqui con esqueleto es poder animar, y un MeshInstance3D invisible sigue ocupando
	# su buffer de vertices en un export que va justo de relleno.
	if _mesh != null:
		_mesh.queue_free()
		_mesh = null
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var mannequin: Node3D = (load(MANNEQUIN_SCENE) as PackedScene).instantiate()
	_model.add_child(mannequin)
	_anim = _find(mannequin, "AnimationPlayer")
	_attach_weapon(_find(mannequin, "Skeleton3D"))
	if not is_equal_approx(body_scale, 1.0):
		_model.scale = Vector3.ONE * body_scale
	_play("Idle")


func _attach_weapon(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "DEF-hand.R"
	skeleton.add_child(attachment)
	var instance := MeshInstance3D.new()
	instance.mesh = WeaponScript.make_gladius()
	_body_material = StandardMaterial3D.new()
	_body_material.vertex_color_use_as_albedo = true
	_body_material.roughness = 0.5
	_body_material.metallic = 0.4
	_body_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	instance.material_override = _body_material
	instance.rotation.x = -0.35
	attachment.add_child(instance)


func _build_volume() -> void:
	_volume = AttackVolumeScript.new()
	_volume.name = "AttackVolume"
	_model.add_child(_volume)
	# Capa 2: Rito. Capa 16: el moloso. Capa 32: el escolta de la mision, otro
	# objetivo valido de los bandidos y no puede quedar fuera del tajo solo porque
	# comparte capa con Rito.
	#
	# Alcance 1,2 con radio 0,8 cubre de 0,4 a 2,0 m. Con el volumen a 1,9 --igual que la
	# distancia de parada-- cualquier objetivo algo mas cerca de lo previsto queda fuera de la
	# esfera y el NPC golpea al aire.
	_volume.setup(1.2, 0.8, 2 | 16 | 32)


func _physics_process(delta: float) -> void:
	if state == "DEAD":
		_corpse_until -= delta
		if _corpse_until <= 0.0:
			queue_free()
		return

	if state == "STUN":
		if _now() >= _stun_until:
			state = "AGGRO"
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	var distance := _distance_to_target()
	if distance < 0.0:
		super._physics_process(delta)
		return

	if state == "PATROL":
		# El raycast de vista va throttled, no cada frame: cuatro NPCs son cuatro consultas
		# al espacio por frame, y la clase base ya decide con intervalo por lo mismo.
		if _now() >= _sense_until:
			_sense_until = _now() + SENSE_INTERVAL
			if distance <= AGGRO_RANGE and _can_see_target():
				state = "AGGRO"
		super._physics_process(delta)
		return

	if distance > LOSE_RANGE:
		state = "PATROL"
		super._physics_process(delta)
		return

	var direction := _flat_direction_to_target()
	if distance > ATTACK_RANGE:
		state = "CHASE"
		_chase(direction, delta)
	else:
		state = "ATTACK"
		_face(direction)
		# Sin esto el NPC sigue entrando con la inercia de la persecucion hasta quedarse
		# dentro de Rito, y el volumen --que mira hacia delante-- le pasa de largo: distancia
		# 0,00 m y cero golpes en seis segundos de pelea.
		# Solo Idle cuando no hay tajo en curso: llamado a ciegas cada frame, _play("Idle")
		# revertia Sword_Attack al fotograma siguiente y el NPC nunca completaba la animacion.
		if _now() >= _swing_until:
			_play("Idle")
		velocity.x = 0.0
		velocity.z = 0.0
		_try_attack()
		_apply_gravity(delta)
		move_and_slide()


func _chase(direction: Vector3, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * chase_speed, 8.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_face(direction)
	_play("Walk")
	_apply_gravity(delta)
	move_and_slide()


func _try_attack() -> void:
	if _now() < _attack_ready:
		return
	_attack_ready = _now() + ATTACK_COOLDOWN
	_attack_count += 1
	# Cada segundo ataque es un empujon: menos dano, pero mete a Rito en el aire.
	var pushing := _attack_count % PUSH_EVERY == 0
	var clip_name := "Push" if pushing else "Sword_Attack"
	var anim_speed := PUSH_ANIM_SPEED if pushing else ATTACK_ANIM_SPEED
	_play(clip_name, anim_speed)
	var clip_length := 0.5
	if _anim != null and _anim.has_animation(clip_name):
		clip_length = _anim.get_animation(clip_name).length / anim_speed
	_swing_until = _now() + clip_length
	_volume.begin_swing(PUSH_DAMAGE if pushing else attack_damage, self, 0.25, 0.55, clip_length, ATTACK_WINDUP)
	# El empuje fisico espera a que se abra la ventana de dano: si sale en el
	# windup, aleja a Rito antes de que el volumen pueda alcanzarlo.
	if pushing:
		var push_at := ATTACK_WINDUP + clip_length * 0.30
		get_tree().create_timer(push_at).timeout.connect(_push_target)
	var sfx := _sfx()
	if sfx != null:
		sfx.call("play", "swing", global_position, -12.0)


## El empujon fisico: el bandido mete a Rito en el aire. Solo el jugador sabe recibir un
## empujon; el moloso tiene su propia forma de caerse.
func _push_target() -> void:
	if state == "DEAD" or state == "STUN":
		return
	if _target == null or not is_instance_valid(_target):
		return
	if not _target.has_method("apply_push"):
		return
	var away := _target.global_position - global_position
	away.y = 0.0
	if away.length() < 0.01:
		return
	_target.apply_push(away, PUSH_STRENGTH)


func _on_damaged(_amount: float, _source_position: Vector3) -> void:
	if _combatant.is_alive():
		_switch_to_player_if_close()
		state = "STUN"
		_stun_until = _now() + STUN_SECONDS
		# Un aturdido no sigue barriendo el volumen ni deslizandose con la inercia:
		# el tajo en curso se cancela y la velocidad horizontal se corta.
		_volume.end_swing()
		velocity.x = 0.0
		velocity.z = 0.0
		_swing_until = 0.0
		_play("Hit_Chest")
		if _body_material != null:
			_body_material.albedo_color = Color(1.6, 1.6, 1.6)
			create_tween().tween_property(_body_material, "albedo_color", Color(1, 1, 1), 0.3)
		var sfx := _sfx()
		if sfx != null:
			sfx.call("play", "enemy_hit", global_position, -8.0)
		var feel := _feel()
		if feel != null:
			feel.call("impact", global_position + Vector3(0, 1.2, 0), Color(0.75, 0.10, 0.06), false)


## Cambio de objetivo: si el jugador esta cerca (le ha llegado a pegar), pasa a
## perseguirlo en vez de al escolta. Sin _player_ref o si ya lo tenia, no hace nada.
func _switch_to_player_if_close() -> void:
	if _player_ref == null or _target == _player_ref:
		return
	if not is_instance_valid(_player_ref):
		return
	if global_position.distance_to(_player_ref.global_position) < 6.0:
		_target = _player_ref


func _on_died(_source_position: Vector3) -> void:
	state = "DEAD"
	_drop_loot()
	_corpse_until = CORPSE_SECONDS
	collision_layer = 0
	_volume.end_swing()
	_play("Death01")
	var sfx := _sfx()
	if sfx != null:
		sfx.call("play", "enemy_die", global_position, -6.0)
	var feel := _feel()
	if feel != null:
		feel.call("impact", global_position + Vector3(0, 1.0, 0), Color(0.75, 0.10, 0.06), true)
	_on_defeated()


## Punto de extension para las subclases: el Praetorian avisa y deja la recompensa.
func _on_defeated() -> void:
	pass


## Reiniciar la misma animacion cada frame la congelaria en su primer fotograma.
## Aturdimiento pedido desde fuera: el ultimo eslabon del combo y los criticos
## dejan al bandido vendido. Si ya estaba aturdido, el aturdimiento se extiende.
func stagger(seconds: float) -> void:
	if state == "DEAD":
		return
	state = "STUN"
	_stun_until = maxf(_stun_until, _now() + seconds)
	_volume.end_swing()
	velocity.x = 0.0
	velocity.z = 0.0
	_swing_until = 0.0
	_play("Hit_Chest")


func _play(anim_name: String, speed: float = -1.0) -> void:
	if _anim == null or anim_name == _current_anim:
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.15, speed)


func _distance_to_target() -> float:
	if _target == null or not is_instance_valid(_target):
		return -1.0
	return global_position.distance_to(_target.global_position)


func _flat_direction_to_target() -> Vector3:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	return to_target.normalized()


func _can_see_target() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.5, 0)
	var to := _target.global_position + Vector3(0, 1.2, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _face(direction: Vector3) -> void:
	if _model != null and direction.length() > 0.01:
		_model.rotation.y = atan2(direction.x, direction.z)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _find(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found := _find(child, type_name)
		if found != null:
			return found
	return null


## Suelta el botin sobre el cadaver: una tirada de la tabla en tier 0 y, con suerte,
## una segunda. Los pickups notifican solos al nodo Progression al recogerlos.
func _drop_loot() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var loot := LootTable.roll(LootTable.tier_for_level(1), rng)
	if rng.randf() < 0.35:
		var extra := LootTable.roll(0, rng)
		for id in extra:
			loot[id] = int(loot.get(id, 0)) + int(extra[id])
	for id in loot:
		var pickup: Area3D = PickupScript.new()
		pickup.call("setup", id, int(loot[id]))
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(
			rng.randf_range(-0.7, 0.7), 0.35, rng.randf_range(-0.7, 0.7))


func _sfx() -> Node:
	return get_tree().get_first_node_in_group("sfx")


func _feel() -> Node:
	return get_tree().get_first_node_in_group("feel")


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
