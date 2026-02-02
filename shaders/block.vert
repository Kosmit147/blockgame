#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_uv;

layout (std140, binding = 0) uniform View_Projection {
	mat4 view;
	mat4 projection;
};

layout (std140, binding = 1) uniform Light_Data {
	vec3 light_direction;
};

uniform mat4 model;

out flat vec3 Light;
out vec2 UV;

vec3 ambient() {
	return vec3(0.3);
}

vec3 diffuse() {
	float strength = dot(-light_direction, in_normal);
	strength = max(strength, 0.0);
	return vec3(strength);
}

// Gourard lighting with no specular component.
vec3 flat_gourard() {
	return ambient() + diffuse();
}

void main() {
	UV = in_uv;
	Light = flat_gourard();
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
