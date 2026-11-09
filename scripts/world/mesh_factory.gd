extends RefCounted

const TRUNK := Color(0.35, 0.25, 0.17)
const OLIVE_LEAF := Color(0.40, 0.47, 0.27)
const OLIVE_LEAF_DARK := Color(0.28, 0.36, 0.19)
const CYPRESS_LEAF := Color(0.15, 0.27, 0.16)
const WHEAT_LOW := Color(0.44, 0.44, 0.21)
const WHEAT_HIGH := Color(0.90, 0.76, 0.35)
const MARBLE := Color(0.80, 0.78, 0.71)
const MARBLE_DIRTY := Color(0.63, 0.60, 0.53)
const ROMAN_SKIN := Color(0.72, 0.51, 0.34)
const ROMAN_TUNIC := Color(0.78, 0.70, 0.55)
const DOG_COAT := Color(0.26, 0.19, 0.13)
const DOG_COAT_LIGHT := Color(0.45, 0.32, 0.18)
const DOG_MUZZLE := Color(0.11, 0.10, 0.09)
const DOG_EYE := Color(0.86, 0.64, 0.20)
const CAVE_ROCK := Color(0.46, 0.43, 0.38)
const CAVE_DARK := Color(0.03, 0.03, 0.04)


## Boca de cueva: monticulo de peñascos con un arco de entrada y interior oscuro.
## El Tunnel.glb del pack no se puede trasplantar: sus rocas estan escaladas 5-11x
## y colocadas para el acantilado del demo, y en otro sitio quedan como un aro de
## rocas flotando. Esto se apoya en el suelo por construccion.
static func make_cave_mouth() -> ArrayMesh:
	var parts: Array = []
	var boulder := SphereMesh.new()
	boulder.radius = 1.0
	boulder.height = 1.0
	boulder.radial_segments = 7
	boulder.rings = 4
	var arrangement := [
		[Vector3(0, 2.6, -1.6), Vector3(4.2, 3.2, 4.0)],
		[Vector3(-3.4, 1.8, -0.4), Vector3(3.4, 2.4, 3.2)],
		[Vector3(3.5, 1.9, -0.3), Vector3(3.2, 2.3, 3.0)],
		[Vector3(0, 4.2, -3.4), Vector3(3.6, 2.0, 3.4)],
		[Vector3(-2.2, 3.8, -2.6), Vector3(2.4, 1.8, 2.2)],
		[Vector3(2.4, 3.7, -2.5), Vector3(2.2, 1.7, 2.0)],
	]
	for entry in arrangement:
		var position: Vector3 = entry[0]
		var scale: Vector3 = entry[1]
		parts.append({
			"mesh": boulder,
			"transform": Transform3D(Basis().scaled(scale), position),
			"color": CAVE_ROCK,
			"top_color": CAVE_ROCK.lerp(Color(1, 1, 1), 0.18),
		})

	var lintel := BoxMesh.new()
	lintel.size = Vector3(3.4, 0.5, 1.2)
	parts.append({
		"mesh": lintel,
		"transform": Transform3D(Basis(), Vector3(0, 3.15, 1.5)),
		"color": MARBLE_DIRTY,
	})

	# El hueco: un cilindro horizontal casi negro. Al no tener emision, el ojo lo lee
	# como entrada profunda aunque detras no haya nada.
	var hole := CylinderMesh.new()
	hole.top_radius = 1.25
	hole.bottom_radius = 1.25
	hole.height = 4.2
	hole.radial_segments = 9
	hole.rings = 1
	var hole_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({
		"mesh": hole,
		"transform": Transform3D(hole_basis, Vector3(0, 1.35, -0.6)),
		"color": CAVE_DARK,
	})
	return _merge(parts)


## Pórtico romano de cuatro columnas con basa y arquitrabe. Todas las piezas se
## fusionan en una sola malla: un draw call para el monumento entero.
static func make_portico() -> ArrayMesh:
	var parts: Array = []
	var base := BoxMesh.new()
	base.size = Vector3(7.2, 0.3, 2.6)
	parts.append({"mesh": base, "transform": Transform3D(Basis(), Vector3(0, 0.15, 0)), "color": MARBLE_DIRTY})

	for i in 4:
		var column := CylinderMesh.new()
		column.top_radius = 0.28
		column.bottom_radius = 0.34
		column.height = 3.1
		column.radial_segments = 8
		column.rings = 1
		var x := -2.7 + 1.8 * float(i)
		parts.append({
			"mesh": column,
			"transform": Transform3D(Basis(), Vector3(x, 1.85, 0)),
			"color": MARBLE,
			"top_color": Color(0.86, 0.84, 0.77),
		})

	var entablature := BoxMesh.new()
	entablature.size = Vector3(7.4, 0.45, 0.9)
	parts.append({
		"mesh": entablature,
		"transform": Transform3D(Basis(), Vector3(0, 3.6, 0)),
		"color": MARBLE,
		"top_color": Color(0.86, 0.84, 0.77),
	})
	return _merge(parts)


