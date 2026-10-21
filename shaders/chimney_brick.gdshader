shader_type spatial;
// Chimney bricks drawn on the stack surface. UV is in metres along the brick courses (UV.x runs
// round the stack, UV.y is height), so every brick has the same real size on every face - no
// stretching. Running bond, sunken mortar, bevelled edges, per-brick colour, a few chipped and
// sooty bricks, soot darkening up near the crown, frost on top faces when iced.
// cap_mode 1 = the concrete crown cap instead (patchy concrete, sooty round the flue hole).
// Same banded toon lighting as toon.gdshader.

uniform float brick_l = 0.22;
uniform float brick_h = 0.068;
uniform float joint = 0.013;
uniform vec4 brick_a : source_color = vec4(0.72, 0.30, 0.21, 1.0);
uniform vec4 brick_b : source_color = vec4(0.62, 0.25, 0.19, 1.0);
uniform vec4 brick_c : source_color = vec4(0.80, 0.42, 0.28, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.62, 0.58, 0.53, 1.0);
uniform vec4 soot_color : source_color = vec4(0.13, 0.10, 0.09, 1.0);
uniform float soot_y0 = 0.6;   // local height where soot starts
uniform float soot_y1 = 1.2;   // local height of full soot
uniform float soot_max = 0.55;
uniform int cap_mode = 0;
uniform vec4 cap_color : source_color = vec4(0.56, 0.55, 0.56, 1.0);
uniform vec2 cap_center = vec2(0.0);
uniform float cap_hole = 0.17;  // half size of the flue hole
uniform float frost = 0.0;
uniform float bands = 3.0;
uniform float band_softness = 0.12;
uniform float rim_strength = 0.18;
uniform vec4 rim_color : source_color = vec4(1.0, 0.75, 0.5, 1.0);

varying vec3 lp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 col;
	float g = hash(floor(lp.xz * 40.0) + floor(lp.y * 40.0) * 7.1);
	if (cap_mode == 1) {
		col = cap_color.rgb * (0.94 + 0.06 * hash(floor(lp.xz * 9.0)) - 0.07 * g);
		float d = max(abs(lp.x - cap_center.x), abs(lp.z - cap_center.y)) - cap_hole;
		float s = 1.0 - smoothstep(0.0, 0.17 + 0.05 * hash(floor(lp.xz * 25.0)), d);
		col = mix(col, soot_color.rgb * 0.5, s * s * 0.95);
	} else {
		vec2 b = UV / vec2(brick_l + joint, brick_h + joint);
		float row = floor(b.y);
		b.x += mod(row, 2.0) * 0.5;
		vec2 id = floor(b);
		vec2 f = fract(b) * vec2(brick_l + joint, brick_h + joint);  // metres inside the cell
		vec2 e = min(f, vec2(brick_l + joint, brick_h + joint) - f);
		float m = min(e.x, e.y);
		float mortar = 1.0 - smoothstep(joint * 0.5 - 0.0015, joint * 0.5 + 0.0015, m);
		float bevel = 1.0 - smoothstep(joint * 0.5, joint * 0.5 + 0.012, m);
		float h = hash(id);
		float h2 = hash(id + 17.3);
		vec3 bc = h < 0.4 ? brick_a.rgb : (h < 0.75 ? brick_b.rgb : brick_c.rgb);
		bc *= 0.9 + 0.2 * h2;
		bc *= 1.0 - 0.1 * g;
		// top edge of each brick catches a little light, bottom edge is in shade
		float top = 1.0 - smoothstep(0.0, 0.01, (brick_h + joint) - joint * 0.5 - f.y);
		bc *= 1.0 - bevel * 0.32;
		bc *= 1.0 + top * 0.12;
		// chipped corner on a few bricks
		float chip = step(0.86, hash(id + 5.1));
		vec2 cc = vec2(hash(id + 9.0) > 0.5 ? joint * 0.5 : brick_l + joint * 0.5, joint * 0.5);
		bc = mix(bc, mortar_color.rgb * 0.7, chip * (1.0 - smoothstep(0.015, 0.03, length(f - cc))));
		// the odd sooty / burnt brick
		bc *= 1.0 - 0.35 * step(0.93, hash(id + 2.7));
		col = mix(bc, mortar_color.rgb * (0.85 + 0.15 * g), mortar);
		col *= 1.0 - mortar * 0.15;
		float sy = smoothstep(soot_y0, soot_y1, lp.y) * soot_max;
		float streak = hash(vec2(floor(UV.x * 14.0), 4.0));
		col = mix(col, soot_color.rgb, clamp(sy * (0.6 + 0.6 * streak), 0.0, 0.9));
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	col = mix(col, vec3(0.86, 0.94, 1.0), frost * smoothstep(0.3, 0.8, wn.y + g * 0.3));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	rim = smoothstep(0.35, 0.75, rim);
	EMISSION = rim_color.rgb * col * rim * rim_strength;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float b;
	if (LIGHT_IS_DIRECTIONAL) {
		float x = ndl * bands;
		b = (floor(x) + smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(x))) / bands;
	} else {
		float wrap = clamp(clamp((dot(NORMAL, LIGHT) + 0.35) / 1.35, 0.0, 1.0) * ATTENUATION, 0.0, 1.0);
		b = wrap * wrap * (3.0 - 2.0 * wrap);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * b / PI;
}
