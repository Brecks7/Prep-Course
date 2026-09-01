# Historial del escritorio — sesiones del 26 al 31 de agosto de 2026

Esto es el relato completo de cada sesión: síntomas, diagnósticos, callejones sin
salida y evidencia. **No se lee al arrancar.** `ESTADO.md` dice en qué anda cada
cosa hoy; acá se viene cuando algo se rompe y hace falta el porqué largo, o
cuando una decisión parece arbitraria y hay que saber contra qué se peleó.

Se movió acá el 30 de agosto de 2026: `ESTADO.md` había llegado a 776 líneas y se
leía entero en cada sesión, que es exactamente lo que el skill `estado-de-proyecto`
dice que no hay que hacer (*«sobrescritura, no bitácora»*).

---

## Sesión del 31 de agosto de 2026 (noche) — el cuelgue con CS2, diagnosticado

La sesión anterior murió acá: se abrió CS2 y el escritorio se fue a **negro
estático**. Nada se pudo escribir en el momento. Lo que sigue es la reconstrucción
desde el journal del arranque `-1`, ya con la sesión nueva levantada.

### Qué pasó de verdad — no era el compositor

```
18:43:01 amdgpu 0000:03:00.0: [gfxhub] page fault (src_id:0 ring:24 vmid:6 pasid:127)
                              Process cs2 pid 14096 thread VKRenderThread pid 14139
                              in page starting at address 0x00008000fbc08000 from client 0x1b (UTCL2)
                              Faulty UTCL2 client ID: SQC (data) (0xa)
                              PERMISSION_FAULTS: 0x3    MORE_FAULTS: 0x1
18:43:04 amdgpu: ring gfx_0.0.0 timeout, signaled seq=246917, emitted seq=246919
18:43:04 amdgpu: Starting gfx_0.0.0 ring reset  →  Ring gfx_0.0.0 reset failed
18:43:05 gnome-shell[3088]: Connection to xwayland lost
18:43:05 amdgpu: GPU reset(1) succeeded!
18:43:05 amdgpu: [drm] device wedged, but recovered through reset
18:44:07 radv/amdgpu: The CS has been cancelled because the context is lost.
```

Se leyó mal dos veces antes de mirar el journal, y las dos lecturas quedaron
escritas en el plan viejo. Las correcciones:

- **El reset no falló.** Lo que falló fue el reset *por ring* (`Ring gfx_0.0.0
  reset failed`); el kernel escaló a un reset de **dispositivo completo** que sí
  funcionó (`GPU reset(1) succeeded!`, `recovered through reset`). El kernel
  nunca murió.
- **Lo que murió fue Xwayland** (`Connection to xwayland lost`). Eso es el
  pantallazo negro: no un cuelgue del sistema, sino el servidor X caído bajo una
  sesión Wayland que siguió viva.
- **La GPU no es una RX 5700 XT.** `glxinfo` da `AMD Radeon RX 6900 XT
  (radeonsi, navi21, ACO)`, PCI `0x73bf`. El `CLAUDE.md` lo tenía mal desde el
  principio y ese dato ya había orientado mal un plan entero. Corregido.

`SQC (data)` + `PERMISSION_FAULTS` significa que un **shader** leyó memoria fuera
de lo suyo. No es hardware fallando ni el compositor: es el código que RADV
compiló para ese shader.

### Por qué el snap de Steam es el sospechoso

Steam está instalado como snap (`/snap/bin/steam`, rev 231) y **no usa el Mesa del
sistema**: lo recibe por content-snap desde `gaming-graphics-core24`. Verificado
desde adentro del confinamiento con `snap run --shell steam -c 'glxinfo -B'`:

| Stack | Mesa (al momento del crash) |
|---|---|
| Sistema (GNOME, escritorio) | **26.0.8** |
| Snap de Steam (`gaming-graphics-core24`, canal `kisak-fresh/stable`) | **25.2.2** |

