#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_uv;
layout (location = 3) in uint in_ambient_occlusion;

layout (std140, binding = 0) uniform View_Projection {
	mat4 view;
	mat4 projection;
};

layout (std140, binding = 1) uniform Light_Data {
	vec3 light_ambient;
	vec3 light_color;
	vec3 light_direction;
};

uniform mat4 model;

out float AmbientStrength;
out flat vec3 DiffuseLight;
out vec2 UV;

float ambient_strength[9] = float[](
	1.0,   // 0
	1.0,   // 1
	1.0,   // 2
	1.0,   // 3
	1.0,   // 4
	0.875, // 5
	0.75,  // 6
	0.5,   // 7
	0.0    // 8
);

vec3 diffuse() {
	float strength = dot(-light_direction, in_normal);
	strength = max(strength, 0.0);
	return strength * light_color;
}

void main() {
	AmbientStrength = ambient_strength[in_ambient_occlusion];
	DiffuseLight = diffuse();
	UV = in_uv;
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
