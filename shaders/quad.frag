#version 460 core

in vec4 Color;

layout (location = 0) out vec4 out_color;

void main() {
	out_color = Color;
}
