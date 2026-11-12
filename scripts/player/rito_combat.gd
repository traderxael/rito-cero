class_name RitoCombat
extends Node

## Politica de combate del jugador: que se pulsa, cuando se puede volver a golpear y que
## animacion va con cada arma. El mecanismo de bloqueo vive en rito.gd; aqui no se repite.
##
## El arsenal tiene dos modos: cuerpo a cuerpo (gladius, spatha), que usa el AttackVolume,
## y lanzamiento (pilum), que crea un proyectil. La diferencia no es solo de numeros:
## el pilum es la unica forma de golpear fuera de la melee.

signal kill_count_changed(count: int)
signal weapon_selected(index: int)
signal combo_changed(step: int)

const AttackVolumeScript := preload("res://scripts/combat/attack_volume.gd")
const ProjectileScript := preload("res://scripts/combat/projectile.gd")
const WeaponScript := preload("res://scripts/combat/weapon.gd")

const ANIM_ATTACK := ["Sword_Attack", "Punch_Jab"]
const ANIM_HEAVY := ["Sword_Attack_RM", "Punch_Cross"]
const ANIM_SPEAR_THRUST := ["Punch_Jab"]

## Una tecla por arma del catalogo. El indice de la accion es el indice del catalogo.
const WEAPON_ACTIONS := ["weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_5"]

## El fuerte es mas lento y golpea algo mas fuerte: 1,3x la cadencia por 1,25x el dano.
const HEAVY_DAMAGE := 1.25
const HEAVY_COOLDOWN := 1.3
const HEAVY_SPEED := 0.8

## Capa 4: los NPCs. La 2 es Rito, que no puede darse a si mismo con el volumen de ataque.
const TARGET_MASK := 4

## Color de la rafaga de un tajo aterrizado.
const BLOOD := Color(0.75, 0.10, 0.06)

## Color del critico: dorado, para que se distinga de un tajo normal.
const CRITICAL_COLOR := Color(1.0, 0.74, 0.22)

## Combo de tres golpes: cada eslabon pega mas que el anterior y el tercero deja al
## bandido vendido. Es la recompensa por no recibir dano entre tajo y tajo.
## La ventana de enlace es de 1,25 s: la cadencia del gladius es de 0,55 s pero la
## animacion bloquea al jugador alrededor de medio segundo, asi que entre tajo y
## tajo quedan unos 0,9 s. Con menos de un segundo la cadena se rompia antes de
## tiempo y el combo nunca se completaba.
const COMBO_DAMAGE := [1.0, 1.15, 1.6]
const COMBO_WINDOW := 1.25
const COMBO_STAGGER := 0.7

## Golpear por la espalda vale el doble. El objetivo mira a +Z, asi que el critico
## es "el jugador esta detras de el": el producto vectorial tiene que ser bien
## negativo.
const CRITICAL_MULTIPLIER := 2.0
const CRITICAL_DOT := -0.35

var kills := 0
var weapon_index := 0

var _rito: Rito
var _volume: AttackVolume
var _cooldown_until := 0.0
var _recover_at := 0.0
var _resolved_attack := ""
var _resolved_heavy := ""
var _resolved_thrust := ""
var _input_enabled := true

## Puerta de desbloqueo de armas: Callable(id de arma) -> bool, igual que en el
## arsenal. Sin chequeo, todas las armas se pueden equipar.
var _unlock_check: Callable

## Estado del combo en curso: en que eslabon va y hasta cuando sigue vivo.
var _combo_step := 0
var _combo_until := 0.0


func _sfx() -> Sfx:
	return get_tree().get_first_node_in_group("sfx") as Sfx


func _feel() -> Feel:
	return get_tree().get_first_node_in_group("feel") as Feel


func setup(rito: Rito) -> void:
	_rito = rito
	var player: AnimationPlayer = rito.animation_player
	if player != null:
		_resolved_attack = _first_existing(player, ANIM_ATTACK)
		_resolved_heavy = _first_existing(player, ANIM_HEAVY)
		_resolved_thrust = _first_existing(player, ANIM_SPEAR_THRUST)

	_volume = AttackVolumeScript.new()
	_volume.name = "AttackVolume"
	_rito.model.add_child(_volume)
	_volume.landed.connect(_on_landed)
	_apply_weapon_geometry()


