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
| `--theme` | Tema WhiteSur: GTK, iconos, cursores, fuentes, botones a la izquierda |
| `--extensions` | Dash to Dock, Blur my Shell, Just Perfection, efecto genio |
| `--dev` | Node vía nvm, VS Code, `rg`/`fzf`/`bat`/`btop`/`eza`/`zoxide`, git |
| `--claude` | Claude Code CLI y un `CLAUDE.md` para el repo |

`*` requiere `--aggressive`.

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
tutoriales: obliga a recomponer zonas enteras de la pantalla constantemente. El
módulo `--limpieza` te ofrece dejarlo solo en el panel superior —que es lo que
da el aspecto de macOS— y apagarlo en el resto. Se ve casi igual y se nota
mucho en fluidez.

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

**Dash to Dock no hace el zoom del Dock de macOS.** El efecto de agrandar los
iconos al pasar el mouse no existe en Dash to Dock. Si lo querés exacto, hace
falta [Plank](https://github.com/ricotz/plank), que es una app aparte y suma un
proceso corriendo. Se puede instalar después con `sudo apt install plank`.

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
