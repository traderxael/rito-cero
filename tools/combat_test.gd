extends SceneTree

## Arnes determinista de combate: sin escena, sin terreno, sin GPU. Cada regla de
## reentrancia que es caro descubrir jugando se comprueba aqui.

const CombatantScript := preload("res://scripts/combat/combatant.gd")
const AttackVolumeScript := preload("res://scripts/combat/attack_volume.gd")
const RitoScript := preload("res://scripts/player/rito.gd")
const RitoCombatScript := preload("res://scripts/player/rito_combat.gd")
const WeaponScript := preload("res://scripts/combat/weapon.gd")
const ProjectileScript := preload("res://scripts/combat/projectile.gd")
const RomanDogScript := preload("res://scripts/npc/roman_dog.gd")
const DogRigScript := preload("res://scripts/npc/dog_rig.gd")
const ArsenalMenuScript := preload("res://scripts/ui/arsenal_menu.gd")

## Un error de runtime dentro de un coroutine aborta el test entero sin lanzar el assert, y
## el arnes se queda en verde con tres de sus siete casos nunca ejecutados. El recuento es lo
## que convierte ese silencio en fallo.
const EXPECTED_CHECKS := 94

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_damage_kills_once()
	_test_damage_after_death_ignored()
	_test_clamp_and_heal()
	_test_invulnerable()
	await _test_reach_hits_and_misses()
	await _test_spear_reach()
	await _test_swing_hits_each_target_once()
	await _test_window_gates_damage()
	await _test_player_respawn()
	await _test_player_attack_lands()
	_test_arsenal_catalog()
	await _test_spatha_reach()
	await _test_pilum_projectile()
	await _test_weapon_switch_updates_geometry()
	await _test_arsenal_menu_equips()
	await _test_dog_bites_and_follows()
	await _test_ragdoll_falls_and_releases()
	await _test_dodge_and_push()
	await _test_dog_rig()
	await _test_dog_knocked_down()
	await _test_idle_animation_recovers()
	_test_dog_call_key()
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


func _make(max_health: float) -> Combatant:
	var combatant: Combatant = CombatantScript.new()
	root.add_child(combatant)
	combatant.setup(max_health)
	return combatant


func _make_target(at: Vector3, max_health: float, parent: Node = null) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	body.add_child(shape)
	body.position = at
	if parent == null:
		parent = root
	parent.add_child(body)
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	body.add_child(combatant)
	combatant.setup(max_health)
	return body


## El volumen vive en el espacio local del modelo, que mira a +Z. Un objetivo a 2,0 m por
## delante y otro a 3,6 m: con alcance 2,2 y radio 0,75 el primero toca y el segundo no.
func _make_volume(reach: float, radius: float) -> AttackVolume:
	var volume: AttackVolume = AttackVolumeScript.new()
	root.add_child(volume)
	volume.setup(reach, radius, 4)
	return volume


func _test_damage_kills_once() -> void:
	var combatant := _make(60.0)
	var deaths := [0]
	combatant.died.connect(func(_p): deaths[0] += 1)
	combatant.take_damage(34.0, Vector3.ZERO)
	_check(combatant.is_alive(), "60hp con 34 de dano sigue vivo")
	_check(is_equal_approx(combatant.health, 26.0), "vida restante 26")
	combatant.take_damage(34.0, Vector3.ONE)
	_check(not combatant.is_alive(), "60hp muerto tras 68 de dano")
	_check(deaths[0] == 1, "died emitido exactamente una vez")


func _test_damage_after_death_ignored() -> void:
	var combatant := _make(60.0)
	var deaths := [0]
	combatant.died.connect(func(_p): deaths[0] += 1)
	combatant.take_damage(999.0, Vector3.ZERO)
	combatant.take_damage(999.0, Vector3.ZERO)
	_check(deaths[0] == 1, "danar a un muerto no re-emite died")
	_check(is_equal_approx(combatant.health, 0.0), "la vida no baja de 0")


func _test_clamp_and_heal() -> void:
	var combatant := _make(100.0)
	combatant.take_damage(-5.0, Vector3.ZERO)
	_check(is_equal_approx(combatant.health, 100.0), "dano negativo no cura")
	combatant.take_damage(30.0, Vector3.ZERO)
	combatant.heal_full()
	_check(combatant.is_alive(), "heal_full revive")
	_check(is_equal_approx(combatant.health, 100.0), "heal_full deja vida llena")


