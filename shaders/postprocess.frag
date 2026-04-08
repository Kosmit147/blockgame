#version 460 core

layout (binding = 0) uniform sampler2D texture_0;

layout (location = 0) out vec4 out_color;

void main() {
	out_color = texelFetch(texture_0, ivec2(gl_FragCoord), 0);
}
