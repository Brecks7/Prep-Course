import Shell from "gi://Shell";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { SignalManager } from "./signalManager.js";
/**
 * Cuántas notificaciones pendientes tiene cada app, para el globo rojo.
 *
 * La bandeja de GNOME no expone «notificaciones por app»: expone fuentes, y
 * atar una fuente a una app es lo único frágil de todo esto. Se prueban tres
 * caminos, en orden: la `Shell.App` que la fuente publica (`app`, o `_app` en
 * las fuentes del daemon de GTK), el id de escritorio que declara, y recién
 * como último recurso el título contra el nombre de la app. Si ninguno pega,
 * la fuente se ignora en vez de adivinar: un globo en el icono equivocado es
 * peor que no tener globo.
 *
 * Las señales de la bandeja cambiaron varias veces entre GNOME 45 y 50, así
 * que cada `connect` va envuelto: si una no existe, se pierde la actualización
 * en vivo de esa fuente, no la extensión entera.
 */
export class Badges {
    _signals = new SignalManager();
    _sourceSignals = new Map(); // source -> [ids]
    _onChanged = null;
    _counts = new Map();
    start(onChanged) {
        this._onChanged = onChanged;
        const tray = Main.messageTray;
        if (!tray)
            return;
        this._signals.connect(tray, "source-added", (_t, source) => {
            this._watchSource(source);
            this._recount();
        });
        this._signals.connect(tray, "source-removed", (_t, source) => {
            this._unwatchSource(source);
            this._recount();
        });
        for (const source of this._sources())
            this._watchSource(source);
        this._recount();
    }
    stop() {
        this._signals.disconnectAll();
        for (const source of [...this._sourceSignals.keys()])
            this._unwatchSource(source);
        this._counts.clear();
        this._onChanged = null;
    }
    /** Cuántas notificaciones tiene esta app ahora mismo. */
    countFor(appId) {
        return this._counts.get(appId) ?? 0;
    }
    _sources() {
        try {
            return Main.messageTray.getSources?.() ?? [];
        }
        catch {
            return [];
        }
    }
    _watchSource(source) {
        if (!source || this._sourceSignals.has(source))
            return;
        const ids = [];
        for (const signal of ["notify::count", "notification-added", "notification-removed", "notification-show"]) {
            try {
                ids.push(source.connect(signal, () => this._recount()));
            }
            catch {
                // Esa señal no existe en esta versión de GNOME; con que quede
                // una alcanza para refrescar.
            }
        }
        this._sourceSignals.set(source, ids);
    }
    _unwatchSource(source) {
        const ids = this._sourceSignals.get(source);
        if (!ids)
            return;
        for (const id of ids) {
            try {
                source.disconnect(id);
            }
            catch { }
        }
        this._sourceSignals.delete(source);
    }
    _recount() {
        const counts = new Map();
        for (const source of this._sources()) {
            const appId = this._appIdFor(source);
            if (!appId)
                continue;
            const count = this._countOf(source);
            if (count <= 0)
                continue;
            counts.set(appId, (counts.get(appId) ?? 0) + count);
        }
        this._counts = counts;
        this._onChanged?.(counts);
    }
    _countOf(source) {
        const n = source.notifications?.length;
        if (Number.isFinite(n))
            return n;
        return Number.isFinite(source.count) ? source.count : 0;
    }
    _appIdFor(source) {
        try {
            const app = source.app ?? source._app;
            if (app?.get_id)
                return app.get_id();
            const desktopId = source.appId ?? source._appId ?? source.policy?.id;
            if (typeof desktopId === "string" && desktopId.length > 0) {
                const withSuffix = desktopId.endsWith(".desktop") ? desktopId : `${desktopId}.desktop`;
                if (Shell.AppSystem.get_default().lookup_app(withSuffix))
                    return withSuffix;
            }
            const title = source.title;
            if (typeof title === "string" && title.length > 0) {
                for (const candidate of Shell.AppSystem.get_default().get_running()) {
                    if (candidate.get_name() === title)
                        return candidate.get_id();
                }
            }
        }
        catch {
            // Fuente con una forma que no conocemos: mejor sin globo.
        }
        return null;
    }
}