func _process(_delta: float) -> void:
	if _rito == null or not _rito.is_alive():
		return
	if _now() >= _recover_at and not _rito.weapons.is_weapon_visible():
		_rito.weapons.set_weapon_visible(true)
	if not _input_enabled:
		return
	for i in WEAPON_ACTIONS.size():
		if Input.is_action_just_pressed(WEAPON_ACTIONS[i]):
			_switch(i)
			break
	if Input.is_action_just_pressed("block"):
		_rito.try_parry()
	if Input.is_action_pressed("block"):
		_rito.set_guarding(true)
	elif _rito.is_guarding():
		_rito.set_guarding(false)
	if Input.is_action_just_pressed("attack"):
		_rito.set_guarding(false)
		_try_attack(false)
	elif Input.is_action_just_pressed("heavy_attack"):
		_rito.set_guarding(false)
		_try_attack(true)
	if Input.is_action_just_pressed("dodge"):
		_rito.set_guarding(false)
		_try_dodge()


## La esquiva es input de combate, pero la fisica es del jugador: aqui solo se traduce la
## pulsacion y la direccion de entrada.
func _try_dodge() -> void:
	if _rito == null or not _rito.is_alive():
		return
	_rito.try_dodge(_rito.input_direction())


## El menu de arsenal congela el input de combate, pero no el mundo: el jugador sigue
## viendo el valle moverse detras del panel.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


func is_input_enabled() -> bool:
	return _input_enabled


## Fija la puerta de desbloqueo (la misma del arsenal): main pasa el Callable que
## lee MissionSystem.has_tech sobre Weapon.unlock_tech. Sin esto, las teclas 4/5
## saltaban el bloqueo del arsenal.
func set_unlock_check(unlock_check: Callable) -> void:
	_unlock_check = unlock_check


func switch_weapon(index: int) -> void:
	_switch(index)


func current_weapon_name() -> String:
	if _rito == null or _rito.weapons == null:
		return ""
	return _rito.weapons.current_name()


## La baja puede venir del combate del jugador o de la senal killed del moloso,
## que manda el objetivo. El argumento es opcional para que las dos llamadas valgan:
## antes la senal reventaba porque add_kill no aceptaba el objetivo.
func add_kill(_target: Node = null) -> void:
	kills += 1
	kill_count_changed.emit(kills)


## El objetivo esta de espaldas cuando el jugador le llega por detras. El modelo
## del bandido mira a +Z, asi que el producto vectorial entre su frente y la
## direccion al jugador tiene que ser negativo.
func _is_behind(target: Node) -> bool:
	var body := target as Node3D
	if body == null or _rito == null:
		return false
	var forward := body.global_transform.basis.z
	var model = body.get("_model")
	if model is Node3D and is_instance_valid(model):
		forward = (model as Node3D).global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return false
	var to_player := _rito.global_position - body.global_position
	to_player.y = 0.0
	if to_player.length() < 0.01:
		return false
	return forward.normalized().dot(to_player.normalized()) < CRITICAL_DOT


## Pide el aturdimiento al objetivo si sabe recibirlo (el bandido y el jefe).
func _stagger(target: Node, seconds: float) -> void:
	if not target.has_method("stagger"):
		return
	target.call("stagger", seconds)


## El numero de dano flotante: un pool de etiquetas que suben y se desvanecen.
func _show_damage_number(at: Vector3, amount: float, critical: bool) -> void:
	var numbers := get_tree().get_first_node_in_group("damage_numbers")
	if numbers == null:
		return
	numbers.call("show_at", at, amount, critical)


func _switch(index: int) -> void:
	if index == weapon_index or index < 0 or index >= WeaponScript.count():
		return
	# Puerta de teclado: sin la tecnologia de armeria que pide el arma, el cambio
	# se deniega igual que en el arsenal. Sin chequeo (tests viejos), no se bloquea.
	if _unlock_check.is_valid():
		var id := str(WeaponScript.get_weapon(index)["id"])
		if not bool(_unlock_check.call(id)):
			return
	weapon_index = index
	_rito.weapons.switch_to(index)
	_apply_weapon_geometry()
	weapon_selected.emit(weapon_index)