El canal que traía el snap, `kisak-fresh/stable`, estaba **congelado en 25.2.2
desde el 18 de diciembre de 2025** — ocho meses sin moverse. O sea que el RADV que
compiló el shader culpable venía una serie mayor entera atrás del que mueve el
escritorio sin problemas.

Es un modo de falla ya documentado para este snap: hay un caso análogo en el foro
de Ubuntu (RX 9070 XT en 25.04) donde el Mesa viejo del snap cuelga la GPU y lo que
lo resuelve es usar Steam por `.deb` o Flatpak, que sí toman el Mesa del sistema.

### La pieza que cerró el caso: el shader cache

`steamapps/shadercache/730/fozpipelinesv6/steam_pipeline_cache.foz` pesaba
**5,3 GB** y tenía fecha **18:39** del 31/08. El crash fue a las **18:43**: cuatro
minutos después. Es el pipeline cache de Fossilize que Steam descarga y precompila
con el RADV local antes de que el juego arranque.

Y en todo el journal guardado (desde el 25 de agosto, 11 arranques) **`cs2` aparece
una sola vez**: la del crash. El único proceso que causó page faults de amdgpu en
esa semana, y en su única corrida. No es esporádico: es 1 de 1, estrenando 5,3 GB
de shaders recién compilados por un driver viejo.

### Qué se hizo

1. `snap refresh gaming-graphics-core24 --channel=kisak-turtle/candidate`
   → de **25.2.2** a **25.3.6** (abril de 2026). Se eligió `kisak-turtle/candidate`
   porque es a la vez la revisión más nueva de todos los canales del snap y la de
   rama más conservadora. Verificado desde adentro: `Mesa 25.3.6 - kisak-mesa PPA`.
   Ningún canal del snap llega al 26.0.8 del sistema.
2. `rm -rf steamapps/shadercache/730` → 5,6 GB. El cache entero lo había compilado
   el driver viejo; se regenera solo en el primer arranque (esa partida va a tardar
   más en cargar, es esperable).

**Falta la prueba de fuego: abrir CS2.** No se hizo en esta sesión a propósito — si
vuelve a colgar se lleva puesto Xwayland y con él la conversación, que es
exactamente la regla que le dio origen a `ESTADO.md`. Se escribió esto primero.

### Si vuelve a pasar

Que no cuelgue a ciegas otra vez. En las propiedades de CS2 en Steam, opciones de
lanzamiento:

```
RADV_DEBUG=hang MESA_VK_ABORT_ON_DEVICE_LOSS=1 %command%
```

Con eso RADV vuelca el shader culpable en `~/radv_dumps` en vez de tumbar el
servidor gráfico. Cuesta rendimiento (sincroniza en cada draw call): es para
diagnosticar, no para jugar. Y en otra terminal, `journalctl -kf | grep amdgpu`.

Escalada, si el Mesa nuevo no alcanzó:

1. `RADV_DEBUG=llvm %command%` — cambia el compilador de shaders de ACO a LLVM. Si
   con esto no cuelga, es un bug de ACO en Navi 21 y hay que reportarlo.
2. **Steam por `.deb` o Flatpak** en lugar del snap: es el fix que reportaron
   efectivo en el caso análogo, porque toma el Mesa 26.0.8 del sistema. Ojo: CS2
   ocupa **67 GB**, así que la biblioteca se migra moviendo `steamapps/`, no
   re-descargando.
3. `amdgpu.noretry=0` en el cmdline. Hoy no hay ningún parámetro de amdgpu ahí, y
   tocarlo pide reiniciar. Último recurso.

### De paso, limpieza de disco — 5,9 GB

- Los tres clones de temas: `~/Descargas/MacTahoe-gtk-theme` (30 MB),
  `~/Descargas/WhiteSur-icon-theme` (118 MB) y `~/WhiteSur-icon-theme` (**148 MB**).
  El último pesaba el doble de lo esperado porque tenía un `MacTahoe-gtk-theme/`
  clonado **adentro** — un `git clone` corrido desde el directorio equivocado.
  Los tres limpios y con remote público, recuperables con un `git clone`.
  Verificado antes de borrar: `grep "Descargas" setup/*.sh` sin hits (`undo.sh` no
  los referencia) y ningún symlink de `~/.themes` o `~/.local/share/icons`
  apuntaba ahí — el tema aplicado vive instalado, independiente del clon.
