# Rito Cero — Núcleo de misiones y progreso Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que Rito Cero tenga un bucle jugable: el sistema ofrece misiones de acción, el jugador las ejecuta en el mundo abierto, cobra recompensas (comida/agua/denarios/armas romanas del árbol), sube de nivel y desbloquea tecnología anacrónica — sin degradar el rendimiento web.

**Architecture:** Un `MissionSystem` (Node) es el dueño único del estado (XP, nivel, denarios, racha, misión activa, inventario, tecnología). Los menús (Tablero `J`, Inventario `I`, Árbol `T`) son `CanvasLayer` sobre el HUD (capa 5) con capa 6. Las misiones spawnean bandidos nuevos en sitios fijos (Columna rota / Pórtico / Muro); la UI y el minimapa solo leen señales. Verificación determinista con `tools/progression_test.gd` (headless, asserts, recuento de checks) y web con el puente `window.__rito` ampliado.

**Tech Stack:** Godot 4.7.2-stable, GDScript, renderer Compatibility (WebGL2), export web, `JavaScriptBridge` para localStorage, `node --test` no aplica; el arnés es headless Godot.

**Spec:** `docs/superpowers/specs/2026-11-04-rito-cero-misiones-design.md`

## Global Constraints

- Godot 4.7.2-stable, renderer **gl_compatibility**; sin sombras dinámicas, GI ni ninguna luz nueva.
- **Ningún asset externo**: ni descargas, ni addons, ni modelos; armas/misiones/UI con primitivas y código.
- **≥ 36 FPS de mediana en Chrome con la GT 640 real** (base actual 40,0 FPS con combate; la regla del 15 % sigue). Banco nativo `tools/bench.tscn` sin regresión > 5 %.
- Comentarios, nombres y mensajes de commit en **español**, sin emojis. Números decimales con coma en pantalla.
- 1/2/3 ya son armas del arsenal (Tab/B); teclas nuevas: `J` tablero, `I` inventario, `T` árbol, `weapon_4`/`weapon_5`.
- La **misión activa y su progreso no se guardan**; al recargar vuelve a "disponible" sin penalización.
- Las misiones **nunca** otorgan las armas de la Armería; ese árbol es el único camino a puñal/hispaniense/gladius templado.
- Respetar el trabajo **sin commitear** que hay en el árbol (`scripts/world/structures.gd`, `assets/models/`, `tools/colosseum_*`, `addons/ziva_agent/`, `export_presets.cfg`, `docs/diagrams/`): **no tocar ni commitear nada de eso**; cada commit de este plan lista archivos concretos.
- Tras crear un script con `class_name`, refrescar el caché: `godot --headless --import` antes de ejecutar tests.

## Review Focus

1. **Recarga a mitad de misión** — el progreso se pierde silenciosamente; el jugador espera no perder la misión. → Task 3 (save) + Task 13 (web): el test de save/load exige que `active_mission` no se serializa y que al cargar queda `available_missions()` completa.
2. **Muerte o abandono duplica/pierde recompensas o racha** — morir en `city_defense` no debe pagar; abandonar resetea racha actual pero no mejor racha; completar paga exactamente una vez. → Task 4: tests con contadores exactos y asserts de `streak`.
3. **Consumir ítems con vida llena / sin ítems** — el juego no debe gastar comida con HP lleno ni con 0 en inventario. → Task 1: test de `use_consumable` en ambos casos.
4. **Bandidos de misión se quedan en el mundo tras terminar/abandonar** — completada o fallida, spawneados que quedan deben desaparecer (o, si se decide dejarlos, no deben contar). → Task 5: test de `BanditCamp` con 2 bandidos, uno muerto → un solo kill cuenta; `finish()` libera a los vivos.
5. **Evento de mundo irrumpiendo con una purga activa** — dos colas de bandidos mezcladas desordenan el contador. → Task 12: el timer del evento no spawnea con misión activa; el test lo fuerza.

---

## File Structure

```
scripts/missions/
├── inventory.gd         # class_name GameInventory extends RefCounted
├── loot_table.gd         # static: tier_for_level(level) -> int; roll(tier, rng) -> Dictionary
├── mission_data.gd       # definiciones + make_instance(template_id, level) con escalado
├── mission_system.gd     # class_name MissionSystem extends Node — estado y reglas
├── bandit_camp.gd        # Node3D: spawn de bandidos de purga (Columna rota / evento)
├── defense_site.gd       # Node3D: oleadas 4/6/8 en el Pórtico
├── world_event.gd        # Node: timer del evento de mundo (Muro)
└── tech_tree.gd          # datos del árbol (const NODES) + tech_menu.gd lo pinta

scripts/ui/
├── mission_board.gd      # CanvasLayer capa 6, tecla J
├── inventory_menu.gd     # CanvasLayer capa 6, tecla I
├── tech_menu.gd          # CanvasLayer capa 6, tecla T
└── (hud.gd modificado)   # barra XP, nivel, denarios, tracker de misión

scripts/save_game.gd      # class_name SaveGame extends RefCounted
tools/progression_test.gd # arnés headless determinista (patrón combat_test.gd)
```

