# Cuerpos rígidos, esqueletos y animaciones de combate — Plan

**Goal:** Que Rito muera con su esqueleto cayendo por la física, que el moloso tenga esqueleto propio, animaciones de pelea y cuerpo rígido, y que entren los clips de combate del pack que no se usaban.

**Architecture:** `ragdoll.gd` monta un `PhysicalBoneSimulator3D` sobre el esqueleto del maniquí con las cápsulas dimensionadas desde las poses de reposo. `dog_rig.gd` construye un esqueleto de 21 huesos para el moloso y sus animaciones por código. Los clips `Roll`, `Push`, `Hit_Head` y `Jump_Land` se conectan al combate existente sin tocar sus reglas de daño.

**Tech Stack:** Godot 4.7.2-stable, GDScript, Jolt Physics, renderer `gl_compatibility`.

**Spec:** `docs/superpowers/specs/2026-11-04-rito-cero-cuerpos-y-animaciones-design.md`

## Global Constraints

- Renderer `gl_compatibility`; sin sombras dinámicas; sin luces nuevas.
- Cero assets externos: el esqueleto del perro y las formas del ragdoll son código.
- **≥ 36 FPS** de mediana en Chrome con la GT 640 real; **≥ 51 FPS** en el banco nativo.
- Comentarios y mensajes de commit en español, sin emojis.
- Tras crear un script con `class_name`, `--headless --import` antes de ejecutar nada.

```bash
GODOT="C:/Users/USUARIO/Desktop/Godot_v4.7.2-stable_win64.exe"
PROY="C:/Users/USUARIO/Documents/rito-cero-"
```

## Línea base

| Medida | Valor |
|---|---|
| `tools/combat_test.gd` | `failures=0 checks=62` |
| `tools/bench.tscn` | `median_avg=60.0` |

---

## Task 1: El ragdoll

**Files:** Create `scripts/combat/ragdoll.gd`

- [ ] **Step 1: Las 17 entradas de hueso con su radio y su tipo de junta**
- [ ] **Step 2: `attach(skeleton)` construye el simulador y las cápsulas desde las poses de reposo**
- [ ] **Step 3: `activate()` / `deactivate()`**
- [ ] **Step 4: Prueba de caída**: el cuerpo baja de Y de forma medible**

## Task 2: Rito físico

**Files:** Modify `scripts/player/rito.gd`, `scripts/player/rito_combat.gd`, `project.godot`

- [ ] **Step 1: Al morir, ragdoll y colisión desactivada; al reaparecer, al revés**
- [ ] **Step 2: `_push_velocity` para el empujón físico**
- [ ] **Step 3: Esquiva con `Roll` (tecla F), con invulnerabilidad y enfriamiento**
- [ ] **Step 4: `Jump_Land` al aterrizar y `Hit_Head` en los golpes fuertes**

## Task 3: El esqueleto del moloso

**Files:** Create `scripts/npc/dog_rig.gd`, modify `scripts/world/mesh_factory.gd`

- [ ] **Step 1: 21 huesos y las piezas atadas**
- [ ] **Step 2: Las seis animaciones: IDLE, WALK, RUN, BITE, DOWN, GET_UP**

## Task 4: El moloso físico

**Files:** Modify `scripts/npc/roman_dog.gd`, `scripts/npc/hostile_npc.gd`

- [ ] **Step 1: El perro usa el rig**
- [ ] **Step 2: Trompeo: el visual se reparenta a un `RigidBody3D` y rueda**
- [ ] **Step 3: Levantarse con `GET_UP`**
- [ ] **Step 4: El perro tiene vida y no muere**
- [ ] **Step 5: `Push` en los bandidos y mascara `2 | 16` para poder golpear al perro**

## Task 5: Verificación

- [ ] **Step 1: Arnés ampliado** (ragdoll, rig, esquiva, empujón)
- [ ] **Step 2: Capturas** (cuerpo en el suelo, mordida, trompeco, levantarse)
- [ ] **Step 3: Banco** antes/después
- [ ] **Step 4: Build web y verificación en navegador**
- [ ] **Step 5: Documentar resultados y commitear**

## Fuera de alcance

Ragdoll de los bandidos muertos, muerte real del moloso, bonesdynamics finos, audio y guardado.
