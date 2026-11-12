class_name Rito
extends CharacterBody3D

const DevVariantsScript := preload("res://scripts/dev/variants.gd")

const RitoOutfitScript := preload("res://scripts/player/rito_outfit.gd")
const RagdollScript := preload("res://scripts/combat/ragdoll.gd")
const SfxScript := preload("res://scripts/audio/sfx.gd")
const FeelScript := preload("res://scripts/fx/feel.gd")
const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"
const FACE_TEXTURE := "res://assets/rito_face.png"

const WALK_SPEED := 6.0
const RUN_SPEED := 12.0
const ACCELERATION := 10.0
const JUMP_VELOCITY := 9.5
const GRAVITY := 32.0
const MOUSE_SENSITIVITY := 0.0032
const CAMERA_DISTANCE := 5.6
const CAMERA_HEIGHT := 1.68
const MIN_PITCH := -1.05
const MAX_PITCH := 0.85

const ANIM_IDLE := ["Idle", "Idle_Loop"]
const ANIM_WALK := ["Walk", "Walk_Loop", "Jog_Fwd"]
const ANIM_SPRINT := ["Sprint", "Sprint_Loop", "Jog_Fwd"]
const ANIM_JUMP := ["Jump", "Jump_Loop", "Jump_Start"]
const ANIM_IDLE_TORCH := ["Idle_Torch", "Idle_Torch_Loop"]
const BLEND_TIME := 0.25
const ONE_SHOT_BLEND := 0.08

## Un golpe recibido no puede perder el turno contra un tajo en curso, y la muerte no puede
## quedar tapada por ninguno de los dos.
const PRIORITY_ATTACK := 1
const PRIORITY_LAND := 2
const PRIORITY_HIT := 3
const PRIORITY_DYING := 4

const ANIM_HIT := ["Hit_Chest", "Hit_Head"]
const ANIM_HIT_STRONG := ["Hit_Head", "Hit_Chest"]
const ANIM_DEATH := ["Death01", "Death"]
const ANIM_ROLL := ["Roll"]
const ANIM_LAND := ["Jump_Land"]

## La animacion de muerte dura 2,4 s y el cuerpo no toca el suelo hasta pasado 1,2 s. La
## fisica toma el relevo a los 1,5 s, con el corpse ya tumbado: si el ragdoll se encendiera
## de pie, el cuerpo se quedaria sostenido en el aire.
const RESPAWN_DELAY := 3.2
const RAGDOLL_DELAY := 1.5

## Altura de la camara cuando el corpse esta en el suelo: mira al cuerpo, no al aire.
const CORPSE_CAMERA_HEIGHT := 0.55

## Golpes de este dano o mas reaccionan con la cabeza, no con el pecho.
const STRONG_HIT := 12.0

## La esquiva: impulso en la direccion de entrada, invulnerabilidad y enfriamiento.
const DODGE_SPEED := 12.0
const DODGE_SECONDS := 0.35
const DODGE_INVULNERABLE := 0.35
const DODGE_COOLDOWN := 0.8
const DODGE_ANIM_SPEED := 1.6

## La guardia: barra propia, reduccion frontal y ruptura. La defensa es activa: la
## esquiva sigue siendo la forma de evitar el dano por completo.
const GUARD_MAX := 100.0
const GUARD_DAMAGE_REDUCTION := 0.8
const GUARD_COST_MULT := 1.1
const GUARD_REGEN := 22.0
const GUARD_REGEN_DELAY := 0.7
const GUARD_SPEED_MULT := 0.55
const GUARD_BREAK_DAMAGE := 0.5
const GUARD_BREAK_STUN := 0.8
const GUARD_BREAK_LOCK := 1.5
const GUARD_REFRACTORY_REFILL := 25.0

## El parry es una ventana corta desde la pulsacion; el riposte, la recompensa.
const PARRY_WINDOW := 0.20
const PARRY_STAGGER := 1.1
const RIPOSTE_WINDOW := 1.5
const RIPOSTE_MULT := 1.75

## El empujon fisico se desvanece solo. Si se sumara a la velocidad del controlador, la
## aceleracion lo borraria en cuatro fotogramas y no se veria nada.
const PUSH_DECAY := 8.0

## Distancia horizontal recorrida entre un paso y otro, en metros.
const STEP_DISTANCE := 2.1