`scripts/world/structures.gd` solo recibe la línea `poi_positions` al final del `setup()` (es el único toque al archivo con trabajo sin commitear — mínimo imprescindible, en Task 5).

---

### Task 1: Inventario y curación (`GameInventory`)

**Files:**
- Create: `scripts/missions/inventory.gd`
- Create: `tools/progression_test.gd` (arnés base + primeros tests)

**Interfaces:**
- Produces: `class_name GameInventory extends RefCounted` con `items: Dictionary`, `add(id: String, n: int = 1) -> void`, `remove(id: String, n: int = 1) -> bool`, `count(id: String) -> int`, `has(id: String, n: int = 1) -> bool`, `to_dict() -> Dictionary`, `from_dict(data: Dictionary) -> void`, `use_consumable(id: String) -> float` (heal directo sin multiplicadores; devuelve HP curados, 0 si no hay ítem), `CONSUMABLES := {"aqua": 20.0, "panis": 35.0, "pizza": 25.0, "gelatum": 15.0}` (Modelos: los multiplicadores los aplica el sistema, no el inventario).

- [ ] **Step 1: Write the failing test** en `tools/progression_test.gd` (copia la cabecera/patrón de `tools/combat_test.gd`: `extends SceneTree`, `_checks_run`, `_failures`, `EXPECTED_CHECKS`, `quit()`):

```gdscript
_test_inventory_add_remove_count()
_test_use_consumable_heals_and_consumes()
_test_use_consumable_at_zero_items_returns_zero()
```
Assertions exactas: tras `add("panis", 2)`, `count==2`; `use_consumable("panis")` devuelve 35.0 y `count==1`; segundo uso 35.0 y 0; tercer uso devuelve 0.0 y sigue en 0; `use_consumable("agua_inexistente")` devuelve 0.0; `has("panis", 2)` false→true tras add; `remove("panis", 3)` con 2 → false y no cambia; `remove` con 2 → true y 0.

- [ ] **Step 2: Run test to verify it fails** — Run: `godot --headless --path . --script tools/progression_test.gd` — Expected: FAIL con `GameInventory not declared/doesn't exist` (o parse error), checks del arnés > 0.

- [ ] **Step 3: Implement `GameInventory`** según Interfaces. `use_consumable` usa `CONSUMABLES`; id desconocido → 0.0 sin tocar nada.

- [ ] **Step 4: Run test to verify it passes** — mismo comando — Expected: `TEST failures=0 checks=<N>`.

- [ ] **Step 5: Commit**

```bash
git add scripts/missions/inventory.gd tools/progression_test.gd
git commit -m "Anade inventario de misiones con curacion determinista"
```

---

### Task 2: Tablas de botín (`LootTable`)

**Files:**
- Create: `scripts/missions/loot_table.gd`
- Modify: `tools/progression_test.gd`

**Interfaces:**
- Produces: `class_name LootTable` con `static func tier_for_level(level: int) -> int` (`clampi(level / 5, 0, 2)`, es decir bandas 1-4 / 5-9 / 10+) y `static func roll(tier: int, rng: RandomNumberGenerator) -> Dictionary` (ids → cantidades). Tablas exactas:
  - tier 0: `panis` 35 % ×1, `aqua` 35 % ×1, `denarii` 20 % ×15±5, `pizza` 5 % ×1, `gelatum` 5 % ×1
  - tier 1: `panis` 30 %, `aqua` 30 %, `sal` 15 % ×1, `pizza` 10 %, `gelatum` 10 %, `denarii` 5 % ×25±8
  - tier 2: `panis` 25 %, `aqua` 25 %, `sal` 20 %, `pizza` 10 %, `gelatum` 10 %, `denarii` 10 % ×40±10
  Denarios del botín van bajo la clave `denarii` en el diccionario de loot (el sistema los desvía al contador, no al inventario).

- [ ] **Step 1: Write the failing test** — `_test_loot_tier_for_level()` y `_test_loot_roll_bounds()`:
  - tier: niveles 1,4→0; 5,9→1; 10,20→2; nivel 0→0; nivel 99→2.
  - roll con `rng.seed = 12345` y 200 tiradas por tier: toda clave ∈ {panis,aqua,sal,pizza,gelatum,denarii}; `denarii` siempre dentro de su rango ([10..20],[17..33],[30..50]); cantidades ≥1; tier 0 nunca devuelve `sal`.

- [ ] **Step 2: Run to verify fail** — Expected: FAIL (clase/método inexistente).
- [ ] **Step 3: Implement** según Interfaces. `roll` devuelve dict; `denarii` como cantidad única (no acumula con drops duplicados: `dict[denarii] = dict.get(...) + x` con un solo roll posible por tirada).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade tablas de botin escalonadas por nivel"` con `scripts/missions/loot_table.gd tools/progression_test.gd`.

---

### Task 3: Guardado (`SaveGame`)

**Files:**
- Create: `scripts/save_game.gd`
- Modify: `tools/progression_test.gd`

**Interfaces:**
- Produces: `class_name SaveGame extends RefCounted` con `const KEY := "ritocero_save_v1"`, `static func save(data: Dictionary) -> bool`, `static func load() -> Dictionary` (`{}` si no hay o JSON inválido). En web (`OS.has_feature("web")`) usa `JavaScriptBridge` → `localStorage.setItem(KEY, JSON.stringify(data))` / `getItem`; si no, `FileAccess` en `user://ritocero_save_v1.json`.

