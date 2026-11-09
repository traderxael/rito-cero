# Rito Cero — subsistema de combate (armas, daño y muerte)

- **Fecha:** 2026-11-02
- **Proyecto:** `C:\Users\USUARIO\Documents\rito-cero-` (Godot 4.7.2, export web, renderer Compatibility)
- **Depende de:** `docs/superpowers/specs/2026-11-02-rito-cero-web-design.md` (v1 y su §14)

---

## 1. Objetivo

Darle a Rito un arma y que el mundo la note. Un gladius y una lanza intercambiables, con
ataques que impactan, NPCs que se enfadan, te persiguen y te golpean, y vida y muerte para
todos los que están en escena, incluido el jugador.

Criterio de éxito: en el build web, Rito puede empuñar el gladius o la lanza, matar a un NPC
de varios tajos con reacción visible, recibir golpes que bajan una barra de vida, morir y
reaparecer — y el FPS del navegador no cae más de un 15 % respecto a los 42,0 medidos antes
de tocar nada.

## 2. Decisiones ya tomadas por el usuario

| Decisión | Elección | Consecuencia inevitable |
|---|---|---|
| Armas | Gladius **y** lanza, cambio con tecla | Dos geometrías y dos ritmos de ataque; la lanza no tiene animación de estocada en el pack |
| Objetivo | Los NPCs actuales pasan a hostiles | Necesitan vida, aggro, persecución, ataque y muerte |
| Consecuencias | Vida y muerte para todos | El jugador puede morir y hay que reaparecerlo |

## 3. Corrección de un dato que di mal

En la iteración anterior afirmé que "4 NPCs con skinning son +30.000-60.000 triángulos".
Nunca lo medí. El maniquí del pack tiene 8.546 vértices y ~2.800 triángulos, así que cuatro
instancias son ~11.000 triángulos. El coste real de darles esqueleto es el **skinning y la
evaluación de 4 AnimationPlayer de 53 huesos por frame**, no la geometría.

Esto importa aquí porque un NPC hostil que recibe un golpe y muere **necesita esqueleto**
para reproducir `Hit_Chest` y `Death01`. La decisión de dárselo o no la toma el banco de
pruebas (§9), no una estimación.

## 4. Arquitectura

### 4.1 Módulos nuevos

```
scripts/combat/
├── combatant.gd        Componente Node. Dueño único de la vida. Lo llevan Rito y cada NPC.
├── weapon.gd           Factoría estática de geometrías: gladius y lanza.
├── attack_volume.gd    Area3D en la mano. Ventana de daño por fracción del clip.
└── weapons_holder.gd   Monta/desmonta el arma en el hueso de la mano y gestiona el cambio.

scripts/player/
└── rito_combat.gd      Input de combate del jugador, estados de ataque, muerte y reaparición.

scripts/npc/
└── hostile_npc.gd      Sustituye a roman_npc.gd: patrulla -> aggro -> persecución -> ataque.

scripts/ui/
└── hud.gd              (modificado) Barra de vida y contador de bajas.
```

### 4.2 Contrato de `combatant.gd`

Interfaz pública — todo lo demás pasa por aquí:

```gdscript
setup(max_health: float) -> void
take_damage(amount: float, source_position: Vector3) -> void
is_alive() -> bool
heal_full() -> void
signal health_changed(current: float, maximum: float)
signal damaged(amount: float)
signal died(source_position: Vector3)
```

Reglas del contrato, que son donde se cuelan los bugs:
- `take_damage` sobre algo muerto **no** emite `died` una segunda vez.
- La vida se clampa a `[0, max_health]`.
- `died` se emite **una sola vez** por instancia.
- El daño no se aplica si `invulnerable_until` está vigente (lo usa la reaparición).

Cada instancia lleva **su propia copia del material**: si dos NPCs compartieran material, el
fogonazo de "me han golpeado" se aplicaría a los dos a la vez.

### 4.3 Capas de colisión

| Capa | Bit | Usos |
|---|---|---|
| 1 | 1 | Terreno (Terrain3D) |
| 2 | 2 | Rito (cuerpo) |
| 4 | 4 | NPCs (cuerpo) |
| 8 | 8 | Volúmenes de ataque |

