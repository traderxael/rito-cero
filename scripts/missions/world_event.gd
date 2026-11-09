class_name WorldEvent
extends Node

## Evento de mundo: campamento de bandidos en el Muro. Espera 180 s desde el
## arranque; con cualquier mision activa se suspende; al cerrarse una mision
## reinicia con 120 s; si al vencer el Muro esta ocupado o hay mision activa,
## reintenta en 60 s; si lleva 900 s sin tocarse expira con finish().
##
## Al activarse levanta 3 bandidos con el tinte rojizo de BanditCamp en
## poi["muro"] y arranca la mision oculta world_event con start_mission
## directo (sin pasar por el tablero). Matar a los 3 completa la mision
## (XP 80 y banda 40-80 escaladas por nivel, como el resto). Mientras el
## evento sigue sin resolver no hay duplicados.
##
## El marcador lo reutiliza de main: al arrancar world_event, main llama a
## _set_objective_marker con el poi del muro (la misma columna de 11 m que
## usa purga y defensa) y el HUD muestra "Bandidos restantes: N" por
## mission_started (el tipo event cae en la rama no-defense del HUD). No se
## crea una columna propia de 12 m: dos pilares en el mismo punto seria
## duplicar y parpatear.
##
## Tiempo testeable: los cuatro retrasos son vars publicas (event_delay,
## restart_delay, retry_delay, event_ttl) y _advance_time_for_test(segundos)
## adelanta el acumulador a mano sin esperar tiempo real; _process usa el
## mismo camino por frame.

## Retraso inicial desde el arranque.
const EVENT_DELAY := 180.0
## Reinicio tras cerrarse cualquier mision.
const RESTART_DELAY := 120.0
## Reintento si al vencer hay mision activa o el Muro esta ocupado.
const RETRY_DELAY := 60.0
## Vida del evento sin tocar antes de expirar con finish().
const EVENT_TTL := 900.0
## Id de la plantilla oculta que arranca este evento.
const EVENT_ID := "world_event"
## Bandidos por activacion.
const EVENT_COUNT := 3

## Retrasos en segundos; publicos para que los tests y main los ajusten sin
## tocar las consts. Se inicializan con las consts y _advance_time_for_test
## los consume.
var event_delay := EVENT_DELAY
var restart_delay := RESTART_DELAY
var retry_delay := RETRY_DELAY
var event_ttl := EVENT_TTL

var _sistema: MissionSystem
var _poi: Dictionary = {}
var _terreno: Variant = null
var _objetivo: Node3D
var _camp: Node3D
var _temporizador := EVENT_DELAY
var _ttl_restante := 0.0
var _suspendido := false
var _activo := false
var _terminado := false


## Enlaza sistema, poi y terreno. parent es Rito (el objetivo de los
## bandidos), como el target de DefenseSite.begin; el campamento cuelga de
## este nodo. Si ya hay mision activa al enlazar, el evento arranca
## suspendido.
func setup(system: MissionSystem, poi: Dictionary, terrain: Variant, parent: Node3D) -> void:
	_sistema = system
	_poi = poi
	_terreno = terrain
	_objetivo = parent
	_temporizador = event_delay
	_ttl_restante = 0.0
	_activo = false
	_terminado = false
	_suspendido = false
	if _sistema == null or not is_instance_valid(_sistema):
		return
	_connect(_sistema, "mission_started", Callable(self, "_on_mission_started"))
	_connect(_sistema, "mission_completed", Callable(self, "_on_mission_completed"))
	_connect(_sistema, "mission_failed", Callable(self, "_on_mission_failed"))
	_connect(_sistema, "mission_abandoned", Callable(self, "_on_mission_abandoned"))
	if _sistema.is_mission_active():
		var actual: Variant = _sistema.get("_active")
		if actual is Dictionary and str((actual as Dictionary).get("id", "")) == EVENT_ID:
			_activo = true
			_ttl_restante = event_ttl
		else:
			_suspendido = true


## True mientras el evento sigue sin resolver (bandidos vivos en el Muro).
func is_event_active() -> bool:
	return _activo and not _terminado


## Bandidos vivos del campamento del evento (0 sin evento o ya terminado).
func bandit_count() -> int:
	if _camp == null or not is_instance_valid(_camp):
		return 0
	var vivos := 0
	for hijo in _camp.get_children():
		var combate: Node = (hijo as Node).get_node_or_null("Combatant")
		if combate != null and bool(combate.call("is_alive")):
			vivos += 1
	return vivos


