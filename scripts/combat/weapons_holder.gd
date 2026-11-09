class_name WeaponsHolder
extends Node3D

## Monta las armas del catalogo en la mano derecha y muestra solo la activa. Cada arma es
## hija de su BoneAttachment3D, asi que sigue al brazo durante el tajo sin recalcular nada.

signal weapon_changed(index: int)

const WeaponScript := preload("res://scripts/combat/weapon.gd")

var _attachments: Array[BoneAttachment3D] = []
var _instances: Array[MeshInstance3D] = []
var _current := 0
var _weapon_visible := true
var _damage_mult := 1.0


func setup(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for i in WeaponScript.count():
		var weapon: Dictionary = WeaponScript.get_weapon(i)

		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "DEF-hand.R"
		skeleton.add_child(attachment)

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = WeaponScript.make_mesh(weapon["mesh"])
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.5
		material.metallic = 0.4
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mesh_instance.material_override = material
		mesh_instance.rotation.x = float(weapon["grip_rot_x"])
		attachment.add_child(mesh_instance)

		attachment.visible = (i == 0)
		_attachments.append(attachment)
		_instances.append(mesh_instance)


func switch_to(index: int) -> void:
	if index < 0 or index >= _attachments.size() or index == _current:
		return
	_attachments[_current].visible = false
	_current = index
	_attachments[_current].visible = _weapon_visible
	weapon_changed.emit(_current)


func current_index() -> int:
	return _current


func current_weapon() -> Dictionary:
	return WeaponScript.get_weapon(_current)


func current_name() -> String:
	return str(current_weapon()["name"])


func current_mode() -> String:
	return str(current_weapon()["mode"])


## Multiplicador del árbol de tecnología (la armería templada): solo aplica al
## gladius (el templado del gladius), no al resto del arsenal. Main lo fija con
## MissionSystem.gladius_damage_mult().
func set_damage_mult(value: float) -> void:
	_damage_mult = value


func current_damage() -> float:
	var base := float(current_weapon()["damage"])
	if str(current_weapon()["id"]) == "gladius":
		return base * _damage_mult
	return base


func current_cooldown() -> float:
	return float(current_weapon()["cooldown"])


func current_reach() -> float:
	return float(current_weapon()["reach"])


func current_radius() -> float:
	return float(current_weapon()["radius"])


func current_window() -> Vector2:
	var weapon := current_weapon()
	return Vector2(float(weapon["window_open"]), float(weapon["window_close"]))


func current_anim_speed() -> float:
	return float(current_weapon()["anim_speed"])


## La posicion global de la mano: el proyectil nace ahi y no en el centro del pecho,
## o el pilum saldría del cuerpo de Rito.
func hand_position() -> Vector3:
	if _attachments.is_empty():
		return global_position
	return _attachments[_current].global_position


## El pilum desaparece de la mano mientras vuela y vuelve cuando el combate lo deja listo.
## El resto de armas no usan esto: se dejan siempre a la vista.
func set_weapon_visible(visible: bool) -> void:
	_weapon_visible = visible
	if not _attachments.is_empty():
		_attachments[_current].visible = visible


func is_weapon_visible() -> bool:
	return _weapon_visible
