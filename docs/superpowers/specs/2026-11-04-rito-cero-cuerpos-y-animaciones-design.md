# Rito Cero — cuerpos rígidos, esqueletos y animaciones de combate

- **Fecha:** 2026-11-04
- **Proyecto:** `C:\Users\USUARIO\Documents\rito-cero-` (Godot 4.7.2, export web, renderer Compatibility, Jolt Physics)
- **Depende de:** `2026-11-04-rito-cero-arsenal-y-moloso-design.md` (arsenal y moloso ya integrado), `2026-11-02-rito-cero-combate-design.md` (combate heredado)
- **Plan:** `docs/superpowers/plans/2026-11-04-rito-cero-cuerpos-y-animaciones.md`

---

## 1. Objetivo

Que el combate tenga **cuerpos**: el jugador muere de verdad, con su esqueleto cayendo por
la física; el moloso deja de ser un dibujo con patas y se convierte en un personaje con
esqueleto propio, animaciones de pelea y cuerpo rígido; y los clips de combate del pack
que hasta ahora no se usaban (`Roll`, `Push`, `Hit_Head`, `Jump_Land`) entran en juego.

Decisiones del usuario: el cuerpo rígido y el esqueleto son **del jugador y del moloso**;
las animaciones son **las dos cosas**: clips del pack para los humanos y animaciones
nuevas para el perro.

Criterio de éxito: al morir, Rito cae con su esqueleto simulado y el cuerpo yace en el
suelo hasta reaparecer; el moloso tiene 21 huesos, ciclo de carrera, salto de mordida,
trompeo y levantarse; Rito esquiva con `Roll`, los bandidos empujan con `Push`; y el
navegador sigue en **36 FPS** de mediana.

## 2. Hechos medidos antes de decidir (no estimaciones)

| Hecho | Valor | De dónde sale |
|---|---|---|
| Huesos del maniquí | **53**, jerarquía `root → DEF-hips → DEF-spine.001/.002/.003 → DEF-neck → DEF-head`, más los cuatro miembros | `tools/skeleton_report.gd` |
| Clips del pack | **46**, todos de humano: `Sword_Attack`, `Sword_Attack_RM`, `Punch_Jab`, `Punch_Cross`, `Hit_Chest`, `Hit_Head`, `Death01`, `Roll`, `Push`, `Jump_Land`, `Interact`… | `tools/anim_report.gd` |
| Rig de cuadrúpedo en el proyecto | **ninguno** | El único modelo es `Godot/AnimationLibrary_Godot_Standard.glb` (y sus copias FBX) |
| Cuerpos rígidos en el juego | **ninguno**: todo es `CharacterBody3D` y la muerte es `Death01` enlatada con el cuerpo congelado 8 s | Lectura del código |
| Poses de reposo | pelvis 0,917 m · cabeza 1,569 m · manos ±0,739 m | `tools/skeleton_report.gd` |
| `Death01` | 2,400 s; el cuerpo toca el suelo a los 1,2 s (pelvis 0,078 m, cabeza 0,117 m) y termina tumbado (pelvis 0,063 m, cabeza 0,151 m) | `tools/anim_report.gd` |
| `Roll` | 1,467 s: la pelvis baja a 0,078 m y vuelve | `tools/anim_report.gd` |
| `Jump_Land` | 1,267 s: se agacha a pelvis 0,511 m y se recupera | `tools/anim_report.gd` |
| `Hit_Head` | 0,433 s: la cabeza baja 9 mm | `tools/anim_report.gd` |
| `Push` | 2,667 s | `tools/anim_report.gd` |

**Consecuencia:** el esqueleto del moloso hay que construirlo por código. No hay asset
de cuadrúpedo y la regla del proyecto sigue siendo "cero assets externos".

## 3. Arquitectura

### 3.1 Módulos

```
scripts/combat/
└── ragdoll.gd            (nuevo)  cuerpos fisicos sobre un esqueleto, con capsulas
                                  dimensionadas desde las poses reales

scripts/npc/
├── dog_rig.gd            (nuevo)  esqueleto de 21 huesos del moloso + animaciones
└── roman_dog.gd          (modificado) usa el rig; trompea con RigidBody3D; se levanta

scripts/world/mesh_factory.gd  (modificado) piezas del perro separadas por hueso
scripts/player/rito.gd    (modificado) ragdoll al morir, empujon fisico, esquiva,
                                  aterrizaje y reaccion fuerte
scripts/player/rito_combat.gd  (modificado) la esquiva entra aqui (es input de combate)
scripts/npc/hostile_npc.gd (modificado) empuje con Push y puede golpear al moloso
scripts/dev/bench.gd      (modificado) anade la pose del corpse, el caso de riesgo
project.godot             (modificado) accion dodge (F)
tools/api_probe.gd        (nuevo)  sonda de la API de cuerpos rigidos de Godot 4.7
tools/ragdoll_probe.gd    (nuevo)  sonda de caida y atado del ragdoll
tools/dog_probe.gd        (nuevo)  sonda del rig y sus piezas
tools/combat_test.gd      (modificado) tests del ragdoll, del rig, de la esquiva y
                                  del empujon
```

