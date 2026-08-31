# Kit de setup para Ubuntu 24.04 en adelante

Scripts para dejar Ubuntu con aspecto de macOS, más rápido, con los drivers de
video completos y con el entorno de desarrollo listo.

Escrito y verificado en **24.04**. Funciona en versiones posteriores (26.04
incluida): el kit no depende de nombres de paquete fijos — detecta si un paquete
no existe o pasó a ser virtual y se adapta. Pero **no está probado ahí**, así que
en una versión distinta de 24.04 empezá con `--dry-run`.

> **Corré esto sentado frente a la PC.** El modo agresivo toca GRUB (el
> arranque) y elimina snapd. Si algo sale mal vas a necesitar la pantalla y el
> teclado. No lo corras por SSH desde el celular.

## Empezá por acá

Si ya seguiste algún tutorial de "Ubuntu como macOS" y te quedó lento, **no
instales nada encima todavía**. Primero averiguá qué te está frenando:

```bash
bash setup/doctor.sh
```

Solo lee, no modifica nada, no necesita `sudo`. Te dice qué está mal y en qué
orden atacarlo. Al final imprime un bloque `=== PEGAR A CLAUDE ===` que podés
copiar y mandarme.

## Uso

```bash
# 1. Ver qué haría, sin tocar absolutamente nada
bash setup/install.sh --dry-run --all --aggressive

# 2. Si te convence, hacerlo de verdad
bash setup/install.sh --all --aggressive

# 3. Cerrar sesión y volver a entrar (obligatorio para temas y extensiones)
```

También podés correr módulos sueltos:

```bash
bash setup/install.sh --theme --extensions   # solo la parte visual
bash setup/install.sh --dev                  # solo Node, VS Code y terminal
```

`bash setup/install.sh --help` lista todo.

## Qué hace cada módulo

| Módulo | Qué hace |
|---|---|
| `--base` | Actualiza el sistema, instala utilidades y configura Flatpak + Flathub |
| `--limpieza` | Saca docks duplicados, Plank/Conky y temas instalados con `sudo` |
| `--gpu` | Detecta la GPU e instala Mesa, Vulkan y aceleración de video |
| `--perf` | swappiness, zram, servicios de arranque, indexado*, GRUB* |
| `--desnap` | Firefox nativo `.deb` y elimina snapd por completo* |
| `--theme` | Apariencia macOS. Si ya tenés MacTahoe puesto, solo completa iconos y cursores; si no hay nada, instala WhiteSur entero |
| `--extensions` | MacOS Dock, Blur my Shell, `mactahoe-tweaks`, bandeja y atajos |
| `--dev` | Node vía nvm, VS Code, `rg`/`fzf`/`bat`/`btop`/`eza`/`zoxide`, git |
| `--claude` | Claude Code CLI y un `CLAUDE.md` para el repo |

`*` requiere `--aggressive`.

## Sobre `--theme` y tu configuración actual

El módulo mira qué tema GTK tenés aplicado antes de tocar nada:

- **Ya usás algo de la familia MacTahoe** (macOS 26) → instala solo los iconos y
  los cursores que combinan. No toca `gtk-theme`, ni el modo oscuro, ni la
  fuente. Eso es tuyo y ya lo elegiste.
- **No hay nada estilo macOS** → instala WhiteSur completo (tema, iconos,
  cursores, fuentes).

Antes pisaba siempre con WhiteSur-Light, lo que te sacaba del modo oscuro y te
cambiaba la fuente sin avisar.

## Correrlo sin terminal

Si lo lanzás desde un editor, un agente o un pipe, tené en cuenta dos cosas:

- Las preguntas se contestan que **no** si no hay entrada disponible, y el script
  lo dice en vez de cancelarse en silencio. Para responder que sí a todo: `--yes`.
  Para responder distinto a cada una: `{ echo s; yes n; } | bash setup/install.sh --perf`
- Los módulos que necesitan `sudo` abren una ventana gráfica de contraseña que
  hay que responder **a mano, frente a la pantalla**. `--theme` sobre un tema ya
  instalado no pide nada.

## Banderas

| Bandera | Qué hace |
|---|---|
| `--dry-run` | Imprime cada comando sin ejecutar nada. Empezá siempre por acá. |
| `--aggressive` | Habilita GRUB, indexado y quitar snapd |
| `--yes` | Responde que sí a todo (no interactivo) |

## Cómo revertir

Cada corrida guarda copias de todo lo que modifica en
`~/.setup-ubuntu-backups/<fecha>/`.

```bash
bash setup/undo.sh --list     # ver las corridas guardadas
bash setup/undo.sh            # revertir la última
bash setup/undo.sh 20260826-1430   # revertir una en particular
```

