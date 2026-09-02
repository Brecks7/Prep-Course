/**
 * Las medidas del dock, en un solo lugar.
 *
 * Antes los mismos números vivían en tres archivos que se tenían que cancelar
 * a mano: `_updatePosition()` sumaba `icon + 12` por icono y `spacing = 6`,
 * `_applyDockStyle()` escribía `padding: 4px 10px; spacing: 6px` en el estilo
 * inline, y `_applyIconSize()` hacía `set_size(icon + 12, icon + 16)`. Tocar
 * el espaciado en uno sin tocar los otros dejaba el rectángulo más corto o más
 * largo que la fila de iconos.
 *
 * Las proporciones salieron de medir el dock de macOS Tahoe con PIL
 * (`~/Descargas/DOCK.png`, dock de 1036x100 con iconos de 60):
 *
 *   arte del icono   60      -> 0.60 del alto del dock
 *   hueco entre arte 16      -> 0.27 del icono
 *   margen lateral   14      -> 0.23 del icono
 *   arte -> punto     4      -> 0.07 del icono
 *   punto            8 (⌀)   -> 0.13 del icono
 *   punto -> base    12      -> 0.13 del icono, más el propio punto
 *   separador        2 x 62  -> 1.03 del icono de alto
 *
 * Todo se deriva de `icon-size`, así que cambiar el tamaño de los iconos
 * reescala el dock entero sin descuadrarlo.
 */
export function metrics(iconSize) {
    const icon = Math.max(16, iconSize || 48);
    const r = (f) => Math.round(icon * f);
    // Aire alrededor del arte, dentro del actor del icono. Existe para que el
    // área clickeable sea un poco mayor que el dibujo; el hueco que se ve entre
    // dos iconos es este aire más el `spacing`.
    const air = Math.max(2, r(0.10));
    const dot = Math.max(4, r(0.13));
    const iconDotGap = Math.max(2, r(0.07));
    const actorWidth = icon + air;
    // El actor es alto como el arte más lo que ocupan los puntos debajo.
    const actorHeight = icon + iconDotGap + dot;
    // El hueco medido es `air + spacing`, así que el spacing es la diferencia.
    const spacing = Math.max(2, r(0.27) - air);
    const padSide = Math.max(4, r(0.23));
    // El aire de arriba y el de abajo NO son iguales, y no por gusto: abajo hay
    // que descontar el bloque de los puntos. Los números salen de despejar dos
    // condiciones medidas sobre la referencia —el arte ocupa 0.60 del alto del
    // dock y le queda el mismo aire arriba que abajo— sabiendo que el arte se
    // pinta 2px más abajo del borde del actor (el St.Icon se centra en lo que
    // le deja el iconWrap). Con icon 40 dan 12 y 7: arte a 14 del techo y 13
    // del piso, sobre un dock de 67.
    const padTop = Math.max(4, r(0.30));
    const padBottom = Math.max(2, r(0.175));
    return {
        icon,
        air,
        dot,
        dotSpacing: Math.max(2, r(0.10)),
        iconDotGap,
        actorWidth,
        actorHeight,
        spacing,
        padSide,
        padTop,
        padBottom,
        // Alto total del rectángulo que se ve.
        dockThickness: padTop + actorHeight + padBottom,
        separatorWidth: 2,
        separatorHeight: r(1.03),
        // El separador respira mucho más que el hueco entre dos iconos: en la
        // referencia hay ~35 de aire a cada lado con iconos de 60.
        separatorMargin: Math.max(4, r(0.4)),
        // El globo de notificaciones.
        badgeHeight: Math.max(12, r(0.34)),
        badgeFont: Math.max(8, r(0.24)),
        // La barra del estilo alternativo de indicador (running-indicator-style 1).
        barWidth: r(0.4),
        barHeight: Math.max(2, r(0.05)),
    };
}
