shader_type spatial;
// Painterly toon shading for the Hello Neighbor-style look:
// banded diffuse (soft band edges), toon rim light, optional toon specular glint,
// optional visual-only warp (bend/bulge along height) and painterly colour patches.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float emission_energy = 0.0;
uniform float bands = 3.0;
uniform float band_softness = 0.1;
uniform float rim_strength = 0.28;
uniform float rim_power = 2.5;
uniform vec4 rim_color : source_color = vec4(1.0, 0.75, 0.5, 1.0);
uniform float specular_strength = 0.0;

// Visual-only warp. Collision never sees this.
uniform float bend = 0.0;
uniform float bulge = 0.0;
uniform float warp_height = 1.0;
uniform float warp_phase = 0.0;

// Painterly patches by world position (ground, roofs).
uniform float patch_strength = 0.0;
uniform vec4 patch_color : source_color = vec4(1.0);
uniform float patch_scale = 0.08;

// Optional lighter/warmer underside (gum-tree canopies catching bounce light).
uniform float underside_light = 0.0;
uniform vec4 underside_color : source_color = vec4(0.7, 0.85, 0.45, 1.0);
// Local (omni/spot) lights are soft and painterly instead of banded, so small lamps make
// gentle pools rather than hard-edged discs. Directional lights keep the toon bands.
uniform float local_light_softness = 1.0;

// Cut-outs (window openings in the house shell, the flue through the roof): fragments whose
// pre-warp object-space position lies inside any [hole_min, hole_max] box are discarded.
uniform int hole_count = 0;
uniform vec3 hole_min[16];
uniform vec3 hole_max[16];

// Painted surface patterns in world space (interiors): 0 none, 1 wallpaper stripes,
// 2 wallpaper dots, 3 floorboards, 4 checker tiles, 5 bricks, 6 carpet speckle.
uniform int pattern = 0;
uniform vec4 pattern_color : source_color = vec4(1.0);
uniform float pattern_scale = 1.0;

varying vec3 world_pos;
varying vec3 raw_local;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	raw_local = VERTEX;
	if (bend != 0.0 || bulge != 0.0) {
		float t = clamp(VERTEX.y / warp_height + 0.5, 0.0, 1.0);
		float s = sin(t * PI);
		VERTEX.xz *= 1.0 + bulge * s;
		VERTEX.x += bend * s;
		VERTEX.z += bend * 0.5 * sin(t * PI * 2.0 + warp_phase);
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float pattern_mask(vec3 n) {
	vec3 p = world_pos / pattern_scale;
	// wall coordinate: along the wall (x or z, whichever the wall runs along) and height
	vec2 w = abs(n.x) > abs(n.z) ? vec2(p.z, p.y) : vec2(p.x, p.y);
	if (pattern == 1) {
		float u = fract(w.x * 2.2);
		return smoothstep(0.02, 0.06, u) * (1.0 - smoothstep(0.30, 0.34, u)) * 0.85 + step(0.55, u) * (1.0 - step(0.6, u)) * 0.5;
	} else if (pattern == 2) {
		vec2 g = w * vec2(3.0, 3.0);
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		return 1.0 - smoothstep(0.16, 0.2, length(fract(g) - 0.5));
	} else if (pattern == 3) {
		float row = floor(p.z * 4.5);
		float x = p.x * 0.8 + hash(vec2(row, 3.1)) * 7.0;
		float seam = 1.0 - smoothstep(0.0, 0.035, min(fract(p.z * 4.5), 1.0 - fract(p.z * 4.5)));
		float joint = 1.0 - smoothstep(0.0, 0.01, min(fract(x), 1.0 - fract(x)));
		float grain = hash(vec2(row, floor(x))) * 0.35;
		return clamp(max(seam, joint) + grain, 0.0, 1.0);
	} else if (pattern == 4) {
		vec2 g = floor(p.xz * 2.5);
		return mod(g.x + g.y, 2.0);
	} else if (pattern == 5) {
		vec2 b = w * vec2(3.6, 7.5);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = fract(b);
		float mortar = 1.0 - smoothstep(0.0, 0.07, min(min(f.x, 1.0 - f.x) * 0.5, min(f.y, 1.0 - f.y)));
		float shade = hash(floor(b)) * 0.35;
		return clamp(mortar + shade * (1.0 - mortar) * 0.6, 0.0, 1.0);
	} else if (pattern == 6) {
		return vnoise(p.xz * 30.0) * 0.6 + vnoise(p.xz * 7.0) * 0.4;
	}
	return 0.0;
}

void fragment() {
	for (int i = 0; i < hole_count; i++) {
		if (all(greaterThan(raw_local, hole_min[i])) && all(lessThan(raw_local, hole_max[i]))) {
			discard;
		}
	}
	vec3 col = albedo.rgb;
	if (pattern > 0) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		col = mix(col, pattern_color.rgb, pattern_mask(wn));
	}
	if (patch_strength > 0.0) {
		float n = vnoise(world_pos.xz * patch_scale) * 0.65 + vnoise(world_pos.xz * patch_scale * 3.1) * 0.35;
		col = mix(col, patch_color.rgb, smoothstep(0.45, 0.62, n) * patch_strength);
	}
	if (underside_light > 0.0) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		col = mix(col, underside_color.rgb, underside_light * smoothstep(0.15, -0.55, wn.y));
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	rim = smoothstep(0.35, 0.75, rim);
	EMISSION = col * emission_energy + rim_color.rgb * mix(vec3(1.0), col, 0.5) * rim * rim_strength;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float b;
	if (LIGHT_IS_DIRECTIONAL || local_light_softness <= 0.0) {
		float x = ndl * bands;
		b = (floor(x) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(x))) / bands;
	} else {
		// Half-wrapped, smooth falloff for lamps and Christmas-light spill.
		// Clamp AFTER attenuation: right next to a lamp ATTENUATION is far above 1, and the
		// smoothstep polynomial then went hugely negative (black discs with glow halos).
		float wrap = clamp(clamp((dot(NORMAL, LIGHT) + 0.35) / 1.35, 0.0, 1.0) * ATTENUATION, 0.0, 1.0);
		b = wrap * wrap * (3.0 - 2.0 * wrap);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * b / PI;
	if (specular_strength > 0.0) {
		vec3 h = normalize(LIGHT + VIEW + vec3(0.0, 1e-4, 0.0));
		float s = smoothstep(0.95, 0.97, dot(NORMAL, h)) * ATTENUATION;
		SPECULAR_LIGHT += LIGHT_COLOR * s * specular_strength / PI;
	}
}
