# Arsenal romano y moloso de Rito Cero — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tres armas romanas elegibles desde un menú (gladius, pilum lanzable, spatha) y un moloso que acompaña a Rito y muerde a los bandidos.

**Architecture:** `weapon.gd` deja de ser un juego de arrays paralelos y pasa a un catálogo de una fila por arma. `weapons_holder.gd` monta las tres y muestra una. El pilum es un proyectil aislado en `scripts/combat/projectile.gd`; todo lo demás del combate (volumen de ataque, capas, esqueleto) queda intacto. El moloso es un `CharacterBody3D` con máquina de estados de compañero y patas animadas por código.

**Tech Stack:** Godot 4.7.2-stable, GDScript, renderer `gl_compatibility` (WebGL2), Terrain3D 1.1 (GDExtension), Jolt Physics, export web sin hilos.

**Spec:** `docs/superpowers/specs/2026-11-04-rito-cero-arsenal-y-moloso-design.md`

## Global Constraints

- Renderer **`gl_compatibility`** obligatorio; nada que exija Forward+/Mobile.
- **Sombras dinámicas: cero.** **Luces nuevas: máximo 0** (la antorcha ya es la única).
- **Ningún asset externo**: armas, perro y UI con primitivas y código.
- Umbral de rendimiento: **≥ 36 FPS de mediana en Chrome con GPU real** y **sin bajar de 51 FPS** en el banco nativo.
- Comentarios, nombres de archivo y mensajes de commit en **español**, sin emojis.
- Tras crear un script con `class_name`, refrescar el caché de clases globales antes de ejecutar nada:
  `"<GODOT>" --headless --path "<PROY>" --import`
- Un commit por tarea, al final de la tarea, con el test en verde.

Rutas de trabajo:

```bash
GODOT="C:/Users/USUARIO/Desktop/Godot_v4.7.2-stable_win64.exe"
PROY="C:/Users/USUARIO/Documents/rito-cero-"
```

## Línea base (medida antes de tocar nada)

| Medida | Valor |
|---|---|
| `tools/combat_test.gd` | `TEST failures=0 checks=37` |
| `tools/bench.tscn` | `median_avg=60.0` (draws 99–106, tris 128k–163k) |
| GPU detectada | NVIDIA GeForce GT 640, Compatibility 3.3.0 |

---

## Task 1: Catálogo de armas y geometrías

**Files:**
- Modify: `scripts/combat/weapon.gd`

**Interfaces:**
- Produces: `Weapon.CATALOG` (una fila por arma), `Weapon.get_weapon(index) -> Dictionary`, `Weapon.count()`, `Weapon.make_mesh(mesh_id) -> ArrayMesh`, y las geometrías `make_gladius`, `make_pilum`, `make_spatha`.

- [x] **Step 1: Sustituir los arrays paralelos por un catálogo**

Cada fila: `id`, `name`, `role`, `mode` (`MODE_MELEE` / `MODE_THROW`), `damage`, `reach`, `cooldown`, `window_open`, `window_close`, `radius`, `anim_speed`, `grip_rot_x`, `mesh`, `summary`.

- [x] **Step 2: `make_spatha`**

Hoja larga (1,15 m), guarda con florete, empuñadura larga y pomo. Mismos colores que el gladius.

- [x] **Step 3: `make_pilum`**

Astil de madera de 1,85 m, vástago de hierro con punta piramidal y punta trasera. Se apoya en
el astil de la lanza heredada, así que el rol cuerpo a cuerpo se pierde a propósito.

- [x] **Step 4: `make_mesh` reparte por id**

- [x] **Step 5: Reimportar y comprobar que nada usa las constantes viejas**

`grep REACH|DAMAGE|COOLDOWN|WINDOW|RADIUS|ANIM_SPEED|GRIP_ROT_X` solo debe dar
`weapons_holder.gd`, que se rehace en la Task 2.

---

## Task 2: El holder monta el arsenal

**Files:**
- Modify: `scripts/combat/weapons_holder.gd`

**Interfaces:**
- Consumes: `Weapon.CATALOG`, `Weapon.make_mesh`.
- Produces: `setup(skeleton)`, `switch_to(index)`, `current_index()`, `current_weapon() -> Dictionary`, `current_damage()`, `current_cooldown()`, `current_reach()`, `current_radius()`, `current_window()`, `current_anim_speed()`, `current_mode()`, `current_name()`, `hand_position()`, `set_weapon_visible(visible)`.

- [x] **Step 1: Un `BoneAttachment3D` por fila del catálogo**

- [x] **Step 2: Solo la activa visible**

- [x] **Step 3: El agarre de cada arma con su `grip_rot_x`**

- [x] **Step 4: `hand_position()` devuelve la posición global de la mano**

La necesita el proyectil para nacer donde está el arma, no en el centro del pecho.

---

## Task 3: El pilum lanzable

**Files:**
- Create: `scripts/combat/projectile.gd`
- Modify: `scripts/player/rito_combat.gd`
- Modify: `project.godot` (acción `weapon_3`)

**Interfaces:**
- Produces: `Projectile.setup(origin, direction, damage, speed, max_distance, mask)`, señal `landed(target, damage)`.

- [x] **Step 1: El proyectil**

Raycast del **segmento** recorrido por frame, máscara `1 | 4`. Impacto en NPC: `Combatant` del
cuerpo golpeado. Impacto en terreno: se clava y se retira a los 2,5 s.

- [x] **Step 2: `rito_combat` distingue el modo**