- El shader cache de CS2: 5,6 GB.

---

## Sesión del 30 de agosto de 2026 (noche)

### 1. PaperWM tiraba la sesión entera — arreglado

El síntoma que se reportó fue "se me reinició la sesión al abrir Discord". No fue
Discord: fue un **SIGSEGV de GNOME Shell** con la traza en `tiling.js:3589` ←
`utils.js:505`.

El handler de `workspace-changed` de PaperWM deja corriendo un timeout de
100 ms × 10 que redimensiona la ventana recién aparecida. **El splash de Discord
se cierra a los ~990 ms**, o sea justo adentro de esa ventana de tiempo: el
`move_resize_frame()` corre sobre una `MetaWindow` que mutter ya está
desmanejando y el shell se cae. Como se cae el shell, se cae la sesión.

Dos guards, los dos en `tiling.js`:

- **El del crash**: si `metaWindow.get_compositor_private()` no devuelve actor, no
  hay ventana viva que redimensionar → `return false`, que es el early exit de
  `Utils.periodic_timeout` y además dispara el `onComplete`, así que el timeout
  tampoco queda colgado en `workspaceChangeTimeouts`. El acceso va en `try`
  porque si el GObject ya fue desalojado, tocarlo tira excepción.
- **Uno de yapa**: `done()` hacía `splice(indexOf(t), 1)` sin chequear, y cuando
  `indexOf` devuelve `-1`, `splice(-1, 1)` **borra el último elemento** — el
  timeout de otra ventana.

Va versionado en `setup/patches/paperwm-timeout-ventana-muerta.patch` y
registrado en `50-extensions.sh`, así que sobrevive a una actualización de
PaperWM desde extensions.gnome.org. Verificado: aplica limpio sobre el
`tiling.js` de fábrica y produce un resultado byte-idéntico al instalado.

### 2. El dock escondía pero no volvía — tres causas, no una

- **La barrera de presión estaba mal puesta.** Iba de `(0,1080)` a `(1920,1080)`,
  el ancho crudo del monitor. Pero DP-3 (2560×1440) arranca en `x=1920`, así que
  **la punta derecha de la barrera caía adentro del otro monitor**, donde
  `y=1080` no es borde de pantalla. Ahora usa
  `Main.layoutManager.getWorkAreaForMonitor()` y recorta 1 px de cada lado, igual
  que `ubuntu-dock`: `(1,1080)-(1919,1080)`. Medido en el journal del sandbox.
- **`_isAnimating` se colgaba en `true`.** Sólo bajaba en el `onComplete` del
  `ease`, y **Clutter no llama `onComplete` cuando la transición se cancela**.
  Con la bandera trabada, `_show()` retornaba para siempre en su primera línea.
  Ahora se resetea en `start()`/`stop()` y cada animación hace
  `remove_all_transitions()` antes de arrancar.
- **Deriva de 20 px por ciclo.** Las animaciones tomaban `container.y` como
  posición de reposo, y como el dock quedaba a media animación, ese valor se iba
  corriendo solo. Ahora usan la Y que manda `_updatePosition()` a través de
  `updateShownY()`, que **era un stub vacío** desde que se escribió.

De paso, la barrera ahora loguea al crearse y al dispararse: antes, si mutter la
rechazaba, fallaba en silencio absoluto.

### 3. La barra de arriba a la derecha, colapsada a un botón

Lo pedido era sacar los cinco iconos de la barra porque su función ya está
adentro del hub. **Medido antes de tocar nada** (con una extensión de volcado
descartable en el sandbox, no leyendo CSS ni mirando la captura): de esos cinco,
**ninguno era un indicador suelto**. Los cinco viven adentro del botón del hub,
en su `panel-status-indicators-box` — red cableada, notificaciones silenciadas,
volumen, perfil de energía y apagado; más unos diez en `w=0`. Todo el resto de
`_rightBox` (grabación de pantalla, compartir pantalla, click por reposo,
accesibilidad, fuente de entrada) ya estaba en `vis=false`.

