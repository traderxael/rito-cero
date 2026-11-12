class_name BruteNpc
extends "res://scripts/npc/hostile_npc.gd"

## Bruto con escudo: lento, duro y con un escudo que bloquea el dano melee de
## frente (lo reduce a la cuarta parte y no lo aturde). Por la espalda entra
## completo y el critico x2 sigue; el pilum ignora el escudo porque llama
## directo al Combatant. Su contramedida es esquivar y entrar por la espalda.

const BRUTE_HEALTH := 140.0
const BRUTE_DAMAGE := 22.0
const BRUTE_SPEED := 2.6
const BRUTE_SCALE := 1.15

## Ataque pesado telegrafiado: el volumen abre 0,5 s despues de empezar.
const BRUTE_WINDUP := 0.5
const ATTACK_COOLDOWN_B := 2.2

## El bloqueo frontal reduce el dano a la cuarta parte.
const BLOCK_REDUCTION := 0.25
const BLOCK_DOT := 0.15
## Ventana en la que un golpe recien bloqueado impide el aturdimiento.
const BLOCK_STAGGER_SHIELD := 0.4

var _blocked_at := -100.0
var _shield_material: StandardMaterial3D


func setup_brute(data, center: Vector3, angle: float, target: Node3D = null, player: Node3D = null) -> void:
	max_health = BRUTE_HEALTH
	attack_damage = BRUTE_DAMAGE
	chase_speed = BRUTE_SPEED
	body_scale = BRUTE_SCALE
	super.setup(data, center, angle, target, player)
	_attach_shield()
	_play("Sword_Idle")


## El escudo cuelga del antebrazo izquierdo, como el gladius de la derecha.
func _attach_shield() -> void:
	var skeleton := _find(_model, "Skeleton3D")
	if skeleton == null:
		return
	_shield_material = StandardMaterial3D.new()
	_shield_material.vertex_color_use_as_albedo = true
	_shield_material.roughness = 0.6
	_shield_material.metallic = 0.2
	_shield_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "DEF-hand.L"
	skeleton.add_child(attachment)
	var instance := MeshInstance3D.new()
	instance.mesh = WeaponScript.make_shield()
	instance.material_override = _shield_material
	attachment.add_child(instance)


## Indireccion de AttackVolume: si el golpe viene de frente, lo bloquea.
func receive_attack(amount: float, source: Node3D) -> bool:
	if not _is_frontal(source):
		return false
	_blocked_at = _now()
	_combatant.take_damage(amount * BLOCK_REDUCTION, source.global_position)
	_block_feedback()
	return true


## Frente del modelo contra direccion al atacante: producto escalar >= 0,15.
func _is_frontal(source: Node3D) -> bool:
	if _model == null or source == null:
		return false
	var forward := _model.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return false
	var to_source := source.global_position - global_position
	to_source.y = 0.0
	if to_source.length() < 0.01:
		return false
	return forward.normalized().dot(to_source.normalized()) >= BLOCK_DOT


## Sonido metalico y fogonazo del escudo: el bloqueo se lee aunque el numero de
## dano siga mostrando el tajo completo.
func _block_feedback() -> void:
	var sfx := _sfx()
	if sfx != null:
		sfx.call("play", "block", global_position, -6.0)
	if _shield_material != null:
		_shield_material.albedo_color = Color(2.0, 2.0, 2.0)
		create_tween().tween_property(_shield_material, "albedo_color", Color(1, 1, 1), 0.2)


## Un golpe recien bloqueado no lo aturde (ni el del combo ni el critico).
func stagger(seconds: float) -> void:
	if _now() - _blocked_at < BLOCK_STAGGER_SHIELD:
		return
	super.stagger(seconds)


## El golpe bloqueado no entra en STUN: solo el fogonazo del bloqueo.
func _on_damaged(_amount: float, _source_position: Vector3) -> void:
	if _now() - _blocked_at < 0.1:
		return
	super._on_damaged(_amount, _source_position)


## Ataque pesado con windup: se lee venir.
func _try_attack() -> void:
	if _now() < _attack_ready:
		return
	_attack_ready = _now() + ATTACK_COOLDOWN_B
	_play("Sword_Attack")
	var clip_length := 0.5
	if _anim != null and _anim.has_animation("Sword_Attack"):
		clip_length = _anim.get_animation("Sword_Attack").length
	_swing_until = _now() + clip_length
	_volume.begin_swing(attack_damage, self, 0.25, 0.55, clip_length, BRUTE_WINDUP)
	var sfx := _sfx()
	if sfx != null:
		sfx.call("play", "swing", global_position, -12.0)


## Pose de reposo con el escudo en alto.
func _play(anim_name: String, speed: float = -1.0) -> void:
	if anim_name == "Idle":
		anim_name = "Sword_Idle"
	super._play(anim_name, speed)