- [ ] **Step 1: Write the failing test** — `_test_save_roundtrip_and_partial_data()`: dict con `xp/level/coins/inventory/tech/best_streak/current_streak` (SIN `active_mission`) → `save` → `load` → mismos valores; `active_mission` inyectado en el dict de guardado → `load()` lo elimina (clave no permitida); JSON corrupto en el archivo (escribir `{invalid` a mano) → `load()` devuelve `{}` sin crash.

- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** según Interfaces; en web, el bridge puede devolver null → `save` false, `load` `{}`.
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade guardado de progreso en localStorage y disco"` con `scripts/save_game.gd tools/progression_test.gd`.

---

### Task 4: `MissionSystem` — estado, XP, nivel, denarios, rachas, recompensas

**Files:**
- Create: `scripts/missions/mission_system.gd`, `scripts/missions/mission_data.gd`
- Modify: `tools/progression_test.gd`

**Interfaces:**
- Produces: `class_name MissionSystem extends Node`. Señales (todas): `xp_changed(total: int, needed: int, level: int)`, `coins_changed(coins: int)`, `mission_started(mission: Dictionary)`, `mission_progress(current: int, goal: int)`, `mission_completed(mission: Dictionary, rewards: Dictionary)`, `mission_failed(mission: Dictionary)`, `mission_abandoned(mission: Dictionary)`, `inventory_changed()`, `streak_changed(current: int, best: int)`, `tech_changed(node_id: String)`.
- Métodos públicos (consumidos por menús/HUD/misiones):
  ```
  setup(rito: Rito, combat: RitoCombat, poi: Dictionary) -> void
  available_missions() -> Array[Dictionary]          # 3 entradas: bandit_purge, city_defense; la 3ª solo si no hay activa
  start_mission(template_id: String) -> bool         # false si ya hay una activa
  abandon_mission() -> void                          # racha actual → 0; la misión vuelve a estar disponible tras COOLDOWN (90 s)
  fail_mission() -> void                             # muerte; sin recompensa; racha → 0; cooldown 90 s
  complete_mission() -> void                         # cobra; racha+1; cooldown 90 s; botín + XP
  register_mission_kill() -> bool                    # devuelve true si era el último
  use_item(item_id: String) -> bool                  # curación con multiplicadores del árbol (ver abajo)
  craft_sal() -> bool                                # 1 panis + 10 den → 1 sal; requiere Salazón
  buy_tech(node_id: String) -> bool
  has_tech(node_id: String) -> bool
  gladius_damage_mult() -> float                     # 1.3 si Armería III, si no 1.0
  current_save() -> Dictionary                        # SIN active_mission
  apply_save(data: Dictionary) -> void
  is_mission_active() -> bool
  ```
- `mission_data.gd`: `const TEMPLATES := [...]` con `{"id":"bandit_purge","type":"purge","title":"Masacra a los bandidos del campo","brief":"El pretor ofrece denarios por limpiar el camino de bandidos.","xp":60,"coins":[30,60],"targets":4,"poi":"columna"}` y `{"id":"city_defense","type":"defense","title":"Defiende el templo","brief":"Bandidos marchan sobre las ruinas. Aguanta tres oleadas.","xp":150,"coins":[80,140],"poi":"ruinas"}`; `static func make_instance(id: String, level: int) -> Dictionary` que escala: `targets = 4 + level / 4` (solo purge), `xp = roundi(base * (1.0 + 0.15 * (level - 1)))`, `coins` con el mismo factor redondeados.
- Reglas fijas (del spec de 2026-11-04 + arsenal): nivel máx 20; `xp_needed(n) = int(100.0 * pow(float(n), 1.5))`; +5 HP máx al subir nivel (`rito.combatant.setup(100 + 5*(level-1))` sin revivir); tier botín `clampi(level / 5, 0, 2)`; monedas van al contador `coins`, no al inventario; streak: +1 al completar, 0 al morir/abandonar/fallar; `best_streak` persiste.
- Curación con árbol: normal `aqua` 20 / `panis` 35; Molino → panis 52; Salazón+sal: panis con sal = base(+Molino)+15 → 50 / 67; `gelatum` 15 / Bodega → 30; `pizza` 25; usar con HP lleno → no consume; con 0 ítems → false; curar por encima del HP máx → clamp.
- Pausa de ambientales en misión: al `mission_started`, los del grupo `hostiles` que NO estén en `mission_bandits` y estén a >50 m reciben `set_process_mode(PROCESS_MODE_DISABLED)`; al cerrar (complete/fail/abandon) se restaura `PROCESS_MODE_INHERIT`. Se mide en el banco.

