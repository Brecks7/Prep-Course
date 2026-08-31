# Estado de la máquina — 31 de agosto de 2026

GNOME 50 sobre Ubuntu 26.04, Wayland. El `CLAUDE.md` dice **qué es** el proyecto;
acá va **en qué anda** la máquina hoy. El relato largo de cada sesión —síntomas,
callejones sin salida, evidencia— está en `ESTADO-historial.md`, que **no hace
falta leer** salvo que algo se rompa.

Este archivo es sobrescritura, no bitácora: si pasa de ~200 líneas, hay un relato
adentro que debía ser una decisión de una línea. (El techo era 150 cuando sólo
cubría el escritorio; el 31/08 se le sumaron discos, gaming, CPU y seguridad.)

Regla que le dio origen: **todo cambio que necesite cerrar sesión se escribe antes
de cerrarla.** Si no, la sesión siguiente arranca sin contexto y repite el
diagnóstico desde cero — pasó tres veces con el mismo bug.

## Dónde retomar

**La prueba pendiente es iniciar sesión en Steam y abrir CS2.** Steam nativo está
corriendo desde `~/Juegos/Steam` y quedó en la pantalla de login — eso lo hace la
persona. Con la sesión iniciada, abrir CS2 con `journalctl -kf | grep amdgpu` en
otra terminal. La primera partida tarda más: el shader cache se regenera.

La causa del cuelgue del 31/08 ya no está: era el Mesa 25.2.2 del snap contra el
26.0.8 del sistema, y ahora Steam es el `.deb` nativo, que usa el del sistema. Si
aun así cuelga, la escalada está en `ESTADO-historial.md` (sesión del 31/08):
`RADV_DEBUG=llvm`. Y para capturar en vez de colgar:
`RADV_DEBUG=hang MESA_VK_ABORT_ON_DEVICE_LOSS=1 %command%`.

**No borrar el snap de Steam hasta que un juego abra.** Los 83 GB del snap siguen
en `~/snap/steam/` y son la única copia de respaldo de la biblioteca. Cuando CS2
arranque desde el nativo: `sudo snap remove steam` libera esos 83 GB del disco raíz.

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

**El RGB es un frente pendiente, con el hardware ya identificado y verificado.**
Objetivo: prender, apagar y cambiar el color de todo desde un solo lado. Placa MSI
X670E (USB HID `0db0:0076`), GPU ASUS con Aura (SMBus, `/dev/i2c-*` ya existe) y
dos tiras ELK-BLEDOM por BLE, ya emparejadas. Nada instalado todavía. El detalle
—protocolo de las tiras, direcciones, diseño del módulo y la trampa del SMBus con
la RAM— está en `ESTADO-historial.md`, «RGB — hardware identificado».

Antes de tocar nada del dock: `gsettings ... auto-hide` tiene que estar en `true`
(ver «Abierto»).

```bash
bash setup/gshell.sh check          # unsafe mode: Alt+F2 → lg → global.context.unsafe_mode = true
bash setup/gshell.sh push bottom
bash setup/gshell.sh find macos-dock-root
```

## Qué funciona, verificado

- **Steam salió del snap y tiene carpeta propia.** El snap corría Mesa 25.2.2
  contra el 26.0.8 del sistema, y ese RADV viejo colgó la GPU el 31/08. Ahora es
  `steam-installer` de multiverse (el `.deb` de Valve), instalado entero en
  **`~/Juegos/Steam`**, con `~/.steam/{steam,root}` y `~/.local/share/Steam`
  apuntando ahí. Los 83 GB se copiaron con `rsync`, no se re-descargaron. Verificado
  que el cliente arranca desde la ruta nueva; falta el login y abrir un juego.
- **Windows se achicó y Linux ganó 462 GiB.** El NTFS pasó de 1162 a **700 GiB**
  (usa 498) con `ntfsresize` —cero reubicaciones— y la partición se recreó con
  `sgdisk` conservando sector de inicio, tipo y PARTUUID. Lo liberado es
  `nvme0n1p6`, ext4, montada en `~/Juegos` por UUID. Verificado después: `ntfsfix`
  da «alternate boot sector OK» y Windows monta intacto. Respaldos de la GPT y de
  `fstab` en `~/.setup-ubuntu-backups/` y `/etc/fstab.bak-20260831`.
  **Windows va a correr `chkdsk` solo en su próximo arranque: es lo normal después
  de un resize, no es que se haya roto.**
