#!/usr/bin/env bash
#
# doctor.sh — ¿por qué Ubuntu no va fluido?
#
# Solo lee. No instala, no modifica, no borra nada. Se puede correr sin miedo
# y sin sudo.
#
#   bash setup/doctor.sh
#
# Al final imprime un bloque compacto para pegarle a Claude.
#
set -uo pipefail

if [[ -t 1 ]]; then
    R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
    ROJO=$'\033[31m'; VERDE=$'\033[32m'; AMA=$'\033[33m'; AZUL=$'\033[34m'
else
    R=''; B=''; DIM=''; ROJO=''; VERDE=''; AMA=''; AZUL=''
fi

# Hallazgos, por gravedad. Lo que llena el veredicto final.
CRITICOS=()
AVISOS=()
BIEN=()
# Líneas crudas para el bloque que se le pega a Claude.
RESUMEN=()

crit()  { CRITICOS+=("$1"); printf '  %s✗ CRÍTICO%s %s\n' "$ROJO" "$R" "$1"; }
avis()  { AVISOS+=("$1");   printf '  %s! %s%s\n' "$AMA" "$R" "$1"; }
bien()  { BIEN+=("$1");     printf '  %s✓%s %s\n' "$VERDE" "$R" "$1"; }
dato()  { printf '  %s·%s %s\n' "$DIM" "$R" "$1"; }
titulo(){ printf '\n%s==>%s %s%s%s\n' "$AZUL" "$R" "$B" "$1" "$R"; }
res()   { RESUMEN+=("$1"); }

hay() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Clasifica la cadena del renderer de OpenGL.
# Separada en su propia función para poder probarla con datos falsos.
#   CRITICO     -> está dibujando con la CPU
#   OK          -> hay aceleración por hardware
#   DESCONOCIDO -> no se pudo determinar
# ---------------------------------------------------------------------------
clasificar_renderer() {
    local cadena="${1,,}"   # a minúsculas
    if [[ -z "$cadena" ]]; then
        echo "DESCONOCIDO"; return
    fi
    if [[ "$cadena" == *llvmpipe* || "$cadena" == *softpipe* || "$cadena" == *swrast* ]]; then
        echo "CRITICO"; return
    fi
    echo "OK"
}

# ---------------------------------------------------------------------------
printf '\n%s%s  Doctor · ¿por qué no va fluido?%s\n' "$B" "$AZUL" "$R"
printf '%s\n' "──────────────────────────────────────────────"
printf '%sSolo lectura: este script no modifica nada.%s\n' "$DIM" "$R"

# --- Sistema ---------------------------------------------------------------
titulo "Sistema"

VERSION_UBUNTU="0"
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    VERSION_UBUNTU="${VERSION_ID:-0}"
    dato "SO: ${PRETTY_NAME:-desconocido}"
    res "SO: ${PRETTY_NAME:-?}"
    if [[ "$VERSION_UBUNTU" != "24.04" ]]; then
        dato "   (el kit se verificó en 24.04; acá no. Usá --dry-run primero)"
        res "Kit NO verificado en esta versión de Ubuntu"
    fi
else
    avis "No se pudo leer /etc/os-release"
fi

dato "Kernel: $(uname -r)"
res "Kernel: $(uname -r)"

if hay gnome-shell; then
    GNOME_VER="$(gnome-shell --version 2>/dev/null || echo '?')"
    dato "$GNOME_VER"
    res "$GNOME_VER"
else
    dato "GNOME Shell: no instalado (¿servidor o contenedor?)"
    res "GNOME: ausente"
fi

SESION="${XDG_SESSION_TYPE:-desconocida}"
ESCRITORIO="${XDG_CURRENT_DESKTOP:-ninguno}"
dato "Sesión: $SESION · Escritorio: $ESCRITORIO"
res "Sesión: $SESION / $ESCRITORIO"

