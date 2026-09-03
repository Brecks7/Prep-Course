/**
 * La magnificación del dock, como la de macOS.
 *
 * Tres cosas la definen, y las tres se midieron contra la sesión viva antes de
 * escribirlas (`gshell.sh pointer` + `gshell.sh eval`, ver setup/README.md):
 *
 *  1. **La onda sigue al puntero, no al icono.** La versión anterior elegía un
 *     icono «focal» —el más cercano— y centraba la campana en *su* centro. El
 *     efecto era discreto: mientras el cursor se movía dentro de un icono no
 *     pasaba nada, y al cruzar el borde la onda entera saltaba 51 px de golpe.
 *     Medido: puntero en x=194 local, el icono de la izquierda a 49 px y el de
 *     la derecha a 41 px recibían **la misma** escala (1.146), porque las dos
 *     distancias se medían contra el icono del medio y no contra el cursor.
 *     Ahora la distancia se mide al puntero, así que la escala cambia en cada
 *     píxel de movimiento y el icono bajo el cursor sólo llega al máximo cuando
 *     el cursor está de verdad en su centro.
 *
 *  2. **Sólo se magnifica con el puntero sobre el dock.** Antes la condición de
 *     corte era `localY < -falloff`, o sea que con `falloff` en 100 los iconos
 *     ya estaban al máximo con el cursor a 82 px por encima del dock (medido:
 *     estado idéntico en (888,1030) y en (888,920)). Eso es lo que se veía como
 *     «se desplaza hacia arriba sin acercarte». La banda activa ahora es el
 *     rectángulo del dock más la altura por la que asoman los iconos grandes,
 *     que es exactamente el área que en macOS responde al cursor.
 *
 *  3. **Los iconos se apartan.** En macOS el que crece empuja a sus vecinos y
 *     el dock se ensancha; sin eso, con `icon-size` 40 el paso es de 51 px y un
 *     icono al 1.3 mide 57, así que se montaba sobre el de al lado. El reflow
 *     va por `translation_x`, que no toca la asignación del BoxLayout: el
 *     layout sigue siendo el de reposo y lo único que se mueve es el dibujo.
 *
 * El reparto del reflow: cada icono que crece `Δ = w·(s-1)` empuja a los que
 * tiene a la derecha por `Δ` entero y a sí mismo por `Δ/2` (crece simétrico
 * respecto de su centro). Restándole a todos la mitad del crecimiento total, la
 * fila queda centrada: el icono bajo el cursor no se mueve, sus vecinos se
 * abren para los dos lados y el rectángulo del fondo crece esa misma cantidad,
 * mitad y mitad. Con eso el conjunto se estira alrededor del cursor en vez de
 * solaparse.
 */
import Clutter from "gi://Clutter";
import GLib from "gi://GLib";
import { SignalManager } from "./signalManager.js";
const MIN_SCALE = 1.0;
/**
 * Cuánto se acerca al objetivo en cada tick. Es alto a propósito: en macOS el
 * icono va pegado al cursor, no lo persigue. Con 0.45 a 60 Hz la constante de
 * tiempo queda en ~25 ms, que se siente inmediato sin ser un salto duro.
 */
