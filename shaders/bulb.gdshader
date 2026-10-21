shader_type spatial;
render_mode unshaded, cull_back;
// C9 Christmas bulb on a socket. Glass: saturated unshaded colour with a brighter core and a soft
// twinkle; socket (UV.y < 0.2): dark green plastic. Grows a little with camera distance so strings
// still read from afar without turning into big floating balls. Optional chase pulse.

uniform float energy = 1.8;
uniform float chase = 0.0;
uniform float chase_speed = 1.4;
uniform float twinkle = 0.18;
uniform float distance_scale_start = 18.0;
uniform float max_distance_scale = 2.2;

varying vec3 bulb_color;
varying float bulb_phase;
varying float bulb_rand;

void vertex() {
	bulb_color = COLOR.rgb;
	bulb_phase = INSTANCE_CUSTOM.x;
	bulb_rand = INSTANCE_CUSTOM.y;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length(origin - CAMERA_POSITION_WORLD);
	VERTEX *= clamp(d / distance_scale_start, 1.0, max_distance_scale);
}

void fragment() {
	if (UV.y < 0.2) {
		ALBEDO = vec3(0.03, 0.09, 0.04);
	} else {
		float tw = 1.0 - twinkle + twinkle * (0.5 + 0.5 * sin(TIME * (2.0 + bulb_rand * 3.0) + bulb_rand * 40.0));
		float pulse = tw;
		if (chase > 0.5) {
			float t = fract(bulb_phase - TIME * chase_speed);
			pulse = (0.5 + 0.85 * pow(t, 5.0)) * tw;
		}
		float core = 0.75 + 0.5 * pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		ALBEDO = bulb_color * energy * pulse * core;
	}
}
