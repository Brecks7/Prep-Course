// La transparencia de las ventanas, con interruptor.
//
// `blur-my-shell` desenfoca y transparenta **todas** las ventanas: su
// `applications.enable-all` viene en true y la opacidad en 190. Está bueno hasta
// que estorba —leer código sobre un fondo que se mueve cansa— y apagarlo pedía
// abrir las preferencias de la extensión y buscar la casilla.
//
// Acá se agrega, en el mismo hub donde ya está el toggle del dock:
//
//   · el cuerpo del botón enciende y apaga el desenfoque de ventanas;
//   · el menú excluye la ventana enfocada (o la vuelve a incluir), y lista lo
//     que hay excluido para sacarlo de a uno.
//
// Excluir por ventana enfocada, y no con una lista escrita a mano, es lo que
// hace que no haya que saber de antemano el `wm_class` de nada: te parás sobre
// la app que molesta y la sacás. El campo es el que compara blur-my-shell —
// `components/applications.js` mira `meta_window.get_wm_class()` contra los
// patrones de `blacklist`— así que guardamos exactamente eso.
//
// El schema de blur-my-shell NO está en el path global de gsettings: vive en la
// carpeta de esa extensión. Por eso se lo carga con `new_from_directory` en vez
// de `new Gio.Settings({schema_id})` a secas, que tiraría y —peor— aborta el
// proceso de gnome-shell entero, no sólo esta extensión.

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {
    QuickMenuToggle,
    SystemIndicator,
} from 'resource:///org/gnome/shell/ui/quickSettings.js';

const BMS_UUID = 'blur-my-shell@aunetx';
const BMS_APPS = 'org.gnome.shell.extensions.blur-my-shell.applications';

const KEY_TOGGLE = 'toggle-blur';
const KEY_EXCLUIR = 'blur-excluir-ventana';

const ICONO_ON = 'weather-fog-symbolic';
const ICONO_OFF = 'window-symbolic';

/** Dónde puede estar instalada blur-my-shell, de la más probable a la menos. */
function directoriosDeSchemas() {
    const dirs = [GLib.build_filenamev([
        GLib.get_home_dir(), '.local', 'share', 'gnome-shell',
        'extensions', BMS_UUID, 'schemas',
    ])];
    for (const base of GLib.get_system_data_dirs()) {
        dirs.push(GLib.build_filenamev([
            base, 'gnome-shell', 'extensions', BMS_UUID, 'schemas',
        ]));
    }
    return dirs;
}

/** Los ajustes de `applications` de blur-my-shell, o null si no está instalada. */
function ajustesDeBlur() {
    const global_ = Gio.SettingsSchemaSource.get_default();

    // Camino barato primero: si alguna vez el schema termina en el path global
    // (paquete de distribución), no hace falta ir a buscarlo a mano.
    if (global_?.lookup(BMS_APPS, true))
        return new Gio.Settings({schema_id: BMS_APPS});

    for (const dir of directoriosDeSchemas()) {
        try {
            const fuente = Gio.SettingsSchemaSource.new_from_directory(
                dir, global_, false);
            const schema = fuente?.lookup(BMS_APPS, false);
            if (schema)
                return new Gio.Settings({settings_schema: schema});
        } catch (_e) {
            // Ese directorio no existe o no tiene gschemas.compiled: siguiente.
        }
    }
    return null;
}

/** El `wm_class` de la ventana enfocada, o null si no hay ninguna. */
function claseEnfocada() {
    const win = global.display.focus_window;
    const clase = win?.get_wm_class();
    return clase && clase !== '' ? clase : null;
}

