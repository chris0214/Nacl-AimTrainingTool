shader_type canvas_item;
render_mode unshaded;

uniform sampler2D lens_texture : filter_linear, repeat_disable;
uniform vec2 canvas_size = vec2(1440.0, 900.0);
uniform float distortion : hint_range(0.0, 1.0) = 0.4;
uniform float edge_shade : hint_range(0.0, 1.0) = 0.2;

void fragment() {
	float radius = min(canvas_size.x, canvas_size.y) * 0.4;
	vec2 p = (UV - vec2(0.5)) * canvas_size / radius;
	float r = length(p);
	// Leave the central 55% exactly rectilinear; only bend the periphery.
	float edge = smoothstep(0.55, 1.0, r);
	vec2 sample_uv = vec2(0.5) + p * (1.0 - 0.16 * distortion * edge * edge) * 0.5;
	vec3 scene = texture(lens_texture, sample_uv).rgb;
	scene *= 1.0 - edge_shade * smoothstep(0.72, 1.0, r);
	float coverage = 1.0 - smoothstep(1.0 - fwidth(r), 1.0, r);
	COLOR = vec4(scene, coverage);
}
