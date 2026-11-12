# Rito Cero — pulido, contenido y meta-juego

- **Fecha:** 2026-11-11
- **Proyecto:** `C:\Users\USUARIO\Documents\rito-cero-` (Godot 4.7.2, GL Compatibility, Jolt Physics)
- **Estado:** propuesto para aprobación
- **Alcance:** fases A1 (pulido), A2 (contenido) y B (meta-juego), en ese orden.
- **Fuera de este plan:** personajes generados (doc `2026-11-09-rito-cero-personajes-generados-design.md`). La guardia/parry (doc `2026-11-11-combate-guardia-parry-design.md`) **ya está implementada y commiteada** (commits `90da1ef` y `a84da7b`, con `tools/guard_parry_test.gd`): este plan no la modifica; el bruto de A2.1 compone con su indirección `receive_attack`.

---

## 1. Intención

El juego funciona y corre a 60 FPS en nativo, pero tiene tres problemas que le quitan
"jugable y entretenido":

1. Bugs de UX conocidos: los menús blandos (J/T/I/B) se apilan, los cooldowns de misión no
   sobreviven a una recarga y la mejor racha se guarda pero no se ve en ninguna parte.
2. El contenido se agota en 2–3 encargos: dos tipos de misión en dos puntos fijos, un solo
   tipo de bandido y un jefe.
3. No hay meta después del nivel 20: el árbol de tecnología se acaba y no queda nada que
   hacer con la partida.

Este plan arregla lo primero (A1), añade variedad (A2) y da un objetivo a largo plazo (B).

## 2. Objetivos

**A1 — Pulido**
- Un solo menú blando abierto a la vez, con Esc cerrando el de arriba y la pausa por encima.
- Cooldowns de misión persistentes (sobreviven a la recarga y avanzan en tiempo real).
- Racha actual y mejor racha visibles en HUD y pausa.
- Spatha balanceada como sidegrade del gladius (sigue gratis).

**A2 — Contenido**
- Tres tipos de enemigo con comportamientos distintos: hondero (a distancia), bruto con
  escudo (bloquea de frente) y rápido (flanquea).
- Tres tipos de misión: escolta, recolección y contrarreloj.

**B — Meta-juego**
- Contratos escalables con mutadores desde nivel 10.
- Modo horda en el coliseo con `best_streak` como marcador entre jugadores.

## 3. No objetivos y anti-objetivos

**No objetivos**
- Modificar la guardia/parry ya implementada: este plan compone con ella donde el diseño lo
  pide (el bruto), pero no la toca.
- Personajes generados con rig propio (doc aparte).
- Rendimiento web: el objetivo de juego es escritorio. No se trabaja FPS web, pero tampoco
  se regresa el banco nativo (60 median) ni el baseline web (26–29).
- Multijugador, historia o diálogos.

**Anti-objetivos**
- Romper los tests existentes (~700 checks entre los 13 arneses) o el formato de guardado.
- Enemigos esponja: subir vida sin cambiar el patrón de pelea.
- Romper la guardia/parry implementada: el bruto compone con `receive_attack`, no la duplica.

## 4. Restricciones

- Godot 4.7.2, renderer Compatibility, Jolt. Sin assets externos nuevos: los enemigos reusan
  el maniquí (`Godot/AnimationLibrary_Godot_Standard.glb`), su esqueleto y sus animaciones.
- Tests deterministas headless (sin GPU), un arnés por feature, como el resto del repo. Los
  conteos existentes se mantienen; si un cambio de balance obliga a actualizar un número en
  `combat_test`, se actualiza documentándolo en el commit.
- Guardado: `SaveGame` lleva `version` y degrada cada campo a su default si el tipo no
  coincide; un save viejo (sin la clave nueva de cooldowns) carga sin cooldowns.
- Comentarios, textos de UI y mensajes en español, sin emojis (regla del proyecto).
- Los enemigos nuevos no añaden clips de animación: reusan los del maniquí con `_play`.

## 5. Enfoques considerados

