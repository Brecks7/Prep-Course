// El portapapeles, dentro del hub de arriba a la derecha.
//
// Antes: Clipboard Indicator ponía su propio icono suelto en la barra —
// verificado con Eval sobre `panelRight`, era el único indicador de extensión
// con ancho > 0; todos los demás (Astra Monitor, grabación de pantalla,
// accesibilidad, fuente de entrada) miden 0 y no se ven. GSConnect ya vive
// adentro del hub como toggle.
//
// Ahora: el icono de la barra se esconde y en el hub aparece "Portapapeles",
// un QuickMenuToggle cuyo menú lista lo último copiado.
//
// Por qué se lee el historial de Clipboard Indicator en vez de abrir su menú:
// un PopupMenu no se muestra si su `sourceActor` está oculto — probado en la
// sesión viva, el menú no aparecía en pantalla. Y reimplementar el historial
// entero (vigilar el portapapeles, deduplicar, persistir) sería duplicar una
// extensión que ya funciona. Así que se lee su registro, que es JSON plano:
//
//   ~/.cache/clipboard-indicator@tudmotu.com/registry.txt
//   [{"favorite":false,"mimetype":"text/plain;charset=utf-8","contents":"…"}]
//
// Es sólo lectura y con fallback: si el archivo no está o cambia de formato, el
// menú lo dice y no rompe nada. Copiar se hace con St.Clipboard, y el propio
// Clipboard Indicator registra el cambio y lo sube en su historial.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {
    QuickMenuToggle,
    SystemIndicator,
} from 'resource:///org/gnome/shell/ui/quickSettings.js';
import GObject from 'gi://GObject';

const REGISTRO = GLib.build_filenamev([
    GLib.get_user_cache_dir(),
    'clipboard-indicator@tudmotu.com',
    'registry.txt',
]);

const MAX_ITEMS = 8;
const MAX_LARGO = 44;

// Los indicadores de extensiones que se esconden de la barra: su función queda
// dentro del hub. Se los busca por el nombre de clase de su actor porque el
// "role" con el que se registran en statusArea es privado de cada extensión.
const ESCONDER = ['ClipboardIndicator'];

function leerHistorial() {
    try {
        const f = Gio.File.new_for_path(REGISTRO);
        const [ok, bytes] = f.load_contents(null);
        if (!ok)
            return null;
        const datos = JSON.parse(new TextDecoder().decode(bytes));
        if (!Array.isArray(datos))
            return null;
        return datos
            .filter(e => typeof e?.contents === 'string' && e.contents.trim() !== '')
            .map(e => e.contents);
    } catch (_e) {
        // Sin historial todavía, o formato inesperado: el menú lo informa.
        return null;
    }
}

/** Una línea, sin saltos ni espacios de más, cortada para que entre en el menú. */
function etiqueta(texto) {
    const limpio = texto.replace(/\s+/g, ' ').trim();
    return limpio.length > MAX_LARGO
        ? `${limpio.slice(0, MAX_LARGO - 1)}…`
        : limpio;
}

export const ClipboardToggle = GObject.registerClass(
    { GTypeName: 'MacTahoeTweaksClipboardToggle' },
    class MacTahoeTweaksClipboardToggle extends QuickMenuToggle {
        _init() {
            super._init({
                title: 'Portapapeles',
                iconName: 'edit-paste-symbolic',
                toggleMode: false,
            });

            this.menu.setHeader('edit-paste-symbolic', 'Portapapeles',
                'Lo último que copiaste');

            this._seccion = new PopupMenu.PopupMenuSection();
            this.menu.addMenuItem(this._seccion);

            // El cuerpo del botón abre el mismo menú que la flecha: acá no hay
            // nada que encender ni apagar, es una lista.
            this.connect('clicked', () => this.menu.open());
            this.menu.connect('open-state-changed', (_m, abierto) => {
                if (abierto)
                    this._recargar();
            });

            this._recargar();
        }

        _recargar() {
            this._seccion.removeAll();

            const historial = leerHistorial();
            if (historial === null) {
                this._vacio('No se pudo leer el historial');
                return;
            }
            if (historial.length === 0) {
                this._vacio('Todavía no copiaste nada');
                return;
            }

            for (const texto of historial.slice(-MAX_ITEMS).reverse()) {
                const item = new PopupMenu.PopupMenuItem(etiqueta(texto));
                item.connect('activate', () => {
                    St.Clipboard.get_default()
                        .set_text(St.ClipboardType.CLIPBOARD, texto);
                    Main.panel.statusArea.quickSettings.menu.close();
                });
                this._seccion.addMenuItem(item);
            }
        }

        _vacio(mensaje) {
            const item = new PopupMenu.PopupMenuItem(mensaje);
            item.setSensitive(false);
            this._seccion.addMenuItem(item);
        }
    }
);

export const ClipboardIndicatorQS = GObject.registerClass(
    { GTypeName: 'MacTahoeTweaksClipboardIndicator' },
    class MacTahoeTweaksClipboardIndicator extends SystemIndicator {
        _init() {
            super._init();
            this._toggle = new ClipboardToggle();
            this.quickSettingsItems.push(this._toggle);
        }
    }
);

export class ClipboardQuick {
    constructor() {
        this._indicador = null;
        this._escondidos = [];
        this._childAddedId = 0;
    }

    enable() {
        this._indicador = new ClipboardIndicatorQS();
        const qs = Main.panel.statusArea.quickSettings;

        // Junto a los toggles grandes, no al final del panel. `_addItemsBefore`
        // es API privada del shell: se prueba y se cae al camino público.
        let colocado = false;
        try {
            const vecino = qs._darkMode?.quickSettingsItems?.[0];
            if (vecino && typeof qs._addItemsBefore === 'function') {
                qs._addItemsBefore(this._indicador.quickSettingsItems, vecino, 1);
                colocado = true;
            }
        } catch (e) {
            console.error(`[mactahoe] no se pudo ubicar el portapapeles en el hub: ${e}`);
        }
        if (!colocado)
            qs.addExternalIndicator(this._indicador);

        this._esconderSueltos();
        // Clipboard Indicator puede cargar después que nosotros: en ese caso su
        // icono aparece más tarde en la barra y hay que esconderlo entonces.
        this._childAddedId = Main.panel._rightBox.connect('child-added',
            () => this._esconderSueltos());
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

        if (this._indicador) {
            this._indicador.quickSettingsItems.forEach(i => i.destroy());
            this._indicador.destroy();
            this._indicador = null;
        }
    }
}
