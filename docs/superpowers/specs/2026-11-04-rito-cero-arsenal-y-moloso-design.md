# Rito Cero — arsenal romano con menú y moloso (perro romano de combate)

- **Fecha:** 2026-11-04
- **Proyecto:** `C:\Users\USUARIO\Documents\rito-cero-` (Godot 4.7.2, export web, renderer Compatibility)
- **Depende de:** `docs/superpowers/specs/2026-11-02-rito-cero-combate-design.md` (combate ya integrado), `2026-11-04-rito-cero-misiones-design.md` (escrito, **fuera de alcance**)
- **Plan:** `docs/superpowers/plans/2026-11-04-rito-cero-arsenal-y-moloso.md`

---

## 1. Objetivo

Que Rito tenga un **arsenal romano elegible desde un menú** y que lo acompañe un **perro
romano de combate (moloso)**. El encargo textual fue "mejoralo y ponele un menú para poder
seleccionar armas y que sean romanas y alla un perro romano", con tres decisiones del
usuario: alcance centrado, perro como compañero de combate, y arsenal de tres armas
(gladius, pilum, spatha) desde el inicio.

Criterio de éxito: en el build web, Rito abre el arsenal con una tecla, ve las tres armas
romanas con sus números, equipa la que quiere con clic o con `1`/`2`/`3`, el cambio se ve
en la mano y altera el daño real; el moloso sigue a Rito por el valle, persigue a los
bandidos y los muerde; y el navegador no baja de **36 FPS** de mediana (misma regla que el
combate).

## 2. Decisiones ya tomadas por el usuario

| Decisión | Elección | Consecuencia inevitable |
|---|---|---|
| Alcance de "mejoralo" | **Centrado**: arsenal + menú + moloso + pulido | El spec de misiones (XP, denarios, árbol) queda fuera: es otro proyecto |
| El perro romano | **Compañero de combate**: sigue, persigue hostiles, muerde | Actor con IA propia, no una mascota decorativa |
| Arsenal | **3 armas romanas desde el inicio**: gladius, pilum, spatha | Sustituye a la lanza melee actual; el pilum es **lanzable** |

## 3. Corrección de un dato del combate heredado

La lanza del combate heredado tenía **3,4 m de alcance cuerpo a cuerpo** y era la segunda
arma. Al cambiar el arsenal a `{gladius, pilum, spatha}` el rol de "arma larga cuerpo a
cuerpo" desaparece y lo ocupa un arma de alcance corto pero más dañina (spatha, 2,6 m /
58 de daño). El juego pierde el tajo a distancia cuerpo a cuerpo y gana el lanzamiento:
es un cambio de rol deliberado, no una pérdida, y queda anotado aquí para que nadie lea la
tabla nueva como una regresión.

## 4. Arquitectura

### 4.1 Módulos nuevos

```
scripts/combat/
├── weapon.gd            (modificado) catalogo por arma + geometrias gladius/pilum/spatha
├── weapons_holder.gd    (modificado) monta N armas de la tabla, muestra la activa
└── projectile.gd        (nuevo)      pilum en vuelo: raycast por segmento, dano y death

scripts/npc/
├── roman_dog.gd         (nuevo)      moloso: seguir, perseguir, morder
└── hostile_npc.gd       (modificado) se registra en el grupo "hostiles"

scripts/ui/
├── arsenal_menu.gd      (nuevo)      panel de arsenal con 3 armas, teclado y raton
└── hud.gd               (modificado) fila de armas, nombre activo, pista de tecla

scripts/world/
└── mesh_factory.gd      (modificado) make_roman_dog + make_dog_leg

scripts/main.gd          (modificado) crea el moloso y el menu de arsenal
scripts/player/rito.gd   (modificado) puente web, bloqueo de captura del raton
scripts/player/rito_combat.gd (modificado) modo lanzamiento y tecla 3
project.godot            (modificado) acciones weapon_3 y arsenal_menu
tools/combat_test.gd     (modificado) tests del arsenal, el proyectil y el moloso
tools/verify_web.js      (modificado) checks de arma 3, menu y perro
```

### 4.2 El catalogo de armas

`weapon.gd` pasa de arrays paralelos (`REACH[0]`, `DAMAGE[0]`, ...) a **una fila por arma**.
Los arrays paralelos obligaban a que cada indice nuevo tocara siete listas y a que un
desajuste de indices se manifestara como "el arma 3 hace el daño del arma 1". Con una fila,
añadir un arma es añadir una fila y su geometría.