export const BlurToggle = GObject.registerClass(
    {GTypeName: 'MacTahoeTweaksBlurToggle'},
    class MacTahoeTweaksBlurToggle extends QuickMenuToggle {
        _init(blur) {
            super._init({
                title: 'Transparencia',
                iconName: ICONO_ON,
                toggleMode: true,
            });

            this._blur = blur;

            // El bind hace toda la lógica: un clic escribe la gsetting, y un
            // cambio hecho desde las preferencias de blur-my-shell mueve el
            // botón solo. No hay estado propio que se pueda desincronizar.
            blur.bind('blur', this, 'checked', Gio.SettingsBindFlags.DEFAULT);

            this.menu.setHeader(ICONO_ON, 'Transparencia',
                'Desenfoque de las ventanas');

            this._excluirItem = new PopupMenu.PopupMenuItem('');
            this._excluirItem.connect('activate', () => this._alternarEnfocada());
            this.menu.addMenuItem(this._excluirItem);

            this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
            this._seccion = new PopupMenu.PopupMenuSection();
            this.menu.addMenuItem(this._seccion);

            this._checkedId = this.connect('notify::checked', () => this._sync());
            this._listaId = blur.connect('changed::blacklist', () => this._sync());
            this.menu.connect('open-state-changed', (_m, abierto) => {
                if (abierto)
                    this._sync();
            });

            this._sync();
        }

        /** Saca o mete la ventana enfocada en la lista de excluidas. */
        _alternarEnfocada() {
            const clase = claseEnfocada();
            if (!clase)
                return;

            const lista = this._blur.get_strv('blacklist');
            const i = lista.indexOf(clase);
            if (i === -1)
                lista.push(clase);
            else
                lista.splice(i, 1);
            this._blur.set_strv('blacklist', lista);
        }

        _quitar(clase) {
            const lista = this._blur.get_strv('blacklist')
                .filter(c => c !== clase);
            this._blur.set_strv('blacklist', lista);
        }

        _sync() {
            const lista = this._blur.get_strv('blacklist');
            this.iconName = this.checked ? ICONO_ON : ICONO_OFF;

            if (!this.checked)
                this.subtitle = 'Apagada';
            else if (lista.length === 0)
                this.subtitle = 'En todo';
            else
                this.subtitle = `Salvo ${lista.length}`;

            // El ítem de arriba cambia de texto según dónde estés parado: es el
            // mismo gesto para sacar y para devolver.
            const clase = claseEnfocada();
            if (!clase) {
                this._excluirItem.label.text = 'No hay ventana enfocada';
                this._excluirItem.setSensitive(false);
            } else {
                const excluida = lista.includes(clase);
                this._excluirItem.label.text = excluida
                    ? `Devolver la transparencia a ${clase}`
                    : `Quitarle la transparencia a ${clase}`;
                this._excluirItem.setSensitive(true);
            }

            this._seccion.removeAll();
            if (lista.length === 0)
                return;

            const titulo = new PopupMenu.PopupMenuItem('Sin transparencia:');
            titulo.setSensitive(false);
            this._seccion.addMenuItem(titulo);

            for (const clase_ of lista) {
                const item = new PopupMenu.PopupMenuItem(`   ${clase_}`);
                item.connect('activate', () => this._quitar(clase_));
                this._seccion.addMenuItem(item);
            }
        }

        destroy() {
            if (this._checkedId) {
                this.disconnect(this._checkedId);
                this._checkedId = null;
            }
            if (this._listaId) {
                this._blur.disconnect(this._listaId);
                this._listaId = null;
            }
            if (this._blur) {
                Gio.Settings.unbind(this, 'checked');
                this._blur = null;
            }
            super.destroy();
        }
    }
);

export const BlurIndicator = GObject.registerClass(
    {GTypeName: 'MacTahoeTweaksBlurIndicator'},
    class MacTahoeTweaksBlurIndicator extends SystemIndicator {
        _init(blur) {
            super._init();
            this._toggle = new BlurToggle(blur);
            this.quickSettingsItems.push(this._toggle);
        }
    }
);

export class BlurControl {
    constructor(settings) {
        this._settings = settings;
        this._blur = null;
        this._indicador = null;
        this._atajos = [];
    }

    enable() {
        this._blur = ajustesDeBlur();
        if (!this._blur) {
            // Sin blur-my-shell no hay nada que controlar. Se avisa y se sigue:
            // el resto de los tweaks no tiene por qué caerse por esto.
            console.error('[mactahoe] no encontré los ajustes de blur-my-shell ' +
                '— el control de transparencia queda afuera');
            return;
        }

        this._indicador = new BlurIndicator(this._blur);
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
            console.error(`[mactahoe] no se pudo ubicar el blur en el hub: ${e}`);
        }
        if (!colocado)
            qs.addExternalIndicator(this._indicador);

        this._atajo(KEY_TOGGLE, () => {
            this._blur.set_boolean('blur', !this._blur.get_boolean('blur'));
        });
        this._atajo(KEY_EXCLUIR, () => {
            this._indicador?.quickSettingsItems[0]?._alternarEnfocada();
        });
    }

    /**
     * Registra un atajo y deja dicho en el journal si mutter lo rechazó:
     * `addKeybinding` devuelve NONE en silencio y un atajo muerto se ve igual
     * que uno vivo hasta que lo apretás.
     */
    _atajo(nombre, accion) {
        const action = Main.wm.addKeybinding(
            nombre,
            this._settings,
            Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW,
            accion
        );
        // Se anota aunque mutter lo haya rechazado: `addKeybinding` deja la
        // entrada puesta igual, así que en `disable()` hay que sacarla.
        this._atajos.push(nombre);

        const combo = this._settings.get_strv(nombre).join(' ') || '(sin asignar)';
        if (action === Meta.KeyBindingAction.NONE) {
            console.error(`[mactahoe] ${nombre}: mutter rechazó el grab de ${combo} ` +
                '— probablemente lo tiene tomado otro atajo');
        } else {
            console.log(`[mactahoe] ${nombre}: ${combo} registrado (action=${action})`);
        }
    }

    disable() {
        for (const nombre of this._atajos)
            Main.wm.removeKeybinding(nombre);
        this._atajos = [];

        if (this._indicador) {
            this._indicador.quickSettingsItems.forEach(i => i.destroy());
            this._indicador.destroy();
            this._indicador = null;
        }
        this._blur = null;
    }
}
