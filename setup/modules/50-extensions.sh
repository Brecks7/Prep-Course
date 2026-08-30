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

    backup_dconf

    local gnome_ver
    gnome_ver="$(detect_gnome_version)"
    if [[ "$gnome_ver" == "0" ]]; then
        # Antes acá había un 46 fijo. Suponer una versión es peor que no hacer
        # nada: se bajarían extensiones para un GNOME que no es el que corre.
        note_warn "No se pudo detectar la versión de GNOME — no se instalan extensiones"
        note_todo "Instalalas a mano desde la app 'Extension Manager'"
        return 0
    fi
    log_info "GNOME Shell versión $gnome_ver"

    # user-theme es la que hace que el tema se aplique a la barra superior. Viene
    # en el paquete gnome-shell-extensions, pero también puede estar instalada en
    # ~/.local desde extensions.gnome.org. Si ya está, no hay nada que instalar:
    # llamar a apt igual dispararía un pedido de sudo (ventana gráfica) al pedo.
    if gnome-extensions info user-theme@gnome-shell-extensions.gcampax.github.com >/dev/null 2>&1; then
        log_ok "user-theme ya está instalada — no hace falta apt"
    else
        apt_install gnome-shell-extensions \
            || note_warn "No se pudo instalar gnome-shell-extensions (user-theme puede faltar)"
    fi

    # Ubuntu trae su propio dock (un fork viejo de Dash to Dock, con menos
    # opciones todavía). Dos docks juntos se pelean, así que lo desactivamos.
    if run gnome-extensions info ubuntu-dock@ubuntu.com >/dev/null 2>&1; then
        run gnome-extensions disable ubuntu-dock@ubuntu.com
        record_action "extensión deshabilitada: ubuntu-dock@ubuntu.com"
        log_ok "Dock de Ubuntu desactivado (lo reemplaza MacOS Dock)"
    fi

    local ext
    for ext in \
        "blur-my-shell@aunetx" \
        "just-perfection-desktop@just-perfection.gmail.com" \
        "rounded-window-corners@fxgn" \
        "clipboard-indicator@tudmotu.com" \
        "gsconnect@andyholmes.github.io" \
        "paperwm@paperwm.github.com"
    do
        instalar_extension "$ext" "$gnome_ver"
    done

    # · rounded-window-corners — esquinas redondeadas en todas las ventanas, no
    #   sólo en el dock y el panel. macos-genie trae un parche de compatibilidad
    #   específico para esta extensión, así que van bien juntas.
    # · clipboard-indicator — el historial de portapapeles que en Windows es
    #   Win+V y que GNOME no trae. Se eligió sobre Pano, que quedó en GNOME 45.
    # · gsconnect — el celular integrado. Necesita `wl-clipboard` para compartir
    #   el portapapeles en Wayland: sin `wl-paste` tira
    #   `GLib.SpawnError` al arrancar (lo caza `setup/shell-sandbox.sh`).
    # · paperwm — tiling scrollable, el gesto de niri sin dejar GNOME. Es la más
    #   invasiva de todas: cambia el manejo de ventanas entero. Si molesta,
    #   `gnome-extensions disable paperwm@paperwm.github.com` y listo.
    apt_install wl-clipboard \
        || note_warn "Sin wl-clipboard, GSConnect no puede compartir el portapapeles"

    # space-bar dibuja el indicador de escritorios en la barra superior, que
    # macOS no tiene — y además se pisa con el propio de PaperWM.
    if run gnome-extensions info space-bar@luchrioh >/dev/null 2>&1; then
        run gnome-extensions disable space-bar@luchrioh
        record_action "extensión deshabilitada: space-bar@luchrioh"
        log_ok "space-bar desactivada (macOS no tiene indicador de escritorios)"
    fi

    # El efecto genio al minimizar lo hacía `compiz-alike-magic-lamp-effect`,
    # y hay que dejarla apagada: en GNOME 50 rompe el minimizado por completo.
    # Reemplaza `Main.wm._shellwm.completed_minimize` por una función vacía, con
    # lo cual el shell deja de completar la minimización por su cuenta y pasa a
    # depender de que el efecto termine — pero su handler llama a
    # `Main.overview.dash._redisplay()`, que revienta porque nuestro dock
    # esconde ese Dash, y entonces la ventana no se minimiza nunca, en ninguna
    # app. El detalle está en setup/README.md. La reemplaza macos-genie.
    if run gnome-extensions info compiz-alike-magic-lamp-effect@hermes83.github.com >/dev/null 2>&1; then
        run gnome-extensions disable compiz-alike-magic-lamp-effect@hermes83.github.com
        record_action "extensión deshabilitada: compiz-alike-magic-lamp-effect@hermes83.github.com"
        log_ok "Magic Lamp desactivada (rompía el minimizado; la reemplaza macOS Genie)"
    fi

    # El efecto de minimizar. No está en extensions.gnome.org, así que va por git.
    instalar_extension_git "macos-genie@thuongvo.dev" \
        "https://github.com/SekiroKenjii/macos-genie.git"

    # Las dos nuestras, que viven en este repo porque no hay nada publicado que
    # sirva:
    #
    # · mactahoe-tweaks — fondo de la barra superior, blur de los menús del
    #   panel y el salto entre escritorios.
    # · macos-dock (fork) — MacOS Dock es la única extensión publicada con
    #   magnificación de iconos, que es el gesto que distingue al Dock de macOS
    #   (Dash to Dock no la tiene), pero la v7 tiene bugs de geometría que hacen
    #   que el icono agrandado se salga del rectángulo. El fork los arregla; el
    #   detalle está en su metadata.json y en setup/README.md.
    instalar_extension_local "mactahoe-tweaks@son.local"
    instalar_extension_local "macos-dock@son.local"

    # Dos docks a la vez se pelean por los atajos Super+N y por ocultar el dash.
    if run gnome-extensions info macos-dock@vinnytherobot.github.io >/dev/null 2>&1; then
        run gnome-extensions disable macos-dock@vinnytherobot.github.io
        record_action "extensión deshabilitada: macos-dock@vinnytherobot.github.io"
        log_ok "MacOS Dock de EGO desactivado (lo reemplaza el fork parcheado)"
    fi

    run gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com \
        || log_info "user-theme ya estaba activa o no disponible"

    parchar_paperwm
    configurar_panel
    configurar_blur
    configurar_dock_macos
    configurar_bandeja
    configurar_atajos

    note_todo "IMPORTANTE: cerrá sesión y volvé a entrar para que las extensiones se activen (en Wayland no alcanza con Alt+F2 r)"
}