Por eso esconderlos a secas no servía: el botón quedaba de ancho cero y no había
dónde hacer clic para abrir el hub. Lo que se hace en `panelDeclutter.js` es
esconder **la caja entera** y poner un icono propio en su lugar, los dos
interruptores del Control Center de macOS (`icons/hub-symbolic.svg`, dibujado a
mano porque MacTahoe-dark no trae ese glifo).

Dos cosas que no eran obvias:

- **Se esconde la caja, no cada indicador.** `SystemIndicator` recalcula su
  propio `visible` cada vez que cambia el estado de alguno de sus iconos, así que
  un `hide()` sobre un indicador se deshace solo apenas te conectás a una red o
  movés el volumen. Sobre la caja contenedora no hay nadie que lo revierta.
- **El icono va en el índice 0.** `PanelMenu.ButtonBox` mide y aloca **sólo su
  primer hijo** (`vfunc_get_preferred_width` y `vfunc_allocate` hacen
  `get_first_child()`), sin mirar si está visible. Con el icono agregado al
  final, el botón seguía midiendo los 132 px de la caja escondida y el icono ni
  se alocaba. Puesto primero: **132 px → 60 px**, medido en el sandbox.

El icono es un `Gio.FileIcon` a un archivo `*-symbolic.svg`; el sufijo es lo que
hace que GTK lo recoloree con el color de la barra. El SVG va todo con `fill` y
sin un solo `stroke`, porque el recoloreo de symbolic sólo reemplaza el relleno y
un contorno se quedaría negro sobre una barra clara. **Eso último es lo único de
esta tanda que no se pudo medir y hay que mirar con los ojos después del login.**

`clipboardQuick.js` quedó sólo con el toggle: el mecanismo de esconder
indicadores sueltos (la lista `ESCONDER`) se mudó a `panelDeclutter.js`, que es
el módulo que limpia la barra.

---

## Sesión del 30 de agosto de 2026 (mañana) — el fantasma, cerrado

### Lo que el parche de PaperWM no atajaba

Con unsafe mode habilitado (`Alt+F2` → `lg` → `global.context.unsafe_mode = true`)
se pudo medir el minimizado **en la sesión viva**, sin reiniciar: sondas en el
`WindowActor` desde `org.gnome.Shell.Eval`. La secuencia real al minimizar una
ventana de PaperWM es:

    hide  →  show (minimized ya en true)  →  notify::minimized

y ese `show` se repite **tres veces**. El actor terminaba en `vis=true` con
`min=true` — el fantasma, medido, no deducido. El clone estaba en `false`, así
que la sospecha quedó confirmada: **es el actor real**.

El parche a `showHandler` de PaperWM está bien puesto pero **no llega a correr**
para esas ventanas, así que el guard se mudó a código propio:
`mactahoe-tweaks@son.local/ghostGuard.js`. Regla única: *una ventana minimizada
no se dibuja*. Si el shell está animando el minimizado (`Main.wm._minimizing`)
no esconde nada y reintenta en el próximo idle, para no cortar la animación
nativa si algún día se saca `macos-genie`.

Al restaurar no interfiere, y no es casualidad: ahí el orden se invierte
(`notify::minimized` con false llega **antes** del `show`). Verificado
minimizando y restaurando con el guard puesto.

**Verificación**: cinco ventanas minimizadas a la vez (Steam, Calculadora,
Configuración, terminal, Editor de texto) → las cinco `vis=false`, y los dos
monitores limpios en la captura. La ventana nueva (Editor de texto, abierta
después del guard) también quedó cubierta, vía `window-created`.

El parche `paperwm-show-minimizado.patch` se deja aplicado: es correcto y no
molesta, pero **el que ataja es el guard propio**.

### Portapapeles dentro del hub

