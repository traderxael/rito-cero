# Combate de Rito Cero — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar a Rito un gladius y una lanza intercambiables que golpean, convertir los 4 NPCs del valle en hostiles con aggro/persecución/ataque/vida/muerte, y que el jugador también pueda morir y reaparecer.

**Architecture:** Un componente `Combatant` es el dueño único de la vida (Rito y cada NPC llevan uno). El ataque se detecta con un `Area3D` que solo se activa durante la ventana del golpe, montado en el eje frontal del modelo (no en el hueso de la mano, cuya orientación no está verificada). `rito.gd` gana un bloqueo de animación de un solo disparo para que un tajo no se corte al dar un paso.

**Tech Stack:** Godot 4.7.2-stable, GDScript, renderer `gl_compatibility` (WebGL2), Terrain3D 1.1 (GDExtension), Jolt Physics, export web sin hilos con Extensions Support.

**Spec:** `docs/superpowers/specs/2026-11-02-rito-cero-combate-design.md` — y su base, `docs/superpowers/specs/2026-11-02-rito-cero-web-design.md` (§14).

## Global Constraints

- Renderer **`gl_compatibility`** obligatorio; no introducir nada que exija Forward+/Mobile.
- **Sombras dinámicas: cero.** Ni `shadow_enabled` en luces nuevas ni `cast_shadow` en geometrías nuevas (esta GPU: ≈3 FPS con sombras vs ≈66 sin).
- **Luces nuevas: máximo 1** (la antorcha nocturna ya es esa una). Nada de luces en el arma ni en los impactos.
- **Ningún asset externo**: ni descargas, ni addons nuevos, ni modelos. Armas con primitivas.
- Umbral de rendimiento: **≥ 36 FPS en Chrome con GPU real** (base medida 42,0) y **sin bajar de 51 FPS** en el banco nativo (base 60,0 con tope de vsync). Regresión > 15 % ⇒ aplicar los repliegues de la Tarea 10.
- Luces y materiales: cada instancia con fogonazo propio necesita **copia de material**, no material compartido.
- Comentarios y nombres de archivo/mensajes de commit en **español**, sin emojis.
- Tras crear un script con `class_name`, refrescar el caché de clases globales antes de ejecutar nada:
  `"<GODOT>" --headless --path "<PROY>" --import`
  (Ya pasó en este proyecto: `Identifier "DevVariants" not declared` por ejecutar sin reescanear.)
- Un commit por tarea, al final de la tarea, con el test en verde.

Rutas de trabajo:

```bash
GODOT="C:/Users/USUARIO/Tools/godot/Godot_v4.7.2-stable_win64.exe"
PROY="C:/Users/USUARIO/Documents/rito-cero-"
```

---

## Mapa de archivos

| Archivo | Qué |
|---|---|
| Crear `scripts/combat/combatant.gd` | Dueño único de la vida. `class_name Combatant` |
| Crear `scripts/combat/weapon.gd` | Factoría de geometrías gladius/lanza |
| Crear `scripts/combat/weapons_holder.gd` | Monta el arma en la mano y la cambia |
| Crear `scripts/combat/attack_volume.gd` | `Area3D` de ventana de impacto. `class_name AttackVolume` |
| Crear `scripts/player/rito_combat.gd` | Input de combate, cadencia, cambio de arma |
| Crear `scripts/npc/hostile_npc.gd` | Máquina de estados del NPC hostil |
| Crear `tools/combat_test.gd` | Arnés de asserts headless |
| Crear `tools/anim_report.gd` | Volcado de nombres/duraciones de animación |
| Modificar `scripts/player/rito.gd` | Bloqueo one-shot, muerte/reaparición, antorcha a mano izquierda |
| Modificar `scripts/player/rito_outfit.gd` | `add_torch` usa `DEF-hand.L` |
| Modificar `scripts/ui/hud.gd` | Barra de vida + contador de bajas |
| Modificar `scripts/world/structures.gd` | Cambia `roman_npc.gd` por `hostile_npc.gd` |
| Modificar `scripts/main.gd` | Crea el componente de combate de Rito |
| Modificar `project.godot` | Acciones `attack`, `heavy_attack`, `weapon_1`, `weapon_2` |
| Dejar `scripts/npc/roman_npc.gd` | Se conserva: `hostile_npc.gd` hereda de él |

`roman_npc.gd` **no se borra**: `hostile_npc.gd` hace `extends` del script y reescribe solo
la toma de decisiones. Así la patrulla que ya funciona no se reescribe a mano.

---

## Task 0: Medir las animaciones antes de escribir nada de combate

Las ventanas de impacto se expresan como fracción de la duración del clip. Sin las
duraciones reales, todo lo que sigue son números inventados.

**Files:**
- Create: `tools/anim_report.gd`

**Interfaces:**
- Produces: una tabla impresa de nombres exactos y duraciones que las tareas 4, 5 y 9 usan
  para fijar sus fracciones.

- [x] **Step 1: Escribir el volcado**

`tools/anim_report.gd`:

```gdscript
extends SceneTree

const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"
const CLAVELES := [
	"Sword_Idle", "Sword_Attack", "Sword_Attack_RM",
	"Punch_Jab", "Punch_Cross", "Punch_Enter",
	"Hit_Chest", "Hit_Head", "Death01",
	"Idle_Loop", "Walk_Loop", "Sprint_Loop", "Jog_Fwd",
]


func _init() -> void:
	var mannequin: Node3D = (load(MANNEQUIN_SCENE) as PackedScene).instantiate()
	root.add_child(mannequin)
	await process_frame
	var player := _find_player(mannequin)
	print("ANIM-COUNT ", player.get_animation_list().size())
	var names := player.get_animation_list()
	names.sort()
	for name in names:
		print("ANIM ", name, " len=", player.get_animation(name).length)
	print("--- claveles ---")
	for name in CLAVELES:
		print("CLAVE ", name, " existe=", player.has_animation(name),
			" len=", player.get_animation(name).length if player.has_animation(name) else -1.0)
	quit()


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
```

- [x] **Step 2: Ejecutarlo**

```bash
"$GODOT" --headless --path "$PROY" --script "res://tools/anim_report.gd" 2>&1 | grep -E "^CLAVE|^ANIM-COUNT"
```

Esperado: `ANIM-COUNT 46`, y `existe=true` para los 13 claveles. Los nombres del pack
pierden el sufijo `_Loop` al importar (`Idle_Loop` se importa **como** `Idle_Loop`, pero
`Jog_Fwd_Loop` se importa `Jog_Fwd`): esta salida es la que decide qué candidato gana, no
lo que dice la documentación.

- [x] **Step 3: Anotar las duraciones**

Escribir en la spec, sección 4.5, una columna nueva `Duración real` con el valor impreso de
`Sword_Attack`, `Punch_Jab`, `Hit_Chest` y `Death01`. Si algún clavel sale `existe=false`,
añadir su alias real a las listas `ANIM_*` de `rito.gd` antes de seguir.

- [x] **Step 4: Commit**

```bash
git add tools/anim_report.gd docs/superpowers/specs/2026-11-02-rito-cero-combate-design.md
git commit -m "Anade volcado de animaciones y registra duraciones reales"
```

---

## Task 1: `Combatant` con su arnés de tests

Es la pieza que todo lo demás consume. Se prueba sola, sin escena de juego.

**Files:**
- Create: `scripts/combat/combatant.gd`
- Create: `tools/combat_test.gd`

**Interfaces:**
- Produces:
  - `Combatant.setup(max_health: float, invulnerable_seconds: float = 0.0) -> void`
  - `Combatant.take_damage(amount: float, source_position: Vector3) -> void`
  - `Combatant.is_alive() -> bool`
  - `Combatant.heal_full(invulnerable_seconds: float = 0.0) -> void`
  - `Combatant.make_invulnerable(seconds: float) -> void`
  - señales `health_changed(current, maximum)`, `damaged(amount, source_position)`, `died(source_position)`
- Consumes: nada.

- [x] **Step 1: Escribir el test que falla**

`tools/combat_test.gd`:

```gdscript
extends SceneTree

const CombatantScript := preload("res://scripts/combat/combatant.gd")

var _failures := 0


func _init() -> void:
	_test_damage_kills_once()
	_test_damage_after_death_ignored()
	_test_clamp_and_heal()
	_test_invulnerable()
	print("TEST failures=", _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		print("FAIL ", label)
	else:
		print("ok ", label)


func _make(max_health: float) -> Node:
	var combatant: Node = CombatantScript.new()
	root.add_child(combatant)
	combatant.setup(max_health)
	return combatant


func _test_damage_kills_once() -> void:
	var combatant := _make(60.0)
	var deaths := [0]
	combatant.died.connect(func(_p): deaths[0] += 1)
	combatant.take_damage(34.0, Vector3.ZERO)
	_check(combatant.is_alive(), "60hp con 34 de dano sigue vivo")
	_check(is_equal_approx(combatant.health, 26.0), "vida restante 26")
	combatant.take_damage(34.0, Vector3.ONE)
	_check(not combatant.is_alive(), "60hp muerto tras 68 de dano")
	_check(deaths[0] == 1, "died emitido exactamente una vez")


func _test_damage_after_death_ignored() -> void:
	var combatant := _make(60.0)
	var deaths := [0]
	combatant.died.connect(func(_p): deaths[0] += 1)
	combatant.take_damage(999.0, Vector3.ZERO)
	combatant.take_damage(999.0, Vector3.ZERO)
	_check(deaths[0] == 1, "danar a un muerto no re-emite died")
	_check(is_equal_approx(combatant.health, 0.0), "la vida no baja de 0")


func _test_clamp_and_heal() -> void:
	var combatant := _make(100.0)
	combatant.take_damage(-5.0, Vector3.ZERO)
	_check(is_equal_approx(combatant.health, 100.0), "dano negativo no cura")
	combatant.take_damage(30.0, Vector3.ZERO)
	combatant.heal_full()
	_check(combatant.is_alive(), "heal_full revive")
	_check(is_equal_approx(combatant.health, 100.0), "heal_full deja vida llena")


func _test_invulnerable() -> void:
	var combatant := _make(100.0)
	combatant.make_invulnerable(0.3)
	combatant.take_damage(50.0, Vector3.ZERO)
	_check(is_equal_approx(combatant.health, 100.0), "invulnerable no recibe dano")
```

- [x] **Step 2: Ejecutar y verificar que falla**

```bash
"$GODOT" --headless --path "$PROY" --script "res://tools/combat_test.gd" 2>&1 | grep -E "^TEST|^FAIL|Parse Error" | head
```

Esperado: fallo de compilación (`Identifier "Combatant" not declared` o `Failed to load script`), porque `combatant.gd` todavía no existe.

- [x] **Step 3: Escribir la implementación mínima**

`scripts/combat/combatant.gd`:

```gdscript
class_name Combatant
extends Node

## Dueño único de la vida de quien lo lleva. Ni el jugador ni los NPCs deciden solos
## cuanto les queda: todo pasa por aqui, y las reglas de reentrancia se comprueban aqui.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source_position: Vector3)
signal died(source_position: Vector3)

var max_health := 100.0
var health := 100.0
var _dead := false
var _invulnerable_until := 0.0


func setup(p_max_health: float, invulnerable_seconds: float = 0.0) -> void:
	max_health = p_max_health
	health = p_max_health
	_dead = false
	_invulnerable_until = _now() + invulnerable_seconds
	health_changed.emit(health, max_health)


func take_damage(amount: float, source_position: Vector3) -> void:
	if _dead or amount <= 0.0:
		return
	if _now() < _invulnerable_until:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, source_position)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_dead = true
		died.emit(source_position)


func heal_full(invulnerable_seconds: float = 0.0) -> void:
	health = max_health
	_dead = false
	_invulnerable_until = _now() + invulnerable_seconds
	health_changed.emit(health, max_health)


func make_invulnerable(seconds: float) -> void:
	_invulnerable_until = _now() + seconds


func is_alive() -> bool:
	return not _dead


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
```

- [x] **Step 4: Refrescar el caché de clases y ejecutar el test**

```bash
"$GODOT" --headless --path "$PROY" --import > /dev/null 2>&1
"$GODOT" --headless --path "$PROY" --script "res://tools/combat_test.gd" 2>&1 | grep -E "^TEST|^FAIL"
```

Esperado: `TEST failures=0` y salida 0.

- [x] **Step 5: Commit**

```bash
git add scripts/combat/combatant.gd tools/combat_test.gd
git commit -m "Anade Combatant con test de dano, muerte unica e invulnerabilidad"
```

---

## Task 2: Geometrías de arma y montaje en la mano

**Files:**
- Create: `scripts/combat/weapon.gd`
- Create: `scripts/combat/weapons_holder.gd`
- Modify: `scripts/player/rito_outfit.gd` (función `add_torch`, mano derecha → izquierda)
- Modify: `scripts/player/rito.gd` (`_build_model`, crear el holder)

**Interfaces:**
- Consumes: `MeshFactory._merge(parts: Array) -> ArrayMesh` (`scripts/world/mesh_factory.gd:290`), que espera diccionarios `{"mesh", "transform", "color", "top_color"}`.
- Produces:
  - `Weapon.make_gladius() -> ArrayMesh`, `Weapon.make_spear() -> ArrayMesh`
  - `WeaponsHolder.setup(skeleton: Skeleton3D) -> void`, `.switch_to(index: int) -> void`,
    `.current_damage() -> float`, `.current_cooldown() -> float`, `.current_reach() -> float`,
    `.current_window() -> Vector2`, `.current_anim_speed() -> float`,
    `.signal weapon_changed(index: int)`

- [x] **Step 1: Escribir la factoría**

`scripts/combat/weapon.gd`:

```gdscript
class_name Weapon
extends RefCounted

const MeshFactoryScript := preload("res://scripts/world/mesh_factory.gd")

const BLADE := Color(0.78, 0.80, 0.84)
const BRONZE := Color(0.62, 0.45, 0.20)
const GRIP := Color(0.30, 0.20, 0.12)
const SHAFT := Color(0.45, 0.33, 0.18)
const SPEAR_TIP := Color(0.72, 0.74, 0.78)

## Alcance efectivo de cada arma, en metros desde el centro del personaje.
const REACH := [2.2, 3.4]
const DAMAGE := [34.0, 46.0]
const COOLDOWN := [0.55, 0.85]
const WINDOW := [[0.25, 0.55], [0.30, 0.60]]
## Multiplicador de reproduccion. Medido en la Task 0: Sword_Attack dura 1,533 s y
## Punch_Jab 0,867 s. Con el gladius a 1,0x la ventana cierra a los 0,843 s, despues de la
## cadencia de 0,55 s; a 2,0x cierra a los 0,422 s. La lanza no necesita reescalado.
const ANIM_SPEED := [2.0, 1.0]


static func make_gladius() -> ArrayMesh:
	var parts: Array = []
	var blade := BoxMesh.new()
	blade.size = Vector3(0.05, 0.10, 0.82)
	parts.append({"mesh": blade, "transform": Transform3D(Basis(), Vector3(0, 0, 0.46)), "color": BLADE})

	var guard := BoxMesh.new()
	guard.size = Vector3(0.17, 0.05, 0.05)
	parts.append({"mesh": guard, "transform": Transform3D(Basis(), Vector3(0, 0, 0.04)), "color": BRONZE})

	var grip := CylinderMesh.new()
	grip.top_radius = 0.022
	grip.bottom_radius = 0.026
	grip.height = 0.16
	grip.radial_segments = 6
	grip.rings = 1
	var grip_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({"mesh": grip, "transform": Transform3D(grip_basis, Vector3(0, 0, -0.06)), "color": GRIP})
	return MeshFactoryScript._merge(parts)


static func make_spear() -> ArrayMesh:
	var parts: Array = []
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.026
	shaft.bottom_radius = 0.028
	shaft.height = 2.3
	shaft.radial_segments = 6
	shaft.rings = 1
	var shaft_basis := Basis(Vector3.RIGHT, PI * 0.5)
	parts.append({"mesh": shaft, "transform": Transform3D(shaft_basis, Vector3(0, 0, 0.95)), "color": SHAFT})

	var tip := CylinderMesh.new()
	tip.top_radius = 0.001
	tip.bottom_radius = 0.055
	tip.height = 0.30
	tip.radial_segments = 6
	tip.rings = 1
	var tip_basis := Basis(Vector3.RIGHT, -PI * 0.5)
	parts.append({"mesh": tip, "transform": Transform3D(tip_basis, Vector3(0, 0, 2.24)), "color": SPEAR_TIP})
	return MeshFactoryScript._merge(parts)
```

