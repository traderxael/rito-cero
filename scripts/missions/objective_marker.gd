class_name ObjectiveMarker
extends Node3D

## Marcador de objetivo (recorte de presupuesto T14): sin columna 3D, solo
## el punto del minimapa (main._set_objective_marker -> set_objective) y la
## posicion logica del nodo. Antes era una columna estatica de luz (cilindro
## de 20 m, transparente, con emision); al no llegar a >=36 FPS en web se
## desactivó primero según el orden pactado. Se mantiene la API
## (set_target/clear/ALTURA) para no romper tests ni el HUD.

const ALTURA := 11.0


var _pilar: MeshInstance3D
var _construido := false


func _ready() -> void:
	_construir_pilar()


## Fija el objetivo en un punto de suelo del mundo (posicion logica a 11 m).
func set_target(mundo: Vector3) -> void:
	_construir_pilar()
	global_position = mundo + Vector3(0.0, ALTURA, 0.0)
	visible = true


## Apaga el marcador: la mision se cerro y ya no hay objetivo.
func clear() -> void:
	visible = false


## Sin malla 3D (recorte T14): el nodo existe solo como posicion; el
## feedback visual es el punto dorado del minimapa.
func _construir_pilar() -> void:
	if _construido:
		return
	_construido = true
	visible = false
