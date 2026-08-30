#!/usr/bin/env bash
# 40-theme — apariencia estilo macOS.
#
# Los repos de vinceliuice cambian flags entre versiones, así que en vez de
# asumir, leemos el --help de cada instalador y usamos solo los flags que
# realmente existan. Si algo no está, caemos al modo por defecto y avisamos.
#
# Hay dos caminos, según lo que ya tengas puesto:
#
#   - Si ya usás un tema de la familia MacTahoe (macOS 26), NO se pisa: se
#     completan solo los iconos y los cursores para que combinen. Tu modo
#     oscuro, tu fuente y tu tema GTK quedan como están.
#   - Si no hay nada estilo macOS, se instala WhiteSur completo.
#
# Pisar la configuración del usuario "porque el script sabe mejor" es
# justamente lo que hace que la gente no confíe en estos kits.

THEME_DIR="$HOME/.local/share/setup-ubuntu"

modulo_theme() {
    log_step "40-theme · Apariencia estilo macOS"

    if ! has_desktop && [[ "$DRY_RUN" != "1" ]]; then
        note_warn "No se detectó un escritorio gráfico — módulo de temas salteado"
        return 0
    fi

    # Antes de pisar nada: guardar la config actual del escritorio.
    backup_dconf

    run mkdir -p "$THEME_DIR"

    local familia
    familia="$(theme_familia_actual)"
    log_info "Tema GTK actual: $(theme_gtk_actual) (familia: $familia)"

    case "$familia" in
        mactahoe)
            log_info "Ya tenés MacTahoe aplicado. Se completan iconos y cursores; el tema, el modo oscuro y la fuente no se tocan."
            theme_iconos_mactahoe
            theme_cursores
            theme_aplicar_iconos
            ;;
        *)
            theme_gtk
            theme_iconos
            theme_cursores
            theme_aplicar_completo
            ;;
    esac

    note_todo "Las apps nativas de GNOME (Archivos, Configuración, Calculadora...) usan libadwaita e IGNORAN los temas GTK: van a seguir viéndose como GNOME. Es una limitación del sistema, no del script."
}

# --- Detección ---------------------------------------------------------------

theme_gtk_actual() {
    gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'"
}

# ¿A qué familia pertenece el tema que ya está aplicado?
theme_familia_actual() {
    local actual
    actual="$(theme_gtk_actual)"
    shopt -s nocasematch
    local familia=ninguna
    case "$actual" in
        *mactahoe*|*tahoe*) familia=mactahoe ;;
        *whitesur*)         familia=whitesur ;;
    esac
    shopt -u nocasematch
    printf '%s\n' "$familia"
}