`clipboardQuick.js`: la barra tenía un solo icono suelto de verdad —
`ClipboardIndicator`; el resto (Astra Monitor, grabación, accesibilidad, fuente
de entrada) mide 0 y no se ve, y GSConnect ya vive adentro. Ahora ese icono se
esconde y en el hub aparece **Portapapeles**, un `QuickMenuToggle` que lista lo
último copiado leyendo el registro JSON de Clipboard Indicator
(`~/.cache/clipboard-indicator@tudmotu.com/registry.txt`) y copia con
`St.Clipboard`.

Se probó antes la vía obvia —esconder el icono y abrir su menú— y **no sirve**:
un `PopupMenu` no se muestra si su `sourceActor` está oculto. Medido en pantalla,
no supuesto.

### Toggle del dock: ubicación y acción verificadas

- **Ubicación**: se insertó un `QuickToggle` de prueba en el hub vivo con
  `_addItemsBefore(..., qs._darkMode.quickSettingsItems[0], 1)` y se capturó:
  aparece como **Dock · Fijo**, justo antes de "Estilo oscuro". Es la misma ruta
  que usa `quickToggle.js`.
- **Acción**: con `gsettings set … macosdock auto-hide true` el dock desaparece
  de la captura, y con `false` vuelve. O sea que `dockManager` reacciona en
  caliente y el botón sólo tiene que dar vuelta esa gsetting.

### Estado de esta sesión

El guard del fantasma está **activo en caliente** (inyectado por Eval), así que
no hay fantasma ahora mismo. El código de las extensiones —guard, portapapeles y
toggle del dock— entra solo en el **próximo inicio de sesión**, sin apuro: no
hace falta cerrar sesión para trabajar.

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

Antes que nada, que las dos extensiones hayan levantado — si alguna quedó en
ERROR, todo lo de abajo va a fallar por el mismo motivo:

```bash
gnome-extensions info mactahoe-tweaks@son.local | grep -i estado
gnome-extensions info macos-dock@son.local | grep -i estado
```

1. **Que no se caiga la sesión**: abrir Discord tres o cuatro veces. Era el caso
   que reventaba el shell. Si vuelve a pasar, el parche no entró:
   `grep -c "get_compositor_private" ~/.local/share/gnome-shell/extensions/paperwm@paperwm.github.com/tiling.js`
2. **Revelado del dock**: apagar el toggle **Dock** en el hub y empujar el borde
   de abajo. Tiene que volver, y **hay que repetirlo diez veces**: las dos causas
   que quedaban (`_isAnimating` colgado y la deriva de 20 px) no se ven en el
   primer intento, se ven cuando se acumulan. La barrera deja rastro:
   `journalctl --user -b -g "macos-dock"` tiene que mostrar
   `barrera de presión en (1,1080)-(1919,1080)` y un `barrera disparada` por cada
   empujón.
3. **La barra**: `bash setup/shot.sh --crop 1200,0,720,44`. Tiene que haber **un
   solo icono** (dos interruptores apilados) donde había cinco. Lo que hay que
   mirar con atención es **el color**: si sale negro sobre la barra oscura, GTK no
   lo tomó como symbolic y hay que registrar el directorio de iconos en el tema en
   vez de cargarlo por ruta.
4. **Fantasma**: minimizar la terminal, Brave y Discord, una por una. El
   escritorio tiene que quedar limpio. Con evidencia:
   `bash setup/shot.sh --out /tmp/min.png` y mirar el semáforo — si aparecen tres
   círculos grises donde estaba la ventana, el fantasma sigue.
5. **Flatpaks**: si alguna no abre, `systemctl --user restart xdg-document-portal`
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

## Podado de `ESTADO.md` el 31 de agosto de 2026

Relato completo de tres cosas ya cerradas, resumidas allá a una línea:

