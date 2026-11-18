shader_type spatial;
// Inverted-hull outline: the dark ink edge around every ring.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.1, 0.0, 0.0, 1.0);
uniform float width = 0.022;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
