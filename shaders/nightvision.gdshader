shader_type canvas_item;
// Glow-Gogs night vision: lifts the dark, tints everything green, film grain, scanlines, vignette.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 1.0;
uniform float gain = 2.4;
uniform float grain = 0.12;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.3, 0.55, 0.15));
	l = 1.0 - exp(-l * gain * 2.0);
	float n = fract(sin(dot(SCREEN_UV * 1000.0 + fract(TIME * 7.13) * 91.7, vec2(12.9898, 78.233))) * 43758.5453);
	l += (n - 0.5) * grain;
	l *= 0.92 + 0.08 * sin(SCREEN_UV.y * 900.0);
	vec2 d = SCREEN_UV - 0.5;
	float vig = smoothstep(0.85, 0.35, length(d * vec2(1.6, 1.0)));
	vec3 nv = vec3(0.25, 1.0, 0.35) * l * vig;
	COLOR = vec4(mix(c, nv, strength), 1.0);
}
