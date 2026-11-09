extends SceneTree

## Arnes del combate avanzado: combo de tres golpes, critico por la espalda,
## aturdimiento en el ultimo eslabon, critico con el estado previo, numeros de dano
## flotantes y la baja que reporta el moloso.

const CombatantScript := preload("res://scripts/combat/combatant.gd")
const RitoScript := preload("res://scripts/player/rito.gd")
const RitoCombatScript := preload("res://scripts/player/rito_combat.gd")
const RomanDogScript := preload("res://scripts/npc/roman_dog.gd")
const DamageNumberScript := preload("res://scripts/fx/damage_number.gd")

## Objetivo que registra el aturdimiento que le pide el combo.
class StunSpy extends CharacterBody3D:
	var stuns: Array[float] = []

	func stagger(seconds: float) -> void:
		stuns.append(seconds)


## Objetivo que imita al bandido real: el dano lo deja en STUN. Sirve para
## comprobar que el critico se decide con el estado ANTERIOR al golpe.
class StatefulSpy extends CharacterBody3D:
	var state := "AGGRO"

	func _on_damaged(_amount: float, _source_position: Vector3) -> void:
		state = "STUN"

const EXPECTED_CHECKS := 16

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_combo_chain()
	await _test_combo_resets_after_window()
	await _test_critical_from_behind()
	await _test_stagger_on_last_hit()
	await _test_damage_numbers()
	await _test_dog_kill_counts()
	await _test_critical_uses_pre_hit_state()
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


## Deja al jugador listo para pelear: con vida, con el combate montado y con la
## cadena de golpes en cero. Devuelve al jugador, porque los objetivos tienen que
## quedar colgados de el (sin terreno ambos caen, y un objetivo quieto se separa
## del volumen por altura antes de que el tajo lo alcance).
func _make_fighter() -> Rito:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var player_combatant: Combatant = CombatantScript.new()
	player_combatant.name = "Combatant"
	rito.add_child(player_combatant)
	var attack: RitoCombat = RitoCombatScript.new()
	attack.name = "Combat"
	rito.add_child(attack)
	await process_frame
	player_combatant.setup(100.0, 0.0)
	rito.bind_combatant(player_combatant, Vector3.ZERO)
	attack.setup(rito)
	# El modelo mira a +Z: el volumen de ataque vive en su espacio, asi que si el
	# modelo quedara mirando a otro lado el tajo no encontraria a nadie.
	rito.model.rotation.y = 0.0
	return rito


## El objetivo tiene que ser un cuerpo fisico con su Combatant, y colgado del
## jugador.
func _make_target(at: Vector3, max_health: float, parent: Node) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	body.add_child(combatant)
	combatant.setup(max_health)
	return body


func _health(body: Node) -> float:
	return float((body.get_node("Combatant") as Combatant).health)


## La ventana de dano del gladius dura ~0,2 s. Bajo carga, un frame puede saltarse
## entera: el test fuerza la ventana abierta para comprobar la logica del golpe sin
## depender del reloj de pared.
func _force_window(attack: RitoCombat) -> void:
	var volume = attack.get("_volume")
	if volume == null:
		return
	volume.set("_open", true)
	volume.set("_close_at", float(Time.get_ticks_msec()) / 1000.0 + 2.0)


func _wait_health(target: Node, before: float, timeout := 3.0) -> float:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(timeout * 1000.0):
		var combatant := target.get_node_or_null("Combatant") as Combatant
		if combatant != null and not is_equal_approx(combatant.health, before):
			return combatant.health
		await process_frame
	var combatant := target.get_node_or_null("Combatant") as Combatant
	return combatant.health if combatant != null else before


func _wait_ready(rito: Rito, attack: RitoCombat, timeout := 3.0) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(timeout * 1000.0):
		if not rito.is_locked() and float(Time.get_ticks_msec()) / 1000.0 >= attack._cooldown_until:
			return true
		await process_frame
	return false


## Tres eslabones: 1,0x, 1,15x y 1,6x sobre el dano base.
func _test_combo_chain() -> void:
	var rito := await _make_fighter()
	var attack := rito.get_node("Combat") as RitoCombat
	var target := _make_target(Vector3(0, 0.8, 1.6), 400.0, rito)
	# Girado 180 grados: mira al jugador, asi que no entra el critico por la espalda.
	target.rotation.y = PI

	var health := 400.0
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	health = await _wait_health(target, health)
	_check(is_equal_approx(400.0 - health, 34.0), "el primer golpe del combo hace el dano base (34)")

	await _wait_ready(rito, attack)
	attack.set("_combo_until", float(Time.get_ticks_msec()) / 1000.0 + 60.0)
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	var second := health
	health = await _wait_health(target, health)
	_check(is_equal_approx(second - health, 39.1), "el segundo eslabon sube a 1,15x (39,1)")

	await _wait_ready(rito, attack)
	attack.set("_combo_until", float(Time.get_ticks_msec()) / 1000.0 + 60.0)
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	var third := health
	health = await _wait_health(target, health)
	_check(is_equal_approx(third - health, 54.4), "el tercer eslabon sube a 1,6x (54,4)")
	rito.free()


## La cadena se cierra sola: esperar mas que la ventana de enlace devuelve el
## combate al primer golpe.
func _test_combo_resets_after_window() -> void:
	var rito := await _make_fighter()
	var attack := rito.get_node("Combat") as RitoCombat
	var target := _make_target(Vector3(0, 0.8, 1.6), 400.0, rito)
	target.rotation.y = PI

	var health := 400.0
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	health = await _wait_health(target, health)

	await create_timer(1.6).timeout
	await _wait_ready(rito, attack)
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	var before := health
	health = await _wait_health(target, health)
	_check(is_equal_approx(before - health, 34.0), "tras la ventana de enlace la cadena vuelve al primer golpe")
	rito.free()