- **El firewall está activo.** `ufw` estaba **instalado pero inactivo**, con un
  `next-server` (Next.js) escuchando en `*:3000`, o sea alcanzable desde toda la
  red local. Ahora: `deny incoming` / `allow outgoing`, con `1714:1764` tcp+udp
  abierto para GSConnect, que es lo único que necesita entrante.
- **La home dejó de estar derramada.** Se fueron: el volcado de Xwayland del
  cuelgue (`core.3902`, 146 MB), el prefijo `~/.wine` (1,2 GB — sólo tenía un
  Lightshot abandonado del 26/08, reemplazado por Flameshot) con su
  `setup-lightshot.exe`, las capturas de `shot.sh` (289 MB), la caché de apt
  (549 MB), nueve revisiones viejas de snaps (`refresh.retain=2`) y un
  `Flameshot.desktop.bak` duplicado en autostart. El backup `~/.claude.bak-*` se
  comprimió a 7,6 MB en `~/.setup-ubuntu-backups/`. La home quedó con sus carpetas
  estándar más `Juegos` y `snap`, nada suelto.
- **El indexador ya no muerde los juegos.** `tracker3` indexaba `$HOME` entero, o
  sea que iba a recorrer los 85 GB de Steam. Excluidos `~/Juegos`, `~/snap`,
  `~/.cache`, `~/.nvm` y `~/.npm`.
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
- **El dock se revela, se esconde y no deriva.** Tres bugs, los tres cerrados con
  medición: la barrera mal puesta más `_isAnimating` colgado (diez ciclos, Y de
  reposo en 987 exacto en las diez), los `enter/leave` de la raíz que eran código
  muerto (`reactive: false`: 0 cruces en la raíz contra 4 en el icon box), y el
  umbral de revelado de 100 px, que era la causa del «se revela una vez y después
  no» — mutter cuenta cuánto te *habrías pasado de largo*, no cuánto recorriste.
  Default 5, configurable como `reveal-threshold`. Causas y barrido de valores en
  `setup/README.md` y en `ESTADO-historial.md`.
- **El clic en el icono cicla, y empieza por la ventana de tu monitor.** Antes
  devolvía la primera del orden de apilado, sin relación con dónde estás mirando.
  Verificado: cinco clics alternando 0→1→0→1→0, el orden invirtiéndose al mover el
  puntero al otro monitor, y el cursor sin saltar ni una vez en siete clics. Quien
  mueve ventanas entre monitores es PaperWM, no el dock.
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

- **El SMT del 9800X3D está apagado en la BIOS: 8 hilos en vez de 16.**
  `/sys/devices/system/cpu/smt/control` dice `notsupported` y `lscpu -e` da un core
  por CPU — el firmware directamente esconde los hermanos. No fue decisión del
  usuario; **quiere los 16**, y es un cambio de BIOS que hace la persona
  (MSI X670E: Del → Advanced → CPU Features → **SMT Control = Auto**). Al volver,
  verificar con `nproc` (debe dar 16) y `cat /sys/devices/system/cpu/smt/active`
  (debe dar 1).
- **Quedan 327 GB de biblioteca de Steam del lado de Windows**, en
  `Program Files (x86)/Steam` (más 39 GB de Riot). No conviene usarlos desde NTFS:
  Proton y los permisos de ntfs-3g se pelean. La migración barata es copiar las
  carpetas de `steamapps/common` a `~/Juegos/Steam/steamapps/common` y darle
  «verificar integridad» en Steam — descarga sólo lo que falta en vez de los 327 GB
  enteros. Hay 370 GB libres en `~/Juegos`, así que entra.
- **Windows sigue en 700 GiB y se puede achicar más** cuando termine la migración
  (mínimo real hoy: ~497 GiB). Falta definir qué programas necesita Nano.
- **Cinco actualizaciones quedan retenidas** (`nautilus`, `software-properties`):
  son actualizaciones por fases de Ubuntu, se destraban solas. Las otras 10, entre
  ellas 5 de seguridad, ya están aplicadas.
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

## Cómo mirar el escritorio

Las herramientas para no trabajar a ciegas —`gshell.sh`, `shot.sh`,
`shell-sandbox.sh`, `watch-shell.sh`— y **las trampas que cuestan una sesión si no
se saben** están en `setup/README.md`, sección «Cómo mirar el escritorio sin
trabajar a ciegas»: que `Eval` sólo responde con unsafe mode y que ahí adentro no
se puede importar `Main`, que el árbol de actores dice qué *cree* el shell y no qué
se dibujó, y que una extensión sí se recarga en vivo con `gshell.sh patch` aunque
`ReloadExtension` esté muerto.
