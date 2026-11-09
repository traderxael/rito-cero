class_name ImpactFx
extends Node3D

## Pool de explosiones de particulas para los impactos. CPUParticles3D porque en el
## renderer gl_compatibility y en el export web es lo unico que no depende de la GPU:
## un puñado de esferas unshaded con emision, sin luces ni sombras anadidas.
##
## El pool se reutiliza: una vez apagada (one_shot cumplido) la rafaga vuelve a estar
## libre, asi que un combate largo no crea nodos sin parar.

const POOL_SIZE := 8
const NORMAL_AMOUNT := 24
const BIG_AMOUNT := 44

var _pool: Array[CPUParticles3D] = []
var _last_amount := 0


func _ready() -> void:
	add_to_group("impact_fx")
	for i in POOL_SIZE:
		var particles := CPUParticles3D.new()
		particles.name = "Burst%d" % i
		particles.amount = NORMAL_AMOUNT
		particles.lifetime = 0.45
		particles.one_shot = true
		particles.explosiveness = 0.9
		particles.direction = Vector3.UP
		particles.spread = 72.0
		particles.initial_velocity_min = 3.0
		particles.initial_velocity_max = 6.5
		particles.gravity = Vector3(0, -9.8, 0)
		particles.damping_min = 1.5
		particles.damping_max = 3.0
		particles.scale_amount_min = 0.6
		particles.scale_amount_max = 1.3
		particles.color = Color.WHITE
		particles.emitting = false
		var sphere := SphereMesh.new()
		sphere.radius = 0.045
		sphere.height = 0.09
		sphere.radial_segments = 6
		sphere.rings = 3
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color.WHITE
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 1.5
		sphere.material = material
		# En CPUParticles3D la malla va en `mesh`; draw_pass_1 solo existe en GPUParticles3D.
		particles.mesh = sphere
		add_child(particles)
		_pool.append(particles)


## big es para la baja: mas particulas y mas duracion.
func burst(at: Vector3, color: Color, big := false) -> void:
	var particles := _free_burst()
	if particles == null:
		return
	particles.global_position = at
	_last_amount = BIG_AMOUNT if big else NORMAL_AMOUNT
	particles.amount = _last_amount
	particles.lifetime = 0.65 if big else 0.45
	particles.color = color
	particles.restart()


func active_count() -> int:
	var count := 0
	for particles in _pool:
		if particles.emitting:
			count += 1
	return count


func last_burst_amount() -> int:
	return _last_amount


func _free_burst() -> CPUParticles3D:
	for particles in _pool:
		if not particles.emitting:
			return particles
	return _pool[0] if not _pool.is_empty() else null
