extends SceneTree

## Arnes de la cueva interior explorable: tiene suelo, techo, paredes, escalera de
## entrada, una sola luz nueva (sin sombras) que se enciende al entrar, antorchas
## emisivas y el punto donde aparece el jefe al fondo de la galeria.

const CaveInteriorScript := preload("res://scripts/world/cave_interior.gd")

const EXPECTED_CHECKS := 17

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_cave_interior()
	if _checks_run != EXPECTED_CHECKS:
		_failures += 1
		print("FAIL solo se ejecutaron ", _checks_run, " de ", EXPECTED_CHECKS, " checks")
	print("TEST failures=", _failures, " checks=", _checks_run)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks_run += 1
	if not condition:
		_failures += 1
		print("FAIL ", label)
	else:
		print("ok ", label)


func _test_cave_interior() -> void:
	var cave: Node3D = CaveInteriorScript.new()
	root.add_child(cave)
	var mouth := Vector3(100.0, 40.0, 200.0)
	cave.call("setup", mouth, Vector3.FORWARD)
	await process_frame

	var floor_pos: Vector3 = cave.call("floor_position")
	var ceiling_pos: Vector3 = cave.call("ceiling_position")
	var entry_pos: Vector3 = cave.call("entry_position")
	var boss_pos: Vector3 = cave.call("boss_spawn_point")

	_check(floor_pos.y < mouth.y - 5.0, "el suelo de la cueva esta bajo la boca")
	_check(ceiling_pos.y > floor_pos.y + 3.0, "la cueva tiene techo")
	_check(entry_pos.distance_to(mouth) < 3.0, "la entrada coincide con la boca")
	_check(Vector2(entry_pos.x - mouth.x, entry_pos.z - mouth.z).length() < 0.5,
		"la entrada esta en la misma vertical que la boca")
	_check(boss_pos.distance_to(entry_pos) > 20.0, "el jefe esta al fondo de la galeria")
	_check(boss_pos.y >= floor_pos.y - 0.5, "el jefe aparece sobre el suelo")

	var body := _find_static_body(cave)
	_check(body != null, "la cueva tiene cuerpo estatico")
	_check(body != null and body.collision_layer == 1,
		"la cueva choca en la capa 1 (terreno): el jugador no la atraviesa")
	_check(body != null and _count_shapes(body) >= 6,
		"la cueva tiene suelo, techo, paredes y escalones")

	var lights := _find_lights(cave)
	_check(lights.size() == 1, "la cueva usa una sola luz nueva")
	_check(lights.size() == 1 and not lights[0].shadow_enabled,
		"la luz de la cueva no proyecta sombras")
	_check(lights.size() == 1 and not lights[0].visible, "la luz empieza apagada")

	var area := _find_area(cave)
	_check(area != null, "la cueva tiene trigger de entrada")
	if area != null and lights.size() == 1:
		var intruder := CharacterBody3D.new()
		intruder.collision_layer = 4
		root.add_child(intruder)
		area.call("_on_body_entered", intruder)
		_check(not lights[0].visible, "un NPC no enciende la luz de la cueva")
		var body_player := CharacterBody3D.new()
		body_player.collision_layer = 2
		root.add_child(body_player)
		area.call("_on_body_entered", body_player)
		_check(lights[0].visible, "al entrar en la cueva se enciende la luz")
		area.call("_on_body_exited", body_player)
		_check(not lights[0].visible, "al salir se apaga la luz")

	_check(_count_emissive_meshes(cave) >= 4, "la cueva tiene antorchas emisivas")


func _find_static_body(node: Node) -> StaticBody3D:
	if node is StaticBody3D:
		return node as StaticBody3D
	for child in node.get_children():
		var found := _find_static_body(child)
		if found != null:
			return found
	return null


func _count_shapes(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is CollisionShape3D:
			count += 1
		count += _count_shapes(child)
	return count


func _find_lights(node: Node) -> Array[OmniLight3D]:
	var found: Array[OmniLight3D] = []
	if node is OmniLight3D:
		found.append(node as OmniLight3D)
	for child in node.get_children():
		found.append_array(_find_lights(child))
	return found


func _find_area(node: Node) -> Area3D:
	if node is Area3D:
		return node as Area3D
	for child in node.get_children():
		var found := _find_area(child)
		if found != null:
			return found
	return null


func _count_emissive_meshes(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			var instance := child as MeshInstance3D
			var material := instance.material_override
			if material == null and instance.mesh != null:
				material = instance.mesh.surface_get_material(0)
			if material != null and material.emission_enabled:
				count += 1
		count += _count_emissive_meshes(child)
	return count
