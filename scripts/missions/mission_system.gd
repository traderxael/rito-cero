class_name MissionSystem
extends Node

## Nucleo de progresion: XP, nivel, denarios, rachas, recompensas, curacion y
## tecnologias. Sin UI: las senales son el contrato con el HUD y el guardado.
## Sin mision activa completar/abandonar/fallar es no-op (paga una sola vez).

signal xp_changed(total: int, needed: int, level: int)
signal coins_changed(coins: int)
signal mission_started(mission: Dictionary)
signal mission_progress(current: int, goal: int)
signal mission_completed(mission: Dictionary, rewards: Dictionary)
signal mission_failed(mission: Dictionary)
signal mission_abandoned(mission: Dictionary)
signal inventory_changed()
signal streak_changed(current: int, best: int)
signal tech_changed(node_id: String)

## Nivel maximo del jugador.
const MAX_LEVEL := 20
## Segundos de cooldown por mision tras cerrarla: bloquea esa mision, no la otra.
## Si ambas estan en cooldown, available_missions devuelve lista vacia.
const COOLDOWN_SECONDS := 90.0
## Vida maxima base (nivel 1) y el extra por nivel: +5, aplicado sin revivir.
const BASE_MAX_HEALTH := 100.0
const HEALTH_PER_LEVEL := 5.0

## Coste de cada tecnologia. La armeria funciona por niveles sueltos (armeria1..3),
## no secuenciales: gladius_damage_mult mira la mayor comprada.
const TECH_COSTS := {
	"pozo": 60,
	"acequia": 60,
	"salazon": 80,
	"granero": 100,
	"molino": 100,
	"bodega": 120,
	"armeria1": 80,
	"armeria2": 150,
	"armeria3": 250,
}

var xp := 0
var level := 1
var coins := 0
var current_streak := 0
var best_streak := 0
var inventory: GameInventory
var tech: Array = []

var _rito: Node
var _combat: Node
var _poi: Dictionary = {}
var _terrain: Variant = null
var _active: Dictionary = {}
var _cooldowns: Dictionary = {}
var _rng: RandomNumberGenerator
var _seeded := false
var _paused_ambient: Array = []


func _init() -> void:
	inventory = GameInventory.new()
	_rng = RandomNumberGenerator.new()
	_rng.randomize()


func _ready() -> void:
	# El arnes siembra el RNG antes de que _ready corriera con el seed del test:
	# no se vuelve a aleatorizar una semilla fijada con seed_rng.
	if not _seeded:
		_rng.randomize()


## Semilla determinista del botin para tests (y demos reproducibles).
func seed_rng(n: int) -> void:
	_rng.seed = n
	_seeded = true


## Expira todos los cooldowns de golpe. Solo para tests: el cooldown real es de
## 90 s por mision y en juego se espera en tiempo real.
func expire_cooldowns() -> void:
	_cooldowns.clear()


## Enlaza el jugador y el combate y aplica la vida maxima del nivel actual.
## Rito y combate van sin tipo estatico a proposito: los tests pasan stubs y el
## acceso es duck-typed (Rito expone combatant; Combatant, heal/setup/health).
func setup(rito: Node, combat: Node, poi: Dictionary, terrain: Variant = null) -> void:
	_rito = rito
	_combat = combat
	_poi = poi
	_terrain = terrain
	_apply_max_health()


## XP que pide el nivel n para subir al siguiente: 100 * n^1,5 (L1=100, L2=282).
static func xp_needed(n: int) -> int:
	return int(100.0 * pow(float(n), 1.5))


## Suma XP y sube niveles mientras alcance: cada subida aplica el +5 de vida maxima.
func add_xp(amount: int) -> void:
	xp += amount
	var subio := false
	while level < MAX_LEVEL and xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		subio = true
	if subio:
		_apply_max_health()
	xp_changed.emit(xp, xp_needed(level), level)


