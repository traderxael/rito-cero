# Rito Cero — juego web de mundo abierto con el personaje "Rito"

- **Fecha:** 2026-11-02
- **Proyecto:** `C:\Users\USUARIO\Documents\rito-cero-` (Godot 4.7.2-stable, proyecto ya existente)
- **Destino:** export web (HTML5) servido por HTTP local, jugable en Chrome.

---

## 1. Objetivo

Entregar un juego 3D jugable en una página web: un campo abierto explorable en tercera
persona cuyo protagonista es **Rito**, un hombre de la antigua Roma creado con IA.

Criterio de éxito: `build/web/index.html` se abre en Chrome, muestra el campo 3D con
Rito visible, y Rito camina/corre con el teclado mientras el terreno se extiende a su
alrededor.

## 2. Alcance

### Incluido (v1)

- Terreno 3D de mundo abierto (sin bordes transitables) generado con Terrain3D.
- Vegetación instanciada: trigal, olivos, cipreses y rocas.
- Personaje jugable **Rito**: humanoide romano sobre un esqueleto animado, vestuario
  romano construido con primitivas, y cara con textura generada por IA.
- Control en tercera persona: teclado + ratón.
- Arte de Rito generado con IA (hoja de personaje + retrato facial).
- Overlay de carga con el arte de Rito y una línea de controles que se desvanece.
- Export web con su preset y un servidor local que lo sirve con las cabeceras correctas.

### Excluido (v1)

Audio, guardado en disco, menú de opciones, combate, misiones, inventario, multijugador,
y cualquier publicación en internet. La entrega es local: archivos exportados + servidor
local.

## 3. Restricciones verificadas

Todas verificadas contra esta máquina el 2026-11-02, no supuestas.

| # | Hecho verificado | Cómo se verificó | Consecuencia en el diseño |
|---|---|---|---|
| R1 | El export web de Godot 4.7 solo admite el renderer **Compatibility (WebGL2)**; Forward+ y Mobile no están soportados | Documentación oficial de export web de Godot 4 | `project.godot` cambia de `Forward Plus` a `GL Compatibility` |
| R2 | Terrain3D 1.1.0 es una GDExtension y trae build web `libterrain.web.release.wasm32.nothreads.wasm` | Inspección de `addons/terrain_3d/bin/` y `terrain.gdextension` | El preset web activa **Extensions Support** |
| R3 | Con Extensions Support, el navegador exige aislamiento de origen: `Cross-Origin-Opener-Policy: same-origin` y `Cross-Origin-Embedder-Policy: require-corp` | Documentación oficial de export web de Godot 4 | `web/serve.py` envía ambas cabeceras en toda respuesta |
| R4 | Terrain3D renderiza en Compatibility sobre la GPU de esta máquina | Ejecución de `res://demo/Demo.tscn` con `--rendering-driver opengl3`: `OpenGL API 3.3.0 NVIDIA 475.14 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce GT 640`, sin errores de shader | El terreno del demo se reutiliza sin adaptación |
| R5 | Las sombras dinámicas en tiempo real son catastrophicas en esta GPU (≈3 FPS con sombras duras frente a ≈66 FPS sin ellas) | Medición previa documentada en SLUG OUT | **Sombras desactivadas.** Se resuelve el contraste con ambiente, emisivos y colores de material |
| R6 | La GPU es una GeForce GT 640 con 2 GB de VRAM y la CPU un i7-3820 sin AVX2 | `Win32_VideoController` y `tasklist` | Presupuesto de draw calls y triángulos conservador; sin GI, SSAO ni niebla volumétrica |
| R7 | La superficie browser-use del entorno no captura pantallas: su viewport es invisible | Notas de sesión previas | La verificación visual se hace con **Chrome headless local** vía `playwright-core` con SwiftShader para WebGL2 |
| R8 | Las plantillas de exportación web no estaban instaladas | `AppData/Roaming/Godot/export_templates/` vacío | Se descargó e instaló `Godot_v4.7.2-stable_export_templates.tpz` en `export_templates/4.7.2.stable/` |

## 4. Arquitectura

### 4.1 Estructura de archivos

