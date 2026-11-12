class_name Pickup
extends Area3D

## Botin suelto en el mundo: un cubo brillante que flota y gira sobre el cadaver. Al
## entrar Rito (capa 2) se lo entrega al nodo Progression y desaparece. Sin luces ni
## sombras: material unshaded con emision, como el resto del HUD 3D.

signal collected(id: String, amount: int)

const BOB_SPEED := 2.4
const BOB_HEIGHT := 0.10
const SPIN_SPEED := 1.8
const PICKUP_RADIUS := 0.6

var item_id := ""
var amount := 1
var quest := false
var _t := 0.0
var _mesh: MeshInstance3D


## Llamar ANTES de add_child: _ready monta la malla y el color segun el id.
## Si quest es true, al recoger no se entrega a Progression: solo se emite
## collected, para que la mision de recoleccion lleve su propio contador.
func setup(p_id: String, p_amount: int, p_quest := false) -> void:
	item_id = p_id
	amount = p_amount
	quest = p_quest


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # solo Rito vive en la capa 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.30, 0.30, 0.30)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var color := _color_for(item_id)
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	box.material = material
	_mesh.mesh = box
	add_child(_mesh)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	if _mesh != null:
		_mesh.rotation.y += SPIN_SPEED * delta
		_mesh.position.y = 0.15 + sin(_t * BOB_SPEED) * BOB_HEIGHT


func _on_body_entered(_body: Node3D) -> void:
	if not quest:
		var prog := get_tree().get_first_node_in_group("progression")
		if prog != null:
			prog.call("apply_loot", {item_id: amount})
	collected.emit(item_id, amount)
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_local", "pickup", -10.0)
	queue_free()


func _color_for(id: String) -> Color:
	match id:
		"denarii":
			return Color(0.95, 0.80, 0.25)
		"panis":
			return Color(0.85, 0.45, 0.20)
		"aqua":
			return Color(0.35, 0.65, 0.95)
		"pizza":
			return Color(0.90, 0.60, 0.25)
		"gelatum":
			return Color(0.75, 0.85, 0.95)
		"sal":
			return Color(0.92, 0.92, 0.88)
		"suministro":
			return Color(0.95, 0.75, 0.30)
	return Color(0.9, 0.9, 0.9)
