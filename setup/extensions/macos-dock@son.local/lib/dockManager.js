import Clutter from "gi://Clutter";
import GLib from "gi://GLib";
import Meta from "gi://Meta";
import Shell from "gi://Shell";
import St from "gi://St";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { CornerEffect } from "./cornerEffect.js";
import { DockVisibility } from "./dockVisibility.js";
import { IconManager } from "./iconManager.js";
import { Intellihide } from "./intellihide.js";
import { Magnification } from "./magnification.js";
import { metrics } from "./metrics.js";
import { SignalManager } from "./signalManager.js";
const POSITIONS = { BOTTOM: 0, LEFT: 1, RIGHT: 2, TOP: 3 };
export class DockManager {
    _signals;
    _container = null;   // raíz: transparente, alta, sin recorte
    _background = null;  // el rectángulo redondeado que se ve
    _iconBox = null;     // la fila de iconos
    _cornerEffect = null;
    _intellihide = null;
    _visibility = null;
    _iconManager = null;
    _magnification = null;
    _settings = null;
    _lastFocusedApp = null;
    // {id, lista, i} del ciclado de ventanas del clic en el dock.
    _cycle = null;
    _recentlyLaunched = new Set();
    _debounceSourceId = null;
    _originalDashVisible;
    _dockPosition = POSITIONS.BOTTOM;
    _blurEffect = null;
    /** Geometría de reposo del rectángulo. La llena `_updatePosition()`. */
    _rest = null;
    /** Píxeles que el fondo tiene de más ahora mismo. Ver `_applyStretch()`. */
    _stretch = 0;
    static MARGIN_BOTTOM = 12;
    static MIN_DOCK_WIDTH = 300;
    static LAUNCH_DEBOUNCE_MS = 400;
    constructor() {
        this._signals = new SignalManager();
    }
    /** Las medidas del dock para el `icon-size` de ahora. Ver lib/metrics.js. */
    get _metrics() {
        return metrics(this._settings?.get_int("icon-size") ?? 48);
    }
    get _iconActorHeight() {
        return this._metrics.actorHeight;
    }
    get _dockHeight() {
        return this._metrics.dockThickness;
    }
    /**
     * Espacio libre que hay que reservar por fuera del rectángulo para que el
     * icono magnificado no se salga del contenedor.
     *
     * Este era el bug de "el dock queda descuadrado": la magnificación escala
     * los actores con scale_x/scale_y, y escalar NO cambia la asignación. El
     * contenedor medía exactamente el alto del rectángulo, así que un icono al
     * 1.4x se salía ~26px por arriba. Ahora el contenedor es más alto que el
     * rectángulo y el icono crece hacia adentro de esa holgura, igual que en
     * macOS, donde el icono sube por encima de la barra sin cortarse.
     */
    get _magnificationHeadroom() {
        if (!this._settings?.get_boolean("magnification-enabled"))
            return 0;
        const scale = Math.max(1, this._settings.get_double("magnification-scale"));
        return Math.ceil(this._iconActorHeight * (scale - 1));
    }
    /**
     * Lo mismo, pero a los costados: cuando la onda pasa, los iconos se apartan
     * y el rectángulo del fondo se ensancha (ver lib/magnification.js). Ese
     * crecimiento sale del contenedor raíz, así que hay que reservarlo o el
     * fondo queda cortado por la asignación.
     *
     * La cota: el crecimiento total es la suma de `ancho·(escala-1)` sobre los
     * iconos que la onda alcanza, y como la integral de la campana sobre su
     * alcance vale justo `falloff`, `(escala-1)·falloff` la acota holgadamente
     * (los iconos no llenan el eje: hay `spacing` entre ellos). Se reparte mitad
     * y mitad, y esto es lo que va de cada lado.
     */
    get _magnificationSideroom() {
        if (!this._settings?.get_boolean("magnification-enabled"))
            return 0;
        const scale = Math.max(1, this._settings.get_double("magnification-scale"));
        const falloff = Math.max(1, this._settings.get_int("magnification-falloff"));
        return Math.ceil((scale - 1) * falloff);
    }
    enable(settings) {
        this._settings = settings;
        // Hide the default GNOME dash to avoid conflict.
        this._hideDefaultDash();
        // Tres actores en vez de uno. Antes el contenedor era a la vez el
        // rectángulo pintado y la caja de iconos, y por eso el alto del
        // rectángulo le ponía techo a la animación.
        //
        //   _container   transparente, no reactivo, alto = rect + holgura
        //   _background  el rectángulo redondeado + blur, pegado abajo
        //   _iconBox     la fila de iconos, pegada abajo, sin recortar
        //
        // _container NO es reactivo a propósito: si lo fuera, la franja
        // transparente de holgura se comería los clics de las ventanas que
        // haya debajo. Los iconos son reactivos por su cuenta.
        this._container = new St.Widget({
            style_class: "macos-dock-root",
            reactive: false,
            layout_manager: new Clutter.FixedLayout(),
        });
        this._background = new St.Widget({
            style_class: "macos-dock-container",
            reactive: false,
        });
        this._iconBox = new St.BoxLayout({
            style_class: "macos-dock-iconbox",
            vertical: false,
            reactive: true,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.END,
        });
        this._container.add_child(this._background);
        this._container.add_child(this._iconBox);
        Main.layoutManager.addTopChrome(this._container);
        // Icon manager: populates the icon box with app buttons.
        this._iconManager = new IconManager(this._iconBox, settings.get_int("icon-size"), settings.get_boolean("running-indicators"), settings.get_int("icon-quality"), settings.get_int("running-indicator-style"));
        this._iconManager.setOnClicked((app) => this._onAppClicked(app));
        this._iconManager.setOnIconsChanged(() => this._updatePosition());
        // Los dos extremos del dock se aplican antes de poblarlo: si no, la
        // gsetting en `false` recién se respetaba al cambiarla a mano, y el
        // botón aparecía igual en cada arranque.
        this._iconManager.setShowAppButton(settings.get_boolean("show-applications-button"));
        this._iconManager.setShowTrash(settings.get_boolean("show-trash"));
        this._iconManager.start();
        // Magnification: scale icons on hover.
        this._magnification = new Magnification(this._iconBox, settings.get_boolean("magnification-enabled"), settings.get_double("magnification-scale"), settings.get_int("magnification-falloff"), settings.get_int("magnification-framerate"));
        this._magnification.setOnStretch((extra) => this._applyStretch(extra));
        this._magnification.start();
        this._applyDockStyle();
        this._applyDockPosition();
        this._registerKeybindings();
        this._updatePosition();
        this._signals.connect(global.display, "workareas-changed", () => this._updatePosition());
        // Watch for newly launched apps so we can bounce their dock icon.
        const tracker = Shell.WindowTracker.get_default();
        this._signals.connect(tracker, "notify::focus-app", () => this._onFocusAppChanged());
        // Live settings.
        this._signals.connect(settings, "changed::icon-size", () => {
            if (this._iconManager) {
                this._iconManager.setIconSize(settings.get_int("icon-size"));
            }
            // El padding y el spacing del iconBox se derivan del tamaño del
            // icono (lib/metrics.js), así que el estilo también se rehace.
            this._applyDockStyle();
            this._updatePosition();
        });
        this._signals.connect(settings, "changed::auto-hide", () => {
            if (settings.get_boolean("auto-hide")) {
                this._startAutoHide();
            }
            else {
                this._stopAutoHide();
            }
        });
        this._signals.connect(settings, "changed::magnification-enabled", () => {
            if (this._magnification) {
                this._magnification.setEnabled(settings.get_boolean("magnification-enabled"));
            }
            this._updatePosition();
        });
        this._signals.connect(settings, "changed::magnification-scale", () => {
            if (this._magnification) {
                this._magnification.setMaxScale(settings.get_double("magnification-scale"));
            }
            this._updatePosition();
        });
        this._signals.connect(settings, "changed::magnification-falloff", () => {
            if (this._magnification) {
                this._magnification.setFalloffDistance(settings.get_int("magnification-falloff"));
            }
        });
        this._signals.connect(settings, "changed::running-indicators", () => {
            if (this._iconManager) {
                this._iconManager.setRunningIndicatorsEnabled(settings.get_boolean("running-indicators"));
            }
        });
        this._signals.connect(settings, "changed::animation-duration", () => {
            if (this._visibility) {
                this._visibility.updateAnimationDuration(settings.get_int("animation-duration"));
            }
        });
        this._signals.connect(settings, "changed::magnification-framerate", () => {
            if (this._magnification) {
                this._magnification.setFramerate(settings.get_int("magnification-framerate"));
            }
        });
        this._signals.connect(settings, "changed::icon-quality", () => {
            if (this._iconManager) {
                this._iconManager.setQuality(settings.get_int("icon-quality"));
            }
        });
        this._signals.connect(settings, "changed::running-indicator-style", () => {
            if (this._iconManager) {
                this._iconManager.setIndicatorStyle(settings.get_int("running-indicator-style"));
            }
        });
        this._signals.connect(settings, "changed::reveal-threshold", () => {
            this._visibility?.updateRevealThreshold(settings.get_int("reveal-threshold"));
        });
        this._signals.connect(settings, "changed::show-threshold", () => {
            if (this._visibility && settings.get_boolean("auto-hide")) {
                this._startAutoHide();
            }
        });
        this._signals.connect(settings, "changed::dock-opacity", () => this._applyDockStyle());
        this._signals.connect(settings, "changed::dock-background-color", () => this._applyDockStyle());
        this._signals.connect(settings, "changed::dock-border-radius", () => this._applyDockStyle());
        this._signals.connect(settings, "changed::dock-blur-enabled", () => this._applyDockStyle());
        this._signals.connect(settings, "changed::dock-position", () => this._applyDockPosition());
        this._signals.connect(settings, "changed::show-trash", () => {
            if (this._iconManager) {
                this._iconManager.setShowTrash(settings.get_boolean("show-trash"));
            }
            this._updatePosition();
        });
        this._signals.connect(settings, "changed::show-applications-button", () => {
            if (this._iconManager) {
                this._iconManager.setShowAppButton(settings.get_boolean("show-applications-button"));
            }
            this._updatePosition();
        });
        this._signals.connect(settings, "changed::enable-keyboard-nav", () => {
            this._removeKeybindings();
            this._registerKeybindings();
        });
        if (settings.get_boolean("auto-hide")) {
            this._startAutoHide();
        }
    }
    disable() {
        if (this._visibility) {
            this._visibility.stop();
            this._visibility = null;
        }
        if (this._intellihide) {
            this._intellihide.stop();
            this._intellihide = null;
        }
        if (this._iconManager) {
            this._iconManager.stop();
            this._iconManager = null;
        }
        if (this._magnification) {
            this._magnification.stop();
            this._magnification = null;
        }
        this._removeKeybindings();
        this._signals.disconnectAll();
        if (this._debounceSourceId !== null) {
            GLib.source_remove(this._debounceSourceId);
            this._debounceSourceId = null;
        }
        if (this._container) {
            this._container.remove_effect_by_name("macos-dock-corner");
            Main.layoutManager.removeChrome(this._container);
            this._container.destroy(); // se lleva _background y _iconBox
            this._container = null;
            this._background = null;
            this._iconBox = null;
            this._blurEffect = null;
            this._cornerEffect = null;
        }
        // Restore the default GNOME dash.
        this._showDefaultDash();
        this._settings = null;
    }
    _startAutoHide() {
        if (!this._container || !this._settings)
            return;
        // Clean up any existing auto-hide before creating new.
        this._stopAutoHide();
        this._intellihide = new Intellihide();
        this._visibility = new DockVisibility(this._container, this._intellihide, this._dockHeight, DockManager.MARGIN_BOTTOM, this._settings.get_int("animation-duration"), this._settings.get_int("show-threshold"), this._dockPosition, this._settings.get_int("reveal-threshold"));
        // Must set dock rect AFTER creating intellihide so it can detect overlap.
        this._updatePosition();
        this._visibility.start();
    }
    _stopAutoHide() {
        if (this._visibility) {
            this._visibility.stop();
            this._visibility = null;
        }
        if (this._intellihide) {
            this._intellihide.stop();
            this._intellihide = null;
        }
        if (this._container) {
            this._container.visible = true;
            this._container.opacity = 255;
            this._updatePosition();
        }
    }
    _onAppClicked(app) {
        const ventanas = this._windowsForApp(app);
        if (ventanas.length === 0) {
            app.open_new_window(-1);
            return;
        }
        // Una sola ventana: el clic la esconde y la trae, como siempre.
        if (ventanas.length === 1) {
            this._cycle = null;
            this._activateWindow(ventanas[0], true);
            return;
        }
        // Varias: se cicla. El orden se congela al empezar el ciclo — si se
        // recalculara en cada clic, `activate()` acaba de mover esa ventana al
        // frente y el índice apuntaría siempre a las mismas dos.
        const id = app.get_id();
        const enfocada = global.display.focus_window;
        const seguimos = this._cycle?.id === id &&
            this._cycle.lista.length === ventanas.length &&
            this._cycle.lista.every(w => ventanas.includes(w)) &&
            this._cycle.lista.includes(enfocada);
        if (seguimos) {
            this._cycle.i = (this._cycle.i + 1) % this._cycle.lista.length;
        }
        else {
            // Ciclo nuevo: se entra por la primera del orden, que es la de tu
            // monitor y la más reciente. Si ya estabas parado en ella, se pasa
            // a la siguiente para que el clic no parezca no hacer nada.
            this._cycle = { id, lista: ventanas, i: ventanas[0] === enfocada ? 1 : 0 };
        }
        this._activateWindow(this._cycle.lista[this._cycle.i], false);
    }
    /** Trae una ventana al frente; con `alternar`, un segundo clic la minimiza. */
    _activateWindow(win, alternar) {
        if (win.minimized) {
            win.unminimize();
            win.activate(global.get_current_time());
        }
        else if (alternar && win.has_focus()) {
            win.minimize();
        }
        else {
            win.activate(global.get_current_time());
        }
    }
    /**
     * Las ventanas de una app, en el orden en que conviene visitarlas: primero
     * las del monitor donde está el puntero, y dentro de cada grupo la más
     * usada primero.
     *
     * Lo que había acá devolvía la primera de `global.get_window_actors()`, o
     * sea la de más abajo en el apilado. Con dos terminales, una por monitor,
     * eso significa que clickeás el icono en la pantalla de la izquierda y la
     * que aparece es la de la derecha: no hay ninguna relación entre el orden
     * de apilado y dónde estás mirando.
     */
    _windowsForApp(app) {
        const tracker = Shell.WindowTracker.get_default();
        const monitor = this._monitorAtPointer();
        return global.get_window_actors()
            .map(wa => wa.get_meta_window())
            .filter(w => w && !w.is_skip_taskbar() && tracker.get_window_app(w) === app)
            .sort((a, b) => {
                const ma = a.get_monitor() === monitor ? 0 : 1;
                const mb = b.get_monitor() === monitor ? 0 : 1;
                if (ma !== mb)
                    return ma - mb;
                return b.get_user_time() - a.get_user_time();
            });
    }
    /** Índice del monitor bajo el puntero, con el primario como respaldo. */
    _monitorAtPointer() {
        const [x, y] = global.get_pointer();
        for (const m of Main.layoutManager.monitors) {
            if (x >= m.x && x < m.x + m.width && y >= m.y && y < m.y + m.height)
                return m.index;
        }
        return Main.layoutManager.primaryIndex;
    }
    _onFocusAppChanged() {
        if (!this._settings)
            return;
        if (!this._settings.get_boolean("bounce-on-launch"))
            return;
        if (!this._iconManager)
            return;
        const tracker = Shell.WindowTracker.get_default();
        const app = tracker.focus_app;
        if (!app) {
            this._lastFocusedApp = null;
            return;
        }
        const appId = app.get_id();
        if (this._lastFocusedApp === app)
            return;
        this._lastFocusedApp = app;
        if (this._recentlyLaunched.has(appId))
            return;
        this._recentlyLaunched.add(appId);
        if (this._debounceSourceId !== null) {
            GLib.source_remove(this._debounceSourceId);
        }
        this._debounceSourceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, DockManager.LAUNCH_DEBOUNCE_MS, () => {
            this._recentlyLaunched.delete(appId);
            this._debounceSourceId = null;
            return GLib.SOURCE_REMOVE;
        });
        this._iconManager.bounceForApp(app);
    }
    _updatePosition() {
        if (!this._container || !this._background || !this._iconBox)
            return;
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor)
            return;
        const m = this._metrics;
        const iconCount = this._iconManager?.getIconCount() ?? 0;
        // Cada extra (los dos separadores, el botón de aplicaciones, la
        // papelera) suma su ancho más un `spacing`, porque va detrás de algo.
        const separators = this._iconManager?.getSeparatorCount() ?? 0;
        const buttons = this._iconManager?.getButtonCount() ?? 0;
        const slots = iconCount + buttons;
        // Un BoxLayout de N hijos mide la suma de los anchos más (N-1) huecos.
        // Los hijos son los slots más los separadores, y el separador es una
        // caja: la línea más su aire a los dos lados (ver _makeSeparator()).
        const children = slots + separators;
        const separatorSlot = m.separatorWidth + 2 * m.separatorMargin;
        const contentSize = children > 0
            ? slots * m.actorWidth +
                separators * separatorSlot +
                (children - 1) * m.spacing
            : 0;
        const dockAxisSize = Math.max(contentSize + 2 * m.padSide, DockManager.MIN_DOCK_WIDTH);
        const thickness = this._dockHeight;
        const headroom = this._magnificationHeadroom;
        const sideroom = this._magnificationSideroom;
        const margin = DockManager.MARGIN_BOTTOM;
        // Rectángulo visible (lo que el usuario llama "el rectángulo gris").
        let rectX = 0, rectY = 0, rectW = 0, rectH = 0;
        // Desplazamiento del rectángulo dentro del contenedor: la holgura va
        // siempre del lado hacia el que crecen los iconos, que es el opuesto al
        // borde de la pantalla donde está pegado el dock.
        let offsetX = 0, offsetY = 0;
        let containerW = 0, containerH = 0;
        switch (this._dockPosition) {
            case POSITIONS.BOTTOM:
                rectW = dockAxisSize;
                rectH = thickness;
                rectX = monitor.x + Math.floor((monitor.width - rectW) / 2);
                rectY = monitor.y + monitor.height - rectH - margin;
                containerW = rectW + 2 * sideroom;
                containerH = rectH + headroom;
                offsetX = sideroom; // se apartan hacia los dos lados
                offsetY = headroom; // crecen hacia arriba
                break;
            case POSITIONS.TOP:
                rectW = dockAxisSize;
                rectH = thickness;
                rectX = monitor.x + Math.floor((monitor.width - rectW) / 2);
                rectY = monitor.y + margin;
                containerW = rectW + 2 * sideroom;
                containerH = rectH + headroom;
                offsetX = sideroom; // se apartan hacia los dos lados
                offsetY = 0; // crecen hacia abajo
                break;
            case POSITIONS.LEFT:
                rectW = thickness;
                rectH = dockAxisSize;
                rectX = monitor.x + margin;
                rectY = monitor.y + Math.floor((monitor.height - rectH) / 2);
                containerW = rectW + headroom;
                containerH = rectH;
                offsetX = 0; // crecen hacia la derecha
                break;
            case POSITIONS.RIGHT:
                rectW = thickness;
                rectH = dockAxisSize;
                rectX = monitor.x + monitor.width - rectW - margin;
                rectY = monitor.y + Math.floor((monitor.height - rectH) / 2);
                containerW = rectW + headroom;
                containerH = rectH;
                offsetX = headroom; // crecen hacia la izquierda
                break;
        }
        this._container.set_size(containerW, containerH);
        this._container.set_position(rectX - offsetX, rectY - offsetY);
        for (const child of [this._background, this._iconBox]) {
            child.set_size(rectW, rectH);
            child.set_position(offsetX, offsetY);
        }
        // La geometría de reposo, para que `_applyStretch()` pueda ensanchar el
        // fondo en cada tick sin volver a calcular todo esto.
        this._rest = { rectW, rectH, offsetX, offsetY };
        this._stretch = 0;
        this._updateCornerGeometry(rectW, rectH);
        if (this._visibility) {
            this._visibility.updateShownY(rectY - offsetY);
        }
        if (this._intellihide) {
            // El rectángulo real, no el contenedor: si le pasáramos el
            // contenedor, una ventana maximizada solaparía la franja de holgura
            // (que es transparente) y el dock se escondería de más.
            this._intellihide.setDockRect(rectX, rectY, rectW, rectH);
        }
        // Los iconos se acaban de mover: hay que volver a decirle a las ventanas
        // dónde quedaron, o la animación de minimizar apunta al lugar viejo (y
        // si nadie la publicó nunca, al (0,0) de la esquina superior izquierda).
        this._iconManager?.queuePublishIconGeometries();
    }
    /**
     * Ensancha el rectángulo del fondo `extra` píxeles, mitad para cada lado.
     *
     * Es la contraparte del reflow: cuando la onda aparta los iconos, la fila
     * ocupa más de lo que ocupa en reposo, y si el fondo no acompaña los de los
     * extremos se salen de la píldora. En macOS el dock se ensancha igual.
     *
     * Va por el camino corto —dos llamadas al actor y los uniforms del shader—
     * porque esto corre a 60 fps: nada de barreras de presión, intellihide ni
     * geometrías de minimizado, que sólo dependen del rectángulo en reposo.
     */
    _applyStretch(extra) {
        if (!this._background || !this._rest)
            return;
        if (this._dockPosition !== POSITIONS.BOTTOM && this._dockPosition !== POSITIONS.TOP)
            return;
        const room = this._magnificationSideroom;
        const grow = Math.max(0, Math.min(Math.round(extra), 2 * room));
        if (grow === this._stretch)
            return;
        this._stretch = grow;
        const { rectW, rectH, offsetX, offsetY } = this._rest;
        const half = Math.round(grow / 2);
        this._background.set_size(rectW + grow, rectH);
        this._background.set_position(offsetX - half, offsetY);
        this._updateCornerGeometry(rectW + grow, rectH);
    }
    _hideDefaultDash() {
        const dash = Main.overview.dash;
        this._originalDashVisible = dash.visible;
        dash.hide();
        const dashSpacer = dash._dashSpacer;
        if (dashSpacer) {
            dashSpacer.visible = false;
        }
    }
    _showDefaultDash() {
        const dash = Main.overview.dash;
        dash.visible = this._originalDashVisible ?? true;
        const dashSpacer = dash._dashSpacer;
        if (dashSpacer) {
            dashSpacer.visible = true;
        }
    }
    _applyDockStyle() {
        if (!this._background || !this._iconBox || !this._settings)
            return;
        const opacity = this._settings.get_int("dock-opacity");
        const color = this._settings.get_string("dock-background-color");
        const radius = this._settings.get_int("dock-border-radius");
        const blurEnabled = this._settings.get_boolean("dock-blur-enabled");
        // Parse hex color
        const r = parseInt(color.slice(1, 3), 16) || 30;
        const g = parseInt(color.slice(3, 5), 16) || 30;
        const b = parseInt(color.slice(5, 7), 16) || 30;
        const alpha = opacity / 100;
        // El fondo pinta; la caja de iconos sólo espacia. Antes iban juntos y el
        // padding empujaba el rectángulo.
        //
        // El relieve: un hairline claro alrededor más una sombra corta abajo.
        //
        // En el dock de macOS los bordes no son iguales —medí #3D3D3D arriba y
        // #2A2A2A abajo sobre un fondo #111111— pero **St no puede hacer eso**:
        // con `border-radius`, declarar `border-top` / `border-bottom` por
        // separado no cambia nada, pinta los cuatro lados del mismo color
        // (probado: 66 arriba y 65 abajo pidiendo 0.20 y 0.05). Así que el
        // borde va parejo, en el promedio de los dos, y quien levanta la
        // píldora del fondo es el `box-shadow` — ese sí lo dibuja, y el
        // CornerEffect del blur no se lo come.
        this._background.style = `
      background-color: rgba(${r}, ${g}, ${b}, ${alpha});
      border-radius: ${radius}px;
      border: 1px solid rgba(255, 255, 255, 0.16);
      box-shadow: 0 4px 14px rgba(0, 0, 0, 0.45);
    `;
        const m = this._metrics;
        this._iconBox.style = `
      padding: ${m.padTop}px ${m.padSide}px ${m.padBottom}px ${m.padSide}px;
      spacing: ${m.spacing}px;
    `;
        // Handle blur effect
        if (blurEnabled && !this._blurEffect) {
            this._blurEffect = new Shell.BlurEffect();
            this._blurEffect.set({ sigma: 30, mode: Shell.BlurMode.BACKGROUND });
            this._background.add_effect(this._blurEffect);
            // Shell.BlurEffect desenfoca el rectángulo completo de la asignación
            // y no sabe nada del border-radius: sin este recorte se ve un
            // cuadrado borroso asomando por las cuatro esquinas del dock.
            this._cornerEffect = new CornerEffect();
            this._cornerEffect.name = "macos-dock-corner";
            this._background.add_effect(this._cornerEffect);
            this._updateCornerGeometry();
        }
        else if (!blurEnabled && this._blurEffect) {
            this._background.remove_effect(this._blurEffect);
            this._blurEffect = null;
            if (this._cornerEffect) {
                this._background.remove_effect(this._cornerEffect);
                this._cornerEffect = null;
            }
        }
        else if (blurEnabled) {
            this._updateCornerGeometry();
        }
    }
    _updateCornerGeometry(width, height) {
        if (!this._cornerEffect || !this._background)
            return;
        const [w, h] = (width && height) ? [width, height] : this._background.get_size();
        if (w <= 0 || h <= 0)
            return;
        this._cornerEffect.setGeometry({
            width: w,
            height: h,
            x: 0,
            y: 0,
            clipWidth: w,
            clipHeight: h,
            radius: this._settings?.get_int("dock-border-radius") ?? 16,
        });
    }
    _applyDockPosition() {
        if (!this._container || !this._iconBox)
            return;
        this._dockPosition = this._settings?.get_int("dock-position") ?? POSITIONS.BOTTOM;
        const isVertical = this._dockPosition === POSITIONS.LEFT || this._dockPosition === POSITIONS.RIGHT;
        if (this._iconBox)
            this._iconBox.vertical = isVertical;
        // Update magnification pivot point based on position
        if (this._magnification) {
            switch (this._dockPosition) {
                case POSITIONS.TOP:
                    this._magnification.setPivotPoint(0.5, 0.0);
                    break;
                case POSITIONS.LEFT:
                    this._magnification.setPivotPoint(0.0, 0.5);
                    break;
                case POSITIONS.RIGHT:
                    this._magnification.setPivotPoint(1.0, 0.5);
                    break;
                default: // BOTTOM
                    this._magnification.setPivotPoint(0.5, 1.0);
            }
        }
        // Update visibility edge
        if (this._visibility) {
            this._visibility.setEdge(this._dockPosition);
        }
        this._updatePosition();
    }
    _registerKeybindings() {
        if (!this._settings)
            return;
        if (!this._settings.get_boolean("enable-keyboard-nav"))
            return;
        const settings = this._settings;
        Main.wm.addKeybinding("toggle-dock", settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT, Shell.ActionMode.NORMAL, () => this._toggleDockVisibility());
        // Super+1 through Super+9, Super+0 for position 10
        for (let i = 1; i <= 9; i++) {
            Main.wm.addKeybinding(`focus-app-${i}`, settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT, Shell.ActionMode.NORMAL, () => this._focusAppByIndex(i - 1));
        }
        Main.wm.addKeybinding("focus-app-10", settings, Meta.KeyBindingFlags.IGNORE_AUTOREPEAT, Shell.ActionMode.NORMAL, () => this._focusAppByIndex(9));
    }
    _removeKeybindings() {
        Main.wm.removeKeybinding("toggle-dock");
        for (let i = 1; i <= 9; i++) {
            Main.wm.removeKeybinding(`focus-app-${i}`);
        }
        Main.wm.removeKeybinding("focus-app-10");
    }
    _toggleDockVisibility() {
        if (!this._container)
            return;
        this._container.visible = !this._container.visible;
        if (this._container.visible) {
            this._container.opacity = 255;
        }
    }
    _focusAppByIndex(index) {
        if (!this._iconManager)
            return;
        const actors = this._iconManager.getIconActors();
        if (index >= actors.length)
            return;
        const data = actors[index]._appData;
        if (!data)
            return;
        const appSystem = Shell.AppSystem.get_default();
        const app = appSystem.lookup_app(data.appId);
        if (app) {
            this._onAppClicked(app);
        }
    }
}
