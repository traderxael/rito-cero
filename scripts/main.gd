extends Node3D

const WorldBuilderScript := preload("res://scripts/world/world_builder.gd")
const VegetationScript := preload("res://scripts/world/vegetation.gd")
const RitoScript := preload("res://scripts/player/rito.gd")
const BootOverlayScript := preload("res://scripts/ui/boot_overlay.gd")
const QualityScript := preload("res://scripts/render/quality.gd")
const DayNightScript := preload("res://scripts/world/day_night.gd")
const StructuresScript := preload("res://scripts/world/structures.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")
const RitoCombatScript := preload("res://scripts/player/rito_combat.gd")
const RomanDogScript := preload("res://scripts/npc/roman_dog.gd")
const SlaveScript := preload("res://scripts/npc/slave.gd")
const ArsenalMenuScript := preload("res://scripts/ui/arsenal_menu.gd")
const SfxScript := preload("res://scripts/audio/sfx.gd")
const FeelScript := preload("res://scripts/fx/feel.gd")
const ImpactFxScript := preload("res://scripts/fx/impact_fx.gd")
const ProgressionScript := preload("res://scripts/missions/progression.gd")
const WeaponScript := preload("res://scripts/combat/weapon.gd")
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const MissionBoardScript := preload("res://scripts/ui/mission_board.gd")
const TechMenuScript := preload("res://scripts/ui/tech_menu.gd")
## Pulido (Task 1): el coordinador de menus escucha J/T/I/Tab-B y Esc por los
## cuatro paneles y deja que Esc llegue a la pausa si no hay ninguno abierto.
const MenuCoordinatorScript := preload("res://scripts/ui/menu_coordinator.gd")
const InventoryMenuScript := preload("res://scripts/ui/inventory_menu.gd")
const DamageNumberScript := preload("res://scripts/fx/damage_number.gd")

var _combatant: Combatant
var _progression: Node
var _dog: CharacterBody3D
var _slave: SlaveScript
var _missions: MissionSystem
var _camp: Node3D
var _defense: Node3D
var _world_event: Node
var _poi_ref: Dictionary = {}
var _terrain_ref: Terrain3D
var _rito_ref: Node3D
var _marker: ObjectiveMarker
var _hud: CanvasLayer
var _tech_menu: CanvasLayer
var _inventory_menu: CanvasLayer
var _save_timer := 0.0