### 3.2 El ragdoll (`ragdoll.gd`)

Un `PhysicalBone3D` por hueso y una cápsula por hueso, colgados **del propio `Skeleton3D`**:

| Hueso | Segmento que cubre | Radio pedido | Junta |
|---|---|---|---|
| `DEF-hips` | hips → spine.001 | 0,15 | **ninguna** (cuerpo libre: es la raíz de la cadena) |
| `DEF-spine.001/.002/.003` | vértebras | 0,12 / 0,12 / 0,11 | cono |
| `DEF-neck` | cuello → cabeza | 0,13 | cono |
| `DEF-shoulder.L/R` | hombro → brazo | 0,07 | cono |
| `DEF-upper_arm.L/R` | brazo → antebrazo | 0,06 | cono |
| `DEF-forearm.L/R` | antebrazo → mano | 0,055 | cono |
| `DEF-thigh.L/R` | muslo → espinilla | 0,085 | cono |
| `DEF-shin.L/R` | espinilla → pie | 0,065 | cono |
| `DEF-foot.L/R` | pie → punta | 0,05 | cono |

**17 cuerpos físicos.** Las cápsulas se dimensionan midiendo la distancia entre las poses
de dos huesos, así que no hay números inventados: si el maniquí cambia, el ragdoll se ajusta
solo.

**El radio se limita a la mitad del tramo.** Los radios de la tabla son el grosor que
*debería* tener cada miembro, pero el tramo entre dos huesos del maniquí es más corto que
dos radios (la cadera a la primera vértebra mide 0,138 m y el radio pedido era 0,15 m). Si no
se limitan, dos cápsulas vecinas se solapan y el cuerpo se descuartela. El radio real es
`min(radio pedido, tramo × 0,45)`.

Los hombros se simulan aunque no hagan falta como forma: sin ellos, el brazo no tendría
cadena física hasta la columna y quedaría anclado al mundo.

**La pelvis va sin junta a propósito**: es el único hueso cuya cadena no llega a ningún
cuerpo simulado, y sin junta queda libre. Con junta, la pelvis quedaría anclada a la
posición de reposo y el corpse colgaría de ella en vez de caer.

**El ragdoll no se enciende al morir, sino 1,5 s después.** La animación `Death01` dura
2,4 s y el cuerpo no toca el suelo hasta pasado 1,2 s (medido: pelvis a 0,078 m y cabeza a
0,117 m a los 1,2 s; pelvis a 0,063 m y cabeza a 0,151 m al final). Si la física tomara el
relevo con el cuerpo de pie, los cuerpos se quedarían sostenidos en el aire y el corpse
quedaría de pie como un poste. El relevo se produce a los 1,5 s, con el corpse ya tumbado,
y la reaparición llega a los 3,2 s.

Al morir Rito: se para el `AnimationPlayer` **sin resetear la pose** (`stop(true)`), se
enciende la simulación y el cuerpo cae. Al reaparecer: se apaga la simulación, se liberan
los cuerpos rígidos, se restauran las poses del esqueleto y vuelve la animación.

### 3.2.1 Lo que la API de Godot 4.7 obliga a hacer (medido, no supuesto)

Todo lo de arriba está copiado de una sonda al motor, `tools/api_probe.gd`, porque la API
de cuerpos rígidos **cambió** respecto a la conocida y varias cosas de la versión anterior
ya no existen:

