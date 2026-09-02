/**
 * probe-dock.js — le saca la foto y las medidas al dock desde adentro del shell.
 *
 * Existe porque en esta máquina ver un cambio del dock costaba un logout por
 * iteración: GNOME 50 no recarga el JS de una extensión (`_callExtensionEnable`
 * reusa el `stateObj` que ya tiene en memoria), y `shot.sh` va contra la sesión
 * real, que sigue corriendo el código viejo.
 *
 * La vuelta es que dentro del shell headless de `shell-sandbox.sh` la clase
 * `Shell.Screenshot` sí está disponible: el `AccessDenied` que uno se come por
 * D-Bus lo pone el servicio, no la clase. Así que la extensión se saca la foto
 * sola y la deja en un archivo.
 *
 * Dos trampas que cuestan una corrida cada una:
 *  · la captura tiene que ir en OTRO tick que los cambios de visibilidad —
 *    `visible = true` no se ve hasta que el shell compone un frame nuevo, y
 *    disparando en el mismo tick se guarda el frame anterior, con el dock
 *    todavía escondido;
 *  · en headless no hay ventanas, así que no hay puntos de app viva ni globos
 *    de notificación. `escenificar()` los pone a mano con el mismo código del
 *    dock, o la foto no se puede comparar con una referencia de macOS.
 */
import GLib from "gi://GLib";
import Gio from "gi://Gio";
import Shell from "gi://Shell";
import St from "gi://St";

const P = "[probe]";

/** Encola el diagnóstico: escenifica, mide, y captura unos segundos después. */
export function arm(ext, outPath, delay = 5) {
    GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, delay, () => {
        intentar("escenificar", () => escenificar(ext));
        intentar("medir", () => medir(ext));
        global.stage.queue_redraw();
        GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3, () => {
            intentar("captura", () => capturar(outPath));
            return GLib.SOURCE_REMOVE;
        });
        return GLib.SOURCE_REMOVE;
    });
}

function intentar(que, fn) {
    try {
        fn();
    }
    catch (e) {
        console.log(`${P} ${que} falló: ${e}`);
    }
}

function line(tag, actor) {
    const [w, h] = actor.get_size();
    const [x, y] = actor.get_transformed_position();
    console.log(`${P} ${tag} ${w}x${h} @${x},${y} vis=${actor.visible} op=${actor.opacity}`);
}

function medir(ext) {
    const dm = ext._dockManager;
    if (!dm) {
        console.log(`${P} sin dockManager`);
        return;
    }
    const s = dm._settings;
    console.log(`${P} icon=${s.get_int("icon-size")} radio=${s.get_int("dock-border-radius")} ` +
        `opacidad=${s.get_int("dock-opacity")} color=${s.get_string("dock-background-color")} ` +
        `blur=${s.get_boolean("dock-blur-enabled")}`);
    line("container", dm._container);
    line("background", dm._background);
    line("iconBox", dm._iconBox);
    let i = 0;
    for (const child of dm._iconBox.get_children()) {
        const cls = child._isSeparator ? "SEPARADOR" : (child.style_class || "?");
        line(`  [${i++}] ${cls} ${child._appData?.appId ?? ""}`, child);
    }
    const im = dm._iconManager;
    console.log(`${P} iconos=${im.getIconCount()} separadores=${im.getSeparatorCount()} ` +
        `botones=${im.getButtonCount()} papelera=${im._trashIcon?.icon_name}`);
}

function escenificar(ext) {
    const im = ext._dockManager._iconManager;
    let i = 0;
    for (const [appId, actor] of im._icons.entries()) {
        const data = actor._appData;
        data.indicatorBox.visible = true;
        data.indicatorBox.remove_all_children();
        const ventanas = i === 1 ? 2 : 1; // una app con dos ventanas, para ver dos puntos
        for (let k = 0; k < ventanas; k++) {
            data.indicatorBox.add_child(new St.Widget({
                style_class: "macos-dock-indicator-dot",
                style: `width: ${im._m.dot}px; height: ${im._m.dot}px; border-radius: ${im._m.dot}px;`,
            }));
        }
        if (appId.startsWith("discord")) {
            im._badges._counts.set(appId, 4);
            im._refreshBadge(actor, appId);
        }
        i++;
    }
    ext._dockManager._container.visible = true;
    ext._dockManager._container.opacity = 255;
}

function capturar(outPath) {
    const stream = Gio.File.new_for_path(outPath)
        .replace(null, false, Gio.FileCreateFlags.NONE, null);
    const shooter = new Shell.Screenshot();
    shooter.screenshot(false, stream, (obj, res) => {
        intentar("screenshot_finish", () => {
            obj.screenshot_finish(res);
            console.log(`${P} captura -> ${outPath}`);
        });
        intentar("close", () => stream.close(null));
    });
}
