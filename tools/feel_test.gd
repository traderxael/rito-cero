extends SceneTree

## Arnes del game feel: hit-stop y shake de Feel, rafagas de ImpactFx, y el cableado de
## sonidos/particulas en el combate del jugador. El reloj de Feel es wall-clock, asi que
## los chequeos de restauracion esperan milisegundos reales y no fotogramas escalados.

const SfxScript := preload("res://scripts/audio/sfx.gd")
const FeelScript := preload("res://scripts/fx/feel.gd")
const ImpactFxScript := preload("res://scripts/fx/impact_fx.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")
const RitoScript := preload("res://scripts/player/rito.gd")
const RitoCombatScript := preload("res://scripts/player/rito_combat.gd")

const EXPECTED_CHECKS := 27

var _failures := 0
var _checks_run := 0


func _init() -> void:
	await _test_hit_stop()
	await _test_shake()
	await _test_impact_types()
	await _test_burst()
	await _test_combat_wiring()
	if _checks_run != EXPECTED_CHECKS:
		_failures += 1
		print("FAIL solo se ejecutaron ", _checks_run, " de ", EXPECTED_CHECKS, " checks")
	Engine.time_scale = 1.0
	print("TEST failures=", _failures, " checks=", _checks_run)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks_run += 1
	if not condition:
		_failures += 1
		print("FAIL ", label)
	else:
		print("ok ", label)


func _wait_wall(milliseconds: int) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < milliseconds:
		await process_frame


func _wait_unfrozen(feel: Feel, timeout := 3.0) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(timeout * 1000.0):
		if not feel.is_frozen() and Engine.time_scale == 1.0:
			return
		await process_frame


func _test_hit_stop() -> void:
	var feel: Feel = FeelScript.new()
	root.add_child(feel)
	feel.hit_stop(0.20)
	# El check sensible al reloj va antes del primer print: en frio, la consola puede
	# tardar mas de 200 ms en arrancar y caducar la ventana antes de evaluarla.
	_check(feel.is_frozen(), "is_frozen true durante el hit-stop")
	_check(Engine.time_scale < 1.0, "hit_stop baja la escala de tiempo")
	await _wait_wall(300)
	_check(Engine.time_scale == 1.0, "la escala de tiempo se restaura sola")
	_check(not feel.is_frozen(), "is_frozen falso tras la ventana")
	feel.free()


func _test_shake() -> void:
	var feel: Feel = FeelScript.new()
	root.add_child(feel)
	feel.shake(0.6, 0.25)
	var offset := feel.camera_offset()
	_check(offset.length() > 0.001, "el shake mueve la camara dentro de la ventana")
	await _wait_wall(350)
	_check(feel.camera_offset() == Vector3.ZERO, "el shake vuelve a cero exacto al caducar")
	feel.free()


## Los tipos de impacto modulan el hit-stop: strong 1,5x con 0,2 de shake, critical 2x
## con 0,4. La duracion se comprueba contra `_restore_at` (no contra el reloj de pared:
## un frame lento de la maquina convierte ese margen en un falso rojo).
func _test_impact_types() -> void:
	var strong: Feel = FeelScript.new()
	root.add_child(strong)
	var start := float(Time.get_ticks_msec()) / 1000.0
	strong.hit_stop(0.3, Feel.IMPACT_TYPE_STRONG)
	_check(strong.is_frozen(), "strong congela el tiempo")
	_check(is_equal_approx(float(strong.get("_shake_amount")), 0.2), "strong anade 0.2 de shake")
	_check(absf(float(strong.get("_restore_at")) - start - 0.45) < 0.05,
		"strong dura 1,5x (450 ms)")
	await _wait_unfrozen(strong)
	_check(not strong.is_frozen() and Engine.time_scale == 1.0, "strong se restaura solo")
	strong.free()

	var critical: Feel = FeelScript.new()
	root.add_child(critical)
	start = float(Time.get_ticks_msec()) / 1000.0
	critical.hit_stop(0.3, Feel.IMPACT_TYPE_CRITICAL)
	_check(critical.is_frozen(), "critical congela el tiempo")
	_check(is_equal_approx(float(critical.get("_shake_amount")), 0.4), "critical anade 0.4 de shake")
	_check(absf(float(critical.get("_restore_at")) - start - 0.6) < 0.05,
		"critical dura 2x (600 ms)")
	await _wait_unfrozen(critical)
	_check(not critical.is_frozen() and Engine.time_scale == 1.0, "critical se restaura solo")
	critical.free()

	# Con shake previo 0.3, strong tiene que dejar 0.5: si el delta local ya incluye el
	# shake activo y luego se vuelve a sumar, el resultado salta a 0.6 (doble suma).
	var capped: Feel = FeelScript.new()
	root.add_child(capped)
	capped.shake(0.3, 1.0)
	capped.hit_stop(0.05, Feel.IMPACT_TYPE_STRONG)
	_check(is_equal_approx(float(capped.get("_shake_amount")), 0.5),
		"el shake de strong se suma una sola vez al activo")
	capped.shake(0.5, 1.0)
	capped.hit_stop(0.05, Feel.IMPACT_TYPE_CRITICAL)
	_check(is_equal_approx(float(capped.get("_shake_amount")), Feel.MAX_SHAKE),
		"el shake acumulado no pasa del tope")
	Engine.time_scale = 1.0
	capped.free()

	# Un hit-stop normal no toca el shake en curso: ni su intensidad ni su ventana.
	var normal: Feel = FeelScript.new()
	root.add_child(normal)
	normal.shake(0.3, 1.0)
	normal.hit_stop(0.05)
	_check(is_equal_approx(float(normal.get("_shake_seconds")), 1.0),
		"el hit-stop normal no pisa la ventana del shake activo")
	Engine.time_scale = 1.0
	normal.free()


