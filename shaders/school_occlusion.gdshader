shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform vec4 base : source_color;
uniform float rough = 0.8;
uniform float grain_scale = 0.0;
uniform bool whole_object = false;
uniform float object_opacity = 1.0;
varying vec3 wp;

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float noise(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

void fragment() {
	float grain = grain_scale > 0.0 ? 0.98 + 0.04 * noise(floor(wp * grain_scale)) : 1.0;
	ALBEDO = base.rgb * grain;
	ROUGHNESS = rough;
	METALLIC = 0.035;
	ALPHA = whole_object ? object_opacity : 1.0;
}
