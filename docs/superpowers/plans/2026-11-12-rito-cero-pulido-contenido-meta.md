# Rito Cero — Pulido, contenido y meta-juego Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que Rito Cero pase de "demo con dos misiones" a juego con bucle largo: menús que no se apilan, cooldowns que sobreviven a la recarga, racha visible, spatha balanceada, tres tipos de enemigo, tres tipos de misión, contratos con mutadores y horda infinita en el coliseo con récord.

**Architecture:** Se extiende lo existente sin rediseñarlo: un `MenuCoordinator` centraliza las teclas de los menús blandos; `MissionSystem` generaliza el progreso de misión (de kills a `register_progress(n)`); los enemigos nuevos son subclases de `hostile_npc.gd` (patrón de `boss_npc.gd`); las misiones nuevas son sitios tipo `BanditCamp`/`DefenseSite`; el bruto compone con la guardia/parry ya implementada vía `receive_attack`; la horda es un modo propio fuera de `MissionSystem._active` que suma racha por oleada.

**Tech Stack:** Godot 4.7.2-stable, GDScript, renderer Compatibility, Jolt Physics; tests deterministas headless (`extends SceneTree`, patrón `combat_test.gd`); guardado JSON con degradación elegante (`save_game.gd`, VERSION 2).

**Spec:** `docs/superpowers/specs/2026-11-11-rito-cero-pulido-contenido-meta-design.md`

## Global Constraints

- Godot 4.7.2-stable, renderer **gl_compatibility**; sin assets externos nuevos: los enemigos y la escolta reusan el maniquí (`Godot/AnimationLibrary_Godot_Standard.glb`), su esqueleto y sus animaciones (sin clips nuevos).
- Tests deterministas headless (sin GPU), un arnés por feature; los verdes del README siguen verdes. `EXPECTED_CHECKS` se actualiza solo si el cambio lo obliga (p. ej. la spatha), documentándolo en el commit.
- Guardado compatible: un save de la versión actual carga sin la clave nueva; **no** se sube `SaveGame.VERSION` (2).
- Comentarios, textos de UI y mensajes de commit en **español**, sin emojis. Decimales con coma en pantalla.
- La guardia/parry ya implementada (`rito.gd`, `attack_volume.gd`, commits `90da1ef`/`a84da7b`) **no se toca**: el bruto compone con `receive_attack`; `tools/guard_parry_test.gd` sigue verde.
- Banco nativo `tools/bench.tscn --variant 1` sin regresión > 5 % (baseline 60 median).
- Tests: con la herramienta `run_tests` de Ziva (la del proyecto) o `godot --headless --path . --script tools/<harness>.gd` si el binario está en el PATH. Tras crear un script con `class_name`, refrescar el caché (`godot --headless --import`) antes de correr tests.
- Respetar el trabajo sin commitear del árbol (`addons/ziva_agent/`, los dos specs sin commitear, los `.uid`): no tocar ni commitear nada de eso; cada commit lista archivos concretos.

## Review Focus

1. **Doble toggle de menús** — si una UI sigue escuchando su tecla además del coordinador, abrirla la cierra en el mismo frame. → Task 1: las cuatro UIs dejan de escuchar su tecla y `ui_cancel`; el test abre con `handle_action` y comprueba que sigue abierta.
2. **Cooldowns tras recargar** — un cooldown a medio cumplir debe sobrevivir, uno expirado no debe bloquear, y un save viejo (sin la clave) no debe dejar cooldowns fantasma. → Task 2: tiempo unix, expirados descartados, clave ausente → sin cooldowns.
3. **Racha y muerte** — morir fuera de misión resetea la racha; la horda suma por oleada; morir en la horda termina la partida pero Rito reaparece. → Tasks 3 y 15: tests de `reset_streak` por señal `died` y de fin de partida sin bloquear el respawn.
4. **Escudo del bruto** — de frente reduce y no aturde; por la espalda entra completo con crítico; el pilum lo ignora; la guardia del jugador sigue intacta. → Task 7: tests de los cuatro casos + `guard_parry_test` verde.
5. **La escolta puede morir** — va en capa 32, incluida en la máscara de los bandidos (2 | 16 | 32) pero fuera del volumen del jugador (capa 4): sin fuego amigo, con amenaza real. → Task 11: test de muerte de la escolta y de capa.

---

## File Structure

```
scripts/ui/
├── menu_coordinator.gd   # class_name MenuCoordinator extends Node (NUEVO)
├── hud.gd                # racha, etiquetas de misión por tipo, cuenta atrás, horda
├── pause_menu.gd         # bloque de estadísticas con racha
├── mission_board.gd      # progreso en vez de kills_done; scroll de filas
├── arsenal_menu.gd       # sin toggle de tecla ni ui_cancel (los mueve el coordinador)
├── tech_menu.gd          # idem
└── inventory_menu.gd     # idem

scripts/missions/
├── mission_system.gd     # register_progress, cooldowns unix, horde, reset_streak público
├── mission_data.gd       # plantillas escort/collect/timed + contratos + "progress"
├── bandit_camp.gd        # spawn_bandit con kind/player/mutators; composition(level, total)
├── defense_site.gd       # composición por nivel + mutadores
├── escort_site.gd        # class_name EscortSite extends Node3D (NUEVO)
├── collect_site.gd       # class_name CollectSite extends Node3D (NUEVO)
├── timed_site.gd         # class_name TimedPurge extends Node3D (NUEVO)
├── horde_site.gd         # class_name HordeSite extends Node3D (NUEVO)
└── pickup.gd             # modo quest (no notifica a Progression)

scripts/npc/
├── hostile_npc.gd        # chase_speed de instancia; setup con player; cambio de objetivo
├── slinger_npc.gd        # class_name SlingerNpc (NUEVO)
├── brute_npc.gd          # class_name BruteNpc (NUEVO)
├── runner_npc.gd         # class_name RunnerNpc (NUEVO)
└── escort_npc.gd         # class_name EscortNpc extends CharacterBody3D (NUEVO)

scripts/world/
├── colosseum_arena.gd    # trigger de la horda (NUEVO)
└── structures.gd         # instancia el trigger en el coliseo

scripts/combat/
├── weapon.gd             # make_stone(), make_shield(); spatha 1,05 s
└── projectile.gd         # malla visual opcional (piedra)

scripts/audio/sfx_bank.gd # sonido "block" procedural

scripts/main.gd           # coordinador, ramas de misión, muerte→racha, horda

tools/                    # harnesses nuevos (menú, cooldown, racha, enemigos, misiones, contratos, horda)
```