## Golpear a la espalda vale el doble. El objetivo sin girar mira a +Z y el
## jugador esta a su espalda: ese es el caso del critico.
func _test_critical_from_behind() -> void:
	var rito := await _make_fighter()
	var attack := rito.get_node("Combat") as RitoCombat
	var behind := _make_target(Vector3(0, 0.8, 1.6), 400.0, rito)
	var facing := _make_target(Vector3(0, 0.8, 1.6), 400.0, rito)
	facing.rotation.y = PI

	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	await _wait_health(behind, 400.0)
	await _wait_health(facing, 400.0)
	_check(is_equal_approx(400.0 - _health(behind), 68.0), "el golpe por la espalda hace el doble (68)")
	_check(is_equal_approx(400.0 - _health(facing), 34.0), "de frente no hay critico (34)")
	rito.free()


## El ultimo eslabon deja al bandido vendido: el combate gana espacio para el
## siguiente tajo.
func _test_stagger_on_last_hit() -> void:
	var rito := await _make_fighter()
	var attack := rito.get_node("Combat") as RitoCombat
	var spy := StunSpy.new()
	spy.collision_layer = 4
	spy.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	spy.add_child(shape)
	spy.position = Vector3(0, 0.8, 1.6)
	spy.rotation.y = PI
	rito.add_child(spy)
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	spy.add_child(combatant)
	combatant.setup(400.0)

	var health := 400.0
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	health = await _wait_health(spy, health)
	await _wait_ready(rito, attack)
	attack.set("_combo_until", float(Time.get_ticks_msec()) / 1000.0 + 60.0)
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	health = await _wait_health(spy, health)
	_check(spy.stuns.is_empty(), "los dos primeros golpes no aturden")

	await _wait_ready(rito, attack)
	attack.set("_combo_until", float(Time.get_ticks_msec()) / 1000.0 + 60.0)
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	await _wait_health(spy, health)
	_check(spy.stuns.size() == 1, "el tercer golpe del combo aturde al objetivo")
	if spy.stuns.size() == 1:
		_check(spy.stuns[0] >= 0.6, "el aturdimiento dura lo suficiente para rematar")
	rito.free()


## El numero de dano flotante: sin el, el jugador no sabe cuanto pego.
func _test_damage_numbers() -> void:
	var rito := await _make_fighter()
	var attack := rito.get_node("Combat") as RitoCombat
	# El pool vive en el grupo "damage_numbers" y el combate lo busca ahi.
	var numbers: Node3D = DamageNumberScript.new()
	root.add_child(numbers)
	await process_frame
	var target := _make_target(Vector3(0, 0.8, 1.6), 400.0, rito)
	target.rotation.y = PI

	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	await _wait_health(target, 400.0)
	var pool := get_nodes_in_group("damage_numbers")
	_check(pool.size() > 0, "el golpe muestra un numero de dano")
	if pool.size() > 0:
		var found := false
		for node in pool:
			for child in node.get_children():
				if child is Label3D and "34" in (child as Label3D).text:
					found = true
		_check(found, "el numero de dano muestra el valor del golpe (34)")
	rito.free()


## El moloso cuenta la baja de su victima. Antes reventaba: add_kill no aceptaba
## el argumento que emite la senal killed.
func _test_dog_kill_counts() -> void:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var attack: RitoCombat = RitoCombatScript.new()
	rito.add_child(attack)
	await process_frame
	attack.setup(rito)
	var dog: CharacterBody3D = RomanDogScript.new()
	root.add_child(dog)
	dog.call("setup", rito)
	dog.connect("killed", Callable(attack, "add_kill"))
	var victim := _make_target(Vector3(0, 0.8, 1.0), 10.0, root)
	dog.emit_signal("killed", victim)
	_check(attack.kills == 1, "la baja que reporta el moloso cuenta como baja")
	rito.free()
	dog.free()


## Regresion del critico perpetuo: el bandido entra en STUN dentro del mismo
## take_damage. El primer golpe NO debe ser critico; el segundo, con el objetivo ya
## aturdido, SI. Si el estado se leyera despues del dano, ambos serian 68.
func _test_critical_uses_pre_hit_state() -> void:
	var rito := await _make_fighter()
	var attack := rito.get_node("Combat") as RitoCombat
	var spy := StatefulSpy.new()
	spy.collision_layer = 4
	spy.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	spy.add_child(shape)
	spy.position = Vector3(0, 0.8, 1.6)
	spy.rotation.y = PI
	rito.add_child(spy)
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	spy.add_child(combatant)
	combatant.setup(400.0)
	combatant.damaged.connect(spy._on_damaged)

	var health := 400.0
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	health = await _wait_health(spy, health)
	_check(is_equal_approx(400.0 - health, 34.0), "el golpe que provoca STUN no es critico")
	_check(str(spy.state) == "STUN", "el golpe deja al objetivo aturdido")
	_check(is_equal_approx(_health(spy), 366.0), "el primer golpe aplica solo el dano base")

	await _wait_ready(rito, attack)
	attack.set("_combo_step", 0)
	attack.set("_combo_until", 0.0)
	attack.call("try_attack", false)
	_force_window(attack)
	await physics_frame
	health = await _wait_health(spy, health)
	_check(is_equal_approx(366.0 - health, 68.0), "el golpe con el objetivo ya aturdido es critico")
	rito.free()
