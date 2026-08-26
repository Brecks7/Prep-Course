#!/usr/bin/env bash
#
# Revierte los cambios hechos por setup/install.sh restaurando los backups.
#
#   bash setup/undo.sh --list        # ver las corridas guardadas
#   bash setup/undo.sh               # revertir la última
#   bash setup/undo.sh 20260826-1430 # revertir una en particular
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

RAIZ_BACKUPS="$HOME/.setup-ubuntu-backups"

listar() {
    if [[ ! -d "$RAIZ_BACKUPS" ]]; then
        log_err "No hay backups en $RAIZ_BACKUPS"
        exit 1
    fi
    printf '\nCorridas guardadas:\n\n'
    local d
    for d in "$RAIZ_BACKUPS"/*/; do
        [[ -d "$d" ]] || continue
        local nombre cantidad
        nombre="$(basename "$d")"
        cantidad=0
        [[ -f "$d/manifest.txt" ]] && cantidad="$(wc -l < "$d/manifest.txt")"
        printf '  %s  (%s archivos respaldados)\n' "$nombre" "$cantidad"
    done
    printf '\n'
}

case "${1:-}" in
    --list|-l) listar; exit 0 ;;
    -h|--help)
        sed -n '2,9p' "$0" | sed 's/^# \?//'
        exit 0
        ;;
esac

require_not_root

# Elegir qué corrida revertir
if [[ -n "${1:-}" ]]; then
    OBJETIVO="$RAIZ_BACKUPS/$1"
else
    OBJETIVO="$(find "$RAIZ_BACKUPS" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)"
fi

if [[ -z "$OBJETIVO" || ! -d "$OBJETIVO" ]]; then
    log_err "No se encontró esa corrida. Probá: bash setup/undo.sh --list"
    exit 1
fi

log_step "Revirtiendo desde $OBJETIVO"

# --- Archivos ----------------------------------------------------------------
GRUB_TOCADO=0

if [[ -f "$OBJETIVO/manifest.txt" ]]; then
    while IFS= read -r original; do
        [[ -n "$original" ]] || continue
        respaldo="$OBJETIVO/files$original"

        if [[ ! -e "$respaldo" ]]; then
            log_warn "sin copia de $original — se saltea"
            continue
        fi

        if [[ "$original" == /etc/* ]]; then
            sudo cp -a "$respaldo" "$original"
        else
            cp -a "$respaldo" "$original"
        fi
        log_ok "restaurado: $original"

        [[ "$original" == "/etc/default/grub" ]] && GRUB_TOCADO=1
    done < "$OBJETIVO/manifest.txt"
else
    log_warn "Esta corrida no tiene manifest.txt (¿fue un dry-run?)"
fi

# --- Archivos creados de cero ------------------------------------------------
# No estaban antes, así que restaurar no alcanza: hay que borrarlos.
for creado in \
    /etc/sysctl.d/99-setup-ubuntu-perf.conf \
    /etc/apt/preferences.d/nosnap.pref
do
    if [[ -f "$creado" ]] && ! grep -qxF "$creado" "$OBJETIVO/manifest.txt" 2>/dev/null; then
        sudo rm -f "$creado"
        log_ok "eliminado: $creado"
    fi
done
sudo sysctl --system >/dev/null 2>&1 || true

# --- Servicios y extensiones -------------------------------------------------
if [[ -f "$OBJETIVO/acciones.txt" ]]; then
    while IFS= read -r accion; do
        case "$accion" in
            "servicio deshabilitado: "*)
                servicios="${accion#servicio deshabilitado: }"
                # shellcheck disable=SC2086
                sudo systemctl enable --now $servicios 2>/dev/null \
                    && log_ok "reactivado: $servicios" \
                    || log_warn "no se pudo reactivar: $servicios"
                ;;
            "unidad de usuario enmascarada: "*)
                unidad="${accion#unidad de usuario enmascarada: }"
                systemctl --user unmask "$unidad" 2>/dev/null \
                    && log_ok "desenmascarado: $unidad" \
                    || log_warn "no se pudo desenmascarar: $unidad"
                ;;
            "extensión deshabilitada: "*)
                ext="${accion#extensión deshabilitada: }"
                gnome-extensions enable "$ext" 2>/dev/null \
                    && log_ok "reactivada: $ext" \
                    || log_warn "no se pudo reactivar: $ext"
                ;;
        esac
    done < "$OBJETIVO/acciones.txt"
fi

# --- GRUB --------------------------------------------------------------------
if [[ "$GRUB_TOCADO" == "1" ]]; then
    log_info "Regenerando la configuración de GRUB..."
    sudo update-grub && log_ok "GRUB regenerado"
fi

# --- Lo que no se puede revertir solo ----------------------------------------
printf '\n%s\n' "──────────────────────────────────────────"
printf '%sRevertido.%s\n\n' "$C_GREEN" "$C_RESET"

printf 'Esto queda a mano, porque no conviene automatizarlo:\n\n'

if [[ -f "$OBJETIVO/snaps-instalados.txt" ]]; then
    printf '  %sVolver a instalar snapd%s (tu lista está en\n' "$C_BOLD" "$C_RESET"
    printf '  %s/snaps-instalados.txt):\n' "$OBJETIVO"
    printf '    sudo rm -f /etc/apt/preferences.d/nosnap.pref\n'
    printf '    sudo apt update && sudo apt install snapd\n\n'
fi

printf '  %sQuitar el tema WhiteSur%s:\n' "$C_BOLD" "$C_RESET"
printf '    cd ~/.local/share/setup-ubuntu/WhiteSur-gtk-theme && ./install.sh -r\n'
printf '    gsettings reset org.gnome.desktop.interface gtk-theme\n'
printf '    gsettings reset org.gnome.desktop.wm.preferences button-layout\n\n'

printf '  %sVolver al dock de Ubuntu%s:\n' "$C_BOLD" "$C_RESET"
printf '    gnome-extensions disable dash-to-dock@micxgx.gmail.com\n'
printf '    gnome-extensions enable ubuntu-dock@ubuntu.com\n\n'

printf 'Cerrá sesión y volvé a entrar para ver los cambios.\n\n'
