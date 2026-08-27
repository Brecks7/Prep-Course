#!/usr/bin/env bash
# Funciones compartidas por todos los módulos de setup.
# Se carga con `source`, no se ejecuta directamente.

# --- Colores (se desactivan si la salida no es una terminal) -----------------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
    C_RESET=''; C_DIM=''; C_BOLD=''
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''
fi

# --- Estado global -----------------------------------------------------------
DRY_RUN="${DRY_RUN:-0}"
AGGRESSIVE="${AGGRESSIVE:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.setup-ubuntu-backups/$(date +%Y%m%d-%H%M%S)}"

# Acumuladores para el resumen final. Se llenan con append_* y los lee install.sh
SUMMARY_OK=()
SUMMARY_WARN=()
SUMMARY_ERR=()
SUMMARY_NOTE=()

# --- Logging -----------------------------------------------------------------
log_step()  { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }
log_ok()    { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_warn()  { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
log_err()   { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_info()  { printf '  %s·%s %s\n' "$C_DIM" "$C_RESET" "$*"; }

note_ok()   { SUMMARY_OK+=("$1");   log_ok "$1"; }
note_warn() { SUMMARY_WARN+=("$1"); log_warn "$1"; }
note_err()  { SUMMARY_ERR+=("$1");  log_err "$1"; }
# Aviso que aparece al final pero no es un fallo: cosas que el usuario debe saber.
note_todo() { SUMMARY_NOTE+=("$1"); log_info "$1"; }

# --- Ejecución ---------------------------------------------------------------
# run <comando> [args...]
# En dry-run imprime en vez de ejecutar. TODO comando con efecto pasa por acá.
run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %s[dry]%s %s\n' "$C_DIM" "$C_RESET" "$*"
        return 0
    fi
    "$@"
}

# run_sh "<línea de shell>"
# Para comandos que necesitan pipes, redirecciones o expansión.
run_sh() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %s[dry]%s sh -c %s\n' "$C_DIM" "$C_RESET" "$1"
        return 0
    fi
    bash -c "$1"
}

# ¿El comando existe en el PATH?
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# ¿El paquete apt está instalado?
pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

# clasificar_paquete <pkg> -> REAL | VIRTUAL | INEXISTENTE
#
# Los nombres de paquete cambian entre versiones de Ubuntu, y un nombre que ya
# no existe hace fallar el lote entero de apt-get install. Peor: un paquete
# puede volverse "virtual" (un alias que provee otro paquete). Por ejemplo
# mesa-va-drivers, que en 24.04 es real y en 26.04 lo provee mesa-libgallium.
# dpkg-query no encuentra los virtuales, así que sin esto el kit reporta que
# falló una instalación que en realidad está bien.
#
#   Real:        apt-cache policy da "Candidate: <versión>"
#   Virtual:     da "Candidate: (none)" y showpkg lista Reverse Provides
#   Inexistente: apt-cache policy no imprime nada (o (none) sin proveedores)
clasificar_paquete() {
    local pkg="$1" salida candidato
    salida="$(LC_ALL=C apt-cache policy "$pkg" 2>/dev/null)"

    [[ -z "$salida" ]] && { echo "INEXISTENTE"; return; }

    candidato="$(awk '/Candidate:/{print $2}' <<<"$salida")"
    if [[ -n "$candidato" && "$candidato" != "(none)" ]]; then
        echo "REAL"; return
    fi

    if [[ -n "$(proveedores_de "$pkg")" ]]; then
        echo "VIRTUAL"; return
    fi

    echo "INEXISTENTE"
}

# Paquetes reales que proveen este nombre virtual, uno por línea.
proveedores_de() {
    LC_ALL=C apt-cache showpkg "$1" 2>/dev/null \
        | sed -n '/Reverse Provides:/,$p' \
        | tail -n +2 \
        | awk 'NF{print $1}' \
        | sort -u
}

# ¿Está cubierto este nombre? Instalado directamente, o virtual con algún
# proveedor instalado.
paquete_satisfecho() {
    local pkg="$1" prov
    pkg_installed "$pkg" && return 0

    while IFS= read -r prov; do
        [[ -n "$prov" ]] && pkg_installed "$prov" && return 0
    done < <(proveedores_de "$pkg")

    return 1
}

# apt_install <paquetes...>
#
# Salta los que ya están cubiertos, resuelve los virtuales a su proveedor, y
# saltea con aviso los que no existen en esta versión de Ubuntu en vez de hacer
# fallar todo el lote.
#
# Devuelve != 0 solo si un paquete que SÍ existía no quedó instalado. Un nombre
# inexistente es un aviso, no un error: significa que cambió entre versiones.
apt_install() {
    local a_instalar=() inexistentes=()
    local p tipo provs n_provs

    for p in "$@"; do
        if paquete_satisfecho "$p"; then
            log_info "ya instalado: $p"
            continue
        fi

        tipo="$(clasificar_paquete "$p")"
        case "$tipo" in
            REAL)
                a_instalar+=("$p")
                ;;
            VIRTUAL)
                provs="$(proveedores_de "$p")"
                n_provs="$(wc -l <<<"$provs")"
                if [[ "$n_provs" -eq 1 ]]; then
                    log_info "$p es virtual, lo provee: $provs"
                    a_instalar+=("$provs")
                else
                    # Elegir por el usuario entre varios proveedores sería
                    # adivinar; mejor decirlo y seguir.
                    note_warn "$p es virtual y lo proveen varios paquetes ($(tr '\n' ' ' <<<"$provs")) — elegí uno a mano"
                fi
                ;;
            INEXISTENTE)
                inexistentes+=("$p")
                ;;
        esac
    done

    if [[ ${#inexistentes[@]} -gt 0 ]]; then
        note_warn "No existen en esta versión de Ubuntu, se saltean: ${inexistentes[*]}"
    fi

    if [[ ${#a_instalar[@]} -eq 0 ]]; then
        log_ok "nada que instalar"
        return 0
    fi

    log_info "instalando: ${a_instalar[*]}"
    run sudo apt-get install -y "${a_instalar[@]}"

    [[ "$DRY_RUN" == "1" ]] && return 0

    # Comprobar de verdad, no confiar en el código de salida de apt.
    local no_quedaron=()
    for p in "${a_instalar[@]}"; do
        paquete_satisfecho "$p" || no_quedaron+=("$p")
    done
    if [[ ${#no_quedaron[@]} -gt 0 ]]; then
        log_err "no se pudieron instalar: ${no_quedaron[*]}"
        return 1
    fi
    return 0
}

# --- Preguntas ---------------------------------------------------------------
# ask "pregunta" -> 0 si sí, 1 si no. Con --yes contesta que sí sin preguntar.
ask() {
    if [[ "$ASSUME_YES" == "1" ]]; then
        log_info "$1 -> sí (--yes)"
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "$1 -> sí (simulado en dry-run)"
        return 0
    fi
    local respuesta
    read -r -p "  ${C_YELLOW}?${C_RESET} $1 [s/N] " respuesta
    [[ "$respuesta" =~ ^[sSyY]$ ]]
}

# --- Backups -----------------------------------------------------------------
# backup_file <ruta> — guarda una copia y la anota en el manifiesto para undo.sh
backup_file() {
    local origen="$1"
    [[ -e "$origen" ]] || { log_info "no existe, nada que respaldar: $origen"; return 0; }

    local destino="$BACKUP_DIR/files$origen"
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %s[dry]%s backup %s -> %s\n' "$C_DIM" "$C_RESET" "$origen" "$destino"
        return 0
    fi

    # Si ya lo respaldamos en esta corrida, NO lo pisamos: la primera copia es
    # la única pristina. Volver a copiar guardaría el archivo ya modificado y
    # undo.sh restauraría basura.
    if [[ -e "$destino" ]]; then
        log_info "ya respaldado en esta corrida: $origen"
        return 0
    fi

    mkdir -p "$(dirname "$destino")"
    # sudo porque puede ser un archivo de /etc que no podemos leer como usuario
    if [[ -r "$origen" ]]; then
        cp -a "$origen" "$destino"
    else
        sudo cp -a "$origen" "$destino"
        sudo chown "$USER:$USER" "$destino"
    fi
    printf '%s\n' "$origen" >> "$BACKUP_DIR/manifest.txt"
    log_info "respaldado: $origen"
}

# backup_dconf — guarda TODA la configuración del escritorio antes de pisarla.
# Los módulos de tema y extensiones cambian decenas de claves de gsettings; sin
# este volcado, undo.sh no tiene forma de devolver el escritorio a como estaba.
# Se hace una sola vez por corrida.
DCONF_RESPALDADO=0
backup_dconf() {
    [[ "$DCONF_RESPALDADO" == "1" ]] && return 0

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %s[dry]%s dconf dump /org/gnome/ -> $BACKUP_DIR/dconf-org-gnome.ini\n' \
            "$C_DIM" "$C_RESET"
        DCONF_RESPALDADO=1
        return 0
    fi

    if ! has_cmd dconf; then
        log_warn "'dconf' no disponible: no se puede respaldar la config del escritorio"
        return 0
    fi

    mkdir -p "$BACKUP_DIR"
    if dconf dump /org/gnome/ > "$BACKUP_DIR/dconf-org-gnome.ini" 2>/dev/null; then
        DCONF_RESPALDADO=1
        log_info "configuración del escritorio respaldada ($(wc -l < "$BACKUP_DIR/dconf-org-gnome.ini") líneas)"
    else
        log_warn "No se pudo respaldar la configuración del escritorio"
    fi
}

# record_action <texto> — deja constancia de algo que undo.sh no puede revertir
# solo. Se escribe en acciones.txt para que el usuario lo vea.
record_action() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %s[dry]%s registrar acción: %s\n' "$C_DIM" "$C_RESET" "$1"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    printf '%s\n' "$1" >> "$BACKUP_DIR/acciones.txt"
}

# --- Bloque marcado en archivos de configuración -----------------------------
# Escribe contenido entre marcadores. Re-ejecutar reemplaza el bloque en vez de
# duplicarlo. Así el script es idempotente sobre ~/.bashrc.
MARCA_INICIO='# >>> setup-ubuntu >>>'
MARCA_FIN='# <<< setup-ubuntu <<<'

write_marked_block() {
    local archivo="$1" contenido="$2"

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %s[dry]%s escribir bloque marcado en %s (%s líneas)\n' \
            "$C_DIM" "$C_RESET" "$archivo" "$(printf '%s' "$contenido" | wc -l)"
        return 0
    fi

    touch "$archivo"
    backup_file "$archivo"

    # Quitar el bloque anterior si existe
    if grep -qF "$MARCA_INICIO" "$archivo"; then
        sed -i "/$(sed 's/[][\.*^$/]/\\&/g' <<<"$MARCA_INICIO")/,/$(sed 's/[][\.*^$/]/\\&/g' <<<"$MARCA_FIN")/d" "$archivo"
    fi

    {
        printf '%s\n' "$MARCA_INICIO"
        printf '%s\n' "$contenido"
        printf '%s\n' "$MARCA_FIN"
    } >> "$archivo"

    log_ok "bloque escrito en $archivo"
}

# --- Detección de hardware ---------------------------------------------------
detect_gpu() {
    local salida
    salida="$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller|display controller' || true)"
    if grep -qi 'amd\|ati\|radeon' <<<"$salida"; then
        echo "amd"
    elif grep -qi 'nvidia' <<<"$salida"; then
        echo "nvidia"
    elif grep -qi 'intel' <<<"$salida"; then
        echo "intel"
    else
        echo "desconocida"
    fi
}

gpu_model() {
    lspci 2>/dev/null | grep -Ei 'vga|3d controller' | sed 's/^[^ ]* //' | head -1
}

detect_ram_gb() {
    local kb
    kb="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    echo $(( kb / 1024 / 1024 ))
}

# 0 = SSD/NVMe, 1 = disco mecánico. Mira el dispositivo que sostiene la raíz.
detect_ssd() {
    local raiz padre rota
    raiz="$(findmnt -no SOURCE / 2>/dev/null || true)"
    [[ -n "$raiz" ]] || return 0
    padre="$(lsblk -no PKNAME "$raiz" 2>/dev/null | head -1)"
    [[ -n "$padre" ]] || return 0
    rota="$(lsblk -dno ROTA "/dev/$padre" 2>/dev/null | tr -d ' ')"
    [[ "$rota" == "0" ]]
}

detect_gnome_version() {
    if has_cmd gnome-shell; then
        gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1
    else
        echo "0"
    fi
}

# ¿Hay un escritorio gráfico? Los módulos de tema y extensiones lo necesitan.
has_desktop() {
    [[ -n "${XDG_CURRENT_DESKTOP:-}" ]] && has_cmd gsettings
}

# --- Guardas -----------------------------------------------------------------
require_not_root() {
    if [[ "$EUID" -eq 0 ]]; then
        log_err "No corras este script con sudo ni como root."
        log_err "Corrélo como tu usuario normal: bash setup/install.sh"
        log_err "El script usa sudo solo en los comandos que lo necesitan."
        exit 1
    fi
}

require_ubuntu() {
    if [[ ! -r /etc/os-release ]]; then
        log_err "No se pudo leer /etc/os-release. Este script es para Ubuntu."
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        log_err "Este script está hecho para Ubuntu. Detectado: ${ID:-desconocido}"
        exit 1
    fi
    # Verificado en 24.04. Las versiones posteriores deberían andar —el kit ya
    # no depende de nombres de paquete fijos— pero no están probadas, y eso se
    # dice en vez de fingir que sí.
    local ver="${VERSION_ID:-0}"
    if [[ "$ver" != "24.04" ]]; then
        # Comparación numérica: 26.04 >= 24.04
        if awk -v v="$ver" 'BEGIN{exit !(v+0 >= 24.04)}' 2>/dev/null; then
            log_warn "Ubuntu $ver: el kit se verificó en 24.04, no acá."
            log_warn "Debería funcionar, pero corré primero con --dry-run."
        else
            log_warn "Ubuntu $ver es anterior a 24.04 — el kit no está pensado para esta versión."
            ask "¿Seguir igual?" || exit 1
        fi
    fi
}

# Mantiene vivo el sudo para no pedir la contraseña una y otra vez.
sudo_keepalive() {
    [[ "$DRY_RUN" == "1" ]] && return 0
    sudo -v || { log_err "Se necesita sudo para continuar."; exit 1; }
    while true; do
        sudo -n true
        sleep 50
        kill -0 "$$" 2>/dev/null || exit
    done &
    SUDO_KEEPALIVE_PID=$!
}

sudo_keepalive_stop() {
    [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    return 0
}
