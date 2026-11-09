class_name DamageNumber
extends Node3D

## Numeros de dano flotantes: dicen al jugador cuanto pegó sin tener que mirar la
## barra del bandido ni contar las veces que ha dado.
##
## Es un pool fijo de etiquetas 3D. Crear y borrar nodos en mitad de un combate es
## justo lo que hunde los FPS en el navegador, asi que las ocho etiquetas se
## reciclan para siempre.

const POOL_SIZE := 8
const LIFETIME := 0.9
const RISE := 1.1

const NORMAL_COLOR := Color(0.95, 0.92, 0.82)
const CRITICAL_COLOR := Color(1.0, 0.74, 0.22)

var _labels: Array[Label3D] = []
var _next := 0


func _ready() -> void:
	add_to_group("damage_numbers")
	for i in POOL_SIZE:
		var label := Label3D.new()
		label.name = "Num%d" % i
		label.text = "0"
		label.font_size = 44
		label.outline_size = 8
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = NORMAL_COLOR
		label.visible = false
		add_child(label)
		_labels.append(label)


## Muestra el numero en un punto del mundo. El pool es circular: si estan todos
## ocupados, el mas viejo se recicla.
func show_at(at: Vector3, amount: float, critical: bool) -> void:
	if _labels.is_empty():
		return
	var label := _labels[_next]
	_next = (_next + 1) % _labels.size()
	label.text = str(int(round(amount)))
	label.modulate = CRITICAL_COLOR if critical else NORMAL_COLOR
	label.visible = true
	label.position = at + Vector3(0, 0.25, 0)
	label.scale = Vector3.ONE * (1.35 if critical else 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector3(0, RISE, 0), LIFETIME)
	tween.tween_property(label, "scale", Vector3.ONE, LIFETIME * 0.45)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME * 0.5).set_delay(LIFETIME * 0.5)
	tween.chain().tween_callback(func() -> void: label.visible = false)


## Numero de etiquetas vivas: lo usa el test para saber que el pool existe.
func label_count() -> int:
	return _labels.size()
