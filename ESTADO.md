# Estado del escritorio — bitácora viva

Este archivo es la memoria de trabajo del escritorio (GNOME 50 sobre Ubuntu
26.04). El `CLAUDE.md` dice **qué es** el proyecto y cómo se corre; acá va **en
qué anda** cada cosa, qué se probó y con qué evidencia.

Regla que dio origen a este archivo: cada cambio del escritorio que necesite
cerrar sesión se escribe **antes** de cerrarla. Si no, la sesión siguiente
arranca sin contexto y repite el diagnóstico desde cero — eso pasó tres veces
seguidas con el mismo bug.

---

## Sesión del 30 de agosto de 2026 (madrugada)

### 1. El fantasma al minimizar — causa encontrada, fix aplicado

**Síntoma**: al minimizar una ventana queda una copia dibujada en pantalla. Se
la reconoce porque los tres botones del semáforo están **grises** en vez de
rojo/amarillo/verde: es la ventana sin foco, no la ventana viva.

**Evidencia**: `~/.cache/setup-shots/fantasma/`. `f07.png` es el escritorio
limpio con la ventana ya minimizada; `f08.png` es la copia redibujada, con los
botones en RGB `(80,86,100)` — medido, no mirado.

**Por qué los dos parches anteriores no alcanzaron.** La cadena real:

1. `tiling.js:4740 minimizeHandler` → `Scratch.makeScratch()` con la ventana ya
   `minimized`.
2. `scratch.js:141` (rama minimizada) conecta `effects-completed` y hace
   `move_resize_frame()` **sobre una ventana minimizada**.
3. Ese resize hace que el cliente commitee un buffer nuevo y mutter **vuelva a
   mostrar el actor** → se emite `WindowActor::show`.
4. `tiling.js:3549` lo intercepta con `showHandler`, que sólo escondía el actor
   si `isWindowAnimating()`. Y esa función se define como "el clone está
   visible" — pero el parche anterior (`scratch-clone-fantasma`) dejó el clone
   oculto, así que ahora da **false**. Nadie escondía nada: el actor real
   quedaba pintado con la ventana minimizada.

O sea: el parche del clone tapó una mitad del bug y **destapó la otra**. Por eso
"seguía apareciendo" después de arreglarlo.

**Fix**: `setup/patches/paperwm-show-minimizado.patch`, aplicado en
`~/.local/share/gnome-shell/extensions/paperwm@paperwm.github.com/tiling.js`.
Invariante nuevo en `showHandler`: *una ventana minimizada no se dibuja, ni por
su actor ni por su clone*. El guard `!Main.wm._minimizing.has(actor)` respeta la
animación de minimizado en curso, para no romper el efecto genie.

`setup/modules/50-extensions.sh` → `parchar_paperwm()` ahora aplica **los tres**
parches (antes aplicaba uno solo y el del fantasma quedaba fuera del kit), cada
uno con su centinela de idempotencia.