const LERP_FACTOR = 0.45;
const SETTLED = 0.004; // por debajo de esto se considera que ya llegó
const SETTLED_PX = 0.4; // lo mismo, para el desplazamiento horizontal
/** Holgura de la banda activa, para que el borde no sea un interruptor duro. */
const EDGE_SLACK = 4;
export class Magnification {
    _signals;
    _container;
    _enabled;
    _maxScale;
    _falloffDistance;
    _framerate;
    _pollId = null;
    _onStretch = null;
    _stretch = 0;
    /**
     * Escala y desplazamiento actuales por icono.
     *
     * Antes era un array indexado por posición. El bug: cuando se abría o
     * cerraba una app el orden de los hijos cambiaba, pero el array conservaba
     * los valores viejos (y nunca se achicaba, porque sólo tenía un `push`), así
     * que la escala de un icono terminaba aplicándose a otro y quedaban iconos
     * agrandados sin que el cursor estuviera encima. Un WeakMap por actor no se
     * puede desincronizar: si el icono muere, su entrada se va con él.
     */
    _states = new WeakMap();
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
    /**
     * Callback que recibe cuántos píxeles hay que ensanchar el rectángulo del
     * dock. Lo consume `DockManager`, que es el único que sabe dónde está el
     * fondo. Se llama en cada tick con el valor ya suavizado, así que el fondo
     * acompaña a los iconos en vez de saltar.
     */
    setOnStretch(callback) {
        this._onStretch = callback;
    }
    setEnabled(enabled) {
        this._enabled = enabled;
        if (!enabled) {
            this._relax(true);
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
        this._relax(true);
    }
    /**
     * Aplica el estado que le correspondería al puntero en (px, py), de una sola
     * vez y sin suavizado.
     *
     * Es la puerta que usan el sandbox y las mediciones: en `--headless` no hay
     * puntero de verdad, así que sin esto la magnificación no se puede
     * fotografiar y habría que verificarla a ojo en la sesión real —que es
     * justamente lo que este repo no hace—.
     */
    applyAt(px, py) {
        this._computeAndApply(px, py, true);
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
            return this._relax();
        const [px, py] = global.get_pointer();
        return this._computeAndApply(px, py, false);
    }
    /**
     * Cuánto crece un icono que está a `distance` píxeles del puntero.
     *
     * `smoothstep` y no una recta: la recta deja un pico en el centro y un
     * quiebre en el borde del alcance, y los dos se ven como un tirón cuando el
     * cursor pasa por ahí. Esta llega a los extremos con derivada cero.
     */
    _scaleFor(distance) {
        const t = 1 - distance / this._falloffDistance;
        if (t <= 0)
            return MIN_SCALE;
        const smooth = t * t * (3 - 2 * t);
        return MIN_SCALE + (this._maxScale - MIN_SCALE) * smooth;
    }
    _computeAndApply(px, py, immediate) {
        const children = this._container.get_children();
        if (children.length === 0)
            return false;
        // Posición en el escenario: _container ya no está en el origen del dock,
        // es un hijo posicionado dentro del contenedor raíz.
        const [dx, dy] = this._container.get_transformed_position();
        const [dw, dh] = this._container.get_size();
        const localX = px - dx;
        const localY = py - dy;
        // La banda activa: el rectángulo del dock, más la franja de arriba por
        // la que asoma el icono magnificado (en macOS esa franja también
        // responde al cursor, porque el icono grande está ahí). Ni un píxel más:
        // el bug que se veía como «se levanta sin acercarte» era justamente que
        // esta condición usaba `falloff` —100 px— como alcance vertical.
        const rise = Math.ceil(children[0].get_height() * (this._maxScale - MIN_SCALE));
        const inside = localY >= -rise - EDGE_SLACK &&
            localY <= dh + EDGE_SLACK &&
            localX >= -EDGE_SLACK &&
            localX <= dw + EDGE_SLACK;
        if (!inside)
            return this._relax(immediate);
        // Escala objetivo de cada hijo, por distancia del puntero a su centro
        // **en reposo** (get_x() es la asignación del BoxLayout, que el reflow
        // no toca porque va por translation_x).
        const widths = [];
        const targets = [];
        for (const child of children) {
            const w = child.get_width();
            const center = child.get_x() + w / 2;
            widths.push(w);
            // Los separadores no se magnifican —una línea que se estira se ve
            // mal y en macOS no pasa— pero sí se corren con el resto.
            targets.push(child._isSeparator ? MIN_SCALE : this._scaleFor(Math.abs(localX - center)));
        }
        let pending = false;
        // Suavizado primero: el reflow tiene que calcularse sobre las escalas
        // que se van a pintar en este frame, no sobre las del objetivo. Si no,
        // los iconos se apartan de golpe mientras el arte todavía está creciendo.
        const scales = [];
        for (let i = 0; i < children.length; i++) {
            const state = this._stateOf(children[i]);
            const next = this._approach(state.scale, targets[i], SETTLED, immediate);
            if (next !== state.scale)
                pending = true;
            state.scale = next;
            scales.push(next);
        }
        let growth = 0;
        for (let i = 0; i < children.length; i++)
            growth += widths[i] * (scales[i] - MIN_SCALE);
        const half = growth / 2;
        let before = 0;
        for (let i = 0; i < children.length; i++) {
            const child = children[i];
            const state = this._stateOf(child);
            const delta = widths[i] * (scales[i] - MIN_SCALE);
            // Empuje entero de los que están a la izquierda, medio del propio
            // (crece simétrico), menos la mitad del total para quedar centrado.
            const shift = before + delta / 2 - half;
            before += delta;
            if (Math.abs(shift - state.shift) >= SETTLED_PX)
                pending = true;
            state.shift = shift;
            this._paint(child, state);
        }
        this._publishStretch(growth);
        return pending;
    }
    _stateOf(child) {
        let state = this._states.get(child);
        if (!state) {
            state = { scale: MIN_SCALE, shift: 0 };
            this._states.set(child, state);
        }
        return state;
    }
    /**
     * Un paso de interpolación hacia `target`, o `target` si ya está encima.
     * Con `immediate` no interpola: salta al objetivo. Lo usa `applyAt()`, que
     * tiene que dejar el estado final para poder fotografiarlo.
     */
    _approach(prev, target, epsilon, immediate = false) {
        if (immediate || Math.abs(target - prev) < epsilon)
            return target;
        return prev + (target - prev) * LERP_FACTOR;
    }
    /**
     * Escribe el estado en el actor.
     *
     * La escala va en `_magActor` —el envoltorio del arte— y no en el actor
     * entero: en macOS el punto de app viva no se magnifica, se queda quieto en
     * la base del dock mientras el icono sube. El desplazamiento sí va en el
     * actor entero, para que el punto acompañe a su icono.
     */
    _paint(child, state) {
        const art = child._magActor ?? child;
        const [pivotX, pivotY] = art.get_pivot_point();
        if (pivotX !== this._pivotX || pivotY !== this._pivotY)
            art.set_pivot_point(this._pivotX, this._pivotY);
        art.scale_x = state.scale;
        art.scale_y = state.scale;
        child.translation_x = state.shift;
    }
    _publishStretch(growth) {
        const rounded = Math.round(growth);
        if (rounded === this._stretch)
            return;
        this._stretch = rounded;
        this._onStretch?.(rounded);
    }
    /** @returns true si todavía queda algo volviendo al reposo. */
    _relax(immediate = false) {
        let pending = false;
        for (const child of this._container.get_children()) {
            const state = this._stateOf(child);
            if (immediate) {
                state.scale = MIN_SCALE;
                state.shift = 0;
            }
            else {
                const scale = this._approach(state.scale, MIN_SCALE, SETTLED);
                const shift = Math.abs(state.shift) < SETTLED_PX ? 0 : state.shift * (1 - LERP_FACTOR);
                if (scale !== state.scale || shift !== state.shift)
                    pending = true;
                state.scale = scale;
                state.shift = shift;
            }
            this._paint(child, state);
        }
        this._publishStretch(0);
        return pending;
    }
}