`undo.sh` restaura los archivos de sistema, reactiva los servicios, regenera
GRUB y te ofrece devolver **toda la configuración del escritorio** (tema,
iconos, dock, atajos) a como estaba: antes de tocar nada se guarda un volcado
completo con `dconf dump`. Lo que no revierte solo (reinstalar snapd, quitar el tema) lo imprime al
terminar, con los comandos exactos.

**Si el equipo no arranca después de tocar GRUB:** en el menú de arranque elegí
*Advanced options* → una versión anterior del kernel, entrá y corré
`bash setup/undo.sh`.

## "Seguí un tutorial y me quedó lento"

Es el resultado más común de los videos de "Ubuntu como macOS", y casi nunca es
culpa del tema. Son tres causas, en este orden de impacto:

**1. Estás dibujando con la CPU en vez de con la placa de video.** Si el driver
no quedó bien, GNOME compone por software (`llvmpipe`). Es invisible —no da
ningún error, solo va lento— y ningún cambio de tema lo va a arreglar. El
`doctor.sh` lo detecta y lo marca como CRÍTICO.

**2. Tenés varios docks activos a la vez.** Los tutoriales hacen instalar Dash
to Dock o Dash to Panel, pero nadie apaga el `ubuntu-dock` que Ubuntu ya trae.
Quedan dos o tres dibujando su propia barra y compitiendo por los mismos
eventos del mouse.

**3. Procesos de más corriendo de fondo.** Plank, Conky y Cairo-Dock quedan en
el autostart consumiendo GPU todo el tiempo, aunque no los uses.

Un cuarto problema que no se nota hasta que actualizás: los tutoriales instalan
el tema con `sudo` en `/usr/share/themes`, que es una carpeta del sistema. Cada
actualización de Ubuntu lo pisa o lo rompe. Lo correcto es `~/.themes`.

### Orden para arreglarlo

```bash
bash setup/doctor.sh                          # 1. ver qué pasa
bash setup/install.sh --gpu                   # 2. aceleración por hardware
bash setup/install.sh --limpieza              # 3. sacar lo duplicado
bash setup/install.sh --theme --extensions    # 4. aplicar el look, ya limpio
# 5. cerrar sesión y volver a entrar
```

El orden importa: si empezás por el tema sin resolver el punto 1, vas a quedar
igual de lento pero con otro tema encima.

### En Ubuntu 26.04 y GNOME 50

Algunas extensiones tardan meses en tener versión para un GNOME recién salido.
Si el módulo `--extensions` te avisa que alguna "no tiene versión compatible", no
es un error del script: todavía no existe. Volvé a correrlo más adelante.

El indexador de archivos cambió de nombre: desde GNOME 47 `tracker3` se llama
`localsearch`. El módulo `--perf` maneja los dos juegos de nombres.

### Sobre el blur

Blur my Shell es lo que más cuesta por cuadro de todo lo que instalan estos
tutoriales: obliga a recomponer zonas enteras de la pantalla constantemente. Si
falta fluidez, el orden para ir apagando componentes es `applications` (blur
dinámico por ventana, el más caro), después `overview`, y recién al final el
resto.

**La barra superior: la trampa del `!important` de Yaru.** Ubuntu 26.04 trae
esta regla en `/usr/share/gnome-shell/theme/Yaru/gnome-shell-dark.css`:

```css
#panel { background-color: #131313 !important; }
```

Ese `!important` le gana a `#panel { background-color: transparent }` de
MacTahoe **pase lo que pase**: en la cascada CSS, un `!important` de autor vence
a cualquier declaración normal, sin importar el orden de las hojas ni cuál se
cargue después. Resultado: la barra se ve gris oscuro fijo aunque el tema pida
transparencia. Medido con `setup/shot.sh --probe`: `RGB(19,19,19)` = `#131313`,
plano, sin importar qué haya de fondo.

Y por lo mismo **el componente `panel` de Blur my Shell tampoco puede hacer
nada**: pone la transparencia con la clase `#panel.transparent-panel`, que es
una declaración normal y pierde igual. Prenderlo no arregla nada.

Lo único que gana, sin editar archivos de `/usr` que la próxima actualización
volvería a pisar, es el **estilo inline del actor**: St lo agrega al final de las
propiedades del `StThemeNode`, después de todas las hojas. Eso hace
`panelStyle.js` de `mactahoe-tweaks`, y por eso el fondo de la barra se
configura ahí y no en Blur my Shell.

**Blur my Shell no puede blurear los menús del panel.** Sus componentes son
panel, overview, dock, lockscreen, appfolders, screenshot y window-list — no hay
ninguno de menús, y v72 es la última versión que existe para GNOME 50. Tampoco
sirve el tema: St no expone ninguna propiedad de blur por CSS. Por eso el hub de
Quick Settings lo cubre `mactahoe-tweaks` (abajo).