| # | Arma | Modo | Daño | Alcance | Cadencia | Ventana | Radio | Animación |
|---|---|---|---|---|---|---|---|---|
| 1 | Gladius | melee | 34 | 2,2 m | 0,55 s | 0,25–0,55 | 0,75 m | `Sword_Attack` 2,0× |
| 2 | Pilum | throw | 40 | 26 m de vuelo | 1,45 s | — | — | `Punch_Jab` 1,2× (suelta de brazo) |
| 3 | Spatha | melee | 58 | 2,6 m | 0,80 s | 0,25–0,55 | 0,70 m | `Sword_Attack` 1,6× |

**Invariante heredada:** el cierre de la ventana de daño, en segundos, queda siempre por
debajo de la cadencia.

- Gladius: clip 1,533 s ÷ 2,0 = 0,767 s; cierra a 0,767 × 0,55 = **0,42 s** < 0,55 s ✓
- Spatha: clip 1,533 s ÷ 1,6 = 0,958 s; cierra a 0,958 × 0,55 = **0,53 s** < 0,80 s ✓
- Pilum: no usa ventana: es un proyectil. Su límite es el alcance de vuelo (26 m) y la
  cadencia de 1,45 s, muy por encima de los ~1,7 s que tarda el pilum en cruzar el valle.

El agarre (`grip_rot_x`) se conserva por arma: −0,35 para las hojas cortas, −0,92 para el
pilum, que es el valor medido que dejaba el astil horizontal en reposo y a 0,90 de
alineación en el golpe.

**El alcance que cuenta es `alcance + radio`, no el alcance.** La esfera del volumen va
centrada en el alcance del arma, así que el gladius cubre hasta 2,95 m (2,2 + 0,75) y la
spatha hasta 3,30 m (2,6 + 0,70). La cifra de la tabla es la del volumen; el alcance real
suma el radio, y esa es la que se muestra en el HUD.

### 4.3 El pilum lanzable

El pilum es un **proyectil**, no un tajo. Es la única pieza que rompe el modelo de combate
heredado, así que va aislada en `scripts/combat/projectile.gd`:

- Nace en la mano de Rito y vuela en la dirección frontal del modelo a 26 m/s.
- Cada frame hace **un raycast del segmento recorrido** (de la posición anterior a la
  nueva), con máscara `1 | 4` (terreno + NPCs). Un raycast por frame sobre el punto final
  solo faltaba el astil; el segmento cubre lo que de verdad barre la jabalina.
- El impacto en un NPC se resuelve por el `Combatant` del cuerpo golpeado: mismo contrato
  que el volumen de ataque, misma fuente de vida.
- El impacto en el terreno clava el pilum y lo retira a los 2,5 s.
- Al lanzarlo, el pilum **desaparece de la mano** y vuelve a aparecer cuando pasa la
  cadencia: no hay munición infinita visible en la mano y un pilum plantado en el suelo.

El pilum **no re-monta el sistema de combate**: no toca el esqueleto, ni las capas de
colisión, ni el `AttackVolume` de los NPCs.

### 4.4 El menú de arsenal

`scripts/ui/arsenal_menu.gd`, un `CanvasLayer` de capa 6 (sobre el HUD, que va en la 5):

- Se abre con **Tab** o **B** y se cierra con el mismo atajo, con `Esc` o con un clic
  fuera del panel.
- Panel centrado con el título "ARSENAL ROMANO" y una fila por arma: nombre latino en
  mayúsculas, rol (cuerpo a cuerpo / lanzamiento), daño, alcance, cadencia y una frase de
  una línea que diga para qué sirve.
- La fila equipada va marcada. Con **clic** en una fila se equipa; la **rueda del ratón**
  cicla; `1`/`2`/`3` equipan al instante sin abrir el menú.
- Mientras el menú está abierto: el ratón pasa a `VISIBLE`, el input de ataque se ignora y
  Rito no recaptura el puntero. El mundo **no** se detiene: es una pausa blanda, la misma
  que propone el spec de misiones para sus menús.
- Teclas: Tab es la tecla principal, pero en el navegador el foco puede robar el Tab, así
  que **B** es el atajo fiable. Ambos están declarados en `project.godot`.

