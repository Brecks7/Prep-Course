#!/usr/bin/env bash
# gshell.sh — hablarle al GNOME Shell que está corriendo, sin cerrar sesión.
#
# Todo esto pasa por `org.gnome.Shell.Eval`, que **sólo responde con unsafe mode
# habilitado**. Se prende a mano una vez por sesión y no sobrevive al logout:
#
#     Alt+F2 → lg → pestaña Evaluator → global.context.unsafe_mode = true
#
# Existe porque cada sesión que necesitó mirar el escritorio volvió a tropezar
# con lo mismo: el escapado de gdbus, cómo llegar a un actor sin poder importar
# `Main`, y que en Wayland el puntero no se mueve desde bash. Acá está resuelto.
#
#   bash setup/gshell.sh check                     ¿unsafe mode está prendido?
#   bash setup/gshell.sh eval '2+2'                JS suelto, devuelve el resultado
#   bash setup/gshell.sh eval -f script.js         lo mismo desde archivo
#   bash setup/gshell.sh find macos-dock-root      buscar actor por style_class
#   bash setup/gshell.sh tree 2                    árbol de actores visibles, N niveles
#   bash setup/gshell.sh tree --all 2              incluyendo los ocultos
#   bash setup/gshell.sh pointer                   dónde está el puntero
#   bash setup/gshell.sh pointer 960 400           moverlo (dispositivo virtual)
#   bash setup/gshell.sh push bottom               empujar un borde hasta que
#                                                  dispare la barrera de presión
#   bash setup/gshell.sh patch <archivo> <Clase>   recargar los métodos de una
#                                                  clase sin cerrar sesión
#   bash setup/gshell.sh debug                     ver los console.debug de Gjs
#
# Para ver **píxeles** no sirve esto, sirve `setup/shot.sh`: el árbol de actores
# dice qué cree el shell, no qué se dibujó. Dos diagnósticos de este repo salieron
# mal justamente por confundir las dos cosas.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# --- El transporte -----------------------------------------------------------
# gdbus devuelve `(true, '<resultado>')` o `(false, '<error>')`. El false es lo
# que sale también con unsafe mode apagado, con el mensaje vacío.
#
# Cuidado con los saltos de línea: el JS viaja como argumento de shell, así que
# un `join("\n")` adentro del script llega como salto real y Eval contesta
# `string literal contains an unescaped line break`. Para listas, unir con un
# separador de una línea (" | ") y partir del lado de bash.
_eval() {
    local js="$1" out b64
    # El JS viaja en base64. Sin esto, gdbus intenta leer el argumento como
    # texto GVariant y cualquier comilla o barra adentro del script lo rompe
    # con "unknown keyword" — que fue exactamente donde se fue media sesión.
    # Con base64 el argumento son sólo [A-Za-z0-9+/=] y no hay nada que escapar.
    b64=$(printf '%s' "$js" | base64 -w0)
    out=$(gdbus call -e -d org.gnome.Shell -o /org/gnome/Shell \
                     -m org.gnome.Shell.Eval \
                     "eval(new TextDecoder().decode(imports.gi.GLib.base64_decode('$b64')))" 2>&1)
    case "$out" in
        "(false, '')")
            log_err "Eval no respondió: falta habilitar unsafe mode"
            log_info "Alt+F2 → lg → Evaluator → global.context.unsafe_mode = true"
            return 3
            ;;
        "(false, "*)
            log_err "Eval falló: $out"
            return 1
            ;;
        "(true, "*) ;;
        *)
            log_err "gdbus falló: $out"
            return 1
            ;;
    esac
    # El shell devuelve el resultado ya pasado por JSON.stringify, y gdbus lo
    # vuelve a envolver en comillas simples. Dos capas: se desarman con python
    # porque hacerlo con expansiones de bash se rompe con cualquier comilla o
    # barra que venga adentro del resultado.
    # Dos capas de envoltorio que hay que sacar en orden: gdbus imprime el
    # texto de un GVariant (comillas simples, barras escapadas) y adentro está
    # lo que el shell pasó por JSON.stringify.
    printf '%s' "$out" | python3 -c '
