class_name BossNpc
extends "res://scripts/npc/hostile_npc.gd"

## Praetorian de la cueva: mas vida, mas dano y mas cuerpo que un bandido. Su muerte
## no cuenta como baja de bandidos: cierra el objetivo del Praetorian y deja la
## recompensa, que es la que decide Progression (el nucleo de reglas).

signal boss_defeated

const BOSS_MAX_HEALTH := 320.0
const BOSS_DAMAGE := 28.0
const BOSS_SCALE := 1.35
const BOSS_TITLE := "Praetorian"


func setup_boss(data, center: Vector3, angle: float, target: Node3D = null) -> void:
	max_health = BOSS_MAX_HEALTH
	attack_damage = BOSS_DAMAGE
	body_scale = BOSS_SCALE
	counts_as_kill = false
	super.setup(data, center, angle, target)
	_dress_as_boss()


## Armadura oscura y brillante: el mismo maniqui, con aire de pretoriano.
func _dress_as_boss() -> void:
	if _body_material != null:
		_body_material.albedo_color = Color(0.34, 0.30, 0.26)
		_body_material.metallic = 0.6


func _on_defeated() -> void:
	boss_defeated.emit()
	var prog := get_tree().get_first_node_in_group("progression")
	if prog != null:
		prog.call("on_boss_defeated")
