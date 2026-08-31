import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

import {BlurControl} from './blurControl.js';
import {ClipboardQuick} from './clipboardQuick.js';
import {GhostGuard} from './ghostGuard.js';
import {MenuBlur} from './menuBlur.js';
import {PanelDeclutter} from './panelDeclutter.js';
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

        // Interruptor de la transparencia de las ventanas, también en el hub.
        this._blurControl = new BlurControl(this._settings);
        this._blurControl.enable();

        // Va último: colapsa la barra a un solo botón, y para eso necesita que
        // los indicadores que se mudan al hub ya estén puestos.
        this._panelDeclutter = new PanelDeclutter(this.path);
        this._panelDeclutter.enable();
    }

    disable() {
        this._panelDeclutter?.disable();
        this._panelDeclutter = null;

        this._blurControl?.disable();
        this._blurControl = null;

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