**El blur de ventanas no es la vibrancy de macOS**, pero sí se ve. En macOS el
desenfoque lo pinta la propia app (AppKit); GNOME no tiene ese API, así que el
componente `applications` dibuja un rectángulo borroso *detrás* de la ventana y
baja la opacidad del actor. Eso alcanza para que una Calculadora o un Nautilus se
vean translúcidos.

Lo que lo rompía era `dynamic-opacity`. Con esa clave en `true`, Blur my Shell
vuelve **sólida la ventana que tiene el foco** — está literal en su código,
`components/applications.js:134`:

```js
// make the currently focused window solid
if (global.display.focus_window) this.set_focus_for_window(...)
```

O sea que el efecto sólo se veía mientras la ventana *no* estaba enfocada: por
eso parecía "durar unos segundos" y desaparecer al volver a ella. El kit la deja
en `false`.

### La extensión propia: `mactahoe-tweaks@son.local`

Vive en `setup/extensions/` y el módulo la copia a
`~/.local/share/gnome-shell/extensions/`. No viene de extensions.gnome.org
porque no hay nada publicado que haga estas tres cosas:

- **El fondo de la barra superior**, por encima del `!important` de Yaru
  (explicado arriba). `panelStyle.js` pone el color con `Main.panel.set_style()`
  y lo vuelve a poner en `style-changed` y al entrar y salir de actividades,
  porque en esas transiciones el shell recalcula el theme node y el inline se
  pierde. Un candado evita el bucle infinito, ya que `set_style()` dispara
  `style-changed`. Se configura con tres claves:
  `panel-background`, `panel-blur-radius` (0 lo apaga) y `panel-blur-brightness`.
- **Blur en los menús del panel** (Quick Settings, calendario, indicadores).
  Encadena dos efectos sobre `menu.box`: `Shell.BlurEffect` en modo `BACKGROUND`
  desenfoca lo que hay detrás, y un `CornerEffect` propio recorta el resultado a
  la caja redondeada del tema. El segundo no es un lujo: `Shell.BlurEffect`
  desenfoca el rectángulo entero de la asignación del actor, sin enterarse del
  `border-radius` ni de los márgenes, así que sin recortar se vería un cuadrado
  borroso asomando por las esquinas del menú.
  Su `stylesheet.css` además baja la opacidad de `.popup-menu-content`: MacTahoe
  lo deja al 92% y con ese fondo el desenfoque queda tapado.
- **`Super+Space` salta entre el escritorio 1 y el 2.** GNOME no tiene un atajo
  nativo de "alternar entre dos escritorios" (solo "ir al N" y "ir al último"), y
  en Wayland un comando externo no puede cambiar de escritorio porque
  `org.gnome.Shell.Eval` está bloqueado fuera de unsafe-mode. Desde adentro del
  shell es trivial. El módulo libera antes el `<Super>space` que reclama ibus.

  El atajo se registraba bien (`addKeybinding` devuelve una acción válida) pero no
  hacía nada, y la razón era el timestamp: `meta_workspace_activate()` descarta la
  petición **en silencio** si le pasás 0, y `global.get_current_time()` devuelve 0
  cuando no hay un evento en curso. Ahora cae a
  `global.display.get_current_time_roundtrip()` cuando eso pasa. La extensión
  loguea qué hace en cada paso; se lee con `setup/watch-shell.sh`.

Para revertirla: `bash setup/undo.sh` la desactiva y borra la carpeta.

### El fork del dock: `macos-dock@son.local`

MacOS Dock (vinnytherobot) es la única extensión publicada con magnificación de
iconos al pasar el cursor, que es el gesto que distingue al Dock de macOS — Dash
to Dock no la tiene. Pero la v7 tiene bugs que se ven, así que en
`setup/extensions/` vive un fork parcheado con UUID propio.

**Contrapartida, que es real:** al tener otro UUID no recibe actualizaciones de
extensions.gnome.org. Si sale una v8, hay que rehacer el fork a mano. Los dos
comparten el schema `org.gnome.shell.extensions.macosdock`, así que se puede
volver al original sin perder la configuración:

```bash
gnome-extensions disable macos-dock@son.local
gnome-extensions enable macos-dock@vinnytherobot.github.io
```

Qué arregla el fork:

- **El icono agrandado ya no se sale del rectángulo.** Era el bug más visible.
  La magnificación escala los actores con `scale_x`/`scale_y`, y escalar **no**
  cambia la asignación: el contenedor medía exactamente el alto del rectángulo,
  así que un icono al 1.4× se salía ~26 px por arriba. Ahora son tres actores en
  vez de uno — un contenedor transparente y más alto, el rectángulo redondeado
  pegado abajo, y la fila de iconos encima sin recortar — y los iconos crecen
  hacia la holgura, igual que en macOS, donde el icono sube por encima de la
  barra.
- **El desenfoque respeta el `border-radius`.** `Shell.BlurEffect` desenfoca el
  rectángulo completo de la asignación; sin recorte se veía un cuadrado borroso
  asomando por las cuatro esquinas del dock. Usa el mismo `CornerEffect` que los
  menús.