---

### Task 1: Coordinador de menús (`MenuCoordinator`)

**Files:**
- Create: `scripts/ui/menu_coordinator.gd`
- Modify: `scripts/ui/mission_board.gd` (quitar toggle de `mission_board` y `ui_cancel` de `_input`), `scripts/ui/tech_menu.gd` (idem con `tech_tree`), `scripts/ui/inventory_menu.gd` (idem con `inventory`), `scripts/ui/arsenal_menu.gd` (idem con `arsenal_menu`), `scripts/main.gd` (instanciar y cablear tras crear los cuatro menús)
- Test: `tools/menu_coordinator_test.gd`

**Interfaces:**
- Consumes: cada menú conserva `open()` / `close()` / `toggle()` / `is_open()` (existentes); `pause_menu.is_open()`.
- Produces: `class_name MenuCoordinator extends Node` con `process_mode = PROCESS_MODE_ALWAYS`, `setup(menus: Dictionary, pause: Node) -> void` (claves: `"mission_board"`, `"tech_tree"`, `"inventory"`, `"arsenal_menu"`), `handle_action(action: String) -> void`, `close_top() -> bool`, `is_soft_open() -> bool`, `open_id() -> String`. `_input`: las cuatro teclas llaman `handle_action`; `ui_cancel` llama `close_top()` y consume el evento **solo si** había un menú blando abierto (si no, no consume: la pausa lo recibe en su `_unhandled_input`).

- [ ] **Step 1: Write the failing test** — `tools/menu_coordinator_test.gd` (patrón `extends SceneTree`, `EXPECTED_CHECKS`). Stubs:

```gdscript
class MenuStub extends Node:
    var abierta := false
    func is_open() -> bool: return abierta
    func open() -> void: abierta = true
    func close() -> void: abierta = false
    func toggle() -> void: abierta = not abierta
```

Checks: `handle_action("mission_board")` → tablero abierto y `open_id() == "mission_board"`; `handle_action("tech_tree")` → tablero cerrado, solo tecnología abierta (nunca dos); `handle_action("tech_tree")` otra vez → todos cerrados y `open_id() == ""`; `close_top()` sin nada → false; con uno abierto → true y cerrado; con `pause.is_open() == true`, `handle_action("mission_board")` no abre nada; un `InputEventAction` con `action = "ui_cancel", pressed = true` pasado a `_input` cierra el blando abierto; con la pausa abierta el coordinador no consume `ui_cancel` (la pausa puede abrirse).

- [ ] **Step 2: Run to verify fail** — `tools/menu_coordinator_test.gd` → FAIL (clase inexistente).
- [ ] **Step 3: Implement** `MenuCoordinator` según Interfaces; quitar de los cuatro menús el bloque de tecla y `ui_cancel` de `_input` (dejar el resto: selección de armas, rueda, clicks, dim). En `main.gd`, tras crear los cuatro menús: `var coordinador := MenuCoordinatorScript.new(); coordinador.name = "MenuCoordinator"; add_child(coordinador); coordinador.call("setup", {"mission_board": tablero, "tech_tree": tech_menu, "inventory": inventario_menu, "arsenal_menu": arsenal}, pause)`.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0 checks=12`. Además `tools/pause_test.gd` sigue verde.
- [ ] **Step 5: Commit** — `git add scripts/ui/menu_coordinator.gd scripts/ui/mission_board.gd scripts/ui/tech_menu.gd scripts/ui/inventory_menu.gd scripts/ui/arsenal_menu.gd scripts/main.gd tools/menu_coordinator_test.gd` + `git commit -m "Anade coordinador de menus blandos con cierre por Esc"`.

---

### Task 2: Cooldowns persistentes

**Files:**
- Modify: `scripts/missions/mission_system.gd`, `tools/mission_test.gd` (nuevo arnés `tools/cooldown_test.gd` — create)
- Test: `tools/cooldown_test.gd`

**Interfaces:**
- `MissionSystem`: nuevo `_now_unix() -> float` (`Time.get_unix_time_from_system()`); `_in_cooldown` y los tres registros de cooldown (completar/fallar/abandonar) usan unix; `current_save()` añade `"cooldowns": {id: float}` (copia del dict); `apply_save(data)` restaura solo los `timestamp > _now_unix()` (los expirados se descartan); clave ausente o de tipo erróneo → `_cooldowns` vacío (degradación elegante). `expire_cooldowns()` (solo tests) no cambia.

- [ ] **Step 1: Write the failing test** — `tools/cooldown_test.gd`: sistema nuevo → `_in_cooldown("bandit_purge") == false`; forzar `_cooldowns["bandit_purge"] = _now_unix() + 50` → `_in_cooldown` true y `available_missions()` **no** incluye `bandit_purge` pero sí `city_defense`; `current_save()["cooldowns"]["bandit_purge"] > _now_unix()`; un segundo sistema con `apply_save(save)` → sigue en cooldown; `apply_save({"cooldowns": {"x": _now_unix() - 10}})` → `x` disponible; `apply_save({})` → sin cooldowns; `apply_save({"cooldowns": "basura"})` → sin crash y sin cooldowns. (8–9 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces. `_cooldowns` guarda floats unix; `current_save` lo serializa tal cual (JSON plano).
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `tools/mission_test.gd` y `tools/progression_test.gd` siguen verdes.
- [ ] **Step 5: Commit** — `git commit -m "Persiste los cooldowns de mision en tiempo unix"`.

---

### Task 3: Racha visible en HUD y pausa

**Files:**
- Modify: `scripts/ui/hud.gd`, `scripts/ui/pause_menu.gd`, `scripts/main.gd` (pasar MissionSystem a la pausa)
- Test: `tools/streak_display_test.gd`

**Interfaces:**
- HUD: en `_ensure_mission_widgets` (funciona sin `setup`), label `Racha: N · Mejor: M` en `Vector2(18, 182)`, font 14, color DIM; se conecta a `streak_changed` en `bind_mission_system`; getter `streak_label_text() -> String`.
- Pausa: `setup(system: Node) -> void` guarda el sistema; al abrir (`toggle()` → `_open = true`) refresca un bloque de texto bajo los botones: `Nivel %d · Denarios %d · Racha: %d · Mejor: %d` (font 16, TEXT, centrado, y ≈ 230); getter `stats_text() -> String`.
- `main.gd`: tras crear la pausa, `pause.call("setup", _missions)`.

- [ ] **Step 1: Write the failing test** — `tools/streak_display_test.gd`: HUD real en el árbol, `bind_mission_system` con un `MissionSystem` real; emitir `streak_changed(3, 7)` → `streak_label_text() == "Racha: 3 · Mejor: 7"`; pausa con `setup(system)`, `streak_changed(3, 7)`, `xp_changed(50, 100, 2)`, `coins_changed(123)`, `toggle()` → `stats_text()` contiene `Nivel 2`, `Denarios: 123`, `Racha: 3`, `Mejor: 7`. (4–5 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces (patrón de labels ya existente en ambos archivos).
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Muestra la racha actual y la mejor en HUD y pausa"`.