## Game feel del controlador: coyote, buffer, camara y FOV.
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const CAMERA_SMOOTH := 18.0
const FOV_WALK := 68.0
const FOV_SPRINT := 74.0
const FOV_LERP := 8.0
const LAND_DIP_AMOUNT := 0.06
const LAND_DIP_DECAY := 0.3

signal died
signal guard_changed(current: float, maximum: float)
signal guard_broken
signal parried
signal riposte_changed(active: bool)

var combatant: Node

var model: Node3D
var animation_player: AnimationPlayer
var camera_yaw: Node3D
var camera_pitch: Node3D
var camera: Camera3D

var _pitch := -0.24
var _animation_state := ""
var _resolved_idle := ""
var _resolved_walk := ""
var _resolved_sprint := ""
var _resolved_jump := ""
var _resolved_idle_torch := ""
var _night := false
var torch: Node3D
var weapons: WeaponsHolder
var _web_elapsed := 0.0
var _web_ready := false
var _spawn_position := Vector3.ZERO
var _lock_until := 0.0
var _lock_priority := 0
var _resolved_hit := ""
var _resolved_hit_strong := ""
var _resolved_death := ""
var _resolved_roll := ""
var _resolved_land := ""
var _resolved_guard := ""
var _respawn_timer := 0.0
var _dead := false
var _spawn_point := Vector3.ZERO
var _capture_blocked := false
var dog: Node3D
var slave: Node3D

## El ragdoll: los cuerpos fisicos que sueltan el esqueleto al morir.
var _ragdoll_bones: Array = []
var _ragdoll_timer := -1.0
var _ragdoll_active := false

## El empujon fisico y el estado de la esquiva.
var _push_velocity := Vector3.ZERO
var _dodge_ready_at := 0.0
var _guard := GUARD_MAX
var _guarding := false
var _guard_regen_at := 0.0
var _guard_lock_until := 0.0
var _parry_until := 0.0
var _riposte_until := 0.0
var _was_on_floor := true
var _coyote_until := 0.0
var _jump_buffered_at := -1.0
var _land_dip := 0.0
var _camera_smooth_pos := Vector3.INF

## Nodo Feel del game feel (shake/hit-stop), o null en los tests que no lo montan.
var feel: Node
var _step_accum := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	_build_body()
	_build_model()
	_build_camera()
	_init_web_bridge()


func _build_body() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 1.8
	collision.shape = capsule
	collision.position = Vector3(0, 0.9, 0)
	add_child(collision)


func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)

	var packed: PackedScene = load(MANNEQUIN_SCENE)
	var mannequin: Node3D = packed.instantiate()
	mannequin.name = "Mannequin"
	model.add_child(mannequin)
	model.rotation.y = PI

	var skeleton := _find_skeleton(mannequin)
	animation_player = _find_animation_player(mannequin)
	if animation_player != null:
		_resolved_idle = _resolve_animation(ANIM_IDLE)
		_resolved_walk = _resolve_animation(ANIM_WALK)
		_resolved_sprint = _resolve_animation(ANIM_SPRINT)
		_resolved_jump = _resolve_animation(ANIM_JUMP)
		_resolved_idle_torch = _resolve_animation(ANIM_IDLE_TORCH)
		_resolved_hit = _resolve_animation(ANIM_HIT)
		_resolved_hit_strong = _resolve_animation(ANIM_HIT_STRONG)
		_resolved_death = _resolve_animation(ANIM_DEATH)
		_resolved_roll = _resolve_animation(ANIM_ROLL)
		_resolved_land = _resolve_animation(ANIM_LAND)
		_resolved_guard = _resolve_animation(["Sword_Idle", "Idle_Loop"])
	if skeleton != null:
		RitoOutfitScript.recolor_skin(mannequin)
		var face: Texture2D = null
		if ResourceLoader.exists(FACE_TEXTURE):
			face = load(FACE_TEXTURE)
		RitoOutfitScript.build(skeleton, face)
		torch = RitoOutfitScript.add_torch(skeleton)
		weapons = WeaponsHolder.new()
		weapons.name = "Weapons"
		add_child(weapons)
		weapons.setup(skeleton)