- **La magnificación no se desincroniza.** Las escalas se guardaban en un array
  indexado por posición que nunca se achicaba: al abrir o cerrar una app el orden
  de los hijos cambiaba y la escala de un icono terminaba aplicándose a otro,
  dejando iconos agrandados sin cursor encima. Ahora es un `WeakMap` por actor.
- **Deja de correr a 60 fps para siempre.** El bucle de animación era un
  `GLib.timeout_add` permanente que despertaba el proceso 60 veces por segundo
  aunque el cursor estuviera del otro lado de la pantalla. Ahora arranca con el
  movimiento del puntero y se apaga solo cuando no queda nada que animar.
- **Los iconos que se van se destruyen.** Se los sacaba del contenedor con
  `remove_child()` y quedaban vivos y huérfanos, con sus señales colgando. Y si
  la app volvía a arrancar durante los 200 ms del fundido, aparecían dos iconos
  de la misma app.
- **`Super+3` cae en la tercera app.** El separador y el botón de aplicaciones
  también son hijos del contenedor y se colaban en la lista que usan los atajos.
- **Las señales de actores muertos no se desconectan.** El `SignalManager`
  llamaba `disconnect()` sobre objetos ya liberados y GJS escupía
  `Object St.BoxLayout ... has been already disposed` con stack trace en el
  journal.
- **El dock ahora escucha los cambios de favoritos.** `iconManager.js` sólo
  conectaba `installed-changed` del `Shell.AppSystem`, nunca
  `changed::favorite-apps` de `org.gnome.shell`. O sea que la lista de
  favoritos se releía **únicamente** cuando se instalaba o desinstalaba una
  app: anclar algo desde Ajustes o desde el Overview no hacía nada visible
  hasta el siguiente `apt install`. Se descubrió migrando Discord de snap a
  `.deb`, cuando el favorito nuevo (`discord.desktop`) no aparecía en el dock.
  Lo que lo vuelve difícil de ver es que `_reload()` hace
  `lookup_app(appId)` y sigue de largo con `continue` si devuelve `null`: un
  favorito que apunta a un `.desktop` que ya no existe **desaparece en
  silencio**, sin una línea en el journal. El síntoma parece del dock y la
  causa está en la lista de favoritos.

### La trampa del `GTypeName` duplicado

`cornerEffect.js` está **duplicado a propósito** en las dos extensiones propias:
`mactahoe-tweaks@son.local/cornerEffect.js` y
`macos-dock@son.local/lib/cornerEffect.js`. Son el mismo shader y hasta el 28 de
agosto de 2026 eran byte a byte idénticos — incluido el `GTypeName`. Eso rompía
el dock entero:

```
Extension macos-dock@son.local: Error: Type name MacTahoeTweaksCornerEffect is already registered
```

**Todas las extensiones de GNOME Shell corren en el mismo contexto de GJS y
comparten un único registro de tipos GObject.** El nombre de tipo es global al
proceso, no al archivo ni a la extensión. `mactahoe-tweaks` carga primero y
registra el tipo; cuando le toca al dock, la excepción salta al **importar el
módulo**, antes de `enable()`, y la extensión queda en estado `ERROR` sin
dibujar nada.

Lo peor es cómo se ve desde afuera: no parece un error, parece que el dock "no
está configurado". Y como el fork esconde el Dash del Overview justamente dentro
de `enable()` (`_hideDefaultDash()`), el Dash grande de GNOME se queda visible —
así que al apretar `Super` aparece "un dock enorme" que en realidad es el Dash.
Dos síntomas, una sola causa.

Si alguna vez volvés a copiar un archivo con `GObject.registerClass` de una
extensión a otra: **renombrá el `GTypeName`**. Los UUID distintos no alcanzan.

### El efecto de minimizar que impedía minimizar

Del 29 de agosto de 2026. Síntoma reportado: "Brave se cuelga y no puedo cerrar
la pestaña". Síntoma real, al preguntar de nuevo: **ninguna ventana de ninguna
aplicación se minimizaba** — Discord, Steam, la terminal, Brave. El navegador
no tenía nada que ver.

La culpable era `compiz-alike-magic-lamp-effect` (v24), el efecto genio.
Empieza por secuestrar el completado de la minimización:

```js
// compiz-alike-magic-lamp-effect/extension.js:57-65
Main.wm._shellwm.original_completed_minimize = Main.wm._shellwm.completed_minimize;
Main.wm._shellwm.completed_minimize = function(actor) { return; };
```

Desde ahí GNOME **ya no completa la minimización por su cuenta**: queda
enteramente a cargo de que el efecto de la extensión termine y llame a
`original_completed_minimize(actor)`. Es un diseño sin red: cualquier excepción
en el camino deja la ventana colgada para siempre.

