import { Extension } from "resource:///org/gnome/shell/extensions/extension.js";
import { DockManager } from "./lib/dockManager.js";
import { addQuickToggle } from "./lib/quickToggle.js";
export default class MacosDockExtension extends Extension {
    _dockManager = null;
    _quickToggle = null;
    enable() {
        const settings = this.getSettings();
        this._dockManager = new DockManager();
        this._dockManager.enable(settings);
        // El botón "Dock" del hub de arriba a la derecha: fijo / se oculta.
        this._quickToggle = addQuickToggle(settings);
    }
    disable() {
        if (this._quickToggle) {
            this._quickToggle.quickSettingsItems.forEach(i => i.destroy());
            this._quickToggle.destroy();
            this._quickToggle = null;
        }
        if (this._dockManager) {
            this._dockManager.disable();
            this._dockManager = null;
        }
    }
}
