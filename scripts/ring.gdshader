shader_type spatial;
// Glossy candy ring: lit colour + rim glow, like the neon-on-black concept art.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float glow = 0.22;
uniform float flash = 0.0;
uniform float dim = 1.0;

void fragment() {
	vec3 c = base_color.rgb;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 2.2);
	ALBEDO = c * dim;
	ROUGHNESS = 0.16;
	SPECULAR = 0.75;
	EMISSION = (c * (glow + rim * 0.85) + vec3(flash)) * dim;
}