# Busca un set de iconos instalado que coincida con el patrón, prefiriendo la
# variante oscura si el escritorio está en modo oscuro. No se hardcodea el
# nombre porque los instaladores de vinceliuice lo cambian entre versiones.
theme_buscar_en_iconos() {
    local patron="$1"
    local oscuro=0
    [[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" == *prefer-dark* ]] && oscuro=1

    local dir nombre candidato=""
    for dir in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r ruta; do
            nombre="$(basename "$ruta")"
            # Solo sirve si tiene index.theme: si no, no es un tema válido.
            [[ -f "$ruta/index.theme" ]] || continue
            if [[ "$oscuro" == "1" && "$nombre" == *-dark ]]; then
                printf '%s\n' "$nombre"
                return 0
            fi
            [[ -z "$candidato" ]] && candidato="$nombre"
        done < <(find "$dir" -maxdepth 1 -iname "$patron" 2>/dev/null | sort)
    done

    [[ -n "$candidato" ]] && printf '%s\n' "$candidato"
}

# --- Instaladores ------------------------------------------------------------

# Clona o actualiza un repo de tema en THEME_DIR.
theme_clonar() {
    local url="$1" nombre="$2"
    local destino="$THEME_DIR/$nombre"

    if [[ -d "$destino/.git" ]]; then
        log_info "Actualizando $nombre..."
        run git -C "$destino" pull --quiet --ff-only
    else
        log_info "Clonando $nombre..."
        run git clone --depth 1 "$url" "$destino"
    fi
}

# Varios instaladores de vinceliuice usan rutas relativas por dentro (p. ej.
# "cp -pr dist ..."). Si se los invoca desde otro directorio fallan sin devolver
# error. Hay que ejecutarlos parados en su propia carpeta.
theme_ejecutar_instalador() {
    local script="$1"; shift
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] (cd $(dirname "$script") && ./$(basename "$script") $*)"
        return 0
    fi
    [[ -x "$script" ]] || { log_err "No se encontró el instalador: $script"; return 1; }
    ( cd "$(dirname "$script")" && "./$(basename "$script")" "$@" )
}

# ¿El instalador soporta este flag? Evita que un flag viejo aborte todo.
theme_soporta_flag() {
    local script="$1" flag="$2"
    [[ "$DRY_RUN" == "1" ]] && return 0
    [[ -x "$script" ]] || return 1
    "$script" --help 2>&1 | grep -q -- "$flag"
}

theme_gtk() {
    theme_clonar https://github.com/vinceliuice/WhiteSur-gtk-theme.git WhiteSur-gtk-theme
    local dir="$THEME_DIR/WhiteSur-gtk-theme"
    local inst="$dir/install.sh"

    log_info "Instalando tema GTK WhiteSur (variantes clara y oscura)..."

    local flags=(-c Light -c Dark)
    # --alt all: botones de ventana redondos tipo Mac
    theme_soporta_flag "$inst" '--alt'   && flags+=(--alt all)
    # --round: esquinas redondeadas
    theme_soporta_flag "$inst" '--round' && flags+=(--round)

    if ! theme_ejecutar_instalador "$inst" "${flags[@]}"; then
        note_warn "El instalador falló con flags; reintentando en modo por defecto"
        theme_ejecutar_instalador "$inst" || { note_err "No se pudo instalar el tema GTK WhiteSur"; return 1; }
    fi
    note_ok "Tema GTK WhiteSur instalado"

    # tweaks.sh aplica el tema a la pantalla de login (GDM) y a Firefox.
    local tweaks="$dir/tweaks.sh"
    if [[ -x "$tweaks" || "$DRY_RUN" == "1" ]]; then
        if ask "¿Aplicar el tema también a la pantalla de login (GDM)?"; then
            record_action "GDM modificado por WhiteSur tweaks.sh -g (revertir: sudo $tweaks -r)"
            run sudo "$tweaks" -g || note_warn "No se pudo aplicar el tema a GDM"
        fi
        if ask "¿Darle a Firefox el aspecto de Safari? (tema WhiteSur en Firefox)"; then
            run "$tweaks" -F || note_warn "No se pudo aplicar el tema a Firefox"
        fi
    fi
}

theme_iconos() {
    theme_clonar https://github.com/vinceliuice/WhiteSur-icon-theme.git WhiteSur-icon-theme
    local inst="$THEME_DIR/WhiteSur-icon-theme/install.sh"

    log_info "Instalando iconos WhiteSur..."
    if theme_ejecutar_instalador "$inst"; then
        note_ok "Iconos WhiteSur instalados"
    else
        note_warn "No se pudieron instalar los iconos WhiteSur"
    fi
}

# Iconos de la misma familia que MacTahoe, para que no queden mezclados con
# los Yaru de Ubuntu.
theme_iconos_mactahoe() {
    theme_clonar https://github.com/vinceliuice/MacTahoe-icon-theme.git MacTahoe-icon-theme
    local inst="$THEME_DIR/MacTahoe-icon-theme/install.sh"

    log_info "Instalando iconos MacTahoe..."
    if theme_ejecutar_instalador "$inst"; then
        note_ok "Iconos MacTahoe instalados"
    else
        note_warn "No se pudieron instalar los iconos MacTahoe — se dejan los que ya tenías"
    fi
}

theme_cursores() {
    theme_clonar https://github.com/vinceliuice/WhiteSur-cursors.git WhiteSur-cursors
    local inst="$THEME_DIR/WhiteSur-cursors/install.sh"

    log_info "Instalando cursores estilo macOS..."
    theme_ejecutar_instalador "$inst"

    # El install.sh de WhiteSur-cursors devuelve 0 aunque el cp falle, así que
    # no alcanza con mirar el código de salida: hay que verificar el resultado.
    if [[ "$DRY_RUN" == "1" ]] || [[ -f "$HOME/.local/share/icons/WhiteSur-cursors/index.theme" ]]; then
        note_ok "Cursores instalados"
    else
        note_warn "No se pudieron instalar los cursores — se dejan los actuales"
    fi
}

# --- Aplicar -----------------------------------------------------------------

# --- Fuentes -----------------------------------------------------------------
#
# Hasta el 29 de agosto de 2026 este módulo seteaba `Inter` y `Fira Code` sin
# instalarlas. Pango no avisa cuando no encuentra una familia: cae al fallback
# (Noto Sans) en silencio, así que `gsettings get` devolvía 'Inter 11' y la
# pantalla mostraba otra cosa. Por eso "la fuente sigue en Ubuntu Sans" quedó
# como pendiente sin resolver durante semanas. Ahora se instalan primero y se
# verifica que Pango las resuelva de verdad.

# Descarga una fuente de un release de GitHub a ~/.local/share/fonts (sin sudo).
theme_instalar_fuente_github() {
    local repo="$1" patron="$2" destino="$3" glob="$4"
    local dir="$HOME/.local/share/fonts/$destino"

    if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
        log_ok "Fuente $destino ya instalada"
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] descargar $repo -> $dir"
        return 0
    fi
    if ! has_cmd curl || ! has_cmd unzip || ! has_cmd jq; then
        note_warn "Faltan curl/unzip/jq — no se pudo instalar la fuente $destino"
        return 1
    fi

    local url tmp
    url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | jq -r --arg p "$patron" '.assets[] | select(.name|test($p;"i")) | .browser_download_url' \
        | head -1)"
    if [[ -z "$url" ]]; then
        note_warn "No encontré el zip de $destino en $repo"
        return 1
    fi

    tmp="$(mktemp -d)"
    if ! curl -fsSL "$url" -o "$tmp/f.zip"; then
        rm -rf "$tmp"; note_warn "Falló la descarga de $destino"; return 1
    fi
    unzip -q "$tmp/f.zip" -d "$tmp/x" 2>/dev/null
    mkdir -p "$dir"
    # shellcheck disable=SC2044
    find "$tmp/x" -type f -name "$glob" -exec cp {} "$dir/" \; 2>/dev/null
    rm -rf "$tmp"

    if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        note_warn "El zip de $destino no traía archivos $glob"
        return 1
    fi
    has_cmd fc-cache && fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1
    record_action "fuente instalada: $destino"
    note_ok "Fuente instalada: $destino"
}

