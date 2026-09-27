shader_type spatial;
render_mode diffuse_burley;

varying vec3 world_position;
uniform vec4 floor_color : source_color = vec4(0.49, 0.53, 0.54, 1.0);
uniform vec4 grid_color : source_color = vec4(0.38, 0.43, 0.44, 1.0);
uniform bool grid_enabled = true;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grid = world_position.xz;
	vec2 width = max(fwidth(grid), vec2(0.001));
	vec2 line = abs(fract(grid - 0.5) - 0.5) / width;
	float minor = 1.0 - min(min(line.x, line.y), 1.0);
	vec2 major_grid = grid / 5.0;
	vec2 major_line = abs(fract(major_grid - 0.5) - 0.5) / max(fwidth(major_grid), vec2(0.001));
	float major = 1.0 - min(min(major_line.x, major_line.y), 1.0);
	ALBEDO = mix(floor_color.rgb, grid_color.rgb, grid_enabled ? minor * 0.24 + major * 0.35 : 0.0);
	ROUGHNESS = 0.95;
}
