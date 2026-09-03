# Estado de la máquina — 1 de septiembre de 2026

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

**El push quedó resuelto el 3/09**: la rama
`claude/linux-ubuntu-windows-migration-whc0li` está en `origin`, a cero. Se
destrabó con una clave SSH (`~/.ssh/id_ed25519`, ed25519 sin passphrase, cargada
en la cuenta `Brecks7`) y el remoto cambiado a `git@github.com:Brecks7/Prep-Course.git`.
`~/.ssh/known_hosts` tiene la clave ed25519 de github.com, verificada contra el
fingerprint publicado (`SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`) —
sin eso el primer push se cuelga preguntándolo. Comprobar con
`ssh -T git@github.com`, que contesta «Hi Brecks7!». Sigue sin haber `gh` ni
`credential.helper`, y no hacen falta.

**El dock está cerrado entero y verificado en la sesión viva**: magnificación,
nitidez del arte, reposo, revelado y ciclado del clic — ver «Qué funciona». No
queda nada pendiente de este tema.

Revertir todo el estilo: `~/.setup-ubuntu-backups/dock-antes-20260902.sh`.

**El revelado y el ciclado quedaron medidos en la sesión viva, sin login** — y
la causa por la que antes «daba cero» **no era** la barrera huérfana que decía
este archivo. Los choques sí llegaban (16 hits contados sobre el `Meta.Barrier`);
lo que no pasaba era la acumulación de presión, porque **la pantalla estaba
bloqueada**: con el bloqueo, `Main.actionMode` vale 8 (`UNLOCK_SCREEN`) y la
barrera del dock pide 3 (`NORMAL|OVERVIEW`), así que `PressureBarrier` descarta
cada evento en `!(this._actionMode & Main.actionMode)` antes de sumar nada. Desde
afuera se ve idéntico a un dock roto. Por eso ahora existe `gshell.sh sesion`:
**se corre primero, siempre**, antes de culpar a nada del escritorio.

**El RGB está cerrado entero, tiras incluidas, y el restore al arrancar también**
— ver «Qué funciona». No queda nada pendiente de este tema.

Para medir el revelado hacen falta dos cosas, en este orden: que `gshell.sh
sesion` diga **NORMAL** (si no, no dispara ninguna barrera de presión y la medición
miente), y `auto-hide` en `true` — sin eso no hay `DockVisibility`. Queda en
`false`, que es como lo usa el escritorio; se prende sólo para medir.

```bash
bash setup/gshell.sh check          # unsafe mode: Alt+F2 → lg → global.context.unsafe_mode = true
bash setup/gshell.sh sesion         # ¿NORMAL? si no, lo que midas no vale
bash setup/gshell.sh push bottom
bash setup/gshell.sh click 837 1037              # clic de verdad, con timestamp
bash setup/gshell.sh find macos-dock-root
bash setup/gshell.sh pointer 888 1030            # el puntero sobre un icono
bash setup/shell-sandbox.sh --shot /tmp/d.png --hover 3 macos-dock@son.local
```

`click` existe porque llamar al handler a mano **no** alcanza: `activate()` sin
timestamp de interacción la descarta mutter por prevención de robo de foco, y el
ciclado avanza su índice igual, así que parece que el clic no hace nada.

`--hover N` fotografía la magnificación en el sandbox: en headless no hay
puntero, así que el probe llama a `applyAt()`, que deja el estado final sin
suavizado. Admite decimales (3.5 es justo entre dos iconos).

## Qué funciona, verificado

- **El arranque te deja elegir el sistema.** No era GRUB —ya estaba bien— sino el
  firmware: `BootOrder` tenía a Windows primero, así que GRUB nunca corría. Ahora
  `0002,0000` (Ubuntu primero) con `efibootmgr`, `GRUB_TIMEOUT` en 10 y el menú
  regenerado: quedan `Ubuntu`, `Windows Boot Manager (on /dev/nvme0n1p1)` y
  `UEFI Firmware Settings` —esta última es el atajo para ir a tocar el SMT—.
  Respaldos del `BootOrder` y del `/etc/default/grub` previos en
  `~/.setup-ubuntu-backups/`. Se revierte con `sudo efibootmgr -o 0000,0002`.
- **El RGB se maneja desde un solo lado, tiras BLE incluidas.**
  `setup/bin/rgb/rgbctl`, enlazado en `~/.local/bin`:
  `rgbctl ff0000 | on | off | list | status | restore`, más `--sin-ram` y
  `--sin-tiras`. Habla dos mundos: **OpenRGB** (dos módulos de RAM, GPU, headers de
  la placa) y **BlueZ** (las dos tiras `LEDDMX-03-*`). Todo se resuelve **por
  nombre/UUID** y no por índice ni por handle fijo, así que no se rompe si cambia el
  orden ni entre arranques. **La trampa del SMBus con la RAM no se cumplió**: se le
  escribió a los dos módulos de a uno, y el bus siguió contestando los 4
  dispositivos con 0 mensajes de `i2c` en el kernel. Empaquetado en
  `setup/modules/80-rgb.sh` con su `--rgb` en `install.sh`, su reverso en `undo.sh`
  y su chequeo en `doctor.sh` (probado: 4 dispositivos, 2 tiras conectadas y
  trusted, último color, 0 críticos).