| Enfoque | Descripción | Veredicto |
|---|---|---|
| A. Pulido + contenido incremental | Arreglar bugs pendientes y añadir variedad con la arquitectura actual | **Elegido, primero** |
| B. Meta-juego | Contratos con mutadores y horda en el coliseo con récords | **Elegido, después** |
| C. Co-op | Segundo jugador romano | Descartado: el usuario juega por turnos |
| Guardia/parry | Doc `2026-11-11` | Descartado en este plan: se aprueba aparte |
| Personajes generados | Doc `2026-11-09` | Descartado en este plan: workstream separado con preguntas abiertas |

El orden A1 → A2 → B es decisión del usuario: el pulido desbloquea todo lo demás, el
contenido necesita la base estable, y el meta-juego necesita el contenido para no repetirse.

## 6. Fase A1 — Pulido

### A1.1 Coordinador de menús

**Problema.** Cada UI blanda (tablero J, tecnología T, inventario I, arsenal B) es un
CanvasLayer que escucha su propia tecla en `_input`. Se pueden apilar (el propio README lo
lista como pendiente), y `ui_cancel` lo escuchan a la vez `pause_menu` y el menú abierto.

**Diseño.** `scripts/ui/menu_coordinator.gd` (Node, instanciado en `main.gd`):

- Cada menú blando expone `open()` / `close()` / `toggle()` / `is_open()` (ya existen); el
  coordinador los registra y **deja de escuchar su tecla** dentro de cada menú: la entrada se
  enruta aquí.
- Una tecla de menú abre su menú y cierra cualquier otro que esté abierto.
- Esc cierra el menú blando abierto; si no hay ninguno, `toggle()` de la pausa (la pausa
  sigue en `pause_menu.gd` con `PROCESS_MODE_ALWAYS`).
- Con la pausa abierta, las teclas de menú no abren nada.
- El arsenal (B) suelta el ratón: el coordinador respeta `set_capture_blocked` del jugador.
- El click en el dim del tablero sigue cerrando el tablero (comportamiento actual intacto).

**Tests.** `tools/menu_coordinator_test.gd` (sin GPU): abrir uno cierra el otro; Esc cierra
el blando; Esc sin blandos abre pausa; con pausa abierta J no abre; el coordinador no
interfiere con el cierre por click.

### A1.2 Cooldowns persistentes

**Problema.** `_cooldowns` vive en memoria con `Time.get_ticks_msec()` (se reinicia al
cerrar el juego) y `apply_save()` lo borra. Recargar salta la espera de 90 s.

**Diseño.** Los cooldowns pasan a tiempo unix (`Time.get_unix_time_from_system()`):

- `current_save()` añade `"cooldowns": {id: timestamp_unix_fin}`.
- `apply_save()` restaura y descarta los ya expirados (`timestamp_fin <= ahora`).
- `_in_cooldown` y el registro al completar/fallar/abandonar usan el reloj unix; el resto de
  MissionSystem no usa `_now()`, así que el cambio es local.
- Sin la clave en el save (partidas viejas) → sin cooldowns: degradación elegante, sin subir
  `SaveGame.VERSION`.

**Tests.** `tools/cooldown_test.gd`: completar → cooldown activo; recargar (apply_save con el
dict guardado) → sigue en cooldown; un timestamp pasado → disponible; save sin la clave →
sin cooldowns.

### A1.3 Racha visible

**Problema.** `current_streak` y `best_streak` se calculan, se guardan y emiten
`streak_changed`, pero ninguna UI los lee (verificado: cero coincidencias en `scripts/ui`).

**Diseño.**

- HUD: etiqueta `Racha: N · Mejor: M` en la columna izquierda (y ≈ 182, bajo el tracker de
  misión), alimentada por `streak_changed`.
- Pausa: bloque de estadísticas bajo el título (Nivel, Denarios, Racha actual, Mejor racha),
  refrescado al abrir.

**Tests.** `tools/streak_display_test.gd`: el HUD muestra la racha tras `streak_changed`; el
texto de pausa incluye el récord tras una racha guardada.

### A1.4 Spatha sidegrade