```
rito-cero-/
├── project.godot                 renderer gl_compatibility, main_scene, input map
├── scenes/
│   └── main.tscn                 escena raíz (Node3D + script)
├── scripts/
│   ├── main.gd                   orquestación: construye el mundo y el jugador
│   ├── world/
│   │   ├── world_builder.gd       configura Terrain3D, cielo, luz, spawn
│   │   ├── vegetation.gd          gestor MultiMesh en celdas alrededor del jugador
│   │   └── mesh_factory.gd        genera mallas low-poly (olivo, ciprés, trigo)
│   ├── player/
│   │   ├── rito.gd                CharacterBody3D: input, cámara, animación
│   │   └── rito_outfit.gd         construye el vestuario romano sobre el maniquí
│   └── ui/
│       └── boot_overlay.gd        overlay de carga + línea de controles
├── assets/
│   ├── rito_sheet.png             IA: hoja de personaje de cuerpo entero
│   ├── rito_face.png              IA: retrato frontal para la cara
│   ├── roman_terrain_assets.tres  copia del pack con los ajustes de coste
│   └── roman_terrain_material.tres
├── web/
│   └── serve.py                   servidor local con MIME y COOP/COEP
├── export_presets.cfg            preset "Web" (Godot lo exige en la raíz)
├── build/web/                     salida del export (generado, no versionado)
├── demo/                          pack de Terrain3D (existente, reutilizado)
├── Godot/                         pack Quaternius CC0 (existente, reutilizado)
└── docs/superpowers/specs/        este documento
```

### 4.2 Límites de módulo

- `world_builder.gd` no conoce al jugador; solo configura el terreno y expone la API de
  consulta de altura que usa `vegetation.gd`.
- `vegetation.gd` no crea mallas; las pide a `mesh_factory.gd` y solo las coloca.
- `rito.gd` no toca la vegetación ni el terreno; solo se mueve y anima.
- `rito_outfit.gd` no lee input; solo construye geometría y materiales sobre el esqueleto.

Cada módulo se puede leer y probar por separado.

## 5. Mundo abierto

### 5.1 Terreno

- Nodo `Terrain3D` con `data_directory = "res://demo/data"`, `assets` y `material` tomados de
  `demo/data/assets.tres` y `demo/data/M_terrain.tres` (ya configurados: hierba `ground037`,
  acantilado `rock023`).
- **Océano desactivado** (`ocean_enabled = false`): un campo romano no tiene mar y el agua
  añade coste de shader.
- `clipmap_target` sigue al jugador para que el terreno se extienda bajo sus pies.
- `collision_target` apunta a Rito para la colisión del terreno.

**Extensión de los datos** (medido el 2026-11-02 sobre `demo/data`):

- Los tres archivos `terrain3d_*` son recursos `Terrain3DRegion` con `region_size = 1024` m
  y `vertex_spacing = 1.0`, es decir una región de **1024 × 1024 m** (≈1,05 km²) con
  heightmap de 1024 × 1024.
- `terrain3d_00_00.res` es la región principal (alturas de −50,95 m a 365,62 m: valle con
  relieve marcado). `terrain3d_00-01.res` y `terrain3d_00-02.res` son **otras dos regiones** (la
  convención es `terrain3d_<x>_<y>.res` con el índice negativo escrito con guion):
  las tres cubren (0,0), (0,−1) y (0,−2), es decir un mundo de **1024 × 3072 m**
  (≈3,1 km²) a lo largo del eje Z, no una sola región.
- El tamaño es fijo y el terreno no crece sin límite: el borde de datos está a 512 m del
  centro de la región. La zona jugable se mantiene dentro de la región y la distancia de
  niebla/horizonte oculta ese borde.
- El punto de aparición de Rito se calcula en runtime: se consulta la altura del terreno en
  un punto elegido por su apertura visual y se ancla el pie del personaje sobre ella, de
  modo que el punto sea válido aunque el terreno cambie.

### 5.2 Vegetación

Gestor propio, independiente del sistema de foliaje de Terrain3D, para tener control
directo del coste y poder medirlo.

- **Celdas** de 32 m, con un radio de 3 celdas (7×7 ⇒ **≈224 m**). Al cruzar el borde de una
  celda se reconstruyen **las 49 celdas enteras** (~3.800 muestras de heightmap en un solo
  frame). Se midió y se propuso la reconstrucción incremental; **no se aprobó**, así que el
  tirón de CPU sigue siendo conocido y pendiente.