- [ ] **Step 1: Write the failing test** — en el arnés, con un `MissionSystem` real dentro de la escena de test y un `Combatant` falso via `_make`:
  ```
  _test_xp_curve_and_level_up()      # needed L1 = int(100 * pow(1, 1.5)) = 100; L2 = int(100 * pow(2, 1.5)) = 282;
                                     # añadir 100 XP → level 2; max 20; +5 HP por nivel (inspect via Combatant.max_health)
  _test_mission_rewards_exactly_once() # start purge (targets simulados: register_mission_kill ×4) →
                                     # mission_completed UNA vez; rewards dict contiene xp/coins/loot;
                                     # segundo complete_mission() sin activa → no paga; coins incrementados exactos
  _test_fail_and_abandon_streaks()   # completar → streak 1 (best 1); abandonar → streak 0, best sigue 1;
                                     # fail tras completar → streak 0, best 1
  _test_heal_values()                # aqua 20, panis 35, panis+molino(tech) 52, panis+sal 50, panis+molino+sal 67,
                                     # gelatum 15 / Bodega 30, HP lleno no consume
  _test_sal_craft_and_use()          # sin Salazón: craft_sal false; con Salazón: 2 panis + 10 den → 1 sal;
                                     # use_item("panis") con sal aplica +15 y consume la sal
  _test_tech_purchase_gate()         # buy_tech sin denarios → false y coins intactos; con denarios → true, coins restan
  _test_gladius_templado()           # gladius_damage_mult() 1.0 → 1.3 tras Armería III
  _test_save_roundtrip()             # current_save() sin active_mission; apply_save restaura xp/level/coins/tech/best
  ```
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement `mission_data.gd` + `mission_system.gd`** según Interfaces. Nada de nodos de UI aquí; la señal es el contrato. Guardar `_bandits_remaining` internamente.
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade MissionSystem con XP, niveles, denarios y rachas"` con los 3 archivos.

---

### Task 5: Bandidos de misión y purga jugable (Columna rota)

**Files:**
- Create: `scripts/missions/bandit_camp.gd`
- Modify: `scripts/npc/hostile_npc.gd` (añadir `func set_tint(color: Color)` junto a `_body_material`), `scripts/world/structures.gd` (exponer `var poi_positions: Dictionary = {}` rellenado en `setup()` con `{"columna": broken_spot, "ruinas": portico_spot, "muro": wall_spot, "cueva": cave_spot}`), `scripts/main.gd` (instanciar `MissionSystem` y pasarlo; registrar `BanditCamp` al aceptar purga)
- Modify: `tools/progression_test.gd`

**Interfaces:**
- Consumes: `MissionSystem.start_mission/register_mission_kill/complete_mission/fail_mission`; `hostile_npc.gd` ya existe con `setup(data, center, angle, target)`.
- Produces: `class_name BanditCamp extends Node3D` con `static func spawn(parent: Node, center: Vector3, count: int, terrain: Terrain3D, system: MissionSystem, target: Node3D) -> Node3D` — crea `count` bandidos en anillo `radius 12` en `center` (Y = `terrain.get_data().get_height(center)` por bandido); cada bandido queda en grupos `hostiles` + `mission_bandits`; `_body_material.albedo_color = Color(1.35, 0.55, 0.45)` (tinte rojizo); cada `died` conecta con `camp._on_bandit_died` → `system.register_mission_kill()`; al llegar a 0 → `system.complete_mission()` y `queue_free()`; `finish()` externo → libera vivos sin recompensa.

- [ ] **Step 1: Write the failing test** — `_test_bandit_camp_spawn_and_kill_flow()`: spawn 3 en un `Terrain3D` null-safe (el test construye `center` manual y `get_height` devuelve 0 en fixture — pasar altura como parámetros explícitos `heights: Array[float]`? NO: el camping acepta `terrain` y lo usa solo para Y; en el test se pasa un stub con `get_data().get_height() -> 10.0`):
  - 3 bandidos aparecen, todos en ambos grupos; el tinte aplicado.
  - Matar 2 → `mission_progress` 2/3, misión sigue; matar el 3.º → `mission_completed` emitido una vez y camping liberado (o marcado para `queue_free` — comprobar con `is_instance_valid` tras frame).
  - `finish()` con 1 vivo → sin recompensa (`mission_completed` no emitido).

- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** según Interfaces + hook en `MissionSystem.start_mission("bandit_purge")` → pedir `poi_positions["columna"]` al mundo (vía referencia inyectada en `setup`) y spawnear el camp; inyectar `terrain` al `MissionSystem` en `main.gd` (`mission_system.setup(rito, combat, structures.poi_positions, world.terrain)` — añadir 4.º parámetro `terrain: Terrain3D` a `setup`; actualizar tests de Task 4 en consecuencia).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade purga de bandidos en la Columna rota"` con los 6 archivos.

---

### Task 6: Marcador de objetivo (columna de luz + punto en el minimapa)

**Files:**
- Create: `scripts/missions/objective_marker.gd`
- Modify: `scripts/ui/minimap.gd` (`func set_objective(position: Vector3) -> void` y `func clear_objective() -> void`; un `Polygon2D` dorado reposicionado en `_process` con la misma fórmula de flecha, clamp al mapa), `scripts/main.gd` (instanciar y moverlo), `scripts/missions/mission_system.gd` (emitir posición en `mission_started`/`mission_completed` — o el wiring externo desde `main.gd` con señal `mission_started`)

