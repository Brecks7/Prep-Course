import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {ClipboardQuick} from './clipboardQuick.js';
import {GhostGuard} from './ghostGuard.js';
import {MenuBlur} from './menuBlur.js';
import {PanelStyle} from './panelStyle.js';
import {WorkspaceToggle} from './workspaceToggle.js';

export default class MacTahoeTweaks extends Extension {
    enable() {
        this._settings = this.getSettings();

        this._panelStyle = new PanelStyle(this._settings);
        this._panelStyle.enable();

        this._menuBlur = new MenuBlur(this._settings);
        this._menuBlur.enable();

        this._workspaceToggle = new WorkspaceToggle(this._settings);
        this._workspaceToggle.enable();

        // Ventanas minimizadas que se siguen dibujando (ver ghostGuard.js).
        this._ghostGuard = new GhostGuard();
        this._ghostGuard.enable();

        // El portapapeles pasa de icono suelto en la barra a ítem del hub.
        this._clipboardQuick = new ClipboardQuick();
        this._clipboardQuick.enable();
    }

    disable() {
        this._clipboardQuick?.disable();
        this._clipboardQuick = null;

        this._ghostGuard?.disable();
        this._ghostGuard = null;

        this._workspaceToggle?.disable();
        this._workspaceToggle = null;

        this._menuBlur?.disable();
        this._menuBlur = null;

        this._panelStyle?.disable();
        this._panelStyle = null;

        this._settings = null;
    }
}
