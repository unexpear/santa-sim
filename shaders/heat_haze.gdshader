shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Heat shimmer over the fire: a faint screen-space wobble, strongest in the middle.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.006;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 c = UV - 0.5;
	float m = 1.0 - smoothstep(0.15, 0.5, length(c));
	vec2 n = vec2(vnoise(UV * 9.0 + vec2(0.0, -TIME * 1.7)), vnoise(UV * 9.0 + vec2(5.2, -TIME * 1.9))) - 0.5;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + n * strength * m, 0.0).rgb;
	ALPHA = m * 0.45;
}
