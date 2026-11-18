shader_type spatial;
// Soft radial blob: contact shadows and the glowing stage floor.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 center_color : source_color = vec4(0.0, 0.0, 0.0, 0.8);
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float power = 1.6;

void fragment() {
	float d = clamp(length(UV - vec2(0.5)) * 2.0, 0.0, 1.0);
	vec4 c = mix(center_color, edge_color, pow(d, power));
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