func _build_camera() -> void:
	camera_yaw = Node3D.new()
	camera_yaw.name = "CameraYaw"
	add_child(camera_yaw)

	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0, CAMERA_HEIGHT, 0)
	camera_yaw.add_child(pivot)

	camera_pitch = Node3D.new()
	camera_pitch.name = "CameraPitch"
	camera_pitch.rotation.x = _pitch
	pivot.add_child(camera_pitch)

	camera = Camera3D.new()
	camera.fov = 68.0
	camera.near = 0.08
	camera.far = 600.0
	camera.position = Vector3(0, 0, CAMERA_DISTANCE)
	camera_pitch.add_child(camera)


func _physics_process(delta: float) -> void:
	if _dead:
		_respawn_timer -= delta
		# El cuerpo no se mueve del sitio mientras esta muerto: el corpse cae con la fisica
		# y el nodo tiene que quedarse donde murio, o se llevaria el corpse consigo.
		if _ragdoll_timer >= 0.0:
			_ragdoll_timer -= delta
			if _ragdoll_timer <= 0.0:
				_ragdoll_timer = -1.0
				_start_ragdoll()
		if _respawn_timer <= 0.0:
			respawn(_spawn_point)
		return

	# Cálculo de dirección de entrada
	var input := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var basis_yaw := camera_yaw.global_transform.basis
	var direction := (basis_yaw * Vector3(input.x, 0.0, -input.y)).normalized()

	# Movimiento con aceleración. La guardia impide esprintar y frena el paso.
	_update_guard(delta)
	var target_speed := RUN_SPEED if Input.is_action_pressed("sprint") and not _guarding else WALK_SPEED
	if _guarding:
		target_speed *= GUARD_SPEED_MULT
	var target_velocity := direction * target_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, ACCELERATION * delta * target_speed)
	velocity.z = move_toward(velocity.z, target_velocity.z, ACCELERATION * delta * target_speed)

	# Aplicar empujon después de la aceleración
	velocity.x += _push_velocity.x
	velocity.z += _push_velocity.z
	_push_velocity = _push_velocity.lerp(Vector3.ZERO, clampf(PUSH_DECAY * delta, 0.0, 1.0))

	# Gravedad, coyote time y jump buffer.
	if Input.is_action_just_pressed("jump"):
		_jump_buffered_at = _now()
	if is_on_floor():
		_coyote_until = _now() + COYOTE_TIME
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	var can_jump := is_on_floor() or _now() < _coyote_until
	var wants_jump := Input.is_action_just_pressed("jump") or (_jump_buffered_at > 0.0 and _now() - _jump_buffered_at < JUMP_BUFFER)
	if can_jump and wants_jump:
		velocity.y = JUMP_VELOCITY
		_coyote_until = 0.0
		_jump_buffered_at = -1.0

	move_and_slide()
	_check_landing()
	_update_steps(delta)
	_update_model(delta, direction)
	_update_camera(delta)


## El aterrizaje de un salto se ve: el cuerpo se agacha y vuelve. Se dispara al tocar el
## suelo, no al saltar, porque en el aire no hay contacto con el que comparar.
func _check_landing() -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		play_one_shot(_resolved_land, 0.45, PRIORITY_LAND)
		_land_dip = LAND_DIP_AMOUNT
	_was_on_floor = on_floor


func _update_model(delta: float, direction: Vector3) -> void:
	if model == null:
		return
	if direction.length() > 0.05:
		var target_angle := atan2(direction.x, direction.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_angle, 1.0 - exp(-14.0 * delta))

	# El decaimiento va antes del retorno: si no, un bloqueo jamas se apaga y Rito se queda
	# con la animacion del ultimo tajo pegada para siempre.
	if _lock_priority > 0 and not is_locked():
		_lock_priority = 0
		_animation_state = ""
	if is_locked():
		return

	if _guarding and _resolved_guard != "":
		if _resolved_guard != _animation_state:
			_animation_state = _resolved_guard
			animation_player.play(_resolved_guard, BLEND_TIME)
		return

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var state := _resolved_idle
	if not is_on_floor():
		state = _resolved_jump
	elif planar_speed > RUN_SPEED * 0.7:
		state = _resolved_sprint
	elif planar_speed > 0.4:
		state = _resolved_walk
	elif _night and _resolved_idle_torch != "":
		state = _resolved_idle_torch
	if state != "" and animation_player != null:
		if state != _animation_state:
			_animation_state = state
			animation_player.play(state, BLEND_TIME)
		if state == _resolved_walk:
			animation_player.speed_scale = clampf(planar_speed / WALK_SPEED, 0.6, 1.6)
		elif state == _resolved_sprint:
			animation_player.speed_scale = clampf(planar_speed / RUN_SPEED, 0.8, 1.3)
		else:
			animation_player.speed_scale = 1.0
	elif animation_player == null:
		model.position.y = sin(float(Time.get_ticks_msec()) * 0.004) * 0.02


