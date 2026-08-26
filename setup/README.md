# Kit de setup para Ubuntu 24.04

Scripts para dejar Ubuntu 24.04 con aspecto de macOS, más rápido, con los
drivers de video completos y con el entorno de desarrollo listo.

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
Noble**, la misma versión de escritorio:

- Sintaxis (`bash -n`) y `shellcheck -S warning`: limpio en los 13 archivos.
- Simulación completa (`--dry-run --all --aggressive`), sin efectos en disco.
- `doctor.sh` corriendo **sin escritorio, sin GPU y sin `glxinfo`,
  `gsettings`, `dconf` ni `gnome-extensions`**: completa el informe y sale
  con código 0. Es el caso que más fácil rompe un script de diagnóstico.
- La función que decide si estás en renderizado por software, probada con 9
  cadenas reales de `glxinfo`. Incluye el caso trampa: una GPU AMD acelerada
  reporta `AMD Radeon RX 7600 (radeonsi, navi33, LLVM 17.0.6)`, que contiene
  "LLVM" pero **no** es `llvmpipe` — se clasifica correctamente como acelerada.
- Detección y limpieza de temas: con `WhiteSur`, `McMojave` y `Yaru` falsos en
  `/usr/share/themes`, detecta los dos de macOS y deja Yaru intacto.
- Limpieza de autostart: con `conky`, `plank` y `nextcloud` en
  `~/.config/autostart`, saca solo el que corresponde.
- Instalación real de las herramientas de terminal, verificando que los
  binarios quedan en el `PATH`.
- Existencia de cada paquete apt, comprobada con `apt-cache policy`.
- Backups, idempotencia y `undo.sh`: probados de verdad, restaurando un archivo
  y comparando `md5sum` contra el original.

Lo que **no** se pudo probar por no haber escritorio ni GPU en el contenedor:
la instalación del tema WhiteSur, las extensiones de GNOME, los `gsettings`
reales, el `dconf dump`/`load`, los drivers de video y los cambios en GRUB.
Esas partes están cubiertas solo por la simulación y por el análisis estático.
Por eso: **empezá siempre con `doctor.sh` y con `--dry-run`.**
