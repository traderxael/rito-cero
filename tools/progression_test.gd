extends SceneTree

## Arnes determinista del nucleo de progresion: inventario y curacion, botin y guardado,
## sin escena, sin terreno, sin GPU. Cada regla de conteo que es caro descubrir jugando se
## comprueba aqui.

## El recuento convierte en fallo cualquier caso que no llegue a ejecutarse: un error
## dentro de un test aborta el resto sin lanzar su assert, y el arnes se quedaria en
## verde con los checks pendientes nunca corridos.
const EXPECTED_CHECKS := 317

## Ruta del guardado en disco (escritorio y headless). El test la borra al empezar y
## al terminar para que dos ejecuciones seguidas midan lo mismo.
const SAVE_PATH := "user://ritocero_save_v1.json"

## Catalogo cerrado del botin: cualquier id fuera de esta lista seria un error de tabla.
const LOOT_IDS := ["panis", "aqua", "sal", "pizza", "gelatum", "denarii"]

## Bandas de denarios por tier, en el mismo orden que los tiers (0, 1, 2).
const LOOT_DENARII_RANGES := [[10, 20], [17, 33], [30, 50]]

class StubCombateTablero:
	extends Node
	## Stub de combate para el tablero: solo registra si el input esta habilitado.
	var input_enabled := true

	func set_input_enabled(valor: bool) -> void:
		input_enabled = valor


class StubJugadorDefensa:
	extends Node3D
	## Jugador de mentira para la defensa: solo lleva el Combatant para que el
	## sitio pueda engancharse a su muerte sin _ready ni escena.
	var combatant: Node


class StubCombateArmeria:
	extends Node
	## Stub de combate para el arsenal: registra el arma activa y la mueve en el holder real.
	var weapon_index := 0
	var holder: WeaponsHolder

	func switch_weapon(indice: int) -> void:
		weapon_index = indice
		holder.switch_to(indice)


var _failures := 0
var _checks_run := 0

## Nodos creados por los tests de misiones: se liberan al final para no dejar
## cuerpos fisicos colgados en la salida headless.
var _cleanup: Array = []


func _init() -> void:
	_test_inventory_add_remove_count()
	_test_use_consumable_heals_and_consumes()
	_test_use_consumable_at_zero_items_returns_zero()
	_test_loot_tier_for_level()
	_test_loot_roll_bounds()
	_test_save_roundtrip_and_partial_data()
	_test_xp_curve_and_level_up()
	_test_mission_rewards_exactly_once()
	_test_fail_and_abandon_streaks()
	_test_heal_values()
	_test_sal_craft_and_use()
	_test_tech_purchase_gate()
	_test_gladius_templado()
	_test_armeria_unlocks()
	await _test_tech_tree()
	_test_save_roundtrip_system()
	_test_save_integration()
	_test_mission_data_scaling()
	await _test_marker_targets()
	await _test_bandit_camp_spawn_and_kill_flow()
	await _test_world_event_rules()
	await _test_board_logic()
	await _test_defense_waves_flow()
	await _test_hud_binds_signals()
	await _test_keyboard_unlock_gate()
	_test_damage_mult_gladius_only()
	_test_apply_save_emits()
	_test_corrupt_save_degrades()
	await _test_board_clears_on_fail()
	await _test_purge_death_fails()
	await _test_inventory_menu()
	await _test_pickup_mirror_and_suppress()
	for nodo in _cleanup:
		if is_instance_valid(nodo):
			nodo.free()
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


## Dar de alta, contar y dar de baja: el remove de mas no toca nada y el de exacto
## lo vacia.
func _test_inventory_add_remove_count() -> void:
	var inv := GameInventory.new()
	_check(not inv.has("panis", 2), "recien creado no tiene dos panis")
	inv.add("panis", 2)
	_check(inv.count("panis") == 2, "add de dos panis deja el recuento en 2")
	_check(inv.has("panis", 2), "tras el add si tiene los dos panis")
	_check(not inv.remove("panis", 3), "quitar tres con dos existencias falla")
	_check(inv.count("panis") == 2, "el recuento no cambia cuando el remove falla")
	_check(inv.remove("panis", 2), "quitar los dos panis funciona")
	_check(inv.count("panis") == 0, "quemados los panis el recuento es 0")


## Cada consumible cura su cantidad fija y baja una unidad: 35 y 35, y el
## inventario queda en 0.
func _test_use_consumable_heals_and_consumes() -> void:
	var inv := GameInventory.new()
	inv.add("panis", 2)
	_check(is_equal_approx(inv.use_consumable("panis"), 35.0), "el panis cura 35")
	_check(inv.count("panis") == 1, "consumido un panis queda uno")
	_check(is_equal_approx(inv.use_consumable("panis"), 35.0), "el segundo panis tambien cura 35")
	_check(inv.count("panis") == 0, "los dos panis consumidos dejan el inventario en 0")


## Tercer uso: un inventario vacio es el mismo estado que tras el segundo uso, y ahi
## no hay nada que curar. Un id fuera del catalogo tampoco cura ni consume nada.
func _test_use_consumable_at_zero_items_returns_zero() -> void:
	var inv := GameInventory.new()
	_check(is_equal_approx(inv.use_consumable("panis"), 0.0), "sin panis que consumir no cura")
	_check(inv.count("panis") == 0, "el recuento sigue en 0 tras el intento")
	_check(is_equal_approx(inv.use_consumable("agua_inexistente"), 0.0),
		"un id fuera del catalogo devuelve 0")


## El rango de botin sube cada cinco niveles y se queda en el ultimo tramo: ni el
## nivel 0 ni los niveles altos inventan tiers fuera de 0..2.
func _test_loot_tier_for_level() -> void:
	_check(LootTable.tier_for_level(1) == 0, "nivel 1 usa el tier 0")
	_check(LootTable.tier_for_level(4) == 0, "nivel 4 sigue en el tier 0")
	_check(LootTable.tier_for_level(5) == 1, "nivel 5 sube al tier 1")
	_check(LootTable.tier_for_level(9) == 1, "nivel 9 sigue en el tier 1")
	_check(LootTable.tier_for_level(10) == 2, "nivel 10 sube al tier 2")
	_check(LootTable.tier_for_level(20) == 2, "nivel 20 se queda en el tier 2")
	_check(LootTable.tier_for_level(0) == 0, "nivel 0 no baja del tier 0")
	_check(LootTable.tier_for_level(99) == 2, "nivel 99 no pasa del tier 2")


## Con la misma semilla, 200 tiradas por tier: una sola pieza por tirada, ids del
## catalogo, cantidades positivas, denarios dentro de su banda y sal jamas en el tier 0.
func _test_loot_roll_bounds() -> void:
	for tier in 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var piezas := 0
		var claves_ok := true
		var cantidades_ok := true
		var denarios_ok := true
		var denarios_vistos := 0
		for i in 200:
			var botin := LootTable.roll(tier, rng)
			piezas += botin.size()
			for id in botin:
				if not LOOT_IDS.has(id):
					claves_ok = false
				if int(botin[id]) < 1:
					cantidades_ok = false
				if id == "denarii":
					denarios_vistos += 1
					var rango: Array = LOOT_DENARII_RANGES[tier]
					if int(botin[id]) < int(rango[0]) or int(botin[id]) > int(rango[1]):
						denarios_ok = false
		_check(piezas == 200, "tier " + str(tier) + " devuelve una pieza por tirada")
		_check(claves_ok, "tier " + str(tier) + " solo usa ids del catalogo")
		_check(cantidades_ok, "tier " + str(tier) + " da cantidades de al menos 1")
		_check(denarios_vistos > 0 and denarios_ok,
			"tier " + str(tier) + " paga denarios dentro de su banda")

	var rng_tier_0 := RandomNumberGenerator.new()
	rng_tier_0.seed = 12345
	var sin_sal := true
	for i in 200:
		if LootTable.roll(0, rng_tier_0).has("sal"):
			sin_sal = false
	_check(sin_sal, "el tier 0 nunca reparte sal")