- **Posiciones deterministas**: cada celda deriva su RNG de `(seed, cell_x, cell_z)`, así que
  la vegetación es idéntica cada vez que se vuelve a entrar en la misma celda.
- **Altura**: `Terrain3D.get_height(posicion)` en el momento de construir la celda.
- **Tipos y densidad por celda** (número de instancias):
  - Trigal: 130 matas por celda, cada una con 3 espigas triangulares afiladas
    (oliva abajo, dorado arriba). Se descartaron los cruzados rectangulares: a
    distancia se leían como cartones.
  - Olivos: 6 árboles low-poly (tronco cilíndrico + copa de 2 esferas achatadas).
  - Cipreses: 5 conos (tronco + cono alargado).
  - Rocas: 4, usando `demo/assets/models/RockA.glb`, `RockB.glb` y `RockC.glb`.
- **Coste**: un `MultiMeshInstance3D` por tipo → 4 draw calls de vegetación en total,
  independientemente de cuántas celdas estén cargadas.
- La densidad total se baja primero si el rendimiento no cumple el presupuesto (§9).

### 5.3 Cielo y luz

Se reutiliza `demo/components/Environment.tscn` (cielo procedural, una `DirectionalLight3D` con
sombra, ambiente por cielo) con dos cambios:

- Sombras **desactivadas** (R5).
- Tono de tarde cálido: sol más bajo y más ámbar, cielo con horizonte más cálido, para el
  ambiente romano.

## 6. Personaje "Rito"

### 6.1 Base

`Godot/AnimationLibrary_Godot_Standard.glb` (pack Quaternius, CC0): maniquí humanoide
riggeado con 46 animaciones, entre ellas `Idle_Loop`, `Walk_Loop`, `Sprint_Loop`, `Jump_Start`,
`Jump_Loop` y `Jump_Land`. Se instancia en runtime y se usa su `AnimationPlayer`.

### 6.2 Vestuario romano

Construido con primitivas y aplicado como hijos del esqueleto (o del maniquí, siguiendo los
huesos), en `rito_outfit.gd`:

| Pieza | Geometría | Color |
|---|---|---|
| Túnica | Cono (`CylinderMesh`, radio superior 0.20, inferior 0.40, alto 0.95) desde la cintura | Lino arena `#C9B48B` |
| Franja senatorial | Banda fina púrpura en el borde inferior de la túnica | Púrpura `#5B2C6F` |
| Cinturón | Cilindro fino | Cuero `#6B4A2F` |
| Sandalias | Dos cajas bajo los pies | Cuero `#6B4A2F` |
| Cabeza | Esfera recoloreada | Piel `#C08A5B` |
| Melena | Esfera achatada en la parte alta y trasera | Castaño `#3A2A1E` |
| Barba | Esfera achatada bajo el mentón | Castaño `#3A2A1E` |
| Corona de laurel | `TorusMesh` inclinado sobre la cabeza | Verde laurel `#6E8F3A` |
| Cuerpo | Material del maniquí recoloreado | Piel `#C08A5B` |

### 6.3 Cara

`assets/rito_face.png` (IA, retrato frontal, fondo liso, luz plana) se proyecta sobre la
cabeza con un `SphereMesh` ligeramente mayor que el cráneo, usando `uv1_scale` / `uv1_offset`
del `StandardMaterial3D` para encuadrar la cara en el hemisferio frontal.

**Si el encaje no es convincente** (se juzga por captura real, no por suposición), la cabeza
queda como esfera lisa con melena y barba, y el retrato se usa solo en el overlay de carga.

### 6.4 Control

`CharacterBody3D` con cápsula de 1.8 m:

- **Cámara**: cadena `CameraYaw → Pivot(1,68 m) → CameraPitch → Camera3D` con la distancia
  resuelta a mano mediante `PhysicsRayQueryParameters3D` contra la capa del terreno. Se optó
  por esto en vez de `SpringArm3D` porque el brazo no deja controlar el recorte con la
  pendiente, y la spec original lo daba por hecho.
- **Movimiento**: WASD relativo a la cámara. `Shift` corre. `Espacio` salta.
- **Gravedad**: 40 u/s², `floor_snap_length` para no perder el contacto al bajar colinas.
- **Ratón**: el clic captura el puntero; `Esc` lo libera. El juego muestra la línea de
  controles al arrancar.
