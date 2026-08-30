import Mtk from "gi://Mtk";
import Clutter from "gi://Clutter";
import Gio from "gi://Gio";
import GLib from "gi://GLib";
import Shell from "gi://Shell";
import St from "gi://St";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { SignalManager } from "./signalManager.js";
/**
 * Manages app icons inside the dock container.
 *
 * Each icon is a small St.BoxLayout wrapping an St.Icon and a running
 * indicator dot. Icons are ordered: favorite apps first, then any
 * additional running-but-not-favorited apps (like macOS shows persistent
 * apps in the dock even when not in the favorites list).
 */
export class IconManager {
    _signals;
    _container;
    _iconSize;
    _runningIndicatorsEnabled;
    _indicatorStyle; // 0 = dots per window, 1 = horizontal bar
    _onClicked = null;
    _onIconsChanged = null;
    _icons = new Map();
    _apps = new Map();
    _dying = new Map(); // appId -> actor que se está desvaneciendo
    _favorites = [];
    _shellSettings = null;
    _windowChangeSourceId = null;
    _publishGeometrySourceId = null;
    _tooltipText = null;
    _contextMenu = null;
    _separator = null;
    _appButton = null;
    _appButtonIcon = null;
    _showAppButton = true;
    constructor(container, iconSize, runningIndicatorsEnabled, _quality = 2, indicatorStyle = 0) {
        this._signals = new SignalManager();
        this._container = container;
        this._iconSize = iconSize;
        this._runningIndicatorsEnabled = runningIndicatorsEnabled;
        this._indicatorStyle = indicatorStyle;
    }
    setOnClicked(callback) {
        this._onClicked = callback;
    }
    setOnIconsChanged(callback) {
        this._onIconsChanged = callback;
    }
    setIconSize(size) {
        this._iconSize = size;
        for (const actor of this._icons.values()) {
            this._applyIconSize(actor);
        }
        if (this._appButton && this._appButtonIcon) {
            this._appButtonIcon.set_icon_size(this._iconSize);
            const padded = this._iconSize + 12;
            this._appButton.set_size(padded, padded + 4);
        }
    }
    setQuality(_quality) {
        for (const actor of this._icons.values()) {
            this._applyIconSize(actor);
        }
    }
    setIndicatorStyle(style) {
        this._indicatorStyle = style;
        this._refreshAllIndicators();
    }
    setRunningIndicatorsEnabled(enabled) {
        this._runningIndicatorsEnabled = enabled;
        for (const [appId, actor] of this._icons.entries()) {
            this._refreshRunningIndicator(actor, appId);
        }
    }
    setShowAppButton(show) {
        this._showAppButton = show;
        this._updateAppButton();
    }
    start() {
        const appSystem = Shell.AppSystem.get_default();
        this._signals.connect(appSystem, "installed-changed", () => this._reload());
        // La lista de favoritos también cambia sin que se instale nada: desde
        // Ajustes, con `gsettings`, o con "Añadir a favoritos" del Overview.
        // Sin este handler el dock se quedaba con la lista que leyó la última
        // vez, y un favorito nuevo no aparecía hasta instalar o desinstalar
        // alguna app. Peor: si un favorito apuntaba a un .desktop que ya no
        // existe (por ejemplo al pasar una app de snap a .deb), `lookup_app`
        // devolvía null, `_reload` lo salteaba en silencio y el icono
        // desaparecía del dock sin ningún error en el log.
        this._shellSettings = new Gio.Settings({ schema: "org.gnome.shell" });
        this._signals.connect(this._shellSettings, "changed::favorite-apps", () => this._reload());
        const tracker = Shell.WindowTracker.get_default();
        this._signals.connect(tracker, "notify::focus-app", () => this._refreshAllIndicators());
        this._signals.connect(global.display, "window-created", () => this._onWindowChange());
        this._signals.connect(global.display, "window-entered-monitor", () => this._onWindowChange());
        this._signals.connect(global.display, "window-left-monitor", () => this._onWindowChange());
        // Initialize tooltip - add to top chrome layer like the dock
        this._tooltipText = new St.Label({
            style_class: "macos-dock-tooltip",
            text: "",
            visible: false,
        });
        Main.layoutManager.addTopChrome(this._tooltipText);
        this._reload();
    }
    stop() {
        this._signals.disconnectAll();
        if (this._windowChangeSourceId !== null) {
            GLib.source_remove(this._windowChangeSourceId);
            this._windowChangeSourceId = null;
        }
        if (this._publishGeometrySourceId !== null) {
            GLib.source_remove(this._publishGeometrySourceId);
            this._publishGeometrySourceId = null;
        }
        this._hideTooltip();
        if (this._tooltipText) {
            Main.layoutManager.removeChrome(this._tooltipText);
            this._tooltipText.destroy();
            this._tooltipText = null;
        }
        this._closeContextMenu();
        this._container.destroy_all_children();
        this._icons.clear();
        this._apps.clear();
        this._dying.clear();
        this._favorites = [];
        this._shellSettings = null;
    }
    /**
     * Get the visible icon actors in the dock, in display order. Used by
     * the magnification animator to map pointer X to a focal index.
     */
    getIconActors() {
        // Sólo los que tienen _appData. El separador y el botón de aplicaciones
        // también son hijos del contenedor, y si se colaban acá el atajo
        // Super+3 podía caer en el separador en vez de en la tercera app.
        return this._container.get_children().filter((child) => !!child._appData);
    }
    getIconCount() {
        return this._icons.size;
    }
    hasSeparator() {
        return this._separator !== null;
    }
    hasAppButton() {
        return this._appButton !== null;
    }
    /**
     * Trigger a macOS-style "bounce" animation on the icon for a given app,
     * used to draw the user's attention when an app is launched.
     */
    bounceForApp(app) {
        const appId = app.get_id();
        const actor = this._icons.get(appId);
        if (!actor)
            return;
        this._bounce(actor);
    }
    _reload() {
        this._container.destroy_all_children();
        this._icons.clear();
        this._apps.clear();
        this._dying.clear();
        this._separator = null;
        this._appButton = null;
        this._favorites = this._readFavorites();
        const appSystem = Shell.AppSystem.get_default();
        // Add favorites in their stored order first.
        for (const appId of this._favorites) {
            const app = appSystem.lookup_app(appId);
            if (!app)
                continue;
            this._addIcon(app);
        }
        // Get running apps that aren't favorites
        const runningApps = this._getRunningApps().filter((app) => !this._favorites.includes(app.get_id()));
        // Add separator if there are both favorites and running apps
        if (this._favorites.length > 0 && runningApps.length > 0) {
            this._addSeparator();
        }
        // Then any running app that isn't already a favorite.
        for (const app of runningApps) {
            this._addIcon(app);
        }
        // Add applications button at the end
        this._updateAppButton();
    }
    _onWindowChange() {
        // Remove any existing timeout before creating a new one.
        if (this._windowChangeSourceId !== null) {
            GLib.source_remove(this._windowChangeSourceId);
        }
        // Delay to ensure window is fully initialized before checking.
        this._windowChangeSourceId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
            this._doWindowChange();
            this._windowChangeSourceId = null;
            return GLib.SOURCE_REMOVE;
        });
    }
    _doWindowChange() {
        // Track which apps are running right now. We add/remove icons as
        // needed so non-favorite running apps still appear (and disappear
        // when their last window closes).
        const runningIds = new Set();
        for (const app of this._getRunningApps()) {
            runningIds.add(app.get_id());
        }
        let changed = false;
        const toRemove = [];
        // Remove icons for apps that are no longer running and aren't favorites.
        for (const [id, actor] of this._icons.entries()) {
            const isFavorite = this._favorites.includes(id);
            if (!isFavorite && !runningIds.has(id)) {
                toRemove.push(id);
                // Animate icon disappearing (fade out + scale)
                // Note: scale_x/scale_y are the correct GJS property names (snake_case),
                // even though TypeScript types expect camelCase (scaleX/scaleY).
                // La animación dura 200ms y durante ese rato el actor sigue
                // siendo hijo del contenedor. Si la app vuelve a arrancar antes
                // de que termine, _addIcon crea otro y quedan dos iconos de la
                // misma app; por eso lo anotamos en _dying.
                this._dying.set(id, actor);
                const easeOut = (params) => actor.ease(params);
                easeOut({
                    opacity: 0,
                    scale_x: 0.8,
                    scale_y: 0.8,
                    duration: 200,
                    mode: Clutter.AnimationMode.EASE_IN_QUAD,
                    onComplete: () => {
                        this._dying.delete(id);
                        // destroy(), no remove_child(): sacarlo del contenedor
                        // lo dejaba huérfano y vivo, con sus señales colgando.
                        actor.destroy();
                    },
                });
                changed = true;
            }
        }
        // Clean up references after animation
        for (const id of toRemove) {
            this._icons.delete(id);
            this._apps.delete(id);
        }
        // Add icons for newly running, non-favorited apps.
        for (const id of runningIds) {
            if (this._icons.has(id))
                continue;
            if (this._favorites.includes(id))
                continue;
            const appSystem = Shell.AppSystem.get_default();
            const app = appSystem.lookup_app(id);
            if (!app)
                continue;
            this._addIcon(app);
            changed = true;
        }
        // Update separator visibility
        this._updateSeparator();
        this._refreshAllIndicators();
        // Notify dock to resize when icons were added/removed.
        if (changed && this._onIconsChanged)
            this._onIconsChanged();
    }
    _updateSeparator() {
        // Count non-favorite running apps
        const runningNonFavorites = this._getRunningApps().filter((app) => !this._favorites.includes(app.get_id()));
        const hasFavorites = this._favorites.length > 0;
        const hasRunningNonFavorites = runningNonFavorites.length > 0;
        // Add separator if needed
        if (hasFavorites && hasRunningNonFavorites && !this._separator) {
            this._addSeparator();
        }
        // Remove separator if not needed
        else if ((!hasFavorites || !hasRunningNonFavorites) && this._separator) {
            this._separator.destroy();
            this._separator = null;
        }
    }
    _addIcon(app) {
        const appId = app.get_id();
        if (this._icons.has(appId))
            return;
        // Si todavía se está yendo el icono viejo de esta misma app, lo matamos
        // ya en vez de esperar a que termine el fundido.
        const moribundo = this._dying.get(appId);
        if (moribundo) {
            this._dying.delete(appId);
            moribundo.destroy();
        }
        const actor = new St.BoxLayout({
            style_class: "macos-dock-icon",
            reactive: true,
            track_hover: true,
            vertical: true,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.FILL,
        });
        this._applyIconSize(actor);
        const icon = new St.Icon({
            gicon: app.get_icon(),
            icon_size: this._iconSize,
            style_class: "macos-dock-icon-gicon",
        });
        actor.add_child(icon);
        // Container for running indicator dots (or a single bar).
        const indicatorBox = new St.BoxLayout({
            style_class: "macos-dock-indicator-box",
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        });
        actor.add_child(indicatorBox);
        // Store references on the actor for retrieval later.
        const appData = { appId, icon, indicatorBox, dots: [] };
        actor._appData = appData;
        this._signals.connect(actor, "button-press-event", (_actor, event) => {
            const button = event.get_button();
            if (button === 3) {
                // Right-click: show context menu
                this._showContextMenu(actor, app);
                return Clutter.EVENT_STOP;
            }
            // Left-click: normal behavior
            if (this._onClicked) {
                this._onClicked(app);
            }
            return Clutter.EVENT_PROPAGATE;
        });
        // Tooltip events - use notify::hover since track_hover is enabled
        this._signals.connect(actor, "notify::hover", () => {
            if (actor.hover) {
                this._showTooltip(actor, app.get_name());
            }
            else {
                this._hideTooltip();
            }
            return Clutter.EVENT_PROPAGATE;
        });
        this._container.add_child(actor);
        this._icons.set(appId, actor);
        this._apps.set(appId, app);
        // Animate icon appearing (fade in + scale)
        // Note: scale_x/scale_y are the correct GJS property names (snake_case),
        // even though TypeScript types expect camelCase (scaleX/scaleY).
        actor.opacity = 0;
        actor.scale_x = 0.8;
        actor.scale_y = 0.8;
        const easeIn = (params) => actor.ease(params);
        easeIn({
            opacity: 255,
            scale_x: 1.0,
            scale_y: 1.0,
            duration: 200,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
        });
        this._refreshRunningIndicator(actor, appId);
        // Notify dock to resize.
        if (this._onIconsChanged)
            this._onIconsChanged();
    }
    _applyIconSize(actor) {
        const data = this._getStored(actor);
        if (data) {
            data.icon.set_icon_size(this._iconSize);
        }
        const padded = this._iconSize + 12;
        actor.set_size(padded, padded + 4);
    }
    _refreshAllIndicators() {
        for (const [appId, actor] of this._icons.entries()) {
            this._refreshRunningIndicator(actor, appId);
        }
        this.queuePublishIconGeometries();
    }
    /**
     * Le dice a cada ventana dónde está el icono de su app en la pantalla.
     *
     * Es lo que leen las animaciones de minimizar: el shell y las extensiones
     * de efecto arrancan por `meta_window.get_icon_geometry()`, y si nadie la
     * publicó, apuntan al centro de la pantalla en vez de al dock. Peor: la
     * vieja `compiz-alike-magic-lamp-effect` caía entonces a un camino que
     * hurgaba el Dash de GNOME — que este dock esconde en `_hideDefaultDash()`
     * — y reventaba ahí, dejando ventanas que no se minimizaban nunca.
     * Publicando la geometría, ese camino no se recorre más.
     */
    /**
     * Encola la publicación para el próximo idle.
     *
     * Directo no sirve: los que llaman acá acaban de mover o redimensionar el
     * dock, y hasta que Clutter no re-asigna el layout `get_transformed_position()`
     * sigue devolviendo la posición vieja. Además esto se dispara seguido
     * (cambio de foco, ventanas que abren y cierran, `workareas-changed`), así
     * que se coalesce en una sola pasada por idle.
     */
    queuePublishIconGeometries() {
        if (this._publishGeometrySourceId !== null)
            return;
        this._publishGeometrySourceId = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            this._publishGeometrySourceId = null;
            this.publishIconGeometries();
            return GLib.SOURCE_REMOVE;
        });
    }
    publishIconGeometries() {
        // Si el actor no está en el stage, la posición y el tamaño que reporta
        // son basura, y valores fuera del rango de int revientan el Rectangle.
        if (!this._container || !this._container.get_stage())
            return;
        // Una pasada por icono: la posición depende de la app, no de la ventana.
        const rects = new Map();
        for (const [appId, actor] of this._icons.entries()) {
            if (!actor.mapped)
                continue;
            const [x, y] = actor.get_transformed_position();
            const [w, h] = actor.get_transformed_size();
            if (!Number.isFinite(x) || !Number.isFinite(y) || !(w > 0) || !(h > 0))
                continue;
            const rect = new Mtk.Rectangle();
            rect.x = Math.round(x);
            rect.y = Math.round(y);
            rect.width = Math.round(w);
            rect.height = Math.round(h);
            rects.set(appId, rect);
        }
        if (rects.size === 0)
            return;
        const tracker = Shell.WindowTracker.get_default();
        for (const wa of global.get_window_actors()) {
            const mw = wa.get_meta_window();
            if (!mw)
                continue;
            const app = tracker.get_window_app(mw);
            if (!app)
                continue;
            const rect = rects.get(app.get_id());
            if (rect)
                mw.set_icon_geometry(rect);
        }
    }
    _refreshRunningIndicator(actor, appId) {
        const data = this._getStored(actor);
        if (!data)
            return;
        const { indicatorBox } = data;
        if (!indicatorBox)
            return;
        if (!this._runningIndicatorsEnabled) {
            indicatorBox.visible = false;
            return;
        }
        const tracker = Shell.WindowTracker.get_default();
        const app = this._apps.get(appId);
        if (!app) {
            indicatorBox.visible = false;
            return;
        }
        // Count all windows for this app (including minimized).
        let windowCount = 0;
        const actors = global.get_window_actors();
        for (const wa of actors) {
            const mw = wa.get_meta_window();
            if (!mw)
                continue;
            if (tracker.get_window_app(mw) === app) {
                windowCount++;
            }
        }
        const focused = tracker.focus_app === app;
        const isRunning = windowCount > 0 || focused;
        if (!isRunning) {
            indicatorBox.visible = false;
            return;
        }
        indicatorBox.visible = true;
        // Clear all children before adding new style.
        indicatorBox.remove_all_children();
        if (this._indicatorStyle === 0) {
            // Dots per window (macOS style).
            const needed = focused ? Math.max(windowCount, 1) : windowCount;
            // Add or remove dots to match window count.
            while (indicatorBox.get_n_children() < needed) {
                const dot = new St.Widget({
                    style_class: "macos-dock-indicator-dot",
                });
                indicatorBox.add_child(dot);
            }
            while (indicatorBox.get_n_children() > needed) {
                const last = indicatorBox.get_n_children() - 1;
                indicatorBox.get_child_at_index(last)?.destroy();
            }
        }
        else {
            // Horizontal bar style.
            const bar = new St.Widget({
                style_class: "macos-dock-indicator-bar",
            });
            indicatorBox.add_child(bar);
        }
    }
    _getRunningApps() {
        const tracker = Shell.WindowTracker.get_default();
        const seen = new Set();
        const result = [];
        const windows = global.get_window_actors();
        for (const wa of windows) {
            const metaWin = wa.get_meta_window();
            if (!metaWin)
                continue;
            if (!metaWin.showing_on_its_workspace())
                continue;
            const app = tracker.get_window_app(metaWin);
            if (!app)
                continue;
            const id = app.get_id();
            if (seen.has(id))
                continue;
            seen.add(id);
            result.push(app);
        }
        return result;
    }
    _readFavorites() {
        try {
            const settings = this._shellSettings ?? new Gio.Settings({ schema: "org.gnome.shell" });
            return settings.get_strv("favorite-apps");
        }
        catch {
            return [];
        }
    }
    _getStored(actor) {
        const data = actor._appData;
        if (!data)
            return null;
        return data;
    }
    _bounce(actor) {
        const baseY = 0;
        const up = -28;
        const small = -10;
        // Note: translation_y is the correct GJS property name (snake_case), even though
        // the TypeScript types expect camelCase (translationY). This is a type definition mismatch.
        const ease = (params) => actor.ease(params);
        ease({
            translation_y: up,
            duration: 180,
            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
            onComplete: () => {
                ease({
                    translation_y: baseY,
                    duration: 120,
                    mode: Clutter.AnimationMode.EASE_IN_QUAD,
                    onComplete: () => {
                        ease({
                            translation_y: small,
                            duration: 100,
                            mode: Clutter.AnimationMode.EASE_OUT_QUAD,
                            onComplete: () => {
                                ease({
                                    translation_y: baseY,
                                    duration: 80,
                                    mode: Clutter.AnimationMode.EASE_IN_QUAD,
                                });
                            },
                        });
                    },
                });
            },
        });
    }
    _showTooltip(actor, appName) {
        if (!this._tooltipText)
            return;
        const [x, y] = actor.get_transformed_position();
        const [width] = actor.get_size();
        this._tooltipText.set_text(appName);
        const [, tooltipWidth] = this._tooltipText.get_preferred_width(-1);
        // Position tooltip above the icon, centered
        const tooltipX = x + (width - tooltipWidth) / 2;
        const tooltipY = y - 40; // 40px above the icon
        this._tooltipText.set_position(tooltipX, tooltipY);
        this._tooltipText.show();
    }
    _hideTooltip() {
        if (this._tooltipText) {
            this._tooltipText.hide();
        }
    }
    _showContextMenu(actor, app) {
        // Close existing context menu if any
        this._closeContextMenu();
        // Create a simple context menu using St.BoxLayout
        this._contextMenu = new St.BoxLayout({
            style_class: "macos-dock-context-menu",
            vertical: true,
            reactive: true,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.START,
        });
        const menuItems = [
            { label: "Nova Janela", action: () => app.open_new_window(-1) },
            { label: "Fechar", action: () => this._closeApp(app) },
        ];
        for (const item of menuItems) {
            const menuItem = new St.Button({
                style_class: "macos-dock-context-menu-item",
                reactive: true,
                track_hover: true,
                x_align: Clutter.ActorAlign.START,
                y_align: Clutter.ActorAlign.CENTER,
                label: item.label,
            });
            menuItem.connect("button-press-event", () => {
                item.action();
                this._closeContextMenu();
                return Clutter.EVENT_STOP;
            });
            this._contextMenu.add_child(menuItem);
        }
        // Position menu above the icon
        const [x, y] = actor.get_transformed_position();
        const [width] = actor.get_size();
        const [, menuWidth] = this._contextMenu.get_preferred_width(-1);
        const [, menuHeight] = this._contextMenu.get_preferred_height(-1);
        const menuX = x + (width - menuWidth) / 2;
        const menuY = y - menuHeight - 10;
        this._contextMenu.set_position(menuX, menuY);
        Main.layoutManager.addTopChrome(this._contextMenu);
        // Close menu when clicking outside
        const clickOutsideId = global.stage.connect("button-press-event", () => {
            this._closeContextMenu();
            global.stage.disconnect(clickOutsideId);
            return Clutter.EVENT_PROPAGATE;
        });
    }
    _closeContextMenu() {
        if (this._contextMenu) {
            Main.layoutManager.removeChrome(this._contextMenu);
            this._contextMenu.destroy();
            this._contextMenu = null;
        }
    }
    _closeApp(app) {
        const windows = app.get_windows();
        for (const window of windows) {
            window.delete(global.get_current_time());
        }
    }
    _addSeparator() {
        if (this._separator)
            return;
        this._separator = new St.Widget({
            style_class: "macos-dock-separator",
            width: 1,
            height: 32,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.CENTER,
        });
        // Insert after the last favorite icon, before non-favorite running apps
        let insertIndex = 0;
        for (const [id] of this._icons) {
            if (this._favorites.includes(id)) {
                insertIndex++;
            }
            else {
                break;
            }
        }
        this._container.insert_child_at_index(this._separator, insertIndex);
    }
    _updateAppButton() {
        if (this._showAppButton && !this._appButton) {
            this._addAppButton();
        }
        else if (!this._showAppButton && this._appButton) {
            this._removeAppButton();
        }
    }
    _addAppButton() {
        if (this._appButton)
            return;
        const padded = this._iconSize + 12;
        this._appButton = new St.BoxLayout({
            style_class: "macos-dock-app-button",
            reactive: true,
            track_hover: true,
            vertical: true,
            x_align: Clutter.ActorAlign.CENTER,
            y_align: Clutter.ActorAlign.FILL,
            width: padded,
            height: padded + 4,
        });
        this._appButtonIcon = new St.Icon({
            icon_name: "view-app-grid-symbolic",
            icon_size: this._iconSize,
            style_class: "macos-dock-app-button-icon",
        });
        this._appButton.add_child(this._appButtonIcon);
        this._appButton.connect("button-press-event", () => {
            if (Main.overview.visible) {
                Main.overview.hide();
            }
            else {
                Main.overview.showApps();
            }
            return Clutter.EVENT_STOP;
        });
        // Tooltip on hover
        this._signals.connect(this._appButton, "notify::hover", () => {
            if (this._appButton?.hover) {
                this._showTooltip(this._appButton, "Applications");
            }
            else {
                this._hideTooltip();
            }
        });
        this._container.add_child(this._appButton);
        // Notify dock to resize
        if (this._onIconsChanged)
            this._onIconsChanged();
    }
    _removeAppButton() {
        if (!this._appButton)
            return;
        this._container.remove_child(this._appButton);
        this._appButton.destroy();
        this._appButton = null;
        this._appButtonIcon = null;
        // Notify dock to resize
        if (this._onIconsChanged)
            this._onIconsChanged();
    }
}