RAM_GB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 / 1024 ))
dato "RAM: ${RAM_GB} GB · CPU: $(nproc) hilos"
res "RAM: ${RAM_GB}GB, $(nproc) hilos"

# --- Video: lo primero que hay que mirar -----------------------------------
titulo "Video · la causa más común de que todo vaya lento"

GPU_MODELO="$(lspci 2>/dev/null | grep -Ei 'vga|3d controller' | sed 's/^[^ ]* //' | head -1)"
if [[ -n "$GPU_MODELO" ]]; then
    dato "GPU: $GPU_MODELO"
    res "GPU: $GPU_MODELO"
else
    avis "No se pudo leer la GPU con lspci"
    res "GPU: no detectada"
fi

if hay glxinfo; then
    RENDERER="$(glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' | cut -d: -f2- | sed 's/^ *//')"
    ESTADO_RENDER="$(clasificar_renderer "$RENDERER")"

    case "$ESTADO_RENDER" in
        CRITICO)
            crit "Estás dibujando TODO con la CPU, no con la placa de video."
            dato "   Renderer: $RENDERER"
            dato "   Por eso nada va fluido, por más que cambies el tema."
            dato "   Se arregla con: bash setup/install.sh --gpu"
            res "RENDER: POR SOFTWARE ($RENDERER)  <-- CAUSA RAÍZ"
            ;;
        OK)
            bien "Aceleración por hardware activa: $RENDERER"
            res "Render: OK ($RENDERER)"
            ;;
        *)
            avis "No se pudo determinar el renderer de OpenGL"
            res "Render: indeterminado"
            ;;
    esac
else
    avis "Falta 'glxinfo' — no se puede comprobar lo más importante."
    dato "   Instalalo con: sudo apt install mesa-utils"
    res "Render: sin datos (falta mesa-utils)"
fi

if hay vulkaninfo; then
    if vulkaninfo --summary >/dev/null 2>&1; then
        bien "Vulkan responde"
        res "Vulkan: OK"
    else
        avis "Vulkan instalado pero no responde"
        res "Vulkan: no responde"
    fi
else
    dato "Vulkan no instalado (lo agrega el módulo --gpu)"
    res "Vulkan: ausente"
fi

if hay vainfo; then
    if vainfo >/dev/null 2>&1; then
        bien "Aceleración de video por hardware (VA-API) funcionando"
        res "VA-API: OK"
    else
        avis "VA-API no responde — el video en el navegador usa CPU de más"
        res "VA-API: no responde"
    fi
else
    avis "Sin VA-API: los videos los decodifica la CPU, no la placa."
    dato "   Se nota en ventiladores, consumo y saltos al reproducir video."
    dato "   Lo instala: bash setup/install.sh --gpu"
    res "VA-API: AUSENTE (video decodifica en CPU)"
fi

# Desde Ubuntu 26.04 la sesión es solo Wayland, así que este consejo no aplica.
if [[ "$SESION" == "x11" ]]; then
    if awk -v v="$VERSION_UBUNTU" 'BEGIN{exit !(v+0 >= 26.04)}' 2>/dev/null; then
        dato "Sesión X11 sobre XWayland (compatibilidad); la sesión nativa es Wayland"
    else
        avis "Estás en X11. Wayland compone mejor, sobre todo con blur y sombras."
        dato "   Se cambia en la pantalla de login: engranaje → Ubuntu (Wayland)"
        res "X11 en uso (Wayland rinde mejor)"
    fi
fi

# --- Extensiones -----------------------------------------------------------
titulo "Extensiones de GNOME · la segunda causa"

