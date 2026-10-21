shader_type spatial;
// Faint additive headlight cone (Rudolph's nose beam). Brightest at the nose, fading toward the far
// end and soft at the silhouette, so it reads like a beam in night air. "along" is derived from the
// cone radius (narrow at the nose), so it doesn't depend on the mesh's axis orientation.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.3, 0.2, 1.0);
uniform float intensity = 0.25;
uniform float far_radius = 8.0;
uniform float edge_softness = 1.2;

varying float along;

void vertex() {
	along = 1.0 - clamp(length(VERTEX.xz) / far_radius, 0.0, 1.0); // 1 at the nose, 0 at the far end
}

void fragment() {
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), edge_softness);
	float a = clamp(pow(along, 1.2) * edge, 0.0, 1.0);
	ALBEDO = clamp(color.rgb * intensity * a, vec3(0.0), vec3(1.0));
}
