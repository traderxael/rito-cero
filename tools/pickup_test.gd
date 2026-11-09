extends SceneTree

## Arnes de los pickups del mundo y del nuevo efecto "pickup" del banco de sonidos.

const ProgressionScript := preload("res://scripts/missions/progression.gd")
const PickupScript := preload("res://scripts/missions/pickup.gd")
const SfxBankScript := preload("res://scripts/audio/sfx_bank.gd")

const EXPECTED_CHECKS := 8
const SAVE_PATH := "user://ritocero_save_v1.json"

var _failures := 0
var _checks_run := 0


func _init() -> void:
	_borrar_guardado()
	_test_sfx_pickup()
	await _test_pickup_collect()
	_borrar_guardado()
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


func _borrar_guardado() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _test_sfx_pickup() -> void:
	var stream := SfxBankScript.get_stream("pickup")
	_check(stream != null, "existe el efecto pickup")
	_check(stream.data.size() > 1000, "pickup tiene muestras de sobra")
	var ui := SfxBankScript.get_stream("ui")
	_check(stream.data != ui.data, "pickup no es el mismo stream que ui")


func _test_pickup_collect() -> void:
	var prog: Node = ProgressionScript.new()
	root.add_child(prog)
	prog.call("setup", null, {})

	var pickup: Area3D = PickupScript.new()
	pickup.call("setup", "denarii", 15)
	root.add_child(pickup)
	pickup.global_position = Vector3(1, 0.5, 1)
	var got := {"n": 0, "id": "", "amount": 0}
	pickup.collected.connect(func(id, n):
		got["n"] += 1
		got["id"] = id
		got["amount"] = n)

	var body := CharacterBody3D.new()
	body.collision_layer = 2
	root.add_child(body)
	await process_frame

	pickup.call("_on_body_entered", body)
	_check(int(prog.get("coins")) == 15, "el pickup entrega 15 denarios a Progression")
	_check(got["n"] == 1 and got["id"] == "denarii" and got["amount"] == 15,
		"collected emite id y cantidad")
	_check(pickup.is_queued_for_deletion(), "el pickup se libera al recogerse")

	var pickup2: Area3D = PickupScript.new()
	pickup2.call("setup", "panis", 1)
	root.add_child(pickup2)
	await process_frame
	pickup2.call("_on_body_entered", body)
	_check(int(prog.call("panis_count")) == 1, "un pickup de panis entra al inventario")
	_check(pickup2.call("_color_for", "denarii") == Color(0.95, 0.80, 0.25), "denarii pinta dorado")
