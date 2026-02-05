#version 460 core

layout (location = 0) in vec3 in_position;

layout (std140, binding = 0) uniform View_Projection {
	mat4 view;
	mat4 projection;
};

uniform mat4 model;
uniform vec4 color;

out flat vec4 Color;

void main() {
	Color = color;
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
