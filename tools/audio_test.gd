extends SceneTree

## Arnes del banco de sonidos procedural y del reproductor Sfx: sin GPU ni dispositivo de
## audio (el driver dummy del headless basta para crear los nodos), se comprueba que cada
## efecto se genera con datos reales y que la puerta de distancia del reproductor funciona.

const SfxBankScript := preload("res://scripts/audio/sfx_bank.gd")
const SfxScript := preload("res://scripts/audio/sfx.gd")

const EXPECTED_CHECKS := 26

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_test_bank()
	await _test_player()
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


func _test_bank() -> void:
	for name in SfxBankScript.NAMES:
		var stream: AudioStreamWAV = SfxBankScript.get_stream(name)
		_check(stream != null and stream.data.size() > 0 and stream.mix_rate == SfxBankScript.MIX_RATE
			and stream.format == AudioStreamWAV.FORMAT_16_BITS,
			"el banco genera datos reales para " + name)

	var wind: AudioStreamWAV = SfxBankScript.get_stream("wind")
	_check(wind.loop_mode == AudioStreamWAV.LOOP_FORWARD and wind.loop_end > 0,
		"el viento es un loop cerrado")

	var hit: AudioStreamWAV = SfxBankScript.get_stream("hit")
	var seconds := float(hit.data.size()) / 2.0 / float(hit.mix_rate)
	_check(seconds >= 0.10, "el golpe dura al menos 0,1 s (dura %.3f s)" % seconds)

	var again: AudioStreamWAV = SfxBankScript.get_stream("hit")
	_check(again == hit, "el banco cachea: misma instancia en la segunda llamada")


func _test_player() -> void:
	var sfx: Sfx = SfxScript.new()
	root.add_child(sfx)
	var listener := CharacterBody3D.new()
	root.add_child(listener)
	listener.global_position = Vector3.ZERO
	sfx.bind_player(listener)
	await process_frame

	_check(sfx.play("hit", Vector3(3, 0, 0)) == true, "un golpe a 3 m suena")
	_check(sfx.play("hit", Vector3(500, 0, 0)) == false, "un golpe a 500 m queda fuera de oido")
	_check(sfx.play_local("ui") == true, "el clic de UI suena en local")
	# En headless no hay salida de audio: el reproductor deja de estar "playing" al
	# instante y el pool reutiliza el mismo slot. Lo que se puede verificar es que el
	# stream se asigne a un reproductor del pool, no cuantos slots quedan ocupados.
	_check(sfx.assigned_streams() >= 1, "los efectos asignan stream a un reproductor del pool")

	sfx.set_ambience(0.0)
	_check(is_equal_approx(sfx.wind_volume_db(), SfxScript.WIND_NIGHT_DB), "de noche el viento esta alto")
	sfx.set_ambience(1.0)
	_check(is_equal_approx(sfx.wind_volume_db(), SfxScript.WIND_DAY_DB), "de dia el viento baja")

	sfx.free()
	listener.free()