---

### Task 4: Spatha sidegrade

**Files:**
- Modify: `scripts/combat/weapon.gd` (fila `spatha`: `"cooldown": 0.80` → `1.05`), `tools/progression_test.gd` (check nuevo; ajustar `EXPECTED_CHECKS`)
- Test: `tools/progression_test.gd`

**Interfaces:**
- `WeaponScript.get_weapon(WeaponScript.index_of("spatha"))["cooldown"] == 1.05`; el daño (58), el alcance (2,6) y el coste (gratis) no cambian.

- [ ] **Step 1: Write the failing test** — en `tools/progression_test.gd`, `_test_spatha_sidegrade()`: el cooldown de la spatha es 1,05; el del gladius sigue en 0,55; la spatha sigue sin `unlock_tech`. Buscar primero (`grep -n "spatha\|0\.8" tools/combat_test.gd tools/progression_test.gd`) aserciones que fijen el valor viejo y actualizarlas.
- [ ] **Step 2: Run to verify fail** — FAIL (cooldown 0,80).
- [ ] **Step 3: Implement** — una línea en el catálogo.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0` en progression_test y combat_test (con `EXPECTED_CHECKS` actualizado y documentado si procede).
- [ ] **Step 5: Commit** — `git commit -m "Rebalancea la spatha a sidegrade del gladius (cadencia 1,05 s)"`.

---

### Task 5: `hostile_npc` — chase_speed de instancia, fábrica y tabla de composición

**Files:**
- Modify: `scripts/npc/hostile_npc.gd`, `scripts/missions/bandit_camp.gd`
- Test: `tools/enemy_variety_test.gd`

**Interfaces:**
- `hostile_npc.gd`: `var chase_speed := CHASE_SPEED` (el `_chase` usa la variable, no la const); `setup(data, center: Vector3, angle: float, target: Node3D = null, player: Node3D = null)` guarda `_player_ref` (si `player == null`, vale `target`); `_on_damaged`: si `_player_ref != null` y `_target != _player_ref` y `global_position.distance_to(_player_ref.global_position) < 6.0` → `_target = _player_ref` (cambio de objetivo).
- `bandit_camp.gd`: `static func spawn_bandit(parent: Node, position: Vector3, angle: float, terrain: Variant, target: Node3D, kind := "bandit", player: Node3D = null, mutators: Dictionary = {}) -> Node3D` — elige script por `kind` (`"bandit"` → `hostile_npc.gd`, `"slinger"` → `slinger_npc.gd`, `"brute"` → `brute_npc.gd`, `"runner"` → `runner_npc.gd`; los tres últimos llegan en Tasks 6–8: hasta entonces un `push_warning` y fallback a bandido); llama `setup_<kind>` (o `setup` para "bandit"); si `mutators` no está vacío: `max_health *= health`, `attack_damage *= damage`, `chase_speed *= speed` (defaults 1,0) y `(get_node("Combatant") as Combatant).setup(max_health)` (re-setup tras el setup del NPC).
- `static func composition(level: int, total: int) -> Array[String]` (en `bandit_camp.gd`): nivel < 5 → todo `"bandit"`; 5–9 → `slingers = maxi(1, total / 4)`, resto bandidos; nivel >= 10 → `slingers = maxi(1, total / 4)`, `brutes = maxi(1, total / 6)`, `runners = maxi(1, total / 5)`, `bandits = maxi(1, total - slingers - brutes - runners)`; devuelve array con los ids (bandidos primero). Determinista, sin RNG.

- [ ] **Step 1: Write the failing test** — `tools/enemy_variety_test.gd` (base): `chase_speed` por defecto 3,4; instancia con 4,6 → `_chase` usa 4,6 (comprobar `velocity` tras un frame); `spawn_bandit(kind="bandit")` devuelve un `hostile_npc`; `composition(3, 4)` → 4 bandidos; `composition(6, 5)` → 1 slinger + 4 bandits; `composition(12, 8)` → 2 slingers, 1 brute, 1 runner, 4 bandits (contar por `get_script()` o por grupo/clase); `mutators {"health": 1.5}` → `max_health` ×1,5 y el Combatant re-setup con ese máximo. (8–10 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces (sin crear aún los NPC nuevos: `kind` desconocido → warning + bandido).
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `combat_test` y `boss_test` verdes (firma `setup` compatible: `boss_npc.setup_boss` llama `super.setup` con 4 argumentos).
- [ ] **Step 5: Commit** — `git commit -m "Anade chase_speed de instancia, fabrica de bandidos y tabla de composicion"`.

---

### Task 6: Hondero (`slinger_npc.gd`)

**Files:**
- Create: `scripts/npc/slinger_npc.gd`
- Modify: `scripts/combat/projectile.gd` (parámetro `visual: Mesh = null` en `setup`; si no es null, usa esa malla en `_build_visual` en vez del pilum), `scripts/combat/weapon.gd` (`static func make_stone() -> ArrayMesh`: esfera gris de 0,09 m, `_merge` con color `Color(0.45, 0.43, 0.40)`), `tools/enemy_variety_test.gd`

**Interfaces:**
- `class_name SlingerNpc extends "res://scripts/npc/hostile_npc.gd"`: `setup_slinger(data, center: Vector3, angle: float, target: Node3D = null)` fija `max_health = 35.0`, `attack_damage = 10.0`, `chase_speed = 3.0` y llama `super.setup`. Consts: `PREFERRED_MIN := 8.0`, `PREFERRED_MAX := 14.0`, `THROW_COOLDOWN := 2.5`, `STONE_SPEED := 26.0`, `STONE_RANGE := 30.0`, `STONE_MASK := 1 | 2 | 16`. Comportamiento: en `_physics_process` (override que llama `super` para STUN/DEAD), si hay objetivo vivo: distancia < `PREFERRED_MIN` → retrocede (dirección contraria, `chase_speed`); > `PREFERRED_MAX` → avanza; en el medio → Idle. `_try_attack` override: si `THROW_COOLDOWN` cumplido → animación `Punch_Cross`, volumen sin daño (`begin_swing(0.0, ...)` o no abrir volumen: usar `_volume.end_swing()`), y al terminar el clip lanza `Projectile` (malla `WeaponScript.make_stone()`, máscara `STONE_MASK`, daño `attack_damage`, velocidad y alcance de las consts) desde `global_position + Vector3(0, 1.4, 0)` hacia el objetivo. Suelta botín al morir (heredado).

- [ ] **Step 1: Write the failing test** — en `tools/enemy_variety_test.gd`: `setup_slinger` → vida 35; con el jugador a 5 m el hondero se aleja (distancia crece tras ~1 s de frames); con el jugador a 20 m no avanza más que `PREFERRED_MAX` (se queda); lanza: tras el cooldown aparece un `Projectile` en el árbol y el jugador recibe 10 de daño cuando impacta (posicionar al jugador en la trayectoria); `counts_as_kill` true. (5–6 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade el hondero: enemigo a distancia con kitin"`.

