shader_type spatial;
render_mode cull_back;

uniform vec4 tint : source_color = vec4(1.0);
uniform float cell_size = 1.0;
uniform vec3 base_color : source_color = vec3(0.55);
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = abs(normalize(world_normal));
	vec2 p = world_position.xz;
	if (n.x > n.y && n.x > n.z) {
		p = world_position.zy;
	} else if (n.z > n.y) {
		p = world_position.xy;
	}
	p /= cell_size;
	vec2 w = max(fwidth(p), vec2(0.0001));
	vec2 grid_distance = abs(fract(p + 0.5) - 0.5) / w;
	float grid = 1.0 - smoothstep(0.25, 1.15, min(grid_distance.x, grid_distance.y));
	vec2 major_distance = abs(fract(p / 5.0 + 0.5) - 0.5) / (w / 5.0);
	float major = 1.0 - smoothstep(0.4, 1.3, min(major_distance.x, major_distance.y));
	float fade = 1.0 - smoothstep(18.0, 65.0, distance(world_position, CAMERA_POSITION_WORLD));
	float detail = (grid * 0.045 + major * 0.045) * fade;
	ALBEDO = max(base_color - vec3(detail), vec3(0.0)) * tint.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}