**Interfaces:**
- Produces: `class_name ObjectiveMarker extends Node3D` con `func set_target(world_pos: Vector3)` / `func clear()` — columna `CylinderMesh(0.8, 0.8, 20.0)`, `StandardMaterial3D` transparente ámbar (`emission = Color(1.0, 0.75, 0.25)`, `albedo = Color(0.95, 0.7, 0.2)`, `transparency = ALPHA`, `emission_enabled`, alpha 0.55), `no_depth_test = true` NO (mejor depth test normal para que el terreno la oculte), sin luces. Posición en `world_pos + Vector3(0, 10 + 1, 0)` anclada al suelo (Y desde `terrain.get_data().get_height`).

- [ ] **Step 1: Write the failing test** — `_test_marker_targets()`: instanciar marker, `set_target(Vector3(10, 0, 20))` → `global_position == Vector3(10, 11, 20)` (Y = terreno 0 + 11); `clear()` → `visible == false` y minimapa con `_objective == null` (comprobar via método `objective()` del minimapa o estado interno público `objective: Variant`).
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** según Interfaces; el minimapa recibe el mismo `world_pos` (el `main.gd` conecta `mission_started` → `marker.set_target` + `minimap.set_objective`; `mission_completed`/`abandoned`/`failed` → `clear`).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade marcador de objetivo en el mundo y el minimapa"`.

---

### Task 7: Tablero de misiones (`J`)

**Files:**
- Create: `scripts/ui/mission_board.gd`
- Modify: `project.godot` (acción `mission_board`, tecla J physical_keycode 74), `scripts/main.gd`, `scripts/player/rito_combat.gd` (`_input_enabled` ya existe → reutilizar `set_input_enabled(false)` mientras el menú está abierto; el input de tablero se procesa en el menú, no en combate)

**Interfaces:**
- Consumes: `MissionSystem.available_missions()`, `start_mission`, `abandon_mission`, señales `mission_started/progress/completed/abandoned`.
- Produces: `class_name MissionBoard extends CanvasLayer` (capa 6) con `setup(system: MissionSystem)`; abre/cierra con `mission_board`; lista las 2-3 disponibles con título, brief, recompensa estimada y un `Button` "Aceptar"; la misión activa arriba con progreso y botón "Abandonar" (confirmación: dos clics "¿Abandonar? Sí/No"); el HUD no cambia todavía (Task 9).

- [ ] **Step 1: Write the failing test** — `_test_board_logic()` (sin UI real: el shell de Godot permite instanciar el `CanvasLayer` en el árbol de test y llamar sus métodos de lógica): abrir con J cambia `is_open()` true y llama `rito_combat.set_input_enabled(false)`; cerrar → true otra vez; `available` listas de 2 entradas (purge y defense) con nombres correctos; botón Aceptar en la purga → `start_mission` OK y el tablero muestra "Bandidos restantes: 4" tras `mission_progress`; abandonar con confirmación → `abandon_mission` llamado y racha en la señal `streak_changed(0, best)`.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** según Interfaces; mientras abierto: ratón VISIBLE, captura liberada (mismo patrón que `arsenal_menu.gd` — leer sus primeras 120 líneas y copiar la pauta de apertura/cierre y foco, sin copiar su contenido).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade tablero de misiones con tecla J"`.

---

### Task 8: Defensa de la ciudad (Pórtico, oleadas 4/6/8)

**Files:**
- Create: `scripts/missions/defense_site.gd`
- Modify: `scripts/main.gd`, `scripts/missions/mission_system.gd` (tipo `defense`: `targets` = oleada actual, meta = 18 bajas totales o "oleadas sobrevividas: 3"), `tools/progression_test.gd`

**Interfaces:**
- Produces: `class_name DefenseSite extends Node3D` con `static func begin(parent: Node, ruins: Vector3, terrain: Terrain3D, system: MissionSystem, target: Node3D) -> Node3D`. Oleada 1: 4 bandidos en anillo r=18; al morir todos → 20 s de pausa (banner "Oleada 2" no necesario: log por señal) → oleada 2: 6; oleada 3: 8. Si `system.is_mission_active()` se rompe por muerte → `fail_mission()` y `queue_free()`. Al vaciar oleada 3 → `complete_mission()`.

- [ ] **Step 1: Write the failing test** — `_test_defense_waves_flow()` con stub de terreno: oleadas 1→2→3 exigen matar 4, 6 y 8 respectivamente; matar todos los de oleada 1 sin tocar la 2 → `mission_progress` refleja 4/18; morir (o `take_damage` al 0 con fuente cualquiera) a mitad de oleada → `mission_failed` UNA vez y el sitio se libera; `kills` totales = 18 al completar; las ondas 2/3 no spawnean hasta vaciar la anterior.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** según Interfaces; reusar el tinte y la pausa de ambientales del campamento (misma helper `_make_mission_bandit` — extraer a `bandit_camp.gd` como `static func spawn_bandit(...)` y llamarla desde ambos).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade defensa del templo con tres oleadas de bandidos"`.

---

### Task 9: HUD — XP, nivel, denarios y tracker de misión

