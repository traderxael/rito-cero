extends SceneTree

## Regresion del game feel del controlador: coyote time, jump buffer, camara suave,
## FOV de sprint y dip de aterrizaje. Cada mejora tiene un check positivo y uno negativo.

const RitoScript := preload("res://scripts/player/rito.gd")

const EXPECTED_CHECKS := 12

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_coyote_valid()
	await _test_coyote_expired()
	await _test_buffer_valid()
	await _test_buffer_expired()
	await _test_camera_lag()
	await _test_camera_recovery()
	await _test_fov_sprint()
	await _test_fov_walk()
	await _test_land_dip_active()
	await _test_land_dip_decay()
	await _test_normal_jump()
	await _test_no_double_jump()
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


func _add_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Suelo"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -0.5, 0)
	root.add_child(body)
	return body


func _make_rito() -> Rito:
	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	return rito


## Coyote: saltar 3 frames despues de dejar el suelo (0.05s < 0.12s) debe funcionar.
func _test_coyote_valid() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3(0, 0.01, 0)
	for i in 5:
		await physics_frame
	floor_body.queue_free()
	await process_frame
	# 3 frames en el aire: todavia dentro de la ventana coyote.
	await physics_frame
	await physics_frame
	await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	_check(rito.velocity.y > 0.0, "coyote: salta 3 frames tras dejar el suelo")
	rito.queue_free()
	await process_frame


## Coyote expirado: 10 frames (0.167s > 0.12s) ya no permite saltar.
func _test_coyote_expired() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3(0, 0.01, 0)
	for i in 5:
		await physics_frame
	floor_body.queue_free()
	await process_frame
	for i in 10:
		await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	_check(rito.velocity.y < 0.0, "coyote expirado: no salta tras 10 frames en el aire")
	rito.queue_free()
	await process_frame


## Buffer: presionar salto poco antes de aterrizar (desde 0.2m) ejecuta el salto al tocar.
func _test_buffer_valid() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3(0, 0.2, 0)
	await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	# Cae ~7 frames, el buffer se consume al aterrizar y salta.
	for i in 12:
		await physics_frame
	_check(rito.velocity.y > 0.0, "buffer: salta al aterrizar si se presiono poco antes")
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## Buffer expirado: presionar salto mucho antes de aterrizar (desde 3m) no ejecuta nada.
func _test_buffer_expired() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3(0, 3.0, 0)
	await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for i in 40:
		await physics_frame
	_check(rito.is_on_floor() and rito.velocity.y <= 0.01, "buffer expirado: no salta si se presiono demasiado pronto")
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## Camara suave: tras mover al jugador 5m, la camara no esta en el target en 1 frame.
func _test_camera_lag() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3.ZERO
	await physics_frame
	await physics_frame
	rito.global_position = Vector3(5, 0, 0)
	await physics_frame
	var pivot := rito.camera_pitch.get_parent() as Node3D
	var desired := rito.camera_pitch.global_transform * Vector3(0, 0, 5.6)
	var dist := rito.camera.global_position.distance_to(desired)
	_check(dist > 0.1, "camara suave: hay lag tras un teleport (dist=%.3f)" % dist)
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## Camara suave: tras 30 frames la camara converge al target.
func _test_camera_recovery() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3.ZERO
	await physics_frame
	await physics_frame
	rito.global_position = Vector3(5, 0, 0)
	for i in 30:
		await physics_frame
	var pivot := rito.camera_pitch.get_parent() as Node3D
	var desired := rito.camera_pitch.global_transform * Vector3(0, 0, 5.6)
	var dist := rito.camera.global_position.distance_to(desired)
	_check(dist < 0.05, "camara suave: converge tras 30 frames (dist=%.3f)" % dist)
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## FOV de sprint: tras 30 frames corriendo, FOV > 72.
func _test_fov_sprint() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3.ZERO
	await physics_frame
	Input.action_press("sprint")
	Input.action_press("move_forward")
	for i in 30:
		await physics_frame
	_check(rito.camera.fov > 72.0, "FOV sprint: sube por encima de 72 (fov=%.1f)" % rito.camera.fov)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## FOV walk: tras soltar sprint y 30 frames, FOV vuelve a < 69.
func _test_fov_walk() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3.ZERO
	await physics_frame
	Input.action_press("sprint")
	Input.action_press("move_forward")
	for i in 30:
		await physics_frame
	Input.action_release("sprint")
	for i in 30:
		await physics_frame
	_check(rito.camera.fov < 69.0, "FOV walk: vuelve por debajo de 69 (fov=%.1f)" % rito.camera.fov)
	Input.action_release("move_forward")
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## Dip de aterrizaje: al tocar suelo tras un salto, _land_dip > 0.
func _test_land_dip_active() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3(0, 0.01, 0)
	for i in 5:
		await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	# Esperar a que aterrice (salto dura ~36 frames a 60fps).
	var landed := false
	for i in 60:
		await physics_frame
		if rito.is_on_floor() and rito.velocity.y <= 0.0 and i > 5:
			landed = true
			break
	var dip_val = rito.get("_land_dip")
	_check(landed and dip_val != null and dip_val > 0.0, "dip: activo en el frame de aterrizaje")
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## Dip decaido: tras 20 frames en el suelo, _land_dip == 0.
func _test_land_dip_decay() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3(0, 0.01, 0)
	for i in 5:
		await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	for i in 60:
		await physics_frame
		if rito.is_on_floor() and rito.velocity.y <= 0.0 and i > 5:
			break
	for i in 20:
		await physics_frame
	var dip_val = rito.get("_land_dip")
	_check(dip_val != null and is_zero_approx(dip_val), "dip: decae a cero tras 20 frames")
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## Salto normal sigue funcionando: en el suelo, presionar jump sube.
func _test_normal_jump() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3(0, 0.01, 0)
	for i in 5:
		await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	_check(rito.velocity.y > 0.0, "salto normal: funciona estando en el suelo")
	rito.queue_free()
	floor_body.queue_free()
	await process_frame


## Sin doble salto: en el aire tras un salto, jump no vuelve a impulsar.
func _test_no_double_jump() -> void:
	var floor_body := _add_floor()
	var rito := _make_rito()
	rito.global_position = Vector3(0, 0.01, 0)
	for i in 5:
		await physics_frame
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	# 10 frames en el aire: el coyote ya se consumio con el primer salto.
	for i in 10:
		await physics_frame
	var vel_before := rito.velocity.y
	Input.action_press("jump")
	await physics_frame
	Input.action_release("jump")
	await physics_frame
	_check(rito.velocity.y < vel_before, "sin doble salto: jump en el aire no impulsa")
	rito.queue_free()
	floor_body.queue_free()
	await process_frame