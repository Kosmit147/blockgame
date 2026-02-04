#version 460 core

in vec2 UV;
in vec4 Tint;

out vec4 out_color;

layout (binding = 0) uniform sampler2D texture_0;

void main() {
	out_color = Tint * texture(texture_0, UV);
}