func _ready() -> void:
	var world: Node3D = WorldBuilderScript.new()
	world.name = "World"
	add_child(world)

	var rito: CharacterBody3D = RitoScript.new()
	rito.name = "Player"
	add_child(rito)

	_combatant = CombatantScript.new()
	_combatant.name = "Combatant"
	rito.add_child(_combatant)

	await world.attach_player(rito)
	_combatant.setup(100.0, 2.0)
	rito.bind_combatant(_combatant, world.spawn_point)

	var player_attack: RitoCombat = RitoCombatScript.new()
	player_attack.name = "Combat"
	rito.add_child(player_attack)
	player_attack.setup(rito)

	# Game feel global: sonidos procedurales, particulas de impacto, shake y hit-stop.
	# Todos alcanzan a los demas por grupo, asi que los tests headless sin main siguen
	# funcionando con las llamadas en null.
	var sfx: Node = SfxScript.new()
	sfx.name = "Sfx"
	add_child(sfx)
	sfx.call("bind_player", rito)

	var fx: Node3D = ImpactFxScript.new()
	fx.name = "ImpactFx"
	add_child(fx)

	var feel: Node = FeelScript.new()
	feel.name = "Feel"
	add_child(feel)
	feel.call("setup", fx)
	rito.call("bind_feel", feel)

	# Progresión: denarios, consumibles (tecla E) y el objetivo de eliminar 6 bandidos.
	# Consolidación de guardado (Task 13): MissionSystem es el dueño del guardado
	# porque su current_save() es el superset (xp/nivel/denarios/inventario/tech/
	# rachas) y el de Progression ({denarios, inventario}) es un subconjunto.
	# Ambos leen el MISMO dict (sin sumar: no hay doble conteo) y tras el apply
	# el archivo se reescribe como superset para que el _save() inmediato de
	# Progression.setup no deje el archivo degradado. Durante la partida los dos
	# nodos acumulan por separado; el guardado de MissionSystem (cada 30 s, al
	# completar y al cerrar) gana y es el que se lee en el próximo arranque. La
	# ventana pendiente es solo el botín de Progression entre su último _save()
	# y el siguiente guardado de MissionSystem (máx. 30 s): el archivo puede
	# retener denarios/inventario algo más viejos en ese intervalo, sin perder
	# nunca XP/nivel/tech/rachas.
	var datos_guardado := SaveGame.load()
	_progression = ProgressionScript.new()
	_progression.name = "Progression"
	add_child(_progression)
	# Suprimir ANTES de setup: restaurar no debe escribir el subconjunto y pisar el
	# superset con el que MissionSystem guarda xp/nivel/tech/rachas.
	_progression.call("suppress_save", true)
	_progression.call("setup", player_attack, datos_guardado)

	# El moloso acompana a Rito desde el principio y trabaja para el: sus mordiscos
	# cuentan como bajas de Rito.
	_dog = RomanDogScript.new()
	_dog.name = "Dog"
	add_child(_dog)
	_dog.call("setup", rito)
	_dog.global_position = world.spawn_point + Vector3(1.6, 0.0, 1.2)
	_dog.connect("killed", Callable(player_attack, "add_kill"))
	rito.call("bind_dog", _dog)

	# Nuevo: esclavo con modelo esquelético y animaciones
	_slave = SlaveScript.new()
	_slave.name = "Slave"
	add_child(_slave)
	_slave.call("setup", rito, rito.global_position)
	_slave.global_position = world.spawn_point + Vector3(3.0, 0.0, 3.0)
	_slave.connect("killed", Callable(player_attack, "add_kill"))
	rito.call("bind_slave", _slave)

	# Numeros de dano flotantes: el pool vive en el grupo "damage_numbers" y el
	# combate lo busca ahi cuando un tajo aterriza.
	var numbers: Node3D = DamageNumberScript.new()
	numbers.name = "DamageNumbers"
	add_child(numbers)

	var arsenal: CanvasLayer = ArsenalMenuScript.new()
	arsenal.name = "Arsenal"
	add_child(arsenal)
	arsenal.call("setup", rito, player_attack)

	var day_night: Node = DayNightScript.new()
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.call("setup", world.sun, world.sky_material, world.world_environment.environment, rito)

	var vegetation: Node3D = VegetationScript.new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.setup(world.terrain, rito)

	var structures: Node3D = StructuresScript.new()
	structures.name = "Structures"
	add_child(structures)
	structures.call("setup", world.terrain, rito)

	# Misiones: la purga levanta su campamento en la Columna rota al iniciarse y lo
	# desmonta al cerrarse. Convive con la Progression clasica hasta la Task 13.
	_missions = MissionSystem.new()
	_missions.name = "Missions"
	add_child(_missions)
	_terrain_ref = world.terrain
	_poi_ref = (structures.poi_positions as Dictionary).duplicate()
	_rito_ref = rito
	_missions.call("setup", rito, player_attack, structures.poi_positions, world.terrain)
	# Restauración diferida: apply_save emite xp/coins/inventory/streak y el HUD
	# aun no esta enlazado aqui, asi que el guardado se aplica mas abajo, tras
	# bind_mission_system, para que el HUD refleje el nivel cargado al instante.
	# El guardado parcial de Progression.setup se tapa con el superset justo despues.
	# Doble pool: MissionSystem es el pool jugable (E/HUD/inventario); Progression
	# deja de escribir el archivo para no pisar el superset, y sus pickups de mundo
	# se espejan a MissionSystem por loot_applied. La supresion ya se aplico antes
	# de su setup (arriba); esta llamada queda como recordatorio idempotente.
	_progression.connect("loot_applied", Callable(_missions, "apply_pickup_loot"))
	_missions.connect("mission_started", Callable(self, "_on_mission_started"))
	_missions.connect("mission_completed", Callable(self, "_on_mission_completed"))
	_missions.connect("mission_failed", Callable(self, "_on_mission_failed"))
	_missions.connect("mission_abandoned", Callable(self, "_on_mission_abandoned"))
	# Red de seguridad de la purga: BanditCamp ya escucha la muerte (como
	# DefenseSite), pero si el campamento no esta, la purga activa debe fallar
	# por la muerte de Rito y no quedarse colgada.
	_combatant.connect("died", Callable(self, "_on_player_died"))

	# Evento de mundo ELIMINADO por recorte de presupuesto (T14, ultimo recurso):
	# la web quedo en 26-27 FPS (<36) tras el primer recorte (columna del
	# marcador). La entrega sigue siendo tablero + purga + defensa. La clase
	# WorldEvent y su plantilla oculta se conservan (los testa
	# progression_test en aislamiento) pero ya no se instancia en el juego.
	_world_event = null

	# La armeria desbloquea las armas nuevas del catalogo: el pugio con la armeria 1
	# y el hispaniense con la armeria 2. El resto no pide tecnologia (unlock_tech = "").
	# El mismo chequeo va al arsenal y al combate por teclado (las teclas 4/5).
	var chequeo := func(id: String) -> bool:
		var tech := str(WeaponScript.unlock_tech(id))
		if tech.is_empty():
			return true
		return _missions.has_tech(tech)
	arsenal.call("set_unlock_check", chequeo)
	player_attack.call("set_unlock_check", chequeo)

	# Tablero de misiones: se abre con J y deja el combate en pausa blanda.
	var tablero: CanvasLayer = MissionBoardScript.new()
	tablero.name = "MissionBoard"
	add_child(tablero)
	tablero.call("setup", _missions, player_attack)

	# Árbol de tecnología: se abre con T y deja el combate en pausa blanda.
	# Consume MissionSystem (buy_tech/has_tech); el daño del gladius se aplica por
	# la señal tech_changed al WeaponsHolder de Rito.
	var tech_menu: CanvasLayer = TechMenuScript.new()
	tech_menu.name = "TechMenu"
	add_child(tech_menu)
	tech_menu.call("setup", _missions, player_attack)
	_tech_menu = tech_menu
	_missions.connect("tech_changed", Callable(self, "_on_tech_changed"))

	# Inventario: se abre con I y deja el combate en pausa blanda. Lee el mismo
	# MissionSystem que E (MissionSystem es el pool jugable).
	var inventario_menu: CanvasLayer = InventoryMenuScript.new()
	inventario_menu.name = "InventoryMenu"
	add_child(inventario_menu)
	inventario_menu.call("setup", _missions, player_attack)
	_inventory_menu = inventario_menu

	# Marcador de objetivo en el mundo: columna de luz sobre el poi de la
	# mision. Empieza oculta hasta que MissionSystem emite mission_started.
	_marker = ObjectiveMarker.new()
	_marker.name = "ObjectiveMarker"
	add_child(_marker)

	var hud: CanvasLayer = HudScript.new()
	hud.name = "Hud"
	add_child(hud)
	hud.call("setup", rito, world.terrain, world.spawn_point, player_attack, _progression, structures.boss)
	hud.call("bind_mission_system", _missions)
	_hud = hud
	# Restauración del guardado: MissionSystem aplica el superset una sola vez
	# (XP/nivel/denarios/inventario/tech/rachas) y el archivo se reescribe ya
	# como superset, tapando el guardado parcial que acaba de hacer Progression.
	# Va tras bind_mission_system para que las senales de apply_save lleguen al HUD.
	_missions.apply_save(datos_guardado)
	# Re-aplicación de la armería al arrancar: el multiplicador del gladius solo
	# se aplicaba al comprar (tech_changed); tras cargar un guardado con armería
	# hay que reaplicarlo al holder o el gladius arranca en 1,0 hasta la próxima
	# compra.
	if _missions.has_tech("armeria1") or _missions.has_tech("armeria2") or _missions.has_tech("armeria3"):
		_apply_armeria_mult()
	SaveGame.save(_missions.current_save())

	var overlay: CanvasLayer = BootOverlayScript.new()
	overlay.name = "BootOverlay"
	add_child(overlay)
	overlay.setup(rito)

	var quality: Node = QualityScript.new()
	quality.name = "Quality"
	add_child(quality)

	var pause: CanvasLayer = PauseMenuScript.new()
	pause.name = "PauseMenu"
	add_child(pause)

	# Coordinador de menus blandos: escucha J/T/I/Tab-B y Esc por los cuatro
	# paneles, abre uno cerrando los demas y deja que Esc llegue a la pausa
	# cuando no hay ningun menu blando abierto.
	var coordinador := MenuCoordinatorScript.new()
	coordinador.name = "MenuCoordinator"
	add_child(coordinador)
	coordinador.call("setup", {
		"mission_board": tablero,
		"tech_tree": tech_menu,
		"inventory": inventario_menu,
		"arsenal_menu": arsenal,
	}, pause)


