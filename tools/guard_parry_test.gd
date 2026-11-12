extends SceneTree

## Pruebas deterministas de la guardia, el parry y el contraataque. Sin GPU ni escena.

const RitoScript := preload("res://scripts/player/rito.gd")
const RitoCombatScript := preload("res://scripts/player/rito_combat.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")
const AttackVolumeScript := preload("res://scripts/combat/attack_volume.gd")
const HostileNPCScript := preload("res://scripts/npc/hostile_npc.gd")

class HeightData:
	func get_height(_at: Vector3) -> float:
		return 0.0


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
	await _test_guard_regenerates()
	await _test_parry_negates_damage_and_opens_riposte()
	await _test_parry_expires_as_normal_guard()
	await _test_guard_uses_model_facing()
	await _test_parry_tap_survives_release()
	await _test_riposte_expires()
	await _test_riposte_uses_stun_crit_multiplier()
	await _test_pilum_does_not_consume_riposte()
	await _test_npc_push_waits_for_windup()
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


## El frente visible del modelo es +basis.z (el maniqui mira a +Z); se calcula
## desde el modelo y no desde una constante para que el test siga la rotacion real.
func _front(rito: Rito) -> Vector3:
	var forward := rito.model.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() * 2.0


func _test_block_action_exists() -> void:
	_check(InputMap.has_action("block"), "la accion block existe")


func _test_guard_reduces_frontal_damage() -> void:
	var rito := await _make_rito()
	rito.call("set_guarding", true)
	_check(bool(rito.call("is_guarding")), "la guardia se activa")
	var attacker := _make_probe(_front(rito))
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
	var attacker := _make_probe(-_front(rito))
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
	var attacker := _make_probe(_front(rito))
	var handled: bool = bool(rito.call("receive_attack", 20.0, attacker))
	_check(handled, "la guardia intercepta el golpe que la rompe")
	_check(is_equal_approx(float(rito.combatant.get("health")), 90.0),
		"la ruptura deja pasar el 50% del dano")
	_check(is_equal_approx(float(rito.call("guard_value")), 25.0),
		"la barra vuelve al 25% tras la ruptura")
	_check(not bool(rito.call("is_guarding")), "la guardia queda rota")
	_check(float(rito.get("_guard_lock_until")) > before_now,
		"la ruptura bloquea la guardia un tiempo")
	rito.call("set_guarding", true)
	_check(not bool(rito.call("is_guarding")),
		"la guardia no se puede levantar durante la ruptura")
	rito.set("_guard_lock_until", 0.0)
	rito.set("_lock_until", 0.0)
	rito.call("set_guarding", true)
	_check(bool(rito.call("is_guarding")),
		"pasada la ruptura la guardia vuelve")
	rito.free()
	attacker.free()


func _test_guard_regenerates() -> void:
	var rito := await _make_rito()
	rito.set("_guard", 50.0)
	rito.set("_guard_regen_at", 0.0)
	await create_timer(0.5).timeout
	_check(float(rito.call("guard_value")) > 50.0,
		"la guardia se regenera tras el retardo")
	rito.free()


func _test_parry_negates_damage_and_opens_riposte() -> void:
	var rito := await _make_rito()
	rito.call("set_guarding", true)
	var parried := [false]
	rito.connect("parried", func() -> void: parried[0] = true)
	var attacker := _make_probe(_front(rito))
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
	var attacker := _make_probe(_front(rito))
	var handled: bool = bool(rito.call("receive_attack", 20.0, attacker))
	_check(handled, "sin ventana de parry el golpe sigue siendo bloqueado")
	_check(is_equal_approx(float(rito.combatant.get("health")), 96.0),
		"fuera de la ventana se aplica la reduccion normal")
	_check(not bool(rito.call("is_riposte_ready")),
		"fuera de la ventana no hay contraataque")
	rito.free()
	attacker.free()


func _test_guard_uses_model_facing() -> void:
	var rito := await _make_rito()
	# El modelo mira a +Z cuando su rotacion es 0; el frente debe ser +Z.
	rito.model.rotation.y = 0.0
	rito.call("set_guarding", true)
	var handled: bool = bool(rito.call("receive_attack", 20.0, _make_probe(_front(rito))))
	_check(handled, "el ataque frontal real se bloquea")
	_check(is_equal_approx(float(rito.combatant.get("health")), 96.0),
		"el frente real recibe la reduccion")
	rito.set("_guard", 100.0)
	var back_handled: bool = bool(rito.call("receive_attack", 20.0, _make_probe(-_front(rito))))
	_check(not back_handled, "el ataque por la espalda real no se bloquea")
	_check(is_equal_approx(float(rito.combatant.get("health")), 96.0),
		"la espalda real no recibe la reduccion")
	rito.free()


