# Rito Cero — núcleo de misiones y progreso (Proyecto 1 de "de peón a emperador")

- **Fecha:** 2026-11-04
- **Proyecto:** `C:\Users\USUARIO\Documents\rito-cero-` (Godot 4.7.2, export web, renderer Compatibility)
- **Depende de:** `docs/superpowers/specs/2026-11-02-rito-cero-combate-design.md` (combate ya integrado), `2026-11-02-rito-cero-web-design.md` (v1)
- **Diagrama de referencia:** `docs/diagrams/rito-cero-loop.mmd` / `.png`

---

## 1. Objetivo

Convertir Rito Cero en un juego con bucle: **el sistema ofrece misiones de acción, el
jugador las acepta y ejecuta en el mundo abierto, cobra recompensas, sube de nivel y
desbloquea un árbol de tecnología anacrónico con monedas romanas.** Es el primer corte
del arco "de peón a emperador": sin historia, sin esposas, sin imperio — solo el bucle
que hace que volver a entrar al juego tenga sentido.

Criterio de éxito: en el build web, el jugador puede abrir el registro de misiones,
aceptar "Masacra a los bandidos del campo", seguir el marcador, completarla, ver
moneda/comida/XP/arma en su inventario, equipar el arma con efecto real en combate,
curarse con comida y agua, subir de nivel, gastarse los denarios en el árbol de
tecnología y recibir botín aleatorio — todo en un ciclo completo, sin errores de
consola y sin que el navegador baje de **36 FPS** (mediana, misma regla que el combate).

## 2. Decisiones ya tomadas por el usuario

| Decisión | Elección | Consecuencia |
|---|---|---|
| Qué es lo divertido | **Misiones de acción** (no gestión de familia) | El núcleo del juego es pelear por encargos, no dialogar |
| Quién da las misiones | **El sistema**, no NPCs mandando | Sin personajes-mandantes; tablero + eventos |
| Tipos de misión | Masacrar bandidos, defender una ciudad | Reutiliza `hostile_npc.gd` para los enemigos |
| Enfoque de construcción | **C: tablero desde el día 1 + eventos de mundo como capa fina** | Más alcance que A; si el evento se descontrola en pruebas, se recorta al tablero |
| Recompensas | Comida y agua (curan + progreso pequeño), armas romanas **equipables**, monedas romanas, botín absurdo (pizza, helado, sal…) | Inventario mínimo con cantidades |
| Progresión | XP → nivel → **mejores recompensas** (rango de botín) | Curva de XP y tablas de botín escalonadas |
| Árbol de tecnología | Gasta **monedas romanas**; desbloquea **tecnología anacrónica** (más agua, más comida, fabricar sal…) y armas romanas | Moneda: denarios; el humor es parte del diseño |
| Arsenal (sesión aparte, mismo día) | gladius, pilum y spatha gratis desde el inicio con menú (Tab/B) | El árbol de tecnología ya no vende spatha; pasa a desbloquear **Puñal** e **Hispaniense** y a mejorar el gladius |
| Modelos 3D | Se construye todo dentro del juego (maniquí Quaternius + vestuario por código, como Rito) | **Cero gasto en IA**; Tripo descartado (cuenta sin créditos) |

## 3. Arquitectura

### 3.1 Módulos nuevos

```
scripts/missions/
├── mission_system.gd      autoload-like vía main.gd: estado de misiones, registro, XP, nivel, denarios
├── mission_board.gd       UI del tablero (menú de misiones disponibles + en curso) y panel de recompensa
├── mission_data.gd        definiciones de misiones como datos (tipos y generadores)
├── objective_marker.gd    columna de luz + punto en minimapa del objetivo activo
├── world_event.gd         eventos de mundo: campamento de bandidos / ciudad bajo asedio (capa fina)
├── inventory.gd           dict item → cantidad; curación; botín; denarios
├── loot_table.gd          tablas de botín escalonadas por nivel
└── tech_tree.gd           datos del árbol + efectos aplicados

scripts/ui/
├── xp_bar.gd              barra de XP + nivel (integrada en hud.gd o junto a la barra de vida)
├── tech_menu.gd           UI del árbol (panel de Control, toggle con tecla)
└── inventory_menu.gd      panel para usar comida/agua y ver denarios/botín (tecla I)
```

### 3.2 Datos de misión (forma)

```gdscript
{
  id: "bandit_purge_01",
  type: "bandit_purge",          # "city_defense" | "world_event_bandits" | ...
  title: "Masacra a los bandidos del campo",
  brief: "El pretor ofrece denarios...",
  targets: 4,                    # bandidos a eliminar (o oleadas si defense)
  xp: 60,
  coins: [30, 60],               # rango de denarios
  loot_tier: 0                   # se resuelve con loot_table(level)
}
```