### 4.5 El HUD

En `hud.gd`, abajo a la **derecha**, junto al resto de información ya existente:

- Una fila de tres fichas con el número y el nombre corto del arma; la activa resaltada.
- El nombre completo y la línea de estadísticas del arma activa.
- La pista `Tab o B: arsenal`.

Va a la derecha y no a la izquierda porque la pantalla de arranque ocupa la franja
izquierda durante los primeros 6,4 s del juego: dos textos encima se leen como un
fallo. Los decimales en pantalla llevan coma, como los números en castellano.

Las actualizaciones llegan por la señal `weapon_selected` del `RitoCombat`, no por
`polling`.

### 4.6 El moloso

`scripts/npc/roman_dog.gd`, un `CharacterBody3D` con la misma evitancia por raycast que el
patrullero (`roman_npc.gd`), pero con una máquina de estados de compañero:

| Estado | Entra cuando | Hace |
|---|---|---|
| `FOLLOW` | por defecto | se acerca al jugador hasta 2,2–3,4 m y lo sigue |
| `CHASE` | hay un hostil a ≤ 14 m | corre hacia él a 8 m/s |
| `BITE` | está a ≤ 1,3 m | muerde: 18 de daño, cadencia 1,0 s |
| `RETURN` | el hostil muere o se aleja | vuelve con el jugador |

- **Malla por código** (`mesh_factory.make_roman_dog`): cuerpo, pecho, cuello, cabeza con
  hocico, orejas caídas y cola, en un solo mesh (1 draw call). Las **cuatro patas** son
  `MeshInstance3D` aparte con pivote en la cadera, que se balancean con un seno del tiempo
  según la velocidad: andar sin esqueleto y sin más geometría.
- **Capa de colisión 16**: ni el volumen de ataque de Rito (máscara 4) ni el de los NPCs
  (máscara 2) lo alcanzan. El perro no puede recibir daño, así que no existe un estado
  blando en el que el compañero pueda bloquear una misión.
- Colisiona con el terreno (máscara 1) y con Rito (máscara 2), para no meterse dentro.
- Sus mordiscos **cuentan como bajas de Rito**: el compañero trabaja para el jugador.
- Busca enemigos en el grupo `"hostiles"`, al que se registran los NPCs hostiles.

### 4.7 Puentes y verificación web

`window.__rito` añade: `weapon_name` (string), `dog_state` (string) y `dog_dist` (float).
`tools/verify_web.js` cambia la comprobación de "tecla 2 = lanza" por "tecla 2 = pilum" y
"tecla 3 = spatha", y añade dos checks: el menú de arsenal se abre y el moloso está cerca
del jugador.

## 5. Restricciones (heredadas)

- Renderer Compatibility / WebGL2; sin sombras dinámicas; sin GI; ninguna luz nueva.
- **Ningún asset externo**: ni descargas, ni addons, ni modelos. Armas, perro y UI con
  primitivas y código.
- Presupuesto de rendimiento: **≥ 36 FPS de mediana en Chrome con la GT 640 real** (base
  40,0 con combate) y **sin bajar de 51 FPS** en el banco nativo (base 60,0). Regresión
  > 15 % ⇒ el perro se congela a 25 m de distancia y la segunda pata del perro se
  simplifica a una caja sin pivote.
- Comentarios, nombres y mensajes de commit en **español**, sin emojis.
- Tras crear un script con `class_name`, refrescar el caché de clases globales antes de
  ejecutar nada (`--headless --import`), como ya pasó en este proyecto.

## 6. Verificación

1. **Test determinista** `tools/combat_test.gd` (headless, asserts reales, con recuento):
   - El catálogo tiene 3 armas romanas con id único, un modo `melee` y uno `throw`.
   - La spatha alcanza a 2,4 m y no a 3,6 m (alcance distinto del gladius).
   - El pilum en vuelo daña al objetivo que tiene delante y no daña a quien no está en su
     trayectoria.
   - Cambiar de arma actualiza el volumen de ataque con el alcance de la nueva.
   - El menú de arsenal equipa el arma elegida.
   - El moloso sigue al jugador y muerde a un hostil, y la baja cuenta en Rito.
2. **Bridge web** (`tools/verify_web.js`): tecla 2 → pilum, tecla 3 → spatha, tecla 1 →
   gladius, el menú se abre, el moloso está a menos de 20 m.
