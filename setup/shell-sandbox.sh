#!/usr/bin/env bash
# shell-sandbox.sh — probar extensiones sin arriesgar la sesión.
#
# El problema: en Wayland una extensión rota se ve recién después de cerrar
# sesión y volver a entrar (`Alt+F2 r` no existe fuera de X11), y si tira en
# `enable()` te podés quedar sin barra ni dock hasta reiniciar GNOME.
#
# Esto levanta un GNOME Shell 50 aparte, headless, con su propio bus de D-Bus,
# su propio dconf y sólo las extensiones que le pasemos. Si algo explota,
# explota ahí. Lo que devuelve es el journal de esa sesión: errores de `enable()`,
# `console.log()` nuestros, valores de retorno de `addKeybinding`.
#
#   bash setup/shell-sandbox.sh mactahoe-tweaks@son.local
#   bash setup/shell-sandbox.sh --seconds 20 mactahoe-tweaks@son.local macos-dock@son.local
#
# Lo que NO hace: capturas. Adentro de la sesión headless el shell le niega
# `org.gnome.Shell.Screenshot` a cualquiera que no sea el portal, y montar un
# portal completo ahí adentro cuesta más de lo que vale. Para ver píxeles está
# `setup/shot.sh`, que va contra la sesión real.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SEGUNDOS=12
UUIDS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --seconds) SEGUNDOS="$2"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) UUIDS+=("$1"); shift ;;
    esac
done

if [[ ${#UUIDS[@]} -eq 0 ]]; then
    log_err "pasá al menos un UUID de extensión"
    exit 2
fi

if ! has_cmd dbus-run-session; then
    log_err "falta dbus-run-session (paquete dbus-daemon)"
    exit 1
fi

PERFIL="$(mktemp -d -t shell-sandbox-XXXXXX)"
trap 'rm -rf "$PERFIL"' EXIT

EXT_DIR="$PERFIL/data/gnome-shell/extensions"
mkdir -p "$EXT_DIR" "$PERFIL/config" "$PERFIL/cache" "$PERFIL/state"

# Preferimos la copia del repo sobre la instalada: lo que queremos probar es el
# código que estamos editando, no el que ya está en ~/.local.
for uuid in "${UUIDS[@]}"; do
    for origen in "$SCRIPT_DIR/extensions/$uuid" \
                  "$HOME/.local/share/gnome-shell/extensions/$uuid" \
                  "/usr/share/gnome-shell/extensions/$uuid"; do
        if [[ -d "$origen" ]]; then
            cp -r "$origen" "$EXT_DIR/$uuid"
            log_info "$uuid  <- $origen"
            break
        fi
    done
    if [[ ! -d "$EXT_DIR/$uuid" ]]; then
        log_err "no encontré $uuid en ningún lado"
        exit 1
    fi
    [[ -d "$EXT_DIR/$uuid/schemas" ]] && \
        glib-compile-schemas "$EXT_DIR/$uuid/schemas" 2>/dev/null
done

LISTA="$(printf "'%s', " "${UUIDS[@]}")"
LISTA="[${LISTA%, }]"

LOG="$PERFIL/shell.log"

log_step "GNOME Shell headless · ${SEGUNDOS}s · $LISTA"

# XDG_DATA_HOME/CONFIG_HOME aislados: el dconf de la sesión real no se toca.
# --headless + --virtual-monitor evita pelear por el compositor de verdad.
env -i \
    HOME="$HOME" USER="$USER" PATH="$PATH" LANG="${LANG:-C.UTF-8}" \
    XDG_DATA_HOME="$PERFIL/data" \
    XDG_CONFIG_HOME="$PERFIL/config" \
    XDG_CACHE_HOME="$PERFIL/cache" \
    XDG_STATE_HOME="$PERFIL/state" \
    XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_DATA_DIRS="/usr/share:/usr/local/share" \
    G_MESSAGES_DEBUG=all \
    dbus-run-session -- bash -c "
        gsettings set org.gnome.shell disable-extension-version-validation true
        gsettings set org.gnome.shell enabled-extensions \"$LISTA\"
        timeout ${SEGUNDOS}s gnome-shell --headless --wayland --no-x11 \
            --virtual-monitor 1920x1080 2>&1
    " > "$LOG" 2>&1

log_info "sesión terminada"

echo
log_step "Errores y mensajes de las extensiones"

# Ojo con este patrón: la versión anterior buscaba "Extension .* error" en
# minúscula y se comía justo el error que más importa. GNOME lo escribe como
# "Extension <uuid>: Error: ..." sobre GNOME Shell-CRITICAL, no como JS ERROR,
# así que el sandbox daba "sin errores" mientras el dock no cargaba. El estado
# "to ERROR" es la confirmación independiente: si aparece, la extensión no
# levantó, sin importar qué diga el resto del log.
PATRON='JS ERROR'
PATRON+='|Extension [^ ]+: Error'
PATRON+='|state of extension [^ ]+ to ERROR'
PATRON+='|GNOME Shell-CRITICAL'
PATRON+='|has been already disposed'
PATRON+='|^ +@.*/extensions/'
PATRON+='|\[mactahoe\]|\[macos-dock\]'

if grep -qE "$PATRON" "$LOG"; then
    grep -E "$PATRON" "$LOG" | sed 's/^/  /' | head -60
else
    log_ok "sin errores ni mensajes de las extensiones"
fi

echo
log_info "$(grep -cE "$PATRON" "$LOG") líneas coincidentes en total"

# Veredicto explícito por extensión, que es lo que uno viene a preguntar.
for uuid in "${UUIDS[@]}"; do
    if grep -qE "state of extension $uuid to ERROR" "$LOG"; then
        log_err "$uuid quedó en ERROR"
    elif grep -qE "Extension $uuid in state ACTIVE" "$LOG"; then
        log_ok "$uuid quedó ACTIVE"
    else
        log_warn "$uuid no llegó a cargar (¿UUID mal escrito?)"
    fi
done
log_info "log completo: se borra al salir; copiá lo que necesites de arriba"
