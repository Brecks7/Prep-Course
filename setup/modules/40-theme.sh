#!/usr/bin/env bash
# 40-theme — apariencia estilo macOS (WhiteSur).
#
# Los repos de vinceliuice cambian flags entre versiones, así que en vez de
# asumir, leemos el --help de cada instalador y usamos solo los flags que
# realmente existan. Si algo no está, caemos al modo por defecto y avisamos.

THEME_DIR="$HOME/.local/share/setup-ubuntu"

modulo_theme() {
    log_step "40-theme · Apariencia estilo macOS"

    if ! has_desktop && [[ "$DRY_RUN" != "1" ]]; then
        note_warn "No se detectó un escritorio gráfico — módulo de temas salteado"
        return 0
    fi

    run mkdir -p "$THEME_DIR"

    theme_gtk
    theme_iconos
    theme_cursores
    theme_aplicar

    note_todo "Las apps nativas de GNOME (Archivos, Configuración, Calculadora...) usan libadwaita e IGNORAN los temas GTK: van a seguir viéndose como GNOME. Es una limitación del sistema, no del script."
}

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

    if ! run "$inst" "${flags[@]}"; then
        note_warn "El instalador falló con flags; reintentando en modo por defecto"
        run "$inst" || { note_err "No se pudo instalar el tema GTK WhiteSur"; return 1; }
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
    if run "$inst"; then
        note_ok "Iconos WhiteSur instalados"
    else
        note_warn "No se pudieron instalar los iconos WhiteSur"
    fi
}

theme_cursores() {
    theme_clonar https://github.com/vinceliuice/WhiteSur-cursors.git WhiteSur-cursors
    local inst="$THEME_DIR/WhiteSur-cursors/install.sh"

    log_info "Instalando cursores WhiteSur..."
    if run "$inst"; then
        note_ok "Cursores WhiteSur instalados"
    else
        note_warn "No se pudieron instalar los cursores WhiteSur"
    fi
}

theme_aplicar() {
    log_info "Aplicando la configuración de apariencia..."

    # Nombres tal como los dejan los instaladores de vinceliuice.
    run gsettings set org.gnome.desktop.interface gtk-theme      'WhiteSur-Light'
    run gsettings set org.gnome.desktop.interface icon-theme     'WhiteSur'
    run gsettings set org.gnome.desktop.interface cursor-theme   'WhiteSur-cursors'
    run gsettings set org.gnome.desktop.interface color-scheme   'default'

    # Fuente: Inter es libre y es lo más parecido a SF Pro (la de Apple, que no
    # se puede redistribuir, así que el script no la descarga).
    run gsettings set org.gnome.desktop.interface font-name          'Inter 11'
    run gsettings set org.gnome.desktop.interface document-font-name 'Inter 11'
    run gsettings set org.gnome.desktop.interface monospace-font-name 'Fira Code 11'

    # Botones de ventana a la izquierda, como en macOS.
    run gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:'

    note_ok "Apariencia aplicada (tema, iconos, cursores, fuentes, botones a la izquierda)"
    note_todo "Si algo no se ve aplicado, abrí 'Retoques' (gnome-tweaks) y revisá la pestaña Apariencia"
}
