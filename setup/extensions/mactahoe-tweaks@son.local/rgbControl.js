// El RGB de la máquina, en el hub.
//
// El objetivo era prender, apagar y cambiar el color de todo desde un solo lado.
// El "solo lado" es `rgbctl`, que habla con OpenRGB y aplica el color a los dos
// módulos de RAM, la GPU y los headers de la placa. Acá se le pone el botón.
//
// Dos cosas que no son negociables en este archivo:
//
//   · **Todo asíncrono.** `rgbctl` tarda segundos: OpenRGB enumera los buses
//     SMBus en cada corrida. Una llamada bloqueante adentro de gnome-shell
//     congela el escritorio entero ese rato, porque el shell es un solo hilo.
//     Por eso `Gio.Subprocess` con `communicate_utf8_async` y nunca `spawn_sync`.
//   · **Una corrida por vez.** Si se apretan tres colores seguidos, tres
//     `openrgb` peleándose por el bus SMBus es justo la forma de colgarlo. Se
//     guarda la corrida en curso y la siguiente espera a que termine.
//
// El estado vive en dos lados a propósito: la gsetting es lo que dibuja el
// botón, y `rgbctl status` es la verdad de lo último aplicado. Se sincronizan al
// abrir el menú.

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

const KEY_TOGGLE = 'toggle-rgb';
const KEY_COLOR = 'rgb-color';
const KEY_ENCENDIDO = 'rgb-encendido';

const ICONO_ON = 'display-brightness-symbolic';
const ICONO_OFF = 'display-brightness-low-symbolic';

// Los nombres van en español porque es el idioma del resto del hub.
const COLORES = [
    ['Blanco', 'ffffff'],
    ['Rojo', 'ff0000'],
    ['Ámbar', 'ff6000'],
    ['Verde', '00ff00'],
    ['Cian', '00ffff'],
    ['Azul', '0000ff'],
    ['Magenta', 'ff00ff'],
];

/**
 * Busca el ejecutable. El módulo 80-rgb.sh deja un symlink en ~/.local/bin, que
 * es lo normal; si no está, se prueban las rutas del repo para no obligar a
 * reinstalar durante el desarrollo.
 */
function rutaDeRgbctl() {
    const candidatas = [
        GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'rgbctl']),
        GLib.build_filenamev([GLib.get_home_dir(), 'Documentos', 'Proyectos',
            'Configurador', 'setup', 'bin', 'rgb', 'rgbctl']),
    ];
    return candidatas.find(p => GLib.file_test(p, GLib.FileTest.IS_EXECUTABLE)) ?? null;
}