## El volumen se construye una vez y solo cambian sus parametros: si la geometria del arma
## nueva no se aplica hasta el primer cambio de arma, el gladius inicial no golpea a nadie.
## En modo lanzamiento el volumen se deja sin alcance: el pilum no taja, lanza. El radio no
## puede ser 0 porque Jolt rechaza una esfera de radio nulo.
func _apply_weapon_geometry() -> void:
	var holder: WeaponsHolder = _rito.weapons
	if holder.current_mode() == WeaponScript.MODE_THROW:
		_volume.setup(0.0, 0.01, TARGET_MASK)
		return
	_volume.setup(holder.current_reach(), holder.current_radius(), TARGET_MASK)


## Intento de golpe. Es publico para que los tests puedan encadenar la cadena
## sin falsificar el teclado.
func try_attack(heavy: bool) -> bool:
	return _try_attack(heavy)


func _try_attack(heavy: bool) -> bool:
	if _now() < _cooldown_until or _rito.is_locked():
		return false
	var holder: WeaponsHolder = _rito.weapons
	var weapon: Dictionary = holder.current_weapon()
	if weapon["mode"] == WeaponScript.MODE_THROW:
		_throw(weapon, heavy)
		return true

	# El combo: el fuerte rompe la cadena, el tajo normal la continua. La ventana de
	# enlace es corta: si el jugador tarda mas, el siguiente golpe vuelve a ser el
	# primero.
	var combo_multiplier := 1.0
	if heavy:
		_combo_step = 0
	else:
		if _now() > _combo_until or _combo_step >= COMBO_DAMAGE.size():
			_combo_step = 0
		_combo_step += 1
		combo_multiplier = float(COMBO_DAMAGE[_combo_step - 1])
		_combo_until = _now() + COMBO_WINDOW
		combo_changed.emit(_combo_step)

	var damage: float = holder.current_damage() * combo_multiplier * (HEAVY_DAMAGE if heavy else 1.0)
	var cooldown: float = holder.current_cooldown() * (HEAVY_COOLDOWN if heavy else 1.0)
	var window: Vector2 = holder.current_window()
	var speed: float = holder.current_anim_speed() * (HEAVY_SPEED if heavy else 1.0)

	var clip_length := 0.5
	var name := _attack_animation(heavy)
	if name != "":
		var player: AnimationPlayer = _rito.animation_player
		clip_length = player.get_animation(name).length / speed
		# El bloqueo dura lo que la ventana de dano, no lo que dura el clip: si cubriera el
		# clip entero la cadencia de la tabla quedaria sustituida por la duracion de la
		# animacion y el gladius golpearia cada 0,77 s en lugar de cada 0,55 s.
		_rito.play_one_shot(name, clip_length * window.y, Rito.PRIORITY_ATTACK, speed)
		_volume.begin_swing(damage, _rito, window.x, window.y, clip_length)
		_cooldown_until = _now() + cooldown
		var sfx := _sfx()
		if sfx != null:
			sfx.play("swing_heavy" if heavy else "swing", _rito.global_position, -8.0)
	return true


## El pilum no taja: se lanza. El arma desaparece de la mano y vuelve cuando pasa la
## cadencia, para que no haya dos pilum en la misma mano.
func _throw(weapon: Dictionary, heavy: bool) -> void:
	var damage := float(weapon["damage"]) * (HEAVY_DAMAGE if heavy else 1.0)
	var cooldown := float(weapon["cooldown"]) * (HEAVY_COOLDOWN if heavy else 1.0)
	var speed := float(weapon["anim_speed"])

	var name := _resolved_thrust
	if name != "":
		var player: AnimationPlayer = _rito.animation_player
		var clip_length := player.get_animation(name).length / speed
		# El bloqueo es corto: es una suelta de brazo, no un tajo con ventana de dano.
		_rito.play_one_shot(name, minf(clip_length * 0.45, 0.35), Rito.PRIORITY_ATTACK, speed)

	_cooldown_until = _now() + cooldown
	_recover_at = _now() + cooldown * 0.8
	_rito.weapons.set_weapon_visible(false)
	_spawn_projectile(weapon, damage)
	var sfx := _sfx()
	if sfx != null:
		sfx.play("throw", _rito.weapons.hand_position(), -8.0)