- **Las dos tiras BLE responden.** Protocolo propio, familia `7b…bf` sobre la
  característica `0000ffe1`, **write sin respuesta y con pausa entre tramas**; color
  en **RGB directo**, no GRB. Ni handshake ni CCCD: lo que domina el snoop del
  celular es ruido. Las tramas exactas están en `rgbctl` y el porqué en
  `ESTADO-historial.md`, «RGB — las tiras BLE, resueltas». Verificado a ojo el 01/09
  en cinco colores y apagado, en las dos.
- **`rgb-restore.service` repone las tiras aunque el arranque sea el peor caso.**
  Verificado el 02/09 simulando un arranque virgen **más duro que el real**: se
  sacaron las dos tiras de la caché de BlueZ (`bluetoothctl remove`, que además les
  quita el `trusted`) **y** se bloqueó el Bluetooth por `rfkill`, los dos factores a
  la vez. `rgbctl restore` salió **rc=0 con las dos tiras aplicadas en 32,9 s**:
  destrabó el `rfkill` solo, escaneó, encontró las tiras y les escribió. El arranque
  real es más benigno —BlueZ persiste los dispositivos en `/var/lib/bluetooth`, así
  que la caché **no** arranca vacía y el `trusted` sobrevive—, y ahí la corrida son
  ~17 s. El `sleep 5` del `ExecStartPre` nunca fue el riesgo: es un retardo, no un
  plazo, y `rgbctl` espera al adaptador por su cuenta.

- **El botón «Luces» del hub prende, apaga y no congela el escritorio.** Verificado
  el 01/09: el toggle está en Quick Settings (medido en píxeles, 196×64 en
  1666,432), el ciclo arrastra GPU, las dos RAM y las dos tiras en ese orden, y
  durante los ~17 s que tarda `rgbctl` el shell contesta Eval en **10 ms**.
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
- **El dock quedó igual al de macOS, medido contra la referencia.** Se rehízo el
  02/09 contra `~/Descargas/DOCK.png`, comparando números y no impresiones: las
  proporciones viven en `lib/metrics.js` (arte 0.60 del alto del dock, hueco 0.27
  del icono, margen 0.23, punto 0.13) y las consumen los tres lugares que antes
  tenían números sueltos. Verificado en el sandbox con `--shot`, con `icon-size 40`:
  dock **511×66**, padding lateral 9 y 9, paso entre iconos 51, separador de 34
  centrado con 23 de aire a cada lado, puntos de **⌀5 en (148,148,148)** contra
  ⌀8 en (141,141,141) de la referencia, y la curva de la esquina normalizada en
  0.23 contra 0.24. Suma papelera con separador fijo (icono lleno/vacío por
  monitor de `trash:///`, «Vaciar» en el menú derecho) y globo de notificaciones.
  **Dos límites de St que costaron una corrida cada uno**: con `border-radius`
  los cuatro bordes se pintan del mismo color, así que el relieve de dos tonos
  del dock de macOS no se puede (el borde va parejo al 16% y quien levanta la
  píldora es el `box-shadow`, que sí se dibuja y el CornerEffect no se come); y
  el radio efectivo no es el número de la gsetting: 21 da la curva de la
  referencia, 18 se queda corto. **El aire vertical se rebalanceó el 02/09**
  después de que el usuario viera los iconos pegados al techo: el arte caía a 15
  del techo y 11 del piso porque `padTop`/`padBottom` se habían calculado sobre
  el actor, y el arte se pinta 2 px más abajo (el St.Icon se centra en lo que le
  deja el iconWrap). Ahora 0.30 y 0.175 del icono dan **14 arriba y 13 abajo**
  sobre un dock de 67, con el arte en 0.597 del alto. De paso: el hueco de los
  puntos ahora se reserva siempre —antes el `indicatorBox` se ocultaba y el arte
  de las apps cerradas bajaba unos píxeles, así que en la misma fila los iconos
  no estaban a la misma altura—.
- **La magnificación es la de macOS y el arte dejó de verse pixelado** (02/09,
  medido en la sesión viva y en el sandbox). La ola sigue al puntero en vez de
  saltar de icono en icono, sólo se activa con el cursor sobre el dock —activa a
  16 px por encima, apagada a 46— y los iconos se apartan mientras el fondo se
  ensancha (511 → 562 px). Los ajustes son **escala 1.45, alcance 130,
  framerate 120**: 1.3 casi no se nota y 1.6 agranda medio dock a la vez. La
  nitidez salió de hacer funcionar `icon-quality`, que estaba en el schema pero
  el `IconManager` ignoraba: el arte se pide a `icon-size × calidad` y se dibuja
  a `icon-size`, así que siempre se reduce. **+2,9× de detalle en el icono
  magnificado y +4,2× en reposo** (varianza del laplaciano). De paso, los nueve
  artes de la fila quedaron a la misma altura —botón de aplicaciones y papelera
  incluidos— y `metrics.js` se rebalanceó a padTop/padBottom 14 y 5 sin cambiar
  el alto del dock. Los cinco síntomas, con números, en `ESTADO-historial.md`.