3. **Banco** `tools/bench.tscn` antes/después; umbrales de §5.
4. **Capturas** (`tools/shot.gd`): panel del arsenal abierto y el moloso junto a Rito.

### 6.1 Resultado medido (2026-11-04)

| Medida | Línea base | Después |
|---|---|---|
| `tools/combat_test.gd` | `failures=0 checks=37` | **`failures=0 checks=62`** |
| `tools/bench.tscn` | `median_avg=60.0`, draws 99-106, tris 128k-163k | **`median_avg=60.0`**, draws 111-133, tris 122k-150k |
| Peor frame del banco | 28-36 ms | 17-24 ms |
| `tools/verify_web.js` | 9 checks PASS | **12 checks PASS** |
| `.pck` web | 14,42 MiB | 15,66 MB |

Los +12 draw calls son las cuatro patas del moloso (una por pata, con pivote propio) y
los dos attachments de arma extra. Los triángulos no suben: la malla del perro es de
primitivas.

**Un dato que salió del test y no del diseño:** el alcance que cuenta no es el del
volumen sino `alcance + radio`, porque la esfera va centrada en el alcance. El gladius
cubre hasta 2,95 m y la spatha hasta 3,30 m; el primer test daba por hecho que la
spatha no llegaba a 3,6 m y sí llegaba, porque el objetivo lleva su propia esfera de
0,4 m de radio.

### 6.2 Capturas

- `shot_light_arsenal.png`: el panel abierto con las tres armas, sus cifras y la
  equipada marcada.
- `shot_light_dog.png`: el moloso junto a Rito (cuerpo, hocico oscuro, cuatro patas, cola).
- `shot_pilum_mano.png`: el pilum en la mano de Rito.
- `shot_light_throw.png`: el pilum en vuelo y Rito en la pose de la suelta.

## 7. Manejo de errores y casos límite

- Atacar con el pilum sin objetivo delante: el proyectil se clava en el terreno y se va.
- Cambiar de arma en pleno vuelo del pilum: el pilum sigue volando y ya no se vuelve a
  mostrar en la mano hasta que se reequipa.
- Pulsar el ataque con el menú de arsenal abierto: no se ignora (se ignora).
- El moloso sin enemigos: se queda pegado al jugador y no estorba.
- El moloso con el hostil ya muerto: vuelve a `FOLLOW` en el siguiente ciclo.
- Enemigo dentro del jugador: el mordisco del moloso no depende de un volumen de ataque,
  así que no comparte el fallo medido del NPC hostil (§8.5 del spec de combate).
- Sin suelo bajo el moloso (caída): cae con la gravedad del mundo, como todo lo demás.

## 8. Fuera de alcance

- El spec de misiones completo: XP, denarios, inventario, árbol de tecnología, tablero.
- Perros con nombre, raza oالا que se pueda elegir: hay un moloso, no un sistema de mascotas.
- Escudo (`scutum`) y bloqueo.
- Audio, sonido de mordida, música.
- Armas de arquetipos no romanos y armas arrojadizas adicionales.
- Multijugador, guardado.

## 9. Orden de trabajo

1. `weapon.gd`: catálogo por arma + `make_pilum` + `make_spatha`.
2. `weapons_holder.gd`: N armas de la tabla, una visible, con su agarre.
3. `projectile.gd` + `rito_combat.gd`: modo lanzamiento, tecla 3.
4. `arsenal_menu.gd` + `project.godot`: el menú y sus atajos.
5. `hud.gd`: fila de armas, nombre y pista.
6. `mesh_factory.make_roman_dog` + `roman_dog.gd` + `hostile_npc.gd` (grupo) + `main.gd`.
7. `rito.gd`: puente web y bloqueo de captura del ratón.
8. `combat_test.gd` ampliado + `verify_web.js` actualizado.
9. Capturas + banco; actualizar este spec y el plan; commit.

## 10. Anti-goals

- Que el arsenal sea un menú de adornos: cada arma cambia números y malla de verdad.
- Que el perro sea una mascota que no hace nada: el compañero tiene que morder bandits.
- Que el pilum rompa el combate heredado: no toca esqueleto, capas ni volúmenes ajenos.
- Que la mejora venga de añadir sistemas: el encargo pide concentrarse en armas y perro.
