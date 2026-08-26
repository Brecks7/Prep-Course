# Kit de setup para Ubuntu 24.04

Scripts para dejar Ubuntu 24.04 con aspecto de macOS, más rápido, con los
drivers de video completos y con el entorno de desarrollo listo.

> **Corré esto sentado frente a la PC.** El modo agresivo toca GRUB (el
> arranque) y elimina snapd. Si algo sale mal vas a necesitar la pantalla y el
> teclado. No lo corras por SSH desde el celular.

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

`undo.sh` restaura los archivos de sistema, reactiva los servicios y regenera
GRUB. Lo que no revierte solo (reinstalar snapd, quitar el tema) lo imprime al
terminar, con los comandos exactos.

**Si el equipo no arranca después de tocar GRUB:** en el menú de arranque elegí
*Advanced options* → una versión anterior del kernel, entrá y corré
`bash setup/undo.sh`.

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

- Sintaxis (`bash -n`) y `shellcheck -S warning`: limpio en los 11 archivos.
- Simulación completa (`--dry-run --all --aggressive`): corre de punta a punta.
- Instalación real de las herramientas de terminal y verificación de que los
  binarios quedan en el `PATH`.
- Existencia de cada paquete apt, comprobada con `apt-cache policy`.
- Backups, idempotencia y `undo.sh`: probados de verdad, restaurando un archivo
  y comparando `md5sum` contra el original.

Lo que **no** se pudo probar por no haber escritorio ni GPU en el contenedor:
la instalación del tema WhiteSur, las extensiones de GNOME, los `gsettings`, los
drivers de video y los cambios en GRUB. Esas partes están cubiertas solo por la
simulación y por el análisis estático. Por eso: **empezá siempre con
`--dry-run`.**
