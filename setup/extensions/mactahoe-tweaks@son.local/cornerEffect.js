// Recorta un actor a un rectángulo redondeado.
//
// Hace falta porque Shell.BlurEffect desenfoca el rectángulo completo de la
// asignación del actor, sin enterarse del border-radius ni de los márgenes del
// tema. Sin esto, detrás de un menú con 33px de radio se vería un cuadrado
// borroso asomando por las esquinas y desbordando los márgenes.
//
// El shader viene del `corner.glsl` de Blur my Shell (GPL-3), que a su vez está
// basado en rounded-window-corners y en código de Mutter. Acá va recortado a lo
// que necesitamos: un solo radio, sin distinguir esquinas de arriba y de abajo.

import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';

const SHADER = `
uniform sampler2D tex;
uniform float radius;
uniform float width;
uniform float height;
uniform float clip_x0;
uniform float clip_y0;
uniform float clip_width;
uniform float clip_height;

// Cobertura antialiaseada de un punto respecto de una esquina circular.
float circle_bounds(vec2 p, vec2 center, float r) {
    vec2 delta = p - center;
    float dist_squared = dot(delta, delta);

    float outer = r + 0.5;
    if (dist_squared >= outer * outer)
        return 0.0;

    float inner = r - 0.5;
    if (dist_squared <= inner * inner)
        return 1.0;

    return outer - sqrt(dist_squared);
}

float rounded_rect_coverage(vec2 p, vec4 bounds, float r) {
    if (p.x < bounds.x || p.x > bounds.z || p.y < bounds.y || p.y > bounds.w)
        return 0.0;

    vec2 center;

    float left = bounds.x + r;
    float right = bounds.z - r;
    if (p.x < left)
        center.x = left;
    else if (p.x > right)
        center.x = right;
    else
        return 1.0;

    float top = bounds.y + r;
    float bottom = bounds.w - r;
    if (p.y < top)
        center.y = top;
    else if (p.y > bottom)
        center.y = bottom;
    else
        return 1.0;

    return circle_bounds(p, center, r);
}

void main(void) {
    vec2 uv = cogl_tex_coord_in[0].xy;
    vec4 c = texture2D(tex, uv);

    vec4 bounds = vec4(
        clip_x0,
        clip_y0,
        clip_x0 + clip_width,
        clip_y0 + clip_height
    );

    float alpha = rounded_rect_coverage(uv * vec2(width, height), bounds, radius);

    // Cogl espera alfa premultiplicado.
    cogl_color_out = vec4(c.rgb * alpha, min(alpha, c.a));
}
`;

export const CornerEffect = GObject.registerClass({
    GTypeName: 'MacTahoeTweaksCornerEffect',
}, class CornerEffect extends Clutter.ShaderEffect {
    constructor() {
        // Sin argumentos a propósito: Clutter 18 (GNOME 50) sacó ShaderType
        // junto con el soporte de vertex shaders, así que ya no hay ningún
        // `shader_type` que pasar — ShaderEffect es de fragmentos y punto.
        super();

        this.set_shader_source(SHADER);

        // Valores de arranque razonables por si `setGeometry` todavía no corrió:
        // sin ellos el shader lee uniformes sin inicializar y el actor parpadea.
        this.setGeometry({
            width: 1, height: 1,
            x: 0, y: 0, clipWidth: 1, clipHeight: 1,
            radius: 0,
        });
    }

    // `width`/`height` son el tamaño completo del actor (el tamaño de la textura
    // offscreen); `x`/`y`/`clipWidth`/`clipHeight` delimitan la caja visible
    // dentro de ese rectángulo, o sea el actor menos sus márgenes.
    setGeometry({width, height, x, y, clipWidth, clipHeight, radius}) {
        // El radio no puede pasar de la mitad del lado más corto o el shader
        // dibuja esquinas que se pisan entre sí.
        const maxRadius = Math.min(clipWidth, clipHeight) / 2;
        const safeRadius = Math.max(0, Math.min(radius, maxRadius));

        // El `- 1e-6` no es cosmético: si el número es entero, GJS lo manda como
        // int y el uniforme, que es float, queda sin setear. Es el mismo truco
        // que usa Blur my Shell.
        const asFloat = v => parseFloat(v) - 1e-6;

        this.set_uniform_value('width', asFloat(width));
        this.set_uniform_value('height', asFloat(height));
        this.set_uniform_value('clip_x0', asFloat(x));
        this.set_uniform_value('clip_y0', asFloat(y));
        this.set_uniform_value('clip_width', asFloat(clipWidth));
        this.set_uniform_value('clip_height', asFloat(clipHeight));
        this.set_uniform_value('radius', asFloat(safeRadius));
    }
});
