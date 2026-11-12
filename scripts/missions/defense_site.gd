class_name DefenseSite
extends Node3D

## Sitio de defensa para la mision de ciudad: aguanta tres oleadas de bandidos
## (4, 6 y 8) en un anillo a 18 m alrededor de las ruinas, con una pausa de
## 20 s entre oleadas. Cada baja suma a la mision activa y al caer el ultimo
## de la oleada 3 el MissionSystem completa la mision solo (18 objetivos).
## Reusa el bandido de mision de BanditCamp: mismo tinte rojizo y grupos
## (hostiles + mission_bandits).
##
## Headless y tests: el contador de la pausa es un acumulador en _process
## (sin Timer de escena) y wave_pause es una var publica que los tests ponen
## a 0; _advance_time_for_test(s) adelanta el temporizador a mano, asi que el
## flujo de oleadas no depende de esperar 20 s en tiempo real.

## Oleadas de la defensa: 4, 6 y 8 bandidos (18 en total, como los targets).
const WAVES: Array[int] = [4, 6, 8]
## Radio del anillo en metros alrededor de las ruinas.
const RING_RADIUS := 18.0

## Pausa entre oleadas en segundos. Var publica y no const: los tests la
## ponen a 0 para que la oleada siguiente entre sin esperar tiempo real.
var wave_pause := 20.0

var _bandidos: Array[Node3D] = []
var _restantes := 0
var _oleada := 0
var _centro: Vector3
var _terreno: Variant = null
var _sistema: MissionSystem
var _objetivo: Node3D
var _en_pausa := false
var _pausa_restante := 0.0
var _terminado := false`r`nvar _mutators: Dictionary = {}`r`n

## Levanta el sitio de defensa en las ruinas y lanza la oleada 1 (4 bandidos
## en anillo a 18 m). El objetivo trae el Combatant de Rito para fallar la
## mision si el jugador cae a mitad de defensa.
static func begin(parent: Node, ruins: Vector3, terrain: Variant, system: MissionSystem, target: Node3D, mutators: Dictionary = {}) -> Node3D:
	var sitio := DefenseSite.new()
	sitio.name = "DefenseSite"
	parent.add_child(sitio)
	sitio._sistema = system
	sitio._centro = ruins
	sitio._terreno = terrain
	sitio._objetivo = target
	sitio._mutators = mutators
	sitio._conectar_muerte(target)
	sitio._spawn_wave(0)
	return sitio


## Cierre sin recompensa (fallo, abandono o desmontaje desde main): libera a
## los bandidos vivos (y los cadaveres pendientes) y detiene el temporizador.
## Las bajas posteriores ya no suman, el guardado no paga.
func finish() -> void:
	_terminado = true
	_en_pausa = false
	for bandido in _bandidos:
		if is_instance_valid(bandido):
			bandido.queue_free()
	_bandidos.clear()


## Adelanta el temporizador de pausa a mano (solo para tests): si la oleada
## siguiente tenia que esperar, al consumirse el tiempo aparece.
func _advance_time_for_test(segundos: float) -> void:
	if _terminado or not _en_pausa:
		return
	_pausa_restante -= segundos
	if _pausa_restante <= 0.0:
		_en_pausa = false
		_spawn_wave(_oleada + 1)


## Resto de la pausa en tiempo real: al consumirse entra la oleada siguiente.
func _process(delta: float) -> void:
	if _terminado or not _en_pausa:
		return
	_pausa_restante -= delta
	if _pausa_restante <= 0.0:
		_en_pausa = false
		_spawn_wave(_oleada + 1)


## Una oleada en anillo alrededor del centro con la altura del terreno (o la
## del centro sin terreno, como el campamento de la purga). La oleada
## siguiente solo puede entrar tras esta: _en_pausa y _terminado lo guardan.
func _spawn_wave(indice: int) -> void:
	_oleada = indice
	var conteo: int = WAVES[indice]
	var tipos := BanditCamp.composition(int(_sistema.level), conteo)
	_restantes = conteo
	var datos: Variant = _terreno.get_data() if _terreno != null else null
	for i in conteo:
		var angulo := TAU * float(i) / float(conteo)
		var posicion := _centro + Vector3(cos(angulo), 0.0, sin(angulo)) * RING_RADIUS
		if datos != null:
			var altura: float = datos.get_height(Vector3(posicion.x, 0.0, posicion.z))
			posicion.y = _centro.y if is_nan(altura) else altura
		var bandido := BanditCamp.spawn_bandit(self, posicion, angulo, _terreno, _objetivo, tipos[i], null, _mutators)
		(bandido.get_node("Combatant") as Combatant).died.connect(Callable(self, "_on_bandit_died"))
		_bandidos.append(bandido)


## Cada baja suma a la mision. Al caer la oleada 3, el decimoctavo kill
## completa la mision solo (targets=18) y el sitio se libera; antes, si la
## pausa es 0 entra la siguiente oleada al instante y si no, espera.
func _on_bandit_died(_source_position: Vector3) -> void:
	if _terminado or _sistema == null or not is_instance_valid(_sistema):
		return
	_restantes -= 1
	_sistema.register_mission_kill()
	if _restantes > 0:
		return
	if _oleada >= WAVES.size() - 1:
		queue_free()
		return
	if wave_pause <= 0.0:
		_spawn_wave(_oleada + 1)
		return
	_en_pausa = true
	_pausa_restante = wave_pause


## Si el jugador cae a mitad de defensa, la mision falla y el sitio se libera:
## el Combatant de Rito (accesible por el objetivo) emite died y aqui se
## puentea a fail_mission. Si el objetivo no trae Combatant, el cableado de
## main cierra el sitio al fallar/abandonar/completar la mision.
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
	if _sistema != null and is_instance_valid(_sistema):
		_sistema.fail_mission()
	queue_free()
