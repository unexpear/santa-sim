shader_type spatial;
render_mode cull_disabled;
// Ember bed / charred wood: black char cracked into cells, the cracks glowing orange-yellow and
// pulsing; frozen = frosty blue-white, no glow.

uniform float scale = 28.0;
uniform float heat = 1.0;     // 0 = cold char
uniform float frost = 0.0;    // 1 = iced
uniform vec4 char_col : source_color = vec4(0.06, 0.04, 0.035, 1.0);
uniform vec4 glow_a : source_color = vec4(1.0, 0.32, 0.05, 1.0);
uniform vec4 glow_b : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform vec4 frost_col : source_color = vec4(0.78, 0.9, 1.0, 1.0);
uniform bool world_uv = true;

varying vec3 wp;

vec2 h2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = (world_uv ? wp.xz + wp.y * 0.7 : UV * 4.0) * scale;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = h2(i + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; id = o.x; } else if (d < d2) { d2 = d; }
		}
	}
	float crack = 1.0 - smoothstep(0.0, 0.08, sqrt(d2) - sqrt(d1));
	float pulse = 0.6 + 0.4 * sin(TIME * (1.5 + id * 2.0) + id * 30.0);
	float cellglow = smoothstep(0.55, 1.0, id) * 0.35 * pulse;
	vec3 glow = mix(glow_a.rgb, glow_b.rgb, crack * pulse * 0.7);
	vec3 col = char_col.rgb * (0.7 + 0.6 * id);
	col = mix(col, frost_col.rgb * (0.8 + 0.3 * id), frost);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.3, frost);
	EMISSION = glow * (crack * pulse + cellglow) * heat * (1.0 - frost) * 2.2;
}
