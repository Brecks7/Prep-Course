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

Estado a agosto 2026, según `bash setup/doctor.sh`:

- **Node NO está instalado.** Cuando lo instale, va con **nvm**, nunca con apt,
  y nunca `sudo npm install -g`.
- Faltan: `ripgrep fzf bat btop eza zoxide code`, Vulkan y VA-API.
- 14 extensiones de GNOME habilitadas y Blur my Shell activo — es lo que más
  probable me esté costando la fluidez del escritorio.
- Tema `MacTahoe-Dark` con iconos `Yaru-prussiangreen`: no combinan, por eso se
  ve mezclado.
- 24 snaps instalados.

## Correr los tests del curso

```bash
npm install
npm test          # jest sobre los homework
```

Las dependencias de este repo son de 2021 (Eleventy 0.12, Jest 27). Con una
versión moderna de Node es probable que fallen: `nvm install 16 && nvm use 16`
solo para este proyecto.

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
