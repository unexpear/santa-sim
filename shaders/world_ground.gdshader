shader_type spatial;
render_mode cull_back;
// Streamed-world ground: a class raster (R8: 0 land, 1 residential, 2 commercial, 3 industrial, 4 grass/park,
// 5 pitch, 6 wood, 7 sand, 8 water, 9 ocean, 10 farmland) turned into colours with a manual bilinear blend,
// so coastlines and parks get soft edges. Summer Christmas in Australia: dry golden paddocks, no snow.
uniform sampler2D classes : filter_nearest, repeat_disable;
uniform float noise_scale = 0.013;

vec4 pal(int c) {
	// rgb + wetness
	if (c == 1) return vec4(0.30, 0.40, 0.24, 0.0);
	if (c == 2) return vec4(0.34, 0.33, 0.36, 0.0);
	if (c == 3) return vec4(0.32, 0.31, 0.31, 0.0);
	if (c == 4) return vec4(0.22, 0.46, 0.21, 0.0);
	if (c == 5) return vec4(0.20, 0.52, 0.22, 0.0);
	if (c == 6) return vec4(0.10, 0.27, 0.13, 0.0);
	if (c == 7) return vec4(0.86, 0.77, 0.56, 0.0);
	if (c == 8) return vec4(0.05, 0.13, 0.25, 1.0);
	if (c == 9) return vec4(0.03, 0.09, 0.21, 1.0);
	if (c == 10) return vec4(0.52, 0.47, 0.25, 0.0);
	return vec4(0.33, 0.41, 0.22, 0.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ivec2 sz = textureSize(classes, 0);
	vec2 st = UV * vec2(sz) - 0.5;
	ivec2 i0 = ivec2(floor(st));
	vec2 f = fract(st);
	ivec2 mx = sz - ivec2(1);
	vec4 c00 = pal(int(texelFetch(classes, clamp(i0, ivec2(0), mx), 0).r * 255.0 + 0.5));
	vec4 c10 = pal(int(texelFetch(classes, clamp(i0 + ivec2(1, 0), ivec2(0), mx), 0).r * 255.0 + 0.5));
	vec4 c01 = pal(int(texelFetch(classes, clamp(i0 + ivec2(0, 1), ivec2(0), mx), 0).r * 255.0 + 0.5));
	vec4 c11 = pal(int(texelFetch(classes, clamp(i0 + ivec2(1, 1), ivec2(0), mx), 0).r * 255.0 + 0.5));
	vec4 c = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
	float wet = smoothstep(0.35, 0.65, c.a);
	float n = vnoise(wpos.xz * noise_scale) * 0.6 + vnoise(wpos.xz * noise_scale * 5.0) * 0.4;
	vec3 col = c.rgb * mix(0.82 + n * 0.36, 0.95 + n * 0.1, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.12, wet);
	SPECULAR = mix(0.15, 0.8, wet);
	METALLIC = 0.0;
}
