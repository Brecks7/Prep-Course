#!/usr/bin/env bash
# 60-dev — entorno de desarrollo: Node, editor, terminal usable.

NVM_VERSION="v0.40.1"

modulo_dev() {
    log_step "60-dev · Entorno de desarrollo"

    dev_cli_modernas
    dev_nvm_node
    dev_vscode
    dev_git_config
    dev_bashrc
}

# --- Herramientas de terminal ------------------------------------------------
dev_cli_modernas() {
    log_info "Instalando herramientas de terminal..."
    # Todas verificadas: existen en los repos oficiales de Ubuntu 24.04.
    if apt_install ripgrep fzf bat btop eza zoxide; then
        note_ok "Herramientas de terminal instaladas (rg, fzf, bat, btop, eza, zoxide)"
    else
        note_err "Falló la instalación de algunas herramientas de terminal"
    fi
}

# --- Node vía nvm ------------------------------------------------------------
dev_nvm_node() {
    # Node NO se instala con apt: la versión de los repos queda vieja enseguida
    # y para desarrollo web vas a necesitar cambiar de versión seguido.
    if [[ -d "$HOME/.nvm" ]]; then
        log_ok "nvm ya está instalado"
    else
        log_info "Instalando nvm..."
        run_sh "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
        note_ok "nvm instalado"
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] nvm install --lts && nvm alias default lts/*"
        return 0
    fi

    # nvm es una función de shell, no un binario: hay que cargarla.
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

    if ! command -v nvm >/dev/null 2>&1; then
        note_warn "nvm no se pudo cargar en esta sesión — abrí una terminal nueva y corré: nvm install --lts"
        return 0
    fi

    nvm install --lts
    nvm alias default 'lts/*'
    note_ok "Node LTS instalado ($(node --version 2>/dev/null || echo '?'))"

    note_todo "Este repo (Prep Course) usa Eleventy 0.12 y Jest 27, de 2021, pero necesita Node 20 o superior: una dependencia transitiva (cheerio -> undici@7) no corre en versiones viejas. En 16 y 18 el build falla; en 22 y 24 anda. El repo trae un .nvmrc, así que alcanza con: nvm use"
}

# --- Editor ------------------------------------------------------------------
dev_vscode() {
    if has_cmd code; then
        log_ok "VS Code ya está instalado"
        return 0
    fi

    if ! ask "¿Instalar Visual Studio Code?"; then
        note_todo "VS Code no se instaló"
        return 0
    fi

    log_info "Instalando VS Code desde el repositorio de Microsoft (no snap)..."
    run sudo install -d -m 0755 /etc/apt/keyrings
    run_sh "wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor \
        | sudo tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null"
    run_sh "echo 'deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main' \
        | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null"
    record_action "creado /etc/apt/sources.list.d/vscode.list"

    run sudo apt-get update
    if apt_install code; then
        note_ok "VS Code instalado"
    else
        note_err "Falló la instalación de VS Code"
    fi
}

# --- Git ---------------------------------------------------------------------
dev_git_config() {
    log_info "Configurando git..."

    # Clave viniendo de Windows: sin esto, los archivos guardados con finales de
    # línea de Windows (CRLF) ensucian todos los diffs.
    run git config --global core.autocrlf input
    run git config --global init.defaultBranch main
    run git config --global pull.rebase false

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] preguntar nombre y mail de git si faltan"
        note_ok "git configurado"
        return 0
    fi

    if [[ -z "$(git config --global user.name || true)" ]]; then
        local nombre
        read -r -p "  ${C_YELLOW}?${C_RESET} Tu nombre para los commits de git: " nombre
        [[ -n "$nombre" ]] && git config --global user.name "$nombre"
    fi

    if [[ -z "$(git config --global user.email || true)" ]]; then
        local mail
        read -r -p "  ${C_YELLOW}?${C_RESET} Tu email para los commits de git: " mail
        [[ -n "$mail" ]] && git config --global user.email "$mail"
    fi

    note_ok "git configurado (core.autocrlf=input, rama por defecto 'main')"
}

# --- ~/.bashrc ---------------------------------------------------------------
dev_bashrc() {
    log_info "Configurando la terminal..."

    # Se escribe entre marcadores, así re-ejecutar el script reemplaza el bloque
    # en vez de duplicarlo.
    local bloque
    bloque="# Cargar nvm
export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
[ -s \"\$NVM_DIR/bash_completion\" ] && . \"\$NVM_DIR/bash_completion\"

# En Debian/Ubuntu el binario de bat se llama batcat
command -v batcat >/dev/null && alias bat='batcat'
command -v batcat >/dev/null && export MANPAGER=\"sh -c 'col -bx | batcat -l man -p'\"

# eza: reemplazo de ls con colores e iconos
if command -v eza >/dev/null; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lah --group-directories-first --git'
    alias tree='eza --tree --level=2'
fi

# zoxide: 'cd' que aprende a dónde vas. Usalo con 'z <parte del nombre>'
command -v zoxide >/dev/null && eval \"\$(zoxide init bash)\"

# fzf: Ctrl+R busca en el historial de forma interactiva.
# La ruta cambió entre versiones de Ubuntu, así que probamos las conocidas.
for _fzf in /usr/share/doc/fzf/examples/key-bindings.bash \\
            /usr/share/fzf/key-bindings.bash \\
            /usr/share/bash-completion/completions/fzf; do
    [ -f \"\$_fzf\" ] && . \"\$_fzf\"
done
unset _fzf

# Atajos varios
alias gs='git status --short --branch'
alias gl='git log --oneline --graph --decorate -20'
alias ..='cd ..'
alias ...='cd ../..'
alias please='sudo \$(fc -ln -1)'   # repetir el último comando con sudo"

    write_marked_block "$HOME/.bashrc" "$bloque"
    note_ok "Terminal configurada (alias, nvm, fzf, zoxide)"
    note_todo "Abrí una terminal nueva (o corré 'source ~/.bashrc') para que tomen efecto los alias"
}