func _test_invulnerable() -> void:
	var combatant := _make(100.0)
	# Ventana larga a proposito: el test mide la regla, no el reloj. Con 0,3 s un
	# stall del proceso entre las dos llamadas caduca la ventana y da un falso rojo.
	combatant.make_invulnerable(60.0)
	combatant.take_damage(50.0, Vector3.ZERO)
	_check(is_equal_approx(combatant.health, 100.0), "invulnerable no recibe dano")
	combatant.take_damage(50.0, Vector3.ZERO)
	_check(is_equal_approx(combatant.health, 100.0), "sigue invulnerable dentro de la ventana")
	combatant.setup(100.0, 0.0)
	combatant.take_damage(50.0, Vector3.ZERO)
	_check(is_equal_approx(combatant.health, 50.0), "setup sin ventana limpia la invulnerabilidad")


func _test_reach_hits_and_misses() -> void:
	var hit := _make_target(Vector3(0, 0.8, 2.0), 60.0)
	var miss := _make_target(Vector3(0, 0.8, 3.6), 60.0)
	var volume := _make_volume(2.2, 0.75)
	volume.begin_swing(34.0, volume, 0.0, 0.6, 1.0)
	for i in 20:
		await process_frame
	_check(is_equal_approx(hit.get_node("Combatant").health, 26.0), "objetivo a 2,0 m recibe el tajo")
	_check(is_equal_approx(miss.get_node("Combatant").health, 60.0), "objetivo a 3,6 m no lo recibe")
	volume.free()
	hit.free()
	miss.free()


## La lanza llega donde el gladius no: alcance 3,4 y radio 0,45 frente a 2,2 y 0,75.
func _test_spear_reach() -> void:
	var hit := _make_target(Vector3(0, 0.8, 3.0), 100.0)
	var miss := _make_target(Vector3(0, 0.8, 4.6), 100.0)
	var volume := _make_volume(3.4, 0.45)
	volume.begin_swing(46.0, volume, 0.0, 0.6, 1.0)
	for i in 20:
		await process_frame
	_check(is_equal_approx(hit.get_node("Combatant").health, 54.0), "la lanza alcanza a 3,0 m")
	_check(is_equal_approx(miss.get_node("Combatant").health, 100.0), "y no a 4,6 m")
	volume.free()
	hit.free()
	miss.free()


## El caso mas frecuente del juego: el NPC ya esta encima cuando la ventana se abre, asi que
## nunca llega a "entrar" en el area. Si solo se escuchara body_entered, no recibira nada.
func _test_swing_hits_each_target_once() -> void:
	var already := _make_target(Vector3(0, 0.8, 1.6), 100.0)
	var volume := _make_volume(2.2, 0.75)
	volume.begin_swing(34.0, volume, 0.0, 0.6, 1.0)
	for i in 20:
		await process_frame
	_check(is_equal_approx(already.get_node("Combatant").health, 66.0),
		"el que ya estaba dentro recibe un unico tajo pese a 20 fotogramas de solape")
	volume.end_swing()
	volume.begin_swing(34.0, volume, 0.0, 0.6, 1.0)
	for i in 20:
		await process_frame
	_check(is_equal_approx(already.get_node("Combatant").health, 32.0),
		"el swing siguiente vuelve a golpear al mismo objetivo")
	volume.free()
	already.free()


func _test_window_gates_damage() -> void:
	var target := _make_target(Vector3(0, 0.8, 1.6), 100.0)
	var volume := _make_volume(2.2, 0.75)
	# Apertura en 0,9 de un clip de 10 s: la ventana sigue cerrada durante los 30 frames.
	volume.begin_swing(34.0, volume, 0.9, 1.0, 10.0)
	for i in 30:
		await process_frame
	_check(is_equal_approx(target.get_node("Combatant").health, 100.0),
		"con la ventana aun cerrada no hay dano")
	_check(volume.is_swinging(), "el swing sigue esperando su ventana")
	volume.end_swing()
	_check(not volume.is_swinging(), "end_swing apaga el swing")

	# Ventana de duracion cero: el primer _process ya la encuentra cerrada, y como el reloj
	# del motor tiene resolucion de milisegundos, cualquier ventana mas corta no es medible.
	volume.begin_swing(34.0, volume, 0.0, 0.0, 1.0)
	for i in 30:
		await process_frame
	_check(not volume.is_swinging(), "la ventana se apaga sola al pasar su cierre")
	_check(is_equal_approx(target.get_node("Combatant").health, 100.0),
		"una ventana de duracion cero no golpea")
	volume.free()
	target.free()