- Volumen de ataque del jugador: `collision_layer = 8`, `collision_mask = 4` (solo NPCs).
- Volumen de ataque de un NPC: `collision_layer = 8`, `collision_mask = 2` (solo Rito).
- Los volúmenes tienen `monitorable = false`, para que un Area3D no detecte a otro.
- La línea de visión del aggro es un raycast con máscara `1` (solo terreno), no contra cuerpos.

### 4.4 Prioridad de animación (el cambio estructural en `rito.gd`)

Hoy `_update_model()` elige un estado en línea recta (idle/caminar/correr/saltar/antorcha).
Un ataque se cortaría en cuanto el jugador dé un paso. Se añade un bloqueo de un solo
disparo:

```gdscript
func play_one_shot(name: String, lock_seconds: float) -> void   # fija _lock_until
func is_locked() -> bool
```

Mientras `_lock_until` esté vigente, `_update_model()` **no cambia** el estado de locomoción.
Muerte y golpe recibido usan el mismo mecanismo, con prioridad: `dying` > `hit` > `attack` >
locomoción.

### 4.5 Ventana de impacto, no raycast por frame

El `attack_volume` es un `Area3D` hijo del nodo `Model` del personaje, desplazado en +Z hasta
el alcance del arma y a 1,2 m de altura; su ventana de daño solo está abierta durante los
fotogramas activos del clip. No sigue al hueso de la mano: el volumen es fijo en el espacio
del cuerpo y lo que se mueve es la animación por encima de él. La ventana se define **como
fracción de la duración del clip**, porque el clip cambia entre armas y la fracción se
mantiene válida si se reescala la animación. Duraciones medidas con `tools/anim_report.gd`
sobre el pack real (46 clips):

| Arma | Clip | Duración real | Velocidad | Ventana activa | Daño | Radio | Cadencia |
|---|---|---|---|---|---|---|---|
| Gladius | `Sword_Attack` | 1,533 s | 2,0× | 0,25 – 0,55 | 34 | 0,75 m | 0,55 s |
| Lanza | `Punch_Jab` (estocada) | 0,867 s | 1,0× | 0,30 – 0,60 | 46 | 0,45 m | 0,85 s |

La **velocidad** no es un adorno: a 1,0× el gladius cierra su ventana a los 0,843 s, muy
después de que la cadencia de 0,55 s permita el siguiente tajo, así que el segundo ataque
llegaría mientras el primero aún describe su arco. A 2,0× la duración efectiva es 0,767 s y
la ventana cierra a los 0,422 s, antes de la cadencia. La lanza no necesita reescalado: su
ventana cierra a los 0,520 s y su cadencia (0,85 s) coincide con el final del clip.

**Invariante que fija estos números:** el cierre de la ventana, en segundos, queda siempre
por debajo de la cadencia. Si se cambia una cadencia o se sustituye un clip, se comprueba.

Resto de claveles verificados: `Sword_Attack_RM` 1,533 s, `Punch_Cross` 1,000 s,
`Hit_Chest` 0,333 s, `Death01` 2,400 s. Y una corrección al punto 1 de §9: `Idle_Loop`,
`Walk_Loop` y `Sprint_Loop` **no existen** en el pack importado; los nombres reales son
`Idle` (2,500 s), `Walk` (1,333 s) y `Sprint` (0,667 s), que ya encabezan las listas `ANIM_*`
de `rito.gd`, así que el candidato primario gana y no hay que tocar nada.

Alcance efectivo: 2,2 m el gladius, 3,4 m la lanza. La `CollisionShape3D` del volumen es una
esfera con el radio de la tabla, desplazada en el eje frontal de la mano hasta esa distancia.
**No** es un radio alrededor del personaje: si lo fuera, un NPC pegado a la espalda de Rito
recibiría el tajo de un giro que no le alcanza.

Un mismo tajo **no puede golpear dos veces al mismo objetivo**: cada swing mantiene una lista
de objetivos ya impactados y se limpia al apagar la ventana.

### 4.6 La lanza y su animación

El pack no tiene animación de estocada. Se reusa `Punch_Jab`: un brazo extendido en línea
recta con la lanza en la mano derecha lee como una estocada. Es una decisión de compromiso,
no una solución ideal, y se comprueba con captura.