# Pregunta a Pango — que es quien lee gsettings — qué carga de verdad para esa
# especificación. Si devuelve otra familia, la fuente no está y el ajuste miente.
theme_fuente_resuelve() {
    local spec="$1" familia="${1%% [0-9]*}"
    has_cmd python3 || return 0   # sin python3 no podemos verificar; no bloquea
    python3 - "$spec" "$familia" <<'PY' 2>/dev/null
import sys
try:
    import gi
    gi.require_version("Pango", "1.0"); gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo
except Exception:
    sys.exit(0)   # sin bindings, no bloqueamos
fm = PangoCairo.FontMap.get_default()
f = fm.load_font(fm.create_context(), Pango.FontDescription.from_string(sys.argv[1]))
got = f.describe().to_string() if f else ""
sys.exit(0 if got.lower().startswith(sys.argv[2].lower()) else 1)
PY
}

# Setea la fuente sólo si Pango la resuelve; si no, avisa en vez de mentir.
theme_set_fuente() {
    local schema="$1" clave="$2" spec="$3"
    if [[ "$DRY_RUN" == "1" ]]; then
        run gsettings set "$schema" "$clave" "$spec"
        return 0
    fi
    if theme_fuente_resuelve "$spec"; then
        run gsettings set "$schema" "$clave" "$spec"
    else
        note_warn "Pango no resuelve '$spec' — dejo $clave como estaba (la fuente no está instalada)"
    fi
}

