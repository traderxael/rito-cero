import bpy, bmesh, math
from mathutils import Vector

# Clean up
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

# ---- Armature (bones) ----
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.object.armature_add(enter_edit_mode=True, location=(0,0,0))
arm = bpy.context.active_object
arm.name = "SlaveArmature"
arm.data.name = "SlaveArmature"

# Root bone
bpy.ops bone.select_all(action='SELECT')
bpy.ops bone.delete()
root = arm.data.edit_bones.new(name="Root")
root.head = Vector((0,0,0))
root.tail = Vector((0,0,1))
root.roll = 0

# Spine
spine = arm.data.edit_bones.new(name="Spine")
spine.parent = root
spine.head = Vector((0,0,1))
spine.tail = Vector((0,0,3))
spine.roll = 0

# Head
head = arm.data.edit_bones.new(name="Head")
head.parent = spine
head.head = Vector((0,0,4))
head.tail = Vector((0,0,5))
head.roll = 0

# Arm bones
for side in ["L", "R"]:
    # Upper arm
    ua = arm.data.edit_bones.new(name=f"UpperArm_{side}")
    ua.parent = spine if side == "L" else spine
    ua.head = Vector((-0.5 if side == "L" else 0.5, 0, 2.5))
    ua.tail = Vector((-0.5 if side == "L" else 0.5, 0, 3.5))
    ua.roll = 0
    
    # Lower arm
    la = arm.data.edit_bones.new(name=f"LowerArm_{side}")
    la.parent = ua
    la.head = Vector((-0.5 if side == "L" else 0.5, 0, 3.5))
    la.tail = Vector((-0.5 if side == "L" else 0.5, 0, 4.5))
    la.roll = 0
    
    # Hand
    hand = arm.data.edit_bones.new(name=f"Hand_{side}")
    hand.parent = la
    hand.head = Vector((-0.5 if side == "L" else 0.5, 0, 4.5))
    hand.tail = Vector((-0.5 if side == "L" else 0.5, 0, 5.0))
    hand.roll = 0

# Leg bones
for side in ["L", "R"]:
    # Thigh
    th = arm.data.edit_bones.new(name=f"Thigh_{side}")
    th.parent = root if side == "L" else root
    th.head = Vector((-0.4 if side == "L" else 0.4, 0, 0))
    th.tail = Vector((-0.4 if side == "L" else 0.4, 0, 2.0))
    th.roll = 0
    
    # Calf
    ca = arm.data.edit_bones.new(name=f"Calf_{side}")
    ca.parent = th
    ca.head = Vector((-0.4 if side == "L" else 0.4, 0, 2.0))
    ca.tail = Vector((-0.4 if side == "L" else 0.4, 0, 3.5))
    ca.roll = 0
    
    # Foot
    foot = arm.data.edit_bones.new(name=f"Foot_{side}")
    foot.parent = ca
    foot.head = Vector((-0.4 if side == "L" else 0.4, 0, 3.5))
    foot.tail = Vector((-0.4 if side == "L" else 0.4, 0, 4.5))
    foot.roll = 0

# Convert to pose mode and set up
bpy.ops.object.mode_set(mode='POSE')

# ---- Create a simple mesh body ----
bpy.ops.mesh.primitive_cube_add(size=2, location=(0,0,0))
body = bpy.context.active_object
body.name = "SlaveBody"
body.parent = arm

# Add material
mat = bpy.data.materials.new(name="SlaveSkin")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.8, 0.6, 0.5, 1.0)  # Skin tone
bsdf.inputs["Roughness"].default_value = 0.3
body.data.materials.append(mat)

# ---- Animation: Idle (simple bone wiggles) ----
# We'll use keyframe animation on the armature

# Set frame start
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 60

