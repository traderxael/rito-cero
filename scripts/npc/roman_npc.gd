extends CharacterBody3D

## NPC romano que patrulla entre puntos sobre el terreno. Sin NavMesh: el horneado de
## navegacion en runtime es sincrono y en el export web sin hilos congelaria el juego.
## La evitancia es un raycast frontal y la decision se toma cada pocos segundos.

const MeshFactoryScript := preload("res://scripts/world/mesh_factory.gd")

const SPEED := 1.7
const GRAVITY := 26.0
const DECISION_INTERVAL := 0.6
const WAYPOINT_RADIUS := 1.6
const OBSTACLE_DISTANCE := 3.5

var _waypoints: Array[Vector3] = []
var _index := 0
var _decision_timer := 0.0
var _mesh: MeshInstance3D


func setup(data, center: Vector3, angle: float) -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.5

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0, 0.85, 0)
	add_child(shape)

	_mesh = MeshInstance3D.new()
	_mesh.name = "Body"
	_mesh.mesh = MeshFactoryScript.make_roman_npc()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mesh.material_override = material
	add_child(_mesh)

	_build_waypoints(data, center, angle)
	global_position = center
	_index = 0


func _build_waypoints(data, center: Vector3, angle: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3(center.x, angle, center.z))
	for i in 4:
		var candidate := center + Vector3(
			rng.randf_range(-14.0, 14.0),
			0.0,
			rng.randf_range(-14.0, 14.0))
		var height: float = data.get_height(candidate)
		if is_nan(height):
			continue
		_waypoints.append(Vector3(candidate.x, height, candidate.z))
	if _waypoints.is_empty():
		_waypoints.append(center)


func _physics_process(delta: float) -> void:
	if _waypoints.is_empty():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var target := _waypoints[_index]
	var to_target := target - global_position
	to_target.y = 0.0

	_decision_timer -= delta
	if to_target.length() < WAYPOINT_RADIUS:
		_index = (_index + 1) % _waypoints.size()
		target = _waypoints[_index]
		to_target = target - global_position
		to_target.y = 0.0

	var direction := to_target.normalized()
	if direction.length() > 0.01 and _decision_timer <= 0.0:
		_decision_timer = DECISION_INTERVAL
		if _obstacle_ahead(direction):
			direction = direction.rotated(Vector3.UP, 1.2)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * SPEED, 6.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	if direction.length() > 0.01 and _mesh != null:
		var target_angle := atan2(direction.x, direction.z)
		_mesh.rotation.y = lerp_angle(_mesh.rotation.y, target_angle, 1.0 - exp(-8.0 * delta))


func _obstacle_ahead(direction: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.9, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * OBSTACLE_DISTANCE)
	query.collision_mask = 1
	return not space.intersect_ray(query).is_empty()