parchar_paperwm() {
    # PaperWM se parchea en sitio (no hay fork con UUID propio como en el dock),
    # así que cada parche vive en setup/patches/ para poder reaplicarlo cuando
    # una actualización desde extensions.gnome.org pise los archivos.
    #
    # Formato de cada entrada: archivo|parche|centinela
    # El centinela es un texto que sólo existe si el parche ya está puesto: sin
    # eso, reaplicar sobre un archivo ya parcheado deja basura.
    #
    #  1. initworkspaces-race: el callback D-Bus de upgradeGnomeMonitors volvía
    #     contra un `Spaces` ya destruido (GNOME hace enable/disable varias veces
    #     en cada arranque y con dos monitores la llamada tarda más). El `try` que
    #     lo rodea se tragaba la excepción: PaperWM quedaba ACTIVE pero sin sus
    #     señales conectadas.
    #  2. scratch-clone-fantasma: al minimizar, el `cloneActor` quedaba pintando
    #     su fuente aunque el actor estuviera oculto.
    #  3. show-minimizado: el que faltaba. Con el clone ya oculto,
    #     `isWindowAnimating()` da false, así que `showHandler` dejaba de esconder
    #     el actor real cuando mutter lo volvía a mostrar (lo dispara el
    #     `move_resize_frame` que makeScratch hace sobre una ventana minimizada).
    #     Resultado: la ventana minimizada seguía dibujada, sin foco — el
    #     semáforo en gris es cómo se la reconoce.
    local base="$HOME/.local/share/gnome-shell/extensions/paperwm@paperwm.github.com"
    local -a parches=(
        "tiling.js|paperwm-initworkspaces-race.patch|spacesAtEnable"
        "scratch.js|paperwm-scratch-clone-fantasma.patch|PARCHE LOCAL"
        "tiling.js|paperwm-show-minimizado.patch|_minimizing.has(actor)"
    )

    if [[ ! -d "$base" ]]; then
        log_info "PaperWM no está instalado — no hay nada que parchear"
        return 0
    fi
    if ! has_cmd patch; then
        note_warn "Falta el comando 'patch' — PaperWM queda sin parchear"
        return 0
    fi

    local entrada archivo parche centinela destino ruta
    for entrada in "${parches[@]}"; do
        IFS='|' read -r archivo parche centinela <<< "$entrada"
        destino="$base/$archivo"
        ruta="$SCRIPT_DIR/patches/$parche"

        if [[ ! -f "$destino" ]]; then
            note_warn "PaperWM no tiene $archivo — salteo $parche"
            continue
        fi
        if [[ ! -f "$ruta" ]]; then
            note_warn "Falta $ruta — PaperWM queda sin ese parche"
            continue
        fi
        if grep -qF "$centinela" "$destino"; then
            log_ok "PaperWM ya tiene ${parche%.patch}"
            continue
        fi

        # --dry-run primero: si el upstream cambió esa zona, mejor avisar que
        # dejar el archivo a medio parchear y romper el shell entero al próximo
        # login.
        if ! run patch --dry-run --silent -p1 -d "$base" -i "$ruta"; then
            note_warn "El parche $parche ya no aplica (¿cambió upstream?) — revisalo"
            note_todo "Sin él vuelve el bug que arregla (ver setup/README.md)"
            continue
        fi
        run patch --silent -p1 -d "$base" -i "$ruta"
        record_action "parche aplicado: $parche"
        note_ok "PaperWM parcheado: ${parche%.patch}"
    done
}

