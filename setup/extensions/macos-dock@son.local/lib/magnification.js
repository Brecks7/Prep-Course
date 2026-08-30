import Clutter from "gi://Clutter";
import GLib from "gi://GLib";
import { SignalManager } from "./signalManager.js";
const MIN_SCALE = 1.0;
const LERP_FACTOR = 0.25; // smoothing factor per tick
const SETTLED = 0.002; // por debajo de esto se considera que ya llegó
export class Magnification {
    _signals;
    _container;
    _enabled;
    _maxScale;
    _falloffDistance;
    _framerate;
    _pollId = null;
    /**
     * Escala actual por icono.
     *
     * Antes era un array indexado por posición. El bug: cuando se abría o
     * cerraba una app el orden de los hijos cambiaba, pero el array conservaba
     * los valores viejos (y nunca se achicaba, porque sólo tenía un `push`), así
     * que la escala de un icono terminaba aplicándose a otro y quedaban iconos
     * agrandados sin que el cursor estuviera encima. Un WeakMap por actor no se
     * puede desincronizar: si el icono muere, su entrada se va con él.
     */
    _scales = new WeakMap();
    _pivotX = 0.5;
    _pivotY = 1.0;
    constructor(container, enabled, maxScale, falloffDistance = 100, framerate = 60) {
        this._signals = new SignalManager();
        this._container = container;
        this._enabled = enabled;
        this._maxScale = maxScale;
        this._falloffDistance = falloffDistance;
        this._framerate = framerate;
    }
    setEnabled(enabled) {
        this._enabled = enabled;
        if (!enabled) {
            this._resetAll(true);
            this._stopPoll();
        }
        else {
            this._startPoll();
        }
    }
    setMaxScale(scale) {
        this._maxScale = scale;
    }
    setFalloffDistance(distance) {
        this._falloffDistance = distance;
    }
    setFramerate(fps) {
        this._framerate = fps;
        this._restartPoll();
    }
    setPivotPoint(x, y) {
        this._pivotX = x;
        this._pivotY = y;
    }
    start() {
        // Cualquier movimiento del puntero puede empezar una animación, así que
        // el motion-event es el que despierta el bucle. Mientras nadie se acerca
        // al dock no hay ningún timer corriendo.
        this._signals.connect(global.stage, "motion-event", () => {
            if (this._enabled)
                this._startPoll();
            return Clutter.EVENT_PROPAGATE;
        });
        this._signals.connect(this._container, "leave-event", () => {
            this._startPoll(); // para animar la vuelta a 1.0
            return Clutter.EVENT_PROPAGATE;
        });
    }
    stop() {
        this._signals.disconnectAll();
        this._stopPoll();
        this._resetAll(true);
    }
    _startPoll() {
        if (this._pollId !== null)
            return;
        const interval = Math.max(1, Math.round(1000 / this._framerate));
        this._pollId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, interval, () => {
            if (this._update())
                return GLib.SOURCE_CONTINUE;
            // Nada más que animar: soltamos el timer. Antes esto corría a 60 fps
            // para siempre, despertando el proceso 60 veces por segundo aunque
            // el cursor estuviera del otro lado de la pantalla.
            this._pollId = null;
            return GLib.SOURCE_REMOVE;
        });
    }
    _stopPoll() {
        if (this._pollId !== null) {
            GLib.source_remove(this._pollId);
            this._pollId = null;
        }
    }
    _restartPoll() {
        if (this._pollId !== null) {
            this._stopPoll();
            this._startPoll();
        }
    }
    /** @returns true si todavía queda animación pendiente. */
    _update() {
        if (!this._enabled)
            return false;
        if (!this._container.visible)
            return this._resetAll();
        const children = this._container.get_children();
        if (children.length === 0)
            return false;
        const [px, py] = global.get_pointer();
        // Posición en el escenario: _container ya no está en el origen del dock,
        // es un hijo posicionado dentro del contenedor raíz.
        const [dx, dy] = this._container.get_transformed_position();
        const [, dh] = this._container.get_size();
        const localX = px - dx;
        const localY = py - dy;
        if (localY < -this._falloffDistance || localY > dh + 20)
            return this._resetAll();
        for (const child of children) {
            const [pivotX, pivotY] = child.get_pivot_point();
            if (pivotX !== this._pivotX || pivotY !== this._pivotY)
                child.set_pivot_point(this._pivotX, this._pivotY);
        }
        // Find closest icon to pointer.
        let focal = null;
        let bestDist = Infinity;
        for (const child of children) {
            const [cx] = child.get_position();
            const [cw] = child.get_size();
            const d = Math.abs(localX - (cx + cw / 2));
            if (d < bestDist) {
                bestDist = d;
                focal = child;
            }
        }
        if (!focal || bestDist > this._falloffDistance * 1.5)
            return this._resetAll();
        // Compute target scales and interpolate.
        const [fx] = focal.get_position();
        const [fw] = focal.get_size();
        const focalCenter = fx + fw / 2;
        let pending = false;
        for (const child of children) {
            const [cx] = child.get_position();
            const [cw] = child.get_size();
            const dist = Math.abs(cx + cw / 2 - focalCenter);
            const t = Math.max(0, 1 - dist / this._falloffDistance);
            const smooth = t * t * (3 - 2 * t);
            const target = MIN_SCALE + (this._maxScale - MIN_SCALE) * smooth;
            if (this._apply(child, target))
                pending = true;
        }
        return pending;
    }
    /** @returns true si el icono todavía se está moviendo. */
    _apply(child, target) {
        const prev = this._scales.get(child) ?? MIN_SCALE;
        if (Math.abs(target - prev) < SETTLED) {
            if (prev !== target) {
                this._scales.set(child, target);
                child.scale_x = target;
                child.scale_y = target;
            }
            return false;
        }
        const next = prev + (target - prev) * LERP_FACTOR;
        this._scales.set(child, next);
        child.scale_x = next;
        child.scale_y = next;
        return true;
    }
    /** @returns true si todavía queda algo volviendo a 1.0. */
    _resetAll(immediate = false) {
        let pending = false;
        for (const child of this._container.get_children()) {
            if (immediate) {
                this._scales.set(child, MIN_SCALE);
                child.scale_x = MIN_SCALE;
                child.scale_y = MIN_SCALE;
                continue;
            }
            if (this._apply(child, MIN_SCALE))
                pending = true;
        }
        return pending;
    }
}
