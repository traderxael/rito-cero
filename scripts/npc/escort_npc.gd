class_name EscortNpc
extends CharacterBody3D

## Companero de la mision de escolta: recorre una ruta de waypoints y espera al
## jugador si este se aleja demasiado. No ataca: su unica defensa es que el
## jugador la proteja. Vive en la capa 32, asi los bandidos pueden alcanzarla
## pero el jugador nunca le dispara por accidente.

const CombatantScript := preload("res://scripts/combat/combatant.gd")

const ESCORT_LAYER := 32
const ESCORT_HEALTH := 80.0
const ESCORT_SPEED := 3.5
const ARRIVE_DISTANCE := 1.0
const MAX_PLAYER_DISTANCE := 25.0
const GRAVITY := 26.0

signal arrived
signal died(source_position: Vector3)

var _player: Node3D
var _combatant: Combatant
var _model: Node3D
var _anim: AnimationPlayer
var _waypoints: Array[Vector3] = []
var _waypoint_index := 0
var state := "WALK"
var _stun_until := 0.0
var _current_anim := ""


func setup(player: Node3D, waypoints: Array[Vector3]) -> void:
	_player = player
	_waypoints = waypoints.duplicate()
	add_to_group("companions")
	collision_layer = ESCORT_LAYER
	collision_mask = 1
	floor_snap_length = 0.6

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
	_combatant.setup(ESCORT_HEALTH)
	_combatant.died.connect(func(_s): died.emit(global_position))

	_build_visual()


func _build_visual() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var instance := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.6
	body.radial_segments = 8
	instance.mesh = body
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.95, 0.88, 0.70)
	material.roughness = 0.6
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	instance.material_override = material
	_model.add_child(instance)

	var packed: PackedScene = load("res://Godot/AnimationLibrary_Godot_Standard.glb")
	var mannequin: Node3D = packed.instantiate()
	_model.add_child(mannequin)
	for child in mannequin.get_children():
		if child is AnimationPlayer:
			_anim = child as AnimationPlayer


func _physics_process(delta: float) -> void:
	if _combatant == null or not _combatant.is_alive():
		return

	if state == "STUN":
		if _now() >= _stun_until:
			state = "WALK"
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		return

	if _player == null or not is_instance_valid(_player):
		velocity.x = 0.0
		velocity.z = 0.0
		_play("Idle")
		return

	if _player.global_position.distance_to(global_position) > MAX_PLAYER_DISTANCE:
		# Espera al jugador: no avanza en la ruta sin su escolta.
		velocity.x = 0.0
		velocity.z = 0.0
		_play("Idle")
		return

	if _waypoint_index >= _waypoints.size():
		arrived.emit()
		return

	var target := _waypoints[_waypoint_index]
	var to_target := target - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance < ARRIVE_DISTANCE:
		_waypoint_index += 1
		if _waypoint_index >= _waypoints.size():
			arrived.emit()
			return
		target = _waypoints[_waypoint_index]
		to_target = target - global_position
		to_target.y = 0.0

	var direction := to_target.normalized()
	velocity.x = direction.x * ESCORT_SPEED
	velocity.z = direction.z * ESCORT_SPEED
	_face(direction)
	_play("Walk")
	_apply_gravity(delta)
	move_and_slide()


func _face(direction: Vector3) -> void:
	if _model != null and direction.length() > 0.01:
		_model.rotation.y = atan2(direction.x, direction.z)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _play(anim_name: String) -> void:
	if _anim == null or anim_name == _current_anim:
		return
	if not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.15)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
