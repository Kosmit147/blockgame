#version 460 core

out vec2 UV;

vec2 positions[4] = vec2[](
	vec2(-1.0,  1.0), // Top-left
	vec2( 1.0,  1.0), // Top-right
	vec2(-1.0, -1.0), // Bottom-left
	vec2( 1.0, -1.0)  // Bottom-right
);

vec2 uvs[4] = vec2[](
	vec2(0.0, 1.0), // Top-left
	vec2(1.0, 1.0), // Top-right
	vec2(0.0, 0.0), // Bottom-left
	vec2(1.0, 0.0)  // Bottom-right
);

void main() {
	UV = uvs[gl_VertexID];
	gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0);
}
