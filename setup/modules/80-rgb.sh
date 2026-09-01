#!/usr/bin/env bash
# 80-rgb — control unificado del RGB de la máquina.
#
# Deja un solo comando, `rgbctl`, para prender, apagar y colorear los módulos de
# RAM, la GPU, los headers de la placa y las dos tiras BLE, más un servicio de
# usuario que devuelve el último color al entrar a la sesión.
#
# Las tiras no necesitan instalación: se hablan por BlueZ, que ya viene con el
# sistema. Sí se marcan `trusted` para que reconecten solas sin escanear.

modulo_rgb() {
    log_step "80-rgb · Control del RGB"

    if ! has_desktop; then
        note_todo "Sin escritorio: el RGB no se configura"
        return 0
    fi

    rgb_openrgb || return 0
    rgb_enlace
    rgb_tiras
    rgb_servicio
}

# Las tiras BLE no se instalan: ya las habla `rgbctl` por BlueZ. Lo único que
# aporta el kit es marcarlas `trusted`, para que reconecten solas en vez de
# obligar a un escaneo de 12 s en cada arranque.
rgb_tiras() {
    if ! has_cmd bluetoothctl; then
        note_todo "Sin bluetoothctl: las tiras BLE quedan fuera de rgbctl"
        return 0
    fi

    local macs
    macs="$(bluetoothctl devices 2>/dev/null | grep -i 'LEDDMX' | awk '{print $2}')"
    if [[ -z "$macs" ]]; then
        note_todo "No veo las tiras BLE — prendelas y corré: bluetoothctl scan le"
        return 0
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] marcar como trusted: $(echo "$macs" | tr '\n' ' ')"
        return 0
    fi

    local mac n=0
    while read -r mac; do
        [[ -n "$mac" ]] || continue
        if bluetoothctl trust "$mac" >/dev/null 2>&1; then
            record_action "tira BLE marcada como trusted: $mac"
            n=$((n + 1))
        fi
    done <<< "$macs"
    note_ok "$n tira(s) BLE reconectan solas — rgbctl las incluye"
}

# `rgbctl` vive en el repo, pero el hub y cualquier terminal esperan encontrarlo
# en el PATH. Un symlink evita duplicar el script y que las copias se desfasen.
rgb_enlace() {
    local repo_raiz origen destino
    repo_raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    origen="$repo_raiz/setup/bin/rgb/rgbctl"
    destino="$HOME/.local/bin/rgbctl"

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] enlazar $destino -> $origen"
        return 0
    fi

    mkdir -p "$(dirname "$destino")"
    if ln -sfn "$origen" "$destino"; then
        record_action "enlace creado: $destino"
        note_ok "rgbctl disponible en el PATH — probalo con: rgbctl ff0000"
    else
        note_warn "No se pudo enlazar rgbctl en ~/.local/bin"
    fi
}

# OpenRGB trae las reglas udev que dan acceso a los buses SMBus y al HID de la
# placa sin sudo. Sin el paquete no hay nada que hacer.
rgb_openrgb() {
    if has_cmd openrgb; then
        log_ok "OpenRGB ya está instalado"
    else
        if ! ask "¿Instalar OpenRGB (control del RGB de placa, GPU y RAM)?"; then
            note_todo "OpenRGB no se instaló — sin él, rgbctl no funciona"
            return 1
        fi
        apt_install openrgb || { note_warn "No se pudo instalar OpenRGB"; return 1; }
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] comprobar qué dispositivos ve OpenRGB"
        return 0
    fi

    local vistos
    vistos="$(openrgb --list-devices 2>/dev/null | grep -cE '^[0-9]+:')"
    if [[ "${vistos:-0}" -gt 0 ]]; then
        note_ok "OpenRGB ve $vistos dispositivo(s) — probalos con: setup/bin/rgb/rgbctl ff0000"
    else
        note_warn "OpenRGB no ve ningún dispositivo (¿hace falta reiniciar para las reglas udev?)"
    fi
    return 0
}

# Un oneshot de usuario: al entrar a la sesión reaplica lo último que se pidió.
# Sin esto el RGB vuelve a lo que tenga grabado el firmware en cada arranque.
rgb_servicio() {
    local repo_raiz destino
    repo_raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    destino="$HOME/.config/systemd/user/rgb-restore.service"

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] crear y habilitar $destino"
        return 0
    fi

    mkdir -p "$(dirname "$destino")"
    cat > "$destino" <<EOF
[Unit]
Description=Devolver al RGB el último color aplicado con rgbctl
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=oneshot
# openrgb tarda en enumerar los buses SMBus; sin esto puede no ver la RAM todavía.
ExecStartPre=/usr/bin/sleep 5
ExecStart=$repo_raiz/setup/bin/rgb/rgbctl restore
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
EOF
    record_action "servicio de usuario creado: rgb-restore.service"

    systemctl --user daemon-reload 2>/dev/null
    if systemctl --user enable rgb-restore.service >/dev/null 2>&1; then
        note_ok "El RGB vuelve solo a su color al iniciar sesión"
    else
        note_warn "No se pudo habilitar rgb-restore.service"
    fi
}