## El guardado es un JSON plano: ida y vuelta de los siete campos, sin mision activa
## (recargar a media mision la pierde, y eso es diseno), y un archivo corrupto o
## ausente se lee como diccionario vacio en vez de romper el arranque.
func _test_save_roundtrip_and_partial_data() -> void:
	_borrar_guardado()
	_check(SaveGame.load().is_empty(), "sin archivo previo load devuelve vacio")

	var data := {
		"xp": 120,
		"level": 3,
		"coins": 45,
		"inventory": {"panis": 2, "aqua": 1},
		"tech": ["testudo", "pilum"],
		"best_streak": 7,
		"current_streak": 2,
	}
	_check(SaveGame.save(data), "guardar un dict valido devuelve true")
	var loaded := SaveGame.load()
	_check(int(loaded.get("xp", -1)) == 120, "load devuelve la xp guardada")
	_check(int(loaded.get("level", -1)) == 3, "load devuelve el nivel guardado")
	_check(int(loaded.get("coins", -1)) == 45, "load devuelve las monedas guardadas")
	var inventario: Dictionary = loaded.get("inventory", {})
	_check(int(inventario.get("panis", 0)) == 2 and int(inventario.get("aqua", 0)) == 1,
		"load devuelve el inventario guardado")
	_check(loaded.get("tech", []) == ["testudo", "pilum"], "load devuelve la tecnologia guardada")
	_check(int(loaded.get("best_streak", -1)) == 7, "load devuelve la mejor racha guardada")
	_check(int(loaded.get("current_streak", -1)) == 2, "load devuelve la racha actual guardada")

	var con_mision := data.duplicate(true)
	con_mision["active_mission"] = {"id": "moloso", "hp": 40}
	_check(SaveGame.save(con_mision), "guardar con mision activa no falla")
	var crudo := FileAccess.get_file_as_string(SAVE_PATH)
	_check(not crudo.contains("active_mission"), "save no escribe la mision activa")
	_check(not SaveGame.load().has("active_mission"), "load elimina la mision activa")

	var archivo := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	archivo.store_string("{invalid")
	archivo = null
	_check(SaveGame.load().is_empty(), "un JSON corrupto devuelve vacio sin romper")

	_borrar_guardado()


