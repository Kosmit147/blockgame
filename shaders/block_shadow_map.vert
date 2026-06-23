#version 460 core

layout (location = 0) in vec3 in_position;
layout (location = 1) in vec3 in_normal;
layout (location = 2) in vec2 in_uv;
layout (location = 3) in uint in_ambient_occlusion;

layout (std140, binding = 1) uniform Light_Data {
  mat4 light_view;
  mat4 light_projection;
  vec3 light_ambient;
  vec3 light_color;
  vec3 light_direction;
};

uniform mat4 model;

void main() {
  gl_Position = light_projection * light_view * model * vec4(in_position, 1.0);
}