## Cierre sin recompensa del evento (TTL expirado o desmontaje desde main):
## libera a los vivos y abandona la mision oculta si era la activa, sin
## pagar. Tras finish el temporizador no reinicia mas.
func finish() -> void:
	if _terminado:
		return
	_terminado = true
	_activo = false
	_suspendido = false
	_clear_camp()
	if _sistema != null and is_instance_valid(_sistema) and _sistema.is_mission_active():
		var actual: Variant = _sistema.get("_active")
		if actual is Dictionary and str((actual as Dictionary).get("id", "")) == EVENT_ID:
			_sistema.abandon_mission()


## Adelanta el temporizador a mano (solo para tests): consume segundos del
## estado actual (espera, reintento o TTL) con la misma regla que _process.
func _advance_time_for_test(segundos: float) -> void:
	_tick(segundos)


func _process(delta: float) -> void:
	_tick(delta)


## Un paso del temporizador: si el evento esta activo consume el TTL; si esta
## suspendido no consume nada; si esta esperando consume el temporizador y al
## vencer intenta levantar el campamento, repartiendo el resto en el TTL.
func _tick(segundos: float) -> void:
	if segundos <= 0.0 or _terminado:
		return
	var restante := segundos
	while restante > 0.0 and not _terminado:
		if _activo:
			var paso := minf(restante, _ttl_restante)
			_ttl_restante -= paso
			restante -= paso
			if _ttl_restante <= 0.0:
				finish()
				return
			return
		if _suspendido:
			return
		var paso := minf(restante, _temporizador)
		_temporizador -= paso
		restante -= paso
		if _temporizador > 0.0:
			return
		_try_spawn()


## Intenta levantar el campamento: si ya hay evento sin resolver, si el Muro
## esta ocupado, si no hay sistema o poi, o si hay mision activa o la oculta
## esta en cooldown, reintenta en 60 s sin duplicar. Si despeja, arranca la
## mision oculta y crea el campamento con tinte rojizo en el Muro.
func _try_spawn() -> void:
	if _terminado:
		return
	if _activo:
		_temporizador = retry_delay
		return
	if _camp != null and is_instance_valid(_camp):
		_temporizador = retry_delay
		return
	if _sistema == null or not is_instance_valid(_sistema):
		_temporizador = retry_delay
		return
	if not _poi.has("muro"):
		_temporizador = retry_delay
		return
	if _sistema.is_mission_active():
		_temporizador = retry_delay
		return
	var centro: Variant = _poi["muro"]
	if not (centro is Vector3):
		_temporizador = retry_delay
		return
	if not _sistema.start_mission(EVENT_ID):
		_temporizador = retry_delay
		return
	# start_mission ya emitio mission_started (main pone el marcador en el
	# Muro y el HUD el tracker); solo falta levantar los bandidos.
	_camp = BanditCamp.spawn(self, centro as Vector3, EVENT_COUNT, _terreno, _sistema, _objetivo)
	_activo = true
	_ttl_restante = event_ttl
	_temporizador = 0.0
	_suspendido = false


## Cualquier mision iniciada suspende la espera; la propia world_event marca
## el evento activo y arranca el TTL.
func _on_mission_started(mision: Dictionary) -> void:
	if _terminado:
		return
	if str(mision.get("id", "")) == EVENT_ID:
		_activo = true
		_ttl_restante = event_ttl
		_suspendido = false
	else:
		_suspendido = true


func _on_mission_completed(mision: Dictionary, _recompensas: Dictionary) -> void:
	_on_mission_closed(mision)


func _on_mission_failed(mision: Dictionary) -> void:
	_on_mission_closed(mision)


func _on_mission_abandoned(mision: Dictionary) -> void:
	_on_mission_closed(mision)


## Al cerrarse el evento se limpia el campamento y al cerrarse cualquier otra
## mision se reinicia la espera a 120 s. Tras finish no se reinicia nada.
func _on_mission_closed(mision: Dictionary) -> void:
	if _terminado:
		return
	if str(mision.get("id", "")) == EVENT_ID:
		_clear_camp()
		_activo = false
		_ttl_restante = 0.0
		_temporizador = restart_delay
		_suspendido = false
	elif not _activo:
		_temporizador = restart_delay
		_suspendido = false


## Desmonta el campamento y libera sus bandidos (el vivo no paga: es desercion).
func _clear_camp() -> void:
	if _camp == null or not is_instance_valid(_camp):
		_camp = null
		return
	_camp.call("finish")
	_camp.queue_free()
	_camp = null


func _connect(source: Object, signal_name: String, target: Callable) -> void:
	if source.has_signal(signal_name) and not source.is_connected(signal_name, target):
		source.connect(signal_name, target)
