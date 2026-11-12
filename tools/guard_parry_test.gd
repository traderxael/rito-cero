extends SceneTree

## Pruebas deterministas de la guardia, el parry y el contraataque. Sin GPU ni escena.

const RitoScript := preload("res://scripts/player/rito.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")
const AttackVolumeScript := preload("res://scripts/combat/attack_volume.gd")

class StaggerProbe extends Node3D:
	var staggered := 0.0

	func stagger(seconds: float) -> void:
		staggered = seconds


class ReceiveProbe extends CharacterBody3D:
	var received := 0.0

	func receive_attack(amount: float, _source: Node3D) -> bool:
		received = amount
		return true


var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_block_action_exists()
	await _test_guard_reduces_frontal_damage()
	await _test_guard_ignores_back_attack()
	await _test_guard_breaks()
	await _test_parry_negates_damage_and_opens_riposte()
	await _test_parry_expires_as_normal_guard()
	await _test_attack_volume_windup()
	await _test_attack_volume_delegates()
	print("TEST failures=", _failures, " checks=", _checks_run)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks_run += 1
	if not condition:
		_failures += 1
		print("FAIL ", label)
	else:
		print("ok ", label)


func _make_rito() -> Rito:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	await process_frame
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	rito.add_child(combatant)
	combatant.setup(100.0)
	rito.bind_combatant(combatant, Vector3.ZERO)
	return rito


func _make_probe(at: Vector3) -> StaggerProbe:
	var probe := StaggerProbe.new()
	root.add_child(probe)
	probe.global_position = at
	return probe


func _test_block_action_exists() -> void:
	_check(InputMap.has_action("block"), "la accion block existe")


func _test_guard_reduces_frontal_damage() -> void:
	var rito := await _make_rito()
	rito.call("set_guarding", true)
	_check(bool(rito.call("is_guarding")), "la guardia se activa")
	var attacker := _make_probe(Vector3(0, 0, 2))
	var handled: bool = bool(rito.call("receive_attack", 20.0, attacker))
	_check(handled, "la guardia intercepta el golpe frontal")
	_check(is_equal_approx(float(rito.combatant.get("health")), 96.0),
		"la guardia reduce el dano frontal al 20%")
	_check(is_equal_approx(float(rito.call("guard_value")), 78.0),
		"la guardia consume 1,1x el dano")
	rito.free()
	attacker.free()


func _test_guard_ignores_back_attack() -> void:
	var rito := await _make_rito()
	rito.call("set_guarding", true)
	var attacker := _make_probe(Vector3(0, 0, -2))
	var before := float(rito.combatant.get("health"))
	var handled: bool = bool(rito.call("receive_attack", 20.0, attacker))
	_check(not handled, "la guardia no intercepta por la espalda")
	_check(is_equal_approx(float(rito.combatant.get("health")), before),
		"el golpe por la espalda no lo aplica la guardia")
	rito.free()
	attacker.free()


func _test_guard_breaks() -> void:
	var rito := await _make_rito()
	rito.call("set_guarding", true)
	rito.set("_guard", 10.0)
	var before_now := float(Time.get_ticks_msec()) / 1000.0
	var attacker := _make_probe(Vector3(0, 0, 2))
	var handled: bool = bool(rito.call("receive_attack", 20.0, attacker))
	_check(handled, "la guardia intercepta el golpe que la rompe")
	_check(is_equal_approx(float(rito.combatant.get("health")), 90.0),
		"la ruptura deja pasar el 50% del dano")
	_check(is_equal_approx(float(rito.call("guard_value")), 25.0),
		"la barra vuelve al 25% tras la ruptura")
	_check(not bool(rito.call("is_guarding")), "la guardia queda rota")
	_check(float(rito.get("_guard_lock_until")) > before_now,
		"la ruptura bloquea la guardia un tiempo")
	rito.free()
	attacker.free()


