shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
// Far-LOD impostor lights: one camera-facing soft dot per house window / string of Christmas lights / streetlight.
// Dots keep a minimum on-screen size with distance so whole suburbs read as glittering light carpets.
uniform float energy = 1.6;
uniform float base_size = 1.6;
uniform float grow = 0.0016;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length(origin - CAMERA_POSITION_WORLD);
	float s = max(base_size, d * grow) * (0.7 + INSTANCE_CUSTOM.x * 0.6);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1], MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	VERTEX *= s;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a;
	ALBEDO = COLOR.rgb * energy * a;
	ALPHA = a;
}
