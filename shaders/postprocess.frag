#version 460 core

uniform float gamma;
layout (binding = 0) uniform sampler2D texture_0;

layout (location = 0) out vec4 out_color;

void main() {
	vec4 tex_color = texelFetch(texture_0, ivec2(gl_FragCoord), 0);
	tex_color.rgb = pow(tex_color.rgb, vec3(1.0 / gamma));
	out_color = tex_color;
}