**Comprobado y corregido.** La primera captura con el agarre del gladius (`rotation.x = -0,35`
para las dos armas) sacó la lanza **hacia atrás y arriba**: alineación −0,62 con el frente del
personaje y la punta 1,8 m sobre la mano. La causa es que el eje de `DEF-hand.R` cambia con la
animación, y el giro del agarre vive en la instancia del `MeshInstance3D`, no en el hueso.
Medido en el frame del impacto, durante `Punch_Jab` el frente del personaje cae sobre el **+Y
de la mano** (coseno 0,87) y solo −0,35 sobre su +Z.

El agarre pasó a ser un número por arma (`Weapon.GRIP_ROT_X`) y se calibró midiendo, no a ojo:

| `rotation.x` | Alineación en reposo | Punta en reposo | Alineación en el golpe |
|---|---|---|---|
| −1,5708 (−90°) | 0,84 | 1,29 m **bajo el suelo** | 0,98 |
| −1,05 | 0,97 | 0,35 m bajo el suelo | 0,97 |
| −0,80 | 0,98 | 0,23 m sobre el suelo | 0,78 |
| **−0,92 (elegido)** | **0,98** | **a nivel del suelo** | **0,90** |

Se descarta el −90° puro aunque da el mejor golpe: el arma se ve sobre todo en reposo, y una
punta clavada en el terreno es un defecto permanente. Con −0,92 la lanza queda horizontal en
reposo y a 0,90 en la estocada, y la captura confirma que lee como una estocada.

La medida la hace `tools/shot.gd --spear` y `--attack`, que imprimen el coseno entre el eje del
arma y el frente en dos fotogramas (reposo e impacto).

### 4.7 Antorcha y arma

Ambas van a la mano derecha (`DEF-hand.R`). **Regla:** la antorcha se reubica a
`DEF-hand.L` de forma permanente. Así la luz nocturna y el arma conviven sin secuestrarse el
hueso. `Idle_Torch_Loop` sigue usándose de noche, pero solo cuando no hay un ataque en curso.

### 4.8 NPCs hostiles (`hostile_npc.gd`)

Máquina de estados simple, con las decisiones atadas al temporizador que ya existe
(`DECISION_INTERVAL = 0,6 s`), no por frame:

| Estado | Entra cuando | Hace |
|---|---|---|
| `PATROL` | inicio | patrulla entre waypoints (código actual) |
| `AGGRO` | Rito a ≤ 22 m **y** raycast de visión limpio | gira hacia Rito, memoriza objetivo |
| `CHASE` | aggro activo y distancia > 1,9 m | corre a 3,4 m/s hacia Rito, raycast de obstáculos |
| `ATTACK` | distancia ≤ 1,9 m y enfriamiento listo | `Sword_Attack` + ventana de daño (12) cada 1,4 s |
| `STUN` | recibe un golpe | `Hit_Chest`, 0,35 s sin actuar, fogonazo en el material |
| `DEAD` | vida ≤ 0 | `Death01`, cuerpo inerte, se libera a los 8 s |

Pierde el aggro si Rito se aleja más de 40 m. El ataque del NPC usa el mismo
`attack_volume` que el jugador, cambiando las máscaras.

Vida del NPC: 60 HP. Con el gladius (34) son 2 tajos; con la lanza (46), 2 estocadas.

El NPC hostil empuña un gladius: la **misma malla** compartida que el del jugador (un recurso,
no cuatro), pero con material propio, y montada en su `DEF-hand.R`. Sin arma el tajo se ve
mudo.

### 4.9 Muerte y reaparición del jugador

- Vida: 100 HP. Golpe de NPC: 12.
- Al llegar a 0: `Death01`, se bloquean input y locomoción, la cámara se queda donde está.
- A los 1,5 s: teletransporte al `spawn_point` del mundo, vida llena, 2 s de
  invulnerabilidad (para no morir encima del mismo enemigo).
- El contador de bajas **no** se reinicia.

### 4.10 HUD

En `hud.gd`, que ya existe: una barra de vida arriba a la izquierda (dos `ColorRect`, uno de
fondo y uno de relleno, ancho proporcional a la vida) y un contador `Bajas: N` debajo. Se
actualizan por señal, no por `polling`.

## 5. Input