# Camino completo: para una máquina sin nada estilo macOS puesto.
theme_aplicar_completo() {
    log_info "Aplicando la configuración de apariencia..."

    # Nombres tal como los dejan los instaladores de vinceliuice.
    run gsettings set org.gnome.desktop.interface gtk-theme      'WhiteSur-Light'
    run gsettings set org.gnome.desktop.interface icon-theme     'WhiteSur'
    run gsettings set org.gnome.desktop.interface cursor-theme   'WhiteSur-cursors'
    run gsettings set org.gnome.desktop.interface color-scheme   'default'

    # Fuente: Inter es libre y es lo más parecido a SF Pro (la de Apple, que no
    # se puede redistribuir). Se instalan primero: setearlas sin instalarlas
    # deja el ajuste puesto y la pantalla con otra fuente, sin ningún aviso.
    theme_instalar_fuente_github "rsms/inter"       '^Inter-.*\.zip$'   "Inter"     "*.otf"
    theme_instalar_fuente_github "tonsky/FiraCode"  'Fira_?Code.*\.zip$' "FiraCode"  "*.ttf"

    theme_set_fuente org.gnome.desktop.interface font-name           'Inter 11'
    theme_set_fuente org.gnome.desktop.interface document-font-name  'Inter 11'
    theme_set_fuente org.gnome.desktop.interface monospace-font-name 'Fira Code 11'
    # Ojo con el nombre del peso: 'Inter Semi Bold' (con espacio) NO lo resuelve
    # Pango y cae a Noto Sans. El que funciona es 'Inter SemiBold'.
    theme_set_fuente org.gnome.desktop.wm.preferences titlebar-font  'Inter SemiBold 11'

    theme_botones_izquierda

    note_ok "Apariencia aplicada (tema, iconos, cursores, fuentes, botones a la izquierda)"
    note_todo "Si algo no se ve aplicado, abrí 'Retoques' (gnome-tweaks) y revisá la pestaña Apariencia"
}

# Camino conservador: solo iconos y cursores. No toca gtk-theme, color-scheme
# ni las fuentes, porque el usuario ya eligió los suyos.
theme_aplicar_iconos() {
    log_info "Aplicando iconos y cursores..."

    local iconos cursores
    iconos="$(theme_buscar_en_iconos 'MacTahoe*')"
    cursores="$(theme_buscar_en_iconos '*[Cc]ursors*')"

    if [[ -n "$iconos" || "$DRY_RUN" == "1" ]]; then
        run gsettings set org.gnome.desktop.interface icon-theme "${iconos:-MacTahoe}"
        note_ok "Iconos aplicados: ${iconos:-MacTahoe}"
    else
        note_warn "No se encontró un set de iconos MacTahoe instalado — se dejan los actuales"
    fi

    if [[ -n "$cursores" || "$DRY_RUN" == "1" ]]; then
        run gsettings set org.gnome.desktop.interface cursor-theme "${cursores:-WhiteSur-cursors}"
        note_ok "Cursores aplicados: ${cursores:-WhiteSur-cursors}"
    else
        note_warn "No se encontraron cursores estilo macOS — se dejan los actuales"
    fi

    theme_botones_izquierda

    note_todo "El tema GTK, el modo oscuro y la fuente NO se tocaron: ya los tenías configurados"
}

# Botones de ventana a la izquierda, como en macOS. Si ya están así, no hace nada.
theme_botones_izquierda() {
    local actual
    actual="$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null | tr -d "'")"
    if [[ "$actual" == *:* && "${actual%%:*}" == *close* ]]; then
        log_ok "Los botones de ventana ya están a la izquierda"
        return 0
    fi
    run gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'
    note_ok "Botones de ventana movidos a la izquierda"
}