func set_night(is_night: bool) -> void:
	_night = is_night
	if torch != null:
		torch.visible = is_night


func _update_camera(delta: float) -> void:
	if camera == null or camera_pitch == null:
		return
	var pivot := camera_pitch.get_parent() as Node3D
	var desired := camera_pitch.global_transform * Vector3(0, 0, CAMERA_DISTANCE)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(pivot.global_position, desired)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	var final_position := desired
	if not hit.is_empty():
		final_position = pivot.global_position + (hit.position - pivot.global_position) * 0.85
	var target := final_position + Vector3(0, -_land_dip, 0)
	if _camera_smooth_pos == Vector3.INF:
		_camera_smooth_pos = target
	else:
		_camera_smooth_pos = _camera_smooth_pos.lerp(target, 1.0 - exp(-CAMERA_SMOOTH * delta))
	camera.global_position = _camera_smooth_pos + _shake_offset()
	_land_dip = move_toward(_land_dip, 0.0, LAND_DIP_DECAY * delta)
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var sprinting := Input.is_action_pressed("sprint") and planar_speed > WALK_SPEED
	var fov_target := FOV_SPRINT if sprinting else FOV_WALK
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-FOV_LERP * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := event as InputEventMouseMotion
			camera_yaw.rotation.y -= motion.relative.x * MOUSE_SENSITIVITY
			_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, MIN_PITCH, MAX_PITCH)
			camera_pitch.rotation.x = _pitch
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			# Con un menu abierto el raton esta suelto a proposito: capturarlo seria
			# quitarle el puntero al panel que esta delante.
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _capture_blocked:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_web_elapsed += delta
	if _web_elapsed < 0.25:
		return
	_web_elapsed = 0.0
	_push_web_state()


func _init_web_bridge() -> void:
	if not OS.has_feature("web"):
		return
	_spawn_position = global_position
	var window := JavaScriptBridge.get_interface("window")
	window.eval(
		"window.__rito = {x:0, y:0, z:0, fps:0, ready:false, moved:0, draws:0, tris:0, variant:0, hp:0, weapon:0, kills:0, alive:true, weapon_name:\"gladius\", dog_state:\"NONE\", dog_dist:0, arsenal:0, xp:0, level:1, coins:0, mission:\"\", streak:0};",
		true)


func _push_web_state() -> void:
	if not OS.has_feature("web"):
		return
	var window := JavaScriptBridge.get_interface("window")
	window.eval(
		"window.__rito.x = %.3f; window.__rito.y = %.3f; window.__rito.z = %.3f;"
		% [global_position.x, global_position.y, global_position.z], true)
	window.eval("window.__rito.fps = %.1f;" % Engine.get_frames_per_second(), true)
	window.eval("window.__rito.moved = %.3f;" % _spawn_position.distance_to(global_position), true)
	window.eval(
		"window.__rito.draws = %d; window.__rito.tris = %d; window.__rito.variant = %d;" % [
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			DevVariantsScript.current()], true)
	var combat := get_node_or_null("Combat")
	var arsenal := get_node_or_null("../Arsenal")
	window.eval(
		"window.__rito.hp = %.1f; window.__rito.weapon = %d; window.__rito.kills = %d; window.__rito.alive = %s; window.__rito.weapon_name = \"%s\"; window.__rito.dog_state = \"%s\"; window.__rito.dog_dist = %.2f; window.__rito.arsenal = %d;" % [
			combatant.health if combatant != null else 0.0,
			combat.weapon_index if combat != null else 0,
			combat.kills if combat != null else 0,
			"true" if is_alive() else "false",
			combat.call("current_weapon_name") if combat != null else "gladius",
			str(dog.get("state")) if dog != null and is_instance_valid(dog) else "NONE",
			global_position.distance_to(dog.global_position) if dog != null and is_instance_valid(dog) else 0.0,
			1 if arsenal != null and bool(arsenal.call("is_open")) else 0], true)
	# Progresión y misión actuales: el MissionSystem vive junto a Rito en main
	# ("Missions"); sin él (tests sin main) el puente arranca en cero.
	var misiones := get_node_or_null("../Missions")
	var xp_actual := 0
	var nivel_actual := 1
	var monedas_actuales := 0
	var mision_actual := ""
	var racha_actual := 0
	if misiones != null:
		xp_actual = int(misiones.get("xp"))
		nivel_actual = int(misiones.get("level"))
		monedas_actuales = int(misiones.get("coins"))
		racha_actual = int(misiones.get("best_streak"))
		if bool(misiones.call("is_mission_active")):
			var activa: Dictionary = misiones.get("_active") as Dictionary
			mision_actual = str(activa.get("id", ""))
	window.eval(
		"window.__rito.xp = %d; window.__rito.level = %d; window.__rito.coins = %d; window.__rito.mission = \"%s\"; window.__rito.streak = %d;" % [
			xp_actual, nivel_actual, monedas_actuales, mision_actual, racha_actual], true)
	if not _web_ready:
		_web_ready = true
		window.eval("window.__rito.ready = true;", true)


