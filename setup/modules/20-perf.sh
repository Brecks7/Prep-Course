#!/usr/bin/env bash
# 20-perf — que el equipo no se sienta tosco.
#
# Las partes que tocan /etc y GRUB solo corren con --aggressive.
# Todo lo que se modifica pasa antes por backup_file, así undo.sh puede volver atrás.

modulo_perf() {
    log_step "20-perf · Rendimiento y arranque"

    local ram_gb
    ram_gb="$(detect_ram_gb)"
    log_info "RAM detectada: ${ram_gb} GB"
    if detect_ssd; then
        log_info "Disco raíz: SSD/NVMe"
    else
        log_info "Disco raíz: mecánico (HDD)"
    fi

    perf_sysctl "$ram_gb"
    perf_zram "$ram_gb"
    perf_servicios
    perf_autostart

    if [[ "$AGGRESSIVE" == "1" ]]; then
        perf_tracker
        perf_grub
    else
        note_todo "Tracker y GRUB no se tocaron (requieren --aggressive)"
    fi
}

# --- sysctl ------------------------------------------------------------------
perf_sysctl() {
    local ram_gb="$1"
    local archivo=/etc/sysctl.d/99-setup-ubuntu-perf.conf

    log_info "Ajustando parámetros del kernel..."

    # swappiness 10: con RAM de sobra, preferí mantener datos en memoria antes
    # que escribir al swap (lento). Con poca RAM, un valor tan bajo es
    # contraproducente: el sistema se queda sin margen y termina matando procesos.
    local swappiness=10
    if [[ "$ram_gb" -lt 8 ]]; then
        swappiness=30
        log_info "RAM < 8 GB: se usa swappiness=30 en vez de 10 (más seguro)"
    fi

    backup_file "$archivo"

    local contenido
    contenido="# Generado por setup/install.sh — borrable sin miedo
# Cuánto insiste el kernel en usar swap. Menor = prefiere mantener en RAM.
vm.swappiness=${swappiness}
# Cuánto retiene la caché de inodos/dentries. Menor = más caché de archivos.
vm.vfs_cache_pressure=50
# Empieza a escribir a disco antes, para evitar frenadas largas al guardar.
vm.dirty_background_ratio=5
vm.dirty_ratio=10"

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] escribir $archivo (swappiness=${swappiness})"
    else
        printf '%s\n' "$contenido" | sudo tee "$archivo" >/dev/null
        run sudo sysctl --system >/dev/null
        record_action "creado $archivo"
    fi
    note_ok "Parámetros del kernel ajustados (swappiness=${swappiness})"
}

# --- zram --------------------------------------------------------------------
perf_zram() {
    local ram_gb="$1"

    if [[ "$ram_gb" -ge 16 ]]; then
        log_info "Con ${ram_gb} GB de RAM zram aporta poco; se saltea."
        note_todo "zram no se instaló (tenés ${ram_gb} GB, no hace falta)"
        return 0
    fi

    log_info "Activando zram (swap comprimido en RAM, mucho más rápido que en disco)..."
    if apt_install zram-config; then
        note_ok "zram activado (se nota al reiniciar)"
    else
        note_err "No se pudo activar zram"
    fi
}

# --- Servicios de arranque ---------------------------------------------------
perf_servicios() {
    log_info "Revisando servicios de arranque..."

    # apport y whoopsie son el sistema de reporte de errores de Ubuntu.
    # Desactivarlos no rompe nada y ahorra arranque y algo de RAM.
    local servicio
    for servicio in apport.service whoopsie.service; do
        if systemctl list-unit-files "$servicio" >/dev/null 2>&1 && \
           systemctl is-enabled "$servicio" >/dev/null 2>&1; then
            run sudo systemctl disable --now "$servicio"
            record_action "servicio deshabilitado: $servicio"
            log_ok "deshabilitado: $servicio"
        else
            log_info "ya inactivo o inexistente: $servicio"
        fi
    done

    # ModemManager solo sirve si hay módem 3G/4G. En una PC de escritorio, no.
    if systemctl is-enabled ModemManager.service >/dev/null 2>&1; then
        if ask "¿Deshabilitar ModemManager? (solo sirve para módems 3G/4G/LTE)"; then
            run sudo systemctl disable --now ModemManager.service
            record_action "servicio deshabilitado: ModemManager.service"
            log_ok "deshabilitado: ModemManager"
        fi
    fi

    # CUPS es el sistema de impresión. Preguntamos siempre: si lo apagamos,
    # deja de poder imprimir, y eso sorprende feo.
    if systemctl is-enabled cups.service >/dev/null 2>&1; then
        if ask "¿Deshabilitar el sistema de impresión (CUPS)? Solo si NO usás impresora"; then
            run sudo systemctl disable --now cups.service cups-browsed.service
            record_action "servicio deshabilitado: cups.service cups-browsed.service"
            log_ok "deshabilitado: CUPS"
            note_todo "Si algún día necesitás imprimir: sudo systemctl enable --now cups"
        fi
    fi

    note_ok "Servicios de arranque revisados"
}