## Rito desnudo, sin World ni Terrain3D: el plan cargaba main.tscn y asi el test dependia
## de cuanto tardara el terreno en generarse para que el Combatant existiera.
func _test_player_respawn() -> void:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var player_combatant: Combatant = CombatantScript.new()
	player_combatant.name = "Combatant"
	rito.add_child(player_combatant)
	await process_frame
	var spawn := Vector3(50.0, 0.0, -30.0)
	rito.bind_combatant(player_combatant, spawn)
	_check(rito.combatant == player_combatant, "Rito queda enlazado a su Combatant")

	player_combatant.take_damage(999.0, Vector3.ZERO)
	_check(not rito.is_alive(), "Rito reporta muerte")
	_check(not player_combatant.is_alive(), "el Combatant de Rito esta muerto")

	var before := float(Time.get_ticks_msec()) / 1000.0
	await create_timer(Rito.RESPAWN_DELAY + 0.6).timeout
	_check(rito.is_alive(), "Rito reaparece tras el retardo")
	_check(player_combatant.is_alive() and is_equal_approx(player_combatant.health, 100.0),
		"reaparece con vida llena")
	_check(is_equal_approx(rito.global_position.x, spawn.x)
		and is_equal_approx(rito.global_position.z, spawn.z), "reaparece en el punto de origen")

	# Se comprueba la ventana que deja la reaparicion, no el tiempo restante: un
	# stall del proceso entre el respawn y el take_damage la caducaba.
	var until := float(player_combatant.get("_invulnerable_until"))
	_check(until >= before + Rito.RESPAWN_DELAY + 1.5,
		"la reaparicion deja 2 s de invulnerabilidad")
	rito.free()


## Unico test que recorre el cableado entero: RitoCombat montando el AttackVolume sobre el
## Model, resolviendo la animacion, respetando la cadencia y firmando el dano.
func _test_player_attack_lands() -> void:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var player_combatant: Combatant = CombatantScript.new()
	player_combatant.name = "Combatant"
	rito.add_child(player_combatant)
	var attack: RitoCombat = RitoCombatScript.new()
	rito.add_child(attack)
	await process_frame
	player_combatant.setup(100.0, 0.0)
	rito.bind_combatant(player_combatant, Vector3.ZERO)
	attack.setup(rito)

	# Hijo de Rito para que caiga con el: sin terreno ambos caen, y si el objetivo se queda
	# quieto el volumen se le separa por altura antes de terminar el barrido.
	var victim := _make_target(Vector3(0, 0.8, 2.0), 100.0, rito)
	rito.model.rotation.y = 0.0
	# Mirado al jugador: de espaldas el tajo entra critico y hace el doble, y ese
	# caso lo comprueba el arnes del combo.
	victim.rotation.y = PI
	_check(attack.weapon_index == 0, "Rito empieza con el gladius")

	var first_ok := attack._try_attack(false)
	_check(first_ok, "el primer tajo arranca")
	_force_window(attack)
	await physics_frame
	var health := await _wait_health(victim, 100.0)
	_check(is_equal_approx(health, 66.0),
		"el tajo del jugador alcanza a un objetivo a 2,0 m")
	_check(attack.kills == 0, "un objetivo con vida no cuenta como baja")

	# La cadencia se prueba con un cooldown sintetico: con el real, un stall del
	# proceso entre las dos llamadas deja pasar el segundo golpe.
	var cooldown_before := attack._cooldown_until
	attack.set("_cooldown_until", float(Time.get_ticks_msec()) / 1000.0 + 60.0)
	var blocked := not attack._try_attack(false)
	attack.set("_cooldown_until", cooldown_before)
	_check(blocked, "la cadencia no permite un segundo golpe inmediato")

	# El segundo tajo es el segundo eslabon del combo: 1,15x (39,1 de dano).
	await _wait_ready(rito, attack)
	attack.set("_combo_until", float(Time.get_ticks_msec()) / 1000.0 + 60.0)
	attack._try_attack(false)
	_force_window(attack)
	await physics_frame
	health = await _wait_health(victim, health)
	_check(is_equal_approx(health, 26.9),
		"pasada la cadencia vuelve a golpear")

	# Baja solo lo que mata el propio volumen: danar al Combatant por fuera no emite landed.
	await _wait_ready(rito, attack)
	attack.set("_combo_until", float(Time.get_ticks_msec()) / 1000.0 + 60.0)
	attack._try_attack(false)
	_force_window(attack)
	await physics_frame
	health = await _wait_health(victim, health)
	_check(not victim.get_node("Combatant").is_alive(), "el tercer tajo remata al objetivo")
	_check(attack.kills == 1, "matar al objetivo suma una baja")
	rito.free()