import ast, json, sys
t = sys.stdin.read().strip()
t = t[len("(true, ") : -1]
try:
    t = ast.literal_eval(t)           # capa gdbus/GVariant
except Exception:
    pass
try:
    v = json.loads(t)                 # capa JSON.stringify del shell
except Exception:
    v = t
print(v if isinstance(v, str) else json.dumps(v, ensure_ascii=False))
'
}

# Prólogo que se antepone a todo: los helpers que siempre hacen falta.
#
# `imports.ui.main` NO funciona — la UI del shell es ESM y el loader legacy tira
# "import declarations may only appear at top level of a module", así que a
# `Main` no se llega. A los objetos se llega caminando `global.stage`, y a las
# clases desde una instancia viva (`Object.getPrototypeOf(x).constructor`).
# `imports.gi.*` sí anda: Clutter, GLib, Meta y St están disponibles.
PRELUDIO='const _C=imports.gi.Clutter, _G=imports.gi.GLib, _M=imports.gi.Meta;
const _t=()=>_G.get_monotonic_time();
function _find(cls, a, d) { a=a||global.stage; d=d||0;
  if (d>6) return null;
  for (const c of a.get_children()) {
    if (c.style_class===cls || c.name===cls || c.constructor.name===cls) return c;
    const r=_find(cls,c,d+1); if (r) return r; }
  return null; }
function _vd() { if (!globalThis.__gshell_vd) {
    const seat=_C.get_default_backend().get_default_seat();
    globalThis.__gshell_vd=seat.create_virtual_device(_C.InputDeviceType.POINTER_DEVICE); }
  return globalThis.__gshell_vd; }
function _abs(x,y){ _vd().notify_absolute_motion(_t(),x,y); }
function _rel(dx,dy){ _vd().notify_relative_motion(_t(),dx,dy); }
function _luego(ms,f){ _G.timeout_add(_G.PRIORITY_DEFAULT,ms,()=>{f(); return _G.SOURCE_REMOVE;}); }
'

ev() { _eval "$PRELUDIO$1"; }

# --- Subcomandos -------------------------------------------------------------
cmd_check() {
    if ev '"ok"' >/dev/null 2>&1; then
        log_ok "unsafe mode habilitado: Eval responde"
    else
        log_err "unsafe mode apagado"
        log_info "Alt+F2 → lg → Evaluator → global.context.unsafe_mode = true"
        return 3
    fi
}

cmd_eval() {
    if [[ "${1:-}" == "-f" ]]; then
        [[ -f "${2:-}" ]] || { log_err "no existe ${2:-<archivo>}"; return 2; }
        ev "$(cat "$2")"
    else
        ev "$*"
    fi
}

cmd_find() {
    local cls="${1:?falta el style_class, name o nombre de clase}"
    ev "const a=_find(${cls@Q});
        a ? a.constructor.name+' '+(a.style_class||a.name||'')+
            ' @'+a.x+','+a.y+' '+a.width+'x'+a.height+
            ' vis='+a.visible+' op='+a.opacity+' reactive='+a.reactive
          : 'no encontrado: ${cls}'"
}

cmd_tree() {
    # Por omisión no muestra los actores ocultos ni entra en ellos: el stage de
    # una sesión real tiene ~130 BoxPointer de menús cerrados, y volcarlos es
    # ruido caro. `--all` los incluye cuando de verdad hacen falta.
    local todos=0
    [[ "${1:-}" == "--all" ]] && { todos=1; shift; }
    local prof="${1:-3}"
    ev "let r=[]; const todos=$todos;
        (function w(a,d){ if(d>$prof) return;
          for(const c of a.get_children()){
            if(!todos && !c.visible) continue;
            r.push('  '.repeat(d)+c.constructor.name+' '+(c.style_class||c.name||'')+
                   ' @'+c.x+','+c.y+' '+c.width+'x'+c.height+(c.visible?'':' [oculto]'));
            w(c,d+1); } })(global.stage,0);
        r.join('\n')"
}

