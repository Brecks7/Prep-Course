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
- **Blur my Shell desactivado.** Quedan 10 extensiones. Si sigue faltando
  fluidez, la próxima candidata es `compiz-windows-effect`.
- Pendiente: `swappiness` sigue en 60 (el módulo `--perf` necesita mi contraseña).
- 24 snaps instalados.

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