## Columna rota: dos tambores y un fragmento en pie.
static func make_broken_column() -> ArrayMesh:
	var parts: Array = []
	for i in 2:
		var drum := CylinderMesh.new()
		drum.top_radius = 0.3
		drum.bottom_radius = 0.32
		drum.height = 0.75
		drum.radial_segments = 8
		drum.rings = 1
		parts.append({
			"mesh": drum,
			"transform": Transform3D(Basis(), Vector3(0, 0.38 + 0.76 * float(i), 0)),
			"color": MARBLE,
			"top_color": Color(0.86, 0.84, 0.77),
		})
	var stump := CylinderMesh.new()
	stump.top_radius = 0.28
	stump.bottom_radius = 0.3
	stump.height = 0.5
	stump.radial_segments = 8
	stump.rings = 1
	parts.append({
		"mesh": stump,
		"transform": Transform3D(Basis(Vector3.FORWARD, 0.2), Vector3(0.15, 2.02, 0.1)),
		"color": MARBLE,
		"top_color": Color(0.86, 0.84, 0.77),
	})
	return _merge(parts)


## Muro de mampostería con huecos: un muro de piedra seco.
static func make_wall() -> ArrayMesh:
	var parts: Array = []
	var sizes := [
		Vector3(2.4, 1.1, 0.55),
		Vector3(2.0, 1.3, 0.55),
		Vector3(1.7, 0.9, 0.55),
	]
	var heights := [0.55, 1.75, 2.75]
	for i in sizes.size():
		var block := BoxMesh.new()
		block.size = sizes[i]
		parts.append({
			"mesh": block,
			"transform": Transform3D(Basis(), Vector3(-3.2 + 2.4 * float(i), heights[i], 0)),
			"color": MARBLE_DIRTY,
			"top_color": Color(0.74, 0.71, 0.63),
		})
	return _merge(parts)