- [x] **Step 2: Escribir el holder**

`scripts/combat/weapons_holder.gd`:

```gdscript
class_name WeaponsHolder
extends Node3D

## Monta las dos armas en la mano derecha y muestra solo la activa. El arma es hija del
## BoneAttachment3D, asi que sigue al brazo durante el ataque.

signal weapon_changed(index: int)

const WeaponScript := preload("res://scripts/combat/weapon.gd")

var _attachments: Array[BoneAttachment3D] = []
var _current := 0


func setup(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for i in 2:
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "DEF-hand.R"
		skeleton.add_child(attachment)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = WeaponScript.make_gladius() if i == 0 else WeaponScript.make_spear()
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.5
		material.metallic = 0.4
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mesh_instance.material_override = material
		# La palma del maniqui mira hacia -Y en su espacio local; el arma apunta +Z.
		mesh_instance.rotation.x = -0.35
		attachment.add_child(mesh_instance)
		attachment.visible = (i == 0)
		_attachments.append(attachment)


func switch_to(index: int) -> void:
	if index < 0 or index >= _attachments.size() or index == _current:
		return
	_attachments[_current].visible = false
	_current = index
	_attachments[_current].visible = true
	weapon_changed.emit(_current)


func current_index() -> int:
	return _current


func current_damage() -> float:
	return WeaponScript.DAMAGE[_current]


func current_cooldown() -> float:
	return WeaponScript.COOLDOWN[_current]


func current_reach() -> float:
	return WeaponScript.REACH[_current]


func current_window() -> Vector2:
	var pair: Array = WeaponScript.WINDOW[_current]
	return Vector2(float(pair[0]), float(pair[1]))


func current_anim_speed() -> float:
	return WeaponScript.ANIM_SPEED[_current]
```

- [x] **Step 3: Mover la antorcha a la mano izquierda**

En `scripts/player/rito_outfit.gd`, dentro de `add_torch`, cambiar el hueso:

```gdscript
	var attachment := _attachment(skeleton, "DEF-hand.L")
```

Motivo: arma y antorcha reclamaban el mismo `DEF-hand.R` y se habrían secuestrado el uno al
otro. La antorcha a la izquierda deja la derecha libre para el arma y la luz sigue valiendo.

- [x] **Step 4: Crear el holder en Rito**

En `scripts/player/rito.gd`, añadir la variable junto a las otras (`:41`, al lado de `torch`):

```gdscript
var weapons: WeaponsHolder
```

y al final de `_build_model()` (después de `torch = RitoOutfitScript.add_torch(skeleton)`):

```gdscript
	if skeleton != null:
		weapons = WeaponsHolder.new()
		weapons.name = "Weapons"
		add_child(weapons)
		weapons.setup(skeleton)
```

- [x] **Step 5: Verificar que el juego arranca y el arma se ve**

```bash
"$GODOT" --headless --path "$PROY" --import > /dev/null 2>&1
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/shot.tscn" 2>&1 | grep -E "^SHOT|SCRIPT ERROR|Invalid" | head
```

Esperado: `SHOT saved=0`, cero `SCRIPT ERROR`. Luego abrir
`C:/Users/USUARIO/AppData/Roaming/Godot/app_userdata/rito cero/shot_light.png` y comprobar
que Rito sostiene un objeto alargado en la mano derecha. Si el arma sale atravesada en el
suelo o mirando hacia atrás, ajustar `mesh_instance.rotation.x` del Step 2.

- [x] **Step 6: Commit**

```bash
git add scripts/combat/weapon.gd scripts/combat/weapons_holder.gd scripts/player/rito.gd scripts/player/rito_outfit.gd
git commit -m "Anade gladius y lanza con montaje en la mano y antorcha a la izquierda"
```

---

## Task 3: Bloqueo de animación de un solo disparo en `rito.gd`

Sin esto, el ataque se corta en cuanto el jugador da un paso. Es un cambio de mecanismo, no
de política: quien decide *qué* se reproduce es la tarea 4.

**Files:**
- Modify: `scripts/player/rito.gd:140-168` (`_update_model`)
- Modify: `scripts/player/rito.gd:33-44` (nuevas variables)

**Interfaces:**
- Produces:
  - `Rito.play_one_shot(name: String, lock_seconds: float) -> void`
  - `Rito.is_locked() -> bool`
  - `Rito.set_combat_priority(state: String, lock_seconds: float) -> void` — `dying` > `hit` > `attack`
- Consumes: `animation_player`, `_animation_state`, `BLEND_TIME` ya existentes.

- [x] **Step 1: Añadir el estado del bloqueo**

En `scripts/player/rito.gd`, junto a las variables privadas (`:33-44`):

```gdscript
var _lock_until := 0.0
var _lock_priority := 0
const PRIORITY_ATTACK := 1
const PRIORITY_HIT := 2
const PRIORITY_DYING := 3
```

- [x] **Step 2: Escribir los métodos**

Al final de `rito.gd`:

```gdscript
func play_one_shot(name: String, lock_seconds: float, priority: int, speed: float = 1.0) -> void:
	if animation_player == null or name == "":
		return
	if not animation_player.has_animation(name):
		return
	if priority < _lock_priority and is_locked():
		return
	_lock_priority = priority
	_lock_until = _now() + lock_seconds
	_animation_state = name
	animation_player.speed_scale = speed
	animation_player.play(name, 0.0)


func is_locked() -> bool:
	return _now() < _lock_until


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
```

`speed` existe por lo medido en la Task 0: `Sword_Attack` dura 1,533 s reales y la cadencia del
gladius es 0,55 s, así que a 1,0× la ventana de daño se abriría y cerraría después de que el
jugador ya pueda volver a golpear. Lo que se bloquea son los segundos **efectivos**
(`length / speed`), no los del clip.

- [x] **Step 3: Respetar el bloqueo en la locomoción**

En `_update_model()` (`:157`), envolver la selección de estado:

```gdscript
	if is_locked():
		return
	if state != "" and animation_player != null:
		...
```

y en el mismo sitio, al final de `_update_model`, decaer la prioridad cuando el bloqueo
termine:

```gdscript
	if _lock_priority > 0 and not is_locked():
		_lock_priority = 0
		_animation_state = ""
```

- [x] **Step 4: Verificar que nada rompió**

```bash
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/bench.tscn" -- --variant 1 2>&1 | grep -E "^BENCH|SCRIPT ERROR" | head -6
```

Esperado: `BENCH-SUMMARY v=light median_avg=60.0` (o ≥ 51) y cero `SCRIPT ERROR`. El bloqueo
no debe cambiar el FPS: es una comparación de tiempo por frame.

- [x] **Step 5: Commit**

```bash
git add scripts/player/rito.gd
git commit -m "Anade bloqueo de animacion de un solo disparo con prioridad"
```

---

## Task 4: `AttackVolume` y su ventana de impacto

**Files:**
- Create: `scripts/combat/attack_volume.gd`
- Modify: `tools/combat_test.gd` (nuevos casos de alcance)

**Interfaces:**
- Consumes: `Combatant.take_damage(amount, source_position)` (Tarea 1).
- Produces:
  - `AttackVolume.setup(reach: float, radius: float, mask: int) -> void`
  - `AttackVolume.begin_swing(damage: float, source: Node3D, open_at: float, close_at: float, clip_length: float) -> void`
  - `AttackVolume.end_swing() -> void`
  - señal `landed(target: Node, damage: float)`

