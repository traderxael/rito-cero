extends Area3D

## Enciende las luces de la cueva solo mientras el jugador esta dentro. En el renderer
## de Compatibility cada luz omni es ALU por pixel sobre el terreno, asi que mantenerlas
## apagadas fuera es la diferencia entre pagar y no pagar el coste.

var _lights: Array[OmniLight3D] = []


func _ready() -> void:
	_lights = _find_lights(get_parent())
	for light in _lights:
		light.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if _is_player(body):
		_set_lights(true)


func _on_body_exited(body: Node3D) -> void:
	if _is_player(body):
		_set_lights(false)


## Solo Rito (capa 2) enciende las luces: el Praetorian de la cueva tambien es un
## CharacterBody3D, y con la puerta abierta la cueva se iluminaria sola.
func _is_player(body: Node3D) -> bool:
	return body is CharacterBody3D and body.collision_layer == 2


func _set_lights(enabled: bool) -> void:
	for light in _lights:
		light.visible = enabled


func _find_lights(node: Node) -> Array[OmniLight3D]:
	var found: Array[OmniLight3D] = []
	if node is OmniLight3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_lights(child))
	return found
