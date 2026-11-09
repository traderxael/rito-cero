class_name MissionTracker
extends RefCounted

## Objetivo de la partida: eliminar GOAL hostiles. El combate del jugador emite
## kill_count_changed con el total y Progression traduce eso en bajas del tracker,
## una a una, hasta completar la mision.

signal progress_changed(kills: int, goal: int)
signal completed()

const GOAL := 6

var kills := 0
var goal := GOAL
var _done := false


func reset() -> void:
	kills = 0
	_done = false
	progress_changed.emit(kills, goal)


func add_kill() -> void:
	if _done:
		return
	kills += 1
	progress_changed.emit(kills, goal)
	if kills >= goal:
		_done = true
		completed.emit()


func is_completed() -> bool:
	return _done


func label() -> String:
	return "Bajas: %d/%d" % [kills, goal]
