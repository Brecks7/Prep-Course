#!/usr/bin/env bash
# shot.sh — sacar capturas de la sesión y medirlas.
#
# Por qué existe: en Wayland no hay forma directa de leer la pantalla desde una
# terminal. `grim` responde "compositor doesn't support wlr-screencopy" (eso es
# de wlroots, GNOME no lo implementa) y llamar a `org.gnome.Shell.Screenshot`
# por D-Bus devuelve `AccessDenied`, porque el shell sólo se lo permite a un
# puñado de nombres de bus privilegiados (el portal, gnome-settings-daemon).
#
# Lo que sí funciona es pedírselo al portal de escritorio, que es la vía que
# usan las apps de Flatpak. La primera vez GNOME muestra un diálogo de permiso;
# después se acuerda.
#
# Sin esto, ajustar el tema y el dock es adivinar. El bug de la barra superior
# gris se resolvió con `--probe`: el CSS decía `transparent` y el píxel decía
# #131313.
#
#   bash setup/shot.sh                          # pantalla completa
#   bash setup/shot.sh --wait 6                 # espera 6s (para dejar el
#                                               #  cursor sobre el dock)
#   bash setup/shot.sh --crop 560,970,800,110   # x,y,ancho,alto
#   bash setup/shot.sh --probe 300,0,60         # RGB de la columna x=300, y 0..60
#   bash setup/shot.sh --probe 300,0,60 --only-changes

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

OUT=""
WAIT=0
CROP=""
PROBE=""
ONLY_CHANGES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)   OUT="$2"; shift 2 ;;
        --wait)  WAIT="$2"; shift 2 ;;
        --crop)  CROP="$2"; shift 2 ;;
        --probe) PROBE="$2"; shift 2 ;;
        --only-changes) ONLY_CHANGES=1; shift ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) log_err "opción desconocida: $1"; exit 2 ;;
    esac
done

if [[ -z "$OUT" ]]; then
    mkdir -p "$HOME/.cache/setup-shots"
    OUT="$HOME/.cache/setup-shots/shot-$(date +%H%M%S).png"
fi

if ! python3 -c 'import gi, PIL' 2>/dev/null; then
    log_err "faltan dependencias: python3-gi y python3-pil"
    log_info "sudo apt install python3-gi python3-pil"
    exit 1
fi

if [[ "$WAIT" != "0" ]]; then
    log_info "esperando ${WAIT}s — poné la pantalla como la querés ver"
    for ((i = WAIT; i > 0; i--)); do printf '\r  %s· %2ds%s' "$C_DIM" "$i" "$C_RESET"; sleep 1; done
    printf '\r%*s\r' 12 ''
fi

# El portal contesta por una señal `Response` sobre un objeto Request, no por el
# valor de retorno de la llamada: hay que suscribirse ANTES de llamar o se pierde.
CAPTURA="$(
python3 - <<'PYEOF'
import random, sys
import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib
from urllib.parse import unquote, urlparse

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
token = 'setupshot%d' % random.randint(0, 2**31)
sender = bus.get_unique_name()[1:].replace('.', '_')
handle = f'/org/freedesktop/portal/desktop/request/{sender}/{token}'

loop = GLib.MainLoop()
box = {}

def on_response(_c, _s, _p, _i, _sig, params):
    box['code'], box['res'] = params.unpack()
    loop.quit()

bus.signal_subscribe(
    'org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request',
    'Response', handle, None, Gio.DBusSignalFlags.NONE, on_response)

try:
    bus.call_sync(
        'org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop',
        'org.freedesktop.portal.Screenshot', 'Screenshot',
        GLib.Variant('(sa{sv})', ('', {
            'handle_token': GLib.Variant('s', token),
            'interactive': GLib.Variant('b', False),
        })),
        GLib.VariantType('(o)'), Gio.DBusCallFlags.NONE, -1, None)
except GLib.Error as e:
    print(f'ERROR {e.message}', file=sys.stderr)
    raise SystemExit(1)

GLib.timeout_add_seconds(90, lambda: (loop.quit(), False)[1])
loop.run()

if box.get('code') != 0:
    print('ERROR el portal rechazó la captura (¿cerraste el diálogo?)', file=sys.stderr)
    raise SystemExit(1)

print(unquote(urlparse(box['res']['uri']).path))
PYEOF
)" || exit 1

[[ -f "$CAPTURA" ]] || { log_err "el portal no dejó ningún archivo"; exit 1; }

# El portal escribe siempre en ~/Imágenes; la movemos a donde nos sirva.
mkdir -p "$(dirname "$OUT")"
mv -f "$CAPTURA" "$OUT"

if [[ -n "$CROP" ]]; then
    CROP="$CROP" OUT="$OUT" python3 - <<'PYEOF'
import os
from PIL import Image
x, y, w, h = (int(v) for v in os.environ['CROP'].split(','))
out = os.environ['OUT']
im = Image.open(out).convert('RGB').crop((x, y, x + w, y + h))
# Escalar x2 para poder leer detalles finos (bordes del dock, altura del panel).
im.resize((im.width * 2, im.height * 2), Image.LANCZOS).save(out)
PYEOF
fi

log_ok "captura: $OUT"

if [[ -n "$PROBE" ]]; then
    PROBE="$PROBE" OUT="$OUT" ONLY_CHANGES="$ONLY_CHANGES" python3 - <<'PYEOF'
import os
from PIL import Image
x, y0, y1 = (int(v) for v in os.environ['PROBE'].split(','))
im = Image.open(os.environ['OUT']).convert('RGB')
only = os.environ['ONLY_CHANGES'] == '1'
prev = None
for y in range(y0, min(y1, im.height)):
    p = im.getpixel((x, y))
    if only and prev is not None and max(abs(a - b) for a, b in zip(p, prev)) <= 6:
        prev = p
        continue
    print(f'  x={x} y={y:4d}  rgb{p}  #{p[0]:02x}{p[1]:02x}{p[2]:02x}')
    prev = p
PYEOF
fi

printf '%s\n' "$OUT"
