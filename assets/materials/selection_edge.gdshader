shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 edge_color : source_color = vec4(1.0, 0.65, 0.2, 1.0);
uniform float width_pixels = 2.2;

void vertex() {
	vec4 here = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 other = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	if (here.w <= 0.001 || other.w <= 0.001) {
		POSITION = vec4(0.0, 0.0, 2.0, 1.0);
	} else {
		vec2 direction = (other.xy / other.w - here.xy / here.w) * VIEWPORT_SIZE * UV.y;
		direction /= max(length(direction), 0.001);
		vec2 perpendicular = vec2(-direction.y, direction.x);
		POSITION = here;
		POSITION.xy += perpendicular * UV.x * width_pixels / VIEWPORT_SIZE * here.w;
		// Reversed Z: a small forward bias prevents coplanar edge flicker.
		POSITION.z += 0.00002 * here.w;
	}
}

void fragment() {
	ALBEDO = edge_color.rgb;
}