- [x] **Step 1: Escribir el test de alcance que falla**

Añadir a `tools/combat_test.gd` (dentro de `_init`, tras los tests existentes) y la función:

```gdscript
func _test_reach_hits_and_misses() -> void:
	var holder := _make_combat_target(Vector3(0, 0, -2.0))
	var miss := _make_combat_target(Vector3(0, 0, -3.6))
	var volume := _make_volume(2.2, 0.75)
	volume.begin_swing(34.0, holder, 0.0, 0.05, 1.0)
	await process_frame
	await process_frame
	_check(is_equal_approx(holder.health, 26.0), "objetivo a 2,0 m recibe el tajo")
	_check(is_equal_approx(miss.health, 60.0), "objetivo a 3,6 m no lo recibe")
	volume.end_swing()
	holder.queue_free()
	miss.queue_free()
	volume.queue_free()
```

Con los ayudantes:

```gdscript
func _make_combat_target(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	body.add_child(shape)
	body.position = at
	root.add_child(body)
	var combatant: Node = CombatantScript.new()
	body.add_child(combatant)
	combatant.setup(60.0)
	return body


func _make_volume(reach: float, radius: float) -> AttackVolume:
	var volume := AttackVolume.new()
	volume.position = Vector3.ZERO
	root.add_child(volume)
	volume.setup(reach, radius, 4)
	return volume
```

Y en `_init`, llamarla con `await` (el arnés debe volverse coroutine: `func _init() -> void:`
seguido de `await` no funciona; usar `_test_reach_hits_and_misses()` dentro de un
`func _run() -> void` llamado desde `_init` con `await _run()`).

- [x] **Step 2: Ejecutar y confirmar el fallo**

```bash
"$GODOT" --headless --path "$PROY" --script "res://tools/combat_test.gd" 2>&1 | grep -E "^TEST|^FAIL|Parse Error" | head
```

Esperado: fallo por `Identifier "AttackVolume" not declared`.

- [x] **Step 3: Implementar el volumen**

`scripts/combat/attack_volume.gd`:

```gdscript
class_name AttackVolume
extends Area3D

## Ventana de impacto del cuerpo a cuerpo. No es un raycast por frame: a 40 FPS un tajo
## rapido puede saltarse un objetivo. El area solo existe durante los fotogramas activos
## del clip, y un mismo swing no golpea dos veces al mismo objetivo.

signal landed(target: Node, damage: float)

var _open := false
var _damage := 0.0
var _source: Node3D
var _hit: Array[Rid] = []
var _close_at := 0.0
var _opened_at := 0.0


func _ready() -> void:
	monitoring = false
	monitorable = false
	body_entered.connect(_on_body_entered)


func setup(reach: float, radius: float, target_mask: int) -> void:
	collision_layer = 8
	collision_mask = target_mask
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	# El volumen es hijo del nodo Model del personaje, y el maniqui mira a +Z:
	# el frente es +Z, no -Z como en el resto de Godot.
	shape.position = Vector3(0, 1.2, reach)
	add_child(shape)


func begin_swing(damage: float, source: Node3D, open_at: float, close_at: float, clip_length: float) -> void:
	_damage = damage
	_source = source
	_hit.clear()
	_opened_at = _now()
	_close_at = _opened_at + maxf(clip_length * (close_at - open_at), 0.05)
	monitoring = true
	_open = true
	# Si la ventana abre tarde, el golpe ya no existe cuando llega.
	if open_at > 0.0:
		_open = false
		monitoring = false
		get_tree().create_timer(clip_length * open_at).timeout.connect(_activate)


func end_swing() -> void:
	_open = false
	monitoring = false


func _activate() -> void:
	_open = true
	monitoring = true


func _process(_delta: float) -> void:
	if _open and _now() >= _close_at:
		end_swing()


func _on_body_entered(body: Node3D) -> void:
	if not _open:
		return
	if _hit.has(body.get_rid()):
		return
	var combatant := body.get_node_or_null("Combatant")
	if combatant == null or not combatant.is_alive():
		return
	_hit.append(body.get_rid())
	combatant.take_damage(_damage, _source.global_position if _source != null else global_position)
	landed.emit(body, _damage)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
```

En el test, el nodo `Combatant` debe crearse con `name = "Combatant"` para que
`get_node_or_null("Combatant")` lo encuentre: añadir `combatant.name = "Combatant"` en
`_make_combat_target`.

- [x] **Step 4: Ejecutar el test**

```bash
"$GODOT" --headless --path "$PROY" --import > /dev/null 2>&1
"$GODOT" --headless --path "$PROY" --script "res://tools/combat_test.gd" 2>&1 | grep -E "^TEST|^FAIL|^ok"
```

Esperado: `TEST failures=0`. **Si en headless las señales `body_entered` no llegan** (el
`Area3D` necesita el espacio físico activo), ejecutar el mismo test en ventana:

```bash
"$GODOT" --path "$PROY" --rendering-driver opengl3 --quit-after 200 --script "res://tools/combat_test.gd" 2>&1 | grep -E "^TEST|^FAIL"
```

Los asserts no cambian; solo cambia cómo se levanta el motor.

- [x] **Step 5: Commit**

```bash
git add scripts/combat/attack_volume.gd tools/combat_test.gd
git commit -m "Anade AttackVolume con ventana por fraccion del clip"
```

**Lo que cambió al ejecutarla** (el código de arriba ya no es el que está en el repo):

- `_close_at` se calculaba como principio + `clip*(close-open)`, o sea la *duración*, mientras
  la apertura se retrasaba con un timer. Con `open_at=0,25` y `close_at=0,55` sobre un clip de
  1 s la ventana duraba 0,05 s en vez de 0,30 s. Ahora ambos bordes son absolutos desde el
  inicio del swing.
- `body_entered` fuera: un NPC ya pegado cuando la ventana abre nunca entra, y reencender
  `monitoring` no re-reporta a los que estaban dentro. Se barre `get_overlapping_bodies()`.
- El estado inicial no va en `_ready`: se notifica con orden diferido y apagaba el
  `monitoring` que `begin_swing` acababa de encender, dejando el tajo en error cada frame.
- `Array[Rid]` no compila, es `Array[RID]`, y el parámetro de `_try_hit` tiene que ser
  `PhysicsBody3D` para que `get_rid()` tenga tipo.
- El arnés ganó guarda de recuento de checks: con tres tests abortados por error de runtime,
  el informe decía `failures=0`.
- Los objetivos del test van a **+Z**, no a −Z, y a 0,8 m de altura para que el solape con el
  volumen a 1,2 m sea real.
- `EXPECTED_CHECKS` es 23, no 22.

---

## Task 5: Combate del jugador (input, cadencia, cambio de arma)

**Files:**
- Create: `scripts/player/rito_combat.gd`
- Modify: `scripts/main.gd:18-20` (crear el componente)
- Modify: `project.godot` (sección `[input]`: 4 acciones nuevas)

**Interfaces:**
- Consumes: `Rito.play_one_shot(name, lock_seconds, priority)`, `Rito.is_locked()`,
  `WeaponsHolder.current_damage()/current_cooldown()/current_reach()/current_window()/switch_to(i)`,
  `AttackVolume.begin_swing(...)`, las listas `ANIM_*` de `rito.gd`.
- Produces: `RitoCombat.setup(rito: Node3D) -> void`, señal `kill_count_changed(count: int)`,
  lectura pública `kills: int`, `weapon_index: int`.

- [x] **Step 1: Añadir las acciones de input**

En `project.godot`, dentro de `[input]`, cuatro bloques con el mismo formato que los
existentes. `physical_keycode`: `49` = tecla 1, `50` = tecla 2, `32` ya es salto.

```
attack={
"deadzone": 0.2,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}
heavy_attack={
"deadzone": 0.2,
"events": [Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),"factor":1.0,"button_index":2,"canceled":false,"pressed":false,"double_click":false,"script":null)
]
}
weapon_1={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":49,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
weapon_2={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":50,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

- [x] **Step 2: Escribir el componente**

`scripts/player/rito_combat.gd`:

```gdscript
class_name RitoCombat
extends Node