- **PaperWM ya no tira la sesión al abrir Discord.** Era un SIGSEGV del shell:
  el timeout de `workspace-changed` redimensionaba una `MetaWindow` que mutter
  ya estaba desmanejando, y el splash de Discord se cierra a los ~990 ms, justo
  adentro de esa ventana. Dos guards en `tiling.js`, versionados en
  `setup/patches/paperwm-timeout-ventana-muerta.patch`.
  Verificado el 30/08: cinco rondas de abrir y cerrar Discord, mismo PID del
  shell, cero segfaults, y el journal muestra el splash — o sea que la prueba
  ejercitó el caso real, no uno en el que Discord no llegó a abrir.

- **El dock se esconde de nuevo.** `dockVisibility.js` colgaba
  `enter-event`/`leave-event` de la raíz del dock, que es `reactive: false` a
  propósito — Clutter no manda cruces a un actor no reactivo, así que esos
  handlers eran código muerto y el dock se revelaba una vez y se quedaba visible
  para siempre. Medido: 0 eventos en la raíz contra 4 en el icon box, y el
  `_scheduleHide()` viejo salía sin reagendar. Ahora se reagenda mientras el
  puntero siga encima. Verificado en caliente con `gshell.sh patch`; el archivo
  en `~/.local` ya está, así que el próximo login arranca con esto puesto.

- **Blur my Shell ya no acumula ventanas.** Bug propio de esa extensión, no
  nuestro: `update_all_windows()` sacaba el efecto con `remove_blur()` pero
  dejaba la entrada en `meta_window_map`, y enseguida volvía a registrar todo con
  un `bms_pid` nuevo al azar. Cada cambio de la lista de exclusión sumaba 5
  entradas y no sacaba ninguna (medido: 5 → 10 → 15, la misma ventana 12 veces),
  con sus señales duplicadas encima. Parcheado en sitio y versionado en
  `setup/patches/blur-my-shell-mapa-de-ventanas-que-crece.patch`; queda en 3
  entradas para 3 ventanas, estable a lo largo de seis ciclos. Importa porque el
  toggle nuevo invita a usar justo ese camino.

- **La barra de arriba a la derecha tiene un solo botón**, donde había cinco
  iconos: 132 px → 60 px, medido. Los cinco no eran indicadores sueltos, viven
  adentro del hub, así que se esconde la caja entera y se pone un icono propio.
- **Flatpaks, Discord por `.deb`, fuentes, atajos**: todo cerrado. El detalle en
  `ESTADO-historial.md`.


## RGB — hardware identificado (31/08/2026)

Rescatado de transcripts viejos, que era el único lugar donde vivía. El plan
operativo está en `~/.claude/plans/`, bloque 3.

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


## Dock — evidencia de los tres arreglos (30–31/08/2026)

Resumido en `ESTADO.md`; acá queda la medición completa.

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


## Steam fuera del snap y Windows achicado (31/08/2026)

Resumido en `ESTADO.md`; acá el detalle de cómo se hizo y qué se verificó.

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


## RGB — las tiras BLE no resuelven GATT (01/09/2026)

OpenRGB cubrió placa y GPU sin drama (ver `ESTADO.md`). Las dos tiras
`LEDDMX-03-885E` (`AC:C2:01:7C:88:5E`) y `-815E` (`AC:C2:01:DC:81:5E`) no.

Lo que se comprobó, en orden:

1. Las dos **anuncian**: aparecen en un `bluetoothctl scan on` de 20 s.
2. Siguen `Paired: yes` / `Trusted: yes`, `Connected: no` en reposo.
3. `bluetoothctl connect AC:C2:01:7C:88:5E` **funciona**: `Connected: yes`,
   `Connection successful`, y en `info` figura el servicio esperado
   `0000ffe0-0000-1000-8000-00805f9b34fb`.
4. Pero **`ServicesResolved` nunca aparece** en `info`, y
   `busctl --system tree org.bluez` muestra sólo el nodo
   `/org/bluez/hci0/dev_AC_C2_01_7C_88_5E`, **sin hijos `/serviceXXXX`**. O sea:
   hay link, no hay árbol GATT.
