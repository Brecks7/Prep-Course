#!/usr/bin/env bash
# 70-claude — Claude Code en la terminal.

modulo_claude() {
    log_step "70-claude · Claude Code"

    if has_cmd claude; then
        log_ok "Claude Code ya está instalado"
    else
        if ask "¿Instalar Claude Code (CLI de Claude para la terminal)?"; then
            log_info "Instalando Claude Code..."
            if run_sh "curl -fsSL https://claude.ai/install.sh | bash"; then
                note_ok "Claude Code instalado — arrancalo con: claude"
                note_todo "La primera vez que corras 'claude' te va a pedir iniciar sesión en el navegador"
            else
                note_warn "Falló la instalación de Claude Code — instrucciones en https://claude.com/claude-code"
            fi
        else
            note_todo "Claude Code no se instaló"
        fi
    fi

    claude_md
}

# Un CLAUDE.md en la raíz del repo se lee solo al arrancar cada sesión de Claude
# Code. Es la forma más directa de no tener que re-explicar el contexto siempre.
claude_md() {
    local repo_raiz destino
    repo_raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    destino="$repo_raiz/CLAUDE.md"

    if [[ -f "$destino" ]]; then
        log_ok "CLAUDE.md ya existe en el repo, no se sobrescribe"
        return 0
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] crear $destino"
        return 0
    fi

    cat > "$destino" <<'EOF'
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

## Entorno

- Ubuntu 24.04 LTS (vengo de Windows, avisame si algo es específico de Linux).
- Node instalado con **nvm**, no con apt.
- Editor: VS Code.

## Correr los tests

```bash
npm install
npm test          # jest sobre los homework
```

Ojo: las dependencias de este repo son de 2021 (Eleventy 0.12, Jest 27), pero
**necesitan Node 20 o superior**, no una más vieja. Una dependencia transitiva
(`eleventy-plugin-toc` -> `cheerio` -> `undici@7`) no corre en versiones viejas:
en Node 16 y 18 el build falla, en 22 y 24 anda. El repo trae un `.nvmrc`, así
que alcanza con `nvm use`.

## Sitio local

```bash
npm start         # levanta Eleventy en http://localhost:8080
```

## Qué no tocar

Las carpetas numeradas (`00-PrimerosPasos/`, `01a-Git/`, `02-JS-I/`, ...) son
material del curso de Henry. Los archivos dentro de `homework/` sí son míos para
resolver.
EOF

    note_ok "CLAUDE.md creado en la raíz del repo"
    note_todo "CLAUDE.md se lee solo cada vez que abrís Claude Code acá — editalo a tu gusto"
}
