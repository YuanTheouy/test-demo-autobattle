shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 wind_color : source_color = vec3(0.48, 0.87, 0.76);

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float height_fade = smoothstep(0.0, 0.045, UV.y) * (1.0 - smoothstep(0.955, 1.0, UV.y));
	ALBEDO = wind_color;
	ALPHA = (0.022 + 0.055 * rim) * height_fade;
}