func set_spawn(position: Vector3) -> void:
	_spawn_point = position
	_spawn_position = position


func _resolve_animation(candidates: Array) -> String:
	if animation_player == null:
		return ""
	for candidate_name in candidates:
		if animation_player.has_animation(candidate_name):
			return candidate_name
	return ""


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func play_one_shot(name: String, lock_seconds: float, priority: int, speed: float = 1.0) -> void:
	if animation_player == null or name == "":
		return
	if not animation_player.has_animation(name):
		return
	if priority < _lock_priority and is_locked():
		return
	_lock_priority = priority
	_lock_until = _now() + lock_seconds
	_animation_state = name
	animation_player.speed_scale = speed
	animation_player.play(name, ONE_SHOT_BLEND)


func is_locked() -> bool:
	return _now() < _lock_until


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func bind_combatant(p_combatant: Node, p_spawn_point: Vector3) -> void:
	combatant = p_combatant
	_spawn_point = p_spawn_point
	combatant.died.connect(_on_died)
	combatant.damaged.connect(_on_damaged)


## El moloso, para que el puente web pueda decir cuanto esta lejos.
func bind_dog(p_dog: Node3D) -> void:
	dog = p_dog


func bind_slave(p_slave: Node3D) -> void:
	slave = p_slave


## El menu de arsenal suelta el raton: con el abierto, Rito no lo vuelve a capturar.
func set_capture_blocked(blocked: bool) -> void:
	_capture_blocked = blocked


func is_alive() -> bool:
	return not _dead


func respawn(at: Vector3) -> void:
	_release_ragdoll()
	global_position = at
	velocity = Vector3.ZERO
	_push_velocity = Vector3.ZERO
	_dead = false
	_was_on_floor = true
	_coyote_until = 0.0
	_jump_buffered_at = -1.0
	_land_dip = 0.0
	_camera_smooth_pos = Vector3.INF
	if combatant != null:
		combatant.heal_full(2.0)
	_lock_priority = 0
	_lock_until = 0.0
	_animation_state = ""
	_reset_guard_state()
	_restore_camera_height()


## Apaga la fisica del corpse y borra los cuerpos rigidos: al reaparecer, Rito vuelve a
## estar en pie y andando, no con el esqueleto tirado en el suelo.
func _release_ragdoll() -> void:
	if _ragdoll_bones.is_empty():
		return
	var skeleton := _find_skeleton(model)
	if skeleton != null:
		RagdollScript.deactivate(skeleton)
		skeleton.reset_bone_poses()
	for node in _ragdoll_bones:
		var bone := node as PhysicalBone3D
		if bone != null and is_instance_valid(bone):
			bone.queue_free()
	_ragdoll_bones = []
	_ragdoll_active = false
	_ragdoll_timer = -1.0


## La fisica toma el relevo de la animacion de muerte. Los cuerpos se montan sobre la pose
## ACTUAL (el corpse ya esta tumbado a los 1,5 s de muerte) y la animacion se para sin
## resetear: stop() a secas devuelve el esqueleto a la pose de reposo y el corpse se
## levanta del suelo.
func _start_ragdoll() -> void:
	var skeleton := _find_skeleton(model)
	if skeleton == null:
		return
	_ragdoll_bones = RagdollScript.attach(skeleton)
	if animation_player != null:
		animation_player.stop(true)
	RagdollScript.activate(skeleton, _ragdoll_bones)
	_ragdoll_active = true
	_camera_to_corpse()


