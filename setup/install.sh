#!/usr/bin/env bash
#
# Setup de Ubuntu 24.04: look estilo macOS + rendimiento + drivers + entorno dev.
#
#   bash setup/install.sh --dry-run --all    # ver qué haría, sin tocar nada
#   bash setup/install.sh --all              # instalación normal
#   bash setup/install.sh --all --aggressive # incluye GRUB y quitar snapd
#   bash setup/install.sh --theme --dev      # solo algunos módulos
#
# Para revertir: bash setup/undo.sh
#
set -uo pipefail   # sin -e a propósito: si un módulo falla, los demás siguen.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

for m in "$SCRIPT_DIR"/modules/*.sh; do
    # shellcheck source=/dev/null
    . "$m"
done

# --- Selección de módulos ----------------------------------------------------
declare -A EJECUTAR=(
    [base]=0 [limpieza]=0 [gpu]=0 [perf]=0 [desnap]=0 [theme]=0 [extensions]=0 [dev]=0 [claude]=0 [rgb]=0
)

uso() {
    cat <<'EOF'
Uso: bash setup/install.sh [opciones] [módulos]

Opciones:
  --all           Todos los módulos
  --dry-run       Mostrar qué haría, sin ejecutar nada
  --aggressive    Habilita lo que toca el sistema a fondo:
                  GRUB, indexado de archivos y eliminar snapd
  --yes           Responder que sí a todas las preguntas (no interactivo)
  -h, --help      Esta ayuda

Módulos:
  --base          Actualizar sistema, utilidades, Flatpak
  --limpieza      Sacar docks duplicados, Plank/Conky y temas puestos con sudo
  --gpu           Drivers de video (AMD/Intel: Mesa, Vulkan, VA-API)
  --perf          swappiness, zram, servicios, GRUB*
  --desnap        Firefox nativo .deb y quitar snapd*     (* requiere --aggressive)
  --theme         Tema WhiteSur: GTK, iconos, cursores, fuentes
  --extensions    Dash to Dock, Blur my Shell y efectos
  --dev           Node (nvm), VS Code, herramientas de terminal, git
  --claude        Claude Code + CLAUDE.md
  --rgb           OpenRGB y rgbctl: un solo comando para el RGB de la máquina

Ejemplos:
  bash setup/install.sh --dry-run --all --aggressive
  bash setup/install.sh --all --aggressive
  bash setup/install.sh --limpieza --theme --extensions

¿No sabés por dónde empezar? Corré primero el diagnóstico:
  bash setup/doctor.sh
EOF
}

if [[ $# -eq 0 ]]; then
    uso
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)         for k in "${!EJECUTAR[@]}"; do EJECUTAR[$k]=1; done ;;
        --dry-run)     DRY_RUN=1 ;;
        --aggressive)  AGGRESSIVE=1 ;;
        --yes|-y)      ASSUME_YES=1 ;;
        --base)        EJECUTAR[base]=1 ;;
        --limpieza)    EJECUTAR[limpieza]=1 ;;
        --gpu|--amd)   EJECUTAR[gpu]=1 ;;
        --perf)        EJECUTAR[perf]=1 ;;
        --desnap)      EJECUTAR[desnap]=1 ;;
        --theme)       EJECUTAR[theme]=1 ;;
        --extensions)  EJECUTAR[extensions]=1 ;;
        --dev)         EJECUTAR[dev]=1 ;;
        --claude)      EJECUTAR[claude]=1 ;;
        --rgb)         EJECUTAR[rgb]=1 ;;
        -h|--help)     uso; exit 0 ;;
        *)             log_err "Opción desconocida: $1"; uso; exit 1 ;;
    esac
    shift
done

# Las lee lib/common.sh (run, ask y los módulos), por eso van exportadas.
export DRY_RUN AGGRESSIVE ASSUME_YES BACKUP_DIR

# --- Comprobaciones previas --------------------------------------------------
require_not_root
require_ubuntu

printf '\n%s%s Setup Ubuntu 24.04 %s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"
printf '%s\n' "──────────────────────────────────────────"
log_info "GPU:    $(gpu_model || echo desconocida)"
log_info "RAM:    $(detect_ram_gb) GB"
log_info "Disco:  $(detect_ssd && echo 'SSD/NVMe' || echo 'mecánico')"
log_info "GNOME:  $(detect_gnome_version)"
if [[ "$DRY_RUN" == "1" ]]; then
    printf '\n  %s*** MODO SIMULACIÓN — no se va a modificar nada ***%s\n' "$C_YELLOW" "$C_RESET"
fi
if [[ "$AGGRESSIVE" == "1" ]]; then
    printf '  %s*** MODO AGRESIVO — se tocan GRUB y snapd ***%s\n' "$C_YELLOW" "$C_RESET"
fi
printf '\n'

if [[ "$DRY_RUN" != "1" ]]; then
    log_warn "Antes de seguir, asegurate de estar sentado FRENTE a esta PC."
    log_warn "Si algo del modo agresivo sale mal, vas a necesitar la pantalla."
    ask "¿Empezamos?" || { log_info "Cancelado."; exit 0; }
fi

# En simulación no se crea nada, ni siquiera la carpeta de backups.
if [[ "$DRY_RUN" != "1" ]]; then
    mkdir -p "$BACKUP_DIR"
    log_info "Backups de esta corrida: $BACKUP_DIR"
fi

# Solo pedimos sudo si algún módulo elegido lo necesita. --theme sobre un tema
# ya instalado, por ejemplo, escribe todo en ~/.local y no lo requiere: pedir la
# contraseña ahí deja una ventana colgada esperando a alguien que quizá no está
# frente a la pantalla.
NECESITA_SUDO=0
for _m in base limpieza gpu perf desnap dev rgb; do
    [[ "${EJECUTAR[$_m]:-0}" == "1" ]] && NECESITA_SUDO=1
done
# El camino WhiteSur de --theme sí usa sudo (tweaks.sh -g para GDM); el camino
# que solo completa iconos sobre un tema ya puesto, no.
if [[ "${EJECUTAR[theme]:-0}" == "1" ]]; then
    _tema_actual="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"
    grep -qiE 'mactahoe|tahoe' <<<"$_tema_actual" || NECESITA_SUDO=1
fi

if [[ "$NECESITA_SUDO" == "1" ]]; then
    sudo_keepalive
    trap sudo_keepalive_stop EXIT
else
    log_info "Ningún módulo elegido necesita sudo — no se pide contraseña."
fi

# --- Ejecución ---------------------------------------------------------------
# Cada módulo se ejecuta aislado: si uno falla, se anota y se sigue con el resto.
ejecutar_modulo() {
    local clave="$1" funcion="$2"
    [[ "${EJECUTAR[$clave]}" == "1" ]] || return 0

    if ! "$funcion"; then
        note_err "El módulo '$clave' terminó con errores (los demás siguieron)"
    fi
}

ejecutar_modulo base       modulo_base
ejecutar_modulo limpieza   modulo_limpieza
ejecutar_modulo gpu        modulo_gpu
ejecutar_modulo perf       modulo_perf
ejecutar_modulo desnap     modulo_desnap
ejecutar_modulo theme      modulo_theme
ejecutar_modulo extensions modulo_extensions
ejecutar_modulo dev        modulo_dev
ejecutar_modulo claude     modulo_claude
ejecutar_modulo rgb        modulo_rgb

# --- Resumen -----------------------------------------------------------------
printf '\n%s\n' "──────────────────────────────────────────"
printf '%s%s Resumen %s\n\n' "$C_BOLD" "$C_BLUE" "$C_RESET"

if [[ ${#SUMMARY_OK[@]} -gt 0 ]]; then
    printf '%sListo:%s\n' "$C_GREEN" "$C_RESET"
    for i in "${SUMMARY_OK[@]}"; do printf '  ✓ %s\n' "$i"; done
    printf '\n'
fi

if [[ ${#SUMMARY_NOTE[@]} -gt 0 ]]; then
    printf '%sTenés que saber:%s\n' "$C_BLUE" "$C_RESET"
    for i in "${SUMMARY_NOTE[@]}"; do printf '  · %s\n' "$i"; done
    printf '\n'
fi

if [[ ${#SUMMARY_WARN[@]} -gt 0 ]]; then
    printf '%sAvisos:%s\n' "$C_YELLOW" "$C_RESET"
    for i in "${SUMMARY_WARN[@]}"; do printf '  ! %s\n' "$i"; done
    printf '\n'
fi

if [[ ${#SUMMARY_ERR[@]} -gt 0 ]]; then
    printf '%sErrores:%s\n' "$C_RED" "$C_RESET"
    for i in "${SUMMARY_ERR[@]}"; do printf '  ✗ %s\n' "$i"; done
    printf '\n'
fi

if [[ "$DRY_RUN" == "1" ]]; then
    printf 'Fue una simulación: no se modificó nada.\n'
    printf 'Para hacerlo de verdad, corré lo mismo sin --dry-run\n\n'
    exit 0
fi

printf 'Backups guardados en: %s\n' "$BACKUP_DIR"
printf 'Para revertir los cambios de sistema: %sbash setup/undo.sh%s\n\n' "$C_BOLD" "$C_RESET"
printf '%sÚltimo paso: cerrá sesión y volvé a entrar%s\n' "$C_BOLD" "$C_RESET"
printf 'Los temas y las extensiones de GNOME no se aplican hasta que lo hagas.\n\n'

if [[ ${#SUMMARY_ERR[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
