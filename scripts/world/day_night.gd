extends Node

## Ciclo dia/noche. Mueve el sol, interpola cielo, ambiente y niebla, y le dice a Rito
## que encienda la antorcha de noche. La niebla se interpola tambien: si solo cambia
## el cielo, el paso a la noche es un salto visible.

const CYCLE_SECONDS := 600.0

const DAY_TOP := Color(0.27, 0.40, 0.60)
const NIGHT_TOP := Color(0.03, 0.05, 0.12)
const DAY_HORIZON := Color(0.80, 0.74, 0.61)
const NIGHT_HORIZON := Color(0.09, 0.11, 0.20)
const DUSK_HORIZON := Color(0.86, 0.45, 0.24)
const DAY_LIGHT := Color(1.0, 0.95, 0.84)
const NIGHT_LIGHT := Color(0.42, 0.52, 0.78)
const DUSK_LIGHT := Color(1.0, 0.58, 0.30)
const DAY_FOG := Color(0.80, 0.76, 0.65)
const NIGHT_FOG := Color(0.12, 0.15, 0.24)

var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var environment: Environment
var player: Node3D

var _time := 0.28
var _was_night := false
var _last_day_amount := 1.0
var _amb_timer := 0.0


func setup(directional_light: DirectionalLight3D, sky: ProceduralSkyMaterial, env: Environment, target: Node3D) -> void:
	sun = directional_light
	sky_material = sky
	environment = env
	player = target
	_apply()


func _process(delta: float) -> void:
	_time = fmod(_time + delta / CYCLE_SECONDS, 1.0)
	_apply()
	# El volumen del viento ambiente se actualiza una vez por segundo, no cada frame.
	_amb_timer -= delta
	if _amb_timer <= 0.0:
		_amb_timer = 1.0
		var sfx := get_tree().get_first_node_in_group("sfx")
		if sfx != null:
			sfx.call("set_ambience", _last_day_amount)


func _apply() -> void:
	var elevation := sin(_time * TAU)
	var day_amount := clampf((elevation + 0.18) / 0.55, 0.0, 1.0)
	_last_day_amount = day_amount
	var dusk_amount := clampf(1.0 - absf(elevation) / 0.32, 0.0, 1.0)
	var is_night := elevation < -0.05

	if sun != null:
		sun.rotation_degrees = Vector3(-(90.0 - elevation * 72.0), _time * 360.0, 0.0)
		sun.light_color = NIGHT_LIGHT.lerp(DAY_LIGHT, day_amount).lerp(DUSK_LIGHT, dusk_amount * 0.75)
		sun.light_energy = lerpf(0.16, 1.15, day_amount)

	if sky_material != null:
		sky_material.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, day_amount)
		sky_material.sky_horizon_color = NIGHT_HORIZON.lerp(DAY_HORIZON, day_amount).lerp(DUSK_HORIZON, dusk_amount * 0.8)
		sky_material.ground_horizon_color = sky_material.sky_horizon_color.lerp(Color(0.24, 0.21, 0.17), 0.45)
		sky_material.ground_bottom_color = Color(0.24, 0.21, 0.17).lerp(Color(0.02, 0.02, 0.04), day_amount)
		sky_material.sun_angle_max = lerpf(4.0, 12.0, day_amount)
		sky_material.sun_curve = lerpf(0.05, 0.15, day_amount)

	if environment != null:
		environment.ambient_light_sky_contribution = lerpf(0.25, 0.85, day_amount)
		environment.ambient_light_energy = lerpf(0.30, 1.0, day_amount)
		environment.ambient_light_color = NIGHT_FOG.lerp(Color(0.85, 0.85, 0.85), day_amount)
		environment.fog_light_color = NIGHT_FOG.lerp(DAY_FOG, day_amount).lerp(DUSK_HORIZON, dusk_amount * 0.6)
		environment.fog_light_energy = lerpf(0.5, 1.0, day_amount)
		environment.fog_density = lerpf(0.0035, 0.0022, day_amount)

	if is_night != _was_night:
		_was_night = is_night
		if player != null and player.has_method("set_night"):
			player.call("set_night", is_night)