func _camera_to_corpse() -> void:
	var pivot := camera_pitch.get_parent() as Node3D
	if pivot != null:
		pivot.position.y = CORPSE_CAMERA_HEIGHT


func _restore_camera_height() -> void:
	var pivot := camera_pitch.get_parent() as Node3D
	if pivot != null:
		pivot.position.y = CAMERA_HEIGHT


func bind_feel(p_feel: Node) -> void:
	feel = p_feel


func _sfx() -> Sfx:
	return get_tree().get_first_node_in_group("sfx") as Sfx


func _feel() -> Feel:
	if feel != null and is_instance_valid(feel):
		return feel as Feel
	return get_tree().get_first_node_in_group("feel") as Feel


## Pasos mientras Rito anda: acumula distancia horizontal y suelta un paso cada X metros.
func _update_steps(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or planar < 0.5:
		return
	_step_accum += planar * delta
	if _step_accum < STEP_DISTANCE:
		return
	_step_accum = 0.0
	var sfx := _sfx()
	if sfx != null:
		sfx.play("step", global_position, -16.0)


func _shake_offset() -> Vector3:
	var feel_node := _feel()
	if feel_node == null:
		return Vector3.ZERO
	return feel_node.camera_offset()


## La direccion de entrada en el mundo. La esquiva la usa: si no hay entrada, sale hacia
## atras.
func input_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if input.length() < 0.05:
		return Vector3.ZERO
	var basis_yaw := camera_yaw.global_transform.basis
	return (basis_yaw * Vector3(input.x, 0.0, -input.y)).normalized()


## El empujon fisico: el bandido que empuja mete a Rito en el aire. Se suma a la
## velocidad y se desvanece solo.
func apply_push(direction: Vector3, strength: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		return
	_push_velocity += flat.normalized() * strength


## La esquiva: el clip Roll del pack, un impulso en la direccion de entrada, 0,35 s de
## invulnerabilidad y 0,8 s de enfriamiento.
func try_dodge(direction: Vector3) -> bool:
	if not is_alive() or is_locked():
		return false
	if _now() < _dodge_ready_at:
		return false
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.05:
		# Sin entrada, la esquiva sale hacia atras: model.basis.z es el frente del
		# personaje, porque el modelo esta girado media vuelta.
		flat = -model.global_transform.basis.z
	flat = flat.normalized()
	_dodge_ready_at = _now() + DODGE_COOLDOWN
	velocity.x = flat.x * DODGE_SPEED
	velocity.z = flat.z * DODGE_SPEED
	if combatant != null:
		combatant.make_invulnerable(DODGE_INVULNERABLE)
	if _resolved_roll != "" and animation_player != null:
		var clip_length := animation_player.get_animation(_resolved_roll).length / DODGE_ANIM_SPEED
		play_one_shot(_resolved_roll, clip_length, PRIORITY_ATTACK, DODGE_ANIM_SPEED)
	var sfx := _sfx()
	if sfx != null:
		sfx.play("dodge", global_position, -10.0)
	var feel_node := _feel()
	if feel_node != null:
		feel_node.shake(0.10, 0.15)
	return true


func is_dodge_ready() -> bool:
	return _now() >= _dodge_ready_at


## La guardia se levanta con Q mantenido. No se puede levantar muerto, durante un
## ataque bloqueado ni mientras dura la ruptura.
func set_guarding(value: bool) -> void:
	if value:
		if not is_alive() or is_locked() or _now() < _guard_lock_until:
			return
		_guarding = true
		return
	_guarding = false
	_parry_until = 0.0


## Pulsa Q: levanta la guardia y abre la ventana de parry. La ventana no se acumula:
## cada pulsacion reinicia los 0,20 s.
func try_parry() -> bool:
	set_guarding(true)
	if not _guarding:
		return false
	_parry_until = _now() + PARRY_WINDOW
	return true


func is_guarding() -> bool:
	return _guarding


func guard_value() -> float:
	return _guard


func is_riposte_ready() -> bool:
	return _now() <= _riposte_until


## Devuelve 1,75 si el golpe consume el contraataque; 1,0 en cualquier otro caso.
func consume_riposte() -> float:
	if _now() > _riposte_until:
		return 1.0
	_riposte_until = 0.0
	riposte_changed.emit(false)
	return RIPOSTE_MULT


## El ataque enemigo pasa por aqui cuando el cuerpo es Rito. Devuelve true si la
## guardia consumio el golpe; false deja que AttackVolume aplique el dano normal.
func receive_attack(amount: float, source: Node3D) -> bool:
	if not is_alive() or not _guarding or source == null or combatant == null:
		return false
	var to_source := source.global_position - global_position
	to_source.y = 0.0
	var forward := -model.global_transform.basis.z
	forward.y = 0.0
	if to_source.length() < 0.01 or forward.length() < 0.01:
		return false
	if forward.normalized().dot(to_source.normalized()) < 0.15:
		return false

	# El parry se comprueba antes del coste de guardia: un acierto no gasta barra.
	if _now() <= _parry_until:
		_parry_until = 0.0
		_riposte_until = _now() + RIPOSTE_WINDOW
		if source.has_method("stagger"):
			source.call("stagger", PARRY_STAGGER)
		parried.emit()
		riposte_changed.emit(true)
		return true

	var cost := amount * GUARD_COST_MULT
	if cost >= _guard:
		_guard = GUARD_REFRACTORY_REFILL
		_guarding = false
		_guard_lock_until = _now() + GUARD_BREAK_LOCK
		_guard_regen_at = _now() + GUARD_REGEN_DELAY
		combatant.take_damage(amount * GUARD_BREAK_DAMAGE, source.global_position)
		guard_changed.emit(_guard, GUARD_MAX)
		guard_broken.emit()
		play_one_shot(_resolved_hit_strong, GUARD_BREAK_STUN, PRIORITY_HIT)
		return true

	_guard = maxf(_guard - cost, 0.0)
	_guard_regen_at = _now() + GUARD_REGEN_DELAY
	combatant.take_damage(amount * (1.0 - GUARD_DAMAGE_REDUCTION), source.global_position)
	guard_changed.emit(_guard, GUARD_MAX)
	return true


## La barra se regenera sola tras el retardo, nunca mientras se mantiene la guardia.
func _update_guard(delta: float) -> void:
	if _guarding or _guard >= GUARD_MAX or _now() < _guard_regen_at:
		return
	_guard = minf(_guard + GUARD_REGEN * delta, GUARD_MAX)
	guard_changed.emit(_guard, GUARD_MAX)


func _reset_guard_state() -> void:
	_guard = GUARD_MAX
	_guarding = false
	_guard_regen_at = 0.0
	_guard_lock_until = 0.0
	_parry_until = 0.0
	if _riposte_until > 0.0:
		_riposte_until = 0.0
		riposte_changed.emit(false)
	guard_changed.emit(_guard, GUARD_MAX)


func is_ragdoll_active() -> bool:
	return _ragdoll_active


func _on_damaged(amount: float, _source_position: Vector3) -> void:
	if _dead:
		return
	var sfx := _sfx()
	if sfx != null:
		sfx.play("hurt", global_position, -6.0)
	var feel_node := _feel()
	if feel_node != null:
		feel_node.hit_stop(0.05)
		feel_node.shake(0.30, 0.22)
	# Un golpe fuerte se nota en la cabeza: el pecho solo para golpes menores.
	if amount >= STRONG_HIT and _resolved_hit_strong != "":
		play_one_shot(_resolved_hit_strong, 0.4, PRIORITY_HIT)
	else:
		play_one_shot(_resolved_hit, 0.35, PRIORITY_HIT)


func _on_died(_source_position: Vector3) -> void:
	_dead = true
	_reset_guard_state()
	_respawn_timer = RESPAWN_DELAY
	_ragdoll_timer = RAGDOLL_DELAY
	play_one_shot(_resolved_death, RESPAWN_DELAY, PRIORITY_DYING)
	var sfx := _sfx()
	if sfx != null:
		sfx.play("death", global_position)
	var feel_node := _feel()
	if feel_node != null:
		feel_node.hit_stop(0.12, Feel.IMPACT_TYPE_STRONG)
		feel_node.shake(0.55, 0.60)
	died.emit()