instalar_extension() {
    local uuid="$1" shell_ver="$2"

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] instalar extensión $uuid (GNOME $shell_ver)"
        return 0
    fi

    # ¿Ya está?
    if gnome-extensions info "$uuid" >/dev/null 2>&1; then
        habilitar_extension "$uuid"
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
        habilitar_extension "$uuid"
        record_action "extensión instalada: $uuid"
        note_ok "Extensión instalada: $uuid"
    else
        note_warn "No se pudo instalar $uuid"
    fi
    rm -f "$zip"
}

# `gnome-extensions enable` habla por D-Bus con el shell que está corriendo, y una
# extensión recién copiada al disco todavía no existe para él: el comando falla en
# silencio y la extensión no arranca nunca, ni después de reiniciar la sesión. La
# lista de gsettings sí es la que el shell lee al arrancar, así que cuando el
# camino por D-Bus falla hay que anotarla ahí a mano.
habilitar_extension() {
    local uuid="$1"

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %s[dry]%s habilitar extensión %s\n' "$C_DIM" "$C_RESET" "$uuid"
        return 0
    fi

    gnome-extensions enable "$uuid" 2>/dev/null && return 0

    local lista
    lista="$(gsettings get org.gnome.shell enabled-extensions)"

    # Ya anotada: no duplicar.
    [[ "$lista" == *"'$uuid'"* ]] && return 0

    if [[ "$lista" == "@as []" || "$lista" == "[]" ]]; then
        gsettings set org.gnome.shell enabled-extensions "['$uuid']"
    else
        gsettings set org.gnome.shell enabled-extensions "${lista/\[/[\'$uuid\', }"
    fi

    log_info "$uuid queda habilitada al reiniciar la sesión"
}

