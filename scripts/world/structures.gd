extends Node3D

## Coloca el contenido del mundo: ruinas romanas, la boca de cueva y los NPCs que
## patrullan el valle. Todos los puntos se apoyan en la altura real del terreno.

const MeshFactoryScript := preload("res://scripts/world/mesh_factory.gd")
const RomanNpcScript := preload("res://scripts/npc/hostile_npc.gd")
const CaveEntranceScript := preload("res://scripts/world/cave_entrance.gd")
const CaveInteriorScript := preload("res://scripts/world/cave_interior.gd")
const HordeSiteScript := preload("res://scripts/missions/horde_site.gd")

const COLOSSEUM_GLB := "res://assets/models/colosseum.glb"
const PORTICO_DISTANCE := 34.0
const CAVE_DISTANCE := 120.0
const NPC_COUNT := 4

var points_of_interest: Array[Dictionary] = []
var poi_positions: Dictionary = {}
var boss: Node3D
var _player: Node3D


func setup(terrain: Terrain3D, player: Node3D) -> void:
	_player = player
	var data := terrain.get_data()
	var origin := player.global_position

	var placed: Array[Vector3] = []

	var portico_spot := _flat_spot(data, origin, 1.1, PORTICO_DISTANCE, 14.0, placed)
	if portico_spot != Vector3.ZERO:
		placed.append(portico_spot)
		_build_portico(portico_spot)
		_add_marker("Ruinas", portico_spot + Vector3(0, 4.4, 0))

	var broken_spot := _flat_spot(data, origin, 2.4, PORTICO_DISTANCE * 0.85, 14.0, placed)
	if broken_spot != Vector3.ZERO:
		placed.append(broken_spot)
		_build_broken_column(broken_spot)
		_add_marker("Columna rota", broken_spot + Vector3(0, 2.8, 0))

	var wall_spot := _flat_spot(data, origin, -1.7, PORTICO_DISTANCE * 1.3, 14.0, placed)
	if wall_spot != Vector3.ZERO:
		placed.append(wall_spot)
		_build_wall(wall_spot)
		_add_marker("Muro", wall_spot + Vector3(0, 2.0, 0))

	var cave_spot := _flat_spot(data, origin, 3.6, CAVE_DISTANCE, 18.0, placed)
	if cave_spot != Vector3.ZERO:
		placed.append(cave_spot)
		_build_cave(cave_spot, data)
		_add_marker("Cueva", cave_spot + Vector3(0, 5.6, 0))

	var colosseum_spot := _colosseum_spot(data, origin, 2.15, 130.0, 48.0, 40.0)
	if colosseum_spot != Vector3.ZERO:
		_build_colosseum(colosseum_spot)
		_add_marker("Coliseo", colosseum_spot + Vector3(0, 30.0, 0))
		_activador_coliseo(colosseum_spot)

	for i in NPC_COUNT:
		var angle := TAU * float(i) / float(NPC_COUNT) + 0.6
		var spot := _flat_spot(data, origin, angle, 26.0 + 9.0 * float(i), 8.0, placed, 9.0)
		if spot != Vector3.ZERO:
			placed.append(spot)
			_build_npc(data, spot, angle)

	# Posiciones de interes para las misiones: la purga levanta su campamento en
	# la Columna rota y la defensa en las Ruinas.
	poi_positions = {"columna": broken_spot, "ruinas": portico_spot, "muro": wall_spot, "cueva": cave_spot}