## Politica de combate del jugador: que se pulsa, cuando se puede volver a golpear y que
## animacion va con cada arma. El mecanismo de bloqueo vive en rito.gd, aqui no se repite.

signal kill_count_changed(count: int)

const AttackVolumeScript := preload("res://scripts/combat/attack_volume.gd")

const ANIM_ATTACK := ["Sword_Attack", "Punch_Jab"]
const ANIM_HEAVY := ["Sword_Attack_RM", "Punch_Cross"]
const ANIM_SPEAR_THRUST := ["Punch_Jab"]

var kills := 0
var weapon_index := 0

var _rito: Node3D
var _volume: AttackVolume
var _cooldown_until := 0.0
var _resolved_attack := ""
var _resolved_heavy := ""
var _resolved_thrust := ""


func setup(rito: Node3D) -> void:
	_rito = rito
	var player: AnimationPlayer = rito.get("animation_player")
	if player != null:
		_resolved_attack = _first_existing(player, ANIM_ATTACK)
		_resolved_heavy = _first_existing(player, ANIM_HEAVY)
		_resolved_thrust = _first_existing(player, ANIM_SPEAR_THRUST)

	_volume = AttackVolumeScript.new()
	_volume.name = "AttackVolume"
	var model: Node3D = rito.get("model")
	model.add_child(_volume)
	_volume.landed.connect(_on_landed)


func _process(_delta: float) -> void:
	if _rito == null or not _rito.is_alive():
		return
	if Input.is_action_pressed("weapon_1"):
		_switch(0)
	elif Input.is_action_pressed("weapon_2"):
		_switch(1)
	if Input.is_action_just_pressed("attack"):
		_try_attack(false)
	elif Input.is_action_just_pressed("heavy_attack"):
		_try_attack(true)


func _switch(index: int) -> void:
	if index == weapon_index:
		return
	weapon_index = index
	var holder: Node = _rito.get("weapons")
	if holder != null:
		holder.call("switch_to", index)
		_volume.call("setup", holder.call("current_reach"), 0.75 if index == 0 else 0.45, 4)


func _try_attack(heavy: bool) -> void:
	if _now() < _cooldown_until:
		return
	if _rito.is_locked():
		return
	var holder: Node = _rito.get("weapons")
	if holder == null:
		return
	var damage: float = float(holder.call("current_damage")) * (1.25 if heavy else 1.0)
	var cooldown: float = float(holder.call("current_cooldown")) * (1.3 if heavy else 1.0)
	var window: Vector2 = holder.call("current_window")
	var reach: float = holder.call("current_reach")

	var name := _attack_animation(heavy)
	var clip_length := 0.5
	var speed: float = holder.call("current_anim_speed")
	if heavy:
		speed *= 0.8
	if name != "":
		var player: AnimationPlayer = _rito.get("animation_player")
		# Segundos efectivos, no los del clip: el bloqueo y la ventana viven en la misma escala.
		clip_length = player.get_animation(name).length / speed
		_rito.play_one_shot(name, clip_length, Rito.PRIORITY_ATTACK, speed)
	_volume.begin_swing(damage, _rito, window.x, window.y, clip_length)
	_cooldown_until = _now() + cooldown


func _attack_animation(heavy: bool) -> String:
	if weapon_index == 1:
		# La lanza no tiene estocada en el pack: Punch_Jab es un brazo extendido en linea
		# recta, que es lo mas cerca que existe de una estocada.
		return _resolved_thrust
	if heavy and _resolved_heavy != "":
		return _resolved_heavy
	return _resolved_attack


func _on_landed(target: Node, _damage: float) -> void:
	var combatant := target.get_node_or_null("Combatant")
	if combatant != null and not combatant.is_alive():
		kills += 1
		kill_count_changed.emit(kills)


func _first_existing(player: AnimationPlayer, candidates: Array) -> String:
	for candidate in candidates:
		if player.has_animation(candidate):
			return candidate
	return ""


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
```

- [x] **Step 3: Crear el componente en `main.gd`**

Tras `add_child(rito)` (`:20`) y **antes** de `await world.attach_player(rito)`:

```gdscript
	var combat: Node = RitoCombatScript.new()
	combat.name = "Combat"
	rito.add_child(combat)
```

con `const RitoCombatScript := preload("res://scripts/player/rito_combat.gd")` arriba, y
`combat.call("setup", rito)` justo después de `await world.attach_player(rito)` (necesita el
modelo ya montado).

- [x] **Step 4: Verificar en ventana**

```bash
"$GODOT" --headless --path "$PROY" --import > /dev/null 2>&1
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/shot.tscn" 2>&1 | grep -E "^SHOT|SCRIPT ERROR|Invalid" | head
```

Esperado: cero errores. El ataque no se ve en una captura estática; se prueba en la tarea 8
con el test de combate y en la 10 en el navegador.

- [x] **Step 5: Commit**

```bash
git add scripts/player/rito_combat.gd scripts/main.gd project.godot
git commit -m "Anade combate del jugador: ataque, fuerte y cambio de arma"
```

**Lo que cambió al ejecutarla:**

- El volumen no recibía `setup()` hasta el primer cambio de arma, y `_switch` sale inmediato
  si el índice no cambia: el gladius inicial no golpeaba a nadie. Ahora `_apply_weapon_geometry()`
  se llama en `setup()` y en cada `_switch`.
- El bloqueo del uno-disparo dura `clip * close_at`, no `clip` entero. Con el clip completo
  la cadencia de la tabla quedaba sustituida por la duración de la animación (0,77 s reales
  en vez de 0,55 s).
- `switch_to` se dispara con `is_action_just_pressed`, no con `is_action_pressed`.
- El fuerte lleva sus constantes propias (`HEAVY_DAMAGE`, `HEAVY_COOLDOWN`, `HEAVY_SPEED`) en
  lugar de literales sueltos dentro de `_try_attack`.
- El test extremo a extremo espera en **tiempo de reloj**, no en fotogramas: en headless el
  bucle corre a cientos de FPS y veinte frames no alcanzan los 0,19 s en que abre la ventana
  del gladius. Con `await process_frame` el ataque nunca aterrizaba y el test daba rojo por
  motivo equivocado.

---

## Task 6: Barra de vida y contador de bajas en el HUD

**Files:**
- Modify: `scripts/ui/hud.gd:24-42` (`setup`) y añadir `_build_health()`
- Modify: `scripts/main.gd:42` (pasar el componente de combate al HUD)

**Interfaces:**
- Consumes: señales `Combatant.health_changed`, `RitoCombat.kill_count_changed`.
- Produces: `Hud.setup(player, terrain, center, combat: Node)` — **cambio de firma**, la
  llamada de `main.gd` se actualiza en el Step 3.

- [x] **Step 1: Añadir la barra**

En `scripts/ui/hud.gd`, variables nuevas junto a las existentes (`:18-21`):

```gdscript
var _health_fill: ColorRect
var _kills_label: Label
```

y el constructor, llamado desde `setup` después de `_build_compass()`:

```gdscript
func _build_health(combatant: Node, combat: Node) -> void:
	var background := ColorRect.new()
	background.color = Color(0.06, 0.05, 0.04, 0.55)
	background.size = Vector2(190, 14)
	background.position = Vector2(18, 44)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_health_fill = ColorRect.new()
	_health_fill.color = Color(0.72, 0.24, 0.20)
	_health_fill.size = Vector2(186, 10)
	_health_fill.position = Vector2(20, 46)
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_health_fill)

	_kills_label = Label.new()
	_kills_label.text = "Bajas: 0"
	_kills_label.add_theme_font_size_override("font_size", 15)
	_kills_label.add_theme_color_override("font_color", Color(0.90, 0.84, 0.70))
	_kills_label.position = Vector2(18, 62)
	_kills_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_kills_label)

	combatant.health_changed.connect(_on_health_changed)
	if combat != null:
		combat.kill_count_changed.connect(_on_kills_changed)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_fill.size.x = 186.0 * clampf(current / maxf(maximum, 1.0), 0.0, 1.0)


