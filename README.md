# Rito Cero

Repositorio: https://github.com/traderxael/rito-cero

Juego de acción en Godot 4.7.2 (Compatibility / WebGL2). Sin historia: peleas
por encargos.

## Misiones

- Tablero de misiones (tecla **J**): purga de bandidos (`bandit_purge`, 4 en la
  Columna rota) y defensa del templo (`city_defense`, 3 oleadas 4/6/8 en las
  ruinas). El sistema ofrece, el jugador acepta y cobra.
- **Escolta** (`escort`): acompaña a un superviviente desde las ruinas hasta la
  cueva. Si cae, la misión falla; si llega, se completa.
- **Recolección** (`collect`): recoge 6 suministros de quest junto al Muro
  mientras bandidos hostigan. Si Rito muere, falla.
- **Contrarreloj** (`timed`): purga de bandidos en la Columna rota con cuenta
  atrás de 90 s. Si el tiempo se agota, falla.
- **Contratos** (desde nivel 10): purga y defensa con mutadores (vida +50 %,
  daño +25 %, velocidad +15 %) y recompensa ×1,5, con cooldown independiente de
  la misión base.
- **Horda del coliseo**: oleadas infinitas de bandidos con escalado de vida y
  número. Cada oleada superada suma a la racha y paga una recompensa pequeña. Al
  morir Rito, la horda termina (sin permadead: Rito reaparece normalmente) y se
  guarda el récord de racha.

- Recompensas: **denarios**, comida/agua, botín absurdo — nunca armas de la
  Armería (ese árbol es el único camino a puñal e hispaniense; la spatha es de
  base).
- Progresión: **XP → nivel → mejor botín** (`xp_para_nivel(n)=100*n^1.5`,
  cap 20; subir da +5 HP máx y mejora `loot_tier`). Curación: `aqua` +20,
  `panis` +35 (con Salazón +15 extra).
- **Racha**: misiones completadas y oleadas de horda suman a la racha actual;
  morir, fallar o abandonar la resetea. La mejor racha se guarda y se muestra en
  el HUD y en la pausa.
- Árbol de tecnología (tecla **T**): gasta **denarios** en 9 nodos anacrónicos
  (pozo, acequia, salazón, granero, molino, bodega de nieve y 3 armerías que
  desbloquean puñal e hispaniense y templan el gladius).
- HUD: barra de XP ámbar + nivel, denarios, racha actual y mejor racha,
  contador de misión activa, punto dorado en el minimapa. La columna de luz
  3D de objetivo se desactivó por recorte de presupuesto (T14); el punto del
  minimapa sigue activo.
- Guardado en `localStorage` (web): XP, nivel, denarios, inventario,
  tecnología y mejor racha. La misión activa no se guarda: al recargar vuelve
  a disponible. El guardado lleva `version` y valida tipos: un save corrupto
  degrada cada campo a su default en vez de impedir el arranque. Los cooldowns
  de misión se persisten (tiempo unix) y sobreviven a recargas.
- **Evento de mundo (Task 12) recortado (T14, último recurso)**: ya no se
  instancia en el juego; la entrega es tablero + purga + defensa. La clase y
  su plantilla oculta siguen para tests en aislamiento.

## Compañeros

- El **moloso** sigue a Rito, persigue hostiles y muerde; sus bajas cuentan
  para el jugador. No muerde ni cuenta cadáveres.
- El **esclavo** es un acompañante que sigue a Rito y ataca hostiles con su
  gladius. Vive en la capa 64, no está en el grupo `hostiles` y su volumen solo
  golpea la capa 4: no recibe fuego amigo ni lo persigue el moloso.

## Controles

WASD mover · ratón mirar · clic tajo · clic derecho golpe fuerte · 1-5 armas ·
F esquiva · C silbar al moloso · E comer · J tablero · T tecnología ·
I inventario · B arsenal · Q calidad · Esc pausa.

Game feel del controlador: coyote time 0,12 s, buffer de salto 0,12 s, cámara
suavizada, FOV 68/74 al caminar/correr y land dip al aterrizar.

## Verificación (esta sesión, 2026-11-12)

- Headless, sin errores de parseo; `main.tscn` corre 120 frames sin errores de
  script (solo quedan los avisos de RIDs de Terrain3D al salir).
- `progression_test` **317/317**, `combat_test` **94/94**, `combo_test`
  **16/16**, `feel_test` **27/27**, `dog_follow_test` **6/6**, `audio_test`
  **26/26**, `mission_test` **33/33**, `pause_test` **10/10**, `pickup_test`
  **8/8**, `boss_test` **15/15**, `cave_test` **17/17**, `input_map_test`
  **6/6**, `slave_test` **7/7**, `controller_test` **12/12**,
  `guard_parry_test` **45/45**, `menu_coordinator_test` **15/15**,
  `enemy_variety_test` **27/27**, `new_missions_test` **21/21**,
  `collect_test` **6/6**, `contracts_test` **10/10**, `horde_test` **8/8**.
- El crítico se decide con el estado **anterior** al golpe: el primer tajo no
  es crítico; el siguiente, si el objetivo quedó aturdido, sí.
- La esquiva ya no suma dos veces el impulso; el STUN corta el tajo del
  bandido; el pilum no cuenta cadáveres.

## Pendientes conocidos

- Ninguno pendiente crítico. Los menús blandos (J/T/I/B) ahora usan un
  coordinador que impide que se apilen. La spatha está rebalanceada (cadencia
  1,05 s) como sidegrade del gladius. Los cooldowns de misión se persisten y
  sobreviven a recargas. La racha actual y la mejor se muestran en HUD y pausa.

## Licencia

El código está bajo licencia MIT (ver `LICENSE`). Los modelos de Quaternius son
CC0 1.0 (ver `License.txt`) y los addons conservan sus licencias en
`THIRD_PARTY.md`.

## Rendimiento medido (T14, 2026-11-07, GT 640 real; no re-medido en esta sesión)

- Nativo `tools/bench.tscn --variant 1` (ventana opengl3): **median_avg=60.0**
  (3 corridas, draws 146–153, tris 122k–175k). Sin regresión >5%.
- Web `tools/web_bench.py` (ANGLE D3D11, GT 640): **mediana 26–29 FPS
  (<36)**. Recortes aplicados y medidos: marcador 26.0, evento 27.0. El
  déficit no se explica por esos sistemas (inactivos en spawn); la escena
  base en web no llega a 36 en este entorno. Ver spec §6 para números exactos.
- `tools/verify_web.js`: **15/15 PASS** (movimiento, combate por puente,
  arsenal, puente `xp`/`level`/`coins`/`mission`).
- Determinista: `progression_test` **317/317**, `combat_test` **94/94**,
  `combo_test` **16/16**, `feel_test` **27/27**, `dog_follow_test` **6/6**,
  `audio_test` **26/26**, `mission_test` **33/33**, `pause_test` **10/10**,
  `pickup_test` **8/8**, `boss_test` **15/15**, `cave_test` **17/17**,
  `input_map_test` **6/6**, `slave_test` **7/7**, `controller_test` **12/12**,
  `guard_parry_test` **45/45**, `menu_coordinator_test` **15/15**,
  `enemy_variety_test` **27/27**, `new_missions_test` **21/21**,
  `collect_test` **6/6**, `contracts_test` **10/10**, `horde_test` **8/8**.
- Capturas en la raíz: `shot_board.png`, `shot_mission.png`, `shot_tech.png`
  (con ventana; en headless puro `shot.tscn` se cuelga).
