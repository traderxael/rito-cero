# Combate con guardia, parry y contraataque — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Añadir guardia con barra, parry de 0,20 s y contraataque de 1,75× al combate de `rito cero`, con ataque enemigo telegrafiado.

**Architecture:** El estado defensivo vive en `Rito`; `AttackVolume` delega el golpe en `receive_attack` cuando el cuerpo lo implementa. `RitoCombat` traduce la entrada `block` y consume el riposte al aterrizar. El HUD escucha señales de `Rito`.

**Tech Stack:** Godot 4.7, GDScript, test harness `SceneTree` existente, Ziva MCP para ejecutar tests y el juego.

**Spec:** `docs/superpowers/specs/2026-11-11-combate-guardia-parry-design.md`

## Global Constraints

- No crear animaciones nuevas; reutilizar `Sword_Idle` y los clips existentes.
- Mantener intactos ataque, combo, esquiva, armas, crítico y los 94 checks de `tools/combat_test.gd`.
- Todos los valores de la tabla del spec son los iniciales.
- La guardia solo protege el frente; por la espalda entra daño completo.
- El pilum no consume riposte.
- No tocar misiones, loot, progresión ni la IA fuera del windup.

## Review Focus

- Ataque por la espalda con guardia activa: debe entrar completo, no reducirse.
- Parry justo al borde de la ventana de 0,20 s: no debe quedar daño a medias.
- Guardia rota: debe recibir exactamente el 50 % del golpe y quedar bloqueada 1,5 s.
- Riposte contra un enemigo ya muerto o fuera de alcance: no debe duplicar daño ni romper el combo.
- `AttackVolume` usado por NPCs y jugador: el camino sin `receive_attack` debe seguir igual.

---

### Task 1: Entrada `block` y guardia en Rito

**Files:**
- Modify: `project.godot` (sección `[input]`)
- Modify: `scripts/player/rito.gd`
- Create: `tools/guard_parry_test.gd`

**Interfaces:**
- Consumes: `Combatant.take_damage(amount, source_position)`, `Rito.model`, `Rito.play_one_shot`.
- Produces:
  - `Rito.set_guarding(value: bool) -> void`
  - `Rito.is_guarding() -> bool`
  - `Rito.guard_value() -> float`
  - `Rito.receive_attack(amount: float, source: Node3D) -> bool`
  - `signal guard_changed(current: float, maximum: float)`
  - `signal guard_broken`

- [ ] **Step 1: Escribir los tests de guardia**

Crear `tools/guard_parry_test.gd` con un `SceneTree`, contador `_checks_run` y estos casos:

```gdscript
extends SceneTree

const RitoScript := preload("res://scripts/player/rito.gd")
const CombatantScript := preload("res://scripts/combat/combatant.gd")

class StaggerProbe extends Node3D:
	var staggered := 0.0
	func stagger(seconds: float) -> void:
		staggered = seconds

func _init() -> void:
	_test_block_action_exists()
	_test_guard_reduces_frontal_damage()
	_test_guard_ignores_back_attack()
	_test_guard_breaks()
	print("TEST failures=", _failures, " checks=", _checks_run)
	quit(1 if _failures > 0 else 0)
```

Los asserts exactos:
- `InputMap.has_action("block")` es verdadero.
- Tras `set_guarding(true)` y `receive_attack(20.0, atacante_delante)`, la vida baja de 100 a 96 (20 × 0,2) y la guardia de 100 a 78 (20 × 1,1).
- `receive_attack(20.0, atacante_detras)` devuelve `false` y no cambia la vida.
- Con guardia 10, `receive_attack(20.0, frente)` deja vida 90 (50 % de 20), guardia 0, `is_guarding() == false` y `_guard_lock_until > ahora`.

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `run_tests` con `path: "res://tools/guard_parry_test.gd"`.
Expected: FAIL porque `block` no existe y `Rito` no tiene `set_guarding`.

- [ ] **Step 3: Implementar la guardia en `Rito`**

Añadir constantes y estado:

```gdscript
const GUARD_MAX := 100.0
const GUARD_DAMAGE_REDUCTION := 0.8
const GUARD_COST_MULT := 1.1
const GUARD_REGEN := 22.0
const GUARD_REGEN_DELAY := 0.7
const GUARD_SPEED_MULT := 0.55
const GUARD_BREAK_DAMAGE := 0.5
const GUARD_BREAK_STUN := 0.8
const GUARD_BREAK_LOCK := 1.5
const GUARD_REFRACTORY_REFILL := 25.0

signal guard_changed(current: float, maximum: float)
signal guard_broken

var _guard := GUARD_MAX
var _guarding := false
var _guard_regen_at := 0.0
var _guard_lock_until := 0.0
```