func _on_kills_changed(count: int) -> void:
	_kills_label.text = "Bajas: %d" % count
```

- [x] **Step 2: Cambiar la firma de `setup`**

```gdscript
func setup(player: Node3D, terrain: Terrain3D, center: Vector3, combat: Node) -> void:
```

y al final del cuerpo:

```gdscript
	var combatant := player.get_node_or_null("Combatant")
	if combatant != null:
		_build_health(combatant, combat)
```

- [x] **Step 3: Pasar el combate desde `main.gd`**

```gdscript
	hud.call("setup", rito, world.terrain, world.spawn_point, combat)
```

- [x] **Step 4: Verificar**

```bash
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/shot.tscn" 2>&1 | grep -E "^SHOT|SCRIPT ERROR|Invalid" | head
```

Esperado: cero errores y, en la captura, una barra roja bajo "RITO" arriba a la izquierda.

- [x] **Step 5: Commit**

```bash
git add scripts/ui/hud.gd scripts/main.gd
git commit -m "Anade barra de vida y contador de bajas al HUD"
```

---

## Task 7: NPCs hostiles

**Files:**
- Create: `scripts/npc/hostile_npc.gd`
- Modify: `scripts/world/structures.gd:7` y `:123-128` (`_build_npc`)

**Interfaces:**
- Consumes: `Combatant`, `AttackVolume`, `Weapon.make_gladius()`, `Rito` como objetivo
  (su `Combatant` en el nodo hijo `"Combatant"`).
- Produces: `HostileNpc.setup(data, center: Vector3, angle: float, target: Node3D) -> void`,
  `HostileNpc.state: String` para el test.

- [x] **Step 1: Escribir el NPC hostil**

`scripts/npc/hostile_npc.gd`:

```gdscript
extends "res://scripts/npc/roman_npc.gd"

## NPC hostil: hereda la fisica y la evitacion por raycast del patrullador y le anade
## aggro, persecucion, ataque, golpe recibido y muerte. Sin NavMesh a proposito: el
## horneado en runtime es sincrono y en el export web sin hilos congelaria el juego.

const CombatantScript := preload("res://scripts/combat/combatant.gd")
const AttackVolumeScript := preload("res://scripts/combat/attack_volume.gd")
const WeaponScript := preload("res://scripts/combat/weapon.gd")
const MANNEQUIN_SCENE := "res://Godot/AnimationLibrary_Godot_Standard.glb"

const AGGRO_RANGE := 22.0
const LOSE_RANGE := 40.0
const ATTACK_RANGE := 1.9
const ATTACK_COOLDOWN := 1.4
const CHASE_SPEED := 3.4
const STUN_SECONDS := 0.35
const CORPSE_SECONDS := 8.0
const MAX_HEALTH := 60.0

var state := "PATROL"

var _target: Node3D
var _combatant: Node
var _volume: Node
var _model: Node3D
var _player: AnimationPlayer
var _attack_ready := 0.0
var _stun_until := 0.0
var _corpse_until := 0.0
var _body_material: StandardMaterial3D


func setup(data, center: Vector3, angle: float, target: Node3D) -> void:
	_target = target
	super.setup(data, center, angle)

	_combatant = CombatantScript.new()
	_combatant.name = "Combatant"
	add_child(_combatant)
	_combatant.setup(MAX_HEALTH)
	_combatant.damaged.connect(_on_damaged)
	_combatant.died.connect(_on_died)

	_build_visual()
	_build_volume()


func _build_visual() -> void:
	if _mesh != null:
		_mesh.visible = false
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var mannequin: Node3D = (load(MANNEQUIN_SCENE) as PackedScene).instantiate()
	_model.add_child(mannequin)
	_player = _find(mannequin, "AnimationPlayer")
	var skeleton := _find(mannequin, "Skeleton3D")
	_attach_weapon(skeleton)
	_play("Idle_Loop")