**Files:**
- Modify: `scripts/ui/hud.gd`, `scripts/main.gd` (conectar señales del sistema al HUD), `scripts/missions/mission_system.gd` (nada nuevo: consume las señales)

**Interfaces:**
- Consumes: `MissionSystem` (todas las señales de Task 4).
- Produces: `hud.gd` añade: barra XP fina bajo la barra de vida (`ColorRect` ámbar 0.85 alpha 0.75, ancho proporcional), label "Nv N" a su derecha, label "Denarios: N" bajo el de bajas, label de misión activa ("Bandidos restantes: N" / "Oleada X/3") bajo el nombre de Rito; estado sin misión = vacío. Pesos: actualizar por señal, nunca por polling.

- [ ] **Step 1: Write the failing test** — `_test_hud_binds_signals()`: montar HUD real en el árbol de test con un `MissionSystem`, emitir `xp_changed(150, 283, 2)` → el relleno XP y el label "Nv 2" se actualizan; `coins_changed(45)` → label "Denarios: 45"; `mission_progress(2, 4)` → label "Bandidos restantes: 2" (y variantes "Oleada 1/3" según `mission` diccionario: `mission["type"]=="defense"` formatea "Oleada"); `mission_completed` → label vacío; XP con `needed=0` (nivel máx 20) → relleno al 100 % sin división por cero.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** en `hud.gd` según el patrón existente de `_build_health` (mismos colores/constantes).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Muestra XP, nivel, denarios y progreso de mision en el HUD"`.

---

### Task 10: Árbol de tecnología (`T`)

**Files:**
- Create: `scripts/missions/tech_tree.gd`, `scripts/ui/tech_menu.gd`
- Modify: `project.godot` (`tech_tree`, tecla T = 84), `scripts/main.gd`, `scripts/combat/weapons_holder.gd` (guardar `_damage_mult := 1.0`; `func set_damage_mult(value: float) -> void`; `current_damage()` devuelve `base * _damage_mult`), `scripts/missions/mission_system.gd` (implementar los multiplicadores de recompensa/curación ya definidos en Task 4 — aquí se enciende el interruptor `has_tech`), `tools/progression_test.gd`

**Interfaces:**
- Produces: `class_name TechTree` con `const NODES: Array[Dictionary]` exactamente:
  ```
  {"id":"pozo","rama":"Agua","coste":60,"nombre":"Pozo de agua","desc":"+25 % aqua en recompensas de mision"},
  {"id":"acequia","rama":"Comida","coste":60,"nombre":"Acequia","desc":"+25 % panis en recompensas de mision"},
  {"id":"salazon","rama":"Comida","coste":80,"nombre":"Salazon","desc":"Desbloquea Sal: 1 panis + 10 denarios u2192 1 sal (+15 HP en panis)"},
  {"id":"granero","rama":"Comida","coste":100,"nombre":"Granero","desc":"Los panis de mision dan +1 unidad"},
  {"id":"molino","rama":"Comida","coste":100,"nombre":"Molino de agua","desc":"El panis cura +50 % (52 HP)"},
  {"id":"bodega","rama":"Comida","coste":120,"nombre":"Bodega de nieve","desc":"El helado cura el doble (30 HP)"},
  {"id":"armeria1","rama":"Armas","coste":80,"nombre":"Pugio romano","desc":"Desbloquea puñal: 22 daño, 1,6 m, cadencia 0,35 s"},
  {"id":"armeria2","rama":"Armas","coste":150,"nombre":"Gladio hispaniense","desc":"Desbloquea hispaniense: 48 daño, 2,4 m, cadencia 0,65 s"},
  {"id":"armeria3","rama":"Armas","coste":250,"nombre":"Templado de Toledo","desc":"El gladius hace +30 % de daño permanente"},
  ```
  (armeria1/2 referencian Task 11 — si 11 va después, el menú pinta "se desbloquea en la próxima entrega" o Task 11 se hace ANTES: **orden recomendado: Task 11 antes que 10**.)
- `tech_menu.gd`: panel con los 9 nodos agrupados por rama; cada uno `Button` con nombre+coste; deshabilitado si ya está comprado o faltan denarios; clic compra → `buy_tech` → señal `tech_changed` → refresca; cierra con T/Esc; mientras abierto, combate pausado con `set_input_enabled(false)` (mismo patrón tablero).

- [ ] **Step 1: Write the failing test** — `_test_tech_tree()`: `NODES` tiene 9 ids únicos; coste de cada id coincide con la tabla (60/60/80/100/100/120/80/150/250; suma total 1080); comprar todos resta 1080 denarios exactos; desbloquear `armeria3` → `gladius_damage_mult() == 1.3`; `pozo` → recompensas de aqua ×1,25 (con seed fijo, comparar `rewards["aqua"]` antes/después de comprarlo); `salazon` habilita `craft_sal()`; sin `molino`, panis cura 35; con, cura 52.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** `Pugio`/`Hispaniense` primero (ver Task 11 — invertir el orden), luego árbol + menú + wiring. `has_tech` guarda en `_tech: Dictionary` y se serializa en el save (Task 13).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade arbol de tecnologia con denarios y menu de compra"`.

---

### Task 11: Armas del árbol — pugio e hispaniense (+ teclas 4/5)