func _test_parry_negates_damage_and_opens_riposte() -> void:
	var rito := await _make_rito()
	rito.call("set_guarding", true)
	var parried := [false]
	rito.connect("parried", func() -> void: parried[0] = true)
	var attacker := _make_probe(Vector3(0, 0, 2))
	_check(bool(rito.call("try_parry")), "el parry acepta la pulsacion")
	var handled: bool = bool(rito.call("receive_attack", 20.0, attacker))
	_check(handled, "el parry intercepta el golpe frontal")
	_check(is_equal_approx(float(rito.combatant.get("health")), 100.0),
		"el parry no deja pasar dano")
	_check(parried[0], "el parry emite su senal")
	_check(is_equal_approx(attacker.staggered, 1.1),
		"el parry aturde al atacante 1,1 s")
	_check(bool(rito.call("is_riposte_ready")), "el parry abre el contraataque")
	_check(is_equal_approx(float(rito.call("consume_riposte")), 1.75),
		"el contraataque vale 1,75x")
	_check(is_equal_approx(float(rito.call("consume_riposte")), 1.0),
		"el contraataque solo se consume una vez")
	rito.free()
	attacker.free()


func _test_parry_expires_as_normal_guard() -> void:
	var rito := await _make_rito()
	rito.call("set_guarding", true)
	rito.call("try_parry")
	rito.set("_parry_until", 0.0)
	var attacker := _make_probe(Vector3(0, 0, 2))
	var handled: bool = bool(rito.call("receive_attack", 20.0, attacker))
	_check(handled, "sin ventana de parry el golpe sigue siendo bloqueado")
	_check(is_equal_approx(float(rito.combatant.get("health")), 96.0),
		"fuera de la ventana se aplica la reduccion normal")
	_check(not bool(rito.call("is_riposte_ready")),
		"fuera de la ventana no hay contraataque")
	rito.free()
	attacker.free()


func _make_target(at: Vector3) -> CharacterBody3D:
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
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	body.add_child(combatant)
	combatant.setup(100.0)
	return body


func _make_volume(reach: float, radius: float) -> AttackVolume:
	var volume: AttackVolume = AttackVolumeScript.new()
	root.add_child(volume)
	volume.setup(reach, radius, 4)
	return volume


func _test_attack_volume_windup() -> void:
	var target := _make_target(Vector3(0, 0.8, 2.0))
	var volume := _make_volume(2.2, 0.75)
	volume.call("begin_swing", 10.0, volume, 0.0, 1.0, 1.0, 0.3)
	await create_timer(0.1).timeout
	_check(is_equal_approx(float(target.get_node("Combatant").get("health")), 100.0),
		"el windup retrasa el dano")
	await create_timer(0.35).timeout
	_check(is_equal_approx(float(target.get_node("Combatant").get("health")), 90.0),
		"pasado el windup el golpe entra")
	volume.free()
	target.free()


func _test_attack_volume_delegates() -> void:
	var probe := ReceiveProbe.new()
	probe.collision_layer = 4
	probe.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	probe.add_child(shape)
	probe.position = Vector3(0, 0.8, 2.0)
	root.add_child(probe)
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	probe.add_child(combatant)
	combatant.setup(100.0)

	var volume := _make_volume(2.2, 0.75)
	volume.begin_swing(10.0, volume, 0.0, 1.0, 1.0)
	for i in 10:
		await physics_frame
	_check(is_equal_approx(probe.received, 10.0),
		"el volumen delega el golpe en receive_attack")
	_check(is_equal_approx(float(combatant.get("health")), 100.0),
		"el cuerpo que intercepta no recibe el dano por defecto")
	volume.free()
	probe.free()

	var normal := _make_target(Vector3(0, 0.8, 2.0))
	var normal_volume := _make_volume(2.2, 0.75)
	normal_volume.begin_swing(10.0, normal_volume, 0.0, 1.0, 1.0)
	for i in 10:
		await physics_frame
	_check(is_equal_approx(float(normal.get_node("Combatant").get("health")), 90.0),
		"sin receive_attack el dano por defecto sigue funcionando")
	normal_volume.free()
	normal.free()