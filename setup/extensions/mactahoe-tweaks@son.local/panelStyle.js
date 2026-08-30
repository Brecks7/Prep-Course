// Fondo de la barra superior.
//
// Por qué hace falta un módulo entero para esto: Ubuntu 26.04 trae, en
// /usr/share/gnome-shell/theme/Yaru/gnome-shell-dark.css, esta regla:
//
//     #panel { background-color: #131313 !important; }
//
// Ese `!important` le gana a la regla normal de MacTahoe
// (`#panel { background-color: transparent }`) sin importar el orden de las
// hojas de estilo: en la cascada, un `!important` de autor vence a cualquier
// declaración normal, venga de donde venga. Por eso la barra se veía gris fija
// (medido: RGB(19,19,19) = #131313) aunque el tema pidiera transparencia.
//
// Y por eso Blur my Shell tampoco podía: BMS pone la transparencia con una
// clase CSS normal (`#panel.transparent-panel`), que pierde igual.
//
// La única forma de ganarle desde una extensión sin editar archivos de /usr es
// el estilo inline del actor: St lo agrega al final de las propiedades del
// StThemeNode, después de todas las hojas. Como red de seguridad, stylesheet.css
// repite la regla con `!important`.

import Shell from 'gi://Shell';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const BLUR_EFFECT = 'mactahoe-panel-blur';

export class PanelStyle {
    constructor(settings) {
        this._settings = settings;
        this._panel = null;
        this._blur = null;
        this._signalIds = [];
        this._settingsIds = [];
        this._applying = false;
    }

    enable() {
        this._panel = Main.panel;

        this._apply();

        // El shell recalcula el theme node del panel al entrar y salir de la
        // vista de actividades y cuando cambia el tema. En esas transiciones el
        // estilo inline se pierde, así que hay que volver a ponerlo.
        this._signalIds = [
            [Main.overview, Main.overview.connect('showing', () => this._apply())],
            [Main.overview, Main.overview.connect('hidden', () => this._apply())],
            [this._panel, this._panel.connect('style-changed', () => this._apply())],
            [St.ThemeContext.get_for_stage(global.stage),
             St.ThemeContext.get_for_stage(global.stage).connect('changed', () => this._apply())],
        ];

        this._settingsIds = [
            'changed::panel-background',
            'changed::panel-blur-radius',
            'changed::panel-blur-brightness',
        ].map(key => this._settings.connect(key, () => this._apply()));
    }

    disable() {
        for (const id of this._settingsIds)
            this._settings.disconnect(id);
        this._settingsIds = [];

        for (const [obj, id] of this._signalIds) {
            try {
                obj.disconnect(id);
            } catch (_e) { /* el objeto ya no existe */ }
        }
        this._signalIds = [];

        if (this._panel) {
            this._panel.remove_effect_by_name(BLUR_EFFECT);
            // Devolver el panel a lo que dicte el CSS, sea lo que sea.
            this._panel.set_style(null);
        }
        this._blur = null;
        this._panel = null;
    }

    _apply() {
        if (!this._panel || this._applying)
            return;

        // set_style() dispara 'style-changed', que nos vuelve a llamar. Sin este
        // candado el shell entra en un bucle y se cuelga.
        this._applying = true;
        try {
            this._panel.set_style(
                `background-color: ${this._settings.get_string('panel-background')};`);
            this._updateBlur();
        } finally {
            this._applying = false;
        }
    }

    _updateBlur() {
        const radius = this._settings.get_int('panel-blur-radius');

        if (radius <= 0) {
            if (this._blur) {
                this._panel.remove_effect_by_name(BLUR_EFFECT);
                this._blur = null;
            }
            return;
        }

        const brightness = this._settings.get_double('panel-blur-brightness');

        if (!this._blur) {
            this._blur = new Shell.BlurEffect({
                name: BLUR_EFFECT,
                mode: Shell.BlurMode.BACKGROUND,
                radius,
                brightness,
            });
            this._panel.add_effect(this._blur);
            return;
        }

        this._blur.radius = radius;
        this._blur.brightness = brightness;
    }
}