export const RgbToggle = GObject.registerClass(
    {GTypeName: 'MacTahoeTweaksRgbToggle'},
    class MacTahoeTweaksRgbToggle extends QuickMenuToggle {
        _init(settings, rgbctl) {
            super._init({
                title: 'Luces',
                iconName: ICONO_ON,
                toggleMode: true,
            });

            this._settings = settings;
            this._rgbctl = rgbctl;
            this._corriendo = null;   // Gio.Subprocess en curso, o null
            this._pendiente = null;   // último pedido mientras había uno corriendo

            this._settings.bind(KEY_ENCENDIDO, this, 'checked',
                Gio.SettingsBindFlags.DEFAULT);

            this.menu.setHeader(ICONO_ON, 'Luces', 'RAM, placa de video y placa madre');

            this._items = [];
            for (const [nombre, hex] of COLORES) {
                const item = new PopupMenu.PopupMenuItem(nombre);
                item.connect('activate', () => this._aplicar(hex));
                item._hex = hex;
                this.menu.addMenuItem(item);
                this._items.push(item);
            }

            this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
            this._nota = new PopupMenu.PopupMenuItem('', {reactive: false});
            this.menu.addMenuItem(this._nota);

            this._checkedId = this.connect('notify::checked',
                () => this._aplicar(this.checked ? this._color() : 'off'));
            this.menu.connect('open-state-changed', (_m, abierto) => {
                if (abierto)
                    this._sync();
            });

            this._sync();
        }

        _color() {
            const c = this._settings.get_string(KEY_COLOR);
            return /^[0-9a-fA-F]{6}$/.test(c) ? c : 'ffffff';
        }

        /**
         * Corre `rgbctl <arg>` sin bloquear el shell. Si ya hay una corrida en
         * curso, se guarda ésta como pendiente y se lanza cuando termine: dos
         * openrgb simultáneos sobre el mismo bus SMBus es lo que lo cuelga.
         */
        _aplicar(arg) {
            if (!this._rgbctl) {
                this._nota.label.text = 'No encuentro rgbctl';
                return;
            }

            if (arg !== 'off')
                this._settings.set_string(KEY_COLOR, arg);

            if (this._corriendo) {
                this._pendiente = arg;
                return;
            }

            let proc;
            try {
                proc = Gio.Subprocess.new([this._rgbctl, arg],
                    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            } catch (e) {
                console.error(`[mactahoe] no pude lanzar rgbctl: ${e}`);
                this._nota.label.text = 'No pude lanzar rgbctl';
                return;
            }

            this._corriendo = proc;
            this._nota.label.text = 'Aplicando…';

            proc.communicate_utf8_async(null, null, (p, res) => {
                let ok = false;
                try {
                    p.communicate_utf8_finish(res);
                    ok = p.get_successful();
                } catch (e) {
                    console.error(`[mactahoe] rgbctl falló: ${e}`);
                }

                this._corriendo = null;
                this._nota.label.text = ok ? '' : 'rgbctl terminó con errores';

                const siguiente = this._pendiente;
                this._pendiente = null;
                if (siguiente !== null)
                    this._aplicar(siguiente);
                else
                    this._sync();
            });
        }

        _sync() {
            const encendido = this.checked;
            this.iconName = encendido ? ICONO_ON : ICONO_OFF;

            const hex = this._color();
            const nombre = COLORES.find(([, h]) => h === hex)?.[0];
            this.subtitle = encendido ? (nombre ?? `#${hex}`) : 'Apagadas';

            for (const item of this._items)
                item.setOrnament(item._hex === hex && encendido
                    ? PopupMenu.Ornament.CHECK
                    : PopupMenu.Ornament.NONE);
        }

        destroy() {
            if (this._checkedId) {
                this.disconnect(this._checkedId);
                this._checkedId = null;
            }
            // El subproceso no se mata: `rgbctl` a mitad de camino deja el bus
            // SMBus en un estado que nadie limpió. Que termine solo.
            this._corriendo = null;
            this._pendiente = null;
            this._settings = null;
            super.destroy();
        }
    }
);

export const RgbIndicator = GObject.registerClass(
    {GTypeName: 'MacTahoeTweaksRgbIndicator'},
    class MacTahoeTweaksRgbIndicator extends SystemIndicator {
        _init(settings, rgbctl) {
            super._init();
            this._toggle = new RgbToggle(settings, rgbctl);
            this.quickSettingsItems.push(this._toggle);
        }
    }
);

export class RgbControl {
    constructor(settings) {
        this._settings = settings;
        this._indicador = null;
        this._atajos = [];
    }

    enable() {
        const rgbctl = rutaDeRgbctl();
        if (!rgbctl) {
            // Sin el CLI no hay nada que controlar. Se avisa y se sigue: el resto
            // de los tweaks no tiene por qué caerse por esto.
            console.error('[mactahoe] no encontré rgbctl — el control del RGB ' +
                'queda afuera (se instala con: bash setup/install.sh --yes --rgb)');
            return;
        }

        this._indicador = new RgbIndicator(this._settings, rgbctl);
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
            console.error(`[mactahoe] no se pudo ubicar el RGB en el hub: ${e}`);
        }
        if (!colocado)
            qs.addExternalIndicator(this._indicador);

        this._atajo(KEY_TOGGLE, () => {
            this._settings.set_boolean(KEY_ENCENDIDO,
                !this._settings.get_boolean(KEY_ENCENDIDO));
        });
    }

    _atajo(key, fn) {
        Main.wm.addKeybinding(key, this._settings,
            Meta.KeyBindingFlags.NONE, Shell.ActionMode.NORMAL, fn);
        this._atajos.push(key);
    }

    disable() {
        for (const key of this._atajos)
            Main.wm.removeKeybinding(key);
        this._atajos = [];

        if (this._indicador) {
            for (const item of this._indicador.quickSettingsItems)
                item.destroy();
            this._indicador.destroy();
            this._indicador = null;
        }
    }
}