Y la excepción llegó. Su handler de `minimize` llama a `getIcon()`, que en la
línea 133 hace `Main.overview.dash._redisplay()`:

```
JS ERROR: TypeError: can't access property "ensure_style", firstIcon.icon is null
    getIcon@.../compiz-alike-magic-lamp-effect/extension.js:133:32
    enable/this.minimizeId<@.../extension.js:73:29
```

`firstIcon` es un símbolo interno del Dash de GNOME, no de la extensión: la
excepción nace dentro de `_redisplay()`. **El Dash está oculto porque nuestro
fork del dock lo esconde** en `_hideDefaultDash()`, y un Dash oculto no
construye sus iconos. La excepción corta el handler antes de
`add_effect_with_name()`, nadie llama al `completed_minimize` original, y la
ventana no se minimiza. Nunca. En ninguna app.

Es la misma forma que la trampa del `GTypeName`: dos extensiones que se pisan,
y el síntoma aparece a kilómetros de la causa.

**El reemplazo: `macos-genie@thuongvo.dev`**, que se instala desde git con
`instalar_extension_git` porque no está publicada en extensions.gnome.org.
Las tres razones por las que es un reemplazo y no otro tiro al aire:

1. Su `metadata.json` declara `shell-version: ["50"]` — nuestra versión exacta.
2. **No toca el Dash.** Cero referencias a `Main.overview.dash`.
3. **Llama a `completed_minimize` siempre, incluso dentro del `catch`**, con un
   flag para no llamarlo dos veces. Aunque el efecto falle, la ventana se
   minimiza. Es justo la red que le faltaba al anterior.

**Y del lado del dock: `publishIconGeometries()`** en `lib/iconManager.js`.
Todas estas animaciones arrancan por `meta_window.get_icon_geometry()` para
saber hacia dónde animar, y si nadie la publicó devuelven `false` — ahí es donde
magic-lamp caía al camino que hurgaba el Dash. Nuestro dock ahora publica la
posición en pantalla de cada icono, así que el genio apunta al icono real en vez
de al centro de la pantalla, y ese camino roto ya no se recorre.

Se llama desde `_refreshAllIndicators()`, que ya se disparaba al cambiar el foco
y al abrirse o cerrarse ventanas — no en cada frame de la magnificación, que
sería tirar trabajo a 60 fps para nada: cuando minimizás, el mouse está en la
ventana, no sobre el dock.

La referencia de cómo hacerlo es `ubuntu-dock/appIcons.js:405`
(`updateIconGeometry`), incluido el guard que importa:

```js
// Fuera del stage, la posición y el tamaño que reporta el actor son valores
// basura que pueden exceder el rango de int y reventar el Rectangle.
if (!this._container.get_stage())
    return;
```

### Fuentes: el ajuste que mentía

`40-theme.sh` seteaba `Inter 11` y `Fira Code 11` desde el primer día, pero
**nunca instalaba ninguna de las dos**. El resultado es peor que un error:

```bash
$ gsettings get org.gnome.desktop.interface font-name
'Inter 11'                 # ← dice Inter
$ fc-list | grep -c Inter
0                          # ← no está instalada
```

**Pango no avisa cuando no encuentra una familia**: cae al fallback (Noto Sans)
en silencio. Así que el ajuste quedaba puesto, la pantalla mostraba otra fuente,
y `gsettings get` confirmaba la versión equivocada. Por eso "la fuente sigue en
`Ubuntu Sans`" estuvo semanas como pendiente sin que nadie viera por qué.

Ahora `theme_instalar_fuente_github()` las baja de sus releases de GitHub a
`~/.local/share/fonts` (sin sudo, así funciona en cualquier máquina), y
`theme_set_fuente()` **le pregunta a Pango si la familia resuelve antes de
setearla**. Si no resuelve, avisa en vez de mentir:

```bash
note_warn "Pango no resuelve 'X' — dejo la clave como estaba"
```

Dos trampas concretas que costaron encontrar:

1. **`'Inter Semi Bold 11'` (con espacio) no lo resuelve Pango** y cae a Noto
   Sans Bold. El que funciona es `'Inter SemiBold 11'`. `fc-list` muestra la
   familia como `Inter SemiBold`, pero eso no garantiza que Pango la acepte
   escrita de cualquier forma — hay que preguntarle a Pango, no a fontconfig.
2. En el patrón de `jq test()`, el escape va con **una sola** barra:
   `'^Inter-.*\.zip$'` matchea `Inter-4.1.zip`; con `\\.` no matchea nada y la
   descarga se saltea en silencio.

Para verificar a mano qué carga Pango de verdad:

```bash
python3 -c "
import gi; gi.require_version('Pango','1.0'); gi.require_version('PangoCairo','1.0')
from gi.repository import Pango, PangoCairo
fm = PangoCairo.FontMap.get_default()
f = fm.load_font(fm.create_context(), Pango.FontDescription.from_string('Inter 11'))
print(f.describe().to_string())"
```