cmd_pointer() {
    if [[ $# -eq 0 ]]; then
        ev 'global.get_pointer().join(",")'
    else
        # En Wayland el puntero sólo se mueve por el dispositivo virtual de
        # Clutter. xdotool, wtype y ydotool no sirven: hablan X11 o /dev/uinput.
        ev "_abs(${1:?falta x}, ${2:?falta y}); 'puntero en '+global.get_pointer().join(',')"
    fi
}

cmd_push() {
    local borde="${1:-bottom}" pasos=16 delta=12
    # La barrera de presión pide ~100 px en menos de 1000 ms. 16 pasos de 12 px
    # cada 12 ms son 192 px en 192 ms: pasa con margen y sigue pareciéndose a
    # una mano empujando, no a un teletransporte.
    local x y dx dy
    case "$borde" in
        bottom) x=960;  y=1070; dx=0;  dy=$delta ;;
        top)    x=960;  y=10;   dx=0;  dy=-$delta ;;
        left)   x=10;   y=540;  dx=-$delta; dy=0 ;;
        right)  x=1910; y=540;  dx=$delta;  dy=0 ;;
        *) log_err "borde desconocido: $borde (bottom|top|left|right)"; return 2 ;;
    esac
    ev "_abs($x,$y);
        let k=0; (function f(){ _rel($dx,$dy); if(++k<$pasos) _luego(12,f); })();
        'empujando el borde $borde'"
    sleep 1
    log_info "$(ev 'global.get_pointer().join(",")' | sed 's/^/puntero ahora en /')"
}

cmd_debug() {
    # Los console.debug de las extensiones los descarta GLib salvo que
    # G_MESSAGES_DEBUG incluya el dominio Gjs. Se puede prender en caliente.
    ev "_G.setenv('G_MESSAGES_DEBUG','Gjs',true); 'G_MESSAGES_DEBUG=Gjs'"
    log_info "ahora sí aparecen; mirá con: bash setup/watch-shell.sh"
}

