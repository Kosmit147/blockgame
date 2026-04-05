#version 460 core

in float AmbientStrength;
in vec3 DiffuseLight;
in vec2 UV;

layout (std140, binding = 1) uniform Light_Data {
	vec3 light_ambient;
	vec3 light_color;
	vec3 light_direction;
};

layout (binding = 0) uniform sampler2D texture_0;

layout (location = 0) out vec4 out_color;

void main() {
	vec3 light = light_ambient * AmbientStrength + DiffuseLight;
	out_color = vec4(light, 1.0) * texture(texture_0, UV);
}
