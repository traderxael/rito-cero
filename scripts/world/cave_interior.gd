class_name CaveInterior
extends Node3D

## Interior de la cueva: un pozo con rampa que baja desde la boca hasta una galeria
## horizontal con suelo, techo y paredes. Todo son cajas: pocas primitivas, colisiones
## previsibles y un presupuesto de relleno que el export web aguanta.
##
## Una sola luz nueva (OmniLight3D sin sombras) que se enciende solo mientras Rito esta
## dentro; las antorchas son emisivas, no luces. La colision va en la capa 1, la misma
## que el terreno: el jugador y los NPCs chocan con ella.

const CaveEntranceScript := preload("res://scripts/world/cave_entrance.gd")
const BossNpcScript := preload("res://scripts/npc/boss_npc.gd")

## Metros bajo la boca, largo y ancho de la galeria, y alto libre.
const DEPTH := 9.0
const LENGTH := 34.0
const WIDTH := 8.0
const HEIGHT := 5.0

## Hueco de la entrada y desnivel horizontal de la rampa.
const ENTRY_WIDTH := 4.0
const RAMP_RUN := 8.0

const TORCH_COUNT := 5
const TORCH_HEIGHT := 2.4

const ROCK := Color(0.46, 0.43, 0.38)
const ROCK_DARK := Color(0.26, 0.24, 0.22)
const FLAME := Color(1.0, 0.55, 0.16)

var _mouth := Vector3.ZERO
var _direction := Vector3.FORWARD
var _body: StaticBody3D
var _boss: Node3D
var _rock_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _flame_material: StandardMaterial3D


## mouth_position es el centro de la boca; direction es hacia donde se alarga la
## galeria. terrain_data, si viene, sirve para colocar al jefe al fondo.
func setup(mouth_position: Vector3, direction: Vector3 = Vector3.FORWARD, terrain_data = null) -> void:
	_mouth = mouth_position
	_direction = direction.normalized() if direction.length() > 0.01 else Vector3.FORWARD
	global_position = _mouth
	# Con +Z local como frente, este yaw alinea la galeria con la direccion pedida.
	rotation.y = atan2(_direction.x, _direction.z)

	_rock_material = _make_material(ROCK)
	_dark_material = _make_material(ROCK_DARK)
	_flame_material = _make_material(FLAME)
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.emission_enabled = true
	_flame_material.emission = FLAME
	_flame_material.emission_energy_multiplier = 1.6

	_body = StaticBody3D.new()
	_body.name = "CuevaInterior"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)

	_build_shaft()
	_build_gallery()
	_build_light()
	_build_trigger()
	_build_torches()
	_spawn_boss(terrain_data)


## El suelo de la galeria, en coordenadas de mundo.
func floor_position() -> Vector3:
	return to_global(Vector3(0, -DEPTH, RAMP_RUN + LENGTH * 0.5))


## El techo de la galeria, en coordenadas de mundo.
func ceiling_position() -> Vector3:
	return to_global(Vector3(0, -DEPTH + HEIGHT, RAMP_RUN + LENGTH * 0.5))


## El borde de la entrada: coincide con la boca de la cueva.
func entry_position() -> Vector3:
	return to_global(Vector3.ZERO)


## Donde aparece el Praetorian: al fondo de la galeria, sobre el suelo.
func boss_spawn_point() -> Vector3:
	return to_global(Vector3(0, -DEPTH, RAMP_RUN + LENGTH - 3.0))


func boss() -> Node3D:
	return _boss


## El pozo de entrada: paredes a los lados, techo solo en la mitad lejana (la primera
## queda abierta, que es la boca) y una rampa continua que baja al fondo.
func _build_shaft() -> void:
	var wall_height := DEPTH + 2.0
	for side in [-1.0, 1.0]:
		_add_box(
			Vector3(0.6, wall_height, RAMP_RUN),
			Vector3(side * (ENTRY_WIDTH * 0.5 + 0.3), -DEPTH * 0.5 + 1.0, RAMP_RUN * 0.5),
			0.0, _dark_material)
	_add_box(
		Vector3(ENTRY_WIDTH + 1.2, 0.6, RAMP_RUN * 0.5),
		Vector3(0, 0.3, RAMP_RUN * 0.75),
		0.0, _dark_material)

	# Rampa: una caja inclinada. Su cara superior pasa por la boca y por el fondo.
	var ramp_length := sqrt(DEPTH * DEPTH + RAMP_RUN * RAMP_RUN) + 0.4
	var angle := atan2(DEPTH, RAMP_RUN)
	var normal := Vector3(0.0, cos(angle), sin(angle))
	var center := Vector3(0.0, -DEPTH * 0.5, RAMP_RUN * 0.5) - normal * 0.2
	_add_box(
		Vector3(ENTRY_WIDTH, 0.4, ramp_length),
		center,
		angle, _dark_material)