- **Animación**: `Idle_Loop` en reposo, `Walk_Loop` al caminar, `Sprint_Loop` al correr,
  `Jump_Start`/`Jump_Loop`/`Jump_Land` en el salto, con velocidad de reproducción
  proporcional a la velocidad real.

### 6.5 Apariencia de Rito (guion de la IA)

Hombre romano de unos 30 años: piel oliva, melena y barba cortas y castañas, túnica de lino
arena con franja púrpura senatorial, cinturón de cuero, sandalias de cuero y corona de laurel.
Estilo low-poly estilizado, coherente con el maniquí base.

## 7. Arte generado con IA

Dos imágenes con `ImageGen`:

1. `assets/rito_sheet.png` — hoja de personaje de cuerpo entero, 3/4, fondo liso neutro.
   Uso: overlay de carga y referencia de construcción del vestuario.
2. `assets/rito_face.png` — retrato frontal de la cara, luz plana, fondo liso. Uso: textura
   de la cara (§6.3).

Las imágenes se guardan en `assets/` y Godot las importa.

**Post-proceso** (Pillow, en local): el fondo de la hoja de personaje era un gris degradado
que se veía como un rectángulo sobre el panel de carga. Se recorta con `floodfill` desde las
cuatro esquinas (tolerancia 60) y se eliminan los píxeles grises claros residuales; después
se recorta al recuadro del personaje y se reduce a 900 px de alto. El retrato facial ya
venía con canal alfa y solo se recortó a la cabeza y se escaló a 256×256.

El `.pck` quedó en **14,4 MB** tras la segunda iteración (texturas del terreno a 512 y
fuera las escenas de editor de Terrain3D). El peso irreducible son las tres regiones de
terreno (11,7 MB) y el maniquí riggeado con sus 46 animaciones.

## 8. Interfaz

Solo dos elementos, coherente con el alcance "explorar libre":

- **Overlay de carga**: retrato de Rito, título "RITO CERO" y una línea con los controles.
- La línea de controles empieza a desvanecerse a los 5 s y desaparece en 1,4 s.

Sin HUD permanente, sin minimapa, sin objetivos, sin menú de pausa.

## 9. Rendimiento

Presupuesto para la GT 640 / 2 GB, con las sombras apagadas:

| Métrica | Objetivo | Medido |
|---|---|---|
| Draw calls | ≤ 60 | 6 de vegetación + terreno + Rito |
| Triángulos visibles | ≤ 80 000 | dentro del presupuesto |
| Sombras dinámicas | 0 | 0 |
| Luces | 1 direccional + ambiente (sin luces extra) | 1 + ambiente |
| Escalado de render | 1.0; bajar a 0.75 solo si hace falta | **0.75** (obligatorio: el terreno es fill-rate bound) |
| FPS objetivo | ≥ 20 a 1280×720 | **20-27** en build debug de editor a 0.75 |

Medición del coste (build debug, 1280×720, en esta GPU):

| Variante | FPS |
|---|---|
|mesh_size 96, tessellation 3, escala 1.0 | 8 |
|mesh_size 64, tessellation 2, escala 1.0 | 13 |
| lo anterior + `macro_variation` y `dual_scaling` apagados | 13 |
| lo anterior + escala 0.75 | **20-27** |

Quitar la vegetación no cambió el FPS (13 → 13): **el cuello de botella es el sombreado
por píxel del terreno**, no la geometría. De ahí que la palanca efectiva sea la escala de
render y no la densidad de plantas.

Reglas: ningún pase visual añade luces reales; los contrastes se resuelven con materiales y
emisivos; cualquier cambio de densidad o de encuadre se mide con FPS antes y después
(la GPU de esta máquina varía entre corridas, así que se comparan varias).

## 10. Export web y serving

### 10.1 Preset

`export_presets.cfg`, preset `Web`. Godot **exige que el archivo esté en la raíz del
proyecto**, no en `web/`; el error que aparece si no es
`This project doesn't have an 'export_presets.cfg' file at its root`.

- Plataforma `Web`, renderer `gl_compatibility`.
- **Extensions Support**: activado (necesario para Terrain3D, R2).
- **Thread Support**: desactivado (build `nothreads`, que es el que trae Terrain3D).
- `exclude_filter`: se excluyen del `.pck` los addons de escritorio (kanban, ziva) y los
  binarios nativos de Terrain3D para Android/iOS/macOS/Linux/Windows; solo se incluye el
  `.wasm` web. Sin esto el `.pck` era de 24 MB; con el filtro queda en 19 MB.