# Idle: subtle body sway and arm movement
for frame in range(1, 61):
    t = frame / 60.0
    # Body sway
    if arm.pose.bones["Spine"]:
        arm.pose.bones["Spine"].rotation_euler = (0.02 * math.sin(t * 2.0), 0, 0.01 * math.cos(t * 1.5))
    # Left arm
    if arm.pose.bones["UpperArm_L"]:
        arm.pose.bones["UpperArm_L"].rotation_euler = (0.1 * math.sin(t * 1.5), 0, -0.05 * math.sin(t * 2.0))
    # Right arm
    if arm.pose.bones["UpperArm_R"]:
        arm.pose.bones["UpperArm_R"].rotation_euler = (0.1 * math.cos(t * 1.5), 0, 0.05 * math.cos(t * 2.0))
    # Left leg
    if arm.pose.bones["Thigh_L"]:
        arm.pose.bones["Thigh_L"].rotation_euler = (0.03 * math.sin(t * 1.8), 0, 0.01 * math.cos(t * 1.7))
    # Right leg
    if arm.pose.bones["Thigh_R"]:
        arm.pose.bones["Thigh_R"].rotation_euler = (0.03 * math.cos(t * 1.8), 0, -0.01 * math.sin(t * 1.7))
    
    # Insert keys for all movable bones
    for bone_name in ["Spine", "UpperArm_L", "UpperArm_R", "Thigh_L", "Thigh_R"]:
        bone = arm.pose.bones[bone_name]
        bone.keyframe_insert(data_path="rotation_euler", frame=frame)

# ---- Animation: Walk (leg movement) ----
bpy.context.scene.frame_start = 61
bpy.context.scene.frame_end = 120

for frame in range(61, 121):
    t = (frame - 60) / 60.0
    # Walking: opposite arm/leg movement
    if arm.pose.bones["UpperArm_L"]:
        arm.pose.bones["UpperArm_L"].rotation_euler = (0.2 * math.sin(t * math.pi), 0, -0.1 * math.cos(t * math.pi))
    if arm.pose.bones["UpperArm_R"]:
        arm.pose.bones["UpperArm_R"].rotation_euler = (0.2 * math.cos(t * math.pi), 0, 0.1 * math.sin(t * math.pi))
    if arm.pose.bones["Thigh_L"]:
        arm.pose.bones["Thigh_L"].rotation_euler = (0.3 * math.sin(t * math.pi), 0, 0)
    if arm.pose.bones["Thigh_R"]:
        arm.pose.bones["Thigh_R"].rotation_euler = (0.3 * math.cos(t * math.pi), 0, 0)
    if arm.pose.bones["Calf_L"]:
        arm.pose.bones["Calf_L"].rotation_euler = (0.5 * math.sin(t * math.pi), 0, 0)
    if arm.pose.bones["Calf_R"]:
        arm.pose.bones["Calf_R"].rotation_euler = (0.5 * math.cos(t * math.pi), 0, 0)
    
    for bone_name in ["UpperArm_L", "UpperArm_R", "Thigh_L", "Thigh_R", "Calf_L", "Calf_R"]:
        bone = arm.pose.bones[bone_name]
        if bone:
            bone.keyframe_insert(data_path="rotation_euler", frame=frame)

# ---- Animation: Sword Attack (upper body) ----
bpy.context.scene.frame_start = 121
bpy.context.scene.frame_end = 180

for frame in range(121, 181):
    t = (frame - 120) / 60.0
    # Sword attack: violent upward swing
    if arm.pose.bones["UpperArm_R"]:
        arm.pose.bones["UpperArm_R"].rotation_euler = (1.5 * (1 - t), 0, -0.5 * t)
    if arm.pose.bones["Spine"]:
        arm.pose.bones["Spine"].rotation_euler = (0.3 * (1 - t), 0, 0)
    
    for bone_name in ["UpperArm_R", "Spine"]:
        bone = arm.pose.bones[bone_name]
        if bone:
            bone.keyframe_insert(data_path="rotation_euler", frame=frame)

# Name the action groups
if bpy.data.actions:
    for action in bpy.data.actions:
        if "Idle" in action.name:
            action.name = "Idle"
        elif "Walk" in action.name:
            action.name = "Walk"
        elif "Attack" in action.name:
            action.name = "Sword_Attack"

# Export as glTF
export_path = "res://assets/models/slave.glb"
print(f"Exporting to {export_path}...")
bpy.ops.export_scene.gltf(filepath=export_path, export_format='GLB', export_apply=True)
print("Export complete!")