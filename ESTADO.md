# Estado del escritorio — 30 de agosto de 2026

GNOME 50 sobre Ubuntu 26.04, Wayland. El `CLAUDE.md` dice **qué es** el proyecto;
acá va **en qué anda** el escritorio hoy. El relato largo de cada sesión —
síntomas, callejones sin salida, evidencia — está en `ESTADO-historial.md`, que
**no hace falta leer** salvo que algo se rompa.

Este archivo es sobrescritura, no bitácora: si vuelve a pasar de ~150 líneas, hay
un relato adentro que debía ser una decisión de una línea.

Regla que le dio origen: **todo cambio que necesite cerrar sesión se escribe antes
de cerrarla.** Si no, la sesión siguiente arranca sin contexto y repite el
diagnóstico desde cero — pasó tres veces con el mismo bug.

## Dónde retomar

Rama `claude/linux-ubuntu-windows-migration-whc0li`, **varios commits adelante de
`origin`**: falta pushear. Es lo único pendiente.

El dock quedó verificado entero, sin necesidad de cerrar sesión: ver
`gshell.sh patch` más abajo, que es la novedad que más cambia el día a día.

```bash
bash setup/gshell.sh check          # unsafe mode: Alt+F2 → lg → global.context.unsafe_mode = true
bash setup/gshell.sh push bottom
bash setup/gshell.sh find macos-dock-root
```

## Qué funciona, verificado

- **PaperWM ya no tira la sesión al abrir Discord.** Era un SIGSEGV del shell:
  el timeout de `workspace-changed` redimensionaba una `MetaWindow` que mutter
  ya estaba desmanejando, y el splash de Discord se cierra a los ~990 ms, justo
  adentro de esa ventana. Dos guards en `tiling.js`, versionados en
  `setup/patches/paperwm-timeout-ventana-muerta.patch`.
  Verificado el 30/08: cinco rondas de abrir y cerrar Discord, mismo PID del
  shell, cero segfaults, y el journal muestra el splash — o sea que la prueba
  ejercitó el caso real, no uno en el que Discord no llegó a abrir.
- **El dock se revela al empujar el borde de abajo, y se esconde al irse.**
  Verificado el 30/08 con diez ciclos seguidos por el dispositivo virtual de
  Clutter, y repetido con el arreglo de `_scheduleHide()` ya cargado, esta vez
  **dejando el puntero quieto 1,2 s sobre el borde** antes de alejarlo: las diez
  veces revela, se queda mientras el puntero está encima y esconde en cuanto se
  va, con la Y de reposo en **987 exacto en las diez** — la deriva de 20 px por
  ciclo está muerta. Los contadores muestran el mecanismo: 4 reagendas de
  `_scheduleHide` por ciclo (la inicial más 1200/400) y un `_hide` por ciclo.
  Confirmado en píxeles: los ocho iconos aparecen en la captura del recorte.
  Cuidado al repetirlo: **si se toca el mouse durante la tanda, la prueba miente**
  — el puntero físico pisa al virtual y `_pointerNearEdge()` mide la mano, no el
  script. La versión buena del test descarta el ciclo si el puntero se corrió más
  de 40 px de donde lo dejó.
  Las tres causas que había: barrera mal puesta (ahora `getWorkAreaForMonitor()`
  con 1 px de recorte por punta, porque el segundo monitor arranca en x=1920),
  `_isAnimating` colgado en `true` (Clutter no llama `onComplete` al cancelar una
  transición), y las animaciones leyendo `container.y` en vez de la Y de reposo.
- **El dock se esconde de nuevo.** `dockVisibility.js` colgaba
  `enter-event`/`leave-event` de la raíz del dock, que es `reactive: false` a
  propósito — Clutter no manda cruces a un actor no reactivo, así que esos
  handlers eran código muerto y el dock se revelaba una vez y se quedaba visible
  para siempre. Medido: 0 eventos en la raíz contra 4 en el icon box, y el
  `_scheduleHide()` viejo salía sin reagendar. Ahora se reagenda mientras el
  puntero siga encima. Verificado en caliente con `gshell.sh patch`; el archivo
  en `~/.local` ya está, así que el próximo login arranca con esto puesto.
- **No hay fantasma al minimizar.** El guard vive en código propio
  (`mactahoe-tweaks/ghostGuard.js`), no en el parche de PaperWM: ese parche está
  bien puesto pero **no llega a correr** para esas ventanas. Regla única: una
  ventana minimizada no se dibuja.
- **La barra de arriba a la derecha tiene un solo botón**, donde había cinco
  iconos: 132 px → 60 px, medido. Los cinco no eran indicadores sueltos, viven
  adentro del hub, así que se esconde la caja entera y se pone un icono propio.
- **Flatpaks, Discord por `.deb`, fuentes, atajos**: todo cerrado. El detalle en
  `ESTADO-historial.md`.

## Abierto