## El catalogo es la fuente de verdad del arsenal: las cinco armas con un id cada
## una, los dos modos de combate y la spatha por encima del gladius.
func _test_arsenal_catalog() -> void:
	var catalog: Array = WeaponScript.CATALOG
	_check(catalog.size() == 5, "el arsenal tiene cinco armas")
	var ids := {}
	var modes := {}
	for weapon: Dictionary in catalog:
		ids[weapon["id"]] = true
		modes[weapon["mode"]] = true
	_check(ids.size() == 5, "las cinco armas tienen id distinto")
	_check(modes.has(WeaponScript.MODE_MELEE), "hay armas de cuerpo a cuerpo")
	_check(modes.has(WeaponScript.MODE_THROW), "hay un arma de lanzamiento")
	var gladius: Dictionary = WeaponScript.get_weapon(WeaponScript.index_of("gladius"))
	var spatha: Dictionary = WeaponScript.get_weapon(WeaponScript.index_of("spatha"))
	_check(float(spatha["damage"]) > float(gladius["damage"]), "la spatha hace mas dano que el gladius")
	_check(float(spatha["reach"]) > float(gladius["reach"]), "la spatha alcanza mas lejos que el gladius")


## La spatha llega mas lejos que el gladius pero no es un alcance infinito. El alcance
## que cuenta es el efectivo: la esfera del volumen va centrada en el alcance con su
## radio, asi que la spatha cubre hasta 2,6 + 0,70 = 3,3 m y el gladius hasta 2,95 m.
## El objetivo se pone a 4,0 m porque su propia esfera (0,4 de radio) llega a 3,6 m.
func _test_spatha_reach() -> void:
	var hit := _make_target(Vector3(0, 0.8, 2.4), 100.0)
	var miss := _make_target(Vector3(0, 0.8, 4.0), 100.0)
	var volume := _make_volume(2.6, 0.70)
	volume.begin_swing(58.0, volume, 0.0, 0.6, 1.0)
	for i in 20:
		await process_frame
	_check(is_equal_approx(hit.get_node("Combatant").health, 42.0), "la spatha alcanza a 2,4 m")
	_check(is_equal_approx(miss.get_node("Combatant").health, 100.0), "y no a 4,0 m")
	volume.free()
	hit.free()
	miss.free()


## El pilum barre con todo el astil: el raycast va de la cola a la punta, asi que un
## objetivo a 6 m recibe el golpe aunque la punta todavia no haya llegado a el.
func _test_pilum_projectile() -> void:
	var target := _make_target(Vector3(0, 0.8, 6.0), 100.0)
	var projectile := ProjectileScript.new()
	root.add_child(projectile)
	projectile.setup(Vector3(0, 0.8, 0.0), Vector3(0, 0, 1), 40.0, 26.0, 26.0)
	for i in 20:
		await physics_frame
	_check(is_equal_approx(target.get_node("Combatant").health, 60.0),
		"el pilum en vuelo daña al objetivo que tiene delante")

	var aside := _make_target(Vector3(9, 0.8, 6.0), 100.0)
	var stray := ProjectileScript.new()
	root.add_child(stray)
	stray.setup(Vector3(0, 0.8, 0.0), Vector3(0, 0, 1), 40.0, 26.0, 26.0)
	for i in 20:
		await physics_frame
	_check(is_equal_approx(aside.get_node("Combatant").health, 100.0),
		"el pilum no daña a quien no tiene delante")

	var dead := _make_target(Vector3(0, 0.8, 6.0), 10.0)
	dead.get_node("Combatant").take_damage(999.0, Vector3.ZERO)
	var corpse_projectile := ProjectileScript.new()
	root.add_child(corpse_projectile)
	corpse_projectile.setup(Vector3(0, 0.8, 0.0), Vector3(0, 0, 1), 40.0, 26.0, 26.0)
	var landed := [0]
	corpse_projectile.landed.connect(
		func(_target: Node, _damage: float, _was_stunned: bool) -> void: landed[0] += 1)
	corpse_projectile._on_hit(dead, dead.global_position)
	_check(landed[0] == 0, "el pilum no cuenta un cadaver como baja")
	dead.free()
	corpse_projectile.free()


