// La ventana fantasma: una ventana minimizada que se sigue dibujando.
//
// Se la reconoce porque los tres botones del semáforo están grises: es la
// ventana de verdad, sin foco, no una copia ni un clone.
//
// Medido en la sesión viva (unsafe mode + org.gnome.Shell.Eval), con sondas en
// el WindowActor, el minimizado de una ventana de PaperWM emite:
//
//     hide  →  show (minimized ya en true)  →  notify::minimized
//
// Es decir: mutter esconde el actor y alguien lo vuelve a mostrar — tres veces
// seguidas, medido — mientras la ventana ya está minimizada. Lo dispara el
// `move_resize_frame()` que `makeScratch()` de PaperWM hace sobre una ventana
// minimizada: el cliente commitea un buffer nuevo y el actor se re-mapea.
//
// PaperWM tiene su propio `showHandler` para esto y hasta lleva un parche
// nuestro, pero en la práctica no ataja este caso, así que el guard vive acá:
// es código propio, no depende de que otra extensión esté cargada, ni de que un
// parche sobreviva a la próxima actualización de PaperWM.
//
// Al restaurar no molesta, y no es casualidad: ahí el orden se invierte
// (`notify::minimized` con false llega ANTES del `show`), así que cuando el
// handler corre la ventana ya no está minimizada. Verificado igual que lo
// anterior, minimizando y restaurando con el guard puesto.

import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export class GhostGuard {
    constructor() {
        this._actorIds = new Map();
        this._pending = new Map();
        this._displayId = 0;
    }

    enable() {
        for (const actor of global.get_window_actors())
            this._watch(actor);

        // Las ventanas nuevas también: el fantasma no distingue.
        this._displayId = global.display.connect('window-created', (_d, win) => {
            const actor = win.get_compositor_private();
            if (actor)
                this._watch(actor);
            else
                win.connect('unmanaged', () => {});
        });
    }

    _watch(actor) {
        if (this._actorIds.has(actor))
            return;

        const showId = actor.connect('show', () => this._hideIfMinimized(actor));

        const destroyId = actor.connect('destroy', () => {
            this._actorIds.delete(actor);
        });

        this._actorIds.set(actor, [showId, destroyId]);
    }

    /**
     * Esconde el actor si su ventana está minimizada.
     *
     * Mientras el shell anima el minimizado el actor tiene que seguir visible,
     * así que en ese caso no se esconde: se reintenta al terminar. Con el
     * efecto genie esa rama no debería darse (completa el minimizado al
     * instante y anima un snapshot aparte), pero sin él la animación nativa
     * depende del actor, y esconderlo ahí la cortaría por la mitad.
     */
    _hideIfMinimized(actor) {
        const win = actor.meta_window;
        if (!win || !win.minimized || !actor.visible)
            return;

        if (!Main.wm._minimizing?.has(actor)) {
            actor.hide();
            return;
        }

        if (this._pending.has(actor))
            return;
        const id = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._pending.delete(actor);
            const w = actor.meta_window;
            if (w?.minimized && actor.visible && !Main.wm._minimizing?.has(actor))
                actor.hide();
            return GLib.SOURCE_REMOVE;
        });
        this._pending.set(actor, id);
    }

    disable() {
        if (this._displayId) {
            global.display.disconnect(this._displayId);
            this._displayId = 0;
        }
        for (const [actor, ids] of this._actorIds) {
            for (const id of ids) {
                try {
                    actor.disconnect(id);
                } catch (_e) {
                    // El actor ya se murió: nada que desconectar.
                }
            }
        }
        for (const id of this._pending.values())
            GLib.source_remove(id);
        this._pending.clear();
        this._actorIds.clear();
    }
}