Si el arma es `throw`, el ataque lanza el proyectil en vez de abrir la ventana del volumen.
El pilum desaparece de la mano y vuelve cuando pasa la cadencia.

- [x] **Step 3: Tecla 3**

`weapon_3` en `project.godot` (physical_keycode 51).

---

## Task 4: El menú de arsenal

**Files:**
- Create: `scripts/ui/arsenal_menu.gd`
- Modify: `project.godot` (acción `arsenal_menu`: Tab y B)

**Interfaces:**
- Consumes: `WeaponsHolder` (para leer y cambiar el arma) y la señal `weapon_changed`.
- Produces: `setup(combat)`, `open()`, `close()`, `is_open()`, `equip(index)`.

- [x] **Step 1: Panel con las tres filas**

Título, nombre latino, rol, daño, alcance, cadencia y resumen. La activa va marcada.

- [x] **Step 2: Clic, rueda y teclas**

- [x] **Step 3: Abrir y cerrar**

Al abrir: ratón `VISIBLE`, combate deshabilitado, Rito no recaptura el puntero. Al cerrar: se
restaura lo que hubiera.

---

## Task 5: HUD con el arsenal

**Files:**
- Modify: `scripts/ui/hud.gd`

- [x] **Step 1: Fila de tres fichas con el arma activa resaltada**

- [x] **Step 2: Nombre completo, estadísticas y pista `Tab: arsenal`**

- [x] **Step 3: Todo por la señal `weapon_changed`**

---

## Task 6: El moloso

**Files:**
- Modify: `scripts/world/mesh_factory.gd` (`make_roman_dog`, `make_dog_leg`)
- Create: `scripts/npc/roman_dog.gd`
- Modify: `scripts/npc/hostile_npc.gd` (grupo `"hostiles"`)
- Modify: `scripts/main.gd`

**Interfaces:**
- Produces: `RomanDog.setup(player)`, señal `killed(target)`.

- [x] **Step 1: Malla del perro**

Cuerpo, pecho, cuello, cabeza, hocico, orejas y cola en un mesh. Patas aparte con pivote en
la cadera.

- [x] **Step 2: Máquina de estados**

`FOLLOW` → `CHASE` → `BITE` → `RETURN`, con evitación por raycast como el patrullero.

- [x] **Step 3: Capa 16 y colisión con terreno y con Rito**

- [x] **Step 4: Las patas se balancean con la velocidad**

- [x] **Step 5: Los hostiles se registran en el grupo `"hostiles"`**

- [x] **Step 6: `main.gd` crea el moloso junto al spawn y enlaza sus bajas con las de Rito**

---

## Task 7: Puentes web y captura del ratón

**Files:**
- Modify: `scripts/player/rito.gd`
- Modify: `scripts/main.gd`

- [x] **Step 1: `__rito` expone `weapon_name`, `dog_state` y `dog_dist`**

- [x] **Step 2: Rito no recaptura el puntero mientras hay un menú abierto**

---

## Task 8: Tests

**Files:**
- Modify: `tools/combat_test.gd`
- Modify: `tools/verify_web.js`

- [x] **Step 1: Test del catálogo**

- [x] **Step 2: Test del alcance de la spatha**

- [x] **Step 3: Test del proyectil**

- [x] **Step 4: Test del cambio de arma y del menú**

- [x] **Step 5: Test del moloso**

- [x] **Step 6: Actualizar `EXPECTED_CHECKS`**

- [x] **Step 7: `verify_web.js`**: tecla 2 → pilum, tecla 3 → spatha, menú abierto, moloso cerca

---

## Task 9: QA visual, banco y cierre

**Files:**
- Modify: `tools/shot.gd`
- Modify: este plan y el spec

- [x] **Step 1: Pose `--arsenal`**: panel del arsenal abierto**

- [x] **Step 2: Pose `--dog`**: el moloso junto a Rito**

- [x] **Step 3: Banco antes/después**

- [x] **Step 4: Medir y documentar el resultado**

Resultados medidos el 2026-11-04:

| Medida | Línea base | Después | Veredicto |
|---|---|---|---|
| `tools/combat_test.gd` | `failures=0 checks=37` | `failures=0 checks=62` | 25 checks nuevos en verde |
| `tools/bench.tscn` | `median_avg=60.0` (draws 99-106, tris 128k-163k) | `median_avg=60.0` (draws 111-133, tris 122k-150k) | Sin regresión |
| Peor frame del banco | 28-36 ms | 17-24 ms | Dentro del ruido |
| `tools/verify_web.js` (Chrome + SwiftShader) | 9 checks PASS | **12 checks PASS** | Menú de arsenal y moloso comprobados en navegador |
| `.pck` web | 14,42 MiB | 15,66 MB | +1,2 MB (scripts, mallas y `demo/` que ya se empaquetaba) |

Capturas: `shot_light_arsenal.png` (el menú con las tres armas y sus cifras),
`shot_light_dog.png` (el moloso junto a Rito), `shot_pilum_mano.png` (el pilum en la
mano) y `shot_light_throw.png` (el pilum en vuelo).

El `console.error` que aparece en la verificación web
(`res://assets/models/colosseum.glb` no existe) es **anterior a este trabajo**: lo carga
`scripts/world/structures.gd` como opcional y cae al coliseo construido por código.

- [x] **Step 5: Commit**

---

## Fuera de alcance

XP, denarios, inventario, árbol de tecnología, tablero de misiones, escudos, audio y
guardado. Son los proyectos 2 y 3 del arco "de peón a emperador".
