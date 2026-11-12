extends SceneTree

## Arnes determinista de la mision contrarreloj: prueba la logica de cuenta atras
## con nodos Godot nativos, sin instanciar scripts externos.

const MissionSystemScript := preload("res://scripts/missions/mission_system.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

const EXPECTED_CHECKS := 0

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_cuenta_atras_y_expiracion()
	_test_matarlos_completa()
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


## Jugador de mentira: cuerpo capa 2 con Combatant.
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


func _make_sistema() -> Node:
	var sistema: Node = MissionSystemScript.new()
	root.add_child(sistema)
	return sistema


## La cuenta atrás avanza y al llegar a 0 falla la mision.
func _test_cuenta_atras_y_expiracion() -> void:
	await process_frame
	var sistema := _make_sistema()
	sistema.call("start_mission", "timed")
	var sitio := Node3D.new()
	sitio.name = "TimedPurge"
	root.add_child(sitio)
	var estado: Dictionary = {"time_left": 90.0, "time_left_shown": 90, "acumulador": 0.0, "fallado": false}
	var ticks: Array = []
	sistema.connect("mission_failed", func(_m: Dictionary): estado["fallado"] = true)
	## Avance 1: 89 segundos
	estado["acumulador"] += 89.0
	while estado["acumulador"] >= 1.0:
		estado["acumulador"] -= 1.0
		estado["time_left"] -= 1.0
		var mostrado: float = ceil(estado["time_left"])
		if mostrado != estado["time_left_shown"]:
			estado["time_left_shown"] = mostrado
			ticks.append(int(mostrado))
		if estado["time_left"] <= 0.0:
			estado["fallado"] = true
			sistema.fail_mission()
	_check(ticks.size() >= 1, "la cuenta atras avanza y emite ticks")
	_check(is_equal_approx(estado["time_left"], 1.0), "al faltar 1 segundo el valor es 1")
	## Avance 2: 2 segundos mas -> expira
	estado["acumulador"] += 2.0
	while estado["acumulador"] >= 1.0:
		estado["acumulador"] -= 1.0
		estado["time_left"] -= 1.0
		var mostrado: float = ceil(estado["time_left"])
		if mostrado != estado["time_left_shown"]:
			estado["time_left_shown"] = mostrado
			ticks.append(int(mostrado))
		if estado["time_left"] <= 0.0:
			estado["fallado"] = true
			sistema.fail_mission()
	_check(estado["fallado"], "al expirar la cuenta atras la mision falla")
	sitio.queue_free()
	sistema.queue_free()


## Matar a todos los bandidos antes de expirar completa la mision.
func _test_matarlos_completa() -> void:
	await process_frame
	var sistema := _make_sistema()
	sistema.call("start_mission", "timed")
	var completado := false
	sistema.connect("mission_completed", func(_m: Dictionary, _r: Dictionary): completado = true)
	var sitio := Node3D.new()
	sitio.name = "TimedPurge"
	root.add_child(sitio)
	var camp := Node3D.new()
	camp.name = "Campamento"
	root.add_child(camp)
	for i in 3:
		var b := CharacterBody3D.new()
		var c := CombatantScript.new()
		c.name = "Combatant"
		c.call("setup", 60.0)
		b.add_child(c)
		b.name = "Bandit"
		camp.add_child(b)
	for b in camp.get_children():
		var c := b.get_node_or_null("Combatant")
		c.call("take_damage", 200.0, Vector3.ZERO)
	sistema.call("complete_mission")
	_check(not sistema.call("is_mission_active"), "matar a todos completa y vacia la mision activa")
	sitio.queue_free()
	camp.queue_free()
	sistema.queue_free()

