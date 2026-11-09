class_name Progression
extends Node

## Nucleo de progresion de la partida: denarios, inventario de consumibles y la mision
## activa (eliminar 6 bandidos). Vive en el grupo "progression" para que los pickups
## del mundo lo encuentren sin conocer a main.
##
## Persiste monedas e inventario con SaveGame. La mision activa nunca se guarda: al
## recargar se empieza de cero, y eso es diseno (SaveGame lo prohibe igual).

signal coins_changed(coins: int)
signal inventory_changed()
signal mission_changed(kills: int, goal: int)
signal mission_completed()
signal healed(amount: float)
signal boss_progress_changed(kills: int, goal: int)
signal boss_defeated()
signal loot_applied(loot: Dictionary)

## Orden de prioridad al comer con E: el panis cura mas, primero.
const CONSUMABLE_ORDER := ["panis", "aqua", "pizza", "gelatum"]

var inventory := GameInventory.new()
var coins := 0
var tracker := MissionTracker.new()

## Cuando esta activo, _save() no toca el archivo: MissionSystem es el dueno del
## guardado (superset) y main lo conecta tras crear ambos sistemas.
var _save_suppressed := false

## Objetivo del Praetorian: uno solo, el jefe del fondo de la cueva.
var boss_tracker := MissionTracker.new()


func _ready() -> void:
	add_to_group("progression")
	tracker.progress_changed.connect(_on_tracker_progress)
	tracker.completed.connect(func() -> void: mission_completed.emit())
	boss_tracker.goal = 1
	boss_tracker.progress_changed.connect(_on_boss_progress)
	boss_tracker.completed.connect(func() -> void: boss_defeated.emit())


func _on_tracker_progress(kills: int, goal: int) -> void:
	mission_changed.emit(kills, goal)


func setup(combat: Node, save_data: Dictionary = {}) -> void:
	coins = int(save_data.get("coins", 0))
	inventory.from_dict(save_data.get("inventory", {}))
	if combat != null and combat.has_signal("kill_count_changed"):
		combat.kill_count_changed.connect(_on_kill_count)
	tracker.reset()
	coins_changed.emit(coins)
	inventory_changed.emit()


## Desactiva (o reactiva) el guardado propio: main lo suprime cuando MissionSystem
## existe para que el guardado parcial no pise el superset a mitad de partida.
## La sincronizacion bidireccional completa queda para el seguimiento aparcado.
func suppress_save(suppressed: bool) -> void:
	_save_suppressed = suppressed


## El combat cuenta bajas totales (incluye las del moloso); el tracker las sigue una
## a una hasta su goal y ahi se cierra.
func _on_kill_count(count: int) -> void:
	while tracker.kills < count and not tracker.is_completed():
		tracker.add_kill()


## Aplica un botin {id: cantidad}: los denarios van a monedas y el resto al inventario.
## Emite loot_applied con el dict crudo para que main lo espeje a MissionSystem.
func apply_loot(loot: Dictionary) -> void:
	var cambio := false
	for id in loot:
		var n := int(loot[id])
		if n <= 0:
			continue
		if id == "denarii":
			coins += n
		else:
			inventory.add(id, n)
		cambio = true
	if not cambio:
		return
	coins_changed.emit(coins)
	inventory_changed.emit()
	loot_applied.emit(loot)
	_save()


## Come el mejor consumible disponible y devuelve los HP que cura (0 si no hay).
func use_potion() -> float:
	for id in CONSUMABLE_ORDER:
		if inventory.has(id):
			var amount := inventory.use_consumable(id)
			inventory_changed.emit()
			_save()
			if amount > 0.0:
				healed.emit(amount)
			return amount
	return 0.0


func panis_count() -> int:
	return inventory.count("panis")


## Progreso del objetivo del Praetorian.
func boss_progress() -> int:
	return boss_tracker.kills


func _on_boss_progress(kills: int, goal: int) -> void:
	boss_progress_changed.emit(kills, goal)


## El Praetorian cae: cierra su objetivo y deja la recompensa. Solo una vez.
func on_boss_defeated() -> void:
	if boss_tracker.is_completed():
		return
	boss_tracker.add_kill()
	apply_loot({"denarii": 150, "panis": 2})


func _save() -> void:
	# Suprimido en juego: el guardado de MissionSystem (cada 30 s, al completar
	# y al cerrar) es el que gana; sin supresion, este subset pisaria el superset.
	if _save_suppressed:
		return
	SaveGame.save({
		"coins": coins,
		"inventory": inventory.to_dict(),
	})
