extends SceneTree

## El moloso tiene que poder seguir a Rito cuando este corre. Rito corre a 12 m/s
## (RUN_SPEED) y el perro, si sigue a 7, se queda atras para siempre: el amo
## desaparece y el companero se queda en el valle.

const RomanDogScript := preload("res://scripts/npc/roman_dog.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

## Velocidad de sprint del jugador, la misma constante de rito.gd.
const PLAYER_SPRINT := 12.0

## El amo de mentira tiene que moverse desde _physics_process: si se mueve a mano
## desde fuera del paso de fisica, Jolt no actualiza su colisionador y el perro se
## queda atascado contra un cuerpo que en realidad se ha ido.
class FakePlayer extends CharacterBody3D:
	var speed := 0.0

	func _physics_process(_delta: float) -> void:
		velocity = Vector3(0, 0, speed)
		move_and_slide()

const EXPECTED_CHECKS := 6

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_add_floor()
	await _test_catches_up_with_sprint()
	await _test_call_to_player()
	await _test_stays_close_when_walking()
	await _test_ignores_corpses()
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


func _add_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Suelo"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)


func _make_player() -> CharacterBody3D:
	var player := FakePlayer.new()
	player.collision_layer = 2
	player.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	player.add_child(shape)
	root.add_child(player)
	return player


func _make_dog(player: CharacterBody3D, at: Vector3) -> CharacterBody3D:
	var dog: CharacterBody3D = RomanDogScript.new()
	root.add_child(dog)
	dog.call("setup", player)
	dog.global_position = at
	return dog


## El caso real: Rito echa a correr en linea recta y el moloso, que va detras, tiene
## que alcanzarle. El perro arranca 20 m detras: si corre a 7 no lo alcanza nunca.
func _test_catches_up_with_sprint() -> void:
	var player := _make_player()
	player.global_position = Vector3(0, 0, 0)
	var dog := _make_dog(player, Vector3(0, 0, -20))

	var closest := 999.0
	for i in 600:
		(player as FakePlayer).speed = PLAYER_SPRINT
		await physics_frame
		closest = minf(closest, player.global_position.distance_to(dog.global_position))
	print("DEBUG perro pos=", dog.global_position, " vel=", dog.velocity, " estado=", dog.get("state"), " closest=", closest)
	_check(closest < 5.0, "el moloso alcanza a Rito aunque corra a 12 m/s")
	player.queue_free()
	dog.queue_free()
	await process_frame


## El silbido lo llama: deja lo que sea y vuelve.
func _test_call_to_player() -> void:
	var player := _make_player()
	player.global_position = Vector3(0, 0, 0)
	var dog := _make_dog(player, Vector3(0, 0, 16))
	await physics_frame

	dog.call("call_to_player")
	# La aceleracion es de 9 m/s2: hacen falta mas de un segundo para llegar a 10 m/s.
	for i in 90:
		await physics_frame
	var speed := Vector2(dog.velocity.x, dog.velocity.z).length()
	_check(speed > 10.0, "el silbido pone al moloso a correr")

	var before := player.global_position.distance_to(dog.global_position)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 5000:
		await physics_frame
		if player.global_position.distance_to(dog.global_position) < 6.0:
			break
	var after := player.global_position.distance_to(dog.global_position)
	_check(after < 6.0, "el silbido lo trae de vuelta con el amo")
	player.queue_free()
	dog.queue_free()
	await process_frame


## Caminando, el moloso se queda a la altura de su amo.
func _test_stays_close_when_walking() -> void:
	var player := _make_player()
	player.global_position = Vector3(0, 0, 0)
	var dog := _make_dog(player, Vector3(0, 0, -20))

	for i in 240:
		(player as FakePlayer).speed = 6.0
		await physics_frame
		if i % 60 == 0:
			var punto: Vector3 = dog.call("_escort_point")
			print("DEBUG paso ", i, " punto=", punto, " perro=", dog.global_position, " vel=", dog.velocity, " estado=", dog.get("state"))
	var distance := player.global_position.distance_to(dog.global_position)
	_check(distance < 6.0, "caminando el moloso no se queda atras")
	# Sin esto, el jugador y el perro de este caso se quedan en el arbol y el
	# siguiente test choca contra sus colisionadores.
	player.queue_free()
	dog.queue_free()
	await process_frame


## Un cadaver sigue en "hostiles" durante CORPSE_SECONDS. El moloso no puede
## morderlo ni emitir killed: main sumaria una baja falsa por cada mordisco.
func _test_ignores_corpses() -> void:
	var player := _make_player()
	player.global_position = Vector3.ZERO
	var dog := _make_dog(player, Vector3(0, 0, 2.0))
	var dead := _make_bandit(Vector3(0, 0, 1.0))
	dead.add_to_group("hostiles")
	var combatant := dead.get_node("Combatant") as Combatant
	combatant.take_damage(999.0, Vector3.ZERO)
	var kills := [0]
	dog.connect("killed", func(_target: Node) -> void: kills[0] += 1)
	for i in 120:
		await physics_frame
	_check(kills[0] == 0, "el moloso no cuenta un cadaver como baja")
	_check(str(dog.get("state")) != "BITE", "el moloso no muerde un cadaver")
	player.queue_free()
	dog.queue_free()
	dead.queue_free()
	await process_frame


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
	var combatant := CombatantScript.new()
	combatant.name = "Combatant"
	body.add_child(combatant)
	combatant.setup(10.0)
	return body
