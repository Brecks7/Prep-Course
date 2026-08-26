#!/usr/bin/env bash
# 00-base — actualizar el sistema e instalar lo básico que usan los demás módulos.

modulo_base() {
    log_step "00-base · Sistema base y utilidades"

    log_info "Actualizando índices de paquetes..."
    run sudo apt-get update

    if ask "¿Actualizar todos los paquetes del sistema ahora? (puede tardar)"; then
        run sudo apt-get full-upgrade -y
        note_ok "Sistema actualizado"
    else
        note_todo "Salteaste la actualización del sistema (corré 'sudo apt full-upgrade' cuando puedas)"
    fi

    log_info "Instalando herramientas base..."
    if apt_install \
        build-essential curl wget git jq unzip \
        software-properties-common apt-transport-https ca-certificates gnupg \
        gnome-tweaks gnome-shell-extension-manager dconf-editor \
        fonts-firacode fonts-inter
    then
        note_ok "Herramientas base instaladas"
    else
        note_err "Falló la instalación de algunas herramientas base"
    fi

    # Flatpak: la vía sana para apps de escritorio en Ubuntu, sobre todo si
    # después sacamos snap.
    log_info "Configurando Flatpak + Flathub..."
    if apt_install flatpak && run sudo flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    then
        note_ok "Flathub configurado (las apps de Flathub se instalan con 'flatpak install')"
        note_todo "Flatpak necesita reiniciar sesión antes de que sus apps aparezcan en el menú"
    else
        note_err "No se pudo configurar Flatpak/Flathub"
    fi
}