`set_guarding(true)` solo activa si `is_alive()`, no está bloqueado y `_now() >= _guard_lock_until`. `set_guarding(false)` baja la guardia.

`receive_attack(amount: float, source: Node3D) -> bool`:
- Si no está guardando o la fuente no está delante (`dot(frente, direccion) >= 0.15`), devolver `false`.
- Si el coste `amount * GUARD_COST_MULT` agota la guardia: guardia 0, `_guarding = false`, `_guard_lock_until = now + 1.5`, `combatant.take_damage(amount * 0.5, ...)`, `guard_broken.emit()`, `play_one_shot(_resolved_hit_strong, 0.8, PRIORITY_HIT)` y devolver `true`.
- Si no: restar coste, `combatant.take_damage(amount * 0.2, ...)`, `_guard_regen_at = now + 0.7`, emitir `guard_changed` y devolver `true`.

En `_physics_process`, multiplicar `target_speed` por `GUARD_SPEED_MULT` si `_guarding`; no permitir sprint con guardia. Regenerar `GUARD_REGEN * delta` cuando `_now() >= _guard_regen_at` y no esté guardando.

En `_update_model`, si `_guarding` y no está bloqueado, usar `_resolved_guard` (`Sword_Idle` o `Idle_Loop`). Resolverlo en `_build_model`.

En `respawn` y `_on_died`, resetear guardia, parry y riposte.

- [ ] **Step 4: Añadir la acción `block` a `project.godot`**

```ini
block={
"deadzone": 0.2,
"events": [Object(InputEventKey,"physical_keycode":81,"pressed":false)]
}
```

Usar el formato de las acciones existentes, con tecla física 81 (Q).

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

Run: `run_tests` con `res://tools/guard_parry_test.gd`.
Expected: PASS con 4 checks.

---

### Task 2: Parry y contraataque

**Files:**
- Modify: `scripts/player/rito.gd`
- Modify: `scripts/player/rito_combat.gd`
- Modify: `tools/guard_parry_test.gd`

**Interfaces:**
- Consumes: `Rito.receive_attack`, `Rito.set_guarding`.
- Produces:
  - `Rito.try_parry() -> bool`
  - `Rito.is_riposte_ready() -> bool`
  - `Rito.consume_riposte() -> float` (1,75 o 1,0)
  - `signal parried`
  - `signal riposte_changed(active: bool)`

- [ ] **Step 1: Escribir los tests de parry y riposte**

Añadir al test:
- `try_parry()` devuelve `true`; un `receive_attack` frontal inmediato deja la vida intacta y emite `parried`.
- El `StaggerProbe` recibe `stagger(1.1)`.
- `is_riposte_ready()` es `true`; `consume_riposte()` devuelve `1.75`; la segunda llamada devuelve `1.0`.
- Un parry con la guardia ya bajada no otorga riposte.

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `run_tests` con `res://tools/guard_parry_test.gd`.
Expected: FAIL porque `try_parry` no existe.

- [ ] **Step 3: Implementar parry/riposte en `Rito`**

Constantes `PARRY_WINDOW := 0.20`, `PARRY_STAGGER := 1.1`, `RIPOSTE_WINDOW := 1.5`, `RIPOSTE_MULT := 1.75`.

`try_parry()` activa `_parry_until = now + 0.20` y devuelve `true` solo si puede guardar.

En `receive_attack`, antes del bloqueo normal: si `_now() <= _parry_until`, poner `_parry_until = 0`, `_riposte_until = now + 1.5`, llamar `source.stagger(1.1)` si existe, emitir `parried` y `riposte_changed(true)`, y devolver `true` sin daño.

`consume_riposte()` devuelve `1.75` y limpia la ventana si está activa; si no, `1.0`.

- [ ] **Step 4: Conectar la entrada y el daño en `RitoCombat`**

En `_process`:
- `Input.is_action_just_pressed("block")` → `_rito.try_parry()`.
- `Input.is_action_pressed("block")` → `_rito.set_guarding(true)`.
- Si no se mantiene `block` y `_rito.is_guarding()` → `_rito.set_guarding(false)`.
- Antes de atacar o esquivar, `_rito.set_guarding(false)`.

En `_on_landed`, consumir riposte solo si `allow_riposte` es verdadero. Añadir el parámetro `allow_riposte: bool = true`; `_on_projectile_landed` pasa `false`. Si el multiplicador es `1.75`, usarlo como multiplicador total (no apilar con el crítico de espalda), forzar `critical = true` para el feedback y aplicar el daño extra una sola vez.

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