---

### Task 7: Bruto con escudo (`brute_npc.gd`)

**Files:**
- Create: `scripts/npc/brute_npc.gd`
- Modify: `scripts/combat/weapon.gd` (`static func make_shield() -> ArrayMesh`: caja de madera 0,65 × 0,85 × 0,08 + umbo metálico; colores `Color(0.42, 0.30, 0.16)` y `Color(0.55, 0.57, 0.60)`), `scripts/audio/sfx_bank.gd` (sonido procedural `"block"`: golpe metálico corto, ~0,12 s), `tools/enemy_variety_test.gd`

**Interfaces:**
- `class_name BruteNpc extends "res://scripts/npc/hostile_npc.gd"`: `setup_brute(data, center, angle, target = null)` fija `max_health = 140.0`, `attack_damage = 22.0`, `chase_speed = 2.6`, `body_scale = 1.15`; tras `super.setup` cuelga `WeaponScript.make_shield()` en `DEF-hand.L` (como el arma en la derecha) y usa `"Sword_Idle"` como animación de reposo (override de `_play`/estado Idle). `ATTACK_WINDUP := 0.5`, `ATTACK_COOLDOWN_B := 2.2`.
- `receive_attack(amount: float, source: Node3D) -> bool` (en el bruto): producto escalar entre el frente del modelo (`_model.global_transform.basis.z`, plano) y la dirección al atacante; si `>= 0.15` (frente): `_blocked_at = _now()`; `(get_node("Combatant") as Combatant).take_damage(amount * 0.25, source.global_position)`; sfx `"block"` y destello en el escudo (material del escudo a blanco 0,1 s); devuelve **true** (manejado). Si no (espalda/lados): devuelve **false** (daño normal por el camino de siempre).
- `stagger(seconds: float)` override: si `_now() - _blocked_at < 0.4` → ignora (no aturde); si no, `super.stagger(seconds)`.
- `_on_damaged` override: si `_now() - _blocked_at < 0.1` (el golpe que acaba de bloquear) → no entra en STUN (solo el fogonazo del Combatant); si no, `super._on_damaged`.
- `_try_attack` override: `begin_swing(attack_damage, self, 0.25, 0.55, clip_length, ATTACK_WINDUP)` (windup = 0,5 s).

