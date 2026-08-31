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

**El RGB es un frente pendiente, con el hardware ya identificado.** El objetivo,
en palabras del usuario: prender, apagar y cambiar el color de todo desde un solo
lado. Lo que hay, verificado en la máquina:

| Qué | Cómo se llega |
|---|---|
| Placa **MSI X670E GAMING PLUS WIFI (MS-7E16)**, Mystic Light | HID por USB `0db0:0076` → OpenRGB |
| GPU **ASUS** Navi 21 (subsistema `1043:04fa`) — Aura | SMBus → OpenRGB, pide `i2c-dev` cargado |
| Dos tiras **`LEDDMX-03-885E`** (`AC:C2:01:7C:88:5E`) y **`-815E`** (`AC:C2:01:DC:81:5E`) | BLE, ya Paired+Trusted en el adaptador `84:9E:56:03:57:D0`. El USB sólo les da corriente |

Las tiras son familia **ELK-BLEDOM**: servicio `0000ffe0`, se escribe en la
característica `ffe1`, color `7e 00 05 03 RR GG BB 00 ef` y on/off
`7e 00 04 f0|00 …ef`. Hay variantes de firmware: **el primer paso es confirmar
esos paquetes contra una tira**, no darlos por buenos.

Hoy no hay nada instalado: `openrgb` no está (candidato de apt `0.9+git20251009`,
y hay Flatpak `org.openrgb.OpenRGB`), `bleak` tampoco, y `i2c-dev` **no hace falta cargarlo**: en el kernel 7.0 de Ubuntu 26.04 viene
compilado adentro, no como módulo — por eso no aparece en `lsmod` pero sí
existen los 21 nodos `/dev/i2c-*`. El bus `i2c_piix4` también está. Forma pensada: CLI `rgbctl` en venv
propio bajo `setup/bin/rgb/` (nunca `sudo pip`), empaquetado como
`setup/modules/70-rgb.sh` con su entrada en `install.sh`, `undo.sh` y `doctor.sh`,
y un `QuickMenuToggle` en el hub que lo llame con `Gio.Subprocess` **asíncrono**
—una llamada BLE bloqueante adentro del shell congela el escritorio un segundo.
Aviso que vale una sesión: escribir por SMBus a los módulos de RAM puede colgar el
bus; si la detección no ve la RAM se prueba `acpi_enforce_resources=lax` y no se
fuerza más.

Antes de tocar nada del dock: `gsettings ... auto-hide` tiene que estar en `true`
(ver «Abierto»).

```bash
bash setup/gshell.sh check          # unsafe mode: Alt+F2 → lg → global.context.unsafe_mode = true
bash setup/gshell.sh push bottom
bash setup/gshell.sh find macos-dock-root
```

## Qué funciona, verificado

- **Steam salió del snap y tiene carpeta propia.** El snap corría un Mesa 25.2.2
  (content-snap `gaming-graphics-core24`) contra el 26.0.8 del sistema, y un shader
  compilado por ese RADV viejo colgó la GPU el 31/08 (`UTCL2 client ID: SQC (data)`
  → ring timeout → reset → Xwayland caído). Ningún canal del snap llega al Mesa del
  sistema, así que la brecha se reabría con cada actualización de Ubuntu. Ahora es
  `steam-installer` de multiverse (el `.deb` de Valve, i386 habilitado), instalado
  entero en **`~/Juegos/Steam`** con `~/.steam/{steam,root}` y `~/.local/share/Steam`
  apuntando ahí. Los 83 GB se copiaron con `rsync` (salida 0), no se re-descargaron,
  y las rutas de `libraryfolders.vdf` quedaron reescritas. Verificado: el cliente
  arranca desde la ruta nueva, con `fsync: up and running` y Fossilize leyendo
  `~/Juegos/Steam/shader_cache_temp_dir_d3d12_64`. Falta el login y abrir un juego.
- **Windows se achicó y Linux ganó 462 GiB.** El NTFS pasó de 1162 a **700 GiB**
  (usa 498, le quedan 203 libres) con `ntfsresize` — **cero reubicaciones**, y la
  partición se recreó con `sgdisk` conservando sector de inicio, tipo y PARTUUID.
  El espacio liberado es la partición nueva `nvme0n1p6`, ext4, montada en
  `~/Juegos` por UUID en `fstab` (454 GiB útiles). Verificado después: `ntfsfix`
  da «alternate boot sector OK» y Windows monta con sus 498 GB intactos. Respaldo
  de la tabla GPT en `~/.setup-ubuntu-backups/gpt-nvme0n1-20260831.bak`, y de
  `/etc/fstab` en `/etc/fstab.bak-20260831`. **Windows va a correr `chkdsk` solo en
  su próximo arranque: es lo normal después de un resize, no es que se haya roto.**
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