El sistema mantiene: misiones disponibles (lista fija que se renueva al completar una
con un cooldown de 1–2 min), misión activa (una a la vez), progreso parcial.

### 3.3 Los dos tipos de misión jugables

**Masacre de bandidos** (`bandit_purge`)
- Al aceptarla se spawnean 3–5 bandidos en la zona de la columna rota
  (`hostile_npc.gd` con vida/daño escalados por nivel de Rito), marcados con tinte
  rojizo en el material. Objetivo: "bandidos restantes: N".
- Completarla: todos los bandidos **de la misión** muertos (los 4 NPCs ambientales
  del valle no cuentan). Recompensa automática.

**Defensa de la ciudad** (`city_defense`)
- Punto de defensa: el **pórtico de las ruinas** ("el templo/puerta de la ciudad"),
  con los bandidos atacando desde los alrededores. La cueva sigue siendo decorativa y
  no participa en misiones.
- Oleadas hasta sobrevivir 3 (4/6/8 enemigos por oleada).
- Si Rito muere: misión fallida (reaparece en spawn, sin recompensa, misión vuelve a
  estar disponible). Si sobrevive: recompensa mayor.

**Eventos de mundo** (`world_event`) — capa fina del enfoque C
- Un prado ya existente muy cerca del pórtico spawnea un campamento de bandidos
  ~3 min tras arrancar (timer), marcado en el minimapa como "actividad".
- Atacar al campamento o estar cerca lo convierte en misión `bandit_purge` sin
  pasar por el tablero.
- Si el evento no se toca, expira a los 15 min y reaparece más tarde.
- **Recorte permitido:** si en las pruebas el evento da problemas de estabilidad o
  rendimiento, se elimina y la entrega sigue siendo el tablero + los dos tipos.

**Reglas comunes**
- Bandidos de misión = spawns nuevos con tinte rojizo; durante una misión se
  despausan/desactivan los ambientales a más de 50 m para no pagar su skinning.
  Se mide en el banco.
- Sitios fijos, nada aleatorio en v1.

### 3.4 Inventario, curación y economía

- Inventario `item → cantidad`: `panis` (comida), `aqua`, `sal`, `denarii` (moneda),
  `pizza` y `gelatum` (helado), más las armas ganadas.
- **Curación:** `aqua` +20 HP, `panis` +35 HP (efectos al usar), sin hambre ni sed.
  **Sal** (requiere la tecnología Salazón) es un consumible: usar `panis` con `sal` en
  el inventario añade **+15 HP fijos** después del multiplicador de Molino y consume
  1 sal. Botín absurdo curativo: `pizza` +25, `gelatum` +15.
  Números exactos: panis 35 · panis+Molino 52 · panis+sal 50 · panis+Molino+sal 67.
- **Las misiones nunca regalan armas de la Armería**: ese árbol es el único camino
  para spatha / puñal / hispaniense. Las misiones dan denarios, consumibles y botín.
- **XP:** curva `xp_para_nivel(n) = 100 * n^1.5` (cap nivel 20). Al subir de nivel:
  +5 HP máx, y el rango del botín mejora (`loot_tier = clampi(level / 5, 0, 2)`; bandas 1-4 / 5-9 / 10+).
- **Denarios:** denarios de Malta (denarii) como float/int. Sueldo por misión según
  rango de la tabla, con bonus por nivel.
- **Botín absurdo:** tabla de 8–12 items inútiles-útiles con pesos (sal, pizza,
  gelatum, mapamundi roto, águila de juguete…). Es el humor del juego; no hacen nada
  o curan un pico.

### 3.5 Árbol de tecnología (monedas, no XP)

Tres ramas cómicas; coste en denarios, efectos pasivos permanentes:

| Rama | Denarios | Efecto |
|---|---|---|
| Pozo de agua | 60 | +25 % `aqua` en recompensas de misión |
| Acequia | 60 | +25 % `panis` en recompensas de misión |
| Salazón | 80 | Desbloquea **Sal**: creación 1 `panis` + 10 den → 1 `sal`, y su uso (+15 HP extra al usar panis). La sal aparece también en botín desde nivel 6. Sin Salazón no hay sal |
| Granero | 100 | Los `panis` de misión suben a +1 cantidad siempre |
| Molino de agua | 100 | `panis` cura +50 % |
| Bodega de nieve | 120 | `gelatum` cura x2 y nunca "caduca" (flavor) |
| Armería romana I | 80 | Desbloquea **puñal** (22 daño, alcance 1,6 m, cadencia 0,35 s; nuevo item de catálogo) |
| Armería romana II | 150 | Desbloquea **gladio hispaniense** (48 daño, alcance 2,4 m, cadencia 0,65 s; nuevo item de catálogo) |
| Armería romana III | 250 | Mejora **gladius inicial** +30 % daño permanente ("templado de Toledo") |

