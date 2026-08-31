# Estado del escritorio — 31 de agosto de 2026

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

**La prueba pendiente es abrir CS2.** El cuelgue del 31/08 —pantalla negra al
lanzarlo— quedó diagnosticado y mitigado, pero **sin verificar**: se escribió esto
primero a propósito, porque si vuelve a colgar se lleva puesto Xwayland y con él la
conversación. Al abrirlo, tener `journalctl -kf | grep amdgpu` en otra terminal. La
primera partida va a tardar más en cargar: el shader cache se está regenerando.

Si vuelve a colgar, la escalada está en `ESTADO-historial.md` (sesión del 31/08):
`RADV_DEBUG=llvm`, después Steam por `.deb`/Flatpak. Y para capturar en vez de
colgar: `RADV_DEBUG=hang MESA_VK_ABORT_ON_DEVICE_LOSS=1 %command%`.

**Falta pushear**, rama `claude/linux-ubuntu-windows-migration-whc0li`, **23 commits
adelante de `origin`**. Está trabado por afuera del repo: esta máquina no tiene con
qué autenticarse contra GitHub — no hay `gh`, no hay `credential.helper` y no hay
claves SSH, así que `git push` muere con `could not read Username for
'https://github.com'`. Se destraba con `sudo apt install gh && gh auth login`
(interactivo, **lo corre la persona**), o con una clave SSH y el remoto en
`git@github.com:`.

**Falta un login limpio para el dock.** Los dos arreglos del 31/08 —umbral de
revelado y ciclado del clic— están verificados, pero la sesión viva quedó con una
barrera de presión huérfana (GNOME marcó `macos-dock` INACTIVE al detectar los
archivos cambiados y no corrió su `disable()`), así que ahí ya no se puede medir el
revelado: los choques contra la barrera nueva no llegan. La prueba en el sandbox sí
es limpia. Al volver a entrar, repetir el gesto suave contra el borde de abajo y los
tres clics sobre el icono de la terminal.

Antes de tocar nada del dock: `gsettings ... auto-hide` tiene que estar en `true`
(ver «Abierto»).

```bash
bash setup/gshell.sh check          # unsafe mode: Alt+F2 → lg → global.context.unsafe_mode = true
bash setup/gshell.sh push bottom
bash setup/gshell.sh find macos-dock-root
```

## Qué funciona, verificado

- **El repo se mudó a `~/Documentos/Proyectos/Configurador`** (31/08). Estaba en
  `~/Imágenes/Prep-Course`, que contradecía la regla de arranque del `CLAUDE.md`
  global. Verificado desde la ruta nueva: `doctor.sh` con 0 críticos y 0 errores de
  gnome-shell, y `npm test` con 129 tests en 7 suites. Nada del kit tenía la ruta
  vieja hardcodeada. Las cuatro memorias del proyecto se consolidaron en la key
  `-home-son-Documentos-Proyectos-Configurador` — venían partidas en **dos** keys, y
  las dos de la key `-home-son-Prep-Course` (`sudo-requiere-ventana-grafica`,
  `setup-install-necesita-yes`) estaban huérfanas: no cargaban desde ninguna ruta.
  Comprobado ya con una sesión abierta desde la ruta nueva: las cuatro cargan al
  arrancar, y `doctor.sh` da 0 críticos y 0 errores de gnome-shell. En las dos keys
  viejas quedaron **copias idénticas** de esas memorias (se copiaron, no se
  movieron); son inertes porque esas rutas ya no existen, pero si alguna vez se
  edita una memoria, la que vale es la de la key nueva.
- **PaperWM ya no tira la sesión al abrir Discord.** Era un SIGSEGV del shell al
  redimensionar una `MetaWindow` que mutter ya estaba desmanejando. Dos guards en
  `tiling.js`, en `setup/patches/paperwm-timeout-ventana-muerta.patch`. Cinco
  rondas de abrir y cerrar Discord, mismo PID del shell, cero segfaults.
- **El dock se revela y se esconde sin derivar.** Diez ciclos por el dispositivo
  virtual de Clutter: las diez revela, se queda mientras el puntero está encima,
  esconde al irse, y la Y de reposo queda en **987 exacto en las diez** — la
  deriva de 20 px por ciclo está muerta. Las tres causas (barrera mal puesta,
  `_isAnimating` colgado, animaciones leyendo `container.y`) están en
  `setup/README.md`. **Si se toca el mouse durante la tanda la prueba miente**:
  el puntero físico pisa al virtual, y el test bueno descarta el ciclo si el
  puntero se corrió más de 40 px de donde lo dejó.
- **El dock se esconde de nuevo.** Los `enter-event`/`leave-event` colgados de la
  raíz eran código muerto: es `reactive: false` a propósito y Clutter no le manda
  cruces (medido: 0 en la raíz contra 4 en el icon box). Ahora `_scheduleHide()`
  mira dónde está el puntero y se reagenda mientras siga encima.