## Coliseo romano: fachada ovalada de tres niveles de arcos, gradas y arena.
## Se fusiona en una sola malla (un draw call), igual que el resto de monumentos.
## La base incluye un faldón que baja 20 m por debajo del suelo, de modo que en una
## ladera la union con el terreno queda tapada en vez de dejar el coliseo flotando.
static func make_colosseum() -> ArrayMesh:
	var parts: Array = []

	var bays := 40
	var levels := 3
	var orx := 48.0
	var ory := 40.0
	var wall_t := 4.0
	var level_h := 9.0
	var total_h := float(levels) * level_h
	var pillar_w := 1.4
	var lintel_h := 1.4
	var skirt_top := 2.0
	var skirt_bottom := -20.0
	var skirt_h := skirt_top - skirt_bottom
	var seat_top_z := 18.0
	var arena_rx := 18.0
	var arena_ry := 15.0

	var mid_rx := orx - wall_t * 0.5
	var mid_ry := ory - wall_t * 0.5
	var arc := TAU * (mid_rx + mid_ry) * 0.5 / float(bays)
	var pillar_h := level_h - lintel_h
	var stone_hi := Color(0.86, 0.84, 0.77)

	var box := BoxMesh.new()
	box.size = Vector3.ONE

	for i in range(bays):
		var t := (float(i) + 0.5) / float(bays) * TAU
		var radial := Vector3(ory * cos(t), 0.0, orx * sin(t)).normalized()
		var tangent := Vector3(-orx * sin(t), 0.0, ory * cos(t)).normalized()
		var frame := Basis(radial, Vector3.UP, tangent)
		var cx := mid_rx * cos(t)
		var cz := mid_ry * sin(t)

		# Faldón de base continuo: tapa el hueco entre el coliseo y el suelo.
		parts.append({
			"mesh": box,
			"transform": Transform3D(frame * Basis.from_scale(Vector3(wall_t, skirt_h, arc)),
				Vector3(cx, (skirt_top + skirt_bottom) * 0.5, cz)),
			"color": MARBLE_DIRTY,
			"top_color": MARBLE,
		})

		for lvl in range(levels):
			var y0 := float(lvl) * level_h
			# Pilar: la separación entre pilares se lee como arco.
			parts.append({
				"mesh": box,
				"transform": Transform3D(frame * Basis.from_scale(Vector3(wall_t, pillar_h, pillar_w)),
					Vector3(cx, y0 + pillar_h * 0.5, cz)),
				"color": MARBLE,
				"top_color": stone_hi,
			})
			# Arquitrabe continuo en la parte alta de cada nivel.
			parts.append({
				"mesh": box,
				"transform": Transform3D(frame * Basis.from_scale(Vector3(wall_t, lintel_h, arc)),
					Vector3(cx, y0 + pillar_h + lintel_h * 0.5, cz)),
				"color": MARBLE_DIRTY,
				"top_color": MARBLE,
			})

		# Cornisa superior.
		parts.append({
			"mesh": box,
			"transform": Transform3D(frame * Basis.from_scale(Vector3(wall_t + 2.5, 2.0, arc)),
				Vector3(cx, total_h + 1.0, cz)),
			"color": MARBLE,
			"top_color": stone_hi,
		})

	# Gradas: cono invertido que sube hacia afuera, visto desde dentro de la arena.
	var seat_top_rx := orx - wall_t - 1.0
	var seating := CylinderMesh.new()
	seating.top_radius = 1.0
	seating.bottom_radius = arena_rx / seat_top_rx
	seating.height = seat_top_z
	seating.radial_segments = 40
	seating.rings = 0
	parts.append({
		"mesh": seating,
		"transform": Transform3D(Basis().scaled(Vector3(seat_top_rx, 1.0, seat_top_rx * (ory / orx))),
			Vector3(0, seat_top_z * 0.5, 0)),
		"color": Color(0.62, 0.59, 0.50),
		"top_color": Color(0.70, 0.66, 0.56),
	})

	# Arena de arena.
	var arena := CylinderMesh.new()
	arena.top_radius = 1.0
	arena.bottom_radius = 1.0
	arena.height = 0.6
	arena.radial_segments = 40
	arena.rings = 0
	parts.append({
		"mesh": arena,
		"transform": Transform3D(Basis().scaled(Vector3(arena_rx, 1.0, arena_ry)),
			Vector3(0, 0.3, 0)),
		"color": Color(0.72, 0.62, 0.42),
	})

	return _merge(parts)


## NPC romano: cuerpo simple sin esqueleto. Cuatro de estos cuestan menos de 5.000
## triangulos, frente a los mas de 15.000 que costaria el maniqui con skinning.
static func make_roman_npc() -> ArrayMesh:
	var parts: Array = []
	var tunic := CylinderMesh.new()
	tunic.top_radius = 0.17
	tunic.bottom_radius = 0.30
	tunic.height = 0.95
	tunic.radial_segments = 7
	tunic.rings = 1
	parts.append({
		"mesh": tunic,
		"transform": Transform3D(Basis(), Vector3(0, 0.48, 0)),
		"color": ROMAN_TUNIC,
		"top_color": ROMAN_TUNIC.lerp(Color(1, 1, 1), 0.15),
	})

	var head := SphereMesh.new()
	head.radius = 0.115
	head.height = 0.25
	head.radial_segments = 7
	head.rings = 4
	parts.append({
		"mesh": head,
		"transform": Transform3D(Basis(), Vector3(0, 1.62, 0)),
		"color": ROMAN_SKIN,
	})

	for side in [-1.0, 1.0]:
		var arm := CylinderMesh.new()
		arm.top_radius = 0.055
		arm.bottom_radius = 0.065
		arm.height = 0.62
		arm.radial_segments = 5
		arm.rings = 1
		parts.append({
			"mesh": arm,
			"transform": Transform3D(Basis(Vector3.FORWARD, 0.0), Vector3(0.22 * side, 1.18, 0)),
			"color": ROMAN_SKIN,
		})
	return _merge(parts)


