shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// One flame tongue: a tapered, bent cone (mesh UV.y = 0 at the base, 1 at the tip) eaten away by
// scrolling noise so it reads as licking tongues from the side AND from straight above (the
// layered cones give concentric glowing licks). Toon-ish banded colours: white-yellow core,
// orange, red tips.

uniform float seed = 0.0;
uniform float speed = 1.6;
uniform float sway = 0.035;      // metres of sideways lick at the tip
uniform float intensity = 1.0;
uniform float cone_h = 0.2;     // the cone mesh height (m), for the base-to-tip gradient
uniform vec4 core : source_color = vec4(1.0, 0.93, 0.6, 1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.55, 0.12, 1.0);
uniform vec4 tip : source_color = vec4(0.85, 0.16, 0.04, 1.0);

varying float hgt;
varying vec3 lp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	hgt = clamp(VERTEX.y / cone_h + 0.5, 0.0, 1.0);
	float t = TIME * speed + seed * 13.1;
	float k = hgt * hgt;
	VERTEX.x += (sin(t * 2.3 + hgt * 4.0) + 0.5 * sin(t * 5.1 + seed)) * sway * k;
	VERTEX.z += (cos(t * 1.9 + hgt * 3.3 + seed) + 0.4 * sin(t * 4.3)) * sway * k;
	// breathe
	VERTEX.y *= 0.85 + 0.25 * vnoise(vec2(t * 1.3, seed));
	lp = VERTEX;
}

void fragment() {
	float t = TIME * speed + seed * 7.0;
	vec2 uv = vec2(UV.x * 5.0, hgt * 1.6 - t * 0.9);
	float n = vnoise(uv * vec2(2.0, 3.0)) * 0.6 + vnoise(uv * vec2(5.0, 7.0) + 3.1) * 0.4;
	// split the cone into separate licks around its rim (reads as tongues from straight above)
	n *= 0.6 + 0.55 * smoothstep(0.25, 0.75, vnoise(vec2(UV.x * 7.0 + seed, t * 0.4)));
	// tongues: noise must beat a threshold that rises towards the tip
	float edge = smoothstep(0.0, 0.25, 1.0 - hgt) ;
	float body = n - hgt * 0.7 + 0.42;
	float a = smoothstep(0.08, 0.22, body) * edge;
	// facing ratio: brighter where we look through more flame
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	a *= 0.55 + 0.45 * facing;
	vec3 col = mix(core.rgb, mid.rgb, smoothstep(0.15, 0.45, hgt + (1.0 - n) * 0.25));
	col = mix(col, tip.rgb, smoothstep(0.5, 0.9, hgt + (1.0 - n) * 0.2));
	// toon bands
	float band = floor(clamp(body, 0.0, 1.0) * 4.0) / 4.0;
	ALBEDO = col * a * intensity * (0.75 + 0.5 * band) * 1.25;
	ALPHA = 1.0;
}