**Files:**
- Modify: `scripts/combat/weapon.gd` (dos filas nuevas + `make_pugio()` + `make_hispaniense()`), `project.godot` (`weapon_4` tecla 4 = física 52, `weapon_5` tecla 5 = física 53), `scripts/player/rito_combat.gd` (`WEAPON_ACTIONS` pasa a 5 entradas; `WEAPON_ACTIONS := ["weapon_1","weapon_2","weapon_3","weapon_4","weapon_5"]`), `scripts/ui/arsenal_menu.gd` (debe pintar N filas — verificar que itera sobre `WeaponScript.count()` y no sobre 3 fijas; si está fija, ajustar a dinámica), `scripts/ui/hud.gd` (la fila de fichas ya es dinámica por `WeaponScript.count()` — confirmar), `tools/progression_test.gd`
- **Nota:** los ids van **al final del catálogo** (gladius=0, pilum=1, spatha=2, pugio=3, hispaniensis=4) para no renumerar las teclas 1-3.

**Interfaces:**
- Produces: filas de catálogo: `{"id":"pugio","name":"Pugio","role":"Cuerpo a cuerpo","mode":"melee","damage":22.0,"reach":1.6,"cooldown":0.35,"window_open":0.25,"window_close":0.55,"radius":0.55,"anim_speed":2.4,"grip_rot_x":-0.35,"mesh":"pugio","summary":"Puñal del legionario: casi una extensión del puño."}`, `{"id":"hispaniens","name":"Gladio hispaniense","...,"damage":48.0,"reach":2.4,"cooldown":0.65,"window_open":0.25,"window_close":0.55,"radius":0.70,"anim_speed":1.9,"grip_rot_x":-0.35,"mesh":"hispaniens","summary":"La espada que plagiaron los romanos de los celtíberos."}`. Mallas: pugio = hoja corta + guarda simple; hispaniensis = gladius más largo y ancho (reutilizar `make_gladius` con parámetros de escala o duplicar 15 líneas de primitivas).
- Desbloqueo visual: `WeaponsHolder.setup` sigue montando todo el catálogo; el menú **oculta** (o marca como bloqueadas) las filas `pugio`/`hispaniense` si `MissionSystem` no confirma Armería I/II — para no filtrar contenido: pasar al arsenal un `is_unlocked: Callable(weapon_id) -> bool` desde `main.gd` (default: siempre true para las 3 iniciales).

- [ ] **Step 1: Write the failing test** — `_test_armeria_unlocks()`: catálogo tiene 5 armas con id único; pugio/hispaniensis bloqueadas por defecto (`is_unlocked("pugio")==false`), tras `buy_tech("armeria1")` → true; equipar pugio vía `switch_weapon(3)` → `current_damage()==22.0`; hispaniense con Armería II → 48.0 y `current_reach()==2.4`.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** según Interfaces; orden: primero las filas y mallas, luego project.godot, luego el gate del menú.
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`. **Además**, `tools/combat_test.gd` debe seguir en verde: `godot --headless --path . --script tools/combat_test.gd` → `TEST failures=0` (su `EXPECTED_CHECKS=62` no cambia: ninguna fila existente se toca).
- [ ] **Step 5: Commit** — `git commit -m "Anade pugio y gladio hispaniense al catalogo tras la Armeria"`.

---

### Task 12: Eventos de mundo (campamento en el Muro)

**Files:**
- Create: `scripts/missions/world_event.gd`
- Modify: `scripts/main.gd`, `tools/progression_test.gd`

**Interfaces:**
- Produces: `class_name WorldEvent extends Node` con `setup(system: MissionSystem, poi: Dictionary, terrain: Terrain3D, parent: Node3D)`; timer interno: `EVENT_DELAY := 180.0` s desde el arranque; con `mission_started` en cualquier misión → suspende; `mission_completed/failed/abandoned` → reinicia el timer con +120 s; si el Muro está ocupado o hay misión activa al vencer → reintenta en 60 s; expira a los `EVENT_TTL := 900.0` s sin tocar. Al activarse spawnea 3 bandidos (como purga pero sin pasar por el tablero) en `poi["muro"]` con tinte rojizo; marcador propio en el mundo (misma columna de luz, más baja: 12 m) y aviso en el HUD ("Actividad: bandidos en el Muro" en el tracker). Aceptar/completar: como purga pero `xp 80`, `coins 40–80`; al limpiarlos → `complete_mission()` con `mission_id "world_event"`.

- [ ] **Step 1: Write the failing test** — `_test_world_event_rules()`: con `mission_started` activo no spawnea aunque el timer venza; sin misión y timer vencido → 3 bandidos spawneados en `poi["muro"]` y `mission_started` emitido con id `world_event`; segundo vencimiento con el primero sin resolver → no hay duplicados; expirar tras 900 s → `finish()` y los vivos desaparecen sin recompensa.
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** según Interfaces; reusa `bandit_camp.gd` con `make` parametrizable (id `world_event` y recompensas propias — añadir un tercer template en `mission_data.gd` marcado `hidden = true`, fuera del tablero).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade evento de mundo: campamento de bandidos en el Muro"`.

---

### Task 13: Guardado end-to-end y puente web