# Instala una extensión que vive en este repo, no en extensions.gnome.org.
instalar_extension_local() {
    local uuid="$1"
    local origen="$SCRIPT_DIR/extensions/$uuid"
    local destino="$HOME/.local/share/gnome-shell/extensions/$uuid"

    if [[ ! -d "$origen" ]]; then
        note_warn "No encontré la extensión local $uuid en $origen"
        return 1
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] copiar $origen -> $destino, compilar schemas y habilitar"
        return 0
    fi

    mkdir -p "$(dirname "$destino")"
    rm -rf "$destino"
    cp -r "$origen" "$destino"

    # Sin esto la extensión arranca y muere al pedir getSettings().
    if has_cmd glib-compile-schemas; then
        glib-compile-schemas "$destino/schemas" 2>/dev/null \
            || note_warn "No se pudieron compilar los schemas de $uuid"
    else
        note_warn "Falta glib-compile-schemas — $uuid no va a poder leer su configuración"
    fi

    habilitar_extension "$uuid"
    record_action "extensión local instalada: $uuid"
    note_ok "Extensión local instalada: $uuid"
}

# Instala una extensión que sólo se publica en git, no en extensions.gnome.org.
# Se clona con --depth 1 a un temporal y se copian los archivos sueltos: el
# repo trae también su install.sh, README y demás, que dentro de la carpeta de
# la extensión no pintan nada.
instalar_extension_git() {
    local uuid="$1" url="$2"
    local destino="$HOME/.local/share/gnome-shell/extensions/$uuid"

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[dry] clonar $url -> $destino, compilar schemas y habilitar"
        return 0
    fi

    if ! has_cmd git; then
        note_warn "Falta git — no se puede instalar $uuid"
        return 1
    fi

    local tmp
    tmp="$(mktemp -d)"
    if ! git clone --depth 1 "$url" "$tmp/src" >/dev/null 2>&1; then
        rm -rf "$tmp"
        note_warn "No se pudo clonar $url — $uuid no se instaló"
        return 1
    fi

    if [[ ! -f "$tmp/src/metadata.json" ]]; then
        rm -rf "$tmp"
        note_warn "$url no parece una extensión de GNOME (falta metadata.json)"
        return 1
    fi

    mkdir -p "$(dirname "$destino")"
    rm -rf "$destino"
    mkdir -p "$destino/schemas"
    cp "$tmp/src"/*.js "$tmp/src/metadata.json" "$destino/" 2>/dev/null
    cp "$tmp/src/schemas/"*.gschema.xml "$destino/schemas/" 2>/dev/null
    rm -rf "$tmp"

    if has_cmd glib-compile-schemas; then
        glib-compile-schemas "$destino/schemas" 2>/dev/null \
            || note_warn "No se pudieron compilar los schemas de $uuid"
    fi

    habilitar_extension "$uuid"
    record_action "extensión de git instalada: $uuid"
    note_ok "Extensión instalada desde git: $uuid"
}

# Los schemas de una extensión viven dentro de su propia carpeta, no en la ruta
# global de glib. Sin esto, `gsettings set` falla con "No existe el esquema" y —
# peor — el módulo sigue de largo creyendo que configuró algo.
ext_schemadir() {
    local uuid="$1" dir
    for dir in "$HOME/.local/share/gnome-shell/extensions/$uuid/schemas" \
               "/usr/share/gnome-shell/extensions/$uuid/schemas"
    do
        if [[ -f "$dir/gschemas.compiled" ]]; then
            printf '%s' "$dir"
            return 0
        fi
    done
    return 1
}

# ext_set <schemadir> <schema> <key> <valor>
ext_set() {
    local schemadir="$1" schema="$2" key="$3" valor="$4"

    if [[ "$DRY_RUN" == "1" ]]; then
        printf '  %s[dry]%s gsettings set %s %s %s\n' "$C_DIM" "$C_RESET" "$schema" "$key" "$valor"
        return 0
    fi

    gsettings --schemadir "$schemadir" set "$schema" "$key" "$valor" \
        || note_warn "no se pudo setear $schema $key"
}

configurar_panel() {
    local schema=org.gnome.shell.extensions.mactahoe-tweaks
    local sd

    if [[ "$DRY_RUN" == "1" ]]; then
        sd="(dry-run)"
    elif ! sd="$(ext_schemadir mactahoe-tweaks@son.local)"; then
        note_warn "Schema de mactahoe-tweaks sin compilar — la barra superior queda gris"
        return 0
    fi

    log_info "Configurando la barra superior..."

    # LA TRAMPA DE UBUNTU 26.04, que costó una tarde encontrar:
    #
    #   /usr/share/gnome-shell/theme/Yaru/gnome-shell-dark.css
    #   #panel { background-color: #131313 !important; }
    #
    # Ese `!important` le gana a `#panel { background-color: transparent }` de
    # MacTahoe pase lo que pase, porque en la cascada CSS un `!important` de
    # autor vence a cualquier declaración normal venga de la hoja que venga. Por
    # eso la barra se veía gris oscuro fijo (medido con `setup/shot.sh --probe`:
    # RGB(19,19,19) = #131313) aunque el tema pidiera transparencia — y por eso
    # el componente `panel` de Blur my Shell tampoco hacía nada, porque también
    # pone la transparencia con una clase CSS normal.
    #
    # Lo único que gana desde una extensión, sin editar archivos de /usr, es el
    # estilo inline del actor. Eso hace panelStyle.js de mactahoe-tweaks.
    ext_set "$sd" "$schema" panel-background "'rgba(0, 0, 0, 0.30)'"
    ext_set "$sd" "$schema" panel-blur-radius 30
    ext_set "$sd" "$schema" panel-blur-brightness 0.65

    note_ok "Barra superior transparente con desenfoque (pisando el !important de Yaru)"
}

configurar_blur() {
    local schema=org.gnome.shell.extensions.blur-my-shell
    local sd

    habilitar_extension blur-my-shell@aunetx

    if [[ "$DRY_RUN" == "1" ]]; then
        sd="(dry-run)"
    elif ! sd="$(ext_schemadir blur-my-shell@aunetx)"; then
        note_warn "No encontré los schemas de Blur my Shell — configuralo a mano desde Extension Manager"
        return 0
    fi

    log_info "Configurando el blur..."

    # El panel lo maneja mactahoe-tweaks (ver configurar_panel). El componente de
    # Blur my Shell queda apagado a propósito: no es que "no haga falta", es que
    # NO PUEDE — pone la transparencia con la clase CSS `#panel.transparent-panel`,
    # que pierde contra el `!important` de Yaru. Dejarlo prendido sólo agregaría
    # un segundo desenfoque encima del nuestro.
    ext_set "$sd" "$schema".panel blur false
    ext_set "$sd" "$schema".panel override-background false

    ext_set "$sd" "$schema".overview blur true
    ext_set "$sd" "$schema".appfolder blur true
    ext_set "$sd" "$schema".lockscreen blur true

    # El dock lo blurea MacOS Dock por su cuenta (dock-blur-enabled), así que
    # este componente sobra y solo duplicaría trabajo de GPU.
    ext_set "$sd" "$schema".dash-to-dock blur false

    # Blur y transparencia de ventanas.
    #
    # `dynamic-opacity` es la clave, y es la que estaba mal: con true, Blur my
    # Shell vuelve SÓLIDA la ventana que tiene el foco (applications.js:134,
    # comentario literal `// make the currently focused window solid`). O sea que
    # el efecto se veía sólo mientras la ventana no estaba enfocada — de ahí que
    # "durara unos segundos" y desapareciera al volver a la Calculadora.
    ext_set "$sd" "$schema".applications blur true
    ext_set "$sd" "$schema".applications enable-all true
    ext_set "$sd" "$schema".applications dynamic-opacity false
    ext_set "$sd" "$schema".applications opacity 190

    note_ok "Transparencia de ventanas arreglada (dynamic-opacity apagado)"
    note_todo "Si Chrome o VS Code muestran artefactos: subí hacks-level a 2, y si sigue, sumalos a la blacklist de 'applications'"
    note_todo "Los menús del panel y la barra superior los maneja mactahoe-tweaks: Blur my Shell no puede con ninguno de los dos"
}

configurar_dock_macos() {
    local schema=org.gnome.shell.extensions.macosdock
    local sd

    if [[ "$DRY_RUN" == "1" ]]; then
        sd="(dry-run)"
    elif ! sd="$(ext_schemadir macos-dock@son.local)"; then
        note_warn "No encontré los schemas del fork de MacOS Dock — configuralo a mano desde Extension Manager"
        return 0
    fi

    log_info "Configurando el dock estilo macOS..."

    ext_set "$sd" "$schema" dock-position 0        # 0 = abajo

    # icon-size y magnification-scale estan atados: el icono magnificado mide
    # icon-size * magnification-scale, y el tope que queremos es 52 px.
    # 40 * 1.3 = 52.0 exacto. Si subis uno, baja el otro.
    #
    # El alto del rectangulo no se configura aparte: sale de icon-size
    # (dockManager.js, _dockHeight = icon-size + 16 + 8). Con 40 son 64 px.
    ext_set "$sd" "$schema" icon-size 40

    # Siempre a la vista. Contrapartida honesta: sin auto-hide GNOME igual no le
    # reserva espacio en pantalla (el dock vive en el "top chrome", no es un
    # panel), así que una ventana maximizada le pasa por debajo. Es el mismo
    # comportamiento que macOS con "ocultar el Dock" desactivado.
    ext_set "$sd" "$schema" auto-hide false
    ext_set "$sd" "$schema" animation-duration 200

    # Lo que veníamos a buscar: los iconos crecen al pasar el cursor.
    ext_set "$sd" "$schema" magnification-enabled true
    ext_set "$sd" "$schema" magnification-scale 1.3   # 40 * 1.3 = 52 px de pico
    ext_set "$sd" "$schema" magnification-falloff 100

    ext_set "$sd" "$schema" bounce-on-launch true
    ext_set "$sd" "$schema" running-indicators true
    ext_set "$sd" "$schema" show-applications-button true

    ext_set "$sd" "$schema" dock-blur-enabled true
    ext_set "$sd" "$schema" dock-opacity 60
    ext_set "$sd" "$schema" dock-border-radius 16

    # <Super>d viene por defecto en esta extensión, pero GNOME ya lo usa para
    # "mostrar el escritorio". Dejar los dos hace que ninguno sea predecible.
    ext_set "$sd" "$schema" toggle-dock "[]"

    # Ojo: el schema de esta extensión arrastra, del fork de Dash to Dock del que
    # nació, un montón de claves `org.gnome.shell.extensions.dash-to-dock`
    # (autohide, dock-fixed, intellihide...). Están muertas: dockManager.js sólo
    # lee `macosdock`. Tocarlas no hace absolutamente nada.

    # Sin numeros hardcodeados: ya paso una vez que el mensaje siguiera diciendo
    # 1.4x despues de bajar la escala, y el resumen es lo unico que uno lee.
    note_ok "Dock configurado (abajo, siempre visible, iconos de 40 px que crecen hasta 52)"
}

configurar_bandeja() {
    # Saca del panel superior los iconos de bandeja de Discord, Spotify,
    # Flameshot y cualquier otra app que use appindicators.
    if run gnome-extensions info ubuntu-appindicators@ubuntu.com >/dev/null 2>&1; then
        run gnome-extensions disable ubuntu-appindicators@ubuntu.com
        record_action "extensión deshabilitada: ubuntu-appindicators@ubuntu.com"
        note_ok "Iconos de bandeja apagados en la barra superior"
        note_todo "Discord corre con --use-tray-icon: apagá 'Minimizar a la bandeja' en sus ajustes o al cerrarlo queda invisible"
    fi
}

configurar_atajos() {
    log_info "Configurando atajos de teclado..."

    # ibus reclama <Super>space para cambiar de método de entrada, pero hay un
    # solo layout instalado, así que no hay entre qué alternar. Liberarlo no
    # quita nada y es lo que deja pasar el atajo de salto entre escritorios.
    run gsettings set org.freedesktop.ibus.general.hotkey triggers "[]" 2>/dev/null || true

    local sd
    if [[ "$DRY_RUN" == "1" ]]; then
        sd="(dry-run)"
    elif ! sd="$(ext_schemadir mactahoe-tweaks@son.local)"; then
        note_warn "Schema de mactahoe-tweaks sin compilar — el atajo queda en su valor por defecto"
        return 0
    fi

    ext_set "$sd" org.gnome.shell.extensions.mactahoe-tweaks \
        toggle-workspace "['<Super>space']"

    note_ok "Super+Space salta entre el escritorio 1 y el 2"
}
