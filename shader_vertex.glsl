#version 460 core

layout (location = 0) in vec3 inPosition;
layout (location = 1) in vec3 inNormal; // Currently unused.
layout (location = 2) in vec2 inUV;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec2 UV;

void main() {
	UV = inUV;
	gl_Position = projection * view * model * vec4(inPosition, 1);
}