func _build_portico(spot: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "Portico"
	instance.mesh = MeshFactoryScript.make_portico()
	instance.material_override = _stone_material()
	add_child(instance)
	instance.global_position = spot
	instance.rotation.y = randf_range(0.0, TAU)


func _build_broken_column(spot: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "ColumnaRota"
	instance.mesh = MeshFactoryScript.make_broken_column()
	instance.material_override = _stone_material()
	add_child(instance)
	instance.global_position = spot
	instance.rotation.y = randf_range(0.0, TAU)


func _build_wall(spot: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "Muro"
	instance.mesh = MeshFactoryScript.make_wall()
	instance.material_override = _stone_material()
	add_child(instance)
	instance.global_position = spot
	instance.rotation.y = randf_range(0.0, TAU)


func _build_colosseum(spot: Vector3) -> void:
	var colosseum := Node3D.new()
	colosseum.name = "Coliseo"
	add_child(colosseum)
	colosseum.global_position = spot
	colosseum.rotation.y = randf_range(0.0, TAU)

	var model := _load_colosseum_model()
	if model != null:
		colosseum.add_child(model)
	else:
		# Respaldo si falta el .glb: el coliseo procedural de mesh_factory.
		var fallback := MeshInstance3D.new()
		fallback.mesh = MeshFactoryScript.make_colosseum()
		fallback.material_override = _stone_material()
		colosseum.add_child(fallback)


## Carga el coliseo exportado desde Blender (glTF) leyendo el .glb directamente, sin
## depender de que el editor ya lo haya importado. Devuelve null si no está.
func _load_colosseum_model() -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(COLOSSEUM_GLB, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## Busca un emplazamiento amplio y llano para el coliseo: muestrea la altura en todo
## el anillo de su huella y elige el punto con menos relieve. La base se apoya en la
## altura máxima de la huella, y el faldón de la malla cubre la diferencia.
func _colosseum_spot(data, origin: Vector3, base_angle: float, distance: float,
		rx: float, ry: float) -> Vector3:
	var best := Vector3.ZERO
	var best_roughness := INF
	for attempt in 12:
		var angle := base_angle + 0.5 * float(attempt)
		var step := distance * (0.85 + 0.1 * float(attempt % 3))
		var candidate := origin + Vector3(cos(angle), 0.0, sin(angle)) * step
		var center_height: float = data.get_height(candidate)
		if is_nan(center_height):
			continue
		var max_height := center_height
		var roughness := 0.0
		var valid := true
		for k in range(12):
			var a := TAU * float(k) / 12.0
			var height: float = data.get_height(candidate + Vector3(rx * cos(a), 0.0, ry * sin(a)))
			if is_nan(height):
				valid = false
				break
			max_height = maxf(max_height, height)
			roughness += absf(height - center_height)
		if not valid:
			continue
		if roughness < best_roughness:
			best_roughness = roughness
			best = Vector3(candidate.x, max_height + 1.0, candidate.z)
		if roughness < 6.0:
			break
	return best


func _build_cave(spot: Vector3, data) -> void:
	var cave := Node3D.new()
	cave.name = "Cueva"
	add_child(cave)
	cave.global_position = spot

	var mouth := MeshInstance3D.new()
	mouth.name = "Boca"
	mouth.mesh = MeshFactoryScript.make_cave_mouth()
	mouth.material_override = _stone_material()
	cave.add_child(mouth)

	var light := OmniLight3D.new()
	light.name = "LuzCueva"
	light.light_color = Color(0.95, 0.62, 0.28)
	light.light_energy = 1.8
	light.omni_range = 14.0
	light.shadow_enabled = false
	light.position = Vector3(0, 1.6, 1.2)
	light.visible = false
	cave.add_child(light)

	var trigger := Area3D.new()
	trigger.name = "CaveArea3D"
	trigger.collision_mask = 2
	trigger.script = CaveEntranceScript
	cave.add_child(trigger)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16, 10, 16)
	shape.shape = box
	shape.position = Vector3(0, 4, 0)
	trigger.add_child(shape)

	# La cueva de verdad: rampa, galeria y el Praetorian al fondo. Es hermana de "Cueva"
	# y no hija: el trigger de la boca busca luces en su padre y no debe encender la
	# luz del interior.
	var interior: Node3D = CaveInteriorScript.new()
	interior.name = "CuevaInterior"
	add_child(interior)
	interior.call("setup", spot, Vector3.FORWARD, data)
	boss = interior.call("boss")




func _build_npc(data, spot: Vector3, angle: float) -> void:
	var npc: CharacterBody3D = RomanNpcScript.new()
	npc.name = "Romano"
	add_child(npc)
	npc.call("setup", data, spot, angle, _player)


func _add_marker(text: String, spot: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.outline_size = 16
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = false
	label.modulate = Color(0.96, 0.88, 0.68)
	label.outline_modulate = Color(0.1, 0.08, 0.05, 0.9)
	add_child(label)
	label.global_position = spot
	points_of_interest.append({"name": text, "position": spot})


func _stone_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## Busca el punto mas llano cerca de una direccion y distancia del origen, evitando
## los puntos ya ocupados: sin eso, los tres monumentos acaban en la unica zona plana
## del entorno y se montan unos encima de otros.
func _flat_spot(
		data,
		origin: Vector3,
		base_angle: float,
		distance: float,
		probe := 14.0,
		avoid: Array[Vector3] = [],
		separation := 16.0) -> Vector3:
	var best := Vector3.ZERO
	var best_roughness := INF
	for attempt in 16:
		var angle := base_angle + 0.3 * float(attempt)
		var step := distance * (0.8 + 0.14 * float(attempt % 3))
		var candidate := origin + Vector3(cos(angle), 0.0, sin(angle)) * step
		var height: float = data.get_height(candidate)
		if is_nan(height):
			continue
		if _too_close(candidate, avoid, separation):
			continue
		var roughness := 0.0
		var valid := true
		for probe_offset in [Vector3(probe, 0, 0), Vector3(-probe, 0, 0), Vector3(0, 0, probe), Vector3(0, 0, -probe)]:
			var neighbour: float = data.get_height(candidate + probe_offset)
			if is_nan(neighbour):
				valid = false
				break
			roughness += absf(neighbour - height)
		if not valid:
			continue
		if roughness < best_roughness:
			best_roughness = roughness
			best = Vector3(candidate.x, height, candidate.z)
		if roughness <= 2.0:
			break
	if best_roughness > 9.0:
		return Vector3.ZERO
	return best


func _too_close(candidate: Vector3, avoid: Array[Vector3], separation: float) -> bool:
	for placed in avoid:
		if Vector2(candidate.x - placed.x, candidate.z - placed.z).length() < separation:
			return true
	return false




