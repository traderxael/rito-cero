extends Node

const DevVariantsScript := preload("res://scripts/dev/variants.gd")

## Banco de pruebas determinista. Mide FPS, percentil 5, draw calls, triangulos y
## tiempo de CPU con la camara y la pose fijas, para que dos variantes sean
## comparables. La decision de rendimiento se toma con estos numeros, no a ojo.
##
## La ultima pose mide el caso de riesgo: el corpse en el suelo. Son 17 cuerpos fisicos
## moviendo el esqueleto a la vez, y es la escena mas pesada del juego.

const POSES := [
	{"yaw": 0.0, "pitch": -0.24},
	{"yaw": 2.0944, "pitch": -0.32},
	{"yaw": 4.1888, "pitch": -0.18},
]
const SETTLE_FRAMES := 40
const SAMPLE_FRAMES := 120


func _ready() -> void:
	var main: Node = $Main
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node3D = main.get_node("Player")

	for i in 90:
		await get_tree().process_frame

	var variant: int = DevVariantsScript.current()
	var yaw: Node3D = player.get("camera_yaw")
	var pitch: Node3D = player.get("camera_pitch")
	var pose_averages: Array[float] = []

	for index in POSES.size():
		yaw.rotation.y = POSES[index]["yaw"]
		pitch.rotation.x = POSES[index]["pitch"]
		for i in SETTLE_FRAMES:
			await get_tree().process_frame
		pose_averages.append(await _measure(player, index))

	# El corpse: 17 cuerpos rigidos con el esqueleto enganchado, moviendose en el suelo.
	var player_combatant: Combatant = player.get_node_or_null("Combatant")
	if player_combatant != null:
		player_combatant.take_damage(999.0, player.global_position + Vector3(0, 0, 2.0))
		await get_tree().create_timer(2.2).timeout
		yaw.rotation.y = 0.0
		pitch.rotation.x = -0.24
		for i in SETTLE_FRAMES:
			await get_tree().process_frame
		pose_averages.append(await _measure(player, "ragdoll"))

	pose_averages.sort()
	print("BENCH-SUMMARY v=%s median_avg=%.1f" % [
		DevVariantsScript.label(variant), pose_averages[pose_averages.size() / 2]])
	get_tree().quit()


## Una pose medida: FPS medio, percentil 5, peor fotograma, draw calls y triangulos.
func _measure(player: Node3D, label) -> float:
	var frame_fps: Array[float] = []
	var total_ms := 0.0
	var draws := 0
	var triangles := 0
	var cpu_ms := 0.0
	var worst_ms := 0.0
	var worst_index := 0
	var last := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var elapsed_ms := float(now - last) / 1000.0
		last = now
		total_ms += elapsed_ms
		if elapsed_ms > worst_ms:
			worst_ms = elapsed_ms
			worst_index = i
		frame_fps.append(1000.0 / maxf(elapsed_ms, 0.01))
		draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		triangles = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		cpu_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0

	var average := SAMPLE_FRAMES * 1000.0 / maxf(total_ms, 0.01)
	frame_fps.sort()
	var p5 := frame_fps[int(frame_fps.size() * 0.05)]
	# worst@index distingue un calentamiento de arranque (frame 0) de un tartamudeo en
	# mitad de la pose, que es lo que de verdad se nota jugando.
	print("BENCH v=%s pose=%s avg=%.1f p5=%.1f worst=%.0fms@%d draws=%d tris=%d cpu_ms=%.2f" % [
		DevVariantsScript.label(DevVariantsScript.current()), label, average, p5, worst_ms, worst_index,
		draws, triangles, cpu_ms])
	return average