- **El dock se revela, se esconde y no deriva.** Tres bugs, los tres cerrados con
  medición: la barrera mal puesta más `_isAnimating` colgado (diez ciclos, Y de
  reposo en 987 exacto en las diez), los `enter/leave` de la raíz que eran código
  muerto (`reactive: false`: 0 cruces en la raíz contra 4 en el icon box), y el
  umbral de revelado de 100 px, que era la causa del «se revela una vez y después
  no» — mutter cuenta cuánto te *habrías pasado de largo*, no cuánto recorriste.
  Default 5, configurable como `reveal-threshold`. Causas y barrido de valores en
  `setup/README.md` y en `ESTADO-historial.md`. **Medido en la sesión viva el
  3/09: cinco de cinco.** Cada ciclo revela, vuelve a esconderse solo, y la
  barrera se destruye al mostrar y se recrea al esconder.
- **El clic en el icono cicla, y empieza por la ventana de tu monitor.** Antes
  devolvía la primera del orden de apilado, sin relación con dónde estás mirando.
  Verificado: cinco clics alternando 0→1→0→1→0, el orden invirtiéndose al mover el
  puntero al otro monitor. Re-verificado el 3/09 con clics de verdad: seis clics
  recorren las tres ventanas de Ptyxis en orden y vuelven a empezar.
  **Corrección:** el cursor sí salta, y no es culpa del dock — al enfocar una
  ventana de otro monitor lo mueve PaperWM, sin condición ni ajuste que lo apague
  (`tiling.js:4665`, «if window is on another monitor then warp pointer there»).
  La medición vieja no lo vio porque el ciclo no cruzaba de monitor.
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

- **El subtítulo del toggle «Luces» miente si se usó `rgbctl` desde la terminal.**
  El comentario de cabecera de `rgbControl.js` promete que la gsetting y
  `rgbctl status` se sincronizan al abrir el menú, pero `_sync()` sólo lee la
  gsetting. Se ve al aplicar magenta por CLI y encontrar el botón diciendo «Azul».
  Cosmético: el color aplicado es el correcto, lo que está desfasado es la etiqueta.
- **La proporción arte/dock es 0.54 y la referencia tiene 0.60**, porque los
  iconos de MacTahoe dejan ~10% de margen adentro de su cuadro y los de macOS
  van a sangre. Se compensaría subiendo `icon-size` a 44 o recortando `padTop`
  en `metrics.js`; no se tocó porque los 40 px son elección del usuario.
- **El globo de notificaciones no se probó contra una app real.** `lib/badges.js`
  ata una fuente de la bandeja a una app por tres caminos (la `Shell.App` que
  publica, el id de escritorio, el título) y si ninguno pega la ignora, así que
  el riesgo es que no aparezca nunca, no que aparezca en el icono equivocado.
  Se comprueba dejando notificaciones sin leer de Discord.
- **La papelera no se magnifica distinto que el resto**: crece como un icono más,
  igual que el botón de aplicaciones. En macOS también. No es un pendiente, es
  para que nadie lo "arregle".
- **Brillo y velocidad de las tiras siguen sin identificar.** El análogo `7b` no se
  buscó; el camino es volver al `btsnoop_hci.log` del bugreport.
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
  y `macos-dock` (`lib/iconManager.js`, `dockManager.js` `_applyDockPosition()`).
  Se vuelve a ver en cada `enable()`; un barrido completo del dock con el puntero
  (11 posiciones a lo ancho, 7 a lo alto) no agregó ni un error.
- **`auto-hide` aparece en `false` al arrancar la sesión** aunque se lo haya
  dejado en `true`. No se investigó si lo pisa el reinicio o el arranque de la
  extensión. Sin auto-hide no hay `DockVisibility` y el revelado no se puede medir.
- **`macos-dock` aparece «Activado: sí, Estado: INACTIVE»** y ni
  `gnome-extensions enable` ni `enableExtension()` la reviven; lo que funciona es
  `stateObj.enable()` a mano por Eval. Antes esto se le atribuía a «cambiarle los
  archivos»; el 3/09 se la encontró así **con la pantalla bloqueada**, así que la
  causa está sin confirmar. Lo que sí quedó medido: mezclar `gnome-extensions
  enable` con `stateObj.enable()` deja `extensionManager` y el `stateObj`
  discrepando, y de ahí salen **dos `macos-dock-root` en el stage** — el dock
  duplicado del que salían las «barreras huérfanas». Se detecta contando raíces y
  se limpia destruyendo la que no sea `_dockManager._container`.
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