## Cambiar de arma no es cambiar un dibujo: cambia el alcance, el dano y el modo.
func _test_weapon_switch_updates_geometry() -> void:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var attack: RitoCombat = RitoCombatScript.new()
	rito.add_child(attack)
	await process_frame
	attack.setup(rito)

	_check(attack.weapon_index == 0, "el arsenal arranca en el gladius")
	_check(is_equal_approx(rito.weapons.current_reach(), 2.2), "el gladius alcanza 2,2 m")

	attack.switch_weapon(2)
	_check(attack.weapon_index == 2, "cambiar de arma mueve el indice")
	_check(is_equal_approx(rito.weapons.current_reach(), 2.6), "la spatha cambia el alcance en la mano")
	_check(is_equal_approx(rito.weapons.current_damage(), 58.0), "la spatha hace 58 de dano")
	_check(rito.weapons.current_mode() == WeaponScript.MODE_MELEE, "la spatha es de cuerpo a cuerpo")

	attack.switch_weapon(1)
	_check(rito.weapons.current_mode() == WeaponScript.MODE_THROW, "el pilum es de lanzamiento")
	_check(rito.weapons.current_name() == "Pilum", "el arma activa es el pilum")
	rito.free()


## El menu no decora: equipar desde el panel cambia el arma de verdad.
func _test_arsenal_menu_equips() -> void:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var attack: RitoCombat = RitoCombatScript.new()
	rito.add_child(attack)
	await process_frame
	attack.setup(rito)

	var menu: CanvasLayer = ArsenalMenuScript.new()
	root.add_child(menu)
	menu.call("setup", rito, attack)
	menu.call("equip", 2)
	_check(attack.weapon_index == 2, "el menu de arsenal equipa el arma elegida")
	_check(is_equal_approx(rito.weapons.current_damage(), 58.0), "el arma equipada es la spatha")
	menu.call("open")
	_check(bool(menu.call("is_open")), "el menu de arsenal se abre")
	menu.call("close")
	_check(not bool(menu.call("is_open")), "el menu de arsenal se cierra")
	menu.free()
	rito.free()


## El moloso muerde al bandido que tiene al lado y, sin enemigos, vuelve con su amo.
func _test_dog_bites_and_follows() -> void:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var dog: CharacterBody3D = RomanDogScript.new()
	root.add_child(dog)
	dog.call("setup", rito)
	rito.global_position = Vector3(0, 0, 0)
	dog.global_position = Vector3(0, 0, 12)

	var bandit := _make_target(Vector3(0, 0.8, 11.0), 100.0)
	bandit.add_to_group("hostiles")
	for i in 20:
		await physics_frame
	_check(is_equal_approx(bandit.get_node("Combatant").health, 82.0),
		"el moloso muerde al bandido que tiene al lado")
	_check(str(dog.get("state")) == "BITE", "el moloso esta en estado de mordida")

	bandit.remove_from_group("hostiles")
	bandit.queue_free()
	for i in 90:
		await physics_frame
	var distance := Vector2(
		dog.global_position.x - rito.global_position.x,
		dog.global_position.z - rito.global_position.z).length()
	_check(distance < 9.0, "sin enemigos el moloso vuelve con Rito")
	rito.free()
	dog.free()


