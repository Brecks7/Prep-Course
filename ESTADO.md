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
`origin`**: falta pushear.

Hay **un arreglo escrito que todavía no corre** (`dockVisibility.js`, ver abajo).
Entra solo en el próximo inicio de sesión; no hay apuro.

Después de ese logout, lo único que queda por verificar: los diez ciclos del dock
**dejando el puntero quieto sobre el borde** entre ciclo y ciclo. Es el caso que
el arreglo cubre y que la prueba anterior no pudo ejercitar.

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
- **El dock se revela al empujar el borde de abajo, y sigue haciéndolo.**
  Verificado el 30/08 con diez ciclos seguidos por el dispositivo virtual de
  Clutter: revela y esconde las diez veces, y la Y de reposo termina en **987
  exacto en las diez** — la deriva de 20 px por ciclo está muerta. Confirmado
  también en píxeles (dock oculto vs. revelado: 132.755 de 208.000 píxeles
  distintos, y los ocho iconos en la captura).
  Las tres causas que había: barrera mal puesta (ahora `getWorkAreaForMonitor()`
  con 1 px de recorte por punta, porque el segundo monitor arranca en x=1920),
  `_isAnimating` colgado en `true` (Clutter no llama `onComplete` al cancelar una
  transición), y las animaciones leyendo `container.y` en vez de la Y de reposo.
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

- **El arreglo del dock todavía no corre.** `dockVisibility.js` colgaba
  `enter-event`/`leave-event` de la raíz del dock, que es `reactive: false` a
  propósito — Clutter no manda cruces a un actor no reactivo, así que esos
  handlers eran código muerto y el dock se revelaba una vez y se quedaba visible
  para siempre. Medido: 0 eventos en la raíz contra 4 en el icon box. Ahora
  `_scheduleHide()` se reagenda mientras el puntero siga encima y esconde en
  cuanto se va. Escrito y copiado a `~/.local`; **entra al próximo login.**
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
- **Desde GNOME 50 no se recarga una extensión en vivo** (`ReloadExtension`
  responde `is deprecated and does not work`): o sandbox, o cerrar sesión.
- Los `console.debug` de las extensiones los descarta GLib salvo que
  `G_MESSAGES_DEBUG` incluya el dominio `Gjs` — `gshell.sh debug` lo prende en
  caliente.
- El kit desde una sesión sin terminal: `--perf`, `--base`, `--gpu`, `--desnap` y
  `--dev` piden `sudo` y abren una ventana gráfica de contraseña.
- Si una Flatpak no abre después de un login:
  `systemctl --user restart xdg-document-portal` antes que cualquier otra cosa.