**Verificado**: `bash setup/shell-sandbox.sh paperwm@paperwm.github.com` →
`ACTIVE`, sin errores. **Falta la prueba en la sesión real** (ver "Qué verificar
después de cerrar sesión").

### 2. Botón del dock en el hub de arriba a la derecha — hecho

`macos-dock@son.local/lib/quickToggle.js`: un `QuickToggle` con la misma forma
que el de modo oscuro. Encendido = **dock fijo**; apagado = **dock invisible**,
aparece al empujar el borde de abajo. El estado es la gsetting `auto-hide` del
dock, atada con `Gio.SettingsBindFlags.INVERT_BOOLEAN`, así que sobrevive al
reinicio y se refleja si alguien la cambia desde otro lado.

Dos cosas que estaban mal documentadas y se corrigieron al leer el código:

- `lib/panelIndicator.js` existía pero **nadie lo importaba**: era un icono
  suelto más en la barra, justo lo contrario de lo pedido. Se borró.
- `lib/dockVisibility.js` **ya no tiene** el poll a 10 Hz que decía el
  `CLAUDE.md`: hoy usa una barrera de presión de mutter (`Meta.Barrier` +
  `Layout.PressureBarrier`) y un chequeo puntual al esconder. No hay nada que
  arreglar ahí.

**Verificado**: sandbox con `macos-dock@son.local` + `mactahoe-tweaks@son.local`
→ las dos `ACTIVE`, sin errores. Falta verlo en pantalla.

### 3. Aplicaciones instaladas — hecho y probado en pantalla

| App | Versión | Cómo |
|---|---|---|
| Google Chrome | 152.0.7977.64 | `.deb` oficial, `pkexec apt-get install` |
| Krita | 5.3.3 | Flatpak (`org.kde.krita`) |
| LibreSprite | 1.1-dev | Flatpak (`com.github.libresprite.LibreSprite`) |
| Pixelorama | 1.2.1 | Flatpak (`com.orama_interactive.Pixelorama`) |

Krita reemplaza a Clip Studio (que no tiene versión Linux y necesitaría Wine);
LibreSprite y Pixelorama van los dos para que el artista elija: LibreSprite es el
fork libre de Aseprite 1.1 (mismos atajos), Pixelorama está más vivo y tiene
mejor animación por capas.

Las cuatro se abrieron y se capturaron en pantalla, no se dieron por instaladas.

**Trampa encontrada**: el primer intento falló con
`bwrap: Can't find source path /run/user/1000/doc/by-app/<id>`. El servicio
`xdg-document-portal` estaba `active (running)` pero **su FUSE no estaba
montado** (`/run/user/1000/doc` vacío, sin entrada en `mount`). Se arregla con
`systemctl --user restart xdg-document-portal`. Si vuelve a pasar después de un
login, ninguna Flatpak arranca y el error no dice "portal": dice `bwrap`.

### 4. Pendiente

- **Agrupar en el hub los iconos sueltos de la barra**: quedan fuera de Quick
  Settings el de **Clipboard Indicator** y el de **GSConnect** (verificado por
  captura: `shot.sh --crop 1500,0,420,40`). El resto (no molestar, volumen,
  medidor, encendido) ya vive adentro. Reparentar botones con menú propio es
  frágil, así que hay que probarlo en vivo antes de dejarlo.
- **PaperWM tiene ruido en el journal** al destruir fondos:
  `Object Meta.BackgroundActor ... already disposed`, con la traza en
  `utils.js:567` / `grab.js:441`. No rompe nada visible; anotado para no
  confundirlo con el fantasma.

---

## Qué verificar después de cerrar sesión

1. **Fantasma**: minimizar la terminal, Brave y Discord, una por una. El
   escritorio tiene que quedar limpio. Con evidencia:
   `bash setup/shot.sh --out /tmp/min.png` y mirar el semáforo — si aparecen tres
   círculos grises donde estaba la ventana, el fantasma sigue.
2. **Botón del dock**: abrir el hub de arriba a la derecha. Tiene que estar el
   toggle **Dock · Fijo**. Apagarlo esconde el dock; el dock vuelve al empujar el
   borde de abajo; encenderlo lo clava otra vez.
3. **Flatpaks**: si alguna no abre, `systemctl --user restart xdg-document-portal`
   antes de investigar cualquier otra cosa.

Si el fantasma **sigue**, no cerrar sesión otra vez a ciegas: habilitar unsafe
mode (`Alt+F2` → `lg` → `global.context.unsafe_mode = true`) y diagnosticar en
caliente por D-Bus, que no cuesta reinicios:

```bash
gdbus call -e -d org.gnome.Shell -o /org/gnome/Shell -m org.gnome.Shell.Eval \
  'global.get_window_actors().map(a => [a.meta_window.title, a.meta_window.minimized, a.visible, a.meta_window.clone?.cloneActor?.visible ?? null]).join(" | ")'
```

`minimized:true` + `visible:true` → es el actor real. `cloneActor.visible:true` →
es el clone. Ese único dato dice cuál de las dos mitades quedó suelta.

---

## Histórico — 26 al 29 de agosto de 2026

Esto vivía en `CLAUDE.md` y lo estaba inflando: son hechos ya cerrados, que se
consultan cuando algo se rompe, no en cada mensaje.

Estado al 26 de agosto de 2026, según `bash setup/doctor.sh`:

- **Node instalado con nvm**, 24.20.0 por defecto (también quedaron la 16, 18 y
  22). La regla se mantiene: siempre nvm, nunca apt, nunca `sudo npm install -g`.
- Ya instalados: `ripgrep fzf bat btop eza zoxide` y VS Code (repo de Microsoft,
  no snap).
- **Vulkan y VA-API funcionan.** Antes el doctor los daba por ausentes, pero los
  drivers ya estaban: lo que faltaba eran las CLI de diagnóstico. Verificado:
  Vulkan responde `RADV NAVI10` y VA-API decodifica y **codifica** H264/HEVC por
  hardware con `radeonsi`.
- Apariencia coherente: tema `MacTahoe-Dark`, iconos `MacTahoe-dark`, cursores
  `WhiteSur-cursors`, botones a la izquierda. Modo oscuro y `Ubuntu Sans` intactos.
- **`swappiness` ya está en 10** — ese pendiente quedó resuelto.
- 24 snaps instalados.

Cambios del 27 y 28 de agosto de 2026 (módulo `--extensions`), **pendientes de
reiniciar sesión** para verse:

- **Barra superior transparente con desenfoque.** Antes se veía gris oscuro fijo,
  y la explicación que estaba acá ("el tema ya la deja transparente") era falsa.
  La causa real: Ubuntu 26.04 trae en
  `/usr/share/gnome-shell/theme/Yaru/gnome-shell-dark.css` la regla
  `#panel { background-color: #131313 !important; }`, y ese `!important` le gana
  al `transparent` de MacTahoe pase lo que pase. Por lo mismo Blur my Shell
  tampoco podía: pone la transparencia con una clase CSS normal. Ahora lo
  resuelve `panelStyle.js` de la extensión propia, con estilo inline sobre
  `Main.panel`, que es lo único que gana en la cascada.
- **Blur my Shell reactivada**, pero con el componente `panel` apagado: no porque
  sobre, sino porque **no puede** (ver arriba). Activados `overview`, `appfolder`,
  `lockscreen` y `applications`. Si vuelve a faltar fluidez, el orden para apagar
  es `applications` → `overview` → el resto.
- **Transparencia de ventanas arreglada.** El efecto "duraba unos segundos" y se
  iba al volver a la ventana. Causa: `blur-my-shell.applications dynamic-opacity`
  en `true` vuelve **sólida la ventana enfocada** (está literal en su código,
  `components/applications.js:134`). Ahora está en `false`, con `opacity` en 190 y
  `enable-all` en `true`. Si Chrome o VS Code muestran artefactos: subir
  `hacks-level` a 2, y si sigue, sumarlos a la `blacklist`.
- **Extensión propia `mactahoe-tweaks@son.local`** (fuente en
  `setup/extensions/`): fondo de la barra superior, blur en los menús del panel
  —que Blur my Shell no puede hacer— y `Super+Space` para saltar entre el
  escritorio 1 y el 2.
- **`Super+Space` arreglado.** El atajo se registraba bien (`addKeybinding`
  devolvía una acción válida, verificado en el sandbox) pero no hacía nada:
  `meta_workspace_activate()` descarta la petición **en silencio** si el timestamp
  es 0, y `global.get_current_time()` devuelve 0 cuando no hay evento en curso.
  Ahora cae a `get_current_time_roundtrip()`.
- **Dock: fork propio `macos-dock@son.local`**, parche de MacOS Dock v7. Arregla
  que el icono magnificado se saliera del rectángulo (escalar no cambia la
  asignación y el contenedor medía justo el alto del rectángulo), el desenfoque
  cuadrado bajo un fondo redondeado, la magnificación que se desincronizaba al
  abrir o cerrar apps, y un bucle a 60 fps que nunca paraba. Detalle completo en
  `setup/README.md`. Al tener UUID propio **no recibe actualizaciones de EGO**.
- **Dock siempre visible** (`auto-hide false`). Contrapartida: no le reserva
  espacio a las ventanas, así que una maximizada le pasa por debajo — igual que
  macOS con "ocultar el Dock" apagado.
- **El dock no cargaba, y por eso el Overview mostraba un "dock enorme"**
  (arreglado el 28 de agosto de 2026). `cornerEffect.js` está duplicado en las
  dos extensiones propias y las dos registraban el mismo
  `GTypeName: 'MacTahoeTweaksCornerEffect'`. Todas las extensiones de GNOME
  comparten **un único registro de tipos GObject**: el nombre es global al
  proceso, no al archivo. `mactahoe-tweaks` cargaba primero, y el dock moría al
  importar el módulo con `Type name ... is already registered`, antes de llegar
  a `enable()`. Ahora el fork usa `MacosDockCornerEffect`. El "dock grande" que
  aparecía con `Super` nunca fue el dock: era el Dash del Overview, que el fork
  esconde en `_hideDefaultDash()` **dentro de** ese `enable()` que nunca corría.
  Una causa, dos síntomas.
- **Iconos del dock: 40 px en reposo, 52 px magnificados** (antes 48 y 67). Los
  dos valores están atados (`icon-size × magnification-scale`, ahora `40 × 1.3`),
  y el alto de la barra sale de `icon-size` (`icon-size + 24` = 64 px), no se
  configura aparte.
- **`shell-sandbox.sh` daba falsos negativos.** Su filtro buscaba
  `Extension .* error` en minúscula, pero GNOME escribe
  `Extension <uuid>: Error:` sobre `GNOME Shell-CRITICAL`. Decía "sin errores"
  sobre un log que tenía el error del dock. Ahora también mira el cambio de
  estado `to ERROR` y cierra con un veredicto `ACTIVE`/`ERROR` por extensión.
- **El dock sí muestra la papelera** (otra afirmación falsa que estaba acá; se ve
  en las capturas). Aparece porque está en `org.gnome.shell favorite-apps`.
- **`ubuntu-appindicators` desactivada**: no hay más iconos de bandeja en la
  barra superior. Eso hace que "minimizar a la bandeja" sea una trampa: la
  ventana se va a una bandeja que no existe. Resuelto para Discord con
  `MINIMIZE_TO_TRAY: false` (ver el 29 de agosto); si aparece otra app con la
  misma opción, apagarla también.
- `Ulauncher` pasó a `Ctrl+Super+Space` (antes solo se abría desde la bandeja, y
  su atajo tenía el comando mal escrito).
- **`compiz-windows-effect` desactivada** (ventanas gelatinosas): es estética
  Compiz, no macOS. El efecto genio al minimizar lo daba
  `compiz-alike-magic-lamp-effect`, que el 29 de agosto **hubo que desactivar
  porque rompía el minimizado por completo** (ver más abajo).
- Se borró un atajo basura (`SAD` / `Ctrl+Space` / comando `ASD`) que bloqueaba
  Ctrl+Space sin hacer nada.
- Sin resolver (los dos se cerraron el 29 de agosto, ver abajo): `space-bar`
  seguía activa y la fuente seguía en `Ubuntu Sans` en vez de `Inter`.

Cambios del 29 de agosto de 2026:

- **Minimizar no funcionaba en ninguna aplicación** — Discord, Steam, la
  terminal, Brave. Parecía que Brave se colgaba; el navegador no tenía nada que
  ver. La culpable era `compiz-alike-magic-lamp-effect`, ya desactivada.
  La cadena: la extensión reemplaza `Main.wm._shellwm.completed_minimize` por
  una función vacía, así que el shell deja de completar la minimización por su
  cuenta y pasa a depender de que el efecto termine. Pero su handler llama a
  `getIcon()`, que en la línea 133 ejecuta `Main.overview.dash._redisplay()` —
  y eso revienta con `firstIcon.icon is null`, porque nuestro fork del dock
  esconde ese Dash en `_hideDefaultDash()` y un Dash oculto no construye sus
  iconos. La excepción corta el handler antes de crear el efecto, nadie llama
  al `completed_minimize` original, y la ventana no se minimiza nunca.
  Misma clase de bug que el `GTypeName` duplicado: dos extensiones que se
  pisan, con el síntoma lejos de la causa.
- **Efecto de minimizar nuevo: `macos-genie@thuongvo.dev`** (de git, no está en
  EGO). Elegido porque su `metadata.json` declara `shell-version: ["50"]`, no
  toca el Dash, y **llama a `completed_minimize` siempre, incluso dentro del
  `catch`** — o sea que aunque el efecto falle, la ventana se minimiza igual.
  Eso es exactamente lo que le faltaba al anterior.
- **El dock ahora publica `set_icon_geometry()`** (`publishIconGeometries()` en
  `lib/iconManager.js`). Es lo que leen las animaciones de minimizar para saber
  hacia dónde animar: sin eso, el genio apunta al centro de la pantalla en vez
  de al icono del dock. Se llama desde `_refreshAllIndicators()`, que ya se
  disparaba al cambiar el foco y al abrirse o cerrarse ventanas. La referencia
  de cómo hacerlo es `ubuntu-dock/appIcons.js:405`, incluido el guard de
  `get_stage()` (fuera del stage, la posición que reporta el actor es basura).
- **`niri` evaluado y descartado por ahora.** No es una distro: es un compositor
  Wayland de scrollable tiling, y ponerlo **reemplaza GNOME Shell entero** —
  se perderían el dock, MacTahoe, Blur my Shell y las dos extensiones propias.
  Lo que da el mismo desplazamiento sin tirar nada es **PaperWM**, extensión de
  GNOME cuya release v50.0.1 ya soporta GNOME 50. Pendiente de probar en
  `setup/shell-sandbox.sh`; va a chocar con `space-bar` y con el `Super+Space`
  de `mactahoe-tweaks`.
- El USB (Kingston DataTraveler 3.0, 32 GB, NTFS) monta bien solo con
  reconectarlo; GNOME lo automonta en `/run/media/son/`. No hacía falta `sudo`.
- **Discord inunda el log de auditoría**: se contaban ~650 denegaciones
  AppArmor de `ptrace` cada 5 minutos, con `kauditd_printk_skb: ~205 callbacks
  suppressed` cada 5 segundos. Es el snap intentando leer procesos fuera de su
  confinamiento. Se arregla con el `.deb`.
  **Esa cifra resultó estar mal por cuatro órdenes de magnitud** y el `~205
  callbacks suppressed` era la pista que no se siguió: el número real eran
  ~230.000 eventos por segundo, y no "ensuciaba el journal", costaba CPU. Cómo
  medirlo bien, en el bullet del `.deb` más abajo.

- **La fuente nunca fue Inter, y el módulo creía que sí.** `40-theme.sh` seteaba
  `Inter 11` y `Fira Code 11` **sin instalar ninguna de las dos**. Pango no
  avisa cuando no encuentra una familia: cae al fallback (Noto Sans) en
  silencio, así que `gsettings get` devolvía `'Inter 11'` y la pantalla mostraba
  Ubuntu Sans. Por eso el pendiente "la fuente sigue en Ubuntu Sans" nunca se
  cerraba: el ajuste estaba puesto, la fuente no estaba. Ahora el módulo baja
  Inter y Fira Code de sus releases de GitHub a `~/.local/share/fonts` (sin
  sudo) y **verifica con Pango que la familia resuelva antes de setearla**;
  si no resuelve, avisa en vez de mentir.
  Trampa concreta: `'Inter Semi Bold 11'` (con espacio) **no** lo resuelve
  Pango y cae a Noto Sans Bold. El que funciona es `'Inter SemiBold 11'`.
- **Extensiones nuevas**, las cuatro verificadas contra GNOME 50 antes de
  instalar y probadas juntas en `setup/shell-sandbox.sh`:
  `paperwm` (tiling scrollable, el gesto de niri sin dejar GNOME),
  `rounded-window-corners@fxgn` (esquinas redondeadas en todas las ventanas),
  `clipboard-indicator` (el historial de portapapeles, el Win+V de Windows) y
  `gsconnect` (el celular integrado).
  **Pano quedó descartada**: su última versión es para GNOME 45.
- **GSConnect necesita `wl-clipboard`.** Sin `wl-paste` tira
  `GLib.SpawnError: Falló al ejecutar el proceso hijo «wl-paste»` al arrancar.
  Lo cazó el sandbox antes de tocar la sesión real; ya está en el módulo.
- **`space-bar` desactivada** — el otro pendiente que estaba anotado. Además se
  pisaba con el indicador propio de PaperWM.
- **`monitors.xml` limpio**: tenía una `<configuration>` obsoleta con `DP-2`
  para el monitor VAL VH2714, que hoy está en `DP-3`.
- **Discord pasó de snap a `.deb`, hecho y verificado.** Con el `.deb` quedan
  **cero** denegaciones propias; las que siguen apareciendo son de los snaps de
  Spotify y snap-store, y son decenas por minuto, no millones.
  Lo que hubo que saber para hacerlo:
  - **El journal miente sobre el tamaño del problema, y por eso las cifras
    viejas de este archivo (“~650 cada 5 minutos”, “14.800 en un arranque”)
    estaban mal por cuatro órdenes de magnitud.** Sin `auditd` instalado los
    registros de audit salen sólo por `printk`, que los limita por ritmo: lo que
    se puede contar con `grep` en el journal es la parte que pasó el filtro, no
    lo que ocurrió. El aviso `kauditd_printk_skb: N callbacks suppressed` es la
    pista de que hay algo debajo.
    La medición de verdad está en el **número de serie** de cada registro, el
    entero después de los dos puntos en `audit(1788052525.472:118635050)`: es un
    contador global del kernel que sube con **todos** los eventos, incluidos los
    que nunca se imprimen. Se lee así:

    ```bash
    journalctl -k --since "-15min" | grep -o 'audit([0-9.]*:[0-9]*)' | sed -n '1p;$p'
    ```

    Arrancando a las 22:01 del 29 de agosto, el contador iba en **432** a las
    22:07 y en **118.635.051** a las 22:15:25, que es el instante exacto en que
    murió el último proceso del snap: **~118 millones de eventos en ocho
    minutos, unos 230.000 por segundo**. Desde entonces el ritmo es de **menos
    de un evento por segundo**, y de Spotify, no de Discord. El salto es de
    cinco órdenes de magnitud, y explica por qué se sentía la máquina: cada
    evento es una entrada al kernel.
  - **Las dependencias sí resuelven.** El `.deb` pide los nombres viejos
    (`libasound2`, `libgtk-3-0`, `libglib2.0-0`, `libatk*`, `libatspi2.0-0`) y
    Ubuntu 26.04 los renombró a `t64`; los 6 casos resuelven por el `Provides:`
    de los `t64`, ya instalados. `apt-get install --simulate` confirmó que
    **instala sólo `discord`**, sin arrastrar ni actualizar nada.
  - **El `.deb` de 2026 ya no es el paquete monolítico**: son 2 MB de
    *bootstrap* (`/usr/share/discord/updater_bootstrap`). El lanzador
    `/usr/bin/discord` mira si existe `~/.config/discord/Discord`; si no, baja
    la app real a `~/.config/discord/app-<versión>/` y la ejecuta. Consecuencia
    práctica: **el primer arranque necesita internet**, y `SKIP_HOST_UPDATE`
    hay que ponerlo en `false` — el snap lo tenía en `true` porque ahí
    actualizaba `snapd`, pero ahora el updater propio es el único que hay.
  - **Trae su propio perfil AppArmor** (`/etc/apparmor.d/discord`) sobre
    `@{HOME}/.config/discord/app-*/Discord` con `flags=(unconfined)` y `userns`.
    Eso es lo que le permite el sandbox de Electron con la restricción de
    namespaces de usuario sin privilegios que trae Ubuntu desde la 24.04.
  - **El perfil se migra solo si se copia a mano**: el snap lo guardaba en
    `~/snap/discord/current/.config/discord` y el `.deb` usa
    `~/.config/discord`, que es exactamente el mismo árbol. Copiado con
    `cp -a` y verificado con `rsync -n` antes de borrar nada; la sesión siguió
    iniciada, no hubo que volver a loguearse.
  - **`MINIMIZE_TO_TRAY: false` en `settings.json`.** El `.desktop` del `.deb`
    no pasa `--use-tray-icon` como hacía el snap, y con `ubuntu-appindicators`
    desactivada no hay bandeja: en `true` (el default) cerrar la ventana la
    manda a un lugar del que no vuelve, con el proceso vivo.
  - El snap se sacó con `snap remove` (sin `--purge`), así que queda una
    **instantánea de 77 MB** como respaldo: `snap saved` la lista, y
    `snap forget 1` la borra cuando ya no haga falta.
  - `sudo` no sirve desde acá: sin TTY responde
    `A terminal is required to authenticate`, incluso con el prefijo `!`.
    La vía que funciona es **`pkexec`**, que abre el diálogo gráfico de GNOME.
    Ojo: `pkexec` corre el comando desde `$HOME`, así que un `./archivo.deb`
    falla con "fichero no admitido" — hay que pasarle la ruta absoluta.
  - **`snap remove` no mata la instancia que ya estaba corriendo.** Después de
    sacar el snap seguían apareciendo denegaciones, y parecía que la migración
    no había servido de nada. No era eso: había un Discord del snap lanzado
    desde el dock **un minuto antes** de quitarlo (se ve en el `lstart` del
    proceso y en que su padre es `gnome-shell`). El squashfs ya estaba
    desmontado, pero el proceso sigue vivo con los archivos mapeados y **con el
    perfil `snap.discord.discord` todavía aplicado**, así que sigue tirando
    `ptrace` hasta que se lo mata a mano. Regla: después de migrar, mirar
    `ps -eo args | grep ^/snap/<app>` antes de dar el ruido por terminado.
    Cuidado también al verificarlo con `pgrep -f`: el patrón matchea la propia
    línea de comando del shell que lo ejecuta y da un falso positivo.
  - Quedan dos perfiles AppArmor con nombre parecido y no es un error:
    `/etc/apparmor.d/discord` lo trae el `.deb` y apunta a
    `~/.config/discord/app-*/Discord`; `/etc/apparmor.d/Discord` (mayúscula) es
    del paquete `apparmor` de Ubuntu, apunta a `/usr/share/discord/Discord`
    (la ruta del `.deb` monolítico viejo) y existe sólo para darle un nombre a
    un proceso que si no aparecería como `unconfined`.
- **Bug propio encontrado de rebote: el dock no reaccionaba a los favoritos.**
  Al cambiar `org.gnome.shell favorite-apps` de `discord_discord.desktop` (snap)
  a `discord.desktop` (deb), el icono simplemente **no aparecía**, sin un solo
  error en el log. Causa: `iconManager.js` conectaba `installed-changed` del
  `Shell.AppSystem` pero **nunca `changed::favorite-apps`**, así que sólo releía
  la lista cuando se instalaba o desinstalaba una app. Peor combinación: como
  `_reload()` hace `lookup_app(appId)` y **saltea en silencio** el que devuelve
  `null`, un favorito que apunta a un `.desktop` muerto desaparece del dock sin
  avisar. Arreglado en el fork (`macos-dock@son.local`), probado en
  `setup/shell-sandbox.sh` (las dos extensiones `ACTIVE`, sin errores).
  Mientras tanto se puede forzar el `installed-changed` creando y borrando
  cualquier `.desktop` en `~/.local/share/applications` — así se vio en la
  captura que el icono entra en su posición y con el punto de "en ejecución".

Noche del 29 de agosto de 2026 — escritorio y migración desde Windows:

- **Windows nunca se borró: está entero en el disco y es sólo inalcanzable.**
  `nvme0n1p3` son **1,1 TB de NTFS** con el C: intacto, más `nvme0n1p4`
  (recuperación), `nvme0n1p2` (MSR) y el gestor de arranque
  `\EFI\Microsoft\Boot\bootmgfw.efi`, con su entrada UEFI **`Boot0000*
  Windows Boot Manager` primera en el `BootOrder`**. Lo que lo esconde son tres
  líneas de `/etc/default/grub`: `GRUB_TIMEOUT=0`, `GRUB_TIMEOUT_STYLE=hidden`
  y `#GRUB_DISABLE_OS_PROBER=false` **comentada**.
  Esa última es la trampa y no es de esta máquina: **desde GRUB 2.06 el
  detector de otros sistemas viene apagado de fábrica**, así que `update-grub`
  jamás escaneó el disco y `grub.cfg` no tiene entrada de Windows. El timeout
  del firmware, además, es de 1 segundo. Antes de plantear cualquier
  reinstalación hay que mirar `lsblk -o NAME,SIZE,FSTYPE,PARTTYPENAME` y
  `efibootmgr -v`: el sistema "perdido" suele estar entero.
- **Los 3 iconos de la izquierda de la barra eran de PaperWM**, verificado en
  píxeles con `shot.sh --crop 0,0,900,40`: `S` = `show-workspace-indicator`,
  el icono de foco = `show-focus-mode-icon`, la flecha `→` =
  `show-open-position-icon`. Al apagarlos aparecieron **tres puntos** que
  estaban tapados: el botón «Actividades» de GNOME, que dibuja un punto por
  escritorio. Se saca con `just-perfection activities-button false`; el
  Overview sigue accesible con `Super` (`overlay-key`).
- **El lag no era un ajuste mal puesto, es el refresco.** El monitor primario
  **DP-1 corre a 1920×1080 @ 360 Hz** (el secundario DP-3, a 2560×1440 @
  200 Hz): cada cuadro dura **2,78 ms** y ahí adentro tienen que entrar todos
  los efectos. El más caro al minimizar era `macos-genie` con
  `minimize-duration 560` y `mesh-resolution 128` — **560 ms a 360 Hz son ~200
  cuadros** deformando una malla de 128 segmentos. Bajado a `300 / 260 / 64`, y
  `paperwm animation-time` de `0.25` a `0.15`.
  `blur-my-shell` **no se tocó**: el usuario reportó que lo tosco es
  minimizar/abrir/cerrar, no el desenfoque, y el diagnóstico anterior que lo
  señalaba era una suposición sin medir.
- **`dockVisibility.js` parece tener un bucle desperdiciado y no lo tiene.**
  Su `GLib.timeout_add(150, 100, ...)` sondea el puntero 10 veces por segundo
  aunque el `motion-event` de al lado ya haga lo mismo — pero
  `DockVisibility.start()` sólo se llama desde `_startAutoHide()`, que está
  detrás de `if (settings.get_boolean("auto-hide"))` en `dockManager.js:189`, y
  `auto-hide` está en `false`. **Nunca arranca.** Anotado para que nadie lo
  "arregle" de nuevo. (`magnification.js` sí estaba bien: suelta el timer
  cuando no queda nada que animar.)
- **PaperWM no permite arrastrar esquinas porque es de mosaico**, no por un
  ajuste. La salida sin abandonarlo es la capa flotante: `Super+Escape` saca la
  ventana enfocada y ahí sí se estira desde cualquier esquina. Documentado en
  `LINUX-SETUP.md`.
- **Migración del pendrive de Windows, hecha y verificada** (`rsync -n` dio 0
  diferencias sobre 100.673 archivos antes de mover nada):
  - `PROYECTOS/` → `~/Documentos/Proyectos/` (84.087 archivos).
  - `.claude` de Windows fusionado con el de Linux: `CLAUDE.md`, `settings.json`,
    7 skills, 2 plugins e historial. **Las credenciales no se copian**: el
    `.credentials.json` del backup es el token de Windows y pisarlo corta la
    sesión en curso.
  - **El historial de proyectos hay que renombrarlo, no copiarlo.** Claude Code
    nombra cada carpeta de `~/.claude/projects/` con la ruta del proyecto
    reemplazando todo lo no alfanumérico por `-` — por eso esta sesión vive en
    `-home-son-Im-genes-Prep-Course`, con la `á` convertida también. Sin
    renombrar, las 12 carpetas `C--Users-kanam-OneDrive-Desktop-Code-*` quedan
    huérfanas. Se descartaron `C--WINDOWS-system32` y `C--Users-kanam`.
  - **Las skills traían rutas de Windows en el cuerpo**, no sólo en la config:
    10 archivos con `C:\Users\kanam\...` y `/c/Users/kanam/.ai-keys.env`.
    Adaptar sólo `settings.json` deja las skills apuntando a rutas inexistentes.
  - `.gemini` → `~/.gemini`, limpiando los `.tmp` y el CRLF que mete PowerShell.
- **El perfil de Brave de Windows no es portable, y el motivo es concreto:** su
  `Local State` tiene `os_crypt.encrypted_key` y `app_bound_encrypted_key`,
  cifradas con **DPAPI**, atado a esa cuenta y esa máquina. Cookies y
  contraseñas son indescifrables en Linux. Sí se migran los marcadores
  (`Default/Bookmarks`, JSON plano) — **borrando el campo `checksum`**, porque
  si no coincide Brave descarta el archivo.
  Las 18 "extensiones" del perfil resultaron ser **componentes internos de
  Brave** (adblock updaters, Tor, imágenes del inicio): no había ninguna de
  terceros que reinstalar.
- **Liberados 3,8 GB**: `~/snap/brave/User Data` (1,5 GB) era un intento de
  copia anterior en una ruta que Brave **no lee jamás** — el perfil vivo del
  snap está en `~/snap/brave/current/.config/BraveSoftware/Brave-Browser/`.
- **La API key de Gemini del backup sigue viva** (HTTP 200 contra
  `generativelanguage.googleapis.com/v1beta/models`). Pero **el nombre del
  modelo de la skill había quedado viejo**: los alias cambian seguido y hay que
  listarlos contra la API antes de usarlos. Al 29/08/2026 el más nuevo es
  `gemini-3.7-flash`. `gemini` y `codex` instalados con nvm.