El árbol se abre con tecla **T**. Un nodo = un `Button`; comprada = estado guardado.

### 3.6 Armas

El catálogo ya existe (`scripts/combat/weapon.gd`): **gladius** (melee), **pilum**
(lanzable) y **spatha** (melee), con menú de arsenal propio (Tab/B) y HUD con fila de
armas. Las armas del árbol no pasan por otro sistema: se agregan como filas nuevas del
catálogo (`puñal`, `hispaniense`) y la mejora del gladius es un `damage_mult`
multiplicativo guardado en la partida y aplicado en `WeaponsHolder.current_damage()`.
El menú de arsenal y las teclas 1-6 pintan lo que haya en el catálogo. Ningún arma del
árbol se regala en misiones.

### 3.7 Guardado (llamada de 1 archivo)

Web sin recarga conserva: XP, nivel, denarios, inventario, nodos de tecnología, y
**mejor racha** = número máximo de misiones completadas de forma consecutiva sin
morir ni abandonar (se muestra en el menú de misiones; se reinicia al morir o
abandonar durante una misión). Se guarda en `localStorage` mediante `JavaScriptBridge`
(patrón ya probado en el proyecto para el FPS puente) y se recarga en `_ready`.
Un solo `save_game.gd`, serialización a JSON. **La misión activa y su progreso no se
guardan**: al recargar, la misión vuelve a "disponible" sin penalización (equivale a
abandonarla). **Si se cuela como problema en la prueba web, es el primer recorte
permitido.**

## 4. HUD y presentación

- Barra de XP (fina, ámbar) debajo de la de vida + número de nivel.
- Denarios en la esquina superior izquierda (junto a la vida), icono de moneda.
- Contador de misión activa ("Bandidos restantes: 3") bajo el título.
- Marcador de objetivo: columna de luz vertical + punto dorado en el minimapa.
- Menús: **Tablero de misiones** (tecla `J` o botón "Misiones" en HUD), **Inventario**
  (`I`), **Armería/Árbol** (`T`). Todos `Control` 2D en pausa de juego suave (el mundo
  no se detiene, pero el input de combate se ignora mientras un menú está abierto).

## 5. Restricciones (heredadas)

- Renderer Compatibility / WebGL2; sin sombras dinámicas; sin GI.
- Presupuesto: no subir el triángulo medio más de lo inevitable (reutilizar mallas de
  `weapon.gd` y maniquí; bandidos = mismos enemigos).
- **Regla de aceptación:** ≥ 36 FPS de mediana en Chrome + GT 640 real, misma regla
  que el combate; banco nativo `bench.tscn` sin regresión > 5 %.

## 6. Verificación

1. **Test determinista** `tools/progression_test.gd` (headless, asserts reales):
   - Completar un `bandit_purge` otorga XP/denarios/botín exactamente una vez.
   - XP suficiente → nivel sube, HP máx crece, `loot_tier` mejora.
   - `aqua` +20 HP, `panis` +35 HP, panis+Molino 52 HP, panis+sal 50 HP,
     panis+Molino+sal 67 HP — exactos.
   - Sal: sin Salazón, crear/usar sal está bloqueado; con Salazón, 1 `panis` + 10
     den → 1 `sal` y el +15 se aplica y consume la sal.
   - Las misiones completadas nunca otorgan spatha/puñal/hispaniense (se chequea la
     tabla de recompensas).
   - Las armas del árbol en `WeaponsHolder.current_damage()` aplican `damage_mult` si
     el gladio está templado (34 → 44,2).
   - Guardado/recarga: serializar → parsear → mismos valores.
2. **Bridge web** (`tools/verify_web.js` + `__rito`): añadir `xp`, `level`, `coins`,
   `active_mission`, `inventory` (pequeño). 9 checks actuales + 3 nuevos.
3. **Banco** `tools/bench.tscn` y `tools/web_bench.py` antes/después; umbrales de §5.
4. **Capturas** (`tools/shot.gd`): pose con spatha y con puñal si difieren
   visualmente; marcador de misión visible en captura de mundo.

