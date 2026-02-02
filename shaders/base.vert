#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal; // Currently unused.
layout (location = 2) in vec2 in_uv;

layout (std140, binding = 0) uniform View_Projection {
	mat4 view;
	mat4 projection;
};

uniform mat4 model;

out vec2 UV;

void main() {
	UV = in_uv;
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