### Las extensiones que se sumaron el 29 de agosto

Las cuatro se verificaron contra GNOME 50 **antes** de instalarlas, consultando
la API de extensions.gnome.org, y se probaron todas juntas en
`setup/shell-sandbox.sh` antes de tocar la sesión real:

| Extensión | Para qué |
|---|---|
| `paperwm` | Tiling scrollable: el gesto de niri sin dejar GNOME |
| `rounded-window-corners@fxgn` | Esquinas redondeadas en todas las ventanas |
| `clipboard-indicator` | Historial de portapapeles (el `Win+V` de Windows) |
| `gsconnect` | El celular integrado |

**Pano quedó descartada** aunque es la mejor de las de portapapeles: su última
versión soporta GNOME 45. La API lo dice sin ambigüedad, y consultarla cuesta
menos que instalar algo que no va a arrancar:

```bash
curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=pano@elhan.io&shell_version=50" \
  | jq -r '.shell_version_map | keys | join(",")'
```

**GSConnect necesita `wl-clipboard`.** Sin `wl-paste` en el PATH tira, al
arrancar:

```
JS ERROR: GLib.SpawnError: Falló al ejecutar el proceso hijo «wl-paste»
```

Lo cazó el sandbox. Es exactamente para eso que existe: el error no rompe la
extensión (queda `ACTIVE`), sólo desactiva el portapapeles compartido — el tipo
de falla que en la sesión real no se nota hasta que la necesitás.

**Y una advertencia sobre PaperWM**: es la más invasiva del conjunto, cambia el
manejo de ventanas entero. Si molesta:

```bash
gnome-extensions disable paperwm@paperwm.github.com
```

### Los parches locales a PaperWM

PaperWM es de terceros, así que no hay fork con UUID propio como con el dock: se
parchea **en sitio**, sobre `~/.local/share/gnome-shell/extensions/paperwm@…`, y
el diff queda guardado en `setup/patches/` para poder reaplicarlo después de una
actualización. Cada parche lleva un comentario `PARCHE LOCAL` en el código.

| Parche | Qué arregla |
|---|---|
| `paperwm-initworkspaces-race.patch` | El callback D-Bus de `upgradeGnomeMonitors` corriendo contra un `Spaces` ya destruido |
| `paperwm-scratch-clone-fantasma.patch` | La "ventana fantasma" al minimizar |

**La ventana fantasma.** Al minimizar cualquier ventana quedaba dibujada una
copia sobre el escritorio, con los tres botones del título en gris; se podía
hacer click en ella pero no escribir, y arrastrarla a un costado la hacía
desaparecer. Además, al querer restaurarla desde el dock, el icono rebotaba y el
puntero se iba al otro monitor.

La causa está en `scratch.js`. Al minimizar, PaperWM manda la ventana al scratch
layer (`minimizeHandler` → `makeScratch`), y ahí hacía:

```js
if (!metaWindow.minimized)
    Tiling.showWindow(metaWindow);
```

`showWindow` hace **dos** cosas: esconde el `cloneActor` que PaperWM dibuja en su
`cloneContainer` y vuelve a mostrar el actor real. Saltearla entera cuando la
ventana está minimizada sólo era correcto para la segunda mitad. El clone se
quedaba visible y con `cloneActor.source` apuntando al actor — y un
`Clutter.Clone` **pinta su fuente aunque el original esté oculto**. De ahí la
copia dibujada, y de ahí que los botones estuvieran grises: no era la ventana,
era su retrato, sacado en el instante en que perdió el foco.

Un solo clone huérfano explicaba los dos síntomas, porque `isWindowAnimating()`
se define justamente como "el clone está visible":

- `tiling.js:4777` (`showHandler`) — con eso en `true`, cada intento de mostrar
  la ventana llamaba a `animateWindow()`, que la vuelve a esconder y muestra el
  clone. Ese era el bucle que mantenía vivo al fantasma.
- `tiling.js:4166` — al reinsertar la ventana en el tiling tomaba la posición
  **del clone** en vez del `frame_rect` real, así que aterrizaba en el space del
  monitor equivocado y `focus_handler` warpeaba el puntero hasta allá.

El arreglo suelta el clone sin tocar el actor real, que es lo único que la rama
minimizada necesitaba. Mismo patrón que la trampa del `GTypeName`: una causa,
dos síntomas lejos de ella.

Se bisecó antes de escribir una línea — `gnome-extensions disable
paperwm@paperwm.github.com`, minimizar, ver si el fantasma seguía — porque el
código solo no distinguía entre PaperWM y `macos-genie`, que también toca el
minimizado.

### El dock siempre visible

