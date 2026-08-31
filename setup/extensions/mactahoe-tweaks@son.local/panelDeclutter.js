// Dejar la barra de arriba a la derecha con un solo botón.
//
// Medido en el sandbox con una extensión de volcado descartable (no a ojo, y
// no leyendo CSS): de los cinco iconos que se veían en la barra, **ninguno era
// un indicador suelto**. Los cinco viven adentro del botón del hub, en su
// `panel-status-indicators-box`:
//
//   QuickSettings .panel-button  w=132
//     St_BoxLayout .panel-status-indicators-box  w=108
//       Indicator      network-wired-symbolic              w=24  vis=true
//       Indicator      notifications-disabled-symbolic     w=24  vis=true
//       OutputIndicator audio-volume-medium-symbolic       w=24  vis=true
//       Indicator      power-profile-performance-symbolic  w=24  vis=true
//       Indicator      system-shutdown-symbolic            w=24  vis=true
//       (y ~10 más en w=0: bluetooth, thunderbolt, cámara, micrófono, …)
//
// El resto de `_rightBox` (grabación de pantalla, compartir pantalla, click
// por reposo, accesibilidad, fuente de entrada) ya estaba con `vis=false`.
//
// Por eso no alcanza con esconderlos: si se esconden los cinco, el botón queda
// de ancho cero y no queda dónde hacer clic para abrir el hub. Lo que se hace
// es esconder la caja entera y poner un icono propio en su lugar — los dos
// interruptores del Control Center de macOS (`icons/hub-symbolic.svg`).
//
// Se esconde la **caja**, no cada indicador: `SystemIndicator` recalcula su
// propio `visible` cada vez que cambia el estado de alguno de sus iconos, así
// que un `hide()` sobre un indicador se deshace solo en cuanto te conectás a
// una red o cambia el volumen. Sobre la caja contenedora no hay nadie que lo
// revierta.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// Indicadores sueltos de otras extensiones que se esconden de la barra porque
// su función ya está adentro del hub. Se los busca por el nombre de clase de su
// actor porque el "role" con el que se registran en statusArea es privado de
// cada extensión.
const ESCONDER = ['ClipboardIndicator'];

/** La caja de iconos de estado del botón del hub, o null si GNOME la movió. */
function cajaDeIndicadores(qs) {
    if (typeof qs?._indicators?.get_children === 'function')
        return qs._indicators;
    // `_indicators` es privado: si una versión de GNOME lo renombra, todavía
    // se lo puede encontrar por su clase de estilo antes de darse por vencido.
    return qs?.get_children?.().find(
        c => c.style_class?.includes('panel-status-indicators-box')) ?? null;
}

export class PanelDeclutter {
    constructor(path) {
        this._path = path;
        this._escondidos = [];
        this._childAddedId = 0;
        this._caja = null;
        this._icono = null;
    }

    enable() {
        this._colapsarHub();
        this._esconderSueltos();
        // Un indicador puede aparecer después que nosotros: Clipboard Indicator
        // carga más tarde y mete su icono en la barra recién ahí.
        this._childAddedId = Main.panel._rightBox.connect('child-added',
            () => this._esconderSueltos());
    }

    _colapsarHub() {
        const qs = Main.panel.statusArea.quickSettings;
        const caja = cajaDeIndicadores(qs);
        if (!caja) {
            console.error('[mactahoe] no encontré la caja de indicadores del hub: ' +
                'la barra queda como estaba');
            return;
        }

        const archivo = Gio.File.new_for_path(
            GLib.build_filenamev([this._path, 'icons', 'hub-symbolic.svg']));
        this._icono = new St.Icon({
            style_class: 'system-status-icon',
            gicon: new Gio.FileIcon({file: archivo}),
        });

        caja.hide();
        // Va en el índice 0, no al final: `PanelMenu.ButtonBox` mide y aloca
        // **sólo su primer hijo** (`vfunc_get_preferred_width` y
        // `vfunc_allocate` en panelMenu.js hacen `get_first_child()`), sin
        // mirar si está visible. Con el icono de segundo, el botón seguía
        // midiendo los 132 px de la caja escondida y el icono no se alocaba.
        qs.insert_child_at_index(this._icono, 0);
        this._caja = caja;
        console.debug('[mactahoe] hub colapsado a un icono ' +
            `(${caja.get_children().length} indicadores escondidos)`);
    }

    _esconderSueltos() {
        for (const bin of Main.panel._rightBox.get_children()) {
            const hijo = bin.get_children?.()[0];
            if (!hijo || !ESCONDER.includes(hijo.constructor.name))
                continue;
            if (this._escondidos.includes(bin))
                continue;
            bin.hide();
            this._escondidos.push(bin);
        }
    }

    disable() {
        if (this._childAddedId) {
            Main.panel._rightBox.disconnect(this._childAddedId);
            this._childAddedId = 0;
        }
        for (const bin of this._escondidos) {
            try {
                bin.show();
            } catch (_e) {
                // El indicador ya no existe: su extensión se desactivó antes.
            }
        }
        this._escondidos = [];

        this._icono?.destroy();
        this._icono = null;

        // La caja se devuelve visible aunque el icono ya no esté: si no, el
        // botón del hub queda de ancho cero con la extensión apagada.
        try {
            this._caja?.show();
        } catch (_e) {
            // El hub se destruyó antes que nosotros (cierre de sesión).
        }
        this._caja = null;
    }
}
