extends SceneTree

## Arnes determinista de la variedad de enemigos: sin escena, sin GPU.
## Comprueba el chase_speed de instancia (base de hondero/bruto/corredor), la
## tabla de composicion por nivel y la fabrica de bandidos con mutadores.

const HOSTILE := preload("res://scripts/npc/hostile_npc.gd")
const BanditCampScript := preload("res://scripts/missions/bandit_camp.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const EXPECTED_CHECKS := 13

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_chase_speed_instancia()
	_test_composition()
	await _test_spawn_bandit_kind_y_mutadores()
	await _test_hondero()
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


class StubData:
	extends RefCounted

	func get_height(position: Vector3) -> float:
		return position.y


func _target_at(pos: Vector3) -> Node3D:
	var target := Node3D.new()
	root.add_child(target)
	target.global_position = pos
	return target


func _test_chase_speed_instancia() -> void:
	await process_frame
	var target := _target_at(Vector3(10, 0, 0))
	var bandit: CharacterBody3D = HOSTILE.new()
	root.add_child(bandit)
	bandit.call("setup", StubData.new(), Vector3.ZERO, 0.0, target)
	_check(is_equal_approx(float(bandit.get("chase_speed")), 3.4), "chase_speed por defecto es 3,4")
	bandit.set("chase_speed", 4.6)
	bandit.call("_chase", Vector3(1, 0, 0), 1.0)
	_check(is_equal_approx(float(bandit.velocity.x), 4.6), "con chase_speed 4,6 persigue a 4,6")
	bandit.queue_free()


func _test_composition() -> void:
	var bajo: Array = BanditCampScript.composition(3, 4)
	_check(bajo.size() == 4 and bajo.count("bandit") == 4, "nivel 3: solo bandidos")
	var medio: Array = BanditCampScript.composition(6, 5)
	_check(medio.count("slinger") == 1 and medio.count("bandit") == 4, "nivel 6: 1 hondero y 4 bandidos")
	var alto: Array = BanditCampScript.composition(12, 8)
	_check(alto.count("slinger") == 2 and alto.count("brute") == 1 and alto.count("runner") == 1 and alto.count("bandit") == 4,
		"nivel 12: 2 honderos, 1 bruto, 1 corredor y 4 bandidos")


func _test_spawn_bandit_kind_y_mutadores() -> void:
	await process_frame
	var target := _target_at(Vector3(5, 0, 0))
	var generico: CharacterBody3D = BanditCampScript.spawn_bandit(root, Vector3.ZERO, 0.0, null, target, "bandit")
	_check(generico.get_script() == HOSTILE, "kind bandit crea un hostile_npc")
	generico.queue_free()
	var mutado: CharacterBody3D = BanditCampScript.spawn_bandit(root, Vector3.ZERO, 0.0, null, target, "bandit", null, {"health": 1.5})
	_check(is_equal_approx(float(mutado.get("max_health")), 90.0), "el mutador de vida deja max_health en 90")
	var combatiente: Node = mutado.get_node("Combatant")
	_check(is_equal_approx(float(combatiente.get("max_health")), 90.0), "el Combatant se re-setup con la vida multiplicada")
	mutado.queue_free()


## Suelo fisico para el hondero: sin el, la gravedad lo tira del mundo y las
## distancias dejan de medir lo que importa.
func _make_floor() -> StaticBody3D:
	var suelo := StaticBody3D.new()
	suelo.collision_layer = 1
	suelo.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	suelo.add_child(shape)
	root.add_child(suelo)
	return suelo


## Jugador de mentira para el hondero: cuerpo en la capa 2 con un Combatant,
## como Rito, para que las piedras le hagan dano.
func _make_player_stub(pos: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 1.0)
	shape.shape = box
	body.add_child(shape)
	var combatant: Node = CombatantScript.new()
	combatant.name = "Combatant"
	body.add_child(combatant)
	combatant.call("setup", 100.0)
	root.add_child(body)
	body.global_position = pos
	return body


func _test_hondero() -> void:
	await process_frame
	_make_floor()
	var stub := _make_player_stub(Vector3(5, 1.4, 0))
	var hondero: CharacterBody3D = BanditCampScript.spawn_bandit(root, Vector3.ZERO, 0.0, null, stub, "slinger")
	_check(is_equal_approx(float(hondero.get("max_health")), 35.0), "el hondero tiene 35 de vida")
	_check(bool(hondero.get("counts_as_kill")), "el hondero cuenta como baja")
	# Kiting: con el jugador a 5 m se aleja.
	for i in 60:
		await physics_frame
	var lejos := hondero.global_position.distance_to(stub.global_position)
	_check(lejos > 5.5, "con el jugador cerca el hondero se aleja")
	# No se aleja mas alla de su banda: con el jugador a 20 m se acerca hasta ~14.
	stub.global_position = Vector3(20, 1.4, 0)
	for i in 200:
		await physics_frame
	var cerca := hondero.global_position.distance_to(stub.global_position)
	_check(cerca < 15.0 and cerca > 8.0, "el hondero se acerca hasta su banda y se queda")
	stub.queue_free()
	hondero.queue_free()
	# Lanza: con el jugador a 10 m en banda, el hondero tira una piedra que dana.
	var stub2 := _make_player_stub(Vector3(10, 1.4, 0))
	var hondero2: CharacterBody3D = BanditCampScript.spawn_bandit(root, Vector3.ZERO, 0.0, null, stub2, "slinger")
	for i in 120:
		await physics_frame
	var vida := float((stub2.get_node("Combatant") as Node).get("health"))
	_check(vida < 100.0, "la piedra del hondero dana al jugador")
	stub2.queue_free()
	hondero2.queue_free()