## Purga aceptada: levanta el campamento en la Columna rota con los objetivos
## de la mision. Los ambientales ya estan pausados (MissionSystem lo hace antes
## de emitir mission_started), asi que el campamento no los despierta.
func _on_mission_started(mision: Dictionary) -> void:
	_set_objective_marker(mision)
	if _missions == null:
		return
	var tipo := str(mision.get("type", ""))
	if tipo == "purge":
		if not _poi_ref.has("columna") or _terrain_ref == null or _rito_ref == null:
			return
		var centro: Vector3 = _poi_ref["columna"]
		if centro == Vector3.ZERO:
			# Sin POI (punto ZERO): no se levanta campamento sobre el origen del
			# mundo. La mision queda activa y el jugador puede abandonarla desde
			# el tablero. No se crea un campamento fantasma en el (0,0,0).
			push_warning("Purga sin POI columna (ZERO): no se levanta campamento")
			return
		_close_camp()
		_camp = BanditCamp.spawn(self, centro, int(mision.get("targets", 0)), _terrain_ref, _missions, _rito_ref)
	elif tipo == "defense":
		if not _poi_ref.has("ruinas") or _terrain_ref == null or _rito_ref == null:
			return
		var centro: Vector3 = _poi_ref["ruinas"]
		if centro == Vector3.ZERO:
			# Sin POI (punto ZERO): no se levanta sitio sobre el origen del mundo.
			# La mision queda activa y el jugador puede abandonarla desde el tablero.
			push_warning("Defensa sin POI ruinas (ZERO): no se levanta sitio")
			return
		_close_defense()
		_defense = DefenseSite.begin(self, centro, _terrain_ref, _missions, _rito_ref)


