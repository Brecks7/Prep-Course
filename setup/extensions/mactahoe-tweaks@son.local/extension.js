import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

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
    }

    disable() {
        this._workspaceToggle?.disable();
        this._workspaceToggle = null;

        this._menuBlur?.disable();
        this._menuBlur = null;

        this._panelStyle?.disable();
        this._panelStyle = null;

        this._settings = null;
    }
}