## El ragdoll es la parte que mas caro sale descubrir jugando: si la pelvis queda
## anclada a la pose de reposo, el corpse cuelga en el aire en vez de desplomarse, y si
## el esqueleto no sigue a los cuerpos, la malla se queda en la pose de la animacion
## mientras la fisica mueve los cuerpos por debajo.
func _test_ragdoll_falls_and_releases() -> void:
	_add_floor()
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var player_combatant: Combatant = CombatantScript.new()
	player_combatant.name = "Combatant"
	rito.add_child(player_combatant)
	await process_frame
	player_combatant.setup(100.0, 0.0)
	rito.bind_combatant(player_combatant, Vector3.ZERO)

	player_combatant.take_damage(999.0, Vector3.ZERO)
	_check(not rito.is_alive(), "Rito muere y entra en el retardo de reaparicion")

	# La fisica toma el relevo a los 1,5 s, con el corpse ya tumbado por la animacion.
	await create_timer(Rito.RAGDOLL_DELAY + 0.5).timeout
	_check(rito.is_ragdoll_active(), "la fisica del corpse se enciende tras la muerte")

	var skeleton := _find_skeleton(rito)
	var head := skeleton.find_bone("DEF-head")
	var head_y := skeleton.get_bone_global_pose(head).origin.y
	_check(head_y > -0.05 and head_y < 0.45, "el corpse se queda tumbado en el suelo")

	# El esqueleto tiene que seguir a los cuerpos: si no, la malla se queda en la pose de
	# la animacion mientras la fisica mueve los cuerpos por debajo.
	var bodies: Array = rito.get("_ragdoll_bones")
	var body_y := 0.0
	for node in bodies:
		var bone := node as PhysicalBone3D
		if bone != null and str(bone.bone_name) == "DEF-head":
			body_y = bone.global_position.y
	_check(absf(head_y - body_y) < 0.25, "el esqueleto sigue a los cuerpos")

	await create_timer(Rito.RESPAWN_DELAY).timeout
	_check(rito.is_alive(), "Rito reaparece con el corpse en el suelo")
	_check(not rito.is_ragdoll_active(), "la fisica se apaga al reaparecer")
	_check((rito.get("_ragdoll_bones") as Array).is_empty(), "los cuerpos rigidos se liberan")
	rito.free()


## La esquiva y el empujon: los dos mueven al jugador de verdad, no solo su animacion.
func _test_dodge_and_push() -> void:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var player_combatant: Combatant = CombatantScript.new()
	player_combatant.name = "Combatant"
	rito.add_child(player_combatant)
	await process_frame
	player_combatant.setup(100.0, 0.0)
	rito.bind_combatant(player_combatant, Vector3.ZERO)

	var before_now := float(Time.get_ticks_msec()) / 1000.0
	_check(rito.try_dodge(Vector3(1, 0, 0)), "la esquiva acepta la peticion")
	_check(rito.velocity.x > 5.0, "la esquiva aplica el impulso")
	# Se mide el delta que deja la esquiva, no el tiempo restante: un stall del
	# proceso entre la llamada y el assert no invalida la ventana concedida.
	var until := float(player_combatant.get("_invulnerable_until"))
	_check(until >= before_now + 0.3, "la esquiva da invulnerabilidad")
	var ready := float(rito.get("_dodge_ready_at"))
	_check(ready >= before_now + 0.7, "la esquiva deja el enfriamiento armado")
	rito.set("_dodge_ready_at", before_now + 60.0)
	_check(not rito.try_dodge(Vector3(1, 0, 0)), "la esquiva respeta el enfriamiento")

	rito.apply_push(Vector3(0, 0, 1), 9.0)
	var push: Vector3 = rito.get("_push_velocity")
	_check(push.z > 5.0, "el empujon fisico mueve al jugador")
	await create_timer(0.5).timeout
	var faded: Vector3 = rito.get("_push_velocity")
	_check(faded.length() < push.length(), "el empujon se desvanece solo")
	rito.free()