**Problema.** Hoy la spatha (58 de daño, 0,80 s) es estrictamente mejor que el gladius (34,
0,55 s): más DPS (72,5 vs 61,8) y más alcance (2,6 vs 2,2). being gratis, el gladius no tiene
razón de existir.

**Diseño.** Subir la cadencia de la spatha a 1,05 s (DPS 55,2). Sigue siendo el golpe brutal
(58 de burst) y el gladius gana por cadencia y combo (la ventana de 1,25 s encadena mejor con
0,55 s que con 1,05 s). Se mantiene gratis. Se actualiza el `summary` del catálogo si
hiciera falta.

**Tests.** Si `combat_test` asserta la cadencia de la spatha, se actualiza el número
documentándolo; si no, un check nuevo en el arnés de armas.

## 7. Fase A2 — Contenido

### A2.1 Tres tipos de enemigo

Subclases de `hostile_npc.gd`, como `boss_npc.gd`. Reusan maniquí, esqueleto, animaciones,
ragdoll y botín. Sin clips nuevos: `_play` con los nombres existentes.

**Hondero** (`scripts/npc/slinger_npc.gd`)
- Vida 35, mantiene 8–14 m (kiting: si el jugador se acerca a < 8 m, retrocede), lanza
  piedras cada ~2,5 s reusando `projectile.gd`.
- `Projectile.setup` **ya acepta `mask`** (verificado en `projectile.gd:34`): el hondero lanza
  con máscara 1 | 2 | 16 (terreno, Rito y moloso: las piedras chocan contra el terreno y no
  atraviesan colinas). `projectile.gd` solo gana una malla opcional (piedra en vez de pilum).
- Animación de lanzamiento: reusar `Punch_Cross` o `Sword_Attack_RM` (sin clips nuevos).
- Suelta botín al morir; cuenta como baja (`counts_as_kill = true`).

**Bruto con escudo** (`scripts/npc/brute_npc.gd`)
- Vida 140, persecución lenta (2,6 m/s), ataque pesado telegrafiado (windup 0,5 s: el volumen
  abre 0,5 s después de empezar la animación, como el diseño de guardia/parry pero sin parry).
- Escudo (malla procedural en `DEF-hand.L`): el daño melee frontal (producto escalar frente
  del bruto · dirección al atacante >= 0,15) se reduce ×0,25 y **no aturde**; por la espalda
  entra completo y el crítico ×2 sigue funcionando; el pilum ignora el escudo (daño completo).
- Construcción (verificado contra el código): la guardia/parry ya implementada (`rito.gd`,
  commits `90da1ef`/`a84da7b`) usa la indirección `receive_attack` de
  `AttackVolume._try_hit` (`attack_volume.gd:97`), que delega en el cuerpo si el método
  existe, y `begin_swing` **ya acepta `windup`** (`attack_volume.gd:44`). El bruto
  **implementa `receive_attack` en su propio nodo**: de frente aplica el ×0,25 y devuelve
  true (manejado); por la espalda devuelve false (daño normal). El pilum llama directo a
  `Combatant.take_damage` (`projectile.gd:110`), así que ignora el escudo sin cambios. Sin
  subclase de Combatant.
- "No aturde" de frente: `receive_attack` guarda la marca de tiempo del bloqueo y el
  `stagger()` del bruto la consulta (si el bloqueo fue hace < 0,4 s, ignora el aturdimiento
  del combo/crítico).
- El número de daño flotante muestra el daño del tajo (el volumen emite `landed` con el daño
  completo); el bloqueo se comunica con un sonido metálico nuevo y el destello del escudo.
- Idle con escudo: el bruto usa `Sword_Idle` como pose de reposo (existe en el maniquí).
- La velocidad de persecución (2,6 m/s) necesita una variable de instancia: hoy `CHASE_SPEED`
  es `const` en `hostile_npc.gd` (también hace falta para el mutador de velocidad de B.1).

