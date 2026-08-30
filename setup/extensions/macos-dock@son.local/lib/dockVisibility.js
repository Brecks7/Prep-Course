import Clutter from "gi://Clutter";
import GLib from "gi://GLib";
import Meta from "gi://Meta";
import Shell from "gi://Shell";
import * as Layout from "resource:///org/gnome/shell/ui/layout.js";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { SignalManager } from "./signalManager.js";
// Cuánta presión hay que hacer contra el borde para que aparezca el dock, y en
// cuánto tiempo. Los valores son los de ubuntu-dock: menos que esto y el dock
// salta solo al pasar rozando; más, y hay que insistir.
const PRESSURE_THRESHOLD = 100;
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
    _hideTimeoutId = null;
    _barrier = null;
    _pressureBarrier = null;
    _edge; // 0=bottom, 1=left, 2=right, 3=top
    constructor(container, intellihide, _dockHeight, _marginBottom, animationDuration = 200, showThreshold = 25, edge = 0) {
        this._signals = new SignalManager();
        this._container = container;
        this._intellihide = intellihide;
        this._animationDuration = animationDuration;
        this._showThreshold = showThreshold;
        this._edge = edge;
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
        // Hide the dock by making it invisible.
        this._container.visible = false;
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
        // Esconder: el dock es un actor del shell, así que sí recibe los eventos
        // de cruce. Al salir arranca la gracia; al volver a entrar se cancela.
        this._signals.connect(this._container, "leave-event", () => {
            this._scheduleHide();
            return Clutter.EVENT_PROPAGATE;
        });
        this._signals.connect(this._container, "enter-event", () => {
            this._cancelHide();
            return Clutter.EVENT_PROPAGATE;
        });
    }
    updateAnimationDuration(duration) {
        this._animationDuration = Math.max(0, Math.min(1000, duration));
    }
    stop() {
        this._cancelHide();
        this._destroyBarrier();
        this._signals.disconnectAll();
        this._intellihide.stop();
        this._container.visible = true;
        this._container.opacity = 255;
    }
    isHidden() {
        return !this._isShown;
    }
    updateShownY(_y) { }
    _createBarrier() {
        if (!this._monitor || this._barrier)
            return;
        const m = this._monitor;
        // La barrera es una línea, y `directions` es el lado desde el que se la
        // empuja. Para el borde de abajo se empuja hacia -Y, o sea subiendo el
        // puntero contra el tope de la pantalla desde arriba: mutter cuenta la
        // presión en la dirección contraria al lado libre.
        let x1, y1, x2, y2, directions;
        switch (this._edge) {
            case 1: // Left
                x1 = m.x; y1 = m.y; x2 = m.x; y2 = m.y + m.height;
                directions = Meta.BarrierDirection.POSITIVE_X;
                break;
            case 2: // Right
                x1 = m.x + m.width; y1 = m.y; x2 = m.x + m.width; y2 = m.y + m.height;
                directions = Meta.BarrierDirection.NEGATIVE_X;
                break;
            case 3: // Top
                x1 = m.x; y1 = m.y; x2 = m.x + m.width; y2 = m.y;
                directions = Meta.BarrierDirection.POSITIVE_Y;
                break;
            default: // Bottom
                x1 = m.x; y1 = m.y + m.height; x2 = m.x + m.width; y2 = m.y + m.height;
                directions = Meta.BarrierDirection.NEGATIVE_Y;
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
        this._pressureBarrier = new Layout.PressureBarrier(PRESSURE_THRESHOLD, PRESSURE_TIMEOUT, Shell.ActionMode.NORMAL | Shell.ActionMode.OVERVIEW);
        this._pressureBarrier.connect("trigger", () => {
            this._cancelHide();
            this._show();
            // Si la barrera disparó pero el puntero nunca entra al dock (pasó de
            // largo por el borde), no habría ningún leave-event que lo esconda.
            this._scheduleHide();
        });
        this._pressureBarrier.addBarrier(this._barrier);
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
            // Chequeo puntual, no un sondeo: si el puntero sigue sobre el borde
            // el dock se queda, y el próximo leave-event vuelve a agendar.
            if (!this._pointerNearEdge())
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
        this._isAnimating = true;
        if (this._animationDuration === 0) {
            this._container.visible = true;
            this._container.opacity = 255;
            this._isAnimating = false;
            return;
        }
        this._container.visible = true;
        this._container.opacity = 0;
        // Slide up animation + fade in
        const startY = this._container.y;
        this._container.y = startY + 20;
        this._container.ease({
            y: startY,
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
        this._isAnimating = true;
        if (this._animationDuration === 0) {
            this._container.visible = false;
            this._isAnimating = false;
            return;
        }
        const startY = this._container.y;
        this._container.ease({
            y: startY + 20,
            opacity: 0,
            duration: this._animationDuration,
            mode: Clutter.AnimationMode.EASE_IN_QUAD,
            onComplete: () => {
                this._container.visible = false;
                this._container.y = startY;
                this._isAnimating = false;
            },
        });
    }
}