## Piezas del moloso, separadas por hueso. Cada pieza se dibuja en el espacio de SU
## propio hueso: el rig la cuelga del BoneAttachment3D de ese hueso y solo tiene que
## restar el punto de anclaje. Las cuatro patas comparten las tres suyas, asi que son
## tres mallas y doce instancias.
static func make_dog_torso() -> ArrayMesh:
	var parts: Array = []
	var torso := BoxMesh.new()
	torso.size = Vector3(0.34, 0.32, 0.72)
	parts.append({
		"mesh": torso,
		"transform": Transform3D(Basis(), Vector3(0, 0.02, 0)),
		"color": DOG_COAT,
		"top_color": DOG_COAT_LIGHT,
	})
	return _merge(parts)


static func make_dog_chest() -> ArrayMesh:
	var parts: Array = []
	var chest := BoxMesh.new()
	chest.size = Vector3(0.38, 0.36, 0.30)
	parts.append({
		"mesh": chest,
		"transform": Transform3D(Basis(), Vector3.ZERO),
		"color": DOG_COAT_LIGHT,
	})
	return _merge(parts)


static func make_dog_neck() -> ArrayMesh:
	var parts: Array = []
	var neck := BoxMesh.new()
	neck.size = Vector3(0.22, 0.22, 0.26)
	parts.append({
		"mesh": neck,
		"transform": Transform3D(Basis(), Vector3.ZERO),
		"color": DOG_COAT,
	})
	return _merge(parts)


## Cabeza con hocico y ojos. El hocico va hacia delante y abajo, y los ojos a los
## lados: el perro mira a +Z, que es su frente.
static func make_dog_head() -> ArrayMesh:
	var parts: Array = []

	var head := BoxMesh.new()
	head.size = Vector3(0.21, 0.21, 0.24)
	parts.append({
		"mesh": head,
		"transform": Transform3D(Basis(), Vector3.ZERO),
		"color": DOG_COAT,
		"top_color": DOG_COAT_LIGHT,
	})

	var muzzle := BoxMesh.new()
	muzzle.size = Vector3(0.13, 0.12, 0.20)
	parts.append({
		"mesh": muzzle,
		"transform": Transform3D(Basis(), Vector3(0, -0.05, 0.18)),
		"color": DOG_MUZZLE,
	})

	for side in [-1.0, 1.0]:
		var eye := BoxMesh.new()
		eye.size = Vector3(0.04, 0.04, 0.02)
		parts.append({
			"mesh": eye,
			"transform": Transform3D(Basis(), Vector3(0.07 * side, 0.04, 0.11)),
			"color": DOG_EYE,
		})
	return _merge(parts)


## Oreja caida del moloso: cuelgan, no se levantan. El giro lateral lo pone el rig, que
## la monta en el hueso de su lado.
static func make_dog_ear() -> ArrayMesh:
	var parts: Array = []
	var ear := BoxMesh.new()
	ear.size = Vector3(0.06, 0.16, 0.10)
	parts.append({
		"mesh": ear,
		"transform": Transform3D(Basis(), Vector3.ZERO),
		"color": DOG_MUZZLE,
	})
	return _merge(parts)


## Cola: cilindro inclinado hacia atras y arriba.
static func make_dog_tail() -> ArrayMesh:
	var parts: Array = []
	var tail := CylinderMesh.new()
	tail.top_radius = 0.03
	tail.bottom_radius = 0.045
	tail.height = 0.30
	tail.radial_segments = 5
	tail.rings = 1
	parts.append({
		"mesh": tail,
		"transform": Transform3D(Basis(Vector3.RIGHT, -PI * 0.35), Vector3.ZERO),
		"color": DOG_COAT,
	})
	return _merge(parts)


## Muslo del moloso: cuelga del hueso de la cadera hacia abajo.
static func make_dog_leg_upper() -> ArrayMesh:
	var parts: Array = []
	var upper := BoxMesh.new()
	upper.size = Vector3(0.10, 0.26, 0.11)
	parts.append({
		"mesh": upper,
		"transform": Transform3D(Basis(), Vector3(0, -0.13, 0)),
		"color": DOG_COAT,
	})
	return _merge(parts)


## Espinilla: va de la rodilla a la zarpa.
static func make_dog_leg_lower() -> ArrayMesh:
	var parts: Array = []
	var lower := BoxMesh.new()
	lower.size = Vector3(0.085, 0.20, 0.09)
	parts.append({
		"mesh": lower,
		"transform": Transform3D(Basis(), Vector3(0, -0.10, 0.02)),
		"color": DOG_COAT_LIGHT,
	})
	return _merge(parts)


