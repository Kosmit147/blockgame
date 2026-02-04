#version 460 core

layout (location = 0) in vec2 in_position;
layout (location = 1) in vec2 in_uv;
layout (location = 2) in vec4 in_tint;

out vec2 UV;
out vec4 Tint;

void main() {
	UV = in_uv;
	Tint = in_tint;
	gl_Position = vec4(in_position, 0.0, 1.0);
}