| Lo que se daba por supuesto | Lo que hace Godot 4.7 |
|---|---|
| `PhysicalBone3D.bone_name` no aparece en el volcado de la API de extensión | Existe como propiedad, pero **oculta**: el hueso se ata por nombre, no por id |
| `physical_bones_start_simulation(lista de nodos)` | Recibe un `Array[StringName]` de **nombres de hueso**; pasarle los nodos falla con `Cannot assign contents of "Array[Object]" to "Array[StringName]"` |
| Los cuerpos cuelgan de un `PhysicalBoneSimulator3D` | Tienen que ser **hijos directos del `Skeleton3D`**: colgados del simulador, `get_skeleton()` devuelve `null`, los `bone_id` quedan a `-1` y el esqueleto no los sigue |
| El simulador arranca la simulación | La arranca el **propio `Skeleton3D`** (`skeleton.physical_bones_start_simulation`) |
| Hay junta de resorte | No existe: los tipos son `NONE`, `PIN`, `CONE`, `HINGE`, `SLIDER` y `6DOF` |
| `is_simulation_running()` | Se llama `is_simulating_physics()` |
| `AnimationPlayer.stop()` deja la pose | `stop()` **resetea la pose al reposo**: el corpse se levantaba del suelo. Con `stop(true)` la conserva |

### 3.3 El esqueleto del moloso (`dog_rig.gd`)

**21 huesos** hechos por código, con el mismo estilo de atado que el vestuario de Rito
(`BoneAttachment3D`, sin skinning): `root`, `hips`, `spine`, `chest`, `neck`, `head`,
`ear.L/R`, `tail` y cuatro patas de tres huesos (`upper`, `lower`, `foot`).

Cada pieza va atada a su hueso, así que la animación mueve la pieza entera:

| Pieza | Hueso |
|---|---|
| torso | `hips` |
| pecho | `chest` |
| cuello | `neck` |
| cabeza + hocico + ojos | `head` |
| orejas | `ear.L/R` |
| cola | `tail` |
| muslo / espinilla / zarpa | `leg.XX.upper/lower/foot` |

**La pose de un hueso en Godot 4 es absoluta, no una desviación.** La pose nace en
identidad y hay que devolverla al reposo (`reset_bone_poses()`) después de definir los
repos; si no, todas las piezas se quedan en el origen y el perro aparece como un montón de
cajas en el suelo. Y una pista de posición escribe la posición **absoluta** del hueso: tiene
que llevar el reposo más el desplazamiento de la animación, o el hueso se va al origen en la
primera clave.

**Cada clip define la pose entera del perro.** Los huesos que un clip no mueve reciben su
valor de reposo al principio y al final. Sin eso, al cambiar de clip (de `DOWN` a `IDLE`, por
ejemplo) los huesos que el clip nuevo no toca se quedan con la pose del anterior, y el perro
se levanta a medias o se queda con la cabeza gacha para siempre.

Animaciones por código (reemplazan al seno que balanceaba las patas):

| Estado | Qué hace |
|---|---|
| `IDLE` | respiración (el pecho sube y baja) y la cola se mueve |
| `WALK` | ciclo de patas en diagonal (delantero izquierdo con trasero derecho), con rebote del cuerpo |
| `RUN` | lo mismo con más amplitud y frecuencia |
| `BITE` | agachazo, mordisco y vuelta; es lo que hace visible la pelea |
| `DOWN` | cuerpo tumbado de lado, patas desmadejadas |
| `GET_UP` | interpolación de `DOWN` a la pose de pie en 0,8 s |

### 3.4 El trompeo del moloso

Cuando un bandido golpea al perro, el perro se tumba de verdad: su visual (el
`Skeleton3D` con las piezas) se **reparenta** a un `RigidBody3D` con una cápsula, que
recibe un impulso en la dirección del golpe y rueda por el suelo. Al cabo de 1,4 s el
cuerpo rígido se libera, el visual vuelve al perro y se reproduce `GET_UP`.

El perro no muere: tiene vida (60) y si llega a cero se tumba y se repone. Es un
perro de guerra, no un companion que se pierde a mitad de una pelea.

Para que le peguen, el volumen de ataque del NPC pasa de la máscara `2` a `2 | 16`: la
capa 16 es la del perro. El volumen del jugador sigue con la máscara `4`, así que Rito
no puede hacerse daño a sí mismo ni al compañero.

El clip `GET_UP` no se interrumpe: si el Perro volviera al clip de andar a mitad, los
huesos que ese clip no toca se quedarían tumbados y el perro no se levantaría.

### 3.5 Clips del pack para los humanos

| Clip | Quién | Como entra |
|---|---|---|
| `Roll` | Rito | **Esquiva con la tecla F**: impulso de movimiento en la dirección de entrada, 0,35 s de invulnerabilidad y 0,8 s de enfriamiento |
| `Push` | Bandidos | Cada segundo ataque: 6 de daño y un empujón fuerte contra Rito |
| `Hit_Head` | Rito | Reacción a los golpes de 12 o más (los fuertes), en vez de `Hit_Chest` |
| `Jump_Land` | Rito | Al aterrizar de un salto |

