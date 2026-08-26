#!/usr/bin/env bash
# 50-extensions — extensiones de GNOME para completar el look de macOS.
#
# Se instalan bajando el zip desde extensions.gnome.org con la API oficial,
# pidiendo explícitamente la versión compatible con el GNOME que tenga el
# equipo. Así no se instala una versión que no arranca.

modulo_extensions() {
    log_step "50-extensions · Dock, blur y efectos"

    if ! has_desktop && [[ "$DRY_RUN" != "1" ]]; then
        note_warn "No se detectó un escritorio gráfico — módulo de extensiones salteado"
        return 0
    fi

    local gnome_ver
    gnome_ver="$(detect_gnome_version)"
    [[ "$gnome_ver" == "0" ]] && gnome_ver="46"
    log_info "GNOME Shell versión $gnome_ver"

    # user-theme (necesaria para que el tema WhiteSur se aplique a la barra
    # superior) viene en este paquete de Ubuntu, no hace falta bajarla.
    apt_install gnome-shell-extensions \
        || note_warn "No se pudo instalar gnome-shell-extensions (user-theme puede faltar)"

    # Ubuntu trae su propio dock (un fork viejo de Dash to Dock). Los dos juntos
    # se pelean, así que desactivamos el de Ubuntu antes.
    if run gnome-extensions info ubuntu-dock@ubuntu.com >/dev/null 2>&1; then
        run gnome-extensions disable ubuntu-dock@ubuntu.com
        record_action "extensión deshabilitada: ubuntu-dock@ubuntu.com"
        log_ok "Dock de Ubuntu desactivado (lo reemplaza Dash to Dock)"
    fi

    local ext
    for ext in \
        "dash-to-dock@micxgx.gmail.com" \
        "blur-my-shell@aunetx" \
        "just-perfection-desktop@just-perfection.gmail.com" \
        "compiz-alike-magic-lamp-effect@hermes83.github.com"
    do
        instalar_extension "$ext" "$gnome_ver"
    done

    run gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com \
        || log_info "user-theme ya estaba activa o no disponible"

    configurar_dock

    note_todo "IMPORTANTE: cerrá sesión y volvé a entrar para que las extensiones se activen (en Wayland no alcanza con Alt+F2 r)"
}

instalar_extension() {
    local uuid="$1" shell_ver="$2"

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] instalar extensión $uuid (GNOME $shell_ver)"
        return 0
    fi

    # ¿Ya está?
    if gnome-extensions info "$uuid" >/dev/null 2>&1; then
        gnome-extensions enable "$uuid" 2>/dev/null || true
        log_ok "ya instalada: $uuid"
        return 0
    fi

    local api="https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_ver}"
    local info download_url
    info="$(curl -fsSL "$api" 2>/dev/null || true)"

    if [[ -z "$info" ]]; then
        note_warn "No se pudo consultar $uuid (¿sin internet?) — instalala a mano desde Extension Manager"
        return 1
    fi

    download_url="$(printf '%s' "$info" | jq -r '.download_url // empty')"
    if [[ -z "$download_url" ]]; then
        note_warn "$uuid no tiene versión compatible con GNOME $shell_ver — salteada"
        return 1
    fi

    local zip
    zip="$(mktemp --suffix=.zip)"
    if ! curl -fsSL "https://extensions.gnome.org${download_url}" -o "$zip"; then
        note_warn "Falló la descarga de $uuid"
        rm -f "$zip"
        return 1
    fi

    if gnome-extensions install --force "$zip" >/dev/null 2>&1; then
        # enable puede fallar hasta que se reinicie la sesión: no es un error real.
        gnome-extensions enable "$uuid" 2>/dev/null || true
        record_action "extensión instalada: $uuid"
        note_ok "Extensión instalada: $uuid"
    else
        note_warn "No se pudo instalar $uuid"
    fi
    rm -f "$zip"
}

configurar_dock() {
    local schema=org.gnome.shell.extensions.dash-to-dock

    if [[ "$DRY_RUN" != "1" ]] && ! gsettings list-schemas | grep -q "^${schema}$"; then
        note_warn "Dash to Dock no está disponible todavía — configuralo después de reiniciar sesión"
        return 0
    fi

    log_info "Configurando el dock estilo macOS..."

    run gsettings set "$schema" dock-position BOTTOM
    run gsettings set "$schema" extend-height false          # dock centrado, no de borde a borde
    run gsettings set "$schema" dock-fixed false             # se esconde solo
    run gsettings set "$schema" intellihide true
    run gsettings set "$schema" autohide true
    run gsettings set "$schema" transparency-mode 'DYNAMIC'
    run gsettings set "$schema" dash-max-icon-size 48
    run gsettings set "$schema" animate-show-apps true
    run gsettings set "$schema" show-trash true
    run gsettings set "$schema" show-mounts false
    run gsettings set "$schema" click-action 'minimize-or-previews'
    run gsettings set "$schema" scroll-action 'cycle-windows'

    run gsettings set "$schema" animation-time 0.15
    run gsettings set "$schema" hot-keys true   # Super+1..9 lanza las apps del dock

    note_ok "Dock configurado (abajo, autohide, transparencia dinámica)"
    # Nota: Dash to Dock no tiene el zoom de iconos al pasar el mouse que hace
    # el Dock de macOS. Si querés ese efecto exacto hace falta Plank, que es una
    # app aparte; está explicado en el README.
}