## El rig del moloso: 21 huesos, las piezas atadas a su hueso y los seis clips.
func _test_dog_rig() -> void:
	var rig = DogRigScript.new()
	root.add_child(rig)
	rig.build()
	await process_frame
	_check(rig.bone_count() == 21, "el moloso tiene 21 huesos")

	var pieces := 0
	var worst := 0.0
	for child in rig.skeleton.get_children():
		var attachment := child as BoneAttachment3D
		if attachment == null:
			continue
		var instance := attachment.get_child(0) as MeshInstance3D
		if instance == null:
			continue
		pieces += 1
		worst = maxf(worst, instance.global_position.distance_to(attachment.global_position))
	_check(pieces == 19, "las 19 piezas estan atadas a su hueso")
	_check(worst < 0.05, "cada pieza cuelga de su hueso y no del origen")

	for clip in ["IDLE", "WALK", "RUN", "BITE", "DOWN", "GET_UP"]:
		if not rig.player.has_animation(clip):
			_check(false, "falta el clip " + clip)
			break
	_check(rig.player.get_animation_list().size() == 6, "el moloso tiene los seis clips")

	var head: int = rig.skeleton.find_bone("head")
	var before: Vector3 = rig.skeleton.get_bone_global_pose(head).origin
	rig.play("WALK")
	await create_timer(0.2).timeout
	var after: Vector3 = rig.skeleton.get_bone_global_pose(head).origin
	_check(before.distance_to(after) > 0.005, "la animacion mueve el esqueleto")
	rig.free()


## El moloso no muere: se tumba de verdad, rueda en un cuerpo rigido y se levanta.
func _test_dog_knocked_down() -> void:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var dog: CharacterBody3D = RomanDogScript.new()
	root.add_child(dog)
	dog.call("setup", rito)
	await process_frame

	var dog_combatant: Combatant = dog.get_node_or_null("Combatant")
	_check(dog_combatant != null, "el moloso tiene vida")
	dog_combatant.take_damage(999.0, Vector3.ZERO)
	await physics_frame
	_check(str(dog.get("state")) == "DOWN", "el moloso se tumba al perder toda la vida")
	var rig := dog.get_node_or_null("Model/Rig")
	_check(rig == null, "el visual se va al cuerpo rigido del tumbo")

	await create_timer(1.8).timeout
	_check(str(dog.get("state")) == "FOLLOW", "el moloso se levanta")
	_check(dog.get_node_or_null("Model/Rig") != null, "el visual vuelve al moloso")
	_check(dog_combatant.is_alive(), "el moloso recupera la vida")
	rito.free()
	dog.free()


## Quedarse quieto tiene que apagar el walk: si el modelo solo se actualiza andando, la
## animacion de caminar se queda pegada para siempre y el bloqueo de animacion no decae.
func _test_idle_animation_recovers() -> void:
	_add_floor()
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	await process_frame
	var walk: String = rito.get("_resolved_walk")
	var idle: String = rito.get("_resolved_idle")
	Input.action_press("move_forward")
	for i in 40:
		await physics_frame
	_check(walk != "" and str(rito.get("_animation_state")) == walk,
		"andando entra la animacion de caminar")
	Input.action_release("move_forward")
	for i in 30:
		await physics_frame
	_check(idle != "" and str(rito.get("_animation_state")) == idle,
		"al soltar la entrada vuelve la animacion de reposo")
	_check(rito.animation_player.current_animation == idle,
		"el AnimationPlayer reproduce el reposo")
	rito.free()


## El silbido del moloso no puede compartir tecla con la esquiva: con la misma F,
## pulsar una vez hacia las dos cosas a la vez.
func _test_dog_call_key() -> void:
	var dog_key := 0
	for event in InputMap.action_get_events("call_dog"):
		var key := event as InputEventKey
		if key != null:
			dog_key = key.physical_keycode
	_check(dog_key == KEY_C, "el silbido del moloso va en la tecla C")
	var dodge_keys := []
	for event in InputMap.action_get_events("dodge"):
		var key := event as InputEventKey
		if key != null:
			dodge_keys.append(key.physical_keycode)
	_check(not dodge_keys.has(dog_key), "esquivar y silbar no comparten tecla")


## Un suelo para las pruebas que necesitan que algo caiga de verdad.
func _force_window(attack: RitoCombat, hold_seconds := 2.0) -> void:
	var volume: AttackVolume = attack.get("_volume")
	if volume == null:
		return
	volume.set("_open", true)
	volume.set("_close_at", float(Time.get_ticks_msec()) / 1000.0 + hold_seconds)


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


func _add_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Suelo"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.position = Vector3(0, -0.5, 0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
