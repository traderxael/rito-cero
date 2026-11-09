extends Control

## Minimapa generado una sola vez a partir del mapa de alturas del terreno: 256x256
## muestras (65.536 llamadas a get_height, unos milisegundos) en un area de 1000x1000 m
## centrada en el punto de aparicion. Nunca se regenera por frame.

const MAP_SIZE := 256
const EXTENT := 500.0
const DISPLAY_SIZE := 150

var _player: Node3D
var _center := Vector3.ZERO
var _arrow: Polygon2D
var _marker: Polygon2D
var _frame: ColorRect
## Posicion del objetivo de la mision (null si no hay mision activa). Se puede
## fijar antes de setup(): sin mapa dibujado el marcador solo espera a que el
## setup() cree el Polygon2D, y _process lo reposiciona cada frame.
var _objective: Variant = null


func setup(player: Node3D, terrain: Terrain3D, center: Vector3) -> void:
	_player = player
	_center = center
	custom_minimum_size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)
	size = Vector2(DISPLAY_SIZE, DISPLAY_SIZE)

	_frame = ColorRect.new()
	_frame.color = Color(0.06, 0.05, 0.04, 0.55)
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.offset_left = 4
	picture.offset_top = 4
	picture.offset_right = -4
	picture.offset_bottom = -4
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = _build_texture(terrain)
	add_child(picture)

	_arrow = Polygon2D.new()
	_arrow.polygon = PackedVector2Array([Vector2(0, -7), Vector2(5, 6), Vector2(0, 3), Vector2(-5, 6)])
	_arrow.color = Color(0.98, 0.78, 0.25)
	add_child(_arrow)

	# Rombo dorado del objetivo, creado una sola vez encima de la flecha.
	_marker = Polygon2D.new()
	_marker.polygon = PackedVector2Array([Vector2(0, -6), Vector2(4, 0), Vector2(0, 6), Vector2(-4, 0)])
	_marker.color = Color(1.0, 0.84, 0.1)
	_marker.visible = false
	add_child(_marker)


## Fija el objetivo de la mision: la posicion del mundo que lleva el rombo
## dorado. Sin setup() previo no hay rombo, pero el objetivo queda guardado.
func set_objective(position: Vector3) -> void:
	_objective = position
	if _marker != null:
		_marker.visible = true


## Apaga el objetivo: la mision se cerro y ya no hay rombo.
func clear_objective() -> void:
	_objective = null
	if _marker != null:
		_marker.visible = false


## Posicion del objetivo actual (null si no hay mision activa). Solo lectura.
func objective() -> Variant:
	return _objective


func _process(_delta: float) -> void:
	if _player != null and _arrow != null:
		var relative := _player.global_position - _center
		var x := clampf(relative.x / EXTENT, -1.0, 1.0)
		var z := clampf(relative.z / EXTENT, -1.0, 1.0)
		# position es relativo a la esquina superior izquierda del Control, no al centro:
		# sin el desplazamiento la flecha se cola en la esquina cuando estas en el centro.
		var half := DISPLAY_SIZE * 0.5 - 8.0
		_arrow.position = Vector2(half, half) + Vector2(x, z) * half
		var model: Node3D = _player.get("model")
		if model != null:
			# El mapa esta orientado con el norte (mundo -Z) arriba y el maniqui mira a +Z.
			_arrow.rotation = model.rotation.y + PI
	if _marker != null and _objective != null:
		# Misma formula que la flecha sobre la posicion del objetivo, restringida
		# al marco de 150 px aunque el objetivo caiga fuera del area del mapa.
		var meta: Vector3 = _objective
		var relative := meta - _center
		var half := DISPLAY_SIZE * 0.5 - 8.0
		var x := clampf(relative.x / EXTENT, -1.0, 1.0)
		var z := clampf(relative.z / EXTENT, -1.0, 1.0)
		_marker.position = Vector2(half, half) + Vector2(x, z) * half


func _build_texture(terrain: Terrain3D) -> ImageTexture:
	var data := terrain.get_data()
	var heights := PackedFloat32Array()
	heights.resize(MAP_SIZE * MAP_SIZE)
	var minimum := INF
	var maximum := -INF
	for z in MAP_SIZE:
		for x in MAP_SIZE:
			var world := _center + Vector3(
				(float(x) / float(MAP_SIZE) * 2.0 - 1.0) * EXTENT,
				0.0,
				(float(z) / float(MAP_SIZE) * 2.0 - 1.0) * EXTENT)
			var height: float = data.get_height(world)
			if is_nan(height):
				height = minimum if minimum < INF else 0.0
			heights[z * MAP_SIZE + x] = height
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)

	var span := maxf(maximum - minimum, 1.0)
	var image := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	for z in MAP_SIZE:
		for x in MAP_SIZE:
			var height := heights[z * MAP_SIZE + x]
			var t := clampf((height - minimum) / span, 0.0, 1.0)
			var color := Color(0.20, 0.32, 0.15).lerp(Color(0.78, 0.74, 0.55), t)
			if height <= minimum + span * 0.04:
				color = Color(0.13, 0.19, 0.24)
			# Sombreado por relieve: sin esto el mapa es una mancha uniforme, porque el
			# rango de alturas de toda la zona lo dominan las montanas del fondo.
			var shade := _hillshade(heights, x, z, span)
			color = color * (0.72 + shade * 0.56)
			image.set_pixel(x, z, color)
	return ImageTexture.create_from_image(image)


## Luz desde todas las direcciones: compara con los cuatro vecinos (N, S, E, O).
func _hillshade(heights: PackedFloat32Array, x: int, z: int, span: float) -> float:
	var north := heights[maxi(z - 1, 0) * MAP_SIZE + x]
	var south := heights[min(z + 1, MAP_SIZE - 1) * MAP_SIZE + x]
	var west := heights[z * MAP_SIZE + maxi(x - 1, 0)]
	var east := heights[z * MAP_SIZE + min(x + 1, MAP_SIZE - 1)]
	var current := heights[z * MAP_SIZE + x]
	var slope := (north + south + west + east - 4.0 * current) / span
	return clampf(0.5 + slope * 11.0, 0.0, 1.0)