**Rápido** (`scripts/npc/runner_npc.gd`)
- Vida 30, persecución 4,6 m/s, daño 8, cadencia 1,0 s, se acerca en diagonal (flanqueo
  simple: el punto de aproximación se desvía 45° y se corrige al entrar en rango).

**Composición por nivel.** `BanditCamp` y `DefenseSite` reciben una tabla: niveles 1–4 solo
bandidos; 5–9 añaden honderos (1 de cada 4); 10+ añaden brutos (1 de cada 6) y rápidos (1 de
cada 5). La transición es suave (redondeo hacia abajo) para no romper la purga de nivel bajo.

**Tests.** `tools/enemy_variety_test.gd`: vida y velocidades; el escudo reduce de frente y no
por la espalda; el pilum ignora el escudo; el hondero mantiene distancia y su proyectil
impacta al jugador; composición por nivel (sin brutos a nivel 3, con brutos a nivel 12).

### A2.2 Tres tipos de misión

Patrón del repo: plantilla en `MissionData.TEMPLATES` + script de sitio (como `BanditCamp` /
`DefenseSite`) + enganche en `main.gd` + progreso en `MissionSystem`.

**Escolta** (`escort`)
- Un NPC aliado con vida propia (80) recorre una **ruta fija de waypoints** de "ruinas" a
  "cueva" (no sigue al jugador: la escolta clásica); espera al jugador si se aleja más de
  25 m; 2–3 emboscadas spawnean al cruzar puntos de la ruta; los bandidos prefieren al
  escolta y cambian al jugador si este los ataca; si el escolta muere, la misión falla;
  cuando llega, completa. La muerte de Rito también falla (igual que la purga).
- Capas: el escolta va en su propia capa (32), incluida en la máscara del volumen de los
  bandidos (hoy `2 | 16`); el volumen del jugador no cambia (sin fuego amigo).
- Progreso: llegada (no bajas).

**Recolección** (`collect`)
- 6 suministros (pickup.gd con flag "quest": no disparan el botín de Progression, notifican
  a MissionSystem) dispersos alrededor de un POI; 3–4 bandidos hostigan mientras tanto.
- La muerte de Rito falla la misión (igual que la purga).
- Progreso: suministros recogidos.

**Contrarreloj** (`timed`)
- Purga de N bandidos (BanditCamp) con deadline de 90 s; el sitio emite el fallo al expirar;
  el HUD muestra la cuenta atrás.
- Progreso: bajas, como la purga.

**MissionSystem.** El `_active` gana `"kind"` y el progreso se generaliza:
`register_mission_kill()` se mantiene y llama a un nuevo `register_progress(n)`; al llegar a
`targets` completa igual que hoy. El reloj y la llegada los maneja el sitio (emite
`mission_failed` o completa por los caminos existentes).

**HUD.** `_refresh_mission_label` por tipo: "Provisiones: N/6", "Escolta: sigue al aliado",
"Contrarreloj: 45 s". El contador de contrarreloj se actualiza por señal del sitio (1 Hz),
no por sondeo.

**Tests.** `tools/new_missions_test.gd`: las 3 plantillas existen y escalan; la escolta falla
si el escolta muere y completa al llegar; la recolección completa al recoger los 6; el
contrarreloj falla al expirar; el progreso emite `mission_progress` con los números correctos.

## 8. Fase B — Meta-juego

### B.1 Contratos escalables

- Desde nivel 10, el tablero ofrece contratos: purga o defensa con mutadores **fijos** (vida
  enemiga +50 %, daño +25 %, velocidad +15 %) y recompensa ×1,5 sobre XP y banda de
  denarios (el botín no se multiplica). La racha sigue contando.
- Implementación: plantillas propias (`bandit_purge_contract`, `city_defense_contract`) para
  que el cooldown sea por plantilla (contrato y misión base no se pisan); los `mutators`
  viajan en la instancia de `mission_data.gd`; `hostile_npc` los aplica sobre `max_health`,
  `attack_damage` y una nueva variable de instancia `chase_speed` (hoy `CHASE_SPEED` es
  `const`); el sitio los aplica al spawn.