Una advertencia que no es un bug: el dock **siempre visible** (`auto-hide false`)
no le reserva espacio a las ventanas, porque vive en el "top chrome" del shell y
no es un panel. Una ventana maximizada le pasa por debajo. Es el mismo
comportamiento que macOS con "ocultar el Dock" desactivado.

### Tamaño de los iconos

`icon-size` y `magnification-scale` están atados: el icono magnificado mide
`icon-size × magnification-scale`. Hoy son **40 × 1.3 = 52 px** de pico, con 40 px
en reposo.

El alto del rectángulo **no se configura aparte**: sale de `icon-size`
(`dockManager.js`, `_dockHeight = icon-size + 16 + 8`), o sea 64 px con 40. La
holgura que necesita el icono magnificado para no salirse es otra cosa más
(`_magnificationHeadroom`) y se recalcula sola. Por eso subir `icon-size` engorda
la barra entera, no sólo los iconos.

Ojo también con el schema: arrastra, del fork de Dash to Dock del que nació, un
montón de claves `org.gnome.shell.extensions.dash-to-dock` (`autohide`,
`dock-fixed`, `intellihide`...). **Están muertas** — `dockManager.js` sólo lee
`macosdock`. Tocarlas no hace nada, y es una pérdida de tiempo garantizada.

### Ver lo que estás cambiando

Ajustar el escritorio a ciegas es la razón por la que dos de los diagnósticos
anteriores de este repo estaban equivocados: el CSS decía `transparent` y el
píxel decía `#131313`. Hay tres scripts para no repetirlo.

```bash
bash setup/shot.sh                          # captura de pantalla completa
bash setup/shot.sh --wait 6                 # espera 6s: te da tiempo a poner el
                                            #  cursor sobre el dock
bash setup/shot.sh --crop 560,970,800,110   # recorta x,y,ancho,alto (y escala x2)
bash setup/shot.sh --probe 300,0,60         # imprime el RGB de una columna
```

En Wayland no hay forma directa de leer la pantalla desde una terminal: `grim`
responde `compositor doesn't support wlr-screencopy` (eso es de wlroots, GNOME no
lo implementa) y llamar a `org.gnome.Shell.Screenshot` por D-Bus devuelve
`AccessDenied`, porque el shell sólo se lo permite a un puñado de nombres de bus
privilegiados. Lo que sí funciona es pedírselo al **portal de escritorio**, que
es la vía de las apps de Flatpak; la primera vez GNOME pide permiso y después se
acuerda.

```bash
bash setup/shell-sandbox.sh mactahoe-tweaks@son.local
bash setup/shell-sandbox.sh --seconds 20 macos-dock@son.local
```

Levanta un **GNOME Shell 50 aparte**, headless, con su propio bus de D-Bus y su
propio dconf, cargando sólo las extensiones que le pases desde este repo. Si algo
explota en `enable()`, explota ahí y no en tu sesión. Devuelve los errores de JS y
los `console.log` de las extensiones. Es la única forma de probar un cambio sin
cerrar sesión: en Wayland `Alt+F2 r` no existe, y desde GNOME 50 el
`ReloadExtension` de D-Bus responde `ReloadExtension is deprecated and does not
work`.

```bash
bash setup/watch-shell.sh          # journal del shell, filtrado, en vivo
bash setup/watch-shell.sh --boot   # todo lo de este arranque
```

Una extensión rota no avisa: `gnome-extensions info` sigue diciendo `ACTIVE`
aunque `enable()` haya tirado a mitad de camino. Lo único que lo cuenta es el
journal.

```bash
bash setup/gshell.sh check                 # ¿unsafe mode prendido?
bash setup/gshell.sh find macos-dock-root  # un actor: posición, tamaño, visible
bash setup/gshell.sh tree 2                # árbol de actores visibles
bash setup/gshell.sh pointer 960 400       # mover el puntero
bash setup/gshell.sh push bottom           # empujar un borde hasta la barrera
```

Le habla al shell **que está corriendo**, sin cerrar sesión. Todo pasa por
`org.gnome.Shell.Eval`, que sólo responde con unsafe mode habilitado
(`Alt+F2` → `lg` → `global.context.unsafe_mode = true`, y se apaga con el logout).

Existe porque cada sesión que necesitó mirar el escritorio volvió a tropezar con
las mismas tres cosas: el escapado de gdbus (el JS viaja en base64, si no cualquier
comilla lo rompe con `unknown keyword`), que **`imports.ui.main` no funciona**
porque la UI del shell es ESM y hay que llegar a los objetos caminando
`global.stage`, y que en Wayland el puntero **sólo** se mueve con el dispositivo
virtual de Clutter — `xdotool`, `wtype` y `ydotool` no sirven.

Ojo con la diferencia: el árbol de actores dice qué **cree** el shell, no qué se
dibujó. Para píxeles, `shot.sh`.

## Decisiones que quizás te sorprendan

