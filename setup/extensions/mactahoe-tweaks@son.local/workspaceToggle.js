// Atajo para saltar entre el escritorio 1 y el 2.
//
// Va acá y no en un script con `gsettings` porque GNOME no tiene un atajo nativo
// de "alternar entre dos escritorios" (solo "ir al N" y "ir al último"), y en
// Wayland un comando externo no puede cambiar de escritorio: org.gnome.Shell.Eval
// está bloqueado fuera de unsafe-mode. Desde adentro del shell es trivial.

import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

const KEYBINDING = 'toggle-workspace';

export class WorkspaceToggle {
    constructor(settings) {
        this._settings = settings;
        this._action = Meta.KeyBindingAction.NONE;
    }

    enable() {
        // IGNORE_AUTOREPEAT: sin esto, mantener la tecla apretada dispara el
        // salto una vez por repetición y el escritorio parpadea.
        this._action = Main.wm.addKeybinding(
            KEYBINDING,
            this._settings,
            Meta.KeyBindingFlags.IGNORE_AUTOREPEAT,
            Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW,
            () => this._toggle()
        );

        // addKeybinding no tira si mutter rechaza el grab: devuelve NONE y sigue
        // como si nada. Eso hace que un atajo que no anda sea indistinguible de
        // uno que anda, salvo que lo digamos. Se lee con `setup/watch-shell.sh`.
        const combo = this._settings.get_strv(KEYBINDING).join(' ') || '(sin asignar)';
        if (this._action === Meta.KeyBindingAction.NONE) {
            console.error(
                `[mactahoe] ${KEYBINDING}: mutter rechazó el grab de ${combo} ` +
                '— probablemente lo tiene tomado otro atajo');
        } else {
            console.log(`[mactahoe] ${KEYBINDING}: ${combo} registrado (action=${this._action})`);
        }
    }

    disable() {
        Main.wm.removeKeybinding(KEYBINDING);
        this._action = Meta.KeyBindingAction.NONE;
    }

    _toggle() {
        const manager = global.workspace_manager;
        const current = manager.get_active_workspace_index();
        const target = current === 0 ? 1 : 0;
        const time = this._timestamp();

        // Con `dynamic-workspaces` activado el escritorio 2 no existe mientras el
        // 1 esté vacío. En ese caso lo creamos en el momento en vez de no hacer
        // nada, que es lo que pasaría si activáramos un índice inexistente.
        while (target >= manager.get_n_workspaces())
            manager.append_new_workspace(false, time);

        const workspace = manager.get_workspace_by_index(target);
        console.log(`[mactahoe] ${KEYBINDING}: ${current} -> ${target} ` +
                    `(n=${manager.get_n_workspaces()}, time=${time}, ok=${!!workspace})`);
        workspace?.activate(time);
    }

    // meta_workspace_activate() descarta la petición en silencio si el timestamp
    // es 0, y global.get_current_time() devuelve 0 cuando no hay un evento en
    // curso — que es justo lo que pasa si el atajo llega por una vía sin evento.
    // El roundtrip al servidor siempre da un timestamp válido, pero cuesta un
    // viaje ida y vuelta, así que es el plan B y no el A.
    _timestamp() {
        const time = global.get_current_time();
        if (time !== 0)
            return time;
        return global.display.get_current_time_roundtrip();
    }
}
