#version 460 core

in float AmbientStrength;
in vec3 Normal;
in vec3 DiffuseLight;
in vec2 UV;
in vec4 LightSpacePosition;

layout (std140, binding = 1) uniform Light_Data {
  mat4 light_view;
  mat4 light_projection;
  vec3 light_ambient;
  vec3 light_color;
  vec3 light_direction;
};

layout (binding = 0) uniform sampler2D block_texture;
layout (binding = 1) uniform sampler2D shadow_map;

layout (location = 0) out vec4 out_color;

float shadow_factor() {
  vec4 clip = LightSpacePosition / LightSpacePosition.w;
  vec4 ndc = clip * 0.5 + 0.5;

  float closest_depth = texture(shadow_map, ndc.xy).r;
  float current_depth = ndc.z;

  if (current_depth > 1.0)
    current_depth = 1.0;

  float shadow_bias = max(0.05 * (1.0 - dot(Normal, -light_direction)), 0.005);
  float shadow = current_depth - shadow_bias > closest_depth ? 1.0 : 0.0;
  return shadow;
}

void main() {
  float diffuse_factor = 1.0 - shadow_factor();
  vec3 light = light_ambient * AmbientStrength + DiffuseLight * diffuse_factor;
  out_color = vec4(light, 1.0) * texture(block_texture, UV);
}
