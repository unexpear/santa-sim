shader_type spatial;
// Fit-Ghost hologram: unshaded, see-through, fresnel edge glow + drifting scanlines.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
uniform vec4 color : source_color = vec4(0.2, 1.0, 0.4, 1.0);
uniform float intensity = 1.2;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float scan = 0.55 + 0.45 * step(0.5, fract(wp.y * 28.0 - TIME * 1.5));
	ALBEDO = color.rgb * (0.25 + fres * 1.4) * scan * intensity;
}