## Instancias disponibles: las que no estan en cooldown y no son ocultas. Sin
## mision activa solo hay dos plantillas de tablero; con las dos en cooldown
## la lista queda vacia. Las plantillas hidden (world_event) nunca salen aqui:
## WorldEvent las arranca con start_mission directo, sin pasar por el tablero.
func available_missions() -> Array:
	var lista: Array = []
	for id in MissionData.TEMPLATES:
		if MissionData.is_hidden(str(id)):
			continue
		if _in_cooldown(str(id)):
			continue
		lista.append(MissionData.make_instance(str(id), level))
	return lista


func is_mission_active() -> bool:
	return not _active.is_empty()


## Tipo de la mision activa ("purge"/"defense"/...) o "" sin mision. Lo usa main
## para decidir si la muerte de Rito falla la purga (la defensa ya escucha sola
## por DefenseSite).
func active_type() -> String:
	if _active.is_empty():
		return ""
	return str(_active.get("type", ""))


## Inicia una mision: falso si ya hay una activa, si el id no existe o si esa
## mision concreta esta en cooldown (la otra puede seguir disponible). Acepta
## tambien las plantillas ocultas (world_event): estan en TEMPLATES para que
## start_mission las arranque, pero available_missions las excluye del tablero.
func start_mission(template_id: String) -> bool:
	if is_mission_active() or not MissionData.TEMPLATES.has(template_id):
		return false
	if _in_cooldown(template_id):
		return false
	_active = MissionData.make_instance(template_id, level)
	_pause_ambient()
	mission_started.emit(_active)
	return true


## Registra una baja de la mision activa. Al alcanzar los objetivos completa la
## mision internamente (y paga una sola vez) y devuelve true.
func register_mission_kill() -> bool:
	if not is_mission_active():
		return false
	var done := int(_active.get("kills_done", 0)) + 1
	_active["kills_done"] = done
	mission_progress.emit(done, int(_active.get("targets", 0)))
	if done >= int(_active.get("targets", 0)):
		complete_mission()
		return true
	return false


## Completa la mision activa y paga: XP, monedas (techo de la banda + denarios del
## botin), botin con multiplicadores de tech, racha +1 y cooldown de 90 s.
## Sin mision activa es no-op: el guard _active == {} garantiza un unico pago.
func complete_mission() -> void:
	if not is_mission_active():
		return
	var mision := _active.duplicate(true)
	_active = {}
	_restore_ambient()
	var botin := _roll_loot_with_tech()
	_apply_tech_to_loot(botin)
	var denarios := int(botin.get("denarii", 0))
	botin.erase("denarii")
	var banda: Array = mision.get("coins", [0, 0])
	var monedas := int(banda[1]) + denarios
	coins += monedas
	coins_changed.emit(coins)
	for id in botin:
		inventory.add(str(id), int(botin[id]))
	if not botin.is_empty():
		inventory_changed.emit()
	var recompensas := {
		"xp": int(mision.get("xp", 0)),
		"coins": monedas,
		"loot": botin,
	}
	add_xp(int(mision.get("xp", 0)))
	current_streak += 1
	best_streak = maxi(best_streak, current_streak)
	streak_changed.emit(current_streak, best_streak)
	_cooldowns[str(mision.get("id", ""))] = _now() + COOLDOWN_SECONDS
	mission_completed.emit(mision, recompensas)


## Falla la mision activa: racha a 0 y cooldown. Sin activa es no-op.
func fail_mission() -> void:
	if not is_mission_active():
		return
	var mision := _active.duplicate(true)
	_active = {}
	_restore_ambient()
	_reset_streak()
	_cooldowns[str(mision.get("id", ""))] = _now() + COOLDOWN_SECONDS
	mission_failed.emit(mision)


## Abandona la mision activa: racha a 0 y cooldown. Sin activa es no-op.
func abandon_mission() -> void:
	if not is_mission_active():
		return
	var mision := _active.duplicate(true)
	_active = {}
	_restore_ambient()
	_reset_streak()
	_cooldowns[str(mision.get("id", ""))] = _now() + COOLDOWN_SECONDS
	mission_abandoned.emit(mision)