func _borrar_guardado() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Crea un sistema de misiones listo para jugar: Rito real sin escena (no entra en el
## arbol, asi que _ready no corre), Combatant real a 100 de vida y sistema sin mision.
## Devuelve [sistema, combatant].
func _make_system() -> Array:
	var combatant: Combatant = Combatant.new()
	combatant.setup(100.0)
	var rito := Rito.new()
	rito.combatant = combatant
	var sistema := MissionSystem.new()
	sistema.setup(rito, null, {})
	_cleanup.append(sistema)
	_cleanup.append(rito)
	_cleanup.append(combatant)
	return [sistema, combatant]


## Completa la purga de bandidos a base de kills (4 objetivos al nivel 1).
func _complete_purge(sistema: MissionSystem) -> void:
	sistema.start_mission("bandit_purge")
	for i in 4:
		sistema.register_mission_kill()


## Curva de XP y niveles: 100 para el nivel 1, 282 para el 2, techo en 20 y
## +5 de vida maxima por nivel aplicado sobre el Combatant.
func _test_xp_curve_and_level_up() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var combatant: Combatant = ctx[1]
	_check(MissionSystem.xp_needed(1) == 100, "el nivel 1 pide 100 de XP")
	_check(MissionSystem.xp_needed(2) == 282, "el nivel 2 pide 282 de XP")
	sistema.add_xp(100)
	_check(sistema.level == 2, "con 100 de XP se sube al nivel 2")
	_check(is_equal_approx(combatant.max_health, 105.0), "el nivel 2 sube la vida maxima a 105")
	sistema.level = 20
	sistema.add_xp(100000)
	_check(sistema.level == 20, "el nivel no pasa de 20")


## La recompensa se paga una sola vez: matar los 4 objetivos completa la mision, el
## contador de monedas crece en exactamente rewards.coins y un complete sin mision
## activa no paga nada.
func _test_mission_rewards_exactly_once() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.seed_rng(12345)
	var completadas: Array = []
	var recompensas: Array = []
	sistema.mission_completed.connect(func(mision: Dictionary, recompensa: Dictionary) -> void:
		completadas.append(mision)
		recompensas.append(recompensa))
	_check(sistema.start_mission("bandit_purge"), "iniciar la purga funciona")
	_check(not sistema.start_mission("city_defense"), "con mision activa no se puede iniciar otra")
	_check(sistema.is_mission_active(), "tras iniciar hay mision activa")
	for i in 3:
		sistema.register_mission_kill()
	_check(sistema.register_mission_kill(), "el cuarto kill completa la mision")
	_check(completadas.size() == 1, "la mision se completa una sola vez")
	_check(not sistema.register_mission_kill(), "sin mision activa el kill no hace nada")
	_check(completadas.size() == 1, "los kills extra no vuelven a pagar")
	var recompensa: Dictionary = recompensas[0] if not recompensas.is_empty() else {}
	_check(recompensa.has("xp") and recompensa.has("coins") and recompensa.has("loot"),
		"las recompensas llevan xp, coins y loot")
	_check(int(recompensa.get("coins", -1)) == sistema.coins, "las monedas crecen en exactamente rewards.coins")
	_check(sistema.xp == int(recompensa.get("xp", -1)), "la XP otorgada llega al contador")
	_check(sistema.current_streak == 1, "completar suma 1 a la racha")
	_check(sistema.best_streak == 1, "la mejor racha sube a 1")
	var monedas := sistema.coins
	sistema.complete_mission()
	_check(sistema.coins == monedas, "completar sin mision activa no paga")


## Rachas: completar la sube, abandonar y fallar la dejan en 0, la mejor racha no baja.
func _test_fail_and_abandon_streaks() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.seed_rng(12345)
	_complete_purge(sistema)
	_check(sistema.current_streak == 1, "tras completar la racha es 1")
	_check(sistema.best_streak == 1, "tras completar la mejor racha es 1")
	sistema.start_mission("city_defense")
	sistema.abandon_mission()
	_check(sistema.current_streak == 0, "abandonar deja la racha en 0")
	_check(sistema.best_streak == 1, "abandonar no baja la mejor racha")
	sistema.expire_cooldowns()
	_check(sistema.start_mission("bandit_purge"), "tras expirar el cooldown se puede repetir la purga")
	sistema.fail_mission()
	_check(sistema.current_streak == 0, "fallar deja la racha en 0")
	_check(sistema.best_streak == 1, "fallar no baja la mejor racha")


## Curacion con tecnologias: aqua 20, panis 35, molino 52, panis con sal 50 sin molino
## (67 con molino), gelatum 15 (30 con bodega), a vida llena no se consume nada.
func _test_heal_values() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var combatant: Combatant = ctx[1]
	sistema.coins = 1000
	sistema.inventory.add("aqua", 1)
	combatant.health = 50.0
	_check(sistema.use_item("aqua"), "usar el aqua cura")
	_check(is_equal_approx(combatant.health, 70.0), "el aqua cura 20")
	sistema.inventory.add("panis", 1)
	combatant.health = 50.0
	sistema.use_item("panis")
	_check(is_equal_approx(combatant.health, 85.0), "el panis cura 35")
	sistema.buy_tech("molino")
	sistema.inventory.add("panis", 1)
	combatant.health = 30.0
	sistema.use_item("panis")
	_check(is_equal_approx(combatant.health, 82.0), "con molino el panis cura 52")
	sistema.inventory.add("panis", 1)
	sistema.inventory.add("sal", 1)
	combatant.health = 30.0
	sistema.use_item("panis")
	_check(is_equal_approx(combatant.health, 97.0), "el panis con molino y sal cura 67")
	_check(sistema.inventory.count("sal") == 0, "la sal se consume con el panis")
	sistema.inventory.add("panis", 1)
	sistema.inventory.add("sal", 1)
	combatant.health = 10.0
	sistema.use_item("panis")
	_check(is_equal_approx(combatant.health, 77.0), "con molino y sal el panis cura 67")
	sistema.inventory.add("gelatum", 1)
	combatant.health = 50.0
	sistema.use_item("gelatum")
	_check(is_equal_approx(combatant.health, 65.0), "el gelatum cura 15")
	sistema.buy_tech("bodega")
	sistema.inventory.add("gelatum", 1)
	combatant.health = 30.0
	sistema.use_item("gelatum")
	_check(is_equal_approx(combatant.health, 60.0), "con bodega el gelatum cura 30")
	sistema.inventory.add("aqua", 1)
	combatant.health = combatant.max_health
	_check(not sistema.use_item("aqua"), "a vida llena no se consume")
	_check(sistema.inventory.count("aqua") == 1, "a vida llena el item se queda")
	_check(not sistema.use_item("pizza"), "sin pizza en el inventario no se puede usar")
	sistema.inventory.add("sal", 1)
	_check(not sistema.use_item("sal"), "la sal sola no cura")
	_check(sistema.inventory.count("sal") == 1, "la sal sola no se consume")


## Crafteo de sal: exige la tecnologia salazon, cuesta 1 panis y 10 denarios y el
## panis curado con ella aplica el +15.
func _test_sal_craft_and_use() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var combatant: Combatant = ctx[1]
	sistema.coins = 100
	sistema.inventory.add("panis", 2)
	_check(not sistema.craft_sal(), "sin salazon no se puede craftear sal")
	_check(sistema.buy_tech("salazon"), "comprar la salazon cuesta 80")
	_check(sistema.craft_sal(), "con salazon el crafteo funciona")
	_check(sistema.inventory.count("sal") == 1, "el crafteo deja una sal")
	_check(sistema.inventory.count("panis") == 1, "el crafteo consume un panis")
	_check(sistema.coins == 10, "el crafteo cuesta 10 denarios")
	combatant.health = 30.0
	sistema.use_item("panis")
	_check(is_equal_approx(combatant.health, 80.0), "el panis con la sal crafteada cura 50")
	_check(sistema.inventory.count("sal") == 0, "usar el panis consume la sal crafteada")


## La compra de tecnologias respeta el saldo, el id y la propiedad: sin denarios no
## toca nada, con denarios resta el coste exacto y ya no se puede recomprar.
func _test_tech_purchase_gate() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	_check(not sistema.buy_tech("tecnologia_inexistente"), "un id desconocido no se puede comprar")
	sistema.coins = 10
	_check(not sistema.buy_tech("pozo"), "sin denarios suficientes no se puede comprar")
	_check(sistema.coins == 10, "la compra fallida no toca las monedas")
	sistema.coins = 100
	_check(sistema.buy_tech("pozo"), "con denarios la compra funciona")
	_check(sistema.coins == 40, "la compra resta el coste exacto de 60")
	_check(sistema.has_tech("pozo"), "tras comprar la tecnologia queda registrada")
	_check(not sistema.buy_tech("pozo"), "la tecnologia ya comprada no se puede recomprar")
	_check(sistema.coins == 40, "la recompra fallida no toca las monedas")


## El gladius templado: multiplicador 1,0 de base y 1,3 con la armeria 3.
func _test_gladius_templado() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	_check(is_equal_approx(sistema.gladius_damage_mult(), 1.0), "sin templar el multiplicador es 1,0")
	sistema.coins = 250
	sistema.buy_tech("armeria3")
	_check(is_equal_approx(sistema.gladius_damage_mult(), 1.3), "con la armeria 3 el multiplicador es 1,3")


## El guardado del sistema: siete claves, sin mision activa, y apply_save restaura
## todo; con un diccionario vacio se empieza de cero en el nivel 1.
func _test_save_roundtrip_system() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.add_xp(50)
	sistema.coins = 500
	sistema.buy_tech("pozo")
	sistema.inventory.add("panis", 2)
	sistema.best_streak = 5
	sistema.current_streak = 2
	var guardado := sistema.current_save()
	_check(not guardado.has("active_mission"), "current_save nunca guarda la mision activa")
	_check(guardado.has("xp") and guardado.has("level") and guardado.has("coins")
		and guardado.has("inventory") and guardado.has("tech") and guardado.has("best_streak")
		and guardado.has("current_streak"), "current_save lleva las siete claves")

	var ctx2: Array = _make_system()
	var restaurado: MissionSystem = ctx2[0]
	restaurado.apply_save(guardado)
	_check(restaurado.xp == 50, "apply_save restaura la XP")
	_check(restaurado.level == sistema.level, "apply_save restaura el nivel")
	_check(restaurado.coins == 440, "apply_save restaura las monedas tras la compra")
	_check(restaurado.inventory.count("panis") == 2, "apply_save restaura el inventario")
	_check(restaurado.has_tech("pozo"), "apply_save restaura la tecnologia")
	_check(restaurado.best_streak == 5, "apply_save restaura la mejor racha")
	_check(restaurado.current_streak == 2, "apply_save restaura la racha actual")

	restaurado.apply_save({})
	_check(restaurado.level == 1, "apply_save vacio empieza en el nivel 1")
	_check(restaurado.xp == 0, "apply_save vacio empieza con 0 de XP")
	_check(restaurado.coins == 0, "apply_save vacio empieza con 0 de monedas")


## Guardado extremo a extremo: completar la purga con semilla fija, guardar con
## current_save y restaurar en un sistema fresco deja los mismos valores
## (XP, nivel, monedas, tecnologia, mejor racha e inventario) y jamas incluye la
## mision activa; apply_save con {} empieza en nivel 1 con 100 de vida maxima.
func _test_save_integration() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.seed_rng(12345)
	_complete_purge(sistema)
	sistema.coins = 500
	sistema.buy_tech("pozo")
	sistema.inventory.add("panis", 3)
	var guardado := sistema.current_save()
	_check(not guardado.has("active_mission"), "save_integration current_save no incluye la mision activa")

	var ctx2: Array = _make_system()
	var restaurado: MissionSystem = ctx2[0]
	var combatant2: Combatant = ctx2[1]
	restaurado.apply_save(guardado)
	_check(restaurado.xp == sistema.xp, "save_integration restaura la misma XP")
	_check(restaurado.level == sistema.level, "save_integration restaura el mismo nivel")
	_check(restaurado.coins == sistema.coins, "save_integration restaura las mismas monedas")
	_check(restaurado.tech == sistema.tech, "save_integration restaura la misma tecnologia")
	_check(restaurado.best_streak == sistema.best_streak, "save_integration restaura la mejor racha")
	_check(restaurado.current_streak == sistema.current_streak, "save_integration restaura la racha actual")
	_check(restaurado.inventory.count("panis") == 3, "save_integration restaura el inventario")

	restaurado.apply_save({})
	_check(restaurado.level == 1, "save_integration apply_save vacio empieza en nivel 1")
	_check(is_equal_approx(combatant2.max_health, 100.0), "save_integration apply_save vacio deja 100 de vida maxima")
	_check(restaurado.xp == 0, "save_integration apply_save vacio deja 0 de XP")


## El escalado de plantillas: la purga sube objetivos y XP con el nivel, la defensa
## no escala objetivos, un id desconocido no produce instancia.
func _test_mission_data_scaling() -> void:
	var purga_nivel_5 := MissionData.make_instance("bandit_purge", 5)
	_check(int(purga_nivel_5.get("targets", 0)) == 5, "la purga al nivel 5 pide 5 objetivos")
	_check(int(purga_nivel_5.get("xp", 0)) == 96, "la purga al nivel 5 paga 96 de XP")
	var defensa := MissionData.make_instance("city_defense", 9)
	_check(int(defensa.get("targets", 0)) == 18, "la defensa no escala objetivos")
	_check(MissionData.make_instance("mision_inexistente", 1).is_empty(), "un id desconocido no da instancia")


## Marcador de objetivo: la columna queda a 11 m sobre el punto dado (terreno a
## altura 0), clear() la oculta y el minimapa guarda el objetivo de la mision.
func _test_marker_targets() -> void:
	var marcador := ObjectiveMarker.new()
	root.add_child(marcador)
	_cleanup.append(marcador)
	await process_frame
	marcador.set_target(Vector3(10, 0, 20))
	_check(marcador.global_position == Vector3(10, 11, 20), "set_target coloca la columna 11 m sobre el suelo")
	_check(marcador.visible, "tras set_target la columna es visible")
	marcador.clear()
	_check(not marcador.visible, "tras clear la columna no es visible")
	var mapa: Node = load("res://scripts/ui/minimap.gd").new()
	_cleanup.append(mapa)
	_check(mapa.call("objective") == null, "el minimapa empieza sin objetivo")
	mapa.call("set_objective", Vector3(10, 0, 20))
	_check(mapa.call("objective") == Vector3(10, 0, 20), "el minimapa guarda la posicion del objetivo")
	mapa.call("clear_objective")
	_check(mapa.call("objective") == null, "tras clear_objective el minimapa no tiene objetivo")


## Purga jugable: el campamento crea N bandidos en ambos grupos con tinte rojizo,
## matar N-1 deja la mision activa, matar el ultimo la completa una sola vez y libera
## el campamento; finish() libera al vivo sin completar. La baja usa la via real de dano.
func _test_bandit_camp_spawn_and_kill_flow() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.seed_rng(777)
	var iniciadas: Array = []
	var completadas: Array = []
	sistema.mission_started.connect(func(mision: Dictionary) -> void:
		iniciadas.append(mision))
	sistema.mission_completed.connect(func(mision: Dictionary, _recompensas: Dictionary) -> void:
		completadas.append(mision))
	sistema.start_mission("bandit_purge")
	var objetivo := int((iniciadas[0] as Dictionary).get("targets", 4)) if not iniciadas.is_empty() else 4

	var arena := Node3D.new()
	arena.name = "ArenaBandidos"
	root.add_child(arena)
	_cleanup.append(arena)
	# Un frame para que la arena entre en el arbol: sin el arbol, setear
	# global_position en setup() y las busquedas por grupo de sfx/feel fallan.
	await process_frame

	var camp := BanditCamp.spawn(arena, Vector3(0, 0, 0), objetivo, null, sistema, null)
	var bandidos: Array = camp.get_children()
	_check(bandidos.size() == objetivo, "el campamento crea los N bandidos de la mision")
	var en_hostiles := true
	var en_mision := true
	var con_tinte := true
	for bandido in bandidos:
		if not (bandido as Node).is_in_group("hostiles"):
			en_hostiles = false
		if not (bandido as Node).is_in_group("mission_bandits"):
			en_mision = false
		var material: StandardMaterial3D = (bandido as Node).get("_body_material")
		if material == null or not (is_equal_approx(material.albedo_color.r, 1.35)
				and is_equal_approx(material.albedo_color.g, 0.55)
				and is_equal_approx(material.albedo_color.b, 0.45)):
			con_tinte = false
	_check(en_hostiles, "los bandidos del campamento estan en hostiles")
	_check(en_mision, "los bandidos del campamento estan en mission_bandits")
	_check(con_tinte, "los bandidos del campamento llevan el tinte rojizo")

	for i in objetivo - 1:
		(bandidos[i] as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	_check(sistema.is_mission_active(), "matar N-1 deja la mision activa")
	(bandidos[objetivo - 1] as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	_check(completadas.size() == 1 and not sistema.is_mission_active(),
		"matar al ultimo completa la mision una sola vez")
	_check(camp.is_queued_for_deletion(), "tras completar el campamento se libera")

	var cuna := Node3D.new()
	cuna.name = "CunaBandido"
	root.add_child(cuna)
	_cleanup.append(cuna)
	await process_frame
	var suelto := BanditCamp.spawn_bandit(cuna, Vector3(40, 0, 0), 0.0, null, null)
	var material_suelto: StandardMaterial3D = (suelto as Node).get("_body_material")
	_check((suelto as Node).is_in_group("hostiles")
		and (suelto as Node).is_in_group("mission_bandits")
		and material_suelto != null and is_equal_approx(material_suelto.albedo_color.r, 1.35),
		"spawn_bandit crea un bandido de mision con tinte")

	sistema.expire_cooldowns()
	sistema.start_mission("bandit_purge")
	var objetivo2 := int(MissionData.make_instance("bandit_purge", sistema.level).get("targets", 4))
	var camp2 := BanditCamp.spawn(arena, Vector3(0, 0, 30), objetivo2, null, sistema, null)
	var bandidos2: Array = camp2.get_children()
	for i in objetivo2 - 1:
		(bandidos2[i] as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	camp2.call("finish")
	await process_frame
	_check(completadas.size() == 1 and sistema.is_mission_active(),
		"finish() con un vivo no completa la mision")
	var ultimo = bandidos2[objetivo2 - 1]
	_check(not is_instance_valid(ultimo) or not (ultimo as Node).is_inside_tree(),
		"finish() libera al bandido vivo")
	sistema.abandon_mission()


## Evento de mundo (campamento en el Muro): la plantilla world_event es oculta
## (fuera del tablero) pero el arranque directo funciona; el evento espera 180 s,
## se suspende con cualquier mision activa, tras cerrarla reinicia a 120 s, sin
## mision levanta 3 bandidos con tinte en poi muro, no duplica mientras sigue
## sin resolver y expirar tras 900 s lo libera sin recompensa.
func _test_world_event_rules() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.seed_rng(31337)
	_check(MissionData.TEMPLATES.has("world_event") and bool((MissionData.TEMPLATES["world_event"] as Dictionary).get("hidden", false)),
		"world_event es plantilla oculta")
	var instancia := MissionData.make_instance("world_event", 1)
	_check(int(instancia.get("xp", 0)) == 80 and int(instancia.get("targets", 0)) == 3 and str(instancia.get("poi", "")) == "muro",
		"world_event paga 80 XP con 3 objetivos en el muro")
	var ids_disponibles: Array = []
	for mision in sistema.available_missions():
		ids_disponibles.append(str((mision as Dictionary).get("id", "")))
	_check(not ids_disponibles.has("world_event") and ids_disponibles.size() == 2,
		"available_missions excluye la plantilla oculta")
	var iniciadas: Array = []
	var completadas: Array = []
	sistema.mission_started.connect(func(mision: Dictionary) -> void:
		iniciadas.append(mision))
	sistema.mission_completed.connect(func(mision: Dictionary, _recompensas: Dictionary) -> void:
		completadas.append(mision))
	var muro := Vector3(0, 0, 0)
	var evento := WorldEvent.new()
	evento.name = "EventoMuro"
	root.add_child(evento)
	_cleanup.append(evento)
	await process_frame
	evento.call("setup", sistema, {"muro": muro}, null, null)
	_check(sistema.start_mission("bandit_purge"), "la purga inicia para suspender el evento")
	evento.call("_advance_time_for_test", 200.0)
	_check(not bool(evento.call("is_event_active")) and int(evento.call("bandit_count")) == 0,
		"la mision activa suspende el evento aunque venza el timer")
	sistema.abandon_mission()
	evento.call("_advance_time_for_test", 119.0)
	_check(not bool(evento.call("is_event_active")), "tras cerrar la purga el evento espera 120 s")
	evento.call("_advance_time_for_test", 1.0)
	_check(bool(evento.call("is_event_active")) and int(evento.call("bandit_count")) == 3,
		"vencido el timer sin mision el evento levanta 3 bandidos en el muro")
	_check(not iniciadas.is_empty() and str((iniciadas[iniciadas.size() - 1] as Dictionary).get("id", "")) == "world_event",
		"el evento inicia la mision oculta world_event")
	var campamento: Node = evento.get("_camp") as Node
	var bandidos: Array = campamento.get_children() if campamento != null else []
	var concuerda := bandidos.size() == 3
	if concuerda:
		for bandido in bandidos:
			var distancia := (bandido as Node3D).position.distance_to(muro)
			if absf(distancia - 12.0) > 0.5:
				concuerda = false
	_check(concuerda, "los 3 bandidos nacen en anillo a 12 m del muro")
	evento.call("_advance_time_for_test", 200.0)
	_check(int(evento.call("bandit_count")) == 3, "el segundo vencimiento sin resolver no duplica bandidos")
	for bandido in bandidos:
		(bandido as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	_check(completadas.size() == 1 and not sistema.is_mission_active(),
		"matar los 3 completa el evento una sola vez")
	sistema.expire_cooldowns()
	evento.call("_advance_time_for_test", 120.0)
	_check(bool(evento.call("is_event_active")) and int(evento.call("bandit_count")) == 3,
		"el evento vuelve a aparecer tras el reinicio")
	var monedas := sistema.coins
	var completadas_antes := completadas.size()
	evento.call("_advance_time_for_test", 900.0)
	_check(not bool(evento.call("is_event_active")) and int(evento.call("bandit_count")) == 0
		and sistema.coins == monedas and completadas.size() == completadas_antes,
		"tras 900 s sin tocar el evento expira sin recompensa y libera los vivos")


## Tablero de misiones: abrir/cerrar congela y restaura el input, lista las dos
## plantillas, aceptar inicia la purga y la etiqueta sigue kills_done/targets,
## y abandonar pide confirmacion en dos pasos dejando la racha en 0 por senal.
func _test_board_logic() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.seed_rng(999)
	var combate := StubCombateTablero.new()
	combate.name = "StubCombateTablero"
	root.add_child(combate)
	_cleanup.append(combate)
	var tablero := MissionBoard.new()
	root.add_child(tablero)
	_cleanup.append(tablero)
	await process_frame
	tablero.call("setup", sistema, combate)
	_check(not tablero.call("is_open"), "el tablero arranca cerrado")
	tablero.call("open")
	_check(bool(tablero.call("is_open")), "open deja el tablero abierto")
	_check(not combate.input_enabled, "open deshabilita el input de combate")
	var ids: Array = tablero.call("available_ids") as Array
	_check(ids.size() == 2 and ids.has("bandit_purge") and ids.has("city_defense"),
		"el tablero lista las dos misiones disponibles")
	var acepta := tablero.call("accept_button", "bandit_purge") as Button
	_check(acepta != null, "hay boton Aceptar para la purga")
	(acepta as Button).emit_signal("pressed")
	_check(sistema.is_mission_active(), "aceptar la purga inicia la mision")
	_check(str(tablero.call("active_label_text")).contains("Bandidos restantes: 4"),
		"la activa muestra los bandidos restantes")
	sistema.register_mission_kill()
	sistema.register_mission_kill()
	_check(str(tablero.call("active_label_text")).contains("Bandidos restantes: 2"),
		"el progreso actualiza los bandidos restantes")
	sistema.register_mission_kill()
	sistema.register_mission_kill()
	_check(str(tablero.call("active_label_text")).contains("Sin misión activa"),
		"al completar la activa vuelve a vacia")
	sistema.expire_cooldowns()
	_check(tablero.call("accept_button", "city_defense") != null, "hay boton Aceptar para la defensa")
	(tablero.call("accept_button", "city_defense") as Button).emit_signal("pressed")
	_check(sistema.is_mission_active(), "aceptar la defensa inicia la mision")
	var rachas: Array = []
	sistema.streak_changed.connect(func(actual: int, _mejor: int) -> void:
		rachas.append(actual))
	var abandonar := tablero.call("abandon_button") as Button
	(abandonar as Button).emit_signal("pressed")
	var si := tablero.call("abandon_confirm_button") as Button
	_check(si != null and si.visible, "abandonar pide confirmacion en dos pasos")
	(si as Button).emit_signal("pressed")
	_check(not sistema.is_mission_active(), "confirmar abandona la mision")
	_check(not rachas.is_empty() and int(rachas[rachas.size() - 1]) == 0
		and sistema.current_streak == 0, "abandonar deja la racha en 0 por senal")
	tablero.call("close")
	_check(not bool(tablero.call("is_open")), "close cierra el tablero")
	_check(combate.input_enabled, "close restaura el input de combate")


## Bandidos de un sitio que siguen vivos: los cadaveres de oleadas pasadas aun
## cuelgan como hijos hasta su temporizador, asi que para contar vivos se
## mira el Combatant de cada hijo y no el tamano de la lista de hijos.
func _alive_bandits(sitio: Node) -> Array:
	var vivos: Array = []
	for hijo in sitio.get_children():
		var combate: Node = (hijo as Node).get_node_or_null("Combatant")
		if combate != null and bool(combate.call("is_alive")):
			vivos.append(hijo)
	return vivos


func _alive_count(sitio: Node) -> int:
	return _alive_bandits(sitio).size()


## Defesa de la ciudad en tres oleadas (4/6/8 en anillo a 18 m en las ruinas):
## con pausa 0 la oleada siguiente entra en cuanto cae la anterior, el progreso
## llega a 18/18 y la mision se completa una sola vez liberando el sitio; con
## la pausa de 20 s la oleada siguiente espera a su temporizador; y si Rito
## cae a mitad de oleada la defensa falla una vez y el sitio se libera.
func _test_defense_waves_flow() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var combatant: Combatant = ctx[1]
	sistema.seed_rng(4242)
	var progresos: Array = []
	var completadas: Array = []
	var fallidas: Array = []
	sistema.mission_progress.connect(func(actual: int, objetivo: int) -> void:
		progresos.append(Vector2i(actual, objetivo)))
	sistema.mission_completed.connect(func(mision: Dictionary, _recompensas: Dictionary) -> void:
		completadas.append(mision))
	sistema.mission_failed.connect(func(mision: Dictionary) -> void:
		fallidas.append(mision))
	_check(sistema.start_mission("city_defense"), "iniciar la defensa funciona")

	var arena := Node3D.new()
	arena.name = "ArenaDefensa"
	root.add_child(arena)
	_cleanup.append(arena)
	await process_frame

	var sitio := DefenseSite.begin(arena, Vector3(0, 0, 0), null, sistema, null)
	_check(sitio != null, "begin crea el sitio de defensa")
	_check(_alive_count(sitio) == 4, "la oleada 1 trae 4 bandidos vivos en las ruinas")
	var primero: Node3D = (sitio.get_children()[0] as Node3D) if sitio.get_child_count() > 0 else null
	_check(primero != null and primero.is_in_group("hostiles")
		and primero.is_in_group("mission_bandits"),
		"los bandidos de defensa estan en hostiles y mission_bandits")
	_check(primero != null and absf(primero.position.length() - 18.0) < 0.01,
		"el primer bandido de la defensa nace a 18 m de las ruinas")

	(sitio as DefenseSite).wave_pause = 0.0
	for bandido in _alive_bandits(sitio):
		(bandido as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	_check(progresos.size() > 0 and (progresos[progresos.size() - 1] as Vector2i) == Vector2i(4, 18),
		"la oleada 1 deja el progreso en 4/18")
	_check(_alive_count(sitio) == 6, "con pausa 0 la oleada 2 trae 6 vivos")
	for bandido in _alive_bandits(sitio):
		(bandido as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	_check(progresos.size() > 0 and (progresos[progresos.size() - 1] as Vector2i) == Vector2i(10, 18),
		"la oleada 2 deja el progreso en 10/18")
	_check(_alive_count(sitio) == 8, "la oleada 3 trae 8 vivos")
	var onda3: Array = _alive_bandits(sitio)
	for i in 7:
		(onda3[i] as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	_check(sistema.is_mission_active(), "matar 7 de la oleada 3 deja la defensa activa")
	_check(progresos.size() > 0 and (progresos[progresos.size() - 1] as Vector2i) == Vector2i(17, 18),
		"matar 7 de la oleada 3 deja el progreso en 17/18")
	(onda3[7] as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	_check(completadas.size() == 1 and not sistema.is_mission_active(),
		"matar al ultimo de la oleada 3 completa la defensa una sola vez")
	_check(sitio.is_queued_for_deletion(), "tras completar la defensa el sitio se libera")

	sistema.expire_cooldowns()
	_check(sistema.start_mission("city_defense"), "tras expirar el cooldown se puede repetir la defensa")
	var sitio_pausa := DefenseSite.begin(arena, Vector3(0, 0, 60), null, sistema, null)
	_check(_alive_count(sitio_pausa) == 4, "el sitio de pausa arranca con 4 vivos")
	for bandido in _alive_bandits(sitio_pausa):
		(bandido as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	_check(_alive_count(sitio_pausa) == 0, "con pausa 20 la oleada 2 aun no aparece")
	(sitio_pausa as DefenseSite).call("_advance_time_for_test", 5.0)
	_check(_alive_count(sitio_pausa) == 0, "con 5 s la oleada 2 sigue sin aparecer")
	(sitio_pausa as DefenseSite).call("_advance_time_for_test", 20.0)
	_check(_alive_count(sitio_pausa) == 6, "tras la pausa la oleada 2 trae 6 vivos")
	sitio_pausa.call("finish")
	sitio_pausa.queue_free()
	sistema.abandon_mission()

	sistema.expire_cooldowns()
	var jugador := StubJugadorDefensa.new()
	jugador.name = "JugadorDefensa"
	jugador.combatant = combatant
	_cleanup.append(jugador)
	_check(sistema.start_mission("city_defense"), "la defensa vuelve a estar disponible tras el cooldown")
	var sitio_muerte := DefenseSite.begin(arena, Vector3(0, 0, 120), null, sistema, jugador)
	_check(_alive_count(sitio_muerte) == 4, "el sitio de muerte arranca con 4 vivos")
	(sitio_muerte.get_children()[0] as Node).get_node("Combatant").call("take_damage", 9999.0, Vector3.ZERO)
	combatant.take_damage(9999.0, Vector3.ZERO)
	_check(fallidas.size() == 1 and not sistema.is_mission_active(),
		"la muerte de Rito a mitad de oleada falla la defensa una sola vez")
	_check(completadas.size() == 1, "la defensa fallida no completa")
	_check(sitio_muerte.is_queued_for_deletion(), "tras fallar por la muerte de Rito el sitio se libera")


## HUD con MissionSystem real: XP/nivel, denarios y tracker de mision.
## La emision es directa (emit_signal) para fijar los numeros exactos del brief
## (150/283, 2/4) sin pasar por la curva de add_xp; MissionSystem ya cubre el
## camino add_xp/start_mission/register_mission_kill en sus propios tests.
func _test_hud_binds_signals() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var hud: CanvasLayer = load("res://scripts/ui/hud.gd").new()
	root.add_child(hud)
	_cleanup.append(hud)
	hud.call("bind_mission_system", sistema)
	# El tracker legado de Progression cuenta cualquier baja: con MissionSystem
	# enlazado su cartel de victoria no puede aparecer.
	var victory := hud.get("_victory_label") as Label
	hud.call("_on_victory")
	_check(victory == null or not victory.visible,
		"el HUD no muestra la victoria legada con MissionSystem")
	sistema.emit_signal("xp_changed", 150, 283, 2)
	_check(str(hud.call("xp_label_text")) == "Nv 2", "el HUD muestra Nv 2 tras xp_changed")
	_check(is_equal_approx(float(hud.call("xp_fill_ratio")), 150.0 / 283.0),
		"el relleno es 150/283 tras xp_changed")
	sistema.emit_signal("coins_changed", 45)
	_check(str(hud.call("coins_label_text")) == "Denarios: 45", "el HUD muestra Denarios: 45")
	var purga := MissionData.make_instance("bandit_purge", 1)
	sistema.emit_signal("mission_started", purga)
	sistema.emit_signal("mission_progress", 2, 4)
	_check(str(hud.call("mission_label_text")) == "Bandidos restantes: 2",
		"la purga muestra los bandidos restantes")
	var defensa := MissionData.make_instance("city_defense", 1)
	sistema.emit_signal("mission_started", defensa)
	sistema.emit_signal("mission_progress", 5, 18)
	_check(str(hud.call("mission_label_text")) == "Oleada 2/3",
		"la defensa muestra la oleada 2/3")
	sistema.emit_signal("mission_completed", defensa, {})
	_check(str(hud.call("mission_label_text")) == "", "al completar la mision el tracker se vacia")
	sistema.emit_signal("xp_changed", 0, 0, 20)
	_check(is_equal_approx(float(hud.call("xp_fill_ratio")), 1.0),
		"con needed 0 el relleno es 1 sin dividir a cero")
	sistema.emit_signal("mission_started", purga)
	sistema.emit_signal("mission_failed", purga)
	_check(str(hud.call("mission_label_text")) == "", "al fallar la mision el tracker se vacia")


## Armeria: el pugio y el gladio hispaniense salen del arbol de tecnologias. El catalogo
## crece sin reordenar (gladius 0, pilum 1, spatha 2, pugio 3, hispaniens 4); las dos
## nuevas nacen bloqueadas: el pugio pide la armeria 1 y el hispaniense la armeria 2.
## Equiparlas pasa por el holder real y el menu no deja equipar la bloqueada.
func _test_armeria_unlocks() -> void:
	_check(Weapon.count() == 5, "el catalogo tiene cinco armas")
	_check(Weapon.index_of("pugio") == 3, "el pugio es el indice 3")
	_check(Weapon.index_of("hispaniens") == 4, "el hispaniense es el indice 4")
	var ids := {}
	for i in Weapon.count():
		ids[str(Weapon.get_weapon(i)["id"])] = true
	_check(ids.size() == 5, "los cinco ids son unicos")
	_check(ids.has("pugio") and ids.has("hispaniens"), "el catalogo trae pugio e hispaniense")
	_check(str(Weapon.unlock_tech("pugio")) == "armeria1", "el pugio pide la armeria 1")
	_check(str(Weapon.unlock_tech("hispaniens")) == "armeria2", "el hispaniense pide la armeria 2")
	_check(str(Weapon.unlock_tech("gladius")) == "", "el gladius no pide tecnologia")
	var pugio: Dictionary = Weapon.get_weapon(Weapon.index_of("pugio"))
	var hispaniens: Dictionary = Weapon.get_weapon(Weapon.index_of("hispaniens"))
	_check(is_equal_approx(float(pugio["damage"]), 22.0), "el pugio pega 22 de dano")
	_check(is_equal_approx(float(pugio["reach"]), 1.6), "el pugio alcanza 1,6 m")
	_check(is_equal_approx(float(hispaniens["damage"]), 48.0), "el hispaniense pega 48 de dano")
	_check(is_equal_approx(float(hispaniens["reach"]), 2.4), "el hispaniense alcanza 2,4 m")
	_check(Weapon.make_mesh("pugio") != null, "la malla del pugio existe")
	_check(Weapon.make_mesh("hispaniens") != null, "la malla del hispaniense existe")
	_check(InputMap.has_action("weapon_4"), "la tecla 4 existe")
	_check(InputMap.has_action("weapon_5"), "la tecla 5 existe")

	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var chequeo := func(id: String) -> bool:
		var tech: String = str(Weapon.unlock_tech(id))
		if tech.is_empty():
			return true
		return sistema.has_tech(tech)

	var esqueleto := Skeleton3D.new()
	root.add_child(esqueleto)
	_cleanup.append(esqueleto)
	var holder := WeaponsHolder.new()
	holder.setup(esqueleto)
	_cleanup.append(holder)
	var stub := StubCombateArmeria.new()
	stub.name = "StubCombateArmeria"
	stub.holder = holder
	root.add_child(stub)
	_cleanup.append(stub)
	var arsenal: CanvasLayer = load("res://scripts/ui/arsenal_menu.gd").new()
	root.add_child(arsenal)
	_cleanup.append(arsenal)
	arsenal.call("setup", null, stub, chequeo)
	_check(not bool(arsenal.call("is_weapon_unlocked", 3)), "sin armeria el pugio nace bloqueado")
	_check(not bool(arsenal.call("is_weapon_unlocked", 4)), "sin armeria el hispaniense nace bloqueado")
	_check(bool(arsenal.call("is_weapon_unlocked", 0)), "el gladius nace desbloqueado")
	arsenal.call("equip", 3)
	_check(stub.weapon_index == 0, "sin armeria no se puede equipar el pugio")
	sistema.coins = 500
	_check(sistema.buy_tech("armeria1"), "comprar la armeria 1 funciona")
	_check(bool(arsenal.call("is_weapon_unlocked", 3)), "con la armeria 1 el pugio se desbloquea")
	_check(not bool(arsenal.call("is_weapon_unlocked", 4)), "la armeria 1 no desbloquea el hispaniense")
	arsenal.call("equip", 3)
	_check(stub.weapon_index == 3, "con la armeria 1 se puede equipar el pugio")
	_check(is_equal_approx(holder.current_damage(), 22.0), "el pugio equipado pega 22 de dano")
	_check(sistema.buy_tech("armeria2"), "comprar la armeria 2 funciona")
	_check(bool(arsenal.call("is_weapon_unlocked", 4)), "con la armeria 2 el hispaniense se desbloquea")
	arsenal.call("equip", 4)
	_check(is_equal_approx(holder.current_damage(), 48.0), "el hispaniense equipado pega 48 de dano")
	_check(is_equal_approx(holder.current_reach(), 2.4), "el hispaniense alcanza 2,4 m")


## Árbol de tecnología: la tabla es la única fuente (9 nodos, total 1000 denarios),
## la compra en MissionSystem ya existe y el menú solo la consume: botones con
## nombre+coste, deshabilitados sin fondos o ya comprados, y salida con T/Esc.
func _test_tech_tree() -> void:
	# ------------------------------------------------------------------
	# Tabla: 9 ids unicos, costes por id y total 1000 (no 1080 del plan).
	# ------------------------------------------------------------------
	_check(TechTree.NODES.size() == 9, "el arbol tiene nueve nodos")
	var ids_vistos := {}
	var costes_vistos := {}
	for nodo in TechTree.NODES:
		ids_vistos[str(nodo["id"])] = true
		costes_vistos[str(nodo["id"])] = int(nodo["coste"])
	_check(ids_vistos.size() == 9, "los nueve ids del arbol son unicos")
	var costes_esperados := {
		"pozo": 60, "acequia": 60, "salazon": 80, "granero": 100,
		"molino": 100, "bodega": 120, "armeria1": 80, "armeria2": 150,
		"armeria3": 250,
	}
	_check(costes_vistos == costes_esperados, "los costes del arbol coinciden con la tabla")
	var suma := 0
	for nodo in TechTree.NODES:
		suma += int(nodo["coste"])
	_check(suma == 1000, "comprar todo el arbol cuesta 1000 denarios")
	var tecla_ok := false
	if InputMap.has_action("tech_tree"):
		for evento in InputMap.action_get_events("tech_tree"):
			var tecla := evento as InputEventKey
			if tecla != null and tecla.physical_keycode == 84:
				tecla_ok = true
	_check(tecla_ok, "la accion tech_tree existe con fisica T (84)")
	# ------------------------------------------------------------------
	# Comprar todos con 1000 deja las monedas en 0 (TECH_COSTS suma 1000).
	# ------------------------------------------------------------------
	var ctx_todo: Array = _make_system()
	var sistema_todo: MissionSystem = ctx_todo[0]
	sistema_todo.coins = 1000
	var todo_comprado := true
	for nodo in TechTree.NODES:
		if not sistema_todo.buy_tech(str(nodo["id"])):
			todo_comprado = false
	_check(todo_comprado, "con 1000 denarios se compran los nueve nodos")
	_check(sistema_todo.coins == 0, "tras comprar todo las monedas quedan en 0")
	# ------------------------------------------------------------------
	# Armeria 3: el templado sube el multiplicador a 1,3 y el holder lo aplica.
	# ------------------------------------------------------------------
	var ctx_arm: Array = _make_system()
	var sistema_arm: MissionSystem = ctx_arm[0]
	sistema_arm.coins = 250
	sistema_arm.buy_tech("armeria3")
	_check(is_equal_approx(sistema_arm.gladius_damage_mult(), 1.3), "con la armeria 3 el multiplicador es 1,3")
	var holder := WeaponsHolder.new()
	_cleanup.append(holder)
	_check(is_equal_approx(holder.current_damage(), 34.0), "el gladius base pega 34")
	holder.set_damage_mult(1.3)
	_check(is_equal_approx(holder.current_damage(), 44.2), "con 1,3 el gladius pega 44,2")
	# ------------------------------------------------------------------
	# Pozo: con la semilla 2 la purga paga 1 aqua; con pozo paga 2 (x1,25 redondeado
	# hacia arriba). La semilla fija cae en aqua del tier 0 (ver LootTable).
	# ------------------------------------------------------------------
	var ctx_base: Array = _make_system()
	var sistema_base: MissionSystem = ctx_base[0]
	sistema_base.seed_rng(2)
	var recomp_base: Array = []
	sistema_base.mission_completed.connect(func(_m: Dictionary, r: Dictionary) -> void:
		recomp_base.append(r))
	sistema_base.start_mission("bandit_purge")
	for i in 4:
		sistema_base.register_mission_kill()
	var botin_base: Dictionary = (recomp_base[0] as Dictionary).get("loot", {}) if not recomp_base.is_empty() else {}
	_check(int(botin_base.get("aqua", 0)) == 1, "sin pozo la semilla 2 paga 1 aqua")
	var ctx_pozo: Array = _make_system()
	var sistema_pozo: MissionSystem = ctx_pozo[0]
	sistema_pozo.coins = 1000
	sistema_pozo.seed_rng(2)
	var recomp_pozo: Array = []
	sistema_pozo.mission_completed.connect(func(_m: Dictionary, r: Dictionary) -> void:
		recomp_pozo.append(r))
	sistema_pozo.start_mission("bandit_purge")
	sistema_pozo.buy_tech("pozo")
	for i in 4:
		sistema_pozo.register_mission_kill()
	var botin_pozo: Dictionary = (recomp_pozo[0] as Dictionary).get("loot", {}) if not recomp_pozo.is_empty() else {}
	_check(int(botin_pozo.get("aqua", 0)) == 2, "con pozo la semilla 2 paga 2 aqua (x1,25)")
	# ------------------------------------------------------------------
	# Salazon y molino: crafteo de sal y curacion del panis sin/con molino.
	# ------------------------------------------------------------------
	var ctx_sal: Array = _make_system()
	var sistema_sal: MissionSystem = ctx_sal[0]
	sistema_sal.coins = 90
	sistema_sal.inventory.add("panis", 1)
	sistema_sal.buy_tech("salazon")
	_check(sistema_sal.craft_sal(), "con salazon se puede craftear sal")
	_check(sistema_sal.inventory.count("sal") == 1, "el crafteo deja una sal")
	var ctx_cura: Array = _make_system()
	var sistema_cura: MissionSystem = ctx_cura[0]
	var combatant_cura: Combatant = ctx_cura[1]
	sistema_cura.coins = 1000
	sistema_cura.inventory.add("panis", 1)
	combatant_cura.health = 50.0
	sistema_cura.use_item("panis")
	_check(is_equal_approx(combatant_cura.health, 85.0), "sin molino el panis cura 35")
	sistema_cura.buy_tech("molino")
	sistema_cura.inventory.add("panis", 1)
	combatant_cura.health = 30.0
	sistema_cura.use_item("panis")
	_check(is_equal_approx(combatant_cura.health, 82.0), "con molino el panis cura 52")
	# ------------------------------------------------------------------
	# Menú: capa 6, abrir/cerrar congela y restaura el input, 9 botones con
	# nombre+coste, sin fondos no se puede comprar y el clic compra y refresca.
	# ------------------------------------------------------------------
	var ctx_menu: Array = _make_system()
	var sistema_menu: MissionSystem = ctx_menu[0]
	var combate_menu := StubCombateTablero.new()
	combate_menu.name = "StubCombateArbol"
	root.add_child(combate_menu)
	_cleanup.append(combate_menu)
	var menu := TechMenu.new()
	root.add_child(menu)
	_cleanup.append(menu)
	await process_frame
	menu.call("setup", sistema_menu, combate_menu)
	_check(menu.layer == 6, "el arbol vive en la capa 6")
	_check(not bool(menu.call("is_open")), "el arbol arranca cerrado")
	menu.call("open")
	_check(not combate_menu.input_enabled, "open deshabilita el input de combate del arbol")
	var hay_nueve := true
	for nodo in TechTree.NODES:
		if menu.call("button_for", str(nodo["id"])) == null:
			hay_nueve = false
	_check(hay_nueve, "hay boton para cada uno de los nueve nodos")
	var btn_pozo := menu.call("button_for", "pozo") as Button
	_check(btn_pozo.disabled, "sin denarios el pozo esta deshabilitado")
	sistema_menu.coins = 1000
	sistema_menu.emit_signal("coins_changed", 1000)
	var btn_pozo_lleno := menu.call("button_for", "pozo") as Button
	_check(not btn_pozo_lleno.disabled, "con denarios el pozo se puede comprar")
	_check(str(btn_pozo_lleno.text).contains("Pozo de agua") and str(btn_pozo_lleno.text).contains("60"),
		"el boton del pozo muestra nombre y coste")
	(btn_pozo_lleno as Button).emit_signal("pressed")
	_check(sistema_menu.has_tech("pozo") and sistema_menu.coins == 940,
		"el clic compra el pozo y resta 60 denarios")
	var btn_pozo_tras := menu.call("button_for", "pozo") as Button
	_check(btn_pozo_tras.disabled, "tras comprar el pozo el boton queda deshabilitado")
	menu.call("close")
	_check(combate_menu.input_enabled, "close restaura el input de combate del arbol")


## Puerta de teclado: sin la tecnologia de armeria, las teclas 4/5 no cambian al
## pugio ni al hispaniense aunque el holder si los montaria. Con la armeria
## comprada el cambio por teclado funciona, igual que en el arsenal.
func _test_keyboard_unlock_gate() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var chequeo := func(id: String) -> bool:
		var tech: String = str(Weapon.unlock_tech(id))
		if tech.is_empty():
			return true
		return sistema.has_tech(tech)
	var rito := Rito.new()
	root.add_child(rito)
	_cleanup.append(rito)
	var combate := RitoCombat.new()
	rito.add_child(combate)
	await process_frame
	combate.setup(rito)
	combate.call("set_unlock_check", chequeo)
	_check(combate.weapon_index == 0, "el combate arranca en el gladius con chequeo")
	combate.call("switch_weapon", 3)
	_check(combate.weapon_index == 0, "sin armeria la tecla 4 no cambia al pugio")
	combate.call("switch_weapon", 4)
	_check(combate.weapon_index == 0, "sin armeria la tecla 5 no cambia al hispaniense")
	combate.call("switch_weapon", 2)
	_check(combate.weapon_index == 2, "la spatha sin tecnologia si se puede cambiar por teclado")
	combate.call("switch_weapon", 0)
	_check(combate.weapon_index == 0, "volver al gladius funciona")
	sistema.coins = 500
	_check(sistema.buy_tech("armeria1"), "comprar la armeria 1 funciona para el teclado")
	combate.call("switch_weapon", 3)
	_check(combate.weapon_index == 3, "con la armeria 1 la tecla 4 equilibra el pugio")
	combate.call("switch_weapon", 4)
	_check(combate.weapon_index == 3, "la armeria 1 no desbloquea el hispaniense por teclado")
	_check(sistema.buy_tech("armeria2"), "comprar la armeria 2 funciona para el teclado")
	combate.call("switch_weapon", 4)
	_check(combate.weapon_index == 4, "con la armeria 2 la tecla 5 equilibra el hispaniense")


## El templado de la armeria solo toca al gladius: con 1,3 el gladius pega 44,2
## y el resto del arsenal conserva su dano base.
func _test_damage_mult_gladius_only() -> void:
	var esqueleto := Skeleton3D.new()
	root.add_child(esqueleto)
	_cleanup.append(esqueleto)
	var holder := WeaponsHolder.new()
	holder.setup(esqueleto)
	_cleanup.append(holder)
	_check(is_equal_approx(holder.current_damage(), 34.0), "el gladius base pega 34 sin mult")
	holder.set_damage_mult(1.3)
	_check(is_equal_approx(holder.current_damage(), 44.2), "con 1,3 el gladius pega 44,2")
	holder.switch_to(2)
	_check(is_equal_approx(holder.current_damage(), 58.0), "con 1,3 la spatha sigue en 58")
	holder.switch_to(1)
	_check(is_equal_approx(holder.current_damage(), 40.0), "con 1,3 el pilum sigue en 40")
	holder.switch_to(3)
	_check(is_equal_approx(holder.current_damage(), 22.0), "con 1,3 el pugio sigue en 22")
	holder.switch_to(4)
	_check(is_equal_approx(holder.current_damage(), 48.0), "con 1,3 el hispaniense sigue en 48")


## Un save manipulado o de otra version no puede tumbar el arranque: apply_save
## valida los tipos y degrada cada campo invalido a su default.
func _test_corrupt_save_degrades() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.apply_save({
		"xp": "a",
		"level": "b",
		"coins": -5,
		"inventory": "x",
		"tech": 3,
		"best_streak": -2,
	})
	_check(sistema.xp == 0 and sistema.level == 1,
		"save corrupto: xp y nivel vuelven al default")
	_check(sistema.coins == 0 and sistema.inventory.count("panis") == 0,
		"save corrupto: monedas e inventario vuelven al default")
	_check(sistema.tech.is_empty(), "save corrupto: tech vuelve al default")


## apply_save emite sus senales para que el HUD refleje el nivel cargado al
## instante, y active_type expone el tipo de la mision activa.
func _test_apply_save_emits() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var xps: Array = []
	var monedas: Array = []
	var inventarios := [0]
	var rachas: Array = []
	sistema.xp_changed.connect(func(t: int, _n: int, l: int) -> void: xps.append([t, l]))
	sistema.coins_changed.connect(func(c: int) -> void: monedas.append(c))
	sistema.inventory_changed.connect(func() -> void: inventarios[0] += 1)
	sistema.streak_changed.connect(func(a: int, m: int) -> void: rachas.append([a, m]))
	var guardado := {"xp": 50, "level": 2, "coins": 440, "inventory": {"panis": 2}, "tech": ["pozo"], "best_streak": 5, "current_streak": 2}
	sistema.apply_save(guardado)
	_check(xps.size() == 1 and int((xps[0] as Array)[0]) == 50 and int((xps[0] as Array)[1]) == 2, "apply_save emite xp_changed con el nivel cargado")
	_check(monedas.size() == 1 and int(monedas[0]) == 440, "apply_save emite coins_changed con las monedas cargadas")
	_check(inventarios[0] == 1, "apply_save emite inventory_changed al cargar el inventario")
	_check(rachas.size() == 1 and int((rachas[0] as Array)[0]) == 2 and int((rachas[0] as Array)[1]) == 5, "apply_save emite streak_changed con las rachas cargadas")
	_check(sistema.active_type() == "", "active_type vacio sin mision activa")
	_check(sistema.start_mission("bandit_purge") and sistema.active_type() == "purge", "active_type es purge con la purga activa")
	sistema.abandon_mission()


## El tablero se vacia al fallar: sin la senal mission_failed la activa quedaba
## obsoleta tras un fallo.
func _test_board_clears_on_fail() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.seed_rng(999)
	var combate := StubCombateTablero.new()
	combate.name = "StubCombateTableroFallo"
	root.add_child(combate)
	_cleanup.append(combate)
	var tablero := MissionBoard.new()
	root.add_child(tablero)
	_cleanup.append(tablero)
	await process_frame
	tablero.call("setup", sistema, combate)
	tablero.call("open")
	_check(bool(tablero.call("is_open")), "el tablero abre para el fallo")
	(tablero.call("accept_button", "bandit_purge") as Button).emit_signal("pressed")
	_check(sistema.is_mission_active(), "aceptar la purga inicia la mision para el fallo")
	sistema.fail_mission()
	_check(str(tablero.call("active_label_text")).contains("Sin misión activa"),
		"al fallar el tablero vacia la activa")
	_check(not sistema.is_mission_active(), "tras fallar no hay mision activa")
	tablero.call("close")


## La muerte de Rito en purga falla la mision: el campamento engancha died como
## DefenseSite.
func _test_purge_death_fails() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var combatant: Combatant = ctx[1]
	sistema.seed_rng(4242)
	var completadas: Array = []
	var fallidas: Array = []
	sistema.mission_completed.connect(func(mision: Dictionary, _recompensas: Dictionary) -> void:
		completadas.append(mision))
	sistema.mission_failed.connect(func(mision: Dictionary) -> void:
		fallidas.append(mision))
	_check(sistema.start_mission("bandit_purge"), "iniciar la purga para la muerte funciona")

	var arena := Node3D.new()
	arena.name = "ArenaPurgaMuerte"
	root.add_child(arena)
	_cleanup.append(arena)
	await process_frame
	var jugador := StubJugadorDefensa.new()
	jugador.name = "JugadorPurga"
	jugador.combatant = combatant
	_cleanup.append(jugador)
	var camp := BanditCamp.spawn(arena, Vector3(0, 0, 0), 4, null, sistema, jugador)
	_check(camp != null and camp.get_child_count() == 4, "el campamento de la purga crea 4 bandidos")
	combatant.take_damage(9999.0, Vector3.ZERO)
	_check(fallidas.size() == 1 and not sistema.is_mission_active(),
		"la muerte de Rito en purga falla la mision una sola vez")
	_check(completadas.is_empty(), "la purga fallida por muerte no completa")
	_check(camp.is_queued_for_deletion(), "tras fallar por muerte el campamento se libera")


## Inventario jugable: capa 6, tecla I, abrir/cerrar, monedas, uso con clic y
## Crear sal con la tecnologia y los ingredientes.
func _test_inventory_menu() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	var combatant: Combatant = ctx[1]
	var combate := StubCombateTablero.new()
	combate.name = "StubCombateInventario"
	root.add_child(combate)
	_cleanup.append(combate)
	var menu := InventoryMenu.new()
	root.add_child(menu)
	_cleanup.append(menu)
	await process_frame
	menu.call("setup", sistema, combate)
	_check(menu.layer == 6, "el inventario vive en la capa 6")
	_check(not bool(menu.call("is_open")), "el inventario arranca cerrado")
	_check(InputMap.has_action("inventory"), "la accion inventory existe")
	var tecla_ok := false
	if InputMap.has_action("inventory"):
		for evento in InputMap.action_get_events("inventory"):
			var tecla := evento as InputEventKey
			if tecla != null and tecla.physical_keycode == 73:
				tecla_ok = true
	_check(tecla_ok, "la accion inventory usa la fisica I (73)")
	menu.call("open")
	_check(bool(menu.call("is_open")), "open deja el inventario abierto")
	_check(not combate.input_enabled, "open deshabilita el input de combate del inventario")
	sistema.coins = 100
	sistema.inventory.add("panis", 2)
	sistema.emit_signal("coins_changed", 100)
	sistema.emit_signal("inventory_changed")
	_check(str(menu.call("coins_label_text")).contains("100"), "el inventario muestra los denarios")
	var btn_panis := menu.call("button_for", "panis") as Button
	_check(btn_panis != null, "hay boton Usar para el panis")
	combatant.health = 30.0
	(btn_panis as Button).emit_signal("pressed")
	_check(is_equal_approx(combatant.health, 65.0), "el clic usa el panis y cura 35")
	_check(sistema.inventory.count("panis") == 1, "usar desde el inventario consume un panis")
	var sal_btn := menu.call("craft_sal_button") as Button
	_check(sal_btn != null and sal_btn.disabled, "sin salazon el boton Crear sal esta deshabilitado")
	sistema.buy_tech("salazon")
	menu.call("refresh")
	var sal_btn2 := menu.call("craft_sal_button") as Button
	_check(not sal_btn2.disabled, "con salazon y panis el boton Crear sal se habilita")
	(sal_btn2 as Button).emit_signal("pressed")
	_check(sistema.inventory.count("sal") == 1 and sistema.inventory.count("panis") == 0,
		"el clic Crear sal consume el panis y deja una sal")
	menu.call("close")
	_check(not bool(menu.call("is_open")), "close cierra el inventario")
	_check(combate.input_enabled, "close restaura el input del inventario")


## Espejo del botin de mundo y supresion del guardado: Progression emite
## loot_applied, MissionSystem lo refleja, y con suppress activo el archivo no se
## pisa con el subset.
func _test_pickup_mirror_and_suppress() -> void:
	var ctx: Array = _make_system()
	var sistema: MissionSystem = ctx[0]
	sistema.coins = 0
	var prog := Progression.new()
	root.add_child(prog)
	_cleanup.append(prog)
	await process_frame
	prog.call("setup", null, {})
	var botines: Array = []
	prog.loot_applied.connect(func(b: Dictionary) -> void: botines.append(b))
	prog.call("suppress_save", true)
	prog.apply_loot({"denarii": 15, "panis": 1})
	_check(botines.size() == 1 and int((botines[0] as Dictionary).get("denarii", 0)) == 15,
		"apply_loot emite loot_applied con el botin")
	sistema.apply_pickup_loot(botines[0] as Dictionary)
	_check(sistema.coins == 15, "el espejo pasa los denarios a MissionSystem")
	_check(sistema.inventory.count("panis") == 1, "el espejo pasa el panis a MissionSystem")
	_borrar_guardado()
	SaveGame.save({"coins": 999, "inventory": {"panis": 9}})
	prog.apply_loot({"denarii": 1, "panis": 1})
	var crudo := SaveGame.load()
	var inv_crudo: Dictionary = crudo.get("inventory", {})
	_check(int(crudo.get("coins", 0)) == 999 and int(inv_crudo.get("panis", 0)) == 9,
		"con suppress el guardado no pisa el archivo")
	_borrar_guardado()
