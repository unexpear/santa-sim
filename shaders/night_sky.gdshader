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
// night_clock.gd: the low sun at sunset / sunrise (0 = below the horizon)
uniform vec3 sun_dir = vec3(0.0, -1.0, 0.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.55, 0.22);
uniform float sun_amount = 0.0;
uniform float twilight_glow = 0.0;  // 0 night .. 1 sun at the horizon: warm glow on the sun's side
uniform vec3 glow_color : source_color = vec3(1.0, 0.36, 0.12);
uniform vec3 moon_lit_dir = vec3(0.0, -1.0, 0.0);  // true direction of the sun (moon phase)

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

		// low sun: a soft disc and a wide warm glow along the horizon on its side of the sky
		vec3 sd = normalize(sun_dir);
		float sdot = dot(d, sd);
		float sun = smoothstep(cos(0.045), cos(0.04), sdot) * sun_amount;
		float sglow = (pow(max(sdot, 0.0), 60.0) * 0.9 + pow(max(sdot, 0.0), 6.0) * 0.35 * (1.0 - smoothstep(0.0, 0.5, h))) * sun_amount;
		col += sun_color * sglow;
		// twilight: a wide band of orange-red along the horizon toward the (set) sun
		vec3 sflat = normalize(vec3(sd.x, 0.0, sd.z) + vec3(1e-5));
		float saz = max(dot(normalize(vec3(d.x, 0.0, d.z) + vec3(1e-5)), sflat), 0.0);
		float band = exp(-h * 7.0);
		float tg = twilight_glow * band * (pow(saz, 2.5) * 0.85 + pow(saz, 14.0) * 0.9);
		col = mix(col, glow_color, clamp(tg, 0.0, 0.92));
		col += glow_color * pow(saz, 40.0) * band * twilight_glow * 0.5;
		ccol = mix(ccol, glow_color * 1.1, clamp(tg * 0.8, 0.0, 0.9));
		ccol = mix(ccol, sun_color * 1.2, sglow * 0.6);
		col += moon_color * glow;
		// the real phase: shade the disc by the sun's true direction
		vec3 o = (d - md * mdot) / sin(moon_size);
		float oz = sqrt(max(1.0 - dot(o, o), 0.0));
		vec3 mn = normalize(o - md * oz);
		float lit = smoothstep(-0.08, 0.08, dot(mn, normalize(moon_lit_dir)));
		col = mix(col, mix(moon_color * 0.07, moon_color * 1.4, lit), moon);
		col = mix(col, ccol, c * 0.92);
		col = mix(col, vec3(1.0, 0.85, 0.6) * 2.0, sun * (1.0 - c * 0.7));
	}
	COLOR = col;
}
