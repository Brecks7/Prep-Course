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

El siguiente frente de gaming son los **327 GB que quedaron del lado de Windows**
(ver «Abierto»). Steam y CS2 ya están cerrados como tema: ver «Qué funciona».

Si alguna vez vuelve a colgar la GPU, la escalada está en `ESTADO-historial.md`
(sesión del 31/08): `RADV_DEBUG=llvm`, y para capturar en vez de colgar
`RADV_DEBUG=hang MESA_VK_ABORT_ON_DEVICE_LOSS=1 %command%`.

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

**El RGB quedó unificado salvo las tiras.** `rgbctl` (en el PATH por symlink) es
el único lado: aplica color, `on` y `off` a los **dos módulos de RAM**, la **GPU** y
los headers de la placa, y guarda lo último para que `rgb-restore.service` lo
reponga al iniciar sesión. Verificado a ojo el 01/09 y **en dos colores distintos**:
la GPU en azul, y **la RAM dejó el arcoíris** — primero azul, después rojo. Ese
frente está cerrado.

**Lo que no salió son las dos tiras BLE, y el bloqueo ya no es la conexión.** Borrar
el bond las destrabó: ahora conectan, resuelven GATT y **aceptan las escrituras con
ACK**. Lo que falta es el **protocolo**: se probaron **nueve formatos** conocidos y
ninguno las movió. El camino que cierra el tema es capturar los bytes que manda la
app del celular («LED Lamp», Android, registro HCI + informe de errores) — detalle
en `ESTADO-historial.md`, «RGB — las tiras BLE no resuelven GATT». Dato del usuario
para cuando se decodifiquen: la app tiene el orden de color en **GRB**, no RGB.

**El botón del hub («Luces») pide un login para aparecer.** `rgbControl.js` está
escrito, desplegado y con su schema compilado, pero GNOME no recarga la extensión
en vivo sin unsafe mode. Al volver a entrar: que aparezca el toggle, que prenda y
apague, y **que el escritorio no se congele** al usarlo (las llamadas son
asíncronas y serializadas justamente por eso).

Antes de tocar nada del dock: `gsettings ... auto-hide` tiene que estar en `true`
(ver «Abierto»).

```bash
bash setup/gshell.sh check          # unsafe mode: Alt+F2 → lg → global.context.unsafe_mode = true
bash setup/gshell.sh push bottom
bash setup/gshell.sh find macos-dock-root
```

## Qué funciona, verificado

- **El arranque te deja elegir el sistema.** No era GRUB —ya estaba bien— sino el
  firmware: `BootOrder` tenía a Windows primero, así que GRUB nunca corría. Ahora
  `0002,0000` (Ubuntu primero) con `efibootmgr`, `GRUB_TIMEOUT` en 10 y el menú
  regenerado: quedan `Ubuntu`, `Windows Boot Manager (on /dev/nvme0n1p1)` y
  `UEFI Firmware Settings` —esta última es el atajo para ir a tocar el SMT—.
  Respaldos del `BootOrder` y del `/etc/default/grub` previos en
  `~/.setup-ubuntu-backups/`. Se revierte con `sudo efibootmgr -o 0000,0002`.
- **El RGB se maneja desde un solo lado.** `setup/bin/rgb/rgbctl`, enlazado en
  `~/.local/bin`: `rgbctl ff0000 | on | off | list | status | restore`. Resuelve los
  dispositivos **por nombre** y no por índice fijo, así que no se rompe si cambia el
  orden. **La trampa del SMBus con la RAM no se cumplió**: se le escribió a los dos
  módulos de a uno, y el bus siguió contestando los 4 dispositivos con 0 mensajes de
  `i2c` en el kernel. Empaquetado en `setup/modules/80-rgb.sh` con su `--rgb` en
  `install.sh`, su reverso en `undo.sh` y su chequeo en `doctor.sh` (probado: reporta
  los 4 dispositivos y el último color).
- **La tableta XP-Pen Deco 01 no necesita nada.** El driver `hid-uclogic` viene en
  el kernel 7.0 y declara `256C:006D` y `256C:006E`, que son el Deco 01 y su V2.
  DIGImend ya no hace falta. Queda probar lápiz, presión y botones al enchufarla.
- **Steam salió del snap, y CS2 abre sin colgar la GPU.** El snap corría Mesa
  25.2.2 contra el 26.0.8 del sistema, y ese RADV viejo colgó la GPU el 31/08.
  Ahora es `steam-installer` de multiverse (el `.deb` de Valve), instalado entero
  en **`~/Juegos/Steam`**, con `~/.steam/{steam,root}` y `~/.local/share/Steam`
  apuntando ahí. Los 83 GB se copiaron con `rsync`, no se re-descargaron.
  Verificado el 01/09: el cliente entra solo por `AutoLogin` (`Logged On` 00:19:54)
  y **CS2 arranca** — `shadercache/730/radv_builtin_shaders` con 52 entradas, o sea
  RADV compilando de verdad, y **165 s de `journalctl -kf` sin un solo evento de
  `amdgpu`**, con 0 «gpu reset» en todo el boot.
- **El snap de Steam se borró: 86 GB de vuelta.** Cumplida la condición de que un
  juego abriera desde el nativo, `snap remove --purge steam` (el `--purge` evita
  que snapd guarde un snapshot del mismo tamaño). `/` pasó de 171 GB usados a
  **85 GB**, con 611 GB libres. Antes de borrar se comprobó que ningún symlink del
  nativo apuntaba al snap: los tres van a `~/Juegos/Steam`.
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
  gnome-shell, y `npm test` con 129 tests en 7 suites. Las cuatro memorias del
  proyecto se consolidaron en la key `-home-son-Documentos-Proyectos-Configurador`
  (venían partidas en dos, con dos huérfanas) y cargan al arrancar. En las keys
  viejas quedaron copias inertes: si alguna vez se edita una memoria, la que vale
  es la de la key nueva.
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
