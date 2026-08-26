#!/usr/bin/env bash
# 05-limpieza — deshacer lo que dejan los tutoriales de "Ubuntu como macOS".
#
# Estos tutoriales suelen apilar cosas sin sacar las anteriores: quedan dos o
# tres docks activos a la vez, Plank y Conky corriendo de fondo, y el tema
# instalado con sudo en carpetas del sistema. El resultado es un escritorio que
# se ve como macOS pero va a los tumbos.
#
# Este módulo corre ANTES de tema y extensiones, para poder aplicar una
# configuración coherente encima en vez de sumar otra capa.
#
# Todo lo que borra se respalda primero y queda anotado para undo.sh.

# Docks que se pelean entre sí. El que se conserva es dash-to-dock, que es el
# que después configura el módulo 50-extensions.
DOCK_A_CONSERVAR="dash-to-dock@micxgx.gmail.com"

modulo_limpieza() {
    log_step "05-limpieza · Sacar lo que dejó el tutorial"

    limpieza_procesos
    limpieza_docks
    limpieza_blur
    limpieza_temas_sistema
}

# --- Procesos y apps de escritorio de más -----------------------------------
limpieza_procesos() {
    log_info "Buscando docks y widgets extra..."

    # Solo se ofrece quitar lo que realmente está: no tiene sentido preguntar
    # por diez programas que no instaló nunca.
    local candidatos=(plank conky cairo-dock docky variety)
    local presentes=()
    local p
    for p in "${candidatos[@]}"; do
        if pkg_installed "$p" || pgrep -x "$p" >/dev/null 2>&1; then
            presentes+=("$p")
        fi
    done

    if [[ ${#presentes[@]} -eq 0 ]]; then
        log_ok "No hay docks ni widgets extra instalados"
        return 0
    fi

    log_warn "Encontrados: ${presentes[*]}"
    log_info "Estos corren de fondo y consumen GPU aunque no los uses."

    for p in "${presentes[@]}"; do
        if ! ask "¿Quitar $p?"; then
            note_todo "$p se dejó instalado"
            continue
        fi

        # Primero frenarlo, después desinstalarlo: si se desinstala mientras
        # corre, puede quedar el proceso huérfano hasta reiniciar sesión.
        if pgrep -x "$p" >/dev/null 2>&1; then
            run pkill -x "$p" || true
        fi

        limpieza_quitar_autostart "$p"

        if pkg_installed "$p"; then
            run sudo apt-get purge -y "$p"
            record_action "paquete desinstalado: $p"
        fi
        note_ok "$p quitado"
    done
}

# Los tutoriales agregan estas apps al autostart para que arranquen solas.
# Desinstalar el paquete no siempre borra el .desktop del usuario.
limpieza_quitar_autostart() {
    local nombre="$1"
    local dir="$HOME/.config/autostart"
    [[ -d "$dir" ]] || return 0

    local f
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        backup_file "$f"
        run rm -f "$f"
        record_action "autostart eliminado: $f"
        log_ok "sacado del arranque: $(basename "$f")"
    done < <(grep -ril "$nombre" "$dir"/*.desktop 2>/dev/null || true)
}

# --- Docks duplicados --------------------------------------------------------
limpieza_docks() {
    if ! has_desktop && [[ "$DRY_RUN" != "1" ]]; then
        log_info "Sin sesión gráfica, se saltea la limpieza de extensiones"
        return 0
    fi

    if ! has_cmd gnome-extensions && [[ "$DRY_RUN" != "1" ]]; then
        log_info "'gnome-extensions' no disponible, se saltea"
        return 0
    fi

    log_info "Revisando docks activos..."

    local activos=()
    if [[ "$DRY_RUN" != "1" ]]; then
        mapfile -t activos < <(gnome-extensions list --enabled 2>/dev/null)
    fi

    local docks=(
        "ubuntu-dock@ubuntu.com"
        "dash-to-dock@micxgx.gmail.com"
        "dash-to-panel@jderose9.github.com"
    )

    local encontrados=()
    local d
    for d in "${docks[@]}"; do
        if [[ "$DRY_RUN" == "1" ]]; then
            log_info "[dry] comprobar si $d está activo"
        elif printf '%s\n' "${activos[@]}" | grep -qx "$d"; then
            encontrados+=("$d")
        fi
    done

    if [[ ${#encontrados[@]} -le 1 ]]; then
        [[ "$DRY_RUN" != "1" ]] && log_ok "No hay docks duplicados"
        return 0
    fi

    note_warn "Hay ${#encontrados[@]} docks activos al mismo tiempo: ${encontrados[*]}"
    log_info "Se deja solo $DOCK_A_CONSERVAR y se apagan los demás."

    for d in "${encontrados[@]}"; do
        [[ "$d" == "$DOCK_A_CONSERVAR" ]] && continue
        run gnome-extensions disable "$d"
        record_action "extensión deshabilitada: $d"
        note_ok "Dock desactivado: $d"
    done
}

# --- Blur ---------------------------------------------------------------------
limpieza_blur() {
    local esquema=org.gnome.shell.extensions.blur-my-shell

    if [[ "$DRY_RUN" != "1" ]]; then
        has_cmd gsettings || return 0
        gsettings list-schemas 2>/dev/null | grep -q "^${esquema}" || return 0
    fi

    # El blur es, con diferencia, lo más caro por cuadro de todo lo que
    # instalan estos tutoriales: obliga a recomponer zonas de pantalla enteras
    # constantemente. En una GPU sin acelerar es directamente el culpable.
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "Si Blur my Shell está instalado, se reduciría el blur al panel."
    else
        log_info "Blur my Shell está instalado."
    fi

    if ask "¿Reducir el blur al mínimo? (gana mucha fluidez, se ve casi igual)"; then
        # Se deja el blur del panel superior, que es el que da el aspecto de
        # macOS, y se apaga en overview y aplicaciones, que es donde más cuesta.
        run gsettings set "${esquema}.panel"       blur true
        run gsettings set "${esquema}.overview"    blur false
        run gsettings set "${esquema}.appfolder"   blur false
        run gsettings set "${esquema}.window-list" blur false
        run gsettings set "${esquema}.lockscreen"  blur false
        note_ok "Blur reducido al panel superior"
    else
        note_todo "Blur sin cambios (si sigue lento, es el primer sospechoso)"
    fi
}

# --- Temas instalados con sudo -----------------------------------------------
limpieza_temas_sistema() {
    log_info "Buscando temas de macOS instalados en carpetas del sistema..."

    # Los tutoriales hacen 'sudo ./install.sh', que deja el tema en
    # /usr/share/themes. Eso es de root: se pisa o se rompe cada vez que se
    # actualiza Ubuntu. Lo correcto es ~/.themes, que es del usuario y
    # sobrevive a las actualizaciones. El módulo 40-theme lo reinstala ahí.
    local encontrados=()
    local dir t
    for dir in /usr/share/themes /usr/share/icons; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r t; do
            [[ -n "$t" ]] && encontrados+=("$t")
        done < <(find "$dir" -maxdepth 1 -mindepth 1 \
                 -iregex '.*\(whitesur\|mcmojave\|mojave\|bigsur\|monterey\).*' 2>/dev/null)
    done

    if [[ ${#encontrados[@]} -eq 0 ]]; then
        log_ok "No hay temas de macOS en carpetas del sistema"
        return 0
    fi

    note_warn "Hay ${#encontrados[@]} temas instalados con sudo en carpetas del sistema"
    for t in "${encontrados[@]}"; do
        log_info "   $t"
    done
    log_info "Se rompen al actualizar Ubuntu. El módulo --theme los reinstala en ~/.themes"

    if ! ask "¿Quitarlos de las carpetas del sistema?"; then
        note_todo "Los temas del sistema se dejaron como estaban"
        return 0
    fi

    for t in "${encontrados[@]}"; do
        backup_file "$t"
        run sudo rm -rf "$t"
        record_action "tema del sistema eliminado: $t"
        log_ok "quitado: $t"
    done

    note_ok "Temas del sistema limpiados (se reinstalan en ~/.themes con --theme)"
}
