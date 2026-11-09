extends Node3D

const DevVariantsScript := preload("res://scripts/dev/variants.gd")

const TERRAIN_DATA_DIR := "res://demo/data"
const TERRAIN_ASSETS := "res://assets/roman_terrain_assets.tres"
const TERRAIN_MATERIAL := "res://assets/roman_terrain_material.tres"
const ENVIRONMENT_SCENE := "res://demo/components/Environment.tscn"

const SPAWN_CANDIDATES := [
	Vector3(223, 0, -1833),
	Vector3(256, 0, -1792),
	Vector3(128, 0, -1920),
	Vector3(384, 0, -1856),
	Vector3(512, 0, -1920),
	Vector3(128, 0, -1200),
	Vector3(256, 0, -1000),
	Vector3(384, 0, -1100),
	Vector3(512, 0, -700),
	Vector3(300, 0, -300),
]

var terrain: Terrain3D
var spawn_point := Vector3.ZERO
var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var world_environment: WorldEnvironment


func _ready() -> void:
	_build_environment()
	_apply_render_scale()


func _apply_render_scale() -> void:
	var scale := DevVariantsScript.render_scale(DevVariantsScript.current())
	if not is_equal_approx(scale, 0.75):
		get_viewport().scaling_3d_scale = scale


func _build_environment() -> void:
	var environment: Node3D = load(ENVIRONMENT_SCENE).instantiate()
	environment.name = "Environment"
	add_child(environment)

	var light: DirectionalLight3D = environment.get_node("DirectionalLight3D")
	sun = light
	light.shadow_enabled = false
	light.light_color = Color(1.0, 0.93, 0.78)
	light.light_energy = 1.15
	light.rotation_degrees = Vector3(-36.0, 128.0, 0.0)

	world_environment = environment.get_node("WorldEnvironment")
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.27, 0.40, 0.60)
	sky_material.sky_horizon_color = Color(0.80, 0.74, 0.61)
	sky_material.ground_horizon_color = Color(0.60, 0.53, 0.42)
	sky_material.ground_bottom_color = Color(0.24, 0.21, 0.17)
	sky_material.ground_curve = 0.13
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = sky_material
	world_environment.environment.sky = sky
	world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_environment.environment.ambient_light_sky_contribution = 0.85
	world_environment.environment.fog_enabled = true
	world_environment.environment.fog_light_color = Color(0.80, 0.76, 0.65)
	world_environment.environment.fog_light_energy = 1.0
	world_environment.environment.fog_density = 0.0022
	world_environment.environment.fog_sky_affect = 0.0
	world_environment.environment.fog_aerial_perspective = 0.4


func _build_terrain(player: Node3D) -> void:
	var material: Terrain3DMaterial = load(TERRAIN_MATERIAL)
	var variant := DevVariantsScript.current()
	if DevVariantsScript.use_light_shader(variant):
		material = material.duplicate()
		material.shader_override_enabled = true
		material.shader_override = load(DevVariantsScript.LIGHT_SHADER_PATH)
		material.projection_enabled = false

	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.data_directory = TERRAIN_DATA_DIR
	terrain.assets = load(TERRAIN_ASSETS)
	terrain.material = material
	terrain.ocean_enabled = false
	terrain.mesh_size = 32 if DevVariantsScript.use_light_shader(variant) else 64
	terrain.tessellation_level = 0 if DevVariantsScript.use_light_shader(variant) else 2
	terrain.collision_mask = 3
	terrain.collision_layer = 1
	terrain.cast_shadows = RenderingServer.SHADOW_CASTING_SETTING_OFF
	terrain.clipmap_target = player
	terrain.collision_target = player
	add_child(terrain)


func attach_player(player: Node3D) -> void:
	_build_terrain(player)
	terrain.set_clipmap_target(player)
	terrain.set_collision_target(player)
	terrain.set_light_target(get_node("Environment/DirectionalLight3D"))

	await get_tree().process_frame
	await get_tree().process_frame

	spawn_point = _find_spawn()
	player.global_position = spawn_point
	if player.has_method("set_spawn"):
		player.call("set_spawn", spawn_point)


func _find_spawn() -> Vector3:
	var data := terrain.get_data()
	var best := Vector3.ZERO
	var best_score := -INF
	for candidate: Vector3 in SPAWN_CANDIDATES:
		var height: float = data.get_height(candidate)
		if is_nan(height):
			continue
		var roughness := 0.0
		var samples := 0
		for offset in [Vector3(10, 0, 0), Vector3(-10, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, -10)]:
			var neighbour: float = data.get_height(candidate + offset)
			if is_nan(neighbour):
				continue
			roughness += absf(neighbour - height)
			samples += 1
		if samples == 0:
			continue
		var score := -roughness
		if height < 25.0 or height > 145.0:
			score -= 600.0
		else:
			score += 120.0
		if score > best_score:
			best_score = score
			best = Vector3(candidate.x, height + 0.15, candidate.z)
	return best


func height_at(world_position: Vector3) -> float:
	return terrain.get_data().get_height(world_position)
