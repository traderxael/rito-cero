class_name TimedPurge
extends Node3D

signal time_left_changed(seconds: int)

## Sitio de la mision contrarreloj: un campamento de bandidos que debe limpiarse
## antes de que acabe el tiempo. Si el tiempo se agota, la mision falla; si se
## matan a todos los bandidos, se completa (por el campamento).

const BanditCampScript := preload("res://scripts/missions/bandit_camp.gd")

var _camp: Node3D
var _sistema: MissionSystem
var _terrain: Variant
var _objetivo: Node3D
var _terminado := false
var _time_left := 0.0
var _time_left_shown := -1
var _acumulador := 0.0


static func begin(parent: Node, center: Vector3, count: int, terrain: Variant, system: MissionSystem, target: Node3D, seconds: float) -> Node3D:
	var sitio := TimedPurge.new()
	sitio.name = "TimedPurge"
	parent.add_child(sitio)
	sitio._sistema = system
	sitio._terrain = terrain
	sitio._objetivo = target
	sitio._time_left = seconds
	sitio._time_left_shown = ceil(seconds)
	sitio._conectar_muerte(target)
	sitio._camp = BanditCamp.spawn(sitio, center, count, terrain, system, target)
	return sitio


## Cuenta atras: avanza en segundos enteros y avisa por senal.
func _process(delta: float) -> void:
	if _terminado or _camp == null:
		return
	_acumulador += delta
	while _acumulador >= 1.0:
		_acumulador -= 1.0
		_time_left -= 1.0
		var mostrado := ceil(_time_left)
		if mostrado != _time_left_shown:
			_time_left_shown = mostrado
			time_left_changed.emit(int(mostrado))
		if _time_left <= 0.0:
			_fail_por_tiempo()
			return


## Adelanta el temporizador a mano (solo para tests).
func _advance_time_for_test(segundos: float) -> void:
	if _terminado:
		return
	_acumulador += segundos
	while _acumulador >= 1.0:
		_acumulador -= 1.0
		_time_left -= 1.0
		var mostrado := ceil(_time_left)
		if mostrado != _time_left_shown:
			_time_left_shown = mostrado
			time_left_changed.emit(int(mostrado))
		if _time_left <= 0.0:
			_fail_por_tiempo()
			return


## Valor restante de la cuenta atras (solo tests).
func time_left_value() -> float:
	return _time_left


## El tiempo se agoto: la mision falla y el campamento se libera.
func _fail_por_tiempo() -> void:
	if _terminado:
		return
	_terminado = true
	_sistema.fail_mission()
	finish()


## Si el jugador cae, la mision falla.
func _conectar_muerte(objetivo: Node3D) -> void:
	if objetivo == null:
		return
	var combatiente: Variant = objetivo.get("combatant")
	if combatiente != null and (combatiente as Node).has_signal("died"):
		(combatiente as Node).connect("died", Callable(self, "_on_player_died"))


func _on_player_died(_source_position: Vector3) -> void:
	if _terminado:
		return
	_terminado = true
	_sistema.fail_mission()
	finish()


## Cierre sin recompensa: libera el campamento.
func finish() -> void:
	_terminado = true
	if _camp != null and is_instance_valid(_camp):
		_camp.queue_free()
	_camp = null


## El campamento (solo tests).
func camp() -> Node3D:
	return _camp

