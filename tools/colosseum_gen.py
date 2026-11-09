import bpy, bmesh, math, sys
from mathutils import Vector

argv = sys.argv
out = argv[argv.index('--') + 1] if '--' in argv else 'colosseum.glb'

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

A, B = 48.0, 40.0
T = 5.0
LEVELS = 3
LH = 9.0
ATTIC_H = 6.0
TOTAL = LEVELS * LH + ATTIC_H
BAYS = 48
ARCH_W = 4.2
ARCH_STRAIGHT = 4.6
ARC_R = ARCH_W / 2.0
CORNICE = 1.2

def cyl(name, sx, sy, h, z=0.0, verts=160):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=1.0, depth=1.0, location=(0.0, 0.0, z + h / 2.0))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (sx, sy, h)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=True)
    return ob

def boolean_diff(target, cutter):
    bpy.context.view_layer.objects.active = target
    m = target.modifiers.new('bool', 'BOOLEAN')
    m.operation = 'DIFFERENCE'
    m.object = cutter
    bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

def ring(name, a_o, b_o, a_i, b_i, h, z):
    o = cyl(name + '_o', a_o, b_o, h, z)
    i = cyl(name + '_i', a_i, b_i, h, z)
    boolean_diff(o, i)
    return o

stone_objs = []
facade = ring('Facade', A, B, A - T, B - T, TOTAL, 0.0)
stone_objs.append(facade)
skirt = ring('Skirt', A, B, A - T, B - T, 16.0, -14.0)
stone_objs.append(skirt)

def make_gate():
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= ARCH_W
        v.co.y *= T * 2.0
        v.co.z *= ARCH_STRAIGHT
        v.co.z += ARCH_STRAIGHT / 2.0
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=16, radius1=ARC_R, radius2=ARC_R, depth=T * 2.0)
    for v in res['verts']:
        x, y, z = v.co
        v.co = Vector((x, -z, y))
        v.co.z += ARCH_STRAIGHT
    me = bpy.data.meshes.new('gate')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('gate', me)
    bpy.context.collection.objects.link(ob)
    return ob

def make_window():
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= 2.0
        v.co.y *= T * 2.0
        v.co.z *= 2.6
        v.co.z += 1.3
    me = bpy.data.meshes.new('window')
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new('window', me)
    bpy.context.collection.objects.link(ob)
    return ob

cutters = []
for lvl in range(LEVELS):
    z0 = lvl * LH
    for i in range(BAYS):
        t = (i + 0.5) / BAYS * (2.0 * math.pi)
        g = make_gate()
        g.rotation_euler = (0.0, 0.0, t + math.pi / 2.0)
        g.location = ((A - T / 2.0) * math.cos(t), (B - T / 2.0) * math.sin(t), z0)
        cutters.append(g)
for i in range(BAYS):
    t = (i + 0.5) / BAYS * (2.0 * math.pi)
    w = make_window()
    w.rotation_euler = (0.0, 0.0, t + math.pi / 2.0)
    w.location = ((A - T / 2.0) * math.cos(t), (B - T / 2.0) * math.sin(t), LEVELS * LH + 2.0)
    cutters.append(w)

bpy.ops.object.select_all(action='DESELECT')
for c in cutters:
    c.select_set(True)
bpy.context.view_layer.objects.active = cutters[0]
bpy.ops.object.join()
cutter = bpy.context.active_object
boolean_diff(facade, cutter)

for i in range(BAYS):
    t = i / BAYS * (2.0 * math.pi)
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    ob = bpy.context.active_object
    ob.scale = (1.4, T + 2.0, TOTAL)
    ob.rotation_euler = (0.0, 0.0, t + math.pi / 2.0)
    ob.location = ((A - T / 2.0) * math.cos(t), (B - T / 2.0) * math.sin(t), TOTAL / 2.0)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.name = 'pilaster'
    stone_objs.append(ob)

for lvl in range(1, LEVELS + 1):
    z = lvl * LH - CORNICE
    stone_objs.append(ring('Cornice%d' % lvl, A + 1.6, B + 1.6, A - T, B - T, CORNICE, z))
stone_objs.append(ring('TopCornice', A + 1.6, B + 1.6, A - T, B - T, CORNICE, TOTAL - CORNICE))

SEAT_TOP_A = A - T - 1.0
SEAT_TOP_B = B - T - 1.0
ARENA_A, ARENA_B = 18.0, 15.0
SEAT_H = 17.0
bpy.ops.mesh.primitive_cone_add(vertices=64, radius1=ARENA_A, radius2=SEAT_TOP_A, depth=SEAT_H, location=(0.0, 0.0, SEAT_H / 2.0))
seat = bpy.context.active_object
seat.name = 'Seating'
seat.scale = (1.0, SEAT_TOP_B / SEAT_TOP_A, 1.0)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

arena = cyl('Arena', ARENA_A, ARENA_B, 0.6, 0.0, verts=64)

def mat(name, color, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = color
    b.inputs['Roughness'].default_value = rough
    return m

stone = mat('Travertine', (0.72, 0.66, 0.53, 1.0), 0.95)
sand = mat('ArenaSand', (0.70, 0.58, 0.40, 1.0), 1.0)

bpy.ops.object.select_all(action='DESELECT')
for ob in stone_objs:
    ob.select_set(True)
bpy.context.view_layer.objects.active = stone_objs[0]
bpy.ops.object.join()
body = bpy.context.active_object
body.name = 'Colosseum'
body.data.materials.clear()
body.data.materials.append(stone)

seat.data.materials.clear()
seat.data.materials.append(stone)
arena.data.materials.clear()
arena.data.materials.append(sand)

bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_apply=True)
print('EXPORTED ' + out)