| Acción | Tecla / botón | Notas |
|---|---|---|
| `attack` | clic izquierdo | **Conflicto a resolver**: hoy el clic izquierdo captura el puntero. Regla: si el puntero no está capturado, el clic captura; si ya lo está, el clic ataca. |
| `heavy_attack` | clic derecho | la **misma** animación con daño ×1,25 y cadencia ×1,3. No es un segundo movimiento ni se puede encadenar durante el bloqueo |
| `weapon_1` | tecla `1` | gladius |
| `weapon_2` | tecla `2` | lanza |
| `toggle_mouse` | `Esc` | ya existe |

`Q` sigue siendo calidad de render; no se reutiliza.

## 6. Rendimiento

Presupuesto heredado y medido: 42,0 FPS en Chrome con la GT 640 real, 100 draw calls,
145.780 triángulos, escala 0,75, shader ligero.

Coste nuevo esperado: 4 NPCs con esqueleto (skinning + 4 AnimationPlayer), 2 armas (una
visible), 5 volúmenes `Area3D` apagados casi siempre.

**Regla de aceptación:** con el combate activo, el navegador debe mantener **≥ 36 FPS**
(es el 42,0 menos el 15 % de ruido que tiene esta GPU). Si no se cumple, en este orden:
1. Bajar a 3 NPCs.
2. Desactivar el `AnimationPlayer` de los NPCs a más de 45 m del jugador.
3. Quitar el esqueleto a los NPCs y volver a la malla estática, con muerte por derribo
   (rotación + desvanecido) en lugar de `Death01`.

### 6.1 Medido con el combate ya montado

Ningún paso del repliegue tuvo que aplicarse.

| | Base sin combate | Con combate | Muestra |
|---|---|---|---|
| Chrome + GT 640 real (mediana) | 42,0 FPS | **40,0 FPS** | 3 corridas: 38,0 / 40,0 / 42,0 |
| Banco nativo (`bench.tscn`, variant light) | 60,0 | **60,0** | 3 corridas, peor frame 20 ms |
| Draw calls | 100 | 103 | puente `__rito` |
| Triángulos | 145.780 | 145.714 | puente `__rito` |
| `.pck` | 14,39 MiB | 14,42 MiB | export |

El delta neto de todo el subsistema son **3 draw calls** y 2 FPS. No lo atribuyo a batching:
cuatro mallas esqueletizadas no se agrupan solas en Godot. Lo que sí está medido es que las
cuatro instancias comparten el recurso `.glb` importado, y el `.pck` creció solo 0,03 MiB.
El skinning es el coste candidato, y en esta GPU se paga dentro del ruido de la propia
medición (±4 FPS entre corridas).

El `min=2,0` de la primera corrida es el arranque del WASM; las siguientes dieron `min` de
25 y 21. El umbral se evalúa sobre la mediana, no sobre el mínimo.

## 7. Manejo de errores y casos límite

- Atacar estando muerto: ignorado.
- Daño después de la muerte: no re-emite `died`.
- Un tajo contra dos NPCs a la vez: ambos reciben (es un área, no un raycast).
- Matar a un NPC mientras ataca: su volumen se apaga al morir.
- Morir el jugador a mitad de un ataque: se corta el bloqueo y entra el estado `dying`.
- Reaparecer dentro de un enemigo: 2 s de invulnerabilidad.
- Que un nombre de animación no exista (la trampa del sufijo `_Loop`, que ya mordió en v1):
  se resuelve por lista de candidatos y, si ninguno existe, el ataque **sigue funcionando**
  con la ventana de daño y solo pierde la animación. Nunca se corta el juego.

## 8. Verificación

### 8.1 Test determinista `tools/combat_test.gd` (headless, asserts reales)

1. `Combatant` de 60 HP + 60 de daño → `died` emitido **una** vez, `is_alive()` falso.
2. Daño extra después de morir → ningún `died` adicional.
3. Ventana de ataque a 2,0 m de un objetivo → impacta; a 3,6 m → no impacta.
4. El mismo swing no golpea dos veces al mismo objetivo (20 fotogramas de solape, un solo
   impacto), y el swing siguiente **sí** vuelve a golpearlo.
5. Alcance por arma: gladius impacta a 2,0 m y falla a 3,6 m; lanza impacta a 3,0 m y falla a
   4,6 m.
6. La ventana abre y cierra: con la apertura retrasada al 0,9 de un clip de 10 s no hay daño
   en 30 fotogramas, y una ventana de duración cero no golpea.
7. Muerte del jugador → a los 1,5 s la vida es 100 y la posición es el `spawn_point`.
8. Los 6 nombres de animación usados se resuelven a algo no vacío.