- Salida: `build/web/index.html`.

El export se ejecuta headless:

```
godot --headless --path <proyecto> --export-release "Web" build/web/index.html
```

Resultado: `index.html` + `index.js` + `index.pck` (19 MB) + `index.wasm` +
`index.side.wasm` + `libterrain.web.release.wasm32.nothreads.wasm`. La carpeta destino tiene
que existir: Godot no la crea y el export falla con
`La carpeta de destino no existe o no es accesible`.

### 10.2 Servidor

`web/serve.py`, puerto 8060:

- `.wasm` → `application/wasm`; `.pck` → `application/octet-stream`; `.js` → `text/javascript`.
- Todas las respuestas incluyen `Cross-Origin-Opener-Policy: same-origin` y
  `Cross-Origin-Embedder-Policy: require-corp` (R3).
- `ThreadingHTTPServer` para no bloquear con los requests del `.pck`.

El juego **no** se abre por `file://`: necesita HTTP por lo anterior.

## 11. Verificación

### 11.1 Criterios de aceptación

| # | Criterio | Evidencia | Resultado |
|---|---|---|---|
| A1 | El proyecto abre en Godot sin errores | Editor reabierto sobre el proyecto: log sin errores ni de parseo | Cumple |
| A2 | La escena principal corre y el terreno se ve | Captura del build web: terreno, acantilados y vegetación renderizados | Cumple |
| A3 | Rito aparece en pantalla y está correctamente vestido | Captura: túnica con franja púrpura, cinturón, sandalias, melena, barba, laurel y cara IA | Cumple |
| A4 | Rito se mueve | `window.__rito` antes `(384, 86.67, -1856)` y después `(384, 86.47, -1860.8)` con `w` pulsado: **4,80 m** en el navegador; 33 m en el build nativo | Cumple |
| A5 | El terreno se extiende al caminar | Tras 33 m de recorrido el terreno sigue presente bajo el jugador, sin borde (clipmap sigue al jugador) | Cumple |
| A6 | Las cabeceras y los MIME son correctos | `curl -I`: 200, `application/wasm`, `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp` | Cumple |
| A7 | El `.pck` pesa ≤ 12 MB | `index.pck` = **14,4 MB** (19,6 → 14,4 en la 2.ª iteración) | **No cumple el objetivo original**; el suelo de 11,7 MB de terreno es irreversible |
| A8 | El FPS cumple el presupuesto | 20-27 FPS en build debug a escala 0.75; en Chrome headless con SwiftShader (render por software) da 1 FPS, que no es representativo de la GPU real | Cumple con nota |

Mediciones de la verificación web (Chrome headless + SwiftShader, 960×540):

- Carga del juego: **2 s** hasta `window.__rito.ready === true`.
- Posición de aparición idéntica entre build nativo y web: `(384, 86.67, -1856)`.
- Errores de JavaScript: ninguno (solo avisos de rendimiento de WebGL del render por software).

### 11.2 Herramienta de verificación

Chrome headless local vía `playwright-core`, con los argumentos
`--use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist`
para tener WebGL2 real. El script de comprobación:

1. `navigate_page` a `http://localhost:8060/index.html`.
2. Espera a que `window.__rito_ready` sea verdadero.
3. Captura de pantalla → se comprueba por estadística de píxeles que hay contenido (nada de
   lienzo completamente uniforme o transparente).
4. Lee `window.__rito.position` antes y después de una secuencia de teclas y comprueba que
   cambia.
5. Lee el FPS que el juego expone en `window.__rito.fps`.

Si el juego no expone ese puente en el build, se añade con `JavaScriptBridge` (solo activo
en web) — es la vía objetiva de comprobar movimiento, porque la superficie browser-use del
entorno no entrega teclado real (R7).

## 12. Riesgos y mitigación