- [ ] **Step 1: Write the failing test** — `tools/enemy_variety_test.gd`: vida 140 y `chase_speed` 2,6; golpe **frontal** (atacante delante): la vida baja solo un 25 % del daño y el estado no es STUN; golpe **por la espalda**: vida completa y STUN; `stagger(0.7)` justo tras un bloqueo → sigue sin STUN; el pilum (llamada directa a `Combatant.take_damage(40, pos)`) hace 40 completos; el escudo cuelga de `DEF-hand.L` (buscar el `BoneAttachment3D` con ese hueso). (6–7 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `tools/guard_parry_test.gd` sigue verde (la indirección `receive_attack` no cambia).
- [ ] **Step 5: Commit** — `git commit -m "Anade el bruto con escudo que bloquea de frente"`.

---

### Task 8: Corredor (`runner_npc.gd`)

**Files:**
- Create: `scripts/npc/runner_npc.gd`
- Modify: `tools/enemy_variety_test.gd`

**Interfaces:**
- `class_name RunnerNpc extends "res://scripts/npc/hostile_npc.gd"`: `setup_runner(data, center, angle, target = null)` fija `max_health = 30.0`, `attack_damage = 8.0`, `chase_speed = 4.6`, `body_scale = 0.95`; `ATTACK_COOLDOWN_R := 1.0`.
- Flanqueo: override de `_flat_direction_to_target()`: si la distancia al objetivo > 6,0 m, la dirección se gira 45° (`direction.rotated(Vector3.UP, PI / 4)`, siempre el mismo lado); a menos de 6 m, va directo.
- `_try_attack` override: cooldown 1,0 s, resto igual que el padre.

- [ ] **Step 1: Write the failing test** — `tools/enemy_variety_test.gd`: vida 30 y `chase_speed` 4,6; a 10 m del objetivo la dirección de avance no apunta directo (dot < 0,9); a 4 m apunta directo (dot > 0,95); cadencia de ataque 1,0 s (dos `_try_attack` seguidas: la segunda no abre swing dentro del cooldown). (4–5 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade el corredor: enemigo rapido que flanquea"`.

---

### Task 9: Composición por nivel en los sitios

**Files:**
- Modify: `scripts/missions/bandit_camp.gd` (`spawn` lee `_system.level` y reparte la composición entre bandidos/honderos/brutos/corredores), `scripts/missions/defense_site.gd` (`_spawn_wave` usa `composition(_sistema.level, WAVES[indice])`), `tools/enemy_variety_test.gd`

**Interfaces:**
- `BanditCamp.spawn(parent, center, count, terrain, system, target)` — sin cambios de firma: tras `_system = system`, cada posición del anillo recibe `composition(int(_system.get("level")), count)[i]` como `kind`. `DefenseSite._spawn_wave` igual con `WAVES[indice]`.

- [ ] **Step 1: Write the failing test** — `tools/enemy_variety_test.gd`: con un sistema stub (`level = 3`), `BanditCamp.spawn` de 4 → 4 bandidos, 0 honderos; `level = 6`, 5 → 1 hondero; `level = 12`, 8 → 2 honderos, 1 bruto, 1 corredor, 4 bandidos; `DefenseSite.begin` con stub nivel 12 → la oleada 1 (4) no lleva brutos (nivel de ola bajo: composition(12, 4) → 1 hondero, 3 bandidos). (4–5 checks; contar tipos por `is` de clase.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `mission_test`/`boss_test` verdes.
- [ ] **Step 5: Commit** — `git commit -m "Escala la composicion de enemigos por nivel en purga y defensa"`.

---

### Task 10: Progreso generalizado + plantillas nuevas

**Files:**
- Modify: `scripts/missions/mission_data.gd`, `scripts/missions/mission_system.gd`, `scripts/ui/mission_board.gd` (`kills_done` → `progress`), `scripts/ui/hud.gd` (`kills_done` → `progress`)
- Test: `tools/new_missions_test.gd`

**Interfaces:**
- `mission_data.gd`: `TEMPLATES` gana tres entradas (con `"progress": 0` además el `make_instance` para **todas**):
  - `"escort"`: `{"type": "escort", "title": "Escolta al superviviente", "brief": "Acompaña al superviviente desde las ruinas hasta la cueva. Si cae, la misión falla.", "xp": 120, "coins": [60, 100], "targets": 1, "poi": "ruinas"}`
  - `"collect"`: `{"type": "collect", "title": "Recolección de suministros", "brief": "Recoge los suministros dispersos junto al Muro mientras los bandidos hostigan.", "xp": 100, "coins": [50, 90], "targets": 6, "poi": "muro"}`
  - `"timed"`: `{"type": "timed", "title": "Purga contrarreloj", "brief": "Limpia la Columna rota antes de que acabe el tiempo.", "xp": 90, "coins": [40, 70], "targets": 4, "poi": "columna", "time_limit": 90}`
  - `make_instance`: añade `"progress": 0`; quita `"kills_done"`; `timed` escala `targets = 4 + level / 4`; copia `time_limit` si existe.
- `mission_system.gd`: `register_progress(n: int = 1) -> bool` — `progress += n`, emite `mission_progress`, completa al `>= targets`; `register_mission_kill() -> bool` = `register_progress(1)` (mismo comportamiento externo).

- [ ] **Step 1: Write the failing test** — `tools/new_missions_test.gd`: las tres plantillas existen; `make_instance("escort", 1)["targets"] == 1`; `collect` → 6; `timed` nivel 1 → 4, nivel 9 → 6, `time_limit` 90; `make_instance("bandit_purge", 3)["progress"] == 0` y sin `kills_done`; `register_progress(2)` emite `mission_progress(2, targets)` y no completa; al llegar a `targets` emite `mission_completed` una vez; sin misión activa → false. (9–10 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces; actualizar `mission_board._active_text` (`progress` en vez de `kills_done`, incluido el `_seed_active`) y `hud._on_mission_started/_on_mission_progress`.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `mission_test`, `progression_test`, `pause_test` verdes.
- [ ] **Step 5: Commit** — `git commit -m "Generaliza el progreso de mision y anade plantillas de escolta, recoleccion y contrarreloj"`.

---

### Task 11: Escolta (`escort_npc.gd` + `escort_site.gd`)

**Files:**
- Create: `scripts/npc/escort_npc.gd`, `scripts/missions/escort_site.gd`
- Modify: `scripts/npc/hostile_npc.gd` (máscara del volumen `2 | 16 | 32`), `scripts/main.gd` (rama `escort`), `scripts/ui/hud.gd` (etiqueta "Escolta: sigue al aliado"), `tools/new_missions_test.gd`

**Interfaces:**
- `class_name EscortNpc extends CharacterBody3D`: `setup(player: Node3D, waypoints: Array[Vector3])` — capa 32, máscara 1, cápsula (0,32, 1,7), `Combatant` 80 HP, visual del maniquí con tinte (patrón del esclavo, sin arma), `signal arrived`, `signal died(source_position)`. `_physics_process`: si el jugador está a más de 25 m → espera (Idle); si no, anda al waypoint actual a 3,5 m/s; al llegar a < 1,0 m pasa al siguiente; al último → `arrived`. Getters: `waypoint_index() -> int`, `is_arrived() -> bool`.
- `class_name EscortSite extends Node3D`: `static func begin(parent: Node, system: MissionSystem, target: Node3D, origin: Vector3, destination: Vector3, terrain: Variant) -> Node3D` — 8 waypoints en línea (Y del terreno, fallback al centro como `BanditCamp`); instancia `EscortNpc`; emboscadas al cruzar los waypoints 3 y 6: `BanditCamp.spawn_bandit` en anillo de 10 m alrededor del escolta (3 bandidos + 1 hondero si `system.level >= 5`), con `target = escolta`, `player = objetivo`; muerte del escolta → `fail_mission`; `arrived` → `register_progress(1)` (completa: targets 1); muerte del jugador → `fail_mission` (patrón `_conectar_muerte` de `BanditCamp`). Getters: `ambush_count() -> int`, `escort() -> Node3D`.
- `hud.gd`: `_refresh_mission_label`: tipo `"escort"` → `"Escolta: sigue al aliado"`.
- `main.gd`: rama `tipo == "escort"` → `EscortSite.begin(self, _missions, _rito_ref, _poi_ref["ruinas"], _poi_ref["cueva"], _terrain_ref)` (con los mismos avisos de POI ZERO que las otras ramas).

- [ ] **Step 1: Write the failing test** — `tools/new_missions_test.gd`: el escolta avanza por la ruta (posición cambia tras frames); a > 25 m del jugador se detiene; al cruzar el waypoint 3 aparece la emboscada (contar `hostiles` + `mission_bandits`); los bandidos de emboscada tienen `_target == escolta`; si el jugador recibe daño cerca ( < 6 m) el bandido cambia a `_target == jugador`; muerte del escolta → `mission_failed`; llegada → `mission_completed` (progress 1/1). (7–8 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `dog_follow_test`/`slave_test` verdes (capa 32 no choca con el moloso: comprobar que el perro no lo persigue).
- [ ] **Step 5: Commit** — `git commit -m "Anade mision de escolta con emboscadas y capa propia"`.

---

### Task 12: Recolección (`collect_site.gd`)

**Files:**
- Create: `scripts/missions/collect_site.gd`
- Modify: `scripts/missions/pickup.gd` (modo quest), `scripts/main.gd` (rama `collect`), `tools/new_missions_test.gd`

**Interfaces:**
- `pickup.gd`: `var quest := false`; `setup(p_id: String, p_amount: int, quest := false)`; en `_on_body_entered`, si `_quest` → **no** llama a `apply_loot` (sin tocar Progression); emite `collected`, sfx y `queue_free` igual. Color nuevo: `"suministro"` → `Color(0.95, 0.75, 0.30)`.
- `class_name CollectSite extends Node3D`: `static func begin(parent: Node, center: Vector3, terrain: Variant, system: MissionSystem, target: Node3D) -> Node3D` — 6 pickups `"suministro"` con `quest = true` en anillo de radio 20 (Y del terreno); 4 bandidos en anillo de radio 14; cada `collected` → `register_progress(1)`; muerte del jugador → `fail_mission`. Getter: `remaining() -> int`.

- [ ] **Step 1: Write the failing test** — `tools/new_missions_test.gd`: aparecen 6 pickups de quest; al recoger uno (llamar `_on_body_entered(null)`) el progreso sube y el stub de Progression del grupo `progression` **no** recibe `apply_loot`; al recoger el sexto → `mission_completed`; muerte del jugador → `mission_failed`; `remaining()` baja de 6 a 0. (6–7 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces; `main.gd`: rama `tipo == "collect"` → `CollectSite.begin(self, _poi_ref["muro"], _terrain_ref, _missions, _rito_ref)` (aviso POI ZERO igual).
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `pickup_test` verde.
- [ ] **Step 5: Commit** — `git commit -m "Anade mision de recoleccion con suministros de quest"`.

---

### Task 13: Contrarreloj (`timed_site.gd`)

**Files:**
- Create: `scripts/missions/timed_site.gd`
- Modify: `scripts/main.gd` (rama `timed` + conexión al HUD), `scripts/ui/hud.gd` (`set_time_left`), `tools/new_missions_test.gd`

**Interfaces:**
- `class_name TimedPurge extends Node3D`: `static func begin(parent: Node, center: Vector3, count: int, terrain: Variant, system: MissionSystem, target: Node3D, seconds: float) -> Node3D` — dentro levanta un `BanditCamp` (`BanditCamp.spawn(self, ...)`, que ya completa la misión al matar a todos); cuenta atrás propia: `var time_left := seconds` (pública para tests), `var wave_pause` no aplica; `_advance_time_for_test(s: float)` (patrón de `DefenseSite`); `signal time_left_changed(seconds: int)` (se emite al cambiar el segundo entero); al llegar a 0 → `fail_mission`, `finish()` del campamento y `queue_free`. Getters: `time_left_value() -> float`, `camp() -> Node3D`.
- `hud.gd`: `var _time_left := -1`; `func set_time_left(seconds: int) -> void` (guarda y refresca etiqueta); `_refresh_mission_label`: tipo `"timed"` → `"Contrarreloj: %d s · quedan %d" % [_time_left, targets - current]`.
- `main.gd`: rama `tipo == "timed"` → `TimedPurge.begin(self, _poi_ref["columna"], int(mision["targets"]), _terrain_ref, _missions, _rito_ref, float(mision.get("time_limit", 90)))`; conectar `time_left_changed` → `hud.set_time_left`.

- [ ] **Step 1: Write the failing test** — `tools/new_missions_test.gd`: el campamento spawnea con N bandidos; `_advance_time_for_test(89)` → `time_left_changed` emitido y `time_left_value()` ≈ 1; `_advance_time_for_test(2)` → `mission_failed` una vez y el campamento liberado (bandidos vivos fuera); matar a todos antes de expirar → `mission_completed` (camino del campamento). (5–6 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`.
- [ ] **Step 5: Commit** — `git commit -m "Anade mision de purga contrarreloj con cuenta atras en el HUD"`.

---

### Task 14: Contratos escalables (`B.1`)

**Files:**
- Modify: `scripts/missions/mission_data.gd` (plantillas de contrato, `min_level`, `mutators`, `reward_mult`), `scripts/missions/mission_system.gd` (`available_missions` filtra por nivel mínimo), `scripts/missions/bandit_camp.gd` (`spawn` acepta y propaga `mutators`), `scripts/missions/defense_site.gd` (`begin`/`_spawn_wave` igual), `scripts/ui/mission_board.gd` (scroll de filas), `tools/contracts_test.gd`
- Test: `tools/contracts_test.gd`

**Interfaces:**
- Plantillas nuevas (ocultas al tablero por debajo de nivel 10):
  - `"bandit_purge_contract"`: igual que `bandit_purge` + `"min_level": 10`, `"mutators": {"health": 1.5, "damage": 1.25, "speed": 1.15}`, `"reward_mult": 1.5`.
  - `"city_defense_contract"`: igual que `city_defense` + los mismos `min_level`, `mutators` y `reward_mult`.
- `make_instance`: copia `mutators` (duplicado) y `min_level` si existen; `xp` y banda de `coins` se multiplican por `reward_mult` (default 1,0) **después** del factor de nivel.
- `available_missions()`: omite plantillas con `min_level > level`.
- `BanditCamp.spawn(..., mutators: Dictionary = {})` y `DefenseSite.begin(..., mutators: Dictionary = {})`: los pasan a `spawn_bandit` (Task 5 ya aplica los multiplicadores).
- `mission_board.gd`: `_rows_host` pasa a vivir dentro de un `ScrollContainer` (mismo rect; scroll vertical; las filas mantienen 64 + 8 px); el resto del panel no cambia.

- [ ] **Step 1: Write the failing test** — `tools/contracts_test.gd`: las dos plantillas existen con los mutadores exactos; `make_instance("bandit_purge_contract", 10)` → xp 90 (60 × 1,5), coins [45, 90], mutadores presentes; nivel 9 → `available_missions()` **no** incluye contratos; nivel 10 → sí; aceptar el contrato y completarlo → cooldown solo del contrato (`available_missions()` sigue ofreciendo `bandit_purge`); `BanditCamp.spawn` con mutadores → enemigo con `max_health` ×1,5. (7–8 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `mission_test`/`progression_test` verdes.
- [ ] **Step 5: Commit** — `git commit -m "Anade contratos con mutadores desde nivel 10"`.

---

### Task 15: Horda en el coliseo (`B.2`)

**Files:**
- Create: `scripts/missions/horde_site.gd`, `scripts/world/colosseum_arena.gd`
- Modify: `scripts/missions/mission_system.gd` (`horde_active`, `start_horde`, `horde_wave_cleared`, `horde_run_ended`, `reset_streak` público; `start_mission` bloqueado con horda activa), `scripts/world/structures.gd` (Area3D trigger en el coliseo con el script nuevo), `scripts/main.gd` (muerte→`reset_streak`, arranque y fin de horda, banner), `scripts/ui/hud.gd` (`set_horde`, banner de fin), `tools/horde_test.gd`
- Test: `tools/horde_test.gd`

**Interfaces:**
- `mission_system.gd`: `var horde_active := false`; `start_horde() -> bool` (false si hay misión activa o horda ya activa); `horde_wave_cleared(wave: int) -> void` — `current_streak += 1`, `best_streak = maxi(...)`, emite `streak_changed`, `add_xp(10 + 2 * wave)`, `coins += 5 + 3 * wave` con `coins_changed`; `horde_run_ended() -> void` — `horde_active = false`; `reset_streak() -> void` público (envuelve `_reset_streak`); `start_mission` devuelve false si `horde_active`.
- `class_name HordeSite extends Node3D`: `static func begin(parent: Node, center: Vector3, terrain: Variant, system: MissionSystem, target: Node3D) -> Node3D`; oleada n: tamaño `mini(3 + n, 12)`, mutador de vida `1.0 + 0.1 * (n - 1)`, composición `composition(9 + n, tamaño)` (desde la oleada 3 entran brutos); pausa de 5 s entre oleadas (`_advance_time_for_test(s)` como `DefenseSite`); cada baja suma al contador de la partida; al vaciar la oleada → `system.horde_wave_cleared(n)`; muerte del jugador → fin de la partida: `system.horde_run_ended()`, `finish()` (libera vivos) y `queue_free`; señales `wave_changed(wave: int)` y `run_ended(waves: int, kills: int)`. Getters: `waves_cleared() -> int`, `kills() -> int`.
- `colosseum_arena.gd`: `Area3D` (caja 20 × 8 × 20, máscara 2) con `signal entered`; `structures.gd` lo instancia sobre el punto del coliseo (como la cueva); `main.gd`: `entered` → si no hay misión activa ni horda activa y Rito vive → `HordeSite.begin(...)` y conecta `wave_changed`/`run_ended` al HUD; banner de fin: `"Oleadas superadas: %d · Bajas: %d"` (reusa `_victory_label` + `_banner_until`).
- `main.gd`: conectar `_combatant.died` → `_missions.reset_streak()` (toda muerte resetea la racha, también fuera de misión; `fail_mission` ya resetea: inofensivo).
- `hud.gd`: `func set_horde(wave: int) -> void` → etiqueta `"Horda: oleada %d"` (columna izquierda, y 182, misma posición que la racha: si hay horda, sustituye a la racha).

- [ ] **Step 1: Write the failing test** — `tools/horde_test.gd`: `start_horde()` → `horde_active` y `start_mission("bandit_purge")` → false; oleada 1 = 3 bandidos; matar 3 → `streak_changed(1, 1)` y XP/denarios suben; oleada 2 = 4; congelar en oleada 3: tamaño 6 y botín con mutador de vida 1,2 (comprobar `max_health` del enemigo = 72); muerte del jugador → `horde_active` false, sitio `finish()` (vivos liberados), `waves_cleared()` y `kills()` devuelven lo de la partida; `reset_streak()` público funciona fuera de horda. (8–9 checks.)
- [ ] **Step 2: Run to verify fail** — FAIL.
- [ ] **Step 3: Implement** según Interfaces.
- [ ] **Step 4: Run to verify pass** — `TEST failures=0`; `defense` (boss_test) y `guard_parry_test` verdes.
- [ ] **Step 5: Commit** — `git commit -m "Anade la horda infinita del coliseo con record de racha"`.

---

### Task 16: Verificación final y documentación

**Files:**
- Modify: `README.md` (sección "Pendientes conocidos": fuera menús apilables, spatha, cooldowns y `best_streak` — ya resueltos; añadir a "Misiones" las tres nuevas y los contratos; nueva sección "Horda" breve), `docs/superpowers/specs/2026-11-11-rito-cero-pulido-contenido-meta-design.md` (marcar fases como ejecutadas)

- [ ] **Step 1: Correr toda la batería** — `progression_test`, `combat_test`, `combo_test`, `feel_test`, `dog_follow_test`, `audio_test`, `mission_test`, `pause_test`, `pickup_test`, `boss_test`, `cave_test`, `input_map_test`, `slave_test`, `controller_test`, `guard_parry_test`, y los nuevos: `menu_coordinator_test`, `cooldown_test`, `streak_display_test`, `enemy_variety_test`, `new_missions_test`, `contracts_test`, `horde_test`. Todos `TEST failures=0`.
- [ ] **Step 2: Banco nativo** — `tools/bench.tscn --variant 1` (ventana opengl3): `median_avg` sin caída > 5 % respecto a 60,0.
- [ ] **Step 3: Partida manual** — menús (J/T/I/B no se apilan; Esc cierra el de arriba; con pausa abierta J no abre); cooldown tras recargar a media espera; racha en HUD y pausa; contratos en el tablero a nivel 10+; horda: entrar al coliseo, morir, banner y reaparición.
- [ ] **Step 4: Documentar** — README y spec actualizados.
- [ ] **Step 5: Commit** — `git commit -m "Documenta el pulido, el contenido y el meta-juego"`.

---

## Self-Review

- **Spec coverage:** A1.1 ✓ (Task 1) · A1.2 ✓ (2) · A1.3 ✓ (3) · A1.4 ✓ (4) · A2.1 enemigos ✓ (5–8) · composición por nivel ✓ (9) · A2.2 escolta ✓ (11) · recolección ✓ (12) · contrarreloj ✓ (13) · progreso generalizado ✓ (10) · B.1 contratos ✓ (14) · B.2 horda ✓ (15) · verificación ✓ (16).
- **Review Focus:** #1 → Task 1 ✓ · #2 → Task 2 ✓ · #3 → Tasks 3 y 15 ✓ · #4 → Task 7 (+ guard_parry_test en Task 16) ✓ · #5 → Task 11 ✓.
- **Type consistency:** `register_progress(n)` (Task 10) es el único camino de progreso; `spawn_bandit(kind, player, mutators)` (Task 5) lo consumen Tasks 9, 11, 12, 13 y 14; `composition(level, total)` (Task 5) lo consumen Tasks 9 y 15; `mutators` viaja `mission_data` → `main` → `BanditCamp.spawn`/`DefenseSite.begin` → `spawn_bandit`; `horde_*` (Task 15) vive en `MissionSystem` (Task 2/10 lo tocan: sin colisión de nombres); la etiqueta de racha (y 182) y la de horda se alternan, no se suman.
- **Riesgo del orden:** Task 5 depende de que existan las clases de Tasks 6–8 (fallback a bandido hasta entonces: el plan lo permite y Task 5 no las toca); Task 9 consume Task 5; Tasks 11–13 consumen Task 10; Task 14 consume Tasks 9 y 10; Task 15 consume Tasks 5, 9 y 10.
- **Nota de composición:** el diseño del spec dice "1 de cada 6 brutos y 1 de cada 5 corredores a nivel 10+"; la tabla de Task 5 lo implementa con redondeo determinista y suelo de 1 bandido: los tests fijan los límites exactos por nivel.