extends SceneTree

## El esclavo es un acompanante: sigue a Rito, no es un hostil (el moloso lo
## confundiria con un enemigo), tiene colision y su volumen solo danza con la capa
## de los bandidos.

const SlaveScript := preload("res://scripts/npc/slave.gd")

const EXPECTED_CHECKS := 7

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_add_floor()
	var player := Node3D.new()
	root.add_child(player)
	player.global_position = Vector3.ZERO
	var slave: CharacterBody3D = SlaveScript.new()
	slave.name = "Slave"
	root.add_child(slave)
	slave.call("setup", player, Vector3(0, 0, 10))
	slave.global_position = Vector3(0, 0, 10)
	await process_frame

	_check(slave.is_in_group("companions"), "el esclavo esta en el grupo companions")
	_check(not slave.is_in_group("hostiles"), "el esclavo no esta en el grupo hostiles")
	_check(slave.collision_layer == 64, "el esclavo vive en la capa 64")
	var has_capsule := false
	for child in slave.get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is CapsuleShape3D:
			has_capsule = true
	_check(has_capsule, "el esclavo tiene capsula de colision")

	var volume := slave.get_node_or_null("Model/AttackVolume") as AttackVolume
	_check(volume != null and volume.collision_mask == 4,
		"el volumen del esclavo solo golpea la capa de hostiles")

	var before := slave.global_position.distance_to(player.global_position)
	for i in 120:
		await physics_frame
	var after := slave.global_position.distance_to(player.global_position)
	_check(after < before - 3.0, "el esclavo sigue a Rito")

	# Apoyo en combate: un hostil a 1,6 m debe recibir el tajo del esclavo.
	var bandit := _make_bandit(Vector3(slave.global_position.x, 0.8, slave.global_position.z + 1.6))
	bandit.add_to_group("hostiles")
	var combatant := bandit.get_node("Combatant") as Combatant
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 4000:
		await physics_frame
		if combatant.health < 100.0:
			break
	_check(combatant.health < 100.0, "el esclavo golpea al hostil cercano")

	player.queue_free()
	slave.queue_free()
	bandit.queue_free()
	await process_frame
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


func _make_bandit(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	body.add_child(shape)
	body.position = at
	root.add_child(body)
	var combatant := Combatant.new()
	combatant.name = "Combatant"
	body.add_child(combatant)
	combatant.setup(100.0)
	return body


func _add_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)
