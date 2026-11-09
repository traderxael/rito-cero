extends Node

## Herramienta de verificación: arranca el mundo, coloca a Rito a cierta distancia del
## punto de interés "Coliseo" y lo encara, para comprobarlo en una captura. No sale:
## se queda corriendo para que la captura del editor muestre el resultado.


func _ready() -> void:
	var main: Node = $Main
	await get_tree().process_frame
	await get_tree().process_frame
	for i in 60:
		await get_tree().process_frame

	var target := Vector3.ZERO
	var found := false
	for entry in main.get_node("Structures").get("points_of_interest"):
		if entry["name"] == "Coliseo":
			target = entry["position"] - Vector3(0, 22.0, 0)
			found = true
	if not found:
		print("COLOSSEUM_VIEW no encontrado; POIs=", main.get_node("Structures").get("points_of_interest"))
		return

	# Cámara oblicua que encuadra la fachada del coliseo.
	var angle := 2.1
	var cam := Camera3D.new()
	cam.name = "ColosseumCamera"
	cam.fov = 55.0
	add_child(cam)
	cam.global_position = target + Vector3(cos(angle) * 118.0, 32.0, sin(angle) * 118.0)
	cam.look_at(target - Vector3(0.0, 6.0, 0.0), Vector3.UP)
	cam.make_current()

	print("COLOSSEUM_VIEW target=", target, " cam=", cam.global_position)