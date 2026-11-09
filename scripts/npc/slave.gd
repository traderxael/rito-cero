extends CharacterBody3D

## Companero de Rito: lo sigue y ataca al hostil vivo mas cercano. No esta en el
## grupo "hostiles" (el moloso lo confundiria con un enemigo) y vive en la capa 64,
## fuera de las mascaras de los volumenes de Rito y de los bandidos: no recibe fuego
## amigo. Su volumen solo danza con la capa 4, la de los hostiles.

const CombatantScript := preload("res://scripts/combat/combatant.gd")
const AttackVolumeScript := preload("res://scripts/combat/attack_volume.gd")
const WeaponScript := preload("res://scripts/combat/weapon.gd")
const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"

signal killed(target: Node)

const COMPANION_LAYER := 64
const COMPANION_HEALTH := 80.0
const FOLLOW_SPEED := 4.5
const CATCHUP_SPEED := 15.0
const CHASE_SPEED := 4.2
const START_FOLLOW_DISTANCE := 3.2
const ENGAGE_RANGE := 12.0
const ATTACK_RANGE := 2.0
const ATTACK_COOLDOWN := 1.4
const ATTACK_DAMAGE := 12.0
const STUN_SECONDS := 0.35
const CORPSE_SECONDS := 8.0
const GRAVITY := 26.0

var state := "FOLLOW"
var _player: Node3D
var _combatant: Combatant
var _model: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _volume: AttackVolume
var _material: StandardMaterial3D
var _attack_ready := 0.0
var _swing_until := 0.0
var _stun_until := 0.0
var _corpse_until := 0.0
var _current_anim := ""


func setup(player: Node3D, at: Vector3 = Vector3.ZERO) -> void:
	_player = player
	add_to_group("companions")
	collision_layer = COMPANION_LAYER
	collision_mask = 1 | 4
	floor_snap_length = 0.6
	global_position = at

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)

	_combatant = CombatantScript.new()
	_combatant.name = "Combatant"
	add_child(_combatant)
	_combatant.setup(COMPANION_HEALTH)
	_combatant.damaged.connect(_on_damaged)
	_combatant.died.connect(_on_died)

	_build_visual()
	_build_volume()
	_play("Idle")


func _build_visual() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var packed: PackedScene = load(MANNEQUIN_SCENE)
	var mannequin: Node3D = packed.instantiate()
	_model.add_child(mannequin)

	_anim = null
	_skeleton = null
	_find_nodes(mannequin)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.6
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_add_rope()
	_attach_weapon()


func _find_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is AnimationPlayer:
			_anim = child as AnimationPlayer
		if child is Skeleton3D:
			_skeleton = child as Skeleton3D
		_find_nodes(child)


func _add_rope() -> void:
	if _skeleton == null:
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "Spine"
	_skeleton.add_child(attachment)
	var instance := MeshInstance3D.new()
	var rope := CylinderMesh.new()
	rope.top_radius = 0.05
	rope.bottom_radius = 0.05
	rope.height = 0.9
	instance.mesh = rope
	var rope_material := StandardMaterial3D.new()
	rope_material.albedo_color = Color(0.42, 0.30, 0.16)
	rope_material.roughness = 1.0
	instance.material_override = rope_material
	instance.rotation = Vector3(0.0, 0.0, PI * 0.5)
	instance.position = Vector3(0.0, -0.35, 0.0)
	attachment.add_child(instance)


func _attach_weapon() -> void:
	if _skeleton == null:
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "DEF-hand.R"
	_skeleton.add_child(attachment)
	var instance := MeshInstance3D.new()
	instance.mesh = WeaponScript.make_gladius()
	instance.material_override = _material
	instance.rotation.x = -0.35
	attachment.add_child(instance)


func _build_volume() -> void:
	_volume = AttackVolumeScript.new()
	_volume.name = "AttackVolume"
	_model.add_child(_volume)
	_volume.setup(1.9, 0.7, 4)
	_volume.landed.connect(_on_volume_landed)


func _physics_process(delta: float) -> void:
	if state == "DEAD":
		_corpse_until -= delta
		if _corpse_until <= 0.0:
			queue_free()
		return

	if state == "STUN":
		if _now() >= _stun_until:
			state = "FOLLOW"
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	var hostile := _nearest_live_hostile()
	if hostile != null and _player_distance() <= 16.0:
		_engage(hostile)
	else:
		_follow()
	_apply_gravity(delta)
	move_and_slide()


func _follow() -> void:
	if _player == null or not is_instance_valid(_player):
		velocity.x = 0.0
		velocity.z = 0.0
		_play("Idle")
		return
	state = "FOLLOW"
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if distance <= START_FOLLOW_DISTANCE:
		velocity.x = 0.0
		velocity.z = 0.0
		_play("Idle")
		return
	var direction := to_player.normalized()
	var speed := FOLLOW_SPEED
	if distance > ENGAGE_RANGE:
		speed = CATCHUP_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face(direction)
	_play("Walk")


func _engage(hostile: Node3D) -> void:
	var to_target := hostile.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.01 else Vector3.FORWARD
	_face(direction)
	if distance > ATTACK_RANGE:
		state = "CHASE"
		velocity.x = direction.x * CHASE_SPEED
		velocity.z = direction.z * CHASE_SPEED
		_play("Walk")
		return
	state = "ATTACK"
	velocity.x = 0.0
	velocity.z = 0.0
	if _now() >= _swing_until:
		_play("Idle")
	_try_attack()


func _try_attack() -> void:
	if _now() < _attack_ready:
		return
	_attack_ready = _now() + ATTACK_COOLDOWN
	_play("Sword_Attack")
	var clip_length := 0.5
	if _anim != null and _anim.has_animation("Sword_Attack"):
		clip_length = _anim.get_animation("Sword_Attack").length
	_swing_until = _now() + clip_length
	_volume.begin_swing(ATTACK_DAMAGE, self, 0.25, 0.55, clip_length)


func _nearest_live_hostile() -> Node3D:
	var best: Node3D = null
	var best_distance := ENGAGE_RANGE
	for node in get_tree().get_nodes_in_group("hostiles"):
		var enemy := node as Node3D
		if enemy == null or not is_instance_valid(enemy) or enemy == self:
			continue
		var combatant := enemy.get_node_or_null("Combatant") as Combatant
		if combatant == null or not combatant.is_alive():
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _player_distance() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	return global_position.distance_to(_player.global_position)


func _on_volume_landed(target: Node, _damage: float, _was_stunned: bool) -> void:
	var combatant := target.get_node_or_null("Combatant") as Combatant
	if combatant != null and not combatant.is_alive():
		killed.emit(target)


func _on_damaged(_amount: float, _source_position: Vector3) -> void:
	if not _combatant.is_alive():
		return
	state = "STUN"
	_stun_until = _now() + STUN_SECONDS
	if _volume != null:
		_volume.end_swing()
	velocity.x = 0.0
	velocity.z = 0.0
	_swing_until = 0.0
	_play("Hit_Chest")


func _on_died(_source_position: Vector3) -> void:
	state = "DEAD"
	collision_layer = 0
	collision_mask = 0
	_corpse_until = CORPSE_SECONDS
	if _volume != null:
		_volume.end_swing()
	_play("Death01")


func _face(direction: Vector3) -> void:
	if _model != null and direction.length() > 0.01:
		_model.rotation.y = atan2(direction.x, direction.z)


func _play(anim_name: String) -> void:
	if _anim == null or anim_name == _current_anim:
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.15)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
