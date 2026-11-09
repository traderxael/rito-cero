extends SceneTree

## El mapa de teclas es contrato de juego: si dos acciones comparten tecla, una
## pulsacion dispara las dos. Este arnes lo comprueba sin abrir una ventana.

const EXPECTED_CHECKS := 6

var _failures := 0
var _checks_run := 0


func _init() -> void:
	var dodge_keys := _keys("dodge")
	var dog_keys := _keys("call_dog")
	_check(not dog_keys.is_empty(), "call_dog tiene una tecla")
	_check(not dodge_keys.is_empty(), "dodge tiene una tecla")
	_check(not _shares(dodge_keys, dog_keys), "esquivar y silbar no comparten tecla")
	_check(dog_keys.has(KEY_C), "el silbido del moloso va en C")
	_check(_keys("toggle_mouse").is_empty(), "toggle_mouse ya no existe")
	_check(_keys("arsenal_menu").has(KEY_B) and not _keys("arsenal_menu").has(KEY_TAB),
		"el arsenal se abre con B, no con Tab")
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


func _keys(action: String) -> Array:
	var keys := []
	if not InputMap.has_action(action):
		return keys
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	return keys


func _shares(a: Array, b: Array) -> bool:
	for key in a:
		if b.has(key):
			return true
	return false