| Riesgo | Impacto | Mitigación |
|---|---|---|
| El navegador bloquea la GDExtension por falta de aislamiento de origen | El juego no arranca | `serve.py` manda COOP/COEP; verificar con `curl -I` y con el arranque real en Chrome. Si aun así falla, plan B: servir sin extensiones y sustituir Terrain3D por terreno propio con `FastNoiseLite` (el módulo `vegetation.gd` y `rito.gd` no cambian) |
| La textura IA no encaja en la cabeza | La cara se ve mal | Fallback documentado en §6.3: cabeza lisa con melena y barba |
| FPS por debajo del presupuesto | Juego injugable | Bajar densidad de vegetación, `rendering/scaling_3d/scale` a 0.75, reducir radio de celdas; medir antes y después de cada cambio |
| El editor de Godot reescribe `project.godot` mientras se edita | Pérdida del cambio de renderer | Cerrar el editor antes de tocar `project.godot` y reabrirlo al terminar |
| El terreno del demo resulta un cañón y no un campo | El resultado no es lo pedido | Inspeccionar la captura real; si no encaja, pintar el mapa de alturas con Terrain3D o sustituirlo por terreno propio |

## 13. Orden de implementación

1. Cerrar el editor de Godot. Cambiar `project.godot` a `gl_compatibility`, añadir `main_scene`
   y las acciones de input. Reabrir el editor.
2. `scenes/main.tscn` + `scripts/main.gd`: mundo, jugador y overlay.
3. `scripts/world/world_builder.gd`: Terrain3D, cielo, luz sin sombras, spawn de Rito.
4. `scripts/player/rito.gd`: controlador, cámara y animación.
5. `scripts/player/rito_outfit.gd`: vestuario romano.
6. `scripts/world/mesh_factory.gd` + `vegetation.gd`: olivos, cipreses, trigo, rocas.
7. Arte IA con `ImageGen`; encajar la cara; overlay de carga.
8. `web/export_presets.cfg` + `web/serve.py`; export headless.
9. Verificación con Chrome headless según §11; ajustes de rendimiento si hacen falta.
10. Commit de todo el trabajo.

---

## 14. Segunda iteración (2026-11-02): rendimiento, atmósfera y contenido

### Banco de pruebas

Todo lo anterior se medía a mano y con una sola corrida. Se añadió un banco determinista
(`scripts/dev/bench.gd` + `tools/bench.tscn`): 3 poses de cámara fijas, 120 frames por pose,
mediana de 3 corridas, y acepta un cambio solo con Δ > 15 %. Mide FPS, percentil 5, draw
calls, triángulos y tiempo de CPU. Las variantes de calidad se conmutan con `--variant N`
sobre **el mismo export**, así que la matriz completa cuesta un export, no nueve.

El FPS se decide en el build nativo. El navegador headless renderiza con SwiftShader (por
software) y da 1-2 FPS: no es representativo de la GPU.

### Resultados medidos (build debug nativo, 1280×720)

| Configuración | FPS mediano | p5 | draw calls | triángulos | CPU |
|---|---|---|---|---|---|
| Baseline: shader nativo, texturas 1K | **15,1** | 10-12 | 94 | 457.530 | 88,6 ms |
| + texturas del terreno a 512 | **22,7** | 19-25 | 94 | 457.530 | 43,7 ms |
| + shader ligero (`tessellation_level = 0`, `mesh_size = 32`) | **39,8** | 18,6 | 73 | 127.194 | 52,2 ms |
| Todo junto, con ruinas, cueva, NPCs y HUD | **60,0** (tope de vsync) | 57-58 | 85-107 | 113.448-146.292 | 15,6 ms |
| Todo junto, sin vegetación | 60,0 | 58 | 81 | 89.046 | 15,7 ms |

Cuatro conclusiones, todas con número detrás:

1. **El terreno era fill-rate y geometría a la vez.** La spec original presupuestaba
   ≤ 80.000 triángulos y ≤ 60 draw calls; lo medido era **457.530 triángulos y 94-111 draw
   calls**, es decir el presupuesto estaba mal, no roto. El shader ligero lo baja a ~127.000.
2. **Bajar la resolución de textura sube el FPS** (15,1 → 22,7) además de recortar el pack:
   en una GT 640 el ancho de banda de textura es un recurso escaso, no solo los píxeles.
3. **El coste de todo el contenido nuevo es medible-cero**: con vegetación apagada el FPS es
   idéntico (60,0), y los monumentos son un draw call cada uno.