## La galeria: suelo, techo, dos paredes y el tapon del fondo.
func _build_gallery() -> void:
	var mid := RAMP_RUN + LENGTH * 0.5
	_add_box(Vector3(WIDTH, 0.6, LENGTH), Vector3(0, -DEPTH - 0.3, mid), 0.0, _rock_material)
	_add_box(Vector3(WIDTH, 0.6, LENGTH), Vector3(0, -DEPTH + HEIGHT + 0.3, mid), 0.0, _rock_material)
	for side in [-1.0, 1.0]:
		_add_box(
			Vector3(0.6, HEIGHT, LENGTH),
			Vector3(side * (WIDTH * 0.5 + 0.3), -DEPTH + HEIGHT * 0.5, mid),
			0.0, _rock_material)
	_add_box(
		Vector3(WIDTH + 1.2, HEIGHT, 0.6),
		Vector3(0, -DEPTH + HEIGHT * 0.5, RAMP_RUN + LENGTH),
		0.0, _rock_material)


## La unica luz nueva de la cueva. Sin sombras: el renderer de Compatibility paga cada
## sombra por pixel y aqui no hace falta ninguna.
func _build_light() -> void:
	var light := OmniLight3D.new()
	light.name = "LuzInterior"
	light.light_color = Color(0.98, 0.72, 0.42)
	light.light_energy = 1.7
	light.omni_range = 24.0
	light.shadow_enabled = false
	light.position = Vector3(0, -DEPTH + 3.2, RAMP_RUN + LENGTH * 0.45)
	light.visible = false
	add_child(light)


## Trigger de la galeria: enciende la luz solo si entra Rito (capa 2).
func _build_trigger() -> void:
	var area := Area3D.new()
	area.name = "InteriorArea"
	area.collision_layer = 0
	area.collision_mask = 2
	area.script = CaveEntranceScript
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH + 1.0, HEIGHT, LENGTH)
	shape.shape = box
	shape.position = Vector3(0, -DEPTH + HEIGHT * 0.5, RAMP_RUN + LENGTH * 0.5)
	area.add_child(shape)
	add_child(area)


## Antorchas: malla emisiva, sin luz. Iluminan de mentira, que es lo barato.
func _build_torches() -> void:
	for i in TORCH_COUNT:
		var side := 1.0 if i % 2 == 0 else -1.0
		var z := RAMP_RUN + 4.0 + (LENGTH - 8.0) * float(i) / float(TORCH_COUNT - 1)
		var torch := MeshInstance3D.new()
		torch.name = "Antorcha%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.22, 0.45, 0.22)
		torch.mesh = mesh
		torch.material_override = _flame_material
		add_child(torch)
		torch.position = Vector3(side * (WIDTH * 0.5 - 0.25), -DEPTH + TORCH_HEIGHT, z)


## El Praetorian espera al fondo de la galeria. Sin terreno valido (estamos bajo tierra)
## no se genera: la cueva queda vacia pero jugable.
func _spawn_boss(terrain_data) -> void:
	if terrain_data == null:
		return
	var boss: Node3D = BossNpcScript.new()
	boss.name = "Praetorian"
	add_child(boss)
	var player := _find_player()
	boss.call("setup_boss", terrain_data, boss_spawn_point(), 0.0, player)
	_boss = boss


func _find_player() -> Node3D:
	var found := get_tree().get_first_node_in_group("player")
	if found != null:
		return found as Node3D
	return null


## Una caja: colision en la capa 1 y malla con el mismo material.
func _add_box(size: Vector3, position: Vector3, tilt: float, material: StandardMaterial3D) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = position
	shape.rotation.x = tilt
	_body.add_child(shape)

	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	cube.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = cube
	_body.add_child(instance)
	instance.position = position
	instance.rotation.x = tilt


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material
