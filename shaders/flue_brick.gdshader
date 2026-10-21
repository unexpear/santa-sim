shader_type spatial;
// Inside of a chimney flue at real brick size (same bricks as the outside: 0.22 x 0.068 m with
// 13 mm joints). Dark recessed mortar, irregular brick shading, a few chipped and missing bricks,
// creosote streaks running down, heavy soot that is blackest near the top and warms to an
// orange fire-lit glow near the firebox (glow_bottom_y). Toon-ish wrapped light.

uniform vec4 brick_color : source_color = vec4(0.5, 0.22, 0.15, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.07, 0.06, 0.055, 1.0);
uniform vec4 soot_color : source_color = vec4(0.075, 0.062, 0.056, 1.0);
uniform float soot_top_y = 10.0;    // world y of the flue mouth
uniform float soot_depth = 1.2;     // metres below the mouth to reach full soot
uniform float soot_max = 0.82;
uniform float brick_w = 0.22;
uniform float brick_h = 0.068;
uniform float joint = 0.013;
uniform float glow_bottom_y = -100.0; // world y of the warm/icy glow at the bottom
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.2, 1.0);
uniform float glow_reach = 1.2;
uniform float glow_energy = 0.0;
uniform float flicker = 1.0;          // driven by the fire (1 = steady)
uniform int mode = 0;                 // 0 = brick (smoke chamber), 1 = clay flue liner sections
uniform float liner_section = 0.6;    // clay liner tile length (m)

varying vec3 wp;
varying float below;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	below = soot_top_y - wp.y;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	bool xface = abs(wn.x) > abs(wn.z);
	vec2 w = xface ? vec2(wp.z, wp.y) : vec2(wp.x, wp.y);
	w.x += xface ? 0.11 : 0.0;  // offset the bond round the corners
	vec2 cell = vec2(brick_w + joint, brick_h + joint);
	vec2 b = w / cell;
	b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
	vec2 id = floor(b);
	vec2 f = fract(b) * cell;               // metres inside the cell
	float ex = min(f.x, cell.x - f.x) - joint * 0.5;
	float ey = min(f.y, cell.y - f.y) - joint * 0.5;
	float e = min(ex, ey);                  // distance to the brick edge (<0 = mortar)
	float h = hash(id);
	float h2 = hash(id + 17.3);
	bool missing = h2 > 0.975;              // a brick fallen out: a dark hole
	bool chipped = h2 > 0.9 && !missing;
	// chipped corners eat into the brick
	float chip = chipped ? smoothstep(0.035, 0.0, length(vec2(min(f.x, cell.x - f.x), min(f.y, cell.y - f.y))) - 0.02 * hash(id + 3.1)) : 0.0;
	float mortar = 1.0 - smoothstep(-0.001, 0.0015, e);
	float bevel = 1.0 - smoothstep(0.0, 0.006, e);
	vec3 col = brick_color.rgb * (0.7 + 0.5 * h);
	col = mix(col, col * vec3(1.15, 0.85, 0.75), h2 * 0.5);
	col *= 0.85 + 0.25 * vnoise(w * 45.0);   // grain
	col *= 1.0 - bevel * 0.35;
	col = mix(col, mortar_color.rgb, max(mortar, chip * 0.9));
	if (missing) {
		col = mortar_color.rgb * 0.35;
	}
	if (mode == 1) {
		// clay liner: smooth terracotta in 600 mm sections, a dark joint between them, grit
		float sy = fract(wp.y / liner_section) * liner_section;
		float jn = 1.0 - smoothstep(0.004, 0.008, min(sy, liner_section - sy));
		float sec = hash(vec2(floor(wp.y / liner_section), xface ? 1.0 : 2.0));
		col = vec3(0.6, 0.31, 0.19) * (0.85 + 0.25 * sec) * (0.88 + 0.2 * vnoise(w * 30.0));
		col = mix(col, mortar_color.rgb, jn);
		e = 0.01;
		missing = false;
		mortar = jn;
	}
	// soot: very black at the top, lifting a little lower down; blotchy, with creosote streaks
	float depth = clamp(below / soot_depth, 0.0, 1.0);
	float blotch = vnoise(w * vec2(6.0, 3.0)) * 0.35 + vnoise(w * 19.0) * 0.15;
	float streak_x = floor(w.x * 30.0);
	float streak = step(0.8, hash(vec2(streak_x, 4.2))) * smoothstep(0.0, 0.6, vnoise(vec2(streak_x, w.y * 2.5)));
	float topness = 1.0 - clamp((glow_bottom_y + glow_reach * 1.6 - wp.y) / max(glow_reach * 1.6, 0.01), 0.0, 1.0);
	float soot = clamp(0.55 + 0.4 * topness + blotch - 0.2 + depth * 0.1, 0.0, 0.97) * soot_max / 0.82;
	soot = max(soot, streak * 0.95);
	col = mix(col, soot_color.rgb, soot);
	ALBEDO = col;
	ROUGHNESS = 1.0 - streak * 0.55;        // creosote is glossy tar
	SPECULAR = 0.15 + streak * 0.4;
	// the fire's light climbing the walls: strongest just above the firebox, on brick faces more
	// than in the recessed joints, flickering
	float g = clamp(1.0 - (wp.y - glow_bottom_y) / glow_reach, 0.0, 1.0);
	float face = mix(0.25, 1.0, smoothstep(-0.001, 0.004, e)) * (missing ? 0.15 : 1.0);
	EMISSION = glow_color.rgb * glow_energy * flicker * g * g * face * (0.25 + 0.75 * (1.0 - soot * 0.7)) * 0.8;
}

void light() {
	// moonlight only reaches a little way down the flue
	float reach = LIGHT_IS_DIRECTIONAL ? 1.0 - smoothstep(0.05, 0.45, below) : 1.0;
	float wrap = clamp(clamp((dot(NORMAL, LIGHT) + 0.3) / 1.3, 0.0, 1.0) * ATTENUATION, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * wrap * wrap * (3.0 - 2.0 * wrap) * reach / PI;
}