func _spawn_projectile(weapon: Dictionary, damage: float) -> void:
	var direction: Vector3 = _rito.model.global_transform.basis.z
	direction.y = 0.0
	direction = direction.normalized()
	if direction.length() < 0.5:
		direction = Vector3(0, 0, 1)

	var projectile := ProjectileScript.new()
	projectile.name = "Pilum"
	var host: Node = _rito.get_parent()
	if host == null:
		host = get_tree().current_scene
	host.add_child(projectile)
	projectile.setup(_rito.weapons.hand_position(), direction, damage, float(weapon["speed"]), float(weapon["reach"]))
	projectile.landed.connect(_on_projectile_landed)


func _attack_animation(heavy: bool) -> String:
	if heavy and _resolved_heavy != "":
		return _resolved_heavy
	return _resolved_attack


func _on_landed(target: Node, damage: float, was_stunned: bool = false, allow_riposte: bool = true) -> void:
	var combatant := target.get_node_or_null("Combatant") as Combatant
	# El critico se decide al aterrizar, que es cuando se sabe a quien se ha
	# golpeado. `was_stunned` llega capturado ANTES del dano base: si se leyera el
	# estado ahora, el STUN que el propio golpe acaba de provocar haria critico
	# cada impacto. El volumen ya quito el dano base: el extra va aparte.
	var critical := _is_behind(target) or was_stunned
	var riposte := _rito.consume_riposte() if allow_riposte else 1.0
	var multiplier := CRITICAL_MULTIPLIER if critical else 1.0
	if riposte > 1.0:
		# El contraataque nunca puede hacer menos dano que un critico normal sobre
		# un enemigo aturdido: el parry ya lo deja en STUN.
		critical = true
		multiplier = maxf(multiplier, riposte)
	if multiplier > 1.0 and combatant != null and combatant.is_alive():
		combatant.take_damage(damage * (multiplier - 1.0), _rito.global_position)
	var total := damage * multiplier
	var killed := combatant != null and not combatant.is_alive()
	if killed and _counts_as_bandit(target):
		add_kill()
	var at: Vector3 = target.global_position + Vector3(0, 1.1, 0)
	var sfx := _sfx()
	if sfx != null:
		var name := "hit"
		if killed:
			name = "kill"
		elif critical:
			name = "critical"
		elif damage >= 40.0:
			name = "heavy_hit"
		sfx.play(name, at, -4.0)
	var feel := _feel()
	if feel != null:
		feel.impact(at, CRITICAL_COLOR if critical else BLOOD, killed or critical)
		if killed:
			feel.hit_stop(0.09, Feel.IMPACT_TYPE_CRITICAL)
		elif critical:
			feel.hit_stop(0.05, Feel.IMPACT_TYPE_STRONG)
		else:
			feel.shake(0.08, 0.10)
	# El ultimo eslabon del combo y el critico dejan al bandido vendido.
	if combatant != null and combatant.is_alive():
		if _combo_step >= COMBO_DAMAGE.size() or critical:
			_stagger(target, COMBO_STAGGER)
	_show_damage_number(at, total, critical)


func _on_projectile_landed(target: Node, damage: float, was_stunned: bool = false) -> void:
	# El pilum no es un golpe de contraataque: la ventana de riposte sigue viva.
	_on_landed(target, damage, was_stunned, false)


## El Praetorian no es un bandido: su muerte no suma al objetivo de eliminar bandidos.
func _counts_as_bandit(target: Node) -> bool:
	var flag = target.get("counts_as_kill")
	if flag == null:
		return true
	return bool(flag)


func _first_existing(player: AnimationPlayer, candidates: Array) -> String:
	for candidate in candidates:
		if player.has_animation(candidate):
			return candidate
	return ""


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
