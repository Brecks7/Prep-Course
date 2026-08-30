# Contexto del proyecto

Este repositorio es el **Prep Course de Henry**: el curso preparatorio de
Desarrollo Web Full Stack. Contiene material de lectura (`README.md` por módulo)
y ejercicios con tests (`homework/`), sobre JavaScript, HTML y CSS.

## Sobre mí

Soy estudiante y estoy aprendiendo. Cuando me ayudes con un ejercicio:

- **Explicá el porqué**, no me des solo la solución. Si me pasás el código
  resuelto sin más, no aprendo nada y el Henry Challenge lo rindo yo, no vos.
- Si me equivoco, señalá dónde está el error y por qué falla, antes de corregirlo.
- Respondeme en español.
- Vengo de Windows, avisame si algo es específico de Linux.

## Mi máquina

- **Ubuntu 26.04 LTS** (Resolute Raccoon), GNOME 50, kernel 7.0, sesión Wayland.
- **AMD Radeon RX 5700 XT** — aceleración por hardware funcionando (radeonsi/ACO).
- 29 GB de RAM, 8 hilos. La máquina es fuerte: si algo va lento, es configuración.
- Editor: VS Code.

Estado corto (el detalle y la bitácora completa están en `ESTADO.md`):

- **Node por nvm**, 24.20.0 por defecto. Nunca apt, nunca `sudo npm install -g`.
- Instalados: `ripgrep fzf bat btop eza zoxide`, VS Code (repo de Microsoft),
  Chrome (`.deb` oficial), y por Flatpak Krita, LibreSprite y Pixelorama.
- **Vulkan y VA-API funcionan** (RADV NAVI10; H264/HEVC por hardware con
  `radeonsi`), `swappiness` en 10.
- Escritorio: tema `MacTahoe-Dark`, dock propio (`macos-dock@son.local`),
  `mactahoe-tweaks@son.local`, PaperWM parcheado, Blur my Shell, efecto genie al
  minimizar.

## No trabajes a ciegas con el escritorio

Dos diagnósticos anteriores de este repo estaban equivocados por leer CSS en vez
de píxeles. Hay tres scripts para evitarlo, y conviene usarlos **antes** de
afirmar por qué algo se ve como se ve:

```bash
bash setup/shot.sh --probe 300,0,60      # RGB de una columna de la pantalla
bash setup/shot.sh --wait 6 --crop 560,960,800,120
bash setup/shell-sandbox.sh mactahoe-tweaks@son.local   # GNOME Shell headless
bash setup/watch-shell.sh                # journal del shell, filtrado
```

En Wayland `grim` no sirve (es de wlroots) y `org.gnome.Shell.Screenshot` por
D-Bus devuelve `AccessDenied`; la vía que funciona es el portal de escritorio,
que es lo que usa `shot.sh`. Y desde GNOME 50 no se puede recargar una extensión
en vivo: `ReloadExtension` responde `is deprecated and does not work`, así que o
se prueba en el sandbox o hay que cerrar sesión.

Ojo con el kit desde una sesión sin terminal: `--perf`, `--base`, `--gpu`,
`--desnap` y `--dev` piden `sudo` y abren una ventana gráfica de contraseña que
hay que responder a mano. `--theme` sobre un tema que ya está puesto no pide nada.

## Correr los tests del curso

```bash
npm install
npm test          # jest sobre los homework
```

Las dependencias de este repo son de 2021 (Eleventy 0.12, Jest 27), pero
**necesitan Node 20 o superior** — al revés de lo que parece. Verificado en
agosto 2026: en Node 16 el build muere con `ReadableStream is not defined` y en
Node 18 con `File is not defined`; en 22 y 24 anda todo. El motivo es
`eleventy-plugin-toc` → `cheerio@1.2.0` → `undici@7`, que exige 20+.

El repo tiene un `.nvmrc` en `24`, así que alcanza con `nvm use` y listo.

```bash
npm start         # levanta Eleventy en http://localhost:8080
```

## El kit de setup (`setup/`)

Scripts para configurar Ubuntu: look de macOS, rendimiento, drivers, entorno de
desarrollo. Se escribieron y verificaron en **Ubuntu 24.04**, y esta máquina es
26.04 — el kit se adaptó para no depender de nombres de paquete fijos, pero
**nada de esto se probó sobre una 26.04 real**.

Por eso, siempre en este orden:

```bash
bash setup/doctor.sh                       # diagnóstico, solo lee
bash setup/install.sh --dry-run --all      # ver qué haría, sin tocar nada
bash setup/install.sh <módulos>            # recién ahí
bash setup/undo.sh                         # revertir si algo salió mal
```

Detalles y decisiones tomadas: `setup/README.md`.
Atajos y trampas al venir de Windows: `LINUX-SETUP.md`.

## Qué no tocar

Las carpetas numeradas (`00-PrimerosPasos/`, `01a-Git/`, `02-JS-I/`, ...) son
material del curso de Henry. Los archivos dentro de `homework/` sí son míos para
resolver.