if hay gnome-extensions; then
    mapfile -t HABILITADAS < <(gnome-extensions list --enabled 2>/dev/null)
    CANT=${#HABILITADAS[@]}
    dato "Extensiones habilitadas: $CANT"
    res "Extensiones habilitadas: $CANT"

    # La lista va también al bloque que se pega: con solo el número no se puede
    # aconsejar cuáles desactivar, que es justo lo que se necesita saber.
    for e in "${HABILITADAS[@]}"; do
        dato "   - $e"
        res "  ext: $e"
    done

    # Varios docks a la vez es el error clásico de estos tutoriales:
    # cada uno dibuja su propia barra y compiten por los mismos eventos.
    DOCKS=()
    for d in "ubuntu-dock@ubuntu.com" "dash-to-dock@micxgx.gmail.com" \
             "dash-to-panel@jderose9.github.com"; do
        printf '%s\n' "${HABILITADAS[@]}" | grep -qx "$d" && DOCKS+=("$d")
    done

    if [[ ${#DOCKS[@]} -gt 1 ]]; then
        crit "Tenés ${#DOCKS[@]} docks activos a la vez: ${DOCKS[*]}"
        dato "   Se pelean entre sí y duplican el trabajo en cada cuadro."
        dato "   Hay que dejar UNO solo."
        res "DOCKS DUPLICADOS: ${DOCKS[*]}  <-- ARREGLAR"
    elif [[ ${#DOCKS[@]} -eq 1 ]]; then
        bien "Un solo dock activo: ${DOCKS[0]}"
        res "Dock: ${DOCKS[0]}"
    fi

    if printf '%s\n' "${HABILITADAS[@]}" | grep -q 'blur-my-shell'; then
        avis "Blur my Shell está activo: es lo que más cuesta por cuadro."
        dato "   Si la GPU no está acelerada, es directamente el culpable."
        res "Blur my Shell: ACTIVO"
    fi

    if [[ "$CANT" -gt 10 ]]; then
        avis "$CANT extensiones: todas corren dentro del mismo proceso que dibuja"
        dato "   tu escritorio. Con esta cantidad es la causa más probable de"
        dato "   que se sienta pesado. La lista completa está arriba."
        res "MUCHAS EXTENSIONES ($CANT)  <-- sospechoso principal"
    elif [[ "$CANT" -gt 6 ]]; then
        avis "$CANT extensiones — revisá si usás todas."
        res "Extensiones: $CANT (revisar)"
    fi
else
    dato "'gnome-extensions' no disponible — sin sesión gráfica, se saltea"
    res "Extensiones: sin datos"
fi

# --- Procesos pesados ------------------------------------------------------
titulo "Procesos que dejan estos tutoriales"

ENCONTRADOS=()
for proc in plank conky cairo-dock docky variety picom compton albert ulauncher; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        ENCONTRADOS+=("$proc")
    fi
done

if [[ ${#ENCONTRADOS[@]} -gt 0 ]]; then
    avis "Corriendo ahora: ${ENCONTRADOS[*]}"
    dato "   Conky y los docks extra comen GPU de fondo todo el tiempo."
    res "Procesos extra: ${ENCONTRADOS[*]}"
else
    bien "Ningún dock ni widget extra corriendo"
    res "Procesos extra: ninguno"
fi

AUTOSTART="$HOME/.config/autostart"
if [[ -d "$AUTOSTART" ]]; then
    N_AUTO=$(find "$AUTOSTART" -name '*.desktop' 2>/dev/null | wc -l)
    if [[ "$N_AUTO" -gt 0 ]]; then
        dato "Apps que arrancan con la sesión: $N_AUTO"
        find "$AUTOSTART" -name '*.desktop' -printf '   - %f\n' 2>/dev/null
        res "Autostart: $N_AUTO apps"
    fi
fi

# --- Temas -----------------------------------------------------------------
titulo "Temas"

if hay gsettings; then
    TEMA="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"
    ICONOS="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
    BOTONES="$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null | tr -d "'")"
    ANIM="$(gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null)"
    dato "Tema GTK: ${TEMA:-?} · Iconos: ${ICONOS:-?}"
    dato "Botones de ventana: ${BOTONES:-?} · Animaciones: ${ANIM:-?}"
    res "Tema: ${TEMA:-?} / iconos ${ICONOS:-?} / botones ${BOTONES:-?}"

    # Un tema estilo macOS con los iconos de Ubuntu (o al revés) se ve
    # incoherente. No afecta el rendimiento, pero es lo que hace que "no
    # termine de verse bien" aunque el tema esté aplicado.
    es_mac_tema=0; es_mac_iconos=0
    grep -qiE 'whitesur|mcmojave|mojave|bigsur|monterey|mactahoe|tahoe|sonoma|ventura' <<<"$TEMA"   && es_mac_tema=1
    grep -qiE 'whitesur|mcmojave|mojave|bigsur|monterey|mactahoe|tahoe|sonoma|ventura' <<<"$ICONOS" && es_mac_iconos=1
    if [[ "$es_mac_tema" != "$es_mac_iconos" ]]; then
        avis "El tema y los iconos son de familias distintas."
        dato "   Tema '${TEMA}' con iconos '${ICONOS}': por eso se ve mezclado."
        dato "   Lo empareja: bash setup/install.sh --theme"
        res "Tema e iconos NO combinan (${TEMA} + ${ICONOS})"
    fi
else
    dato "'gsettings' no disponible — se saltea"
    res "Tema: sin datos"
fi

# Los tutoriales suelen instalar el tema con sudo en /usr/share/themes.
# Eso se pisa o se rompe en cada actualización del sistema; lo correcto es
# que viva en ~/.themes, que es del usuario.
SISTEMA_TEMAS=()
for d in /usr/share/themes /usr/share/icons; do
    [[ -d "$d" ]] || continue
    while IFS= read -r t; do
        [[ -n "$t" ]] && SISTEMA_TEMAS+=("$d/$(basename "$t")")
    done < <(find "$d" -maxdepth 1 -iregex '.*\(whitesur\|mcmojave\|mojave\|bigsur\|monterey\).*' 2>/dev/null)
done

if [[ ${#SISTEMA_TEMAS[@]} -gt 0 ]]; then
    avis "Hay temas estilo macOS instalados con sudo en carpetas del sistema:"
    for t in "${SISTEMA_TEMAS[@]}"; do dato "   $t"; done
    dato "   Se rompen al actualizar Ubuntu. Deberían estar en ~/.themes"
    res "Temas en /usr con sudo: ${#SISTEMA_TEMAS[@]}"
else
    bien "No hay temas de macOS instalados en carpetas del sistema"
fi

for d in "$HOME/.themes" "$HOME/.local/share/themes"; do
    if [[ -d "$d" ]]; then
        N=$(find "$d" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        [[ "$N" -gt 0 ]] && dato "Temas de usuario en $d: $N"
    fi
done

# --- Rendimiento del sistema -----------------------------------------------
titulo "Rendimiento del sistema"

SWAP="$(cat /proc/sys/vm/swappiness 2>/dev/null || echo '?')"
dato "swappiness: $SWAP $( [[ "$SWAP" == "60" ]] && echo '(valor por defecto)' )"
res "swappiness: $SWAP"

if [[ -e /dev/zram0 ]]; then
    bien "zram activo"
    res "zram: activo"
else
    dato "zram no activo"
    res "zram: no"
fi

if hay systemctl && systemctl --user is-enabled tracker-miner-fs-3.service >/dev/null 2>&1; then
    dato "Indexado de archivos (tracker): activo"
    res "tracker: activo"
fi

# --- Software --------------------------------------------------------------
titulo "Software instalado"

FALTAN=()
for p in mesa-utils mesa-vulkan-drivers gnome-tweaks gnome-shell-extension-manager \
         flatpak ripgrep fzf bat btop eza zoxide code; do
    if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed"; then
        dato "instalado: $p"
    else
        FALTAN+=("$p")
    fi
done
[[ ${#FALTAN[@]} -gt 0 ]] && dato "faltan: ${FALTAN[*]}"
res "Faltan paquetes: ${FALTAN[*]:-ninguno}"

if hay snap; then
    N_SNAPS=$(snap list 2>/dev/null | tail -n +2 | wc -l)
    dato "snapd presente · $N_SNAPS snaps instalados"
    res "snaps: $N_SNAPS"
else
    dato "snapd no está instalado"
    res "snaps: sin snapd"
fi

if [[ -d "$HOME/.nvm" ]]; then
    bien "nvm instalado$(hay node && echo " · node $(node -v 2>/dev/null)")"
    res "Node: nvm$(hay node && echo " $(node -v 2>/dev/null)")"
elif dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -q "ok installed"; then
    avis "Node instalado con apt — para desarrollo web conviene nvm"
    res "Node: apt (conviene nvm)"
else
    dato "Node no instalado"
    res "Node: ausente"
fi

if [[ -d "$HOME/.setup-ubuntu-backups" ]]; then
    N_B=$(find "$HOME/.setup-ubuntu-backups" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    dato "Corridas previas de install.sh: $N_B"
    res "install.sh corrió $N_B veces"
else
    dato "install.sh nunca se corrió en esta máquina"
    res "install.sh: nunca corrió"
fi

# --- Errores del shell -----------------------------------------------------
titulo "Errores recientes de GNOME Shell"

if hay journalctl; then
    N_ERR=$(journalctl --user -b -p err --no-pager 2>/dev/null | grep -ci 'gnome-shell' || true)
    if [[ "${N_ERR:-0}" -gt 0 ]]; then
        avis "$N_ERR errores de gnome-shell desde el último arranque"
        journalctl --user -b -p err --no-pager 2>/dev/null \
            | grep -i 'gnome-shell' | tail -3 | sed 's/^/     /'
        res "Errores gnome-shell: $N_ERR"
    else
        bien "Sin errores de gnome-shell desde el último arranque"
        res "Errores gnome-shell: 0"
    fi
else
    dato "journalctl no disponible"
fi

# --- Veredicto -------------------------------------------------------------
printf '\n%s\n' "──────────────────────────────────────────────"
printf '%s%s  Veredicto%s\n\n' "$B" "$AZUL" "$R"

if [[ ${#CRITICOS[@]} -gt 0 ]]; then
    printf '%sEsto es lo que te está frenando el equipo:%s\n\n' "$B$ROJO" "$R"
    n=1
    for c in "${CRITICOS[@]}"; do
        printf '  %s%d.%s %s\n' "$B" "$n" "$R" "$c"
        n=$((n+1))
    done
    printf '\n'
    printf '%sOrden recomendado para atacarlo:%s\n' "$B" "$R"
    printf '  1. bash setup/install.sh --gpu           (aceleración por hardware)\n'
    printf '  2. bash setup/install.sh --limpieza      (sacar docks y procesos duplicados)\n'
    printf '  3. bash setup/install.sh --theme --extensions\n'
    printf '  4. Cerrar sesión y volver a entrar\n\n'
elif [[ ${#AVISOS[@]} -gt 0 ]]; then
    printf '%sNada crítico. Cosas que se pueden mejorar:%s\n\n' "$B$AMA" "$R"
    for a in "${AVISOS[@]}"; do printf '  · %s\n' "$a"; done
    printf '\n'
else
    printf '%sNo se encontraron problemas de rendimiento.%s\n\n' "$VERDE" "$R"
fi

# --- Bloque para pegar -----------------------------------------------------
printf '%s\n' "=== PEGAR A CLAUDE ==="
for l in "${RESUMEN[@]}"; do printf '%s\n' "$l"; done
printf 'Críticos: %d | Avisos: %d\n' "${#CRITICOS[@]}" "${#AVISOS[@]}"
for c in "${CRITICOS[@]}"; do printf 'CRIT: %s\n' "$c"; done
printf '%s\n\n' "=== FIN ==="

printf '%sCopiá desde "=== PEGAR A CLAUDE ===" hasta "=== FIN ===" y pegámelo.%s\n\n' "$DIM" "$R"

# Nunca falla: es un diagnóstico, no una prueba.
exit 0
