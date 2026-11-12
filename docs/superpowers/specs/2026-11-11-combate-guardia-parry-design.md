# Combate: guardia, parry y contraataque

Fecha: 2026-11-11
Estado: propuesto para aprobación

## Intención

El combate actual ya tiene ataque, fuerte, combo de tres, esquiva, crítico por espalda,
aturdimiento y cinco armas. La única defensa es la esquiva. Esta mecánica añade un
intercambio de golpes legible: el jugador levanta la guardia, puede arriesgar un parry en
el último instante y castigar con un contraataque. El enemigo gana un ataque telegrafiado
para que el parry sea una decisión y no un botón de suerte.

## Objetivos

- Añadir guardia activa con coste y ruptura.
- Añadir parry con ventana corta y recompensa clara.
- Añadir contraataque (riposte) tras un parry exitoso.
- Telegrafiar el ataque enemigo lo suficiente para poder leerlo.
- Mantener intactos ataque, combo, esquiva, armas y crítico actuales.

## No objetivos

- No añadir stamina general ni cambiar el movimiento base.
- No rehacer la IA enemiga ni añadir bloqueo a los NPCs.
- No crear animaciones nuevas; se reutilizan clips existentes.
- No tocar el sistema de misiones, loot o progresión.

## Enfoques considerados

1. **Solo guardia**: mantiene pulsado Q y reduce daño. Es simple, pero pasivo y no premia
   el timing.
2. **Solo parry**: pulsación en ventana corta, sin guardia mantenida. Muy exigente y
   castiga a quien no acierta.
3. **Guardia + parry + contraataque** *(elegido)*: Q mantenido bloquea; Q pulsado en el
   último instante hace parry; el parry abre una ventana de contraataque. Cubre defensa
   para principiantes y recompensa para jugadores hábiles.

## Mecánica

### Entrada

- Nueva acción `block`, tecla **Q**.
- Mantener Q: guardia.
- Pulsar Q: intento de parry durante 0,20 s.
- Atacar mientras se mantiene Q baja la guardia y ejecuta el ataque.
- Esquivar cancela la guardia.

### Guardia

- Reduce el daño frontal un **80 %**.
- Solo protege ataques que vengan de delante: producto escalar entre el frente del
  personaje y la dirección al atacante `>= 0,15`. Por la espalda, el golpe entra completo.
- Consume guardia: `coste = daño * 1,1`. Guardia máxima 100.
- Se regenera a **22/s** tras 0,7 s sin bloquear.
- Movimiento al **55 %** mientras se mantiene.
- Si la guardia llega a 0: **ruptura**. El jugador recibe el 50 % del golpe, queda
  aturdido 0,8 s, no puede guardar 1,5 s y la barra vuelve al 25 %.

### Parry

- Ventana de **0,20 s** desde que se pulsa Q. Soltar Q no cancela la ventana: el gesto
  es una pulsación. Atacar o esquivar sí la cancela.
- Si un ataque frontal impacta dentro de la ventana: daño 0, coste de guardia 0,
  atacante aturdido **1,1 s**, y se abre riposte.
- El parry no funciona por la espalda.
- Feedback: destello dorado, hit-stop corto, sonido de impacto y cartel `PARRY`.

### Contraataque (riposte)

- Ventana de **1,5 s** tras un parry.
- El siguiente golpe cuerpo a cuerpo hace **1,75×** daño y fuerza crítico/aturdimiento.
  Sobre un enemigo ya aturdido por el parry nunca hace menos que el crítico normal
  (2×): se usa el mayor de ambos multiplicadores.
- Se consume al impactar o al expirar la ventana.
- El pilum no consume riposte: es ataque a distancia.

### Telegrafiado enemigo

- `AttackVolume.begin_swing` acepta un `windup` opcional (por defecto 0, para no romper
  llamadas existentes).
- El bandido reproduce `Sword_Attack` a velocidad 0,7 y abre el volumen **0,35 s** después
  de empezar. El empuje usa el mismo windup.
- El sonido de swing suena al iniciar el windup, no al impactar.
- La ventana de daño sigue siendo la misma fracción del clip, solo desplazada.

## Arquitectura

- `scripts/player/rito.gd`: estado de guardia, barra, parry, riposte, `receive_attack`,
  modificador de velocidad y señales (`guard_changed`, `parried`, `guard_broken`,
  `riposte_changed`).
- `scripts/player/rito_combat.gd`: lee la entrada `block`, cancela guardia al atacar o
  esquivar, y aplica el multiplicador de riposte en `_on_landed`.
- `scripts/combat/attack_volume.gd`: `windup` opcional; si el cuerpo tiene
  `receive_attack`, le delega el golpe en vez de llamar directamente a `Combatant`.
- `scripts/npc/hostile_npc.gd`: windup de 0,35 s y animación más lenta.
- `scripts/ui/hud.gd`: barra de guardia bajo la vida y carteles `PARRY` /
  `CONTRAATAQUE`.
- `project.godot`: acción `block` con Q.

## Números iniciales

| Valor | Inicio |
|---|---|
| Guardia máxima | 100 |
| Reducción frontal | 80 % |
| Coste por golpe | daño × 1,1 |
| Regeneración | 22/s tras 0,7 s |
| Velocidad con guardia | 55 % |
| Ventana de parry | 0,20 s |
| Aturdimiento por parry | 1,1 s |
| Ventana de riposte | 1,5 s |
| Multiplicador riposte | 1,75× |
| Windup enemigo | 0,35 s |
| Ruptura: daño recibido | 50 % |
| Ruptura: aturdimiento | 0,8 s |
| Ruptura: bloqueo de guardia | 1,5 s |

## Pruebas

Nuevo `tools/guard_parry_test.gd` determinista, sin GPU:

1. La acción `block` existe.
2. Guardia reduce daño frontal y consume barra.
3. Ataque por la espalda ignora la guardia.
4. La barra se agota y provoca ruptura con aturdimiento.
5. Parry dentro de ventana: daño 0 y atacante aturdido.
6. Parry fuera de ventana: se comporta como guardia normal.
7. Riposte: el siguiente golpe hace 1,75× y aturde; el segundo vuelve a la normalidad.
8. `windup` retrasa el daño del `AttackVolume`.
9. La guardia se cancela al atacar y al esquivar.

Se ejecuta con la herramienta `run_tests` de Ziva y, si falla, se revisa el log de Godot.

## Riesgos

- No hay clip de bloqueo en el pack. La guardia usa `Sword_Idle` como pose y el parry se
  comunica con feedback visual/sonoro, no con una animación dedicada.
- El `AttackVolume` es compartido por jugador y NPC; el cambio debe mantener el
  comportamiento actual cuando no hay `receive_attack`.
- El test de combate existente espera 94 checks; no se modifica para no alterar su
  recuento. Las pruebas nuevas van en un archivo aparte.

## Criterios de aceptación

- Q mantenido levanta guardia, frena el movimiento y muestra barra.
- Un golpe frontal bloqueado quita poca vida y gasta barra; uno por la espalda entra completo.
- Q en el último instante muestra `PARRY`, no quita vida y deja al enemigo vendido.
- El siguiente golpe tras un parry hace daño dorado aumentado y aturde.
- La guardia se rompe tras varios golpes y castiga con aturdimiento.
- Ataque, combo, esquiva, armas y crítico siguen funcionando como antes.