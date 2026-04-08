#version 460 core

uniform float gamma;
layout (binding = 0) uniform sampler2D texture_0;

layout (location = 0) out vec4 out_color;

vec3 tone_mapping(vec3 v) {
	// return v / (v + 1.0); Reinhard tone mapping.
	return v;
}

vec3 gamma_correction(vec3 v) {
	return pow(v, vec3(1.0 / gamma));
}

void main() {
	vec4 tex_fetch = texelFetch(texture_0, ivec2(gl_FragCoord), 0);
	vec3 color = tex_fetch.rgb;
	float alpha = tex_fetch.a;

	color = tone_mapping(color);
	color = gamma_correction(color);

	out_color = vec4(color.rgb, alpha);
}
