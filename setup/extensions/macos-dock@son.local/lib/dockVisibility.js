import Clutter from "gi://Clutter";
import GLib from "gi://GLib";
import Meta from "gi://Meta";
import Shell from "gi://Shell";
import * as Layout from "resource:///org/gnome/shell/ui/layout.js";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { SignalManager } from "./signalManager.js";
// Cuánta presión hay que hacer contra el borde para que aparezca el dock, y en
// cuánto tiempo.
//
// El default era 100 px, el de ubuntu-dock, y ahí estaba el «se revela una vez y
// después no». La presión que cuenta mutter no es cuánto recorriste hasta el
// borde: es cuánto **te habrías pasado** de largo, la suma de los `dy` de los
// eventos que chocan la barrera. Medido con el dispositivo virtual, dos gestos:
//
//   · barrido desde el medio de la pantalla, 192 px en 200 ms → 15 choques,
//     dispara. Es el primer paso, el que siempre funciona.
//   · el puntero ya cerca del borde, 90 px en 250 ms → 1 o 2 choques, ~18 px de
//     presión. Con umbral 100 no dispara nunca, por más veces que lo intentes.
//
// Barriendo umbrales con ese segundo gesto: 100, 40 y 20 no revelan; 10, 5 y 1
// sí. Y el falso positivo que el umbral alto venía a evitar no aparece: rozar el
// borde de lado a lado (600 px en horizontal, pegado a la última fila) no dispara
// con ningún umbral, porque moverse *a lo largo* de la barrera no suma presión.
// Por eso el default baja a 5 px — tocar el borde y seguir un instante — y queda
// en el schema como `reveal-threshold` por si con ventanas maximizadas molesta.
const PRESSURE_THRESHOLD = 5;
const PRESSURE_TIMEOUT = 1000;
// Gracia antes de esconderlo de nuevo. Cubre dos casos: que la barrera dispare
// sin que el puntero llegue a entrar al dock, y el rebote al salir y volver.
const HIDE_DELAY = 400;
export class DockVisibility {
    _signals;
    _container;
    _intellihide;
    _isShown = false;
    _isAnimating = false;
    _monitor = null;
    _animationDuration;
    _showThreshold;
    _revealThreshold;
    _hideTimeoutId = null;
    _barrier = null;
    _pressureBarrier = null;
    // Y de reposo del contenedor, la que manda dockManager._updatePosition().
    // Las animaciones parten y vuelven de acá en vez de leer container.y: si se
    // lee el actor, una transición interrumpida deja la Y corrida y el dock
    // baja 20 px más en cada ciclo.
    _shownY = null;
    _edge; // 0=bottom, 1=left, 2=right, 3=top
    constructor(container, intellihide, _dockHeight, _marginBottom, animationDuration = 200, showThreshold = 25, edge = 0, revealThreshold = PRESSURE_THRESHOLD) {
        this._signals = new SignalManager();
        this._container = container;
        this._intellihide = intellihide;
        this._animationDuration = animationDuration;
        this._showThreshold = showThreshold;
        this._edge = edge;
        this._revealThreshold = revealThreshold;
    }
    /**
     * Cambia cuánto hay que empujar el borde. Si el dock está oculto se rehace
     * la barrera en el acto; si está a la vista no hay ninguna —`_show()` la
     * destruye— y el valor nuevo entra solo cuando `_hide()` la vuelva a crear.
     */
    updateRevealThreshold(px) {
        this._revealThreshold = Math.max(1, Math.min(200, px));
        if (this._monitor && this._barrier) {
            this._destroyBarrier();
            this._createBarrier();
        }
    }
    setEdge(edge) {
        this._edge = edge;
        if (this._monitor) {
            this._destroyBarrier();
            this._createBarrier();
        }
    }
    start() {
        this._monitor = Main.layoutManager.primaryMonitor;
        if (!this._monitor) {
            console.error("[macos-dock] No primary monitor available");
            return;
        }
        // Hide the dock by making it invisible. El estado de animación arranca
        // limpio: si quedó una transición a medias de un ciclo anterior, su
        // onComplete no corre nunca y _isAnimating se queda en true, que es lo
        // que traba _show() para siempre.
        this._container.remove_all_transitions();
        this._isAnimating = false;
        this._container.visible = false;
        this._container.opacity = 255;
        this._isShown = false;
        this._intellihide.start((overlap) => {
            if (overlap && this._isShown) {
                this._hide();
            }
        });
        // Revelar: una barrera de presión en el borde del monitor.
        //
        // Antes acá había un GLib.timeout_add(150, 100, …) que leía la posición
        // del puntero diez veces por segundo, para siempre, más un handler de
        // `motion-event` sobre el stage. Ninguno de los dos servía: el poll
        // gasta CPU en reposo, y el motion-event del stage no llega cuando el
        // puntero está sobre una ventana cliente — que es justo el caso en el
        // que hay que revelar el dock. La barrera la resuelve mutter en el
        // compositor y sólo avisa cuando el puntero empuja de verdad el borde.
        this._createBarrier();
        // Esconder: NO por eventos de cruce, aunque parezca lo natural.
        // `this._container` es la raíz del dock y se crea con `reactive: false`
        // a propósito (dockManager.js: si fuera reactiva, la franja transparente
        // de holgura se comería los clics de las ventanas de abajo), y Clutter
        // no le manda `enter-event` ni `leave-event` a un actor no reactivo.
        //
        // Medido con el dispositivo virtual de Clutter, entrando y saliendo del
        // dock dos veces: la raíz recibió 0 leave-events y el icon box —que sí
        // es reactivo— recibió 4. Con los handlers colgados de la raíz nunca
        // corría nadie, así que el dock se revelaba la primera vez y se quedaba
        // a la vista para siempre. Lo esconde `_scheduleHide()`, que mira dónde
        // está el puntero en vez de esperar un evento que no llega.
    }
    updateAnimationDuration(duration) {
        this._animationDuration = Math.max(0, Math.min(1000, duration));
    }
    stop() {
        this._cancelHide();
        this._destroyBarrier();
        this._signals.disconnectAll();
        this._intellihide.stop();
        this._container.remove_all_transitions();
        this._isAnimating = false;
        if (this._shownY !== null)
            this._container.y = this._shownY;
        this._container.visible = true;
        this._container.opacity = 255;
    }
    isHidden() {
        return !this._isShown;
    }
    updateShownY(y) {
        this._shownY = y;
        // Si el dock está a la vista y quieto, seguir la posición nueva.
        if (this._isShown && !this._isAnimating)
            this._container.y = y;
    }
    /** La Y de reposo, con el actor como respaldo si todavía no llegó ninguna. */
    _restY() {
        return this._shownY ?? this._container.y;
    }
    _createBarrier() {
        if (!this._monitor || this._barrier)
            return;
        const m = this._monitor;
        // La barrera es una línea, y `directions` es el lado desde el que se la
        // empuja. Para el borde de abajo se empuja hacia -Y, o sea subiendo el
        // puntero contra el tope de la pantalla desde arriba: mutter cuenta la
        // presión en la dirección contraria al lado libre.
        //
        // El eje transversal va sobre el área de trabajo y recortado 1 px en
        // cada punta, que es lo que hace ubuntu-dock (docking.js, "minus 1 px
        // to avoid conflicting with other active corners"). A lo ancho completo
        // del monitor las puntas pisan los hot corners, y con un segundo
        // monitor pegado al costado la punta `m.x + m.width` ya es la primera
        // columna del monitor de al lado, donde esa Y no es borde de pantalla.
        const wa = Main.layoutManager.getWorkAreaForMonitor(m.index) ?? m;
        let x1, y1, x2, y2, directions;
        switch (this._edge) {
            case 1: // Left
                x1 = m.x + 1; x2 = x1;
                y1 = wa.y + 1; y2 = wa.y + wa.height - 1;
                directions = Meta.BarrierDirection.POSITIVE_X;
                break;
            case 2: // Right
                x1 = m.x + m.width - 1; x2 = x1;
                y1 = wa.y + 1; y2 = wa.y + wa.height - 1;
                directions = Meta.BarrierDirection.NEGATIVE_X;
                break;
            case 3: // Top
                y1 = m.y; y2 = y1;
                x1 = wa.x + 1; x2 = wa.x + wa.width - 1;
                directions = Meta.BarrierDirection.POSITIVE_Y;
                break;
            default: // Bottom
                y1 = m.y + m.height; y2 = y1;
                x1 = wa.x + 1; x2 = wa.x + wa.width - 1;
                directions = Meta.BarrierDirection.NEGATIVE_Y;
        }
        // Una barrera degenerada no falla: no dispara nunca, en silencio.
        if (x1 === x2 && y1 === y2) {
            console.error(`[macos-dock] barrera vacía en el borde ${this._edge} ` +
                `(monitor ${m.x},${m.y} ${m.width}x${m.height}) — no se crea`);
            return;
        }
        // El constructor cambió en GNOME 46: antes `display`, ahora `backend`.
        // Probamos el nuevo primero y caemos al viejo, en vez de mirar la
        // versión: la firma es la verdad, el número de versión es una pista.
        try {
            this._barrier = new Meta.Barrier({
                backend: global.backend,
                x1, y1, x2, y2, directions,
            });
        }
        catch (_e) {
            try {
                this._barrier = new Meta.Barrier({
                    display: global.display,
                    x1, y1, x2, y2, directions,
                });
            }
            catch (e) {
                console.error("[macos-dock] no se pudo crear la barrera de presión:", e);
                this._barrier = null;
                return;
            }
        }
        const umbral = this._revealThreshold ?? PRESSURE_THRESHOLD;
        this._pressureBarrier = new Layout.PressureBarrier(umbral, PRESSURE_TIMEOUT, Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW);
        this._pressureBarrier.connect("trigger", () => {
            console.debug("[macos-dock] barrera disparada — revelando el dock");
            this._cancelHide();
            this._show();
            // Si la barrera disparó pero el puntero nunca entra al dock (pasó de
            // largo por el borde), no habría ningún leave-event que lo esconda.
            this._scheduleHide();
        });
        this._pressureBarrier.addBarrier(this._barrier);
        console.debug(`[macos-dock] barrera de presión en (${x1},${y1})-(${x2},${y2}) ` +
            `umbral ${umbral}px/${PRESSURE_TIMEOUT}ms`);
    }
    _destroyBarrier() {
        if (this._pressureBarrier) {
            if (this._barrier)
                this._pressureBarrier.removeBarrier(this._barrier);
            this._pressureBarrier.destroy();
            this._pressureBarrier = null;
        }
        if (this._barrier) {
            this._barrier.destroy();
            this._barrier = null;
        }
    }
    _scheduleHide() {
        this._cancelHide();
        this._hideTimeoutId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, HIDE_DELAY, () => {
            this._hideTimeoutId = null;
            // Mientras el puntero siga sobre el dock —o haya una animación en
            // curso, que haría que `_hide()` se fuera sin hacer nada— se vuelve
            // a preguntar dentro de HIDE_DELAY. No es el sondeo perpetuo que
            // había antes de la barrera: este timer sólo existe mientras el
            // dock está a la vista y se apaga solo en cuanto el puntero se va.
            //
            // Acá antes se salía sin reagendar, confiando en que un leave-event
            // de la raíz volviera a pedir el escondido. Ese evento no llega
            // nunca (ver `start()`), y ese era el bug.
            if (this._isShown && (this._pointerNearEdge() || this._isAnimating)) {
                this._scheduleHide();
                return GLib.SOURCE_REMOVE;
            }
            this._hide();
            return GLib.SOURCE_REMOVE;
        });
    }
    _cancelHide() {
        if (this._hideTimeoutId !== null) {
            GLib.source_remove(this._hideTimeoutId);
            this._hideTimeoutId = null;
        }
    }
    _pointerNearEdge() {
        if (!this._monitor)
            return false;
        const [x, y] = global.get_pointer();
        const m = this._monitor;
        // Se usa la altura del dock, no el umbral de revelado: para que aparezca
        // hay que empujar el borde, pero para que se quede alcanza con estar
        // sobre él.
        const margin = Math.max(this._container.height, this._showThreshold);
        switch (this._edge) {
            case 1: return x <= m.x + margin;
            case 2: return x >= m.x + m.width - margin;
            case 3: return y <= m.y + margin;
            default: return y >= m.y + m.height - margin;
        }
    }
    _show() {
        if (this._isShown || this._isAnimating)
            return;
        this._isShown = true;
        // Con el dock a la vista la barrera sólo estorba: frenaría el puntero
        // contra un borde que ya no hay nada que revelar. Se recrea al
        // esconderlo, igual que en ubuntu-dock.
        this._destroyBarrier();
        const restY = this._restY();
        this._container.remove_all_transitions();
        if (this._animationDuration === 0) {
            this._container.y = restY;
            this._container.visible = true;
            this._container.opacity = 255;
            this._isAnimating = false;
            return;
        }
        this._isAnimating = true;
        this._container.visible = true;
        this._container.opacity = 0;
        // Slide up animation + fade in
        this._container.y = restY + 20;
        this._container.ease({
            y: restY,
            opacity: 255,
            duration: this._animationDuration,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onComplete: () => {
                this._isAnimating = false;
            },
        });
    }
    _hide() {
        if (!this._isShown || this._isAnimating)
            return;
        this._isShown = false;
        const restY = this._restY();
        this._container.remove_all_transitions();
        if (this._animationDuration === 0) {
            this._container.visible = false;
            this._container.y = restY;
            this._container.opacity = 255;
            this._isAnimating = false;
            this._createBarrier();
            return;
        }
        this._isAnimating = true;
        this._container.ease({
            y: restY + 20,
            opacity: 0,
            duration: this._animationDuration,
            mode: Clutter.AnimationMode.EASE_IN_QUAD,
            onComplete: () => {
                this._container.visible = false;
                this._container.y = restY;
                this._container.opacity = 255;
                this._isAnimating = false;
                // El dock volvió a estar oculto: sin barrera no hay forma de
                // pedirlo de nuevo.
                this._createBarrier();
            },
        });
    }
}