El empujón físico se aplica con una velocidad propia (`_push_velocity`) que se suma a
la de caminar y se desvanece: si se sumara a `velocity`, la aceleración del
controlador la borraría en cuatro fotogramas y no se vería nada.

### 3.6 Capas de colisión

| Capa | Bit | Usos |
|---|---|---|
| 1 | 1 | Terreno |
| 2 | 2 | Rito |
| 4 | 4 | NPC hostiles |
| 8 | 8 | Volúmenes de ataque |
| 16 | 16 | Moloso |
| 32 | 32 | Cuerpos rígidos (ragdoll del jugador y trompeco del perro) |

Los cuerpos rígidos van en la capa 32 con máscara 1: colisionan con el terreno y no
empujan a nadie.

## 4. Restricciones (heredadas)

- Renderer Compatibility; sin sombras dinámicas; sin luces nuevas.
- Cero assets externos: el esqueleto del perro y las formas del ragdoll son código.
- **≥ 36 FPS de mediana en Chrome con la GT 640 real** y **≥ 51 FPS** en el banco
  nativo. Con un ragdoll activo (17 cuerpos + skinning) se vigila especialmente.
- Comentarios y mensajes de commit en español, sin emojis.

## 5. Verificación

1. **Arnés** `tools/combat_test.gd` (86 checks):
   - El ragdoll se construye con 17 cuerpos, todas las cápsulas con radio > 0 y todos los
     cuerpos atados a su hueso (`bone_id` ≥ 0).
   - Al activarlo, el corpse **queda tumbado en el suelo** y el esqueleto sigue a los
     cuerpos (si la pelvis quedara anclada, el corpse colgaría y este test lo delata).
   - Al reaparecer, la simulación se apaga y los cuerpos se liberan.
   - El rig del perro tiene 21 huesos, 19 piezas atadas a su hueso y los seis clips.
   - La esquiva aplica el impulso, da invulnerabilidad y respeta el enfriamiento.
   - El empujón físico se aplica al jugador y se desvanece.
   - El moloso se tumba, su visual se va al cuerpo rígido, se levanta y recupera la vida.
2. **Sondas** `tools/api_probe.gd`, `tools/ragdoll_probe.gd`, `tools/dog_probe.gd`: cada
   hecho de la API de Godot 4.7 de la sección 3.2.1 sale de aquí, no de la memoria.
3. **Capturas**: el cuerpo de Rito en el suelo tras morir, el moloso en `IDLE`, corriendo,
   mordiendo y tumbado.
4. **Banco** `tools/bench.tscn` antes/después, incluida una pose con el corpse en el suelo.
5. **Navegador** `tools/verify_web.js`: sin errores de consola y el juego sigue vivo.

## 6. Manejo de errores y casos límite

- Morir y reaparecer en el mismo frame: el simulador se apaga antes de teletransportar,
  o el cuerpo físico se queda en el sitio.
- Reaparecer dentro de un enemigo: 2 s de invulnerabilidad (ya existía).
- El ragdoll se queda colgado en el aire si el terreno no tiene colisión: el cuerpo
  físico tiene máscara 1 y cae al vacío; no es un fallo del juego, pero la captura lo
  delata.
- Trompear al perro mientras ya está tumbado: se ignora hasta que se levanta.
- El perro se levanta dentro de un muro: el visual vuelve al perro, que sigue en su
  sitio, y el `GET_UP` no mueve el cuerpo.
- Atacar mientras hay un menú abierto: el menú ya bloquea el input de combate.

## 7. Fuera de alcance

- Ragdoll de los bandidos muertos (el usuario lo dejó fuera: player y moloso).
- Que el moloso muera de verdad.
- Bonesdynamics (`PhysicalBoneSimulator3D` con límites por hueso) más finos que los de
  este documento.
- Multijugador, guardado, audio.

## 8. Orden de trabajo

1. `ragdoll.gd` + prueba de caída.
2. Rito: ragdoll al morir, restauración, empujón, esquiva, aterrizaje, reacción fuerte.
3. `dog_rig.gd` con 21 huesos y las seis animaciones.
4. `mesh_factory.gd`: piezas del perro separadas.
5. `roman_dog.gd`: rig, trompeco con `RigidBody3D`, levantarse, vida.
6. `hostile_npc.gd`: `Push` y máscara `2 | 16`.
7. `project.godot`: acción `dodge`.
8. Arnés ampliado, capturas, banco, navegador.
9. Documentar resultados y commitear.