> **S6 EJECUTADO (T14, 2026-11-07, HEAD 21f8dd5 + recortes):**
> - `progression_test.gd` (headless): **TEST failures=0 checks=263** (tras los dos recortes). `combat_test.gd`: **TEST failures=0 checks=86**.
> - Bridge web (`verify_web.js`): **15/15 PASS** antes y despues de los recortes. Unico error persistente: `Can't open file at path "res://assets/models/colosseum.glb"` (GLTF, no rompe checks).
> - Banco nativo GT 640 real (ventana, `--rendering-driver opengl3 --variant 1`, 3 corridas): **BENCH-SUMMARY median_avg=60.0** (poses 60.0/60.0/60.0/ragdoll 60.0; p5 55-59; draws 146-153; tris 122k-175k). Sin regresion >5% frente a base historica 60.0. Headless sin GPU: draws=0 median 144.9, no representativo.
> - Web (`web_bench.py`, ANGLE D3D11 GT 640, build re-exportado en HEAD): **NO CUMPLE el umbral S5**. Mediana **26.0** (26.0, 27.0; `--headed` 29.0), min 3-14 / max 29-40. Recorte 1 (columna del marcador desactivada) -> 26.0. Recorte 2 (evento Task 12 no instanciado) -> 27.0. Ambos aplicados y medidos; ninguno recupera 36 porque en spawn (sin mision) columna y evento ya estan inactivos (draws 142-143, tris 146k-150k). Deficit no explicado por marcador/evento: la escena base en web ya no llega a 36 en este entorno (base historica 40.0 con combate). No se finge ningun numero.
> - Capturas (ventana opengl3 `--variant 1`, fps 59-60): **generadas** en raiz: `shot_board.png` (tablero_abierto=true), `shot_mission.png` (activa=true; sin columna 3D por recorte, HUD+minimapa), `shot_tech.png` (tech_abierto=true). En headless puro `shot.tscn` se cuelga (sin dibujo): solo corre con ventana.

## 7. Manejo de errores y casos límite

- Curación a HP lleno: no consume el ítem.
- Usar un ítem no poseído: ignorado, aviso en HUD ("sin comida").
- Muerte durante `city_defense`: misión falla, sin recompensa; el menú de muerte ya
  existe del combate (reaparición en 1.5 s) — la misión queda disponible otra vez.
- Compra de tecnología sin denarios suficientes: botón deshabilitado + tooltip.
- Dos misiones activas a la vez: imposible (solo una activa); aceptar una nueva con
  otra en curso: el tablero pregunta "¿abandonar la misión actual?" y si se acepta, la
  actual se abandona sin recompensa ni penalización.
- Botín en el límite de nivel (cap 20): XP se sigue acumulando pero no sube más
  (o "Nivel máximo").
- Evento de mundo mientras hay misión bandit_purge activa: el evento no spawnea
  (evita zonas duplicadas); vuelve al expirar el temporizador.
- localStorage lleno o bloqueado (incógnito): guardado falla en silencio con un
  `push_warning`; el juego sigue y el menú indica "Guardado no disponible".

## 8. Fuera de alcance (proyecto 1)

- **Las tres esposas** y sus arcos (`casa`, negocios, bodas) — proyecto 2.
- **Escalera al imperio** (rango, historia, final emperador) — proyecto 3.
- **Audio** — se pospone a presentación (proyecto 4).
- Multijugador, más tipos de misión (escolta, caza, encargo romano…), craft de armas,
  dificultad seleccionable.
- Guardado en servidor; partidas múltiples.

## 9. Orden de trabajo

1. `inventory.gd` + `loot_table.gd` + test determinista de inventario/curación.
2. `mission_system.gd` (estado, XP, nivel, denarios) + test de progresión.
3. `mission_data.gd` + `bandit_purge` jugable + `objective_marker.gd` + HUD misión.
4. `mission_board.gd` (tecla J) + abandono/completar + recompensa visible.
5. `city_defense` (oleadas, punto de defensa, recompensa mayor, derrota = fallo).
6. Árbol de tecnología (datos + `tech_menu.gd`, tecla T) + efectos en recompensa/cura/armas.
7. Armas del árbol (puñal, hispaniense) como filas de `weapon.gd` + mejora del gladius (`damage_mult`).
8. Botín absurdo + notificación de loot.
9. `save_game.gd` (localStorage) + verificación web + bridge `__rito`.
10. Eventos de mundo (campamento temporal + expiración); recortable.
11. Banco + web_bench + actualizar specs + commitear. — EJECUTADO T14 (2026-11-07): nativo 60.0 median (sin regresion), web 26-27 FPS mediana (<36; recortes marcador+evento aplicados, sin recuperacion; ver §6). Capturas shot_board/mission/tech.png en raiz. Diagrama rito-cero-loop.png sin cambios.

## 10. Anti-goals

- Que el juego se vuelva un inventario de spreadsheet: cada ítem absurdo debe hacer
  *algo* pequeño o ser puro chiste visible, nunca requisito de progreso.
- Que el árbol de tecnología se lea como free-to-play: sin moneda real, sin esperas,
  sin economía estrangulada; los denarios salen generosos (la gracia es comprarlo
  todo en una partida).
- Romper la física del combate existente: las armas nuevas solo cambian números y
  malla, nunca el esqueleto ni las capas de colisión.