func _test_parry_tap_survives_release() -> void:
	var rito := await _make_rito()
	rito.call("set_guarding", true)
	rito.call("try_parry")
	rito.call("set_guarding", false)
	var handled: bool = bool(rito.call("receive_attack", 20.0, _make_probe(_front(rito))))
	_check(handled, "un toque de Q sigue parando tras soltar")
	_check(is_equal_approx(float(rito.combatant.get("health")), 100.0),
		"el parry de toque no deja pasar dano")
	_check(bool(rito.call("is_riposte_ready")),
		"el parry de toque abre el contraataque")
	rito.free()


func _test_riposte_expires() -> void:
	var rito := await _make_rito()
	var events: Array = []
	rito.connect("riposte_changed", func(active: bool) -> void: events.append(active))
	var now := float(Time.get_ticks_msec()) / 1000.0
	rito.set("_riposte_until", now + 0.05)
	for i in 20:
		await physics_frame
	_check(not bool(rito.call("is_riposte_ready")),
		"la ventana de riposte caduca sola")
	_check(events.has(false), "la caducidad avisa al HUD")
	rito.free()


func _test_riposte_uses_stun_crit_multiplier() -> void:
	var rito := await _make_rito()
	var attack: RitoCombat = RitoCombatScript.new()
	rito.add_child(attack)
	await process_frame
	attack.setup(rito)
	var target := _make_target(Vector3(0, 0.8, 2.0))
	target.rotation.y = PI
	# Simula el dano base ya aplicado por el AttackVolume: 90 de vida restante.
	target.get_node("Combatant").take_damage(10.0, Vector3.ZERO)
	rito.set("_riposte_until", float(Time.get_ticks_msec()) / 1000.0 + 1.0)
	attack._on_landed(target, 10.0, true)
	_check(is_equal_approx(float(target.get_node("Combatant").get("health")), 80.0),
		"el riposte sobre un aturdido usa al menos el critico normal (2x), no 1,75x")
	rito.free()
	target.free()


func _test_pilum_does_not_consume_riposte() -> void:
	var rito := await _make_rito()
	var attack: RitoCombat = RitoCombatScript.new()
	rito.add_child(attack)
	await process_frame
	attack.setup(rito)
	var target := _make_target(Vector3(0, 0.8, 2.0))
	rito.set("_riposte_until", float(Time.get_ticks_msec()) / 1000.0 + 1.0)
	attack._on_projectile_landed(target, 10.0, false)
	_check(bool(rito.call("is_riposte_ready")),
		"el pilum no consume la ventana de contraataque")
	rito.free()
	target.free()


func _test_npc_push_waits_for_windup() -> void:
	var rito := await _make_rito()
	# Sin terreno en el arnes, Rito tambien caeria fuera del volumen.
	rito.set_physics_process(false)
	var npc: CharacterBody3D = HostileNPCScript.new()
	root.add_child(npc)
	npc.setup(HeightData.new(), Vector3(0, 0, 1.5), 0.0, rito)
	await process_frame
	# Sin suelo en el arnes, la gravedad se lleva al NPC lejos del volumen. Se
	# congela su fisica y se orienta el modelo a mano: el ataque y el empuje siguen.
	npc.set_physics_process(false)
	(npc.get("_model") as Node3D).rotation.y = PI
	npc.set("state", "ATTACK")
	npc.set("_attack_ready", 0.0)
	npc.set("_attack_count", 1)
	npc.call("_try_attack")
	_check((rito.get("_push_velocity") as Vector3).length() < 0.01,
		"el empuje fisico no sale antes del windup")
	await create_timer(0.95).timeout
	_check((rito.get("_push_velocity") as Vector3).length() > 0.01,
		"el empuje fisico sale al abrirse la ventana")
	_check(float(rito.combatant.get("health")) < 100.0,
		"el empuje a 1,5x llega antes del siguiente ataque")
	npc.free()
	rito.free()


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
	# Caso real del NPC: la ventana abre al 25% del clip, desplazada por el windup.
	volume.call("begin_swing", 10.0, volume, 0.25, 1.0, 1.0, 0.3)
	for i in 6:
		await physics_frame
	_check(is_equal_approx(float(target.get_node("Combatant").get("health")), 100.0),
		"el windup retrasa el dano")
	for i in 60:
		await physics_frame
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