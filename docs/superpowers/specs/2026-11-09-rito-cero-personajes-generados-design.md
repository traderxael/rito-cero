# Rito Cero — personajes generados con rig propio

- **Fecha:** 2026-11-09
- **Proyecto:** `C:\Users\USUARIO\Documents\rito-cero-` (Godot 4.7.2, export web, renderer Compatibility, Jolt Physics)
- **Estado:** borrador para aprobación del usuario

---

## 1. Intención

Hoy los personajes se ven como el maniquí de prueba del Animation Library: Rito lleva una túnica cilíndrica y una cara plana pintada en un quad; los bandidos son el maniquí crudo (naranja con articulaciones moradas) con una gladius. El objetivo es que los personajes sean **modelos 3D generados** (hechos con las herramientas de modelado/generación, no con geometría por código):

- **Rito:** romano con toga drapeada (pliegues, pliegue del hombro, borde púrpura) y una cara con volumen y mejor pintada.
- **Bandidos:** ropa y armadura (túnica, cinturón, casco, escudo), con variaciones para distinguir la purga de la cueva.
- **Praetorian:** más grande y con más armadura.

Decisiones del usuario: **modelos generados** (camino C), **personaje completo** (C1, no solo ropa sobre el maniquí) y **rig propio con retradición** de las animaciones (R2).

## 2. Objetivos, no objetivos y anti-objetivos

**Objetivos**

- Rito, los bandidos y el Praetorian son modelos generados con su propio rig.
- Las animaciones del maniquí siguen funcionando, retraducidas al rig nuevo, con los mismos nombres.
- El juego no baja de su media actual en web (**26–29 FPS** medidos en Chrome con GT 640; el objetivo del proyecto sigue siendo 36) ni de 51 FPS en nativo.
- Las caras mejoran: volumen (nariz, orejas, cejas) y una textura más nítida.

**No objetivos**

- Cambiar el combate, las misiones, la progresión ni el entorno.
- Animaciones nuevas: solo se retradicen las existentes.
- Rediseñar el esclavo: comparte maniquí y hay que actualizar sus nombres de huesos, pero su aspecto no es objetivo.

**Anti-objetivos**

- Que un personaje se vea peor que el maniquí actual.
- Que las animaciones se rompan: pies que se deslizan, piernas que se abren, manos que se meten en el cuerpo.
- Que el juego baje de su media actual en web (26–29 FPS).
- Que el ragdoll deje de funcionar (depende de los nombres de huesos del maniquí).

## 3. Restricciones

- Renderer Compatibility; sin sombras dinámicas; sin luces nuevas (salvo la antorcha).
- No bajar de la media actual en web (26–29 FPS en Chrome, GT 640 real) ni de 51 FPS en el banco nativo. El objetivo del proyecto sigue siendo 36 FPS en web.
- La regla "cero assets externos" se relaja para este proyecto: se permiten modelos generados.
- Comentarios y mensajes en español, sin emojis.
- Los clips del rig nuevo deben llamarse igual que los actuales para no tocar la lógica de juego.

## 4. Enfoques considerados

| Enfoque | Descripción | Veredicto |
|---|---|---|
| A. Vestuario procedural por código | Geometría por huesos, como la ropa actual | Descartado: el usuario quiere modelos generados |
| B. Texturas pintadas | Pintar ropa y cara en texturas | Descartado: no da volumen |
| **C. Modelos generados** | Personajes hechos con las herramientas 3D | **Elegido** |
| C1. Personaje completo | Reemplaza el maniquí | **Elegido** |
| C2. Ropa y cara sobre el maniquí | Híbrido | Descartado |
| R1. Reusar el esqueleto del maniquí | Skin nuevo, animaciones intactas | Descartado: proporciones limitadas |
| **R2. Rig propio + retradición** | kiln autorig + copiar los clips | **Elegido** |

## 5. Decisiones de construcción

### 5.1 Herramienta y pipeline

- **kiln** (Blender 5.2 + MCP) es la herramienta principal: ya está probada en el equipo (`kiln-test` con el galo). Puede modelar por brief, auto-rigear con SkinTokens (huesos Mixamo), texturizar desde PolyHaven (CC0), optimizar (Draco + WebP) y exportar GLB.
- **StableGen** (IA + rigging) necesita ComfyUI, que no está instalado (5,6 GB). Solo si lo pides.
- **foto-3d** (Hunyuan3D-2) genera mallas sin rig; habría que acoplarlo a kiln para el rig.
- **Propuesta:** cuerpo base CC0 (Blender Human Base Meshes) + ropa/armadura modelada con kiln + textura con kiln. Evita las topologías sucias de la IA y da control sobre el estilo.
- **Riesgo del rig:** `autorig.py` (SkinTokens) **no está instalado** (5,6 GB, ~7 GB de RAM por malla). La máquina es un i7-3820 (sin AVX2) con GT 640 de 2 GB: PyTorch moderno puede negarse a correr y no hay GPU útil. Si no funciona, la alternativa es el rig manual de kiln (Rigify, offline y sin torch; medido peor en deformación, pero con nombres `DEF-*` muy cercanos al maniquí, lo que facilita la retradición).

### 5.2 El rig y la retradición

- **Rig:** `kiln/tools/autorig.py rig` (SkinTokens) genera huesos tipo Mixamo: `Hips`, `Spine`, `Spine1`, `Neck`, `Head`, `LeftUpLeg`, `LeftLeg`, `LeftFoot`, `LeftToeBase`, `LeftArm`, `LeftForeArm`, `LeftHand`, `LeftFingers` (y los Right).
- **Retradicción:** un script propio adaptando la matemática de `kiln/tools/retarget.py` (que ya convierte movimiento en giros world-space):
  1. Importar el maniquí (`Godot/AnimationLibrary_Godot_Standard.glb`) y el personaje generado (rig kiln) en Blender.
  2. Mapear huesos `DEF-*` del maniquí a los nombres Mixamo del rig nuevo (tabla 5.2.1).
  3. Por cada clip y por cada fotograma: copiar el giro world-space de cada hueso del maniquí al equivalente del rig nuevo, relativo a su reposo, **y también la traslación de la cadera**. Los clips llevan movimiento en las caderas (`Death01` termina 0,825 m adelante y 0,482 m abajo; `Roll` recorre 1,103 m; `Sword_Attack` lanza 0,267 m) y el ragdoll depende de que `Death01` deje la pelvis a 0,063 m. Copiar solo rotaciones rompe el ragdoll y los movimientos.
  4. Bake y nombrar los clips con los nombres que el código pide (ver 5.2.2).
  5. Medir con `kiln/tools/motion_measure.py` y revisar visualmente (pie deslizado, pierna abierta, brazo dentro del cuerpo).

**Nota:** `kiln/tools/retarget.py` solo lee clips SOMA en `.npz`, no animaciones glTF. Habrá que escribir un lector de animaciones glTF y aplicar la misma matemática (giros world-space, pies plantados, brazos fuera del cuerpo, bucles cerrados). Es la parte más grande del trabajo.

**Tabla 5.2.1 — mapeo de huesos**

| Maniquí (`DEF-*`) | Rig nuevo (Mixamo) |
|---|---|
| `DEF-hips` | `Hips` |
| `DEF-spine.001` | `Spine` |
| `DEF-spine.002` | `Spine1` |
| `DEF-spine.003` | `Spine2` |
| `DEF-neck` | `Neck` |
| `DEF-head` | `Head` |
| `DEF-shoulder.L/R` | `LeftShoulder` / `RightShoulder` (si el rig los tiene) |
| `DEF-upper_arm.L/R` | `LeftArm` / `RightArm` |
| `DEF-forearm.L/R` | `LeftForeArm` / `RightForeArm` |
| `DEF-hand.L/R` | `LeftHand` / `RightHand` |
| `DEF-thigh.L/R` | `LeftUpLeg` / `RightUpLeg` |
| `DEF-shin.L/R` | `LeftLeg` / `RightLeg` |
| `DEF-foot.L/R` | `LeftFoot` / `RightFoot` |
| `DEF-toe.L/R` | `LeftToeBase` / `RightToeBase` |

**Clips que el código espera:**

- Rito: `Idle`, `Idle_Loop`, `Walk`, `Walk_Loop`, `Jog_Fwd`, `Sprint`, `Sprint_Loop`, `Jump`, `Jump_Loop`, `Jump_Start`, `Idle_Torch`, `Idle_Torch_Loop`, `Hit_Chest`, `Hit_Head`, `Death01`, `Death`, `Roll`, `Jump_Land`, `Sword_Attack`, `Sword_Attack_RM`, `Punch_Jab`, `Punch_Cross`.
- Bandidos y esclavo: `Idle`, `Walk`, `Sword_Attack`, `Push`, `Hit_Chest`, `Death01`.

El código usa listas de respaldo (`["Idle", "Idle_Loop"]`), así que la falta de `Idle` no rompe nada: resuelve a `Idle_Loop`. Pero hay un desajuste real: `hostile_npc.gd` llama `_play("Push")` **sin respaldo** y el maniquí tiene `Push_Loop`; el empujón nunca llega a animarse (fallo existente).

**Decisión (mía):** el rig nuevo tendrá los clips con los nombres del maniquí (`Push_Loop`, `Idle_Loop`, `Walk_Loop`, `Sprint_Loop`, `Jump_Loop`, `Death01`, …) y se corrige el `_play("Push")` para que use `Push_Loop`.

### 5.3 Integración en Godot

- Sustituir `MANNEQUIN_SCENE` por el nuevo GLB en `scripts/player/rito.gd`, `scripts/npc/hostile_npc.gd` y `scripts/npc/slave.gd`.
- Actualizar los nombres de huesos en:
  - `scripts/combat/ragdoll.gd` — 17 pares de huesos.
  - `scripts/player/rito_outfit.gd` — 5 nombres. La túnica, las sandalias, el pelo, la barba y la cara **desaparecen** (van en la malla generada); queda la antorcha.
  - `scripts/combat/weapons_holder.gd` — `DEF-hand.R`.
  - `scripts/npc/hostile_npc.gd` — `DEF-hand.R`.
  - `scripts/npc/slave.gd` — `DEF-hand.R` y `Spine`.
- Los radios de las cápsulas del ragdoll se midieron sobre el maniquí. Si el nuevo cuerpo cambia de proporciones, se vuelven a medir con `tools/skeleton_report.gd`.
- **Verificar el set de huesos del rig nuevo:** el ragdoll necesita hombros (`LeftShoulder`/`RightShoulder`) y el esclavo cuelga una soga de `Spine`. Si el rig no los tiene, se añaden a mano. (La soga del esclavo ya está rota: el maniquí no tiene `Spine`.)
- **Se elimina `recolor_skin`** (`rito_outfit.gd`): sustituye todos los materiales por un color plano y destruiría las texturas del modelo generado.
- **Herramientas de test y sonda:** `tools/combat_test.gd`, `tools/anim_report.gd`, `tools/api_probe.gd`, `tools/ragdoll_probe.gd`, `tools/shot.gd` y `tools/skeleton_report.gd` cargan el maniquí y/o usan `DEF-*`. Se actualizan al nuevo rig.
- Los nombres de los clips no cambian.

### 5.4 Variantes

- **Propuesta:** un **cuerpo base** compartido + piezas de ropa/armadura generadas por separado (toga de Rito, armadura de bandido, casco, escudo). Así las variantes son combinaciones, no modelos nuevos.
- Tinte por material para distinguir la purga (rojizo) de la cueva.
- Praetorian: escala mayor y piezas extra.

### 5.5 Optimización

- Objetivo: cada personaje ≤ ~15.000 triángulos (como el maniquí) para no reventar el presupuesto actual (122–175k en escena).
- GLB **sin Draco**: Godot 4.7 no lee `KHR_draco_mesh_compression` (verificado en el fuente 4.7-stable). Texturas WebP (sí soportadas). Alternativa: FBX.
- Un GLB por personaje con todos sus clips.

## 6. Fases

1. **Piloto (Rito + 3 clips):** `Idle`, `Walk`, `Sword_Attack`. Valida generación, rig, retradición e integración antes de seguir.
2. **Rito completo:** todos los clips, toga drapeada, cara.
3. **Bandidos:** armadura, casco, escudo y variantes de tinte.
4. **Praetorian:** escala y armadura extra.
5. **Optimización y verificación:** banco, web, tests.

## 7. Verificación

- Capturas en juego: Rito en reposo, andando, atacando, muerto (ragdoll) y bandidos.
- `tools/combat_test.gd` (ragdoll, esquiva, empuje) y el resto de los tests actuales.
- `tools/bench.tscn` antes y después.
- Medir la media en web antes y después (baseline 26–29 FPS); el criterio es no bajarla.
- `tools/verify_web.js` en el build web.
- `kiln/tools/motion_measure.py` en los clips retraducidos.

## 8. Preguntas abiertas

**Para el usuario (cambian el plan):**

1. **El rig:** `autorig.py` (SkinTokens) no está instalado y la máquina es un i7-3820 con GT 640. ¿Instalamos SkinTokens (5,6 GB, riesgo de que PyTorch no corra por falta de AVX2) o usamos el rig manual de kiln (Rigify, offline, sin torch, nombres `DEF-*` cercanos al maniquí)?
2. **El objetivo de web:** el baseline real es 26–29 FPS, no 36. ¿El criterio es "no bajar de 26–29" o hay que subir a 36 (lo que exigiría un trabajo de rendimiento aparte)?

**Propuestas mías (rectificables):**

3. **¿Empezamos por el piloto de Rito?** (recomendado: valida el pipeline entero).
4. **¿Estilo low-poly estilizado**, para que combine con el entorno? (recomendado).
5. **¿kiln como herramienta principal**, sin StableGen ni foto-3d? (recomendado).
6. **¿Un cuerpo base compartido con piezas de ropa intercambiables** o un modelo completo por personaje?