- **El revelado ya no pide un empujón de 100 px.** Era la causa del «se revela
  una vez y después no»: la presión que cuenta mutter es cuánto **te habrías
  pasado de largo**, no cuánto recorriste hasta el borde. El primer gesto —un
  barrido desde el medio de la pantalla— da 15 choques y dispara; el segundo, con
  el puntero ya cerca del borde, da uno o dos y acumula ~18 px, y con umbral 100
  no dispara nunca. Barrido de valores con el mismo gesto: 100, 40 y 20 no
  revelan; 10, 5 y 1 sí. El roce lateral pegado al borde no dispara con ninguno,
  así que el falso positivo que justificaba el umbral alto no existe. Default 5,
  configurable como `reveal-threshold`. En el sandbox el `enable()` completo
  imprime `umbral 5px/1000ms`.
- **El clic en el icono cicla, y empieza por la ventana de tu monitor.** Lo que
  había devolvía la primera del orden de apilado, sin relación con dónde estás
  mirando: con dos terminales, una por monitor, clickeás en la pantalla izquierda
  y aparece la de la derecha. Verificado: cinco clics alternando 0→1→0→1→0 con el
  foco siguiendo, y el orden invirtiéndose al mover el puntero al otro monitor.
  **El cursor no salta**: medido antes y después en siete clics y dos
  `activate()` directos, no se movió ni una vez. Quien mueve ventanas entre
  monitores es PaperWM, que se las lleva a su monitor al restaurarlas y le gana a
  `move_to_monitor()`.
- **No hay fantasma al minimizar.** El guard vive en código propio
  (`mactahoe-tweaks/ghostGuard.js`), no en el parche de PaperWM: ese parche está
  bien puesto pero **no llega a correr** para esas ventanas. Regla única: una
  ventana minimizada no se dibuja.
- **La transparencia de las ventanas tiene interruptor.** Toggle "Transparencia"
  en el hub (`blurControl.js`): el cuerpo prende y apaga el componente
  `applications` de Blur my Shell, el menú le saca la transparencia a la ventana
  enfocada o se la devuelve. Atajos `Super+B` y `Super+Shift+B`. Verificado: con
  la opción prendida Blur my Shell tiene 3 ventanas con efecto, apagada 0, y el
  botón aparece en el hub con su subtítulo — comprobado en píxeles.
- **Blur my Shell ya no acumula ventanas.** Bug de esa extensión:
  `update_all_windows()` dejaba la entrada en `meta_window_map` y volvía a
  registrar todo con un id nuevo (medido: 5 → 10 → 15, la misma ventana 12
  veces). Parcheado en
  `setup/patches/blur-my-shell-mapa-de-ventanas-que-crece.patch`; queda en 3
  entradas para 3 ventanas, estable en seis ciclos.

## Abierto

- **El snap de Steam corre un Mesa más viejo que el sistema, y eso colgó la GPU.**
  No usa el Mesa del sistema: lo recibe por content-snap desde
  `gaming-graphics-core24`. Al momento del cuelgue del 31/08 el snap traía **25.2.2**
  (canal `kisak-fresh/stable`, congelado desde diciembre de 2025) contra **26.0.8**
  del sistema, y un shader compilado por ese RADV viejo hizo page fault
  (`UTCL2 client ID: SQC (data)`, `PERMISSION_FAULTS`) → ring timeout → reset de
  dispositivo → Xwayland caído. Mitigado pasando el canal a
  `kisak-turtle/candidate` (**25.3.6**) y borrando el shader cache de CS2, pero
  **ningún canal del snap llega al 26.0.8 del sistema**: la brecha se reabre sola con
  cada actualización de Ubuntu. La salida de fondo es Steam por `.deb` o Flatpak, que
  toman el Mesa del sistema; cuesta migrar 67 GB de biblioteca. Relato y evidencia en
  `ESTADO-historial.md`.

- **Ruido en el journal**, sin síntoma visible, sin mirar: PaperWM
  (`Meta.BackgroundActor ... already disposed`, en `utils.js:567` / `grab.js:441`)
  y `macos-dock` (`lib/iconManager.js:474` ← `:374` ← `:263`, `dockManager.js:390-394`,
  `_applyDockPosition()` `:497`).
- **`auto-hide` aparece en `false` al arrancar la sesión** aunque se lo haya
  dejado en `true`. No se investigó si lo pisa el reinicio o el arranque de la
  extensión. Cuesta una sesión: sin auto-hide no hay `DockVisibility`, así que
  medir el revelado da cero y parece un bug del revelado.
- **GNOME desactiva `macos-dock` al cambiarle los archivos** (queda «Activado:
  sí, Estado: INACTIVE») y ni `gnome-extensions enable` ni `enableExtension()`
  la reviven; lo que sí funciona es `stateObj.enable()` a mano por Eval. Pero
  las barreras de la instancia anterior quedan vivas y se comen los eventos:
  para medir el revelado después de tocar archivos hace falta login o sandbox.
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