func _attach_weapon(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = "DEF-hand.R"
	skeleton.add_child(attachment)
	var instance := MeshInstance3D.new()
	instance.mesh = WeaponScript.make_gladius()
	_body_material = StandardMaterial3D.new()
	_body_material.vertex_color_use_as_albedo = true
	_body_material.roughness = 0.5
	_body_material.metallic = 0.4
	_body_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	instance.material_override = _body_material
	instance.rotation.x = -0.35
	attachment.add_child(instance)


func _build_volume() -> void:
	_volume = AttackVolumeScript.new()
	_volume.name = "AttackVolume"
	_model.add_child(_volume)
	_volume.call("setup", 1.9, 0.7, 2)


func _physics_process(delta: float) -> void:
	if state == "DEAD":
		_corpse_until -= delta
		if _corpse_until <= 0.0:
			queue_free()
		return

	if state == "STUN":
		if _now() >= _stun_until:
			state = "AGGRO"
		_apply_gravity(delta)
		move_and_slide()
		return

	var distance := _distance_to_target()
	if distance < 0.0:
		super._physics_process(delta)
		return

	if state == "PATROL":
		if distance <= AGGRO_RANGE and _can_see_target():
			state = "AGGRO"
			return
		super._physics_process(delta)
		return

	if distance > LOSE_RANGE:
		state = "PATROL"
		super._physics_process(delta)
		return

	var direction := _flat_direction_to_target()
	if distance > ATTACK_RANGE:
		state = "CHASE"
		_chase(direction, delta)
	else:
		state = "ATTACK"
		_face(direction)
		_try_attack()
		_apply_gravity(delta)
		move_and_slide()


func _chase(direction: Vector3, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(direction * CHASE_SPEED, 8.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_face(direction)
	_apply_gravity(delta)
	move_and_slide()


func _try_attack() -> void:
	if _now() < _attack_ready:
		return
	_attack_ready = _now() + ATTACK_COOLDOWN
	_play("Sword_Attack")
	_volume.call("begin_swing", 12.0, self, 0.25, 0.55, 0.5)


func _on_damaged(_amount: float, _source: Vector3) -> void:
	if _combatant.is_alive():
		state = "STUN"
		_stun_until = _now() + STUN_SECONDS
		_play("Hit_Chest")
		if _body_material != null:
			_body_material.albedo_color = Color(1.6, 1.6, 1.6)
			create_tween().tween_property(_body_material, "albedo_color", Color(1, 1, 1), 0.3)


func _on_died(_source: Vector3) -> void:
	state = "DEAD"
	_corpse_until = CORPSE_SECONDS
	collision_layer = 0
	_volume.call("end_swing")
	_play("Death01")


func _play(name: String) -> void:
	if _player != null and _player.has_animation(name):
		_player.play(name)


func _distance_to_target() -> float:
	if _target == null or not is_instance_valid(_target):
		return -1.0
	return global_position.distance_to(_target.global_position)


func _flat_direction_to_target() -> Vector3:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	return to_target.normalized()


func _can_see_target() -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.5, 0)
	var to := _target.global_position + Vector3(0, 1.2, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _face(direction: Vector3) -> void:
	if _model != null and direction.length() > 0.01:
		_model.rotation.y = atan2(direction.x, direction.z)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _find(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found := _find(child, type_name)
		if found != null:
			return found
	return null


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
```

Requiere dos cambios en `roman_npc.gd` para ser heredable: `GRAVITY`, `_mesh`,
`_physics_process`, `_decision_timer` y `setup` deben ser accesibles al hijo (en GDScript los
miembros de la clase base ya son accesibles; lo único necesario es que `_physics_process` no
sea `private` en el sentido de nombre — **renombrar `_physics_process` no aplica**, Godot la
llama por ese nombre, así que el hijo la sobrescribe y llama `super._physics_process(delta)`
como hace el código de arriba).

- [x] **Step 2: Cambiar el ataque del NPC a la ventana correcta**

`begin_swing(damage, source, open_at, close_at, clip_length)` usa fracciones. Con
`Sword_Attack` de duración medida en la Tarea 0, pasar `0.25`/`0.55` y la duración real.
Sustituir el `0.5` fijo por la duración leída:

```gdscript
	var clip_length := 0.5
	if _player != null and _player.has_animation("Sword_Attack"):
		clip_length = _player.get_animation("Sword_Attack").length
	_volume.call("begin_swing", 12.0, self, 0.25, 0.55, clip_length)
```

- [x] **Step 3: Conectar en `structures.gd`**

Cambiar la precarga (`:7`) y `_build_npc` (`:123-128`):

```gdscript
const RomanNpcScript := preload("res://scripts/npc/hostile_npc.gd")
```

```gdscript
func _build_npc(data, spot: Vector3, angle: float) -> void:
	var npc: CharacterBody3D = RomanNpcScript.new()
	npc.name = "Romano"
	add_child(npc)
	npc.call("setup", data, spot, angle, _player)
```

y guardar el jugador en `setup()`:

```gdscript
var _player: Node3D

func setup(terrain: Terrain3D, player: Node3D) -> void:
	_player = player
	...
```

- [x] **Step 4: Verificar en ventana**

```bash
"$GODOT" --headless --path "$PROY" --import > /dev/null 2>&1
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/shot.tscn" 2>&1 | grep -E "^SHOT NPC|^SHOT npcs|^SHOT fps|SCRIPT ERROR|Invalid" | head
```

Esperado: `SHOT npcs=4`, cero errores, y el FPS del bench nativo todavía ≥ 51. Los NPCs
ahora son maniquíes con esqueleto: si el FPS cae por debajo de 51, **no** continuar — ir a la
Tarea 9 y aplicar el repliegue antes de seguir.

- [x] **Step 5: Commit**

```bash
git add scripts/npc/hostile_npc.gd scripts/world/structures.gd
git commit -m "Convierte los NPCs en hostiles con aggro, persecucion y ataque"
```

**Lo que cambió al ejecutarla:**

- `setup()` del hijo lleva el objetivo **opcional** (`target: Node3D = null`): con el cuarto
  argumento obligatorio GDScript rechaza la firma por incompatible con la del padre, y los
  cuatro NPCs desaparecían del mundo (`SHOT npcs=0`).
- `_play("Idle_Loop")` → `_play("Idle")`, y `_play("Walk")` en la persecución. La Task 0 ya
  había medido que los alias `_Loop` no existen; el plan no lo reflejaba.
- `_play()` ignora el nombre repetido: sin ese guardado, llamarlo cada frame reiniciaba la
  animación y el tajo se congelaba en su primer fotograma.
- El volumen del NPC pasa de alcance 1,9 / radio 0,7 a **1,2 / 0,8**. Con el volumen a la
  misma distancia que la de parada, cualquier objetivo algo más cerca quedaba fuera de la
  esfera: el primer `--fight` midió `distancia_min=0,00` y **cero golpes**.
- En ATTACK se anula la velocidad horizontal. Sin eso la inercia de la persecución meteía al
  NPC dentro de Rito y el volumen, que mira hacia delante, le pasaba de largo.
- `_swing_until` corta el `_play("Idle")` del estado ATTACK: llamado a ciegas cada frame,
  revertía `Sword_Attack` al fotograma siguiente.
- La malla fusionada del patrullador se libera con `queue_free()` en vez de ocultarse.

Medición tras el arreglo, con `--fight` (10 s junto a un NPC): 7 golpes recibidos a la
cadencia de 1,4 s, `distancia_min=1,87`, y Rito lo mata (`hp_npc=0`, `estado=DEAD`,
`bajas=1`). Bench en tres corridas: `median_avg=60,0`, peor frame 20 ms.

---

## Task 8: Muerte y reaparición del jugador

**Files:**
- Modify: `scripts/player/rito.gd` (`_ready`, `_physics_process`, nuevos métodos)
- Modify: `scripts/main.gd` (crear el `Combatant` del jugador)
- Modify: `tools/combat_test.gd` (test de reaparición)

**Interfaces:**
- Consumes: `Combatant` (Tarea 1), `play_one_shot(..., PRIORITY_DYING)` (Tarea 3),
  `WorldBuilder.spawn_point` (existente).
- Produces: `Rito.is_alive() -> bool`, `Rito.died` señal, `Rito.respawn(at: Vector3) -> void`,
  campo `respawn_delay := 1.5`.

- [x] **Step 1: Escribir el test de reaparición**

Añadir a `tools/combat_test.gd`:

```gdscript
func _test_player_respawn() -> void:
	var rito: CharacterBody3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(rito)
	await process_frame
	await process_frame
	var combatant := rito.get_node_or_null("Combatant")
	_check(combatant != null, "Rito lleva su Combatant")
	if combatant == null:
		return
	combatant.take_damage(999.0, Vector3.ZERO)
	_check(not combatant.is_alive(), "Rito muere con dano letal")
	_check(not rito.is_alive(), "Rito reporta muerte")
	await get_tree().create_timer(2.2).timeout
	_check(combatant.is_alive(), "Rito reaparece vivo")
	_check(is_equal_approx(combatant.health, 100.0), "reaparece con vida llena")
	rito.queue_free()
```

- [x] **Step 2: Ejecutar y confirmar el fallo**

```bash
"$GODOT" --path "$PROY" --rendering-driver opengl3 --script "res://tools/combat_test.gd" 2>&1 | grep -E "^TEST|^FAIL" | head
```

Esperado: `FAIL Rito lleva su Combatant`.

- [x] **Step 3: Crear el Combatant del jugador**

En `main.gd`, tras `add_child(rito)` (`:20`):

```gdscript
	var combatant: Node = CombatantScript.new()
	combatant.name = "Combatant"
	rito.add_child(combatant)
```

y tras `await world.attach_player(rito)`:

```gdscript
	combatant.setup(100.0, 2.0)
	rito.call("bind_combatant", combatant, world.spawn_point)
```

- [x] **Step 4: Enlazar muerte y reaparición en `rito.gd`**

Variables nuevas:

```gdscript
signal died

var combatant: Node
var _spawn_point := Vector3.ZERO
var _respawn_timer := 0.0
var _dead := false
const RESPAWN_DELAY := 1.5
```

y los métodos:

```gdscript
func bind_combatant(p_combatant: Node, p_spawn: Vector3) -> void:
	combatant = p_combatant
	_spawn_point = p_spawn
	combatant.died.connect(_on_died)
	combatant.damaged.connect(_on_damaged)


func is_alive() -> bool:
	return not _dead


func _on_damaged(_amount: float, _source: Vector3) -> void:
	if not _dead:
		play_one_shot(_resolved_hit, 0.35, PRIORITY_HIT)


func _on_died(_source: Vector3) -> void:
	_dead = true
	_respawn_timer = RESPAWN_DELAY
	play_one_shot(_resolved_death, RESPAWN_DELAY, PRIORITY_DYING)
	if combatant != null:
		combatant.make_invulnerable(2.0)
	died.emit()


func respawn(at: Vector3) -> void:
	global_position = at
	velocity = Vector3.ZERO
	_dead = false
	if combatant != null:
		combatant.heal_full(2.0)
	_lock_priority = 0
	_lock_until = 0.0
	_animation_state = ""
```

En `_physics_process`, al principio:

```gdscript
	if _dead:
		_respawn_timer -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		if _respawn_timer <= 0.0:
			respawn(_spawn_point)
		return
```

y resolver los nombres nuevos en `_build_model()`:

```gdscript
const ANIM_HIT := ["Hit_Chest", "Hit_Head"]
const ANIM_DEATH := ["Death01", "Death"]
var _resolved_hit := ""
var _resolved_death := ""
```

```gdscript
	_resolved_hit = _resolve_animation(ANIM_HIT)
	_resolved_death = _resolve_animation(ANIM_DEATH)
```

- [x] **Step 5: Ejecutar el test**

```bash
"$GODOT" --path "$PROY" --rendering-driver opengl3 --script "res://tools/combat_test.gd" 2>&1 | grep -E "^TEST|^FAIL" | head
```

Esperado: `TEST failures=0`.

- [x] **Step 6: Commit**

```bash
git add scripts/player/rito.gd scripts/main.gd tools/combat_test.gd
git commit -m "Anade muerte y reaparicion del jugador con invulnerabilidad"
```

---

## Task 9: Puerta de rendimiento y calibración de la lanza

**Files:**
- Modify: `scripts/npc/hostile_npc.gd` (repliegue si hace falta)
- Modify: `scripts/combat/weapon.gd` (rotación del arma si la lanza sale mal)
- Create: captura de comparación

**Interfaces:**
- Consumes: `tools/bench.tscn`, `tools/web_bench.py`, `tools/shot.gd`.
- Produces: una decisión documentada (esqueleto o malla estática) y el número final.

- [x] **Step 1: Banco nativo**

```bash
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/bench.tscn" -- --variant 1 2>&1 | grep -E "^BENCH"
```

Esperado: `median_avg` ≥ 51. Si está por debajo, aplicar en este orden y volver a medir
después de cada paso:
1. `structures.gd`: `NPC_COUNT` de 4 a 3.
2. `hostile_npc.gd`: en `_physics_process`, si `global_position.distance_to(_target.global_position) > 45.0`, `_player.speed_scale = 0.0` y saltar el resto del frame.
3. Si aún así no llega: quitar el maniquí del NPC y volver a `_mesh` estático, con muerte
   por rotación (`_model.rotation.x` hacia ±PI/2 en 0,4 s) en lugar de `Death01`.

- [x] **Step 2: Captura de la lanza**

Añadir a `tools/shot.gd` una pose `--spear` que haga `weapons.switch_to(1)` y dispare el
ataque, congelando el frame en el 45 % del clip:

```gdscript
	if args.has("--spear"):
		player.get("weapons").call("switch_to", 1)
		player.get("combat").call("_try_attack", false)
		for i in 12:
			await get_tree().process_frame
```

```bash
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/shot.tscn" -- --spear 2>&1 | grep -E "^SHOT saved|SCRIPT ERROR"
```

Abrir la imagen y juzgar: ¿la lanza está en la mano, en la línea del brazo extendido, sin
clavarse en el suelo ni atravesar la cabeza? Si falla, ajustar `mesh_instance.rotation.x` o
el offset de `make_spear()` y repetir. **Si tras dos intentos sigue ilegible, sustituir
`Punch_Jab` por `Sword_Attack` en `_attack_animation()` y anotar el cambio en la spec.**

- [x] **Step 3: Medición en navegador con GPU real**

```bash
cd "$PROY" && python web/serve.py &
sleep 3
python tools/web_bench.py --seconds 18
```

Esperado: `RENDERER: ANGLE (NVIDIA, NVIDIA GeForce GT 640 ... D3D11)` (no software) y
`median_fps` ≥ 36.

- [x] **Step 4: Commit**

```bash
git add -A
git commit -m "Calibra rendimiento del combate y pose de la lanza"
```

---

**Lo que cambió al ejecutarla:**

- La escalera de repliegue del paso 1 no hizo falta: tres corridas del bench nativo con los
  cuatro NPCs esqueletizados dan `median_avg=60,0` y peor frame 20 ms.
- El paso 2 no se resolvió a ojo en dos intentos, como pedía el plan, sino midiendo. La
  primera lanza apuntaba **hacia atrás** (alineación −0,62). La causa no era el valor del giro
  sino que se medía sobre el transform del `BoneAttachment3D`, que ignora `rotation.x` de la
  instancia: la primera versión del sondeo daba el mismo número aunque se cambiara el agarre.
- El agarre pasa a `Weapon.GRIP_ROT_X`, un valor por arma, calibrado en cuatro puntos
  (-1,5708 / -1,05 / -0,80 / -0,92) con dos fotogramas cada uno: reposo e impacto. Elegido
  **-0,92** (reposo 0,98 con la punta a nivel de suelo, golpe 0,90). -90° daba el mejor golpe
  pero clavaba la punta 1,29 m bajo el terreno.
- `tools/shot.gd` gana `--attack` y `--spear`, que imprimen el coseno arma-frente en ambos
  fotogramas.

---

## Task 10: Export, verificación final y documentación

**Files:**
- Modify: `tools/verify_web.js` (nuevos campos)
- Modify: `docs/superpowers/specs/2026-11-02-rito-cero-web-design.md` (§14)
- Modify: `docs/superpowers/specs/2026-11-02-rito-cero-combate-design.md` (resultados)

- [x] **Step 1: Exportar**

```bash
cd "$PROY" && rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path "$PROY" --export-release "Web" "build/web/index.html" 2>&1 | tail -3
ls -l build/web/index.pck | awk '{print $5/1048576 " MiB"}'
```

Esperado: sin errores y `.pck` ≤ 15 MiB (los maniquíes extra son el mismo recurso importado,
así que no debería crecer más de ~0,3 MiB).

- [x] **Step 2: Verificación funcional en navegador**

Ampliar `tools/verify_web.js` para leer los campos nuevos y añadir una comprobación de
combate: pulsar `attack` y verificar que `window.__rito.hp` cambia o que `kills` sube tras
acercarse a un NPC.

```bash
NODE_PATH="C:/Users/USUARIO/AppData/Local/Temp/ritoverify/node_modules" node tools/verify_web.js
```

Esperado: `RESULT PASS`, `ERRORS []`, y el JSON con `hp`, `weapon`, `kills`, `alive`.

- [x] **Step 3: Exponer los campos nuevos en el puente JS**

En `rito.gd`, `_init_web_bridge()` y `_push_web_state()`:

```gdscript
	"window.__rito = {x:0, y:0, z:0, fps:0, ready:false, moved:0, draws:0, tris:0, variant:0, hp:0, weapon:0, kills:0, alive:true};"
```

```gdscript
	window.eval(
		"window.__rito.hp = %.1f; window.__rito.weapon = %d; window.__rito.kills = %d; window.__rito.alive = %s;"
		% [
			float(combatant.health) if combatant != null else 0.0,
			combat.get("weapon_index") if combat != null else 0,
			combat.get("kills") if combat != null else 0,
			"true" if is_alive() else "false",
		], true)
```

- [x] **Step 4: Actualizar documentación con lo medido**

En la spec de combate, tabla de §6 con los números reales (banco nativo y navegador), y en el
§14 de la spec v1 una línea que apunte a la spec de combate.

- [x] **Step 5: Capturas finales y commit**

```bash
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/shot.tscn" -- --spear 2>&1 | grep "^SHOT saved"
"$GODOT" --path "$PROY" --rendering-driver opengl3 "res://tools/shot.tscn" 2>&1 | grep "^SHOT saved"
git add -A
git commit -m "Export web con combate y documentacion de resultados medidos"
```

---

## Auto-revisión del plan

**Cobertura de la spec:** §4.1→T1-T7 · §4.2→T1 · §4.3→T4,T7 · §4.4→T3 · §4.5→T0,T4,T5 ·
§4.6→T5,T9 · §4.7→T2 · §4.8→T7 · §4.9→T8 · §4.10→T6 · §5→T5 · §6→T9 · §7→T1,T4,T8 ·
§8→T1,T4,T8,T9,T10 · §9→orden del plan. Sin huecos.

**Tipos consistentes:** `Combatant.setup/take_damage/is_alive/heal_full/make_invulnerable`
se firman en T1 y se consumen igual en T4, T6, T7, T8. `AttackVolume.setup(reach, radius,
mask)` y `begin_swing(damage, source, open_at, close_at, clip_length)` se firman en T4 y se
llaman con esos argumentos exactos en T5 y T7. `play_one_shot(name, lock_seconds, priority)`
se define en T3 y se usa con los tres argumentos en T5 y T8. `Hud.setup` cambia de firma en
T6 y su única llamada (main.gd) se actualiza en el mismo task.

**Riesgo conocido del plan:** el arnés de test en `extends SceneTree` puede no entregar
señales de `Area3D` en headless. Está previsto en el Step 4 de T4 con la variante en ventana
y los mismos asserts. No se acepta ningún test que solo compruebe el código de salida.
