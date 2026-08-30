import Clutter from "gi://Clutter";
/**
 * Manages GObject signal connections to prevent leaks.
 * Every connect() must be paired with a disconnectAll() in disable().
 */
export class SignalManager {
    _connections = [];
    connect(source, signal, callback) {
        const id = source.connect(signal, callback);
        const record = { source, signalId: id };
        this._connections.push(record);
        // Los iconos del dock se crean y se destruyen todo el tiempo (una app
        // que arranca, otra que se cierra). Cuando Clutter destruye un actor se
        // lleva sus handlers, pero el registro seguía acá: en disable() se
        // llamaba disconnect() sobre objetos ya liberados y GJS escupía
        // `Object St.BoxLayout ... has been already disposed` con stack trace.
        // Escuchando su `destroy` sacamos el registro mientras el actor todavía
        // existe.
        if (source instanceof Clutter.Actor && signal !== "destroy") {
            const purgeId = source.connect("destroy", () => {
                record.dead = true;
            });
            this._connections.push({ source, signalId: purgeId, purge: true, owner: record });
        }
        return id;
    }
    disconnectAll() {
        for (const conn of this._connections) {
            if (conn.dead || conn.owner?.dead)
                continue;
            conn.source.disconnect(conn.signalId);
        }
        this._connections = [];
    }
}
