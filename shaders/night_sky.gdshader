shader_type sky;
// Stylized dusk-to-night sky: amber horizon -> purple -> deep teal, toon-edged clouds,
// twinkling stars and a big glowing moon.

uniform vec3 top_color : source_color = vec3(0.03, 0.13, 0.25);
uniform vec3 mid_color : source_color = vec3(0.3, 0.16, 0.45);
uniform vec3 horizon_color : source_color = vec3(1.0, 0.52, 0.2);
uniform vec3 below_color : source_color = vec3(0.12, 0.07, 0.16);
uniform vec3 cloud_color : source_color = vec3(0.42, 0.28, 0.58);
uniform vec3 cloud_lit_color : source_color = vec3(1.0, 0.68, 0.42);
uniform vec3 moon_color : source_color = vec3(1.0, 0.95, 0.78);
uniform vec3 moon_dir = vec3(0.3, 0.45, -0.85);
uniform float moon_size = 0.06;
uniform float cloud_coverage = 0.42;
uniform float cloud_speed = 0.006;
uniform float star_amount = 0.35;
uniform float cloud_edge_softness = 0.12;

float hash(vec2 p) {
	// Sin-free hash: stable precision far from the origin (the old one stair-stepped clouds).
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h < 0.0) {
		col = mix(horizon_color * 0.55, below_color, clamp(-h * 5.0, 0.0, 1.0));
	} else {
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.22, h));
		col = mix(col, top_color, smoothstep(0.18, 0.75, h));

		// Stars
		vec2 suv = vec2(atan(d.x, d.z), asin(h)) * 90.0;
		vec2 cell = floor(suv);
		float rnd = hash(cell);
		float star = step(1.0 - star_amount * 0.08, rnd);
		float tw = 0.6 + 0.4 * sin(TIME * (1.0 + rnd * 3.0) + rnd * 40.0);
		star *= smoothstep(0.35, 0.0, length(fract(suv) - 0.5)) * tw;
		col += vec3(1.0, 0.95, 0.85) * star * smoothstep(0.12, 0.45, h);

		// Moon + glow
		vec3 md = normalize(moon_dir);
		float mdot = dot(d, md);
		float moon = smoothstep(cos(moon_size), cos(moon_size * 0.9), mdot);
		float glow = pow(max(mdot, 0.0), 300.0) * 0.8 + pow(max(mdot, 0.0), 24.0) * 0.18;

		// Toon clouds on a virtual dome
		vec2 cp = d.xz / (h + 0.15) * 0.9 + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.3);
		float n = fbm(cp * 1.4);
		float edge = 1.0 - cloud_coverage;
		// Wider, anti-aliased edges (soft band) so cloud outlines stay smooth and painterly.
		float aa = cloud_edge_softness;
		float c = smoothstep(edge - aa * 0.5, edge + aa, n) * smoothstep(0.0, 0.1, h) * (1.0 - smoothstep(0.5, 0.8, h));
		float inner = smoothstep(edge + 0.05, edge + 0.2, n);
		vec3 ccol = mix(cloud_lit_color, cloud_color, inner * 0.7 + smoothstep(0.05, 0.4, h) * 0.3);
		ccol += moon_color * glow * 1.5;

		col += moon_color * glow;
		col = mix(col, moon_color * 1.4, moon);
		col = mix(col, ccol, c * 0.92);
	}
	COLOR = col;
}