func _on_mission_completed(_mision: Dictionary, _recompensas: Dictionary) -> void:
	_close_camp()
	_close_defense()
	_clear_objective_marker()
	_save_progress()


func _on_mission_failed(_mision: Dictionary) -> void:
	_close_camp()
	_close_defense()
	_clear_objective_marker()


func _on_mission_abandoned(_mision: Dictionary) -> void:
	_close_camp()
	_close_defense()
	_clear_objective_marker()


## Muerte de Rito durante la purga: falla la mision y cierra el campamento.
## DefenseSite ya escucha solo la muerte para la defensa; aqui la purga queda
## cubierta aunque BanditCamp no este (los dos caminos fallan una sola vez por
## el guardado de MissionSystem sin mision activa).
func _on_player_died(_source_position: Vector3) -> void:
	if _missions == null or not _missions.is_mission_active():
		return
	if _missions.active_type() == "purge":
		_missions.fail_mission()
		_close_camp()


## Compra de armería: pasa el multiplicador de daño del gladius al WeaponsHolder
## de Rito. Se aplica con cualquier nivel de armeria para que 1,1/1,2/1,3 entren
## en cuanto se compra (mira la mayor comprada en MissionSystem).
func _on_tech_changed(node_id: String) -> void:
	if _missions == null:
		return
	if not str(node_id).begins_with("armeria"):
		return
	_apply_armeria_mult()


