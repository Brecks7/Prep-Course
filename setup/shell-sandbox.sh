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
#   bash setup/shell-sandbox.sh --shot /tmp/dock.png macos-dock@son.local
#
# `--shot` saca una captura del dock ahí adentro y le pasa las medidas a
# `bin/medir-dock`. Es lo que evita el logout por iteración: GNOME 50 no recarga
# el JS de una extensión —`_callExtensionEnable` reusa el `stateObj` que ya tiene
# en memoria—, así que la sesión real sigue mostrando el código viejo por más que
# se copien los archivos, y `shot.sh` fotografía eso.
#
# El truco es que el `AccessDenied` de `org.gnome.Shell.Screenshot` lo pone el
# servicio de D-Bus, no la clase: adentro del shell `new Shell.Screenshot()`
# anda. El detalle está en `lib/probe-dock.js`.
#
# La captura sale con el dconf real de `macosdock`, no con los defaults del
# schema. `--set clave=valor` lo pisa, que es como se barre un parámetro sin
# tocar la sesión de verdad:
#
#   bash setup/shell-sandbox.sh --shot /tmp/r.png --set dock-border-radius=26 macos-dock@son.local

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SEGUNDOS=12
UUIDS=()
SHOT=""
OVERRIDES=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --seconds) SEGUNDOS="$2"; shift 2 ;;
        --shot)    SHOT="$2"; shift 2 ;;
        --set)     OVERRIDES+=("$2"); shift 2 ;;
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

# El probe se engancha al final de enable() de la extensión que tenga dock.
if [[ -n "$SHOT" ]]; then
    SHOT="$(readlink -f "$SHOT" 2>/dev/null || echo "$SHOT")"
    rm -f "$SHOT"
    probe_uuid=""
    for uuid in "${UUIDS[@]}"; do
        grep -q "_dockManager" "$EXT_DIR/$uuid/extension.js" 2>/dev/null && probe_uuid="$uuid"
    done
    if [[ -z "$probe_uuid" ]]; then
        log_warn "--shot: ninguna extensión tiene _dockManager; sigo sin captura"
        SHOT=""
    else
        cp "$SCRIPT_DIR/lib/probe-dock.js" "$EXT_DIR/$probe_uuid/probe-dock.js"
        python3 "$SCRIPT_DIR/lib/enganchar-probe.py" \
            "$EXT_DIR/$probe_uuid/extension.js" "$SHOT" || exit 1
        # El dconf del sandbox se compila antes de arrancar: pasarlo por
        # `gsettings` adentro del `bash -c` no sirve, el quoting se come los
        # overrides y la corrida sale con los defaults sin avisar.
        mkdir -p "$PERFIL/keyfiles" "$PERFIL/config/dconf"
        {
            echo "[org/gnome/shell/extensions/macosdock]"
            dconf dump /org/gnome/shell/extensions/macosdock/ 2>/dev/null | tail -n +2
            echo "auto-hide=false"
            for o in "${OVERRIDES[@]}"; do echo "$o"; done
        } > "$PERFIL/keyfiles/dock"
        dconf compile "$PERFIL/config/dconf/user" "$PERFIL/keyfiles" 2>/dev/null
    fi
fi

LISTA="$(printf "'%s', " "${UUIDS[@]}")"
LISTA="[${LISTA%, }]"
# Sin los favoritos de verdad el dock del sandbox sale con lo que haya suelto en
# el perfil vacío, y la captura no representa nada.
FAVORITOS="$(gsettings get org.gnome.shell favorite-apps)"
# Y el tema de iconos real: con el Adwaita del perfil vacío los iconos traen su
# propio margen y el dock parece tener más aire del que tiene.
TEMA_ICONOS="$(gsettings get org.gnome.desktop.interface icon-theme)"

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
    XDG_DATA_DIRS="$HOME/.local/share:/var/lib/snapd/desktop:/usr/share:/usr/local/share" \
    G_MESSAGES_DEBUG=all \
    dbus-run-session -- bash -c "
        gsettings set org.gnome.shell disable-extension-version-validation true
        gsettings set org.gnome.shell enabled-extensions \"$LISTA\"
        gsettings set org.gnome.shell favorite-apps \"$FAVORITOS\"
        gsettings set org.gnome.desktop.interface icon-theme \"$TEMA_ICONOS\"
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
PATRON+='|\[mactahoe\]|\[macos-dock\]|\[probe\]'

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
if [[ -n "$SHOT" ]]; then
    echo
    if [[ -s "$SHOT" ]]; then
        python3 "$SCRIPT_DIR/lib/recortar-dock.py" "$SHOT" "$LOG" >/dev/null 2>&1
        log_ok "captura: $SHOT"
        "$SCRIPT_DIR/bin/medir-dock" "$SHOT" 2>/dev/null | sed 's/^/  /'
    else
        log_err "--shot no dejó archivo: mirá las líneas [probe] de arriba"
    fi
fi

log_info "log completo: se borra al salir; copiá lo que necesites de arriba"