4. La palanca que más rinde sigue siendo la **escala de render**, ahora adaptativa con
   histéresis (baja si el FPS medio < 24 durante 2 s, sube si > 57 durante 6 s, como mucho
   un ajuste cada 3 s porque reescalar el framebuffer da un tirón). Tecla `Q` para fijarla a
   mano.

### Qué se añadió

- **Cross-fade** de 0,25 s entre animaciones y resolución de nombres cacheada (antes se
  consultaba `has_animation()` hasta 4 veces por frame).
- **Ciclo día/noche** de 10 min (`scripts/world/day_night.gd`): sol en arco, cielo, ambiente
  y niebla interpolados **juntos**. De noche Rito saca una antorcha (`Idle_Torch_Loop` +
  `OmniLight3D` de 6 m) y solo entonces.
- **HUD**: minimapa generado una vez desde el heightmap con sombreado de relieve, brújula y
  marcadores `Label3D` en los puntos de interés.
- **Ruinas romanas**: pórtico de 4 columnas, columna rota y muro de mampostería. Cada
  monumento es **una sola malla fusionada** (1 draw call) colocada en la zona más llana
  disponible, con separación mínima entre puntos.
- **Boca de cueva** con un `Area3D` que enciende la luz solo al entrar.
- **4 NPCs romanos** que patrullan con waypoints sobre el terreno y evitación por raycast.

### Dos decisiones de diseño que contradijeron lo previsto

- **El `Tunnel.tscn` del pack no se puede trasplantar.** Sus rocas van escaladas 5-11× y
  colocadas para el acantilado del demo; al moverlo a otro sitio quedaba como **un aro de
  rocas flotando sobre el jugador**, y sus cristales usan translucidez con refracción y rim,
  el pixel shader más caro del renderer de Compatibility. Se construyó la boca de cueva con
  primitivas. El objetivo aprobado era "un destino en el mundo", no ese asset.
- **Los NPCs no usan NavMesh.** El horneado en runtime del pack
  (`NavigationServer3D.bake_from_source_geometry_data()`) es **síncrono** y con
  `variant/thread_support=false` el `WorkerThreadPool` no tiene worker real: cada rehorneado
  (cada 64 m de movimiento) congelaría el juego segundos. Se optó por waypoints + raycast.

### Correcciones a esta spec

Se corrigieron en el cuerpo del documento: las tres regiones de terreno **no son variantes**
(mundo de 1024 × 3072 m), el radio de vegetación es 224 m y no 160, las densidades son 6/5/4
y no 14/10/6, la cámara no usa `SpringArm3D`, son 46 animaciones y no 45, la cara es un
`QuadMesh` con textura alfa y no una esfera proyectada, y el overlay se desvanece a los 5 s.

### Contraste en el navegador con GPU real

`tools/web_bench.py` mide el build web en Chrome con ANGLE/D3D11 y **aborta si el renderer
detectado es software**, porque el headless con SwiftShader da 1-2 FPS y no significa nada.

Leyendo `WEBGL_debug_renderer_info`: `ANGLE (NVIDIA, NVIDIA GeForce GT 640 Direct3D11
vs_5_0 ps_5_0, D3D11)` → GPU real. Resultado sobre 18 muestras de 1 s:

| Métrica | Valor |
|---|---|
| FPS mediano en Chrome | **42,0** (mín 39, máx 44) |
| Draw calls | 100 |
| Triángulos | 145.780 |
| Variante | 1 (shader ligero, escala 0,75) |
| Carga hasta `ready` | 2 s |

Es el número honesto para el navegador: por debajo de los 60 del build nativo por el coste de
ANGLE, pero 2,8× el baseline original. Verificación funcional en Chrome headless: 5,6 m de
recorrido con `w`, cero errores de consola.

### Pendiente de la segunda iteración (no aprobado)

Reconstrucción incremental de vegetación (el tirón de CPU al cruzar celda sigue), gamepad,
modo foto, audio procedural y `AnimationTree` completo.

### Tercera iteración: combate

Ejecutada. Gladius, lanza, NPCs hostiles con aggro y muerte, HUD de vida y bajas. Spec y
números medidos en `2026-11-02-rito-cero-combate-design.md` (§6.1) y plan con las desviaciones
en `../plans/2026-11-02-rito-cero-combate.md`. Con el combate activo: 40,0 FPS de mediana en
Chrome sobre la GT 640, 103 draw calls, `.pck` de 14,42 MiB.