Run: `run_tests` con `res://tools/guard_parry_test.gd`.
Expected: PASS con 8 checks.

---

### Task 3: Windup del ataque enemigo y delegación del `AttackVolume`

**Files:**
- Modify: `scripts/combat/attack_volume.gd`
- Modify: `scripts/npc/hostile_npc.gd`
- Modify: `tools/guard_parry_test.gd`

**Interfaces:**
- Produces:
  - `AttackVolume.begin_swing(damage, source, open_at, close_at, clip_length, windup: float = 0.0)`
  - `AttackVolume` llama `body.receive_attack(amount, source)` si existe.

- [ ] **Step 1: Escribir el test de windup y delegación**

Añadir al test:
- Un `AttackVolume` con `begin_swing(10.0, volume, 0.0, 1.0, 1.0, 0.3)`: a los 0,1 s el objetivo sigue a 100; a los 0,4 s baja a 90.
- Un cuerpo con `receive_attack` que devuelve `true` no recibe `Combatant.take_damage` por el camino por defecto.
- Un cuerpo sin `receive_attack` sigue recibiendo daño normal.

- [ ] **Step 2: Ejecutar y verificar que falla**

Run: `run_tests` con `res://tools/guard_parry_test.gd`.
Expected: FAIL porque `begin_swing` no acepta `windup` y no delega.

- [ ] **Step 3: Implementar en `AttackVolume`**

Añadir el parámetro `windup := 0.0` y desplazar `_open_at` y `_close_at` por `windup`.

En `_try_hit`:

```gdscript
var handled := false
if body.has_method("receive_attack"):
	handled = bool(body.call("receive_attack", _damage, _source))
if not handled:
	combatant.take_damage(_damage, _source.global_position if _source != null else global_position)
landed.emit(body, _damage, was_stunned)
```

- [ ] **Step 4: Telegrafiar al bandido**

En `hostile_npc.gd`, añadir `ATTACK_WINDUP := 0.35` y `ATTACK_ANIM_SPEED := 0.7`. En `_try_attack`, reproducir el clip a `0.7`, calcular `clip_length` con esa velocidad y llamar `_volume.begin_swing(..., clip_length, ATTACK_WINDUP)`. El empuje usa el mismo windup.

- [ ] **Step 5: Ejecutar los tests y verificar que pasan**

Run: `run_tests` con `res://tools/guard_parry_test.gd`.
Expected: PASS con 11 checks, y `tools/combat_test.gd` sigue en 94 checks.

---

### Task 4: HUD de guardia, parry y contraataque

**Files:**
- Modify: `scripts/ui/hud.gd`

**Interfaces:**
- Consumes: `guard_changed`, `parried`, `riposte_changed`.
- Produces: barra visual bajo la vida y carteles centrales.

- [ ] **Step 1: Añadir la barra de guardia**

En `_build_health`, crear un fondo de 190×6 en `y = 58` y un `ColorRect` de 186×4 en `y = 59`, color azul acero. Guardar `_guard_fill` y conectar `player.guard_changed` a `_on_guard_changed`.

- [ ] **Step 2: Añadir carteles de parry/riposte**

Crear `_parry_label` centrado a `y = 120`, dorado, oculto. En `_on_parried`, mostrar `PARRY` y desvanecerlo con un tween. Crear `_riposte_label` a `y = 150`, mostrar `CONTRAATAQUE` mientras `riposte_changed(true)` esté activo y ocultarlo al consumirse.

- [ ] **Step 3: Verificar en el juego**

Run: `run_scene` con `res://scenes/main.tscn`, `duration_ms: 3000`.
Expected: el HUD sigue funcionando y no hay errores de script.

---

### Task 5: Verificación final

**Files:** ninguno nuevo.

- [ ] **Step 1: Ejecutar el test nuevo**

Run: `run_tests` con `res://tools/guard_parry_test.gd`.
Expected: PASS con 11 checks.

- [ ] **Step 2: Ejecutar el test de combate existente**

Run: `run_tests` con `res://tools/combat_test.gd`.
Expected: PASS con 94 checks, sin regresiones.

- [ ] **Step 3: Probar en vivo**

Run: `run_scene` con `res://scenes/main.tscn`, `duration_ms: 3000`, y comprobar que el juego arranca, el HUD muestra la barra de guardia y no hay errores de parseo nuevos.

- [ ] **Step 4: Revisar el diff**

Run: `git diff -- scripts/player/rito.gd scripts/player/rito_combat.gd scripts/combat/attack_volume.gd scripts/npc/hostile_npc.gd scripts/ui/hud.gd project.godot tools/guard_parry_test.gd`.
Expected: solo los cambios descritos; `tools/combat_test.gd` intacto.