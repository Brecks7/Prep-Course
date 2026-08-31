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

---

# El escritorio

Además del curso, este repo tiene el kit que configura mi Ubuntu y las dos
extensiones propias de GNOME. **Si la tarea es del escritorio, leé `ESTADO.md`**
(132 líneas, el estado de hoy). El relato largo de cada sesión está en
`ESTADO-historial.md` y sólo se lee si hace falta el porqué de algo.

## Mi máquina

- **Ubuntu 26.04 LTS**, GNOME 50, kernel 7.0, sesión Wayland.
- **AMD Radeon RX 5700 XT**, aceleración por hardware funcionando (radeonsi/ACO).
- 29 GB de RAM, 8 hilos. La máquina es fuerte: si algo va lento, es configuración.
- Dos monitores: DP-1 1920×1080 @360 Hz en x=0 (ahí viven barra y dock), DP-3
  2560×1440 @200 Hz en x=1920. La pantalla completa mide 4480×1440.
- Editor: VS Code.

## No trabajes a ciegas

Dos diagnósticos de este repo salieron mal por leer CSS en vez de píxeles. Hay
herramientas para no repetirlo, y conviene usarlas **antes** de afirmar por qué
algo se ve como se ve:

```bash
bash setup/gshell.sh check                 # ¿unsafe mode prendido?
bash setup/gshell.sh find macos-dock-root  # un actor del shell, en vivo
bash setup/gshell.sh push bottom           # empujar un borde (mueve el puntero)
bash setup/shot.sh --crop 700,980,520,100  # píxeles de verdad
bash setup/shell-sandbox.sh <uuid>         # GNOME Shell headless
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
bash setup/install.sh <módulos>            # recién ahí
bash setup/undo.sh                         # revertir si algo salió mal
```

Detalles y decisiones: `setup/README.md`. Atajos y trampas al venir de Windows:
`LINUX-SETUP.md`.
