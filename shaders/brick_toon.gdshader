shader_type spatial;
// Chunky modelled bricks (one MultiMesh per chimney). Per-brick colour comes from the instance
// colour; the brick edges are darkened like a bevel so the mortar gaps read with depth.
// Same banded toon lighting as toon.gdshader.

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec3 brick_half = vec3(0.13, 0.05, 0.065);
uniform float edge_width = 0.014;
uniform float edge_dark = 0.3;
uniform float grit = 0.12;
uniform float bands = 3.0;
uniform float band_softness = 0.12;
uniform float rim_strength = 0.22;
uniform vec4 rim_color : source_color = vec4(1.0, 0.75, 0.5, 1.0);
uniform float emission_energy = 0.0;
// Frost (iced fire): whitens upward-facing surfaces.
uniform float frost = 0.0;

varying vec3 lp;
varying vec3 wp;
varying vec4 inst;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	lp = VERTEX;
	inst = COLOR;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 a = abs(lp) / brick_half;            // 1.0 on the faces
	vec3 d = (brick_half - abs(lp));           // distance to each face pair (m)
	// distance to the nearest edge on this face = second smallest of d
	float m1 = min(d.x, min(d.y, d.z));
	float m3 = max(d.x, max(d.y, d.z));
	float m2 = d.x + d.y + d.z - m1 - m3;
	float edge = 1.0 - smoothstep(0.0, edge_width, m2);
	vec3 col = albedo.rgb * inst.rgb;
	float g = hash3(floor(wp * 30.0));
	col *= 1.0 - grit * g;
	col *= 1.0 - edge * edge_dark;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	col = mix(col, vec3(0.86, 0.94, 1.0), frost * smoothstep(0.2, 0.8, wn.y + g * 0.3));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	rim = smoothstep(0.35, 0.75, rim);
	EMISSION = col * emission_energy + rim_color.rgb * col * rim * rim_strength;
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