**No instala el driver propietario de AMD.** En Ubuntu 24.04 el stack open
source (`amdgpu` en el kernel + Mesa) es el recomendado: para escritorio y
juegos rinde igual o mejor, y el instalador propietario de AMD es la causa
número uno de sistemas que arrancan sin entorno gráfico. Mesa en 24.04 ya viene
en la versión 25.x, así que tampoco hace falta ningún PPA externo. El driver
propietario solo tiene sentido para ROCm (cómputo/IA) o software profesional
certificado.

**No pone `mitigations=off` en GRUB.** Es lo que recomienda medio internet para
"acelerar Ubuntu", pero desactiva las mitigaciones de Spectre/Meltdown a cambio
de unos pocos puntos porcentuales. En la máquina donde estudiás y guardás tus
cosas no vale la pena. Si aun así lo querés, agregalo a mano en
`/etc/default/grub` y corré `sudo update-grub`.

**No descarga la fuente SF Pro de Apple.** No es redistribuible. Usa
[Inter](https://rsms.me/inter/), que es libre y prácticamente idéntica.

**El tema no llega a todas las apps.** Las apps nativas de GNOME (Archivos,
Configuración, Calculadora, Calendario) usan libadwaita, que ignora los temas
GTK a propósito. Van a seguir viéndose como GNOME. No es un fallo del script ni
algo que se pueda arreglar con otro tema: es cómo funciona GNOME desde la
versión 43.

**El dock es MacOS Dock, no Dash to Dock.** Dash to Dock no hace el zoom de
iconos al pasar el mouse, que es el gesto que distingue al Dock de macOS, y
`ubuntu-dock` es un fork viejo suyo con menos opciones todavía. La única
extensión publicada que implementa la magnificación es
[MacOS Dock](https://github.com/vinnytherobot/MacOSDock). Es joven (v7), así que
si no convence: `gnome-extensions disable macos-dock@vinnytherobot.github.io` y
`gnome-extensions enable ubuntu-dock@ubuntu.com`. A cambio se pierde la papelera
en el dock, que MacOS Dock no muestra.

## Qué se probó y qué no

Los scripts se escribieron y verificaron en un contenedor con **Ubuntu 24.04.4
Noble**:

- Sintaxis (`bash -n`) y `shellcheck -S warning`: limpio en los 13 archivos.
- Simulación completa (`--dry-run --all --aggressive`), sin efectos en disco.
- **Clasificación de paquetes** (`REAL` / `VIRTUAL` / `INEXISTENTE`), probada
  contra paquetes reales de cada clase: `ripgrep` y `mesa-vulkan-drivers`
  (reales), `awk` y `mail-transport-agent` (virtuales), un nombre inventado y
  `libgl1-mesa-glx` (obsoleto, sin proveedores).
- **Resistencia a nombres que cambian entre versiones**: con un paquete
  inexistente mezclado en el lote, `apt-get install` directo falla y no instala
  nada; `apt_install` avisa, lo saltea e instala el resto. Comprobado de verdad
  instalando y desinstalando.
- `doctor.sh` corriendo **sin escritorio, sin GPU y sin `glxinfo`, `gsettings`,
  `dconf` ni `gnome-extensions`**: completa el informe y sale con código 0.
- La función que decide si estás en renderizado por software, probada con 9
  cadenas reales de `glxinfo`, incluido el caso trampa: una AMD acelerada
  reporta `AMD Radeon RX 7600 (radeonsi, navi33, LLVM 17.0.6)`, que contiene
  "LLVM" pero **no** es `llvmpipe`.
- Detección de temas: con `WhiteSur`, `McMojave` y `Yaru` falsos en
  `/usr/share/themes`, detecta los de macOS y deja Yaru intacto.
- Limpieza de autostart: con `conky`, `plank` y `nextcloud`, saca solo el que
  corresponde.
- El informe del doctor sobre un escritorio simulado (GNOME 50, 14 extensiones,
  tema y iconos de familias distintas): lista las extensiones y detecta la
  mezcla.
- Backups, idempotencia y `undo.sh`: restaurando un archivo y comparando
  `md5sum` contra el original.

Lo que **no** se pudo probar, porque el contenedor es 24.04 sin escritorio ni
GPU: nada de esto corriendo sobre una **Ubuntu 26.04 real** — los nombres de
paquete de "resolute", las unidades `localsearch-*`, las extensiones para GNOME
50, ni el tema WhiteSur sobre libadwaita de GNOME 50. Tampoco los `gsettings`
reales, el `dconf dump`/`load`, los drivers de video ni los cambios en GRUB.

Por eso el kit está hecho para **degradar bien ante lo desconocido** en vez de
acertarle a una lista de nombres: si un paquete no existe, lo dice y sigue; si
no puede detectar la versión de GNOME, no la inventa. Y por eso: **empezá
siempre con `doctor.sh` y con `--dry-run`.**
