// Blur detrás de los menús del panel: Quick Settings, calendario e indicadores.
//
// Blur my Shell no puede hacer esto — sus componentes son panel, overview, dock,
// lockscreen, appfolders, screenshot y window-list, y no hay ninguno de menús.
// Y St no expone blur por CSS, así que tampoco se arregla desde el tema.
//
// El efecto va sobre `menu.box` (el StBoxLayout con la clase `popup-menu-content`,
// que para el hub lleva además `quick-settings`). Son dos efectos encadenados:
// Shell.BlurEffect en modo BACKGROUND desenfoca lo que hay detrás, y CornerEffect
// recorta el resultado a la caja redondeada del tema.

import Shell from 'gi://Shell';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

import {CornerEffect} from './cornerEffect.js';

const BLUR_EFFECT = 'mactahoe-menu-blur';
const CORNER_EFFECT = 'mactahoe-menu-corner';

export class MenuBlur {
    constructor(settings) {
        this._settings = settings;
        this._entries = new Map();
        this._manager = null;
        this._originalAddMenu = null;
    }

    enable() {
        this._manager = Main.panel.menuManager;

        // PopupMenuManager no avisa cuando le agregan un menú, así que envolvemos
        // addMenu. Hace falta: las extensiones que suman indicadores al panel
        // registran sus menús mucho después de que arrancamos nosotros.
        this._originalAddMenu = this._manager.addMenu;
        const self = this;
        this._manager.addMenu = function (menu, position) {
            self._originalAddMenu.call(this, menu, position);
            self._attach(menu);
        };

        for (const menu of [...this._manager._menus])
            this._attach(menu);

        this._settingsIds = [
            this._settings.connect('changed::menu-blur-radius', () => this._refreshBlur()),
            this._settings.connect('changed::menu-blur-brightness', () => this._refreshBlur()),
        ];
    }

    disable() {
        for (const id of this._settingsIds ?? [])
            this._settings.disconnect(id);
        this._settingsIds = null;

        if (this._manager && this._originalAddMenu) {
            this._manager.addMenu = this._originalAddMenu;
            this._originalAddMenu = null;
        }
        this._manager = null;

        for (const menu of [...this._entries.keys()])
            this._detach(menu);
    }

    _attach(menu) {
        const box = menu?.box;
        if (!box || this._entries.has(menu))
            return;

        const blur = new Shell.BlurEffect({
            name: BLUR_EFFECT,
            mode: Shell.BlurMode.BACKGROUND,
            radius: this._settings.get_int('menu-blur-radius'),
            brightness: this._settings.get_double('menu-blur-brightness'),
        });
        const corner = new CornerEffect();
        corner.name = CORNER_EFFECT;

        // El orden importa: primero desenfocar el fondo, después recortar.
        box.add_effect(blur);
        box.add_effect(corner);

        const entry = {box, blur, corner, alive: true};

        // La geometría solo se puede leer del theme node cuando el actor ya está
        // en escena y con estilo resuelto. Al abrir el menú siempre lo está.
        entry.openStateId = menu.connect('open-state-changed', (_menu, isOpen) => {
            if (isOpen)
                this._updateGeometry(box, corner);
        });
        entry.sizeId = box.connect('notify::size', () => this._updateGeometry(box, corner));
        entry.styleId = box.connect('style-changed', () => this._updateGeometry(box, corner));

        // Escuchamos el `destroy` del BOX, no el del menú. Cuando se emite, el
        // actor todavía existe y desconectarlo es seguro; si esperáramos al
        // `destroy` del menú el box ya podría estar liberado, y tocar un objeto
        // liberado en GJS imprime un warning que `try/catch` no atrapa
        // (`Object St.BoxLayout ... has been already disposed`). Eso llenaba el
        // journal con un bloque de stack trace por cada menú que se cerraba.
        entry.destroyId = box.connect('destroy', () => {
            entry.alive = false;
            this._detach(menu);
        });

        this._entries.set(menu, entry);
    }

    _detach(menu) {
        const entry = this._entries.get(menu);
        if (!entry)
            return;
        this._entries.delete(menu);

        const {box, alive, openStateId, sizeId, styleId, destroyId} = entry;

        // El menú sobrevive a su box, así que su señal se desconecta siempre.
        try {
            menu.disconnect(openStateId);
        } catch (_e) { /* el menú ya no existe */ }

        // Si el box ya se está destruyendo no hay nada que desconectar ni que
        // sacar: Clutter se lleva efectos y señales con él.
        if (!alive)
            return;

        box.disconnect(sizeId);
        box.disconnect(styleId);
        box.disconnect(destroyId);
        box.remove_effect_by_name(CORNER_EFFECT);
        box.remove_effect_by_name(BLUR_EFFECT);
    }

    _refreshBlur() {
        const radius = this._settings.get_int('menu-blur-radius');
        const brightness = this._settings.get_double('menu-blur-brightness');
        for (const {blur} of this._entries.values()) {
            blur.radius = radius;
            blur.brightness = brightness;
        }
    }

    // El actor incluye los márgenes del tema, así que el rectángulo que hay que
    // recortar no es el actor entero: es el actor menos esos márgenes. Sin este
    // ajuste el desenfoque desbordaría por los cuatro lados del menú.
    _updateGeometry(box, corner) {
        let node;
        try {
            node = box.get_theme_node();
        } catch (_e) {
            return; // todavía sin estilo resuelto
        }

        const [width, height] = box.get_size();
        if (width <= 0 || height <= 0)
            return;

        const left = node.get_margin(St.Side.LEFT);
        const right = node.get_margin(St.Side.RIGHT);
        const top = node.get_margin(St.Side.TOP);
        const bottom = node.get_margin(St.Side.BOTTOM);

        corner.setGeometry({
            width, height,
            x: left,
            y: top,
            clipWidth: Math.max(1, width - left - right),
            clipHeight: Math.max(1, height - top - bottom),
            radius: node.get_border_radius(St.Corner.TOPLEFT),
        });
    }
}
