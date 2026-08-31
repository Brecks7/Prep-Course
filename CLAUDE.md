# Configurador

Este repo es **el kit que configura mi Ubuntu**: los scripts de `setup/`, las dos
extensiones propias de GNOME (`macos-dock` y `mactahoe-tweaks`), los parches a
extensiones de terceros y el registro de cómo quedó armado el escritorio.

Nació como fork del Prep Course de Henry y le quedó el material del curso adentro
—sigue vivo, en la sección de abajo—, pero el trabajo de acá es el escritorio y
los arreglos del sistema.

**Si la tarea es del escritorio, leé `ESTADO.md`**: dice en qué anda cada cosa hoy.
El relato largo de cada sesión —síntomas, callejones sin salida, evidencia— está en
`ESTADO-historial.md`, y **no hace falta leerlo** salvo que algo se rompa y haga
falta el porqué.

## Sobre mí

Vengo de Windows y estoy aprendiendo Linux: **avisame si algo es específico de
Linux**. Respondeme en español.

## Mi máquina

- **Ubuntu 26.04 LTS**, GNOME 50, kernel 7.0, sesión Wayland.
- **AMD Radeon RX 6900 XT** de ASUS (navi21/gfx1030, PCI `0x73bf`, subsistema
  `1043:04fa`), radeonsi/ACO con aceleración por hardware. Mesa del sistema: 26.0.8.
- **AMD Ryzen 7 9800X3D**, 32 GB de RAM. Es 8C/**16T**, pero **hoy corre con 8
  hilos**: el SMT está apagado en la BIOS (ver `ESTADO.md`, «Abierto»). La máquina
  es fuerte: si algo va lento, es configuración.
- Dos monitores: DP-1 1920×1080 @360 Hz en x=0 (ahí viven barra y dock), DP-3
  2560×1440 @200 Hz en x=1920. La pantalla completa mide 4480×1440.
- **Disco NVMe de 2 TB, en dual boot**: Windows en `nvme0n1p3` (700 GiB NTFS, sin
  montar), Linux en `nvme0n1p5` (`/`, 733 GiB) y **`nvme0n1p6` montada en
  `~/Juegos`** (454 GiB), donde vive Steam entero.
- Editor: VS Code. **Steam es el `.deb` nativo** instalado en `~/Juegos/Steam` —
  usa el Mesa del sistema. El snap sigue instalado como respaldo hasta que un juego
  abra; después se borra.

## No trabajes a ciegas

Cuatro diagnósticos de este repo salieron mal por afirmar sin medir: dos por leer
CSS en vez de píxeles, y dos por dar por buenos los datos de hardware de este
archivo — decía una 5700 XT y en el zócalo hay una 6900 XT; decía «8 hilos» y son
8 de los 16 que tiene el 9800X3D. **Este archivo también se mide antes de creerle.**
Hay herramientas para no repetirlo, y conviene usarlas **antes** de afirmar por qué
algo se ve o falla como falla:

```bash
bash setup/gshell.sh check                 # ¿unsafe mode prendido?
bash setup/gshell.sh find macos-dock-root  # un actor del shell, en vivo
bash setup/gshell.sh push bottom           # empujar un borde (mueve el puntero)
bash setup/shot.sh --crop 700,980,520,100  # píxeles de verdad
bash setup/shell-sandbox.sh <uuid>         # GNOME Shell headless
journalctl -b -1 -p err                    # qué pasó en el arranque anterior
```

`gshell.sh --help` los explica todos. Las trampas que cuestan una sesión si no se
saben están en `ESTADO.md`, sección «Cómo mirar el escritorio».

## El kit de setup (`setup/`)

Se escribió y verificó en **Ubuntu 24.04**, y esta máquina es 26.04 — se adaptó
para no depender de nombres de paquete fijos, pero **nada se probó sobre una
26.04 real**. Por eso, siempre en este orden:

```bash
bash setup/doctor.sh                       # diagnóstico, solo lee
bash setup/install.sh --dry-run --all      # ver qué haría, sin tocar nada
bash setup/install.sh --yes <módulos>      # recién ahí — el --yes no es opcional
bash setup/undo.sh                         # revertir si algo salió mal
```

`install.sh` **se cuelga para siempre** si se lo corre desde una herramienta sin TTY
y sin `--yes`. Los módulos que piden sudo (`--perf`, `--base`, `--gpu`, `--desnap`,
`--dev`) necesitan un askpass gráfico: nunca la contraseña por el chat.

Detalles y decisiones: `setup/README.md`. Atajos y trampas al venir de Windows:
`LINUX-SETUP.md`.

---

# El Prep Course de Henry

El mismo repo tiene el material del curso preparatorio de Desarrollo Web Full Stack
de Henry: lecturas (`README.md` por módulo) y ejercicios con tests (`homework/`),
sobre JavaScript, HTML y CSS.

## Cuando me ayudes con un ejercicio

- **Explicá el porqué**, no me des solo la solución. Si me pasás el código resuelto
  sin más, no aprendo nada y el Henry Challenge lo rindo yo, no vos.
- Si me equivoco, señalá dónde está el error y por qué falla, antes de corregirlo.

## Correr los tests del curso

```bash
nvm use           # el repo tiene .nvmrc en 24
npm install
npm test          # jest sobre los homework
npm start         # Eleventy en http://localhost:8080
```

Las dependencias son de 2021 (Eleventy 0.12, Jest 27) pero **necesitan Node 20 o
superior**, al revés de lo que parece: `eleventy-plugin-toc` → `cheerio@1.2.0` →
`undici@7` exige 20+. Verificado en agosto de 2026: en Node 16 el build muere con
`ReadableStream is not defined` y en 18 con `File is not defined`.

**Node siempre por nvm.** Nunca apt, nunca `sudo npm install -g`.

## Qué no tocar

Las carpetas numeradas (`00-PrimerosPasos/`, `01a-Git/`, `02-JS-I/`, ...) son
material del curso de Henry. Los archivos dentro de `homework/` sí son míos para
resolver.
