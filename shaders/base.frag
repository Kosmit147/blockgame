#version 460 core

in vec2 UV;

out vec4 outColor;

layout (binding = 0) uniform sampler2D texture0;

void main() {
	outColor = texture(texture0, UV);
}
