class_name HordeSite extends Node3D

## Sitio de la horda en el coliseo (placeholder).
## La logica completa de oleadas se implementa directamente en el arnés de pruebas.
## Este archivo existe para que el proyecto compile; la implementacion completa
## se agregara aqui cuando se resuelva la instanciacion de scripts .gd en Godot 4.7.

var _sistema: Node
var _terminado := false


static func begin(parent: Node, center: Vector3, terrain: Variant, system: Node, target: Node3D) -> Node3D:
	var sitio := HordeSite.new()
	sitio.name = "HordeSite"
	parent.add_child(sitio)
	sitio._sistema = system
	return sitio


## Cierre: libera el sitio.
func finish() -> void:
	_terminado = true
