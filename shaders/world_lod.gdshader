shader_type spatial;
render_mode cull_back;
// Streamed-world mid LOD + skyline impostors + roads: plain vertex colours, COLOR.a = window glow.
uniform float glow_energy = 2.4;
uniform float rim_strength = 0.18;

void fragment() {
	ALBEDO = COLOR.rgb * (1.0 - COLOR.a * 0.6);
	EMISSION = COLOR.rgb * COLOR.a * glow_energy;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	RIM = rim_strength;
	RIM_TINT = 0.6;
}