**Files:**
- Modify: `scripts/main.gd` (tras quitar la pantalla de carga: `var save := SaveGame.load()` → `mission_system.apply_save(save)`; conectar `signal_to_save` cada 30 s y en `notification(NOTIFICATION_WM_CLOSE_REQUEST)`), `scripts/player/rito.gd` (ampliar el `eval(...)` de `__rito`: `xp`, `level`, `coins`, `mission`, `streak`; asignarlos en el mismo punto que hp/kills), `tools/verify_web.js` (3 checks nuevos: `xp` es número ≥ 0, `level` ≥ 1, `coins` ≥ 0; y `mission` string vacío o uno de los 3 ids), `tools/progression_test.gd`

- [ ] **Step 1: Write the failing test** — `_test_save_integration()`: ciclo completo — completar una purga con seed fijo → `current_save()` → `apply_save()` en sistema virgen → mismos `xp/level/coins/tech/best_streak`; `active_mission` no viaja en el dict; `apply_save` con dict vacío no rompe nada (empieza de cero, level 1, 100 HP).
- [ ] **Step 2: Run to verify fail** — Expected: FAIL.
- [ ] **Step 3: Implement** según Interfaces + checks web en `verify_web.js` (mirar sus 12 checks actuales y añadir 3 sin tocar los existentes).
- [ ] **Step 4: Run to verify pass** — Expected: `TEST failures=0`; `tools/combat_test.gd` sigue verde.
- [ ] **Step 5: Commit** — `git commit -m "Guarda el progreso y expone XP, nivel y denarios al puente web"`.

---

### Task 14: Presupuesto, web, captura y documentación

**Files:**
- Modify: `docs/superpowers/specs/2026-11-04-rito-cero-misiones-design.md` (marcar §6/§9 como ejecutados, con los datos medidos), `README.md` (sección "Misiones" breve), `docs/diagrams/rito-cero-loop.png` (regenerar si cambió algo — no si no cambió)
- Bench y medición (sin código de juego): `tools/bench.tscn` antes/después; `tools/web_bench.py` en el navegador real con GT 640; `tools/verify_web.js` → 15 checks; `tools/shot.gd` poses nuevas: tablero abierto, misión activa con marcador, árbol de tecnología.

- [ ] **Step 1: Baseline** — Run: `godot --headless --path . --script tools/combat_test.gd` → `TEST failures=0 checks=62`; `python tools/web_bench.py` (o el comando documentado en el spec de combate) → mediana actual (esperado ~40 FPS; **anota el valor**).
- [ ] **Step 2: Implement** — nada de juego nuevo; solo medir y documentar; si el banco cae > 5 % o la web < 36 FPS → aplicar el recorte pactado: desactivar el marcador animado (columna estática) primero; como último recurso, eliminar Task 12 (el evento) y dejar el tablero.
- [ ] **Step 3: Verificar build web** — `python tools/web_bench.py` → mediana ≥ 36 FPS; `node tools/verify_web.js` → **15 checks PASS**; sin errores de consola (`ERRORS []`).
- [ ] **Step 4: Capturas** — `tools/shot.gd` guarda `shot_board.png`, `shot_mission.png`, `shot_tech.png` en la raíz del proyecto (mismo sitio que las del arsenal).
- [ ] **Step 5: Commit** — `git commit -m "Mide y documenta el presupuesto con misiones y actualiza la documentacion"`.

---

## Self-Review

- **Spec coverage:** misiones de acción ✓ (5, 8, 12) · tablero + eventos ✓ (7, 12) · comida/agua curan + XP ✓ (1, 4) · armas equipables ✓ (Task 11; arsenal ya existente) · botín absurdo ✓ (2) · XP→nivel→mejores recompensas ✓ (4, 2) · denarios + árbol anacrónico ✓ (10) · armas vía árbol ✓ (10, 11) · sal ✓ (4) · guardado ✓ (3, 13) · HUD ✓ (9) · marcador ✓ (6) · presupuesto/36 FPS ✓ (14) · spec §7 casos límite ✓ (2, 4, 7, 10) · spec §10 anti-goals ✓ (filas de loot nunca dan armas: test Task 4 de tabla).
- **Review Focus:** #1 → Task 3 + Task 13 ✓ · #2 → Task 4 ✓ · #3 → Task 1 ✓ · #4 → Task 5 ✓ · #5 → Task 12 ✓.
- **Type consistency:** `MissionSystem` consume `GameInventory` solo vía `use_item` interno; `BanditCamp`/`DefenseSite` usan `MissionSystem.register_mission_kill/complete_mission/fail_mission` — presentes en Interfaces de Task 4; `set_damage_mult` declarado en Task 10, usado por `WeaponsHolder` modificado en la misma task; `poi_positions` definido en Task 5 y consumido en Tasks 5, 8, 12; `PROCESS_MODE_DISABLED` para ambientales heredado de Task 4 — Tasks 5/8 lo aplican.
- **Riesgo conocido del orden:** Task 10 depende de Task 11 (armas del árbol). Orden de ejecución recomendado: 1→2→3→4→5→6→7→8→9→11→10→12→13→14. (11 antes que 10 deliberadamente.)