5. Por eso `bleak` muere con `TimeoutError` dentro de `connect()`, tres veces
   seguidas con 30 s de timeout: su backend BlueZ espera `ServicesResolved`.
   `BleakScanner.find_device_by_address()` sí las encuentra — el que falla es el
   connect, no el descubrimiento. También falló `list-attributes` de
   `bluetoothctl menu gatt`, que devuelve vacío por la misma razón.

`bleak` quedó instalado en `setup/bin/rgb/.venv` (no versionado, con
`python3-venv` que hubo que instalar). Los paquetes del protocolo
—`7e 00 05 03 RR GG BB 00 ef` para color, `7e 00 04 f0 …` para on/off— **siguen sin
confirmar**: nunca se llegó a escribir uno.

**Hipótesis a probar primero, no probada:** que el emparejamiento es justamente lo
que traba a estas ELK-BLEDOM, que son BLE abierto y no necesitan parear. Se probaría
con `bluetoothctl remove AC:C2:01:7C:88:5E` y conectando en crudo. No se hizo porque
**destruye el pairing actual** y era mejor dejarlo decidido a mano. Segunda vía si
esa falla: `btmon` en paralelo para ver si el link se cae antes del MTU exchange.


## RGB — el bond era el problema, el protocolo sigue sin salir (01/09/2026)

Continúa la entrada anterior. **La hipótesis del bond era correcta.**

`bluetoothctl remove` sobre las dos tiras, y conectando **sin parear**, la
`AC:C2:01:DC:81:5E` resolvió el árbol GATT de una:

```
servicio 0000ffe0-0000-1000-8000-00805f9b34fb
   char 0000ffe1-…  props=['read', 'write-without-response', 'write', 'notify']
```

O sea que el bloqueo era BlueZ intentando cifrar un link «just works», no la tira.
(La `7C:88:5E` necesitó un segundo `remove`: el primero dijo «removed» pero `info`
seguía mostrándola `Bonded: yes` por caché.)

**Pero las tiras no cambian de color.** Lo importante es que *no es que no lleguen*:
con `write_gatt_char(..., response=True)` el servidor **ACKea las tres familias**, y
`start_notify` se activa sin error. Los bytes entran; la tira no los reconoce.

Formatos probados y descartados, todos contra `ffe1`, confirmado a ojo por el
usuario:

| # | Familia | Paquete |
|---|---|---|
| 1 | ELK-BLEDOM | `7e 00 05 03 RR GG BB 00 ef` |
| 2 | Triones / Zengge | `56 RR GG BB 00 f0 aa` |
| 3 | LEDBLE | `7e 07 05 03 RR GG BB 00 ef` |
| 4 | Lotus Lantern | `7b RR GG BB 00 00 00 bf` |
| 5 | genérico `aa..55` | `aa RR GG BB 55` |
| 6 | SP110E | `38 RR GG BB 83` |
| 7 | Zengge corto | `56 RR GG BB bb` |
| 8 | iDealLED | `a0 RR GG BB` |
| 9 | MohuanLED | `69 96 RR GG BB` |

Un `read` de `ffe1` devuelve `GATT Protocol Error 0x80` (application-specific), y
`notify` no entrega nada: la tira no cuenta su estado, así que **no se puede deducir
el formato leyéndola**.

**Ojo con una idea que no funciona:** `btmon` **no sirve** para capturar lo que manda
la app del celular. Captura el tráfico del adaptador de esta PC, no el enlace entre
el teléfono y la tira; para eso haría falta un sniffer BLE aparte.

**El camino que queda, y es determinista:** el registro HCI de Android. Opciones de
desarrollador → «Habilitar registro de Bluetooth HCI» → apagar y prender el
Bluetooth → usar la app *LED Lamp* haciendo rojo / verde / azul / apagar-prender →
Opciones de desarrollador → «Informe de errores», que trae el `btsnoop_hci.log`
adentro del zip. Ahí están los bytes exactos. El usuario tiene iPhone (que no permite
sacar ese log sin una Mac) pero consigue un Android prestado.

**Dato del usuario que va a importar al decodificar:** en la configuración de la app,
el orden de color está en **GRB**, no RGB. Así que en los paquetes capturados el
primer byte de color es el verde.