# --- Autostart ---------------------------------------------------------------
perf_autostart() {
    # No borramos nada acá: mostramos qué arranca solo para que el usuario decida.
    local dir="$HOME/.config/autostart"
    [[ -d "$dir" ]] || return 0

    local archivos=("$dir"/*.desktop)
    [[ -e "${archivos[0]}" ]] || return 0

    log_info "Aplicaciones que arrancan con la sesión:"
    local f
    for f in "${archivos[@]}"; do
        log_info "  - $(basename "$f")"
    done
    note_todo "Revisá tus apps de inicio en 'Aplicaciones al Inicio' (gnome-tweaks). No se borró ninguna."
}

# --- Tracker (indexado) ------------------------------------------------------
perf_tracker() {
    log_info "Desactivando el indexador de archivos (tracker)..."

    # tracker indexa el CONTENIDO de tus archivos para buscarlos desde GNOME.
    # Consume CPU y disco en segundo plano. Al desactivarlo perdés la búsqueda
    # por contenido; la búsqueda por NOMBRE de archivo sigue funcionando.
    if ! ask "¿Desactivar el indexado de contenido? (gana fluidez, perdés buscar por contenido)"; then
        note_todo "Tracker sigue activo"
        return 0
    fi

    if has_cmd tracker3; then
        run tracker3 reset -s -r
    fi

    local unidad
    for unidad in tracker-miner-fs-3.service tracker-miner-fs-control-3.service \
                  tracker-extract-3.service tracker-writeback-3.service; do
        run systemctl --user mask "$unidad"
        record_action "unidad de usuario enmascarada: $unidad"
    done

    note_ok "Indexado desactivado"
    note_todo "Para revertir el indexado: systemctl --user unmask 'tracker-*'"
}

# --- GRUB --------------------------------------------------------------------
perf_grub() {
    local archivo=/etc/default/grub

    log_warn "Los cambios en GRUB afectan el arranque del sistema."
    if ! ask "¿Modificar GRUB? (se respalda antes; undo.sh lo revierte)"; then
        note_todo "GRUB no se tocó"
        return 0
    fi

    backup_file "$archivo"

    # Timeout a 2 segundos: el menú sigue estando (importante para poder entrar
    # a una versión anterior del kernel si algo se rompe), pero no hace esperar.
    run sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' "$archivo"
    log_ok "GRUB_TIMEOUT=2"

    # ppfeaturemask habilita el control de curvas de ventilador y undervolt en
    # GPUs AMD (lo usa CoreCtrl). No cambia rendimiento por sí solo.
    if [[ "$(detect_gpu)" == "amd" ]]; then
        if ! grep -q 'amdgpu.ppfeaturemask' "$archivo"; then
            run sudo sed -i \
                's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 amdgpu.ppfeaturemask=0xffffffff"/' \
                "$archivo"
            log_ok "amdgpu.ppfeaturemask habilitado (control de ventiladores/undervolt)"
        fi
    fi

    run sudo update-grub
    record_action "modificado $archivo (+ update-grub)"

    note_ok "GRUB actualizado"
    note_todo "Si el equipo no arranca bien: entrá a una versión anterior del kernel desde el menú de GRUB y corré 'bash setup/undo.sh'"

    # Deliberadamente NO agregamos mitigations=off. Es lo que recomienda medio
    # internet para "acelerar Ubuntu", pero desactiva las mitigaciones de
    # Spectre/Meltdown a cambio de unos pocos puntos porcentuales. En la máquina
    # donde estudiás y guardás tus cosas no vale la pena. Está explicado en el README.
}