cmd_patch() {
    # Recargar el código de una extensión sin cerrar sesión.
    #
    # GNOME 50 sacó `ReloadExtension`, así que tocar una extensión costaba un
    # logout por iteración — el gasto más grande de este proyecto. La salida es
    # que `import()` dinámico **sí** funciona adentro de Eval:
    #
    #   - `import('file://<ruta>')` a secas devuelve el módulo **ya cargado**
    #     por el shell (el registro es el mismo), o sea la clase viva.
    #   - la misma ruta con una query distinta (`?v=<ts>`) es otra clave en ese
    #     registro, así que el archivo se lee de nuevo desde el disco.
    #
    # Copiando los métodos del segundo prototipo al primero, las instancias que
    # ya existen pasan a correr el código nuevo en el acto.
    #
    # Lo que NO hace, y por eso no reemplaza al logout para la prueba final:
    # el `constructor` ya corrió (los campos y las señales conectadas quedan
    # como estaban) y sólo alcanza a métodos del prototipo, no a los campos de
    # clase ni a lo que la extensión haya hecho en `enable()`.
    #
    #   bash setup/gshell.sh patch ~/.local/share/gnome-shell/extensions/foo/lib/bar.js Clase
    #   bash setup/gshell.sh patch <ruta-viva> Clase --from <ruta-con-el-código-nuevo>
    #   bash setup/gshell.sh patch <ruta-viva> Clase _scheduleHide _hide
    local vivo="${1:-}" clase="${2:-}" desde="" metodos=()
    shift 2 2>/dev/null
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from) desde="$2"; shift 2 ;;
            *) metodos+=("$1"); shift ;;
        esac
    done
    if [[ -z "$vivo" || -z "$clase" ]]; then
        log_err "uso: patch <archivo.js> <Clase> [--from <archivo.js>] [método...]"
        return 2
    fi
    # La ruta viva tiene que ser **la que cargó el shell** (la de ~/.local): si
    # se le pasa la copia del repo, el import sin query crea un módulo nuevo en
    # vez de devolver el vivo, y el parche no le llega a nadie.
    vivo="$(cd -- "$(dirname -- "$vivo")" && pwd)/$(basename -- "$vivo")"
    [[ -f "$vivo" ]] || { log_err "no existe $vivo"; return 2; }
    if [[ -n "$desde" ]]; then
        desde="$(cd -- "$(dirname -- "$desde")" && pwd)/$(basename -- "$desde")"
        [[ -f "$desde" ]] || { log_err "no existe $desde"; return 2; }
    else
        desde="$vivo"
    fi

    local lista="[]"
    if [[ ${#metodos[@]} -gt 0 ]]; then
        lista="$(printf '"%s",' "${metodos[@]}")"
        lista="[${lista%,}]"
    fi

    ev "globalThis.__gp = {estado: 'cargando'};
        Promise.all([
            import('file://$vivo'),
            import('file://$desde?v=' + Date.now()),
        ]).then(([a, b]) => {
            const P = a['$clase'] && a['$clase'].prototype;
            const Q = b['$clase'] && b['$clase'].prototype;
            if (!P || !Q) {
                globalThis.__gp = {estado: 'error', msg: 'la clase $clase no está exportada'};
                return;
            }
            const pedidos = $lista;
            const todos = Object.getOwnPropertyNames(Q).filter(n => n !== 'constructor' &&
                typeof Object.getOwnPropertyDescriptor(Q, n).value === 'function');
            const nombres = pedidos.length ? pedidos : todos;
            const cambiados = [], iguales = [], faltan = [];
            for (const n of nombres) {
                if (typeof Q[n] !== 'function') { faltan.push(n); continue; }
                if (typeof P[n] === 'function' && P[n].toString() === Q[n].toString()) {
                    iguales.push(n); continue;
                }
                P[n] = Q[n];
                cambiados.push(n);
            }
            globalThis.__gp = {estado: 'listo', cambiados, iguales, faltan};
        }).catch(e => { globalThis.__gp = {estado: 'error', msg: String(e.message || e)}; });
        'lanzado'" >/dev/null || return $?

    # `import()` es asíncrono: hay que esperar a que la promesa se asiente.
    local r="" i
    for i in $(seq 1 30); do
        r="$(ev 'JSON.stringify(globalThis.__gp)' 2>/dev/null)"
        [[ "$r" == *'"listo"'* || "$r" == *'"error"'* ]] && break
        sleep 0.2
    done

    printf '%s' "$r" | python3 -c '
import json, sys
try:    d = json.loads(sys.stdin.read() or "{}")
except Exception: d = {}
e = d.get("estado")
if e == "error":   print("  ✗ " + d.get("msg", "falló el import")); sys.exit(1)
if e != "listo":   print("  ✗ el import no terminó a tiempo");      sys.exit(1)
c, ig, f = d.get("cambiados", []), d.get("iguales", []), d.get("faltan", [])
print("  ✓ recargados: " + (", ".join(c) if c else "(ninguno: el disco ya coincide)"))
if ig: print("    sin cambios: " + str(len(ig)) + " método(s)")
if f:  print("  ✗ no existen en el archivo nuevo: " + ", ".join(f))
'
}


case "${1:-}" in
    check)   shift; cmd_check "$@" ;;
    eval)    shift; cmd_eval "$@" ;;
    find)    shift; cmd_find "$@" ;;
    tree)    shift; cmd_tree "$@" ;;
    pointer) shift; cmd_pointer "$@" ;;
    push)    shift; cmd_push "$@" ;;
    debug)   shift; cmd_debug "$@" ;;
    patch)   shift; cmd_patch "$@" ;;
    -h|--help|"") sed -n '2,28p' "$0" | sed 's/^# \?//' ;;
    *) log_err "subcomando desconocido: $1"; sed -n '13,25p' "$0" | sed 's/^# \?//'; exit 2 ;;
esac