## Cura con un item del inventario. La sal sola no cura (no es consumible) y el
## panis con sal suma +15 consumiendo la sal. A vida llena o sin item devuelve
## false sin consumir nada. Clamp al maximo lo hace Combatant.heal.
func use_item(item_id: String) -> bool:
	var combatant: Variant = _combatant()
	if combatant == null:
		return false
	if float(combatant.get("health")) >= float(combatant.get("max_health")):
		return false
	if not GameInventory.CONSUMABLES.has(item_id) or not inventory.has(item_id):
		return false
	if combatant.has_method("is_alive") and not bool(combatant.call("is_alive")):
		return false
	var cura := int(float(GameInventory.CONSUMABLES[item_id]))
	if item_id == "aqua" and has_tech("pozo"):
		cura = int(cura * 1.25)
	if item_id == "panis" and has_tech("molino"):
		cura = int(cura * 1.5)
	if item_id == "gelatum" and has_tech("bodega"):
		cura = cura * 2
	inventory.remove(item_id)
	if item_id == "panis" and inventory.has("sal"):
		cura += 15
		inventory.remove("sal")
	combatant.call("heal", float(cura))
	inventory_changed.emit()
	return true


## Craftea 1 sal con 1 panis + 10 denarios. Requiere la tecnologia salazon.
func craft_sal() -> bool:
	if not has_tech("salazon") or not inventory.has("panis") or coins < 10:
		return false
	inventory.remove("panis")
	coins -= 10
	inventory.add("sal", 1)
	coins_changed.emit(coins)
	inventory_changed.emit()
	return true


## Espejo del botin de mundo de Progression (pickups): denarios a monedas y resto a
## inventario, con sus senales. Main lo conecta a Progression.loot_applied para que
## el botin suelto no se pierda en el doble pool. La sincronizacion bidireccional
## completa sigue pendiente (ver informe de la oleada de arreglo).
func apply_pickup_loot(loot: Dictionary) -> void:
	var cambio := false
	for id in loot:
		var n := int(loot[id])
		if n <= 0:
			continue
		if id == "denarii":
			coins += n
		else:
			inventory.add(str(id), n)
		cambio = true
	if not cambio:
		return
	coins_changed.emit(coins)
	inventory_changed.emit()


## Compra una tecnologia: falso si el id no existe, ya la tiene o no llegan los
## denarios. Verdadero y resta el coste exacto.
func buy_tech(node_id: String) -> bool:
	if not TECH_COSTS.has(node_id) or has_tech(node_id):
		return false
	var coste := int(TECH_COSTS[node_id])
	if coins < coste:
		return false
	coins -= coste
	tech.append(node_id)
	coins_changed.emit(coins)
	tech_changed.emit(node_id)
	return true


func has_tech(node_id: String) -> bool:
	return tech.has(node_id)


## Multiplicador de dano del gladius segun la mayor armeria comprada: 1,0/1,1/1,2/1,3.
func gladius_damage_mult() -> float:
	if has_tech("armeria3"):
		return 1.3
	if has_tech("armeria2"):
		return 1.2
	if has_tech("armeria1"):
		return 1.1
	return 1.0


## Guardado de progresion: siete claves y NUNCA la mision activa (recargar a media
## mision la pierde, y eso es diseno).
func current_save() -> Dictionary:
	return {
		"version": SaveGame.VERSION,
		"xp": xp,
		"level": level,
		"coins": coins,
		"inventory": inventory.to_dict(),
		"tech": tech.duplicate(),
		"best_streak": best_streak,
		"current_streak": current_streak,
	}