- Tablero: los contratos salen como filas extra; el host de filas gana scroll si no caben
  (hoy ~3 filas visibles).
- Tests: `tools/contracts_test.gd` (mutadores, recompensa ×1,5, nivel mínimo, cooldown
  independiente del contrato y de la base).

### B.2 Horda en el coliseo

- "Defensa del coliseo": oleadas infinitas en el POI del coliseo (reusa `defense_site.gd`
  con escalado procedural: +2 enemigos y +10 % de vida por oleada; el mutador de composición
  de A2.1 aplica desde la oleada 3).
- **Modo propio, no misión del tablero** (decisión del usuario): la horda no pasa por
  `MissionSystem._active` ni por `register_mission_kill` (que completa al llegar a `targets`).
  El sitio (HordeSite) lleva su estado y llama a MissionSystem para premiar y anotar:
  - Cada oleada superada: +1 a la racha (métodos nuevos de MissionSystem; emite la señal
    `streak_changed`, que ya existe) y recompensa pequeña (XP/denarios), sin cooldown.
  - Al morir Rito: fin de la partida, **sin permadeath** (Rito reaparece como siempre a los
    3,2 s, en el valle); banner de fin con "Oleadas superadas: N" y "Bajas de la partida: M"
    (contador por partida, aparte de las "Bajas" acumuladas del HUD); si N supera el récord,
    `best_streak` se actualiza.
- **La racha cambia de significado** (decisión del usuario): "aciertos consecutivos" — misiones
  completadas y oleadas de horda suman +1; la resetean fallar, abandonar o **morir** (la señal
  `died` del Combatant llega a `_reset_streak` de MissionSystem, también fuera de misión). Así
  `best_streak` es el marcador entre jugadores en ambos modos.
- Acceso: trigger en el coliseo (como la cueva) y/o entrada en el tablero.
- Tests: `tools/horde_test.gd` (oleadas escalan, la racha suma por oleada, la muerte cierra la
  partida sin impedir el reaparecer, el récord se guarda y se emite, la muerte resetea la racha
  fuera de la horda).

## 9. Verificación

- Todos los arneses del README (progresión, combate, combo, feel, audio, misión, pausa,
  pickup, jefe, cueva, input, esclavo, controlador) siguen en verde, más los nuevos.
- `tools/bench.tscn --variant 1` sin regresión > 5 % (baseline nativo 60 median).
- Guardado: un save de la versión actual carga sin cooldowns y sin errores.
- Capturas del HUD con la racha, del tablero con contratos y de la horda.

## 10. Riesgos

- **Doble toggle en menús**: si una UI sigue escuchando su tecla además del coordinador, se
  abre y cierra en el mismo frame. Mitigación: las UIs dejan de escuchar su tecla; test de
  coordinador.
- **Reloj de cooldowns**: cambiar de ticks a unix puede dejar cooldowns "futuros" si el reloj
  del sistema se atrasa; se acepta (es un juego local) y se documenta.
- **Escudo del bruto**: el bloqueo se decide en `receive_attack` del bruto (la indirección
  que ya usa la guardia del jugador); comprobar que el ragdoll, el stagger y el crítico por
  la espalda no se rompen, y que el pilum (que no pasa por `receive_attack`) hace daño
  completo.
- **Composición por nivel**: una tabla mal calibrada hace imposible la purga de nivel bajo;
  los tests fijan los límites por nivel.
- **Alcance**: A2.2 es la parte más invasiva (MissionSystem generaliza el progreso); si crece,
  se parte en sub-fases antes de tocar el meta-juego.

## 11. Criterios de aceptación

- A1: un solo menú blando abierto; el cooldown sobrevive a la recarga y avanza en tiempo
  real; la racha se ve en HUD y pausa; la spatha tarda 1,05 s entre golpes.
- A2: los tres enemigos se comportan de forma distinta y la composición escala por nivel; las
  tres misiones son completables y fallables por las vías descritas.
- B: hay contratos desde nivel 10; la horda del coliseo esconde oleadas infinitas y guarda el
  récord; la mejor racha se muestra entre partidas.