El arnés además **cuenta los checks ejecutados** y falla si el recuento no cuadra. Sin esa
guarda, un error de runtime dentro de un `await` aborta el test en seco y el informe sale en
verde con tres de siete casos sin ejecutar: así se colaron los tres primeros tests de
`AttackVolume`.

El `Area3D` no usa `body_entered`. Se barre `get_overlapping_bodies()` cada frame dentro de
la ventana, por dos motivos medidos: un NPC que ya está pegado cuando la ventana se abre
nunca "entra", y reencender `monitoring` no vuelve a reportar los cuerpos que ya estaban
dentro, así que el segundo swing del mismo combate no golpeaba a nadie. La puerta es la
ventana de daño, no el `monitoring` de física.

### 8.2 Banco de pruebas

`tools/bench.tscn` con las 3 poses de siempre, antes y después, mediana de 3 corridas y
umbral de aceptación del 15 %.

### 8.3 Navegador

- `tools/web_bench.py` (ya existe, aborta si el renderer es software) → FPS reales con la
  GT 640.
- `tools/verify_web.js` se amplía: `window.__rito` pasa a incluir `hp`, `weapon`, `kills` y
  `alive`. Se comprueba que `hp` baja tras un golpe de NPC y que `kills` sube al matar.

### 8.4 Capturas

`tools/shot.gd` con una pose nueva `--attack`: Rito a mitad del tajo con el gladius, y otra
con la lanza, para juzgar visualmente el §4.6.

### 8.5 Resultado medido

- **Arnés determinista:** `TEST failures=0 checks=37`. La guarda de recuento no es decorativa:
  sin ella, tres tests de `AttackVolume` abortados por un error de runtime dieron `failures=0`.
- **Banco nativo:** `median_avg=60,0` en tres corridas, peor frame 20 ms.
- **Extremo a extremo en el mundo real** (`tools/shot.gd -- --fight`, 10 s junto a un NPC):
  el NPC pasa a `ATTACK`, se detiene a 1,87 m y conecta **7 golpes** a la cadencia de 1,4 s
  (Rito baja de 100 a 16 HP). Rito se gira y lo mata: `hp_npc=0`, `estado=DEAD`, `bajas=1`.
- **Navegador:** `RESULT PASS` en los 9 checks, `ERRORS []`. El puente expone
  `hp=100, weapon=0, kills=0, alive=true`, la tecla 2 cambia a lanza y la 1 devuelve al
  gladius. La carga hasta `ready` sigue en 2 s.
- **Rendimiento:** 40,0 FPS de mediana con la GPU real; ver §6.1.

Un detalle que cambió el diseño: `--fight` midió primero `distancia_min=0,00` y **cero
golpes**. El NPC se colaba dentro del jugador con la inercia de la persecución y el volumen,
montado a 1,9 m hacia delante, le pasaba de largo. Sin esa medida el ataque hostil se habría
dado por bueno porque el código compila y el estado llega a `ATTACK`.

## 9. Orden de trabajo

1. **Medir antes de codificar**: volcar del `AnimationPlayer` importado los nombres exactos y
   la duración de `Sword_Idle`, `Sword_Attack`, `Punch_Jab`, `Hit_Chest`, `Death01` y
   `Walk_Loop`. Las ventanas del §4.5 dependen de estas duraciones.
2. `combatant.gd` + test determinista (es la pieza que todo lo demás usa).
3. `weapon.gd` + `weapons_holder.gd` + reubicar la antorcha a la mano izquierda.
4. Bloqueo de un disparo en `rito.gd` + `rito_combat.gd` + ataque con el gladius.
5. `attack_volume.gd` y las capas de colisión.
6. HUD de vida y bajas.
7. `hostile_npc.gd` con aggro, persecución y ataque.
8. Muerte y reaparición del jugador.
9. Lanza + captura para juzgar `Punch_Jab` como estocada.
10. Banco de pruebas y `web_bench.py`; aplicar la regla de §6 si hace falta.
11. Actualizar la spec v1 (§14) y commitear.

## 10. Fuera de alcance

Botín, experiencia y niveles, partículas de sangre, sonido, bloqueo/parry/esquive, más de dos
armas, enemigos a distancia, NPCs que reaparecen, y cualquier cosa que necesite assets
descargados de fuera del proyecto.