## Aplica el multiplicador de la armería mayor al holder del gladius. Es el mismo
## efecto para la compra en caliente y para la restauración del guardado al
## arrancar.
func _apply_armeria_mult() -> void:
	if _missions == null or _rito_ref == null:
		return
	var holder: WeaponsHolder = _rito_ref.get("weapons") as WeaponsHolder
	if holder == null:
		return
	holder.set_damage_mult(_missions.gladius_damage_mult())


## Guardado de MissionSystem (el superset). Se llama cada 30 s, al completar una
## misión y al pedir el cierre de la ventana, para que el archivo siempre guarde
## XP/nivel/tech/rachas además de denarios e inventario.
func _save_progress() -> void:
	if _missions == null:
		return
	SaveGame.save(_missions.current_save())


func _process(delta: float) -> void:
	if _missions == null:
		return
	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		_save_progress()


func _notification(what: int) -> void:
	# Cierre de ventana (escritorio): guardar sin esperar al temporizador.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_progress()


## Columna de luz + punto en el minimapa sobre el poi de la mision. El poi ya
## trae la altura del suelo; el marcador le suma sus 11 m internamente.
func _set_objective_marker(mision: Dictionary) -> void:
	var poi: String = str(mision.get("poi", ""))
	if poi.is_empty() or not _poi_ref.has(poi):
		return
	var pos: Vector3 = _poi_ref[poi]
	if _marker != null:
		_marker.set_target(pos)
	var mapa := _minimap()
	if mapa != null:
		mapa.call("set_objective", pos)


## Apaga columna y punto del minimapa al cerrarse la mision.
func _clear_objective_marker() -> void:
	if _marker != null:
		_marker.clear()
	var mapa := _minimap()
	if mapa != null:
		mapa.call("clear_objective")


## El minimapa lo crea el HUD: se alcanza sin tocar su cableado propio.
func _minimap() -> Node:
	if _hud == null:
		return null
	return _hud.get("_minimap")


## Desmonta el campamento y libera sus bandidos (el vivo no paga: es desercion).
func _close_camp() -> void:
	if _camp == null or not is_instance_valid(_camp):
		_camp = null
		return
	_camp.call("finish")
	_camp.queue_free()
	_camp = null


## Desmonta el sitio de defensa y libera sus bandidos vivos: al cerrarse la
## mision por cualquier via no queda oleada en el mundo. El sitio ya se
## libero solo al completar o al morir Rito; aqui finish + queue_free es
## no-op en esos casos (ya esta en cola de borrado).
func _close_defense() -> void:
	if _defense == null or not is_instance_valid(_defense):
		_defense = null
		return
	_defense.call("finish")
	_defense.queue_free()
	_defense = null


func _unhandled_input(event: InputEvent) -> void:
	# C silba al moloso: deja la pelea y vuelve con su amo aunque este lejos.
	if event.is_action_pressed("call_dog") and _dog != null and is_instance_valid(_dog):
		_dog.call("call_to_player")
	# E come el mejor consumible de MissionSystem (panis primero) y cura al instante.
	# El pool jugable es MissionSystem; Progression queda como legado (ver espejo).
	if event.is_action_pressed("use_potion") and _missions != null:
		for id in ["panis", "aqua", "pizza", "gelatum"]:
			if _missions.use_item(id):
				var sfx := get_tree().get_first_node_in_group("sfx")
				if sfx != null:
					sfx.call("play_local", "pickup", -6.0)
				break