func _test_burst() -> void:
	var fx: ImpactFx = ImpactFxScript.new()
	root.add_child(fx)
	await process_frame
	fx.burst(Vector3(5, 1, 0), Color(0.8, 0.1, 0.05))
	_check(fx.active_count() >= 1, "burst enciende una rafaga del pool")
	_check(fx.last_burst_amount() == ImpactFx.NORMAL_AMOUNT, "rafaga normal usa el cupo normal")
	fx.burst(Vector3(5, 1, 0), Color(0.8, 0.1, 0.05), true)
	_check(fx.last_burst_amount() == ImpactFx.BIG_AMOUNT, "la baja usa rafaga grande")
	fx.free()


func _make_target(at: Vector3, max_health: float) -> CharacterBody3D:
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
	combatant.setup(max_health)
	return body


func _test_combat_wiring() -> void:
	var sfx: Sfx = SfxScript.new()
	root.add_child(sfx)
	var fx: ImpactFx = ImpactFxScript.new()
	root.add_child(fx)
	var feel: Feel = FeelScript.new()
	root.add_child(feel)
	feel.setup(fx)

	var rito: Rito = RitoScript.new()
	root.add_child(rito)
	var combatant: Combatant = CombatantScript.new()
	combatant.name = "Combatant"
	rito.add_child(combatant)
	await process_frame
	combatant.setup(100.0, 0.0)
	rito.bind_combatant(combatant, Vector3.ZERO)
	rito.bind_feel(feel)
	var attack: RitoCombat = RitoCombatScript.new()
	rito.add_child(attack)
	attack.setup(rito)
	sfx.bind_player(rito)
	await process_frame

	attack._try_attack(false)
	_check(sfx.assigned_streams() >= 1, "el tajo del jugador asigna sonido de barrido")

	var victim := _make_target(Vector3(0, 0.8, 2.0), 100.0)
	attack._on_landed(victim, 34.0)
	_check(fx.active_count() >= 1, "un tajo aterrizado spawnea particulas")
	_check(attack.kills == 0, "un golpe no mortal no suma baja")

	var weak := _make_target(Vector3(0, 0.8, 2.0), 5.0)
	weak.get_node("Combatant").take_damage(999.0, Vector3.ZERO)
	attack._on_landed(weak, 34.0)
	_check(attack.kills == 1, "el remate suma la baja")
	_check(Engine.time_scale < 1.0, "el remate congela el tiempo (hit-stop)")
	Engine.time_scale = 1.0

	# Sin sfx ni feel en el arbol, nada del cableado debe romperse.
	sfx.remove_from_group("sfx")
	feel.remove_from_group("feel")
	var lone: Rito = RitoScript.new()
	root.add_child(lone)
	var lone_combatant: Combatant = CombatantScript.new()
	lone_combatant.name = "Combatant"
	lone.add_child(lone_combatant)
	await process_frame
	lone_combatant.setup(100.0, 0.0)
	lone.bind_combatant(lone_combatant, Vector3.ZERO)
	_check(lone.try_dodge(Vector3(1, 0, 0)), "la esquiva funciona sin nodos de feel")
	lone.call("_on_damaged", 5.0, Vector3.ZERO)
	_check(true, "recibir dano sin sfx/feel no rompe")