## Zarpa del moloso.
static func make_dog_leg_paw() -> ArrayMesh:
	var parts: Array = []
	var paw := BoxMesh.new()
	paw.size = Vector3(0.10, 0.06, 0.14)
	parts.append({
		"mesh": paw,
		"transform": Transform3D(Basis(), Vector3(0, 0, 0.03)),
		"color": DOG_MUZZLE,
	})
	return _merge(parts)


static func make_olive() -> ArrayMesh:
	var parts: Array = []
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.13
	trunk.bottom_radius = 0.19
	trunk.height = 1.45
	trunk.radial_segments = 7
	trunk.rings = 1
	parts.append({
		"mesh": trunk,
		"transform": Transform3D(Basis(), Vector3(0, 0.72, 0)),
		"color": TRUNK,
	})

	var canopy := SphereMesh.new()
	canopy.radius = 0.5
	canopy.height = 1.0
	canopy.radial_segments = 6
	canopy.rings = 3
	parts.append({
		"mesh": canopy,
		"transform": Transform3D(Basis().scaled(Vector3(1.35, 0.95, 1.35)), Vector3(0, 1.95, 0)),
		"color": OLIVE_LEAF,
		"top_color": Color(0.46, 0.53, 0.31),
	})
	parts.append({
		"mesh": canopy,
		"transform": Transform3D(Basis().scaled(Vector3(0.85, 0.65, 0.85)), Vector3(0.38, 1.62, 0.22)),
		"color": OLIVE_LEAF_DARK,
	})
	parts.append({
		"mesh": canopy,
		"transform": Transform3D(Basis().scaled(Vector3(0.75, 0.6, 0.75)), Vector3(-0.34, 1.68, -0.18)),
		"color": OLIVE_LEAF_DARK,
	})
	return _merge(parts)


static func make_cypress() -> ArrayMesh:
	var parts: Array = []
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.10
	trunk.bottom_radius = 0.14
	trunk.height = 0.9
	trunk.radial_segments = 6
	trunk.rings = 1
	parts.append({
		"mesh": trunk,
		"transform": Transform3D(Basis(), Vector3(0, 0.45, 0)),
		"color": TRUNK,
	})

	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.52
	cone.height = 3.6
	cone.radial_segments = 8
	cone.rings = 2
	parts.append({
		"mesh": cone,
		"transform": Transform3D(Basis(), Vector3(0, 2.5, 0)),
		"color": CYPRESS_LEAF,
		"top_color": Color(0.22, 0.36, 0.20),
	})
	return _merge(parts)


static func make_wheat_tuft() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var angle := TAU * i / 3.0 + 0.4
		var side := Vector3(cos(angle), 0.0, sin(angle))
		_add_blade(surface_tool, side, 0.085, 0.52 + 0.06 * float(i))
	surface_tool.generate_normals()
	return surface_tool.commit()


static func _add_blade(surface_tool: SurfaceTool, side: Vector3, half_width: float, height: float) -> void:
	var left := -side * half_width
	var right := side * half_width
	var tip := Vector3(0.0, height, 0.0)
	surface_tool.set_color(WHEAT_LOW)
	surface_tool.add_vertex(left)
	surface_tool.set_color(WHEAT_LOW)
	surface_tool.add_vertex(right)
	surface_tool.set_color(WHEAT_HIGH)
	surface_tool.add_vertex(tip)


static func _merge(parts: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for part: Dictionary in parts:
		var mesh: Mesh = part["mesh"]
		var xform: Transform3D = part["transform"]
		var base_color: Color = part["color"]
		var top_color: Color = part.get("top_color", base_color)
		var part_min := INF
		var part_max := -INF
		var part_vertices := PackedVector3Array()

		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var offset := vertices.size()
			for vertex in source_vertices:
				var point := xform * vertex
				part_vertices.append(point)
				vertices.append(point)
				part_min = minf(part_min, point.y)
				part_max = maxf(part_max, point.y)
			for index in source_indices:
				indices.append(index + offset)

		var span := maxf(part_max - part_min, 0.001)
		for point in part_vertices:
			var t := clampf((point.y - part_min) / span, 0.0, 1.0)
			colors.append(base_color.lerp(top_color, t))

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in vertices.size():
		surface_tool.set_color(colors[i])
		surface_tool.add_vertex(vertices[i])
	for index in indices:
		surface_tool.add_index(index)
	surface_tool.generate_normals()
	return surface_tool.commit()
