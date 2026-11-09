extends RefCounted

const SKIN := Color(0.76, 0.55, 0.37)
const SKIN_SHADOW := Color(0.66, 0.45, 0.29)
const TUNIC := Color(0.81, 0.73, 0.57)
const TUNIC_SHADE := Color(0.69, 0.60, 0.44)
const PURPLE := Color(0.33, 0.16, 0.42)
const LEATHER := Color(0.40, 0.27, 0.16)
const HAIR := Color(0.21, 0.14, 0.10)
const LAUREL := Color(0.40, 0.52, 0.22)

const BONE_SPINE := "DEF-spine.001"
const BONE_HEAD := "DEF-head"
const BONE_FOOT_L := "DEF-foot.L"
const BONE_FOOT_R := "DEF-foot.R"


static func build(skeleton: Skeleton3D, face_texture: Texture2D) -> void:
	if skeleton == null:
		return
	_tunic(skeleton)
	_sandals(skeleton)
	_hair(skeleton)
	if face_texture != null:
		_face(skeleton, face_texture)


static func recolor_skin(root: Node) -> void:
	for node in _descendants(root):
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			for surface in mesh_instance.mesh.get_surface_count():
				var material := StandardMaterial3D.new()
				material.roughness = 0.85
				material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				var original := mesh_instance.mesh.surface_get_material(surface)
				if original != null:
					var color: Color = original.albedo_color
					if color.b > color.r:
						material.albedo_color = SKIN_SHADOW
					else:
						material.albedo_color = SKIN
				else:
					material.albedo_color = SKIN
				mesh_instance.set_surface_override_material(surface, material)


static func _tunic(skeleton: Skeleton3D) -> void:
	var attachment := _attachment(skeleton, BONE_SPINE)
	if attachment == null:
		return

	var tunic := CylinderMesh.new()
	tunic.top_radius = 0.19
	tunic.bottom_radius = 0.36
	tunic.height = 0.60
	tunic.radial_segments = 12
	tunic.rings = 1
	_add_mesh(attachment, tunic, Vector3(0, -0.30, 0), TUNIC)

	var hem := CylinderMesh.new()
	hem.top_radius = 0.365
	hem.bottom_radius = 0.375
	hem.height = 0.10
	hem.radial_segments = 12
	hem.rings = 1
	_add_mesh(attachment, hem, Vector3(0, -0.57, 0), PURPLE)

	var belt := TorusMesh.new()
	belt.inner_radius = 0.17
	belt.outer_radius = 0.215
	belt.rings = 12
	belt.ring_segments = 6
	_add_mesh(attachment, belt, Vector3(0, -0.01, 0), LEATHER)


static func _sandals(skeleton: Skeleton3D) -> void:
	for bone_name in [BONE_FOOT_L, BONE_FOOT_R]:
		var attachment := _attachment(skeleton, bone_name)
		if attachment == null:
			continue
		var sole := BoxMesh.new()
		sole.size = Vector3(0.13, 0.045, 0.27)
		_add_mesh(attachment, sole, Vector3(0, -0.085, 0.045), LEATHER)


static func _hair(skeleton: Skeleton3D) -> void:
	var attachment := _attachment(skeleton, BONE_HEAD)
	if attachment == null:
		return

	var cap := SphereMesh.new()
	cap.radius = 0.108
	cap.height = 0.14
	cap.radial_segments = 10
	cap.rings = 6
	_add_mesh(attachment, cap, Vector3(0, 0.185, -0.012), HAIR)

	var beard := SphereMesh.new()
	beard.radius = 0.062
	beard.height = 0.11
	beard.radial_segments = 8
	beard.rings = 5
	_add_mesh(attachment, beard, Vector3(0, 0.055, 0.072), HAIR)

	var laurel := TorusMesh.new()
	laurel.inner_radius = 0.085
	laurel.outer_radius = 0.125
	laurel.rings = 12
	laurel.ring_segments = 6
	var laurel_mesh := MeshInstance3D.new()
	laurel_mesh.mesh = laurel
	laurel_mesh.material_override = _material(LAUREL)
	laurel_mesh.position = Vector3(0, 0.165, 0)
	laurel_mesh.rotation_degrees = Vector3(14, 0, 0)
	attachment.add_child(laurel_mesh)


static func _face(skeleton: Skeleton3D, face_texture: Texture2D) -> void:
	var attachment := _attachment(skeleton, BONE_HEAD)
	if attachment == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(0.17, 0.17)
	var material := StandardMaterial3D.new()
	material.albedo_texture = face_texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_color = Color(1, 1, 1, 1)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(0, 0.095, 0.112)
	attachment.add_child(mesh_instance)


static func add_torch(skeleton: Skeleton3D) -> Node3D:
	# Izquierda porque la derecha la ocupan las armas: si compartieran DEF-hand.R, el
	# BoneAttachment de la antorcha y el del gladius se secuestrarian el uno al otro.
	var attachment := _attachment(skeleton, "DEF-hand.L")
	if attachment == null:
		return null

	var root := Node3D.new()
	root.name = "Torch"
	attachment.add_child(root)
	root.position = Vector3(0, -0.06, 0.06)
	root.rotation_degrees = Vector3(-72, 0, 12)

	var stick := CylinderMesh.new()
	stick.top_radius = 0.014
	stick.bottom_radius = 0.02
	stick.height = 0.46
	stick.radial_segments = 5
	stick.rings = 1
	_add_mesh(root, stick, Vector3(0, 0.12, 0), LEATHER)

	var flame := SphereMesh.new()
	flame.radius = 0.055
	flame.height = 0.13
	flame.radial_segments = 6
	flame.rings = 4
	var flame_mesh := MeshInstance3D.new()
	flame_mesh.mesh = flame
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color(1.0, 0.58, 0.16)
	flame_material.emission_enabled = true
	flame_material.emission = Color(1.0, 0.62, 0.22)
	flame_material.emission_energy_multiplier = 3.0
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mesh.material_override = flame_material
	flame_mesh.position = Vector3(0, 0.38, 0)
	root.add_child(flame_mesh)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.66, 0.32)
	light.light_energy = 2.4
	light.omni_range = 6.0
	light.shadow_enabled = false
	light.position = Vector3(0, 0.38, 0)
	root.add_child(light)

	root.visible = false
	return root


static func _attachment(skeleton: Skeleton3D, bone_name: String) -> BoneAttachment3D:
	if skeleton.find_bone(bone_name) == -1:
		return null
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	return attachment


static func _add_mesh(parent: Node3D, mesh: Mesh, offset: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	mesh_instance.position = offset
	parent.add_child(mesh_instance)


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


static func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result
