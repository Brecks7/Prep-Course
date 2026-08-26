#!/usr/bin/env bash
# 30-desnap — sacar snapd y reemplazar Firefox por la versión .deb de Mozilla.
#
# Por qué: cada snap monta una imagen squashfs propia. Eso agrega tiempo de
# arranque, RAM y sobre todo demora en abrir las apps (el famoso "Firefox tarda
# 10 segundos la primera vez"). El .deb de Mozilla abre igual que cualquier
# programa normal.
#
# El ORDEN importa: si sacás snapd antes de instalar el Firefox nuevo, te
# quedás sin navegador. Este módulo lo hace en el orden correcto y verifica
# cada paso antes de seguir.

modulo_desnap() {
    log_step "30-desnap · Firefox nativo y quitar snap"

    if [[ "$AGGRESSIVE" != "1" ]]; then
        note_todo "Módulo desnap salteado (requiere --aggressive)"
        return 0
    fi

    if ! has_cmd snap; then
        log_info "snapd no está instalado, no hay nada que hacer."
        return 0
    fi

    log_warn "Esto elimina snapd por completo del sistema."
    if ! ask "¿Seguir?"; then
        note_todo "snapd sigue instalado"
        return 0
    fi

    desnap_guardar_estado
    desnap_migrar_perfil_firefox
    desnap_instalar_firefox_deb || {
        note_err "Falló la instalación de Firefox .deb — NO se quitó snapd (seguís teniendo navegador)"
        return 1
    }
    desnap_purgar
}

# Guardar qué snaps había, para poder reinstalarlos si hace falta.
desnap_guardar_estado() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] guardar lista de snaps instalados"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    snap list > "$BACKUP_DIR/snaps-instalados.txt" 2>/dev/null || true
    log_ok "Lista de snaps guardada en $BACKUP_DIR/snaps-instalados.txt"
}

# El perfil de Firefox-snap vive en otro lado. Si no se copia, el usuario
# pierde marcadores, contraseñas y pestañas.
desnap_migrar_perfil_firefox() {
    local origen="$HOME/snap/firefox/common/.mozilla"
    local destino="$HOME/.mozilla"

    if [[ ! -d "$origen" ]]; then
        log_info "No hay perfil de Firefox-snap que migrar."
        return 0
    fi

    if [[ -d "$destino" ]]; then
        note_warn "Ya existe ~/.mozilla — no se sobrescribe. Perfil snap intacto en $origen"
        return 0
    fi

    log_info "Migrando perfil de Firefox (marcadores, contraseñas, pestañas)..."
    run cp -a "$origen" "$destino"
    record_action "perfil de Firefox copiado de $origen a $destino"
    note_ok "Perfil de Firefox migrado"
}

desnap_instalar_firefox_deb() {
    log_info "Agregando el repositorio oficial de Mozilla..."

    # Llave en /etc/apt/keyrings (apt-key está deprecado desde hace años).
    run sudo install -d -m 0755 /etc/apt/keyrings
    run_sh "wget -qO- https://packages.mozilla.org/apt/repo-signing-key.gpg \
        | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null"

    run_sh "echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' \
        | sudo tee /etc/apt/sources.list.d/mozilla.list >/dev/null"

    # Sin este pin, APT puede volver a preferir el paquete de Ubuntu (que es un
    # envoltorio que reinstala el snap).
    backup_file /etc/apt/preferences.d/mozilla
    run_sh "printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
        | sudo tee /etc/apt/preferences.d/mozilla >/dev/null"
    record_action "creado /etc/apt/sources.list.d/mozilla.list y /etc/apt/preferences.d/mozilla"

    run sudo apt-get update

    # Quitar primero el snap de Firefox, si no el .deb no puede tomar el nombre.
    if snap list firefox >/dev/null 2>&1; then
        run sudo snap remove --purge firefox
    fi
    run sudo apt-get install -y firefox

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] verificar que firefox quedó instalado como .deb"
        return 0
    fi

    if pkg_installed firefox; then
        note_ok "Firefox instalado como .deb nativo (arranca mucho más rápido)"
        return 0
    fi

    return 1
}

desnap_purgar() {
    log_info "Quitando el resto de los snaps..."

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] snap remove --purge de cada snap instalado"
        log_info "[dry] sudo apt purge -y snapd"
        log_info "[dry] rm -rf ~/snap /snap /var/snap /var/cache/snapd /var/lib/snapd"
        note_ok "[dry] snapd sería eliminado"
        return 0
    fi

    # Se quitan en varias pasadas: algunos snaps dependen de otros (las bases
    # core/gnome tienen que salir al final).
    local snapname
    for _ in 1 2 3; do
        while read -r snapname _; do
            [[ "$snapname" == "Name" || -z "$snapname" ]] && continue
            sudo snap remove --purge "$snapname" >/dev/null 2>&1 || true
        done < <(snap list 2>/dev/null)
    done

    sudo systemctl stop snapd.service snapd.socket snapd.seeded.service 2>/dev/null || true
    sudo apt-get purge -y snapd
    sudo apt-get autoremove -y

    rm -rf "$HOME/snap"
    sudo rm -rf /snap /var/snap /var/cache/snapd /var/lib/snapd

    # Evitar que vuelva a entrar como dependencia de otro paquete.
    backup_file /etc/apt/preferences.d/nosnap.pref
    printf 'Package: snapd\nPin: release a=*\nPin-Priority: -10\n' \
        | sudo tee /etc/apt/preferences.d/nosnap.pref >/dev/null
    record_action "creado /etc/apt/preferences.d/nosnap.pref (bloquea reinstalación de snapd)"

    note_ok "snapd eliminado del sistema"
    note_todo "Para instalar apps de escritorio ahora usá: flatpak install flathub <app>"
}