## Restaura un guardado (JSON plano; los ints llegan como float, se usa int()).
## Con {} empieza de cero en el nivel 1. Limpia mision activa y cooldowns.
## Al terminar emite xp/coins/inventory/streak para que el HUD refleje el nivel
## cargado al instante (antes quedaba en "Nv 1" hasta la siguiente XP).
func apply_save(data: Dictionary) -> void:
	_active = {}
	_cooldowns.clear()
	_restore_ambient()
	xp = maxi(0, _int_or(data.get("xp", 0), 0))
	level = clampi(_int_or(data.get("level", 1), 1), 1, MAX_LEVEL)
	coins = maxi(0, _int_or(data.get("coins", 0), 0))
	best_streak = maxi(0, _int_or(data.get("best_streak", 0), 0))
	current_streak = maxi(0, _int_or(data.get("current_streak", 0), 0))
	var inv_data: Variant = data.get("inventory", {})
	if typeof(inv_data) == TYPE_DICTIONARY:
		inventory.from_dict(_sanitize_inventory(inv_data))
	else:
		inventory.from_dict({})
	tech = []
	var tech_data: Variant = data.get("tech", [])
	if typeof(tech_data) == TYPE_ARRAY:
		for nodo in tech_data:
			tech.append(str(nodo))
	_apply_max_health()
	xp_changed.emit(xp, xp_needed(level), level)
	coins_changed.emit(coins)
	inventory_changed.emit()
	streak_changed.emit(current_streak, best_streak)


## Un save manipulado o de una version futura no puede tumbar el arranque: los
## valores que no sean del tipo esperado se degradan a su default.
func _int_or(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


func _sanitize_inventory(raw: Dictionary) -> Dictionary:
	var limpio := {}
	for key in raw:
		var value: Variant = raw[key]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			continue
		var cantidad := clampi(int(value), 0, 9999)
		if cantidad > 0:
			limpio[str(key)] = cantidad
	return limpio


## El Combatant de Rito sin tipo estatico: duck typing para no acoplar tests.
func _combatant() -> Variant:
	if _rito == null or not is_instance_valid(_rito):
		return null
	return _rito.get("combatant")


## Aplica la vida maxima del nivel (+5 por nivel) sin curar ni revivir: si vive,
## re-siembras con setup() y devuelves la vida que tenia; si esta muerto no se toca
## su estado de muerte (setup reapareceria: lo prohibe la regla "sin revivir").
func _apply_max_health() -> void:
	var combatant: Variant = _combatant()
	if combatant == null:
		return
	var nuevo_max := BASE_MAX_HEALTH + HEALTH_PER_LEVEL * float(level - 1)
	if bool(combatant.call("is_alive")):
		var vida := float(combatant.get("health"))
		combatant.call("setup", nuevo_max)
		combatant.set("health", minf(vida, nuevo_max))
	else:
		combatant.set("max_health", nuevo_max)


## Tirada de botin del tier que toca al nivel, con el RNG interno.
func _roll_loot_with_tech() -> Dictionary:
	var tier := LootTable.tier_for_level(level)
	return LootTable.roll(tier, _rng)


## Multiplicadores de tech sobre el botin: pozo aqua x1,25, acequia panis x1,25
## (redondeo hacia arriba: 1 -> 2) y granero panis +1.
func _apply_tech_to_loot(botin: Dictionary) -> void:
	if botin.has("aqua") and has_tech("pozo"):
		botin["aqua"] = int(ceil(float(botin["aqua"]) * 1.25))
	if botin.has("panis") and has_tech("acequia"):
		botin["panis"] = int(ceil(float(botin["panis"]) * 1.25))
	if botin.has("panis") and has_tech("granero"):
		botin["panis"] = int(botin["panis"]) + 1


func _reset_streak() -> void:
	if current_streak != 0:
		current_streak = 0
		streak_changed.emit(current_streak, best_streak)


func _in_cooldown(id: String) -> bool:
	return float(_cooldowns.get(id, 0.0)) > _now()


## Pausa los hostiles ambientales no-mision a mas de 50 m: al iniciar la mision no
## deben interferir. Sin arbol o sin nodos en el grupo es no-op.
func _pause_ambient() -> void:
	_paused_ambient.clear()
	if not is_inside_tree() or _rito == null or not is_instance_valid(_rito):
		return
	for nodo in get_tree().get_nodes_in_group("hostiles"):
		if nodo is Node3D and (nodo as Node3D).global_position.distance_to((_rito as Node3D).global_position) > 50.0:
			nodo.process_mode = PROCESS_MODE_DISABLED
			_paused_ambient.append(nodo)


func _restore_ambient() -> void:
	for nodo in _paused_ambient:
		if is_instance_valid(nodo):
			nodo.process_mode = PROCESS_MODE_INHERIT
	_paused_ambient.clear()


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
