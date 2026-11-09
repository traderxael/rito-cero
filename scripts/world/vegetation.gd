extends Node3D

const DevVariantsScript := preload("res://scripts/dev/variants.gd")

const MeshFactoryScript := preload("res://scripts/world/mesh_factory.gd")

const CELL_SIZE := 32.0
const TREE_RADIUS_CELLS := 3
const WHEAT_RADIUS_CELLS := 1
const OLIVES_PER_CELL := 6
const CYPRESSES_PER_CELL := 5
const ROCKS_PER_CELL := 4
const WHEAT_PER_CELL := 130
const MAX_SLOPE := 2.2

var terrain: Terrain3D
var player: Node3D

var _data: Object
var _last_cell := Vector2i(999999, 999999)
var _olive: MultiMeshInstance3D
var _cypress: MultiMeshInstance3D
var _wheat: MultiMeshInstance3D
var _rocks: Array[MultiMeshInstance3D] = []


func setup(world_terrain: Terrain3D, target: Node3D) -> void:
	terrain = world_terrain
	player = target
	_data = terrain.get_data()

	if not DevVariantsScript.vegetation_enabled(DevVariantsScript.current()):
		return

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	_olive = _make_instance("Olive", MeshFactoryScript.make_olive(), material)
	_cypress = _make_instance("Cypress", MeshFactoryScript.make_cypress(), material)
	_wheat = _make_instance("Wheat", MeshFactoryScript.make_wheat_tuft(), material)

	var rock_material: Material = load("res://demo/assets/materials/M_rock23_tp.tres")
	for rock_scene in ["RockA", "RockB", "RockC"]:
		var mesh := _load_rock_mesh("res://demo/assets/models/%s.glb" % rock_scene)
		_rocks.append(_make_instance(rock_scene, mesh, rock_material))

	_rebuild()


func _make_instance(instance_name: String, mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.name = instance_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _load_rock_mesh(path: String) -> Mesh:
	var packed: PackedScene = load(path)
	var instance := packed.instantiate()
	var mesh_instance := _find_mesh_instance(instance)
	var mesh := mesh_instance.mesh
	instance.free()
	return mesh


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found != null:
			return found
	return null


func _process(_delta: float) -> void:
	if player == null or _data == null:
		return
	var cell := Vector2i(
		floori(player.global_position.x / CELL_SIZE),
		floori(player.global_position.z / CELL_SIZE))
	if cell != _last_cell:
		_last_cell = cell
		_rebuild()


func _rebuild() -> void:
	var center := _last_cell
	var olives: Array[Transform3D] = []
	var cypresses: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var rocks_b: Array[Transform3D] = []
	var rocks_c: Array[Transform3D] = []
	var wheat: Array[Transform3D] = []

	for dz in range(-TREE_RADIUS_CELLS, TREE_RADIUS_CELLS + 1):
		for dx in range(-TREE_RADIUS_CELLS, TREE_RADIUS_CELLS + 1):
			var cell_x := center.x + dx
			var cell_z := center.y + dz
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector2i(cell_x, cell_z))
			var distance := Vector2(dx, dz).length()
			var falloff := clampf(1.25 - distance * 0.16, 0.3, 1.25)

			_place(rng, cell_x, cell_z, int(round(OLIVES_PER_CELL * falloff)), olives, Vector3.ONE, 0.85, 1.35)
			_place(rng, cell_x, cell_z, int(round(CYPRESSES_PER_CELL * falloff)), cypresses, Vector3.ONE, 0.8, 1.25)

			var rock_count := int(round(ROCKS_PER_CELL * falloff))
			for i in rock_count:
				var bucket := i % 3
				var target := rocks
				if bucket == 1:
					target = rocks_b
				elif bucket == 2:
					target = rocks_c
				_place_one(rng, cell_x, cell_z, target, 0.5, 1.6)

			if absi(dx) <= WHEAT_RADIUS_CELLS and absi(dz) <= WHEAT_RADIUS_CELLS:
				_place(rng, cell_x, cell_z, WHEAT_PER_CELL, wheat, Vector3.ONE, 0.8, 1.25)

	_apply(_olive, olives)
	_apply(_cypress, cypresses)
	_apply(_wheat, wheat)
	_apply(_rocks[0], rocks)
	_apply(_rocks[1], rocks_b)
	_apply(_rocks[2], rocks_c)


func _place(
		rng: RandomNumberGenerator,
		cell_x: int,
		cell_z: int,
		count: int,
		target: Array[Transform3D],
		_scale: Vector3,
		min_scale: float,
		max_scale: float) -> void:
	for i in count:
		_place_one(rng, cell_x, cell_z, target, min_scale, max_scale)


func _place_one(
		rng: RandomNumberGenerator,
		cell_x: int,
		cell_z: int,
		target: Array[Transform3D],
		min_scale: float,
		max_scale: float) -> void:
	var position := Vector3(
		cell_x * CELL_SIZE + rng.randf() * CELL_SIZE,
		0.0,
		cell_z * CELL_SIZE + rng.randf() * CELL_SIZE)
	var height: float = _data.get_height(position)
	if is_nan(height):
		return
	var slope: float = _data.get_height(position + Vector3(3, 0, 3))
	if is_nan(slope) or absf(slope - height) > MAX_SLOPE:
		return
	var uniform_scale := rng.randf_range(min_scale, max_scale)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * uniform_scale)
	target.append(Transform3D(basis, Vector3(position.x, height - 0.12, position.z)))


func _apply(instance: MultiMeshInstance3D, transforms: Array[Transform3D]) -> void:
	var multimesh := instance.multimesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
