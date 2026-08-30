// Botón del dock dentro del hub de arriba a la derecha (Quick Settings), con la
// misma forma y el mismo comportamiento que el de modo oscuro: un botón, dos
// estados, sin menú desplegable.
//
//   encendido  = dock fijo, siempre visible (auto-hide false)
//   apagado    = dock invisible, aparece al empujar el borde de abajo
//                (auto-hide true)
//
// Por qué acá y no en mactahoe-tweaks: lo único que hace es dar vuelta la
// gsetting `auto-hide` del propio dock, y `dockManager` ya escucha
// `changed::auto-hide` para arrancar y parar el auto-ocultado. No hace falta
// cablear nada entre las dos extensiones.
//
// Reemplaza al viejo `panelIndicator.js`, que ponía un icono suelto más en la
// barra —justo lo contrario de lo pedido— y que además nunca llegó a
// importarse desde ningún lado.

import Gio from "gi://Gio";
import GObject from "gi://GObject";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { QuickToggle, SystemIndicator } from "resource:///org/gnome/shell/ui/quickSettings.js";

// El nombre de tipo de GObject es global al proceso de gnome-shell, no al
// archivo: todas las extensiones comparten un registro y un nombre repetido
// mata la extensión al importar el módulo, antes de llegar a enable(). Ya pasó
// en este repo con `MacTahoeTweaksCornerEffect`. De ahí el prefijo `MacosDock`.
export const DockQuickToggle = GObject.registerClass(
    { GTypeName: "MacosDockQuickToggle" },
    class MacosDockQuickToggle extends QuickToggle {
        _init(settings) {
            super._init({
                title: "Dock",
                iconName: "view-pin-symbolic",
                toggleMode: true,
            });

            this._settings = settings;

            // INVERT_BOOLEAN es lo que evita toda la lógica manual: `checked` es
            // "dock fijo", que es exactamente `!auto-hide`. El bind va en los dos
            // sentidos, así que un clic escribe la gsetting y un cambio de la
            // gsetting (desde prefs, o desde el kit de setup) mueve el botón.
            settings.bind("auto-hide", this, "checked",
                Gio.SettingsBindFlags.INVERT_BOOLEAN);

            this._notifyId = this.connect("notify::checked", () => this._sync());
            this._sync();
        }

        _sync() {
            this.subtitle = this.checked ? "Fijo" : "Se oculta";
            // Chincheta clavada cuando está fijo; flecha al borde cuando hay que
            // ir a buscarlo abajo.
            this.iconName = this.checked ? "view-pin-symbolic" : "go-bottom-symbolic";
        }

        destroy() {
            if (this._notifyId) {
                this.disconnect(this._notifyId);
                this._notifyId = null;
            }
            if (this._settings) {
                Gio.Settings.unbind(this, "checked");
                this._settings = null;
            }
            super.destroy();
        }
    }
);

export const DockIndicator = GObject.registerClass(
    { GTypeName: "MacosDockQuickIndicator" },
    class MacosDockQuickIndicator extends SystemIndicator {
        _init(settings) {
            super._init();
            this._toggle = new DockQuickToggle(settings);
            this.quickSettingsItems.push(this._toggle);
        }
    }
);

/**
 * Cuelga el toggle del hub. Devuelve el indicador para poder destruirlo en
 * disable().
 */
export function addQuickToggle(settings) {
    const indicator = new DockIndicator(settings);
    const qs = Main.panel.statusArea.quickSettings;

    // Queremos que quede arriba, con los toggles grandes, no al final del
    // panel: `addExternalIndicator` lo manda al fondo. `_addItemsBefore` es
    // API privada del shell, así que se prueba y se cae al camino público —
    // la firma es la verdad, el número de versión es una pista.
    let colocado = false;
    try {
        const vecino = qs._darkMode?.quickSettingsItems?.[0];
        if (vecino && typeof qs._addItemsBefore === "function") {
            qs._addItemsBefore(indicator.quickSettingsItems, vecino, 1);
            colocado = true;
        }
    } catch (e) {
        console.error(`[macos-dock] no se pudo ubicar el toggle junto al de modo oscuro: ${e}`);
    }
    if (!colocado)
        qs.addExternalIndicator(indicator);

    return indicator;
}