- **Ruido en el journal**, sin síntoma visible, sin mirar: PaperWM
  (`Meta.BackgroundActor ... already disposed`, en `utils.js:567` / `grab.js:441`)
  y `macos-dock` (`lib/iconManager.js:474` ← `:374` ← `:263`, `dockManager.js:390-394`,
  `_applyDockPosition()` `:497`).
- **`auto-hide` aparece en `false` al arrancar la sesión** aunque se lo haya
  dejado en `true`. No se investigó si lo pisa el reinicio o el arranque de la
  extensión.
- Curiosidad técnica, no un bug: por qué el `showHandler` parcheado de PaperWM no
  corre para las ventanas que dejaban fantasma. El guard propio ya cubre el
  síntoma.

## Decisiones cerradas — no reabrir

- **El botón del hub se queda invisible.** El glifo no se dibuja (adentro del
  botón hay 2 colores: fondo de píldora y fondo de panel, cero píxeles de icono;
  el SVG está sano, renderizado con librsvg se ven los dos interruptores). La
  causa quedó sin diagnosticar **a pedido del usuario, el 30 de agosto**: le
  gusta así, la zona sigue siendo clickeable y abre el hub. Si una sesión futura
  ve el botón vacío, que no lo "arregle".
- **`niri` descartado**: reemplaza GNOME Shell entero y se perderían dock, tema y
  las dos extensiones propias. PaperWM da el mismo desplazamiento sin tirar nada.
- **Blur my Shell con el componente `panel` apagado**: no porque sobre, sino
  porque no puede — Yaru pone `#panel { background-color: #131313 !important }` y
  eso sólo lo gana un estilo inline, que es lo que hace `panelStyle.js`.
- **El dock no recibe actualizaciones de EGO**: es un fork con UUID propio.

## Cómo mirar el escritorio sin trabajar a ciegas

Dos diagnósticos de este repo salieron mal por leer CSS en vez de píxeles, y
varias sesiones se fueron en volver a descubrir cómo hablarle al shell.

```bash
bash setup/gshell.sh check                 # ¿unsafe mode prendido?
bash setup/gshell.sh find macos-dock-root  # un actor: posición, tamaño, visible
bash setup/gshell.sh tree 2                # árbol de actores visibles
bash setup/gshell.sh pointer 960 400       # mover el puntero (Wayland)
bash setup/gshell.sh push bottom           # empujar un borde hasta la barrera
bash setup/gshell.sh patch <js> <Clase>     # recargar código sin cerrar sesión
bash setup/shot.sh --probe 300,0,60        # RGB de una columna: los píxeles
bash setup/shot.sh --crop 700,980,520,100  # un recorte de la pantalla
bash setup/shell-sandbox.sh <uuid>         # GNOME Shell headless, sin arriesgar
bash setup/watch-shell.sh                  # journal del shell, filtrado
```

Lo que hay que saber antes de usarlos:

- **`Eval` sólo responde con unsafe mode**, que se prende a mano una vez por
  sesión (`Alt+F2` → `lg` → `global.context.unsafe_mode = true`) y muere con el
  logout. Adentro de `Eval` **no se puede importar `Main`** (la UI del shell es
  ESM): a los objetos se llega caminando `global.stage`. `imports.gi.*` sí anda.
- **El árbol de actores dice qué cree el shell, no qué se dibujó.** Para píxeles,
  `shot.sh`. En Wayland `grim` no sirve y `org.gnome.Shell.Screenshot` por D-Bus
  da `AccessDenied`; la vía que funciona es el portal, que es lo que usa `shot.sh`.
- **Una extensión sí se recarga en vivo, aunque `ReloadExtension` esté muerto**
  (responde `is deprecated and does not work`). La vía es `gshell.sh patch`:
  adentro de `Eval`, `import('file://<ruta>')` devuelve el módulo **ya cargado**
  por el shell, y la misma ruta con otra query (`?v=<ts>`) lo relee del disco;
  copiando los métodos del segundo prototipo al primero, las instancias vivas
  pasan a correr el código nuevo. Esto sacó el logout por iteración, que era el
  gasto más grande del proyecto.
  Lo que **no** cubre: el `constructor` ya corrió y `enable()` también, así que
  los campos y las señales conectadas quedan como estaban — alcanza sólo a
  métodos del prototipo. Para un cambio en `start()` o en el constructor, sigue
  siendo sandbox o logout.
- Los `console.debug` de las extensiones los descarta GLib salvo que
  `G_MESSAGES_DEBUG` incluya el dominio `Gjs` — `gshell.sh debug` lo prende en
  caliente.
- El kit desde una sesión sin terminal: `--perf`, `--base`, `--gpu`, `--desnap` y
  `--dev` piden `sudo` y abren una ventana gráfica de contraseña.
- Si una Flatpak no abre después de un login:
  `systemctl --user restart xdg-document-portal` antes que cualquier otra cosa.
