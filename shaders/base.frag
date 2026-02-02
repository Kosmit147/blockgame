#version 460 core

in vec3 Light;
in vec2 UV;

out vec4 out_color;

layout (binding = 0) uniform sampler2D texture_0;

void main() {
	out_color = vec4(Light, 1.0) * texture(texture_0, UV);
}
