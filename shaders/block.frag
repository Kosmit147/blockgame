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
  float shadow_bias = max(0.05 * (1.0 - dot(Normal, -light_direction)), 0.005);

  vec4 clip = LightSpacePosition / LightSpacePosition.w;
  vec4 ndc = clip * 0.5 + 0.5;

  float current_depth = ndc.z;
  if (current_depth > 1.0)
    current_depth = 1.0;

  vec2 texel_size = 1.0 / textureSize(shadow_map, 0);

  float shadow = 0.0;
  for (int x = -1; x <= 1; x++) {
    for (int y = -1; y <= 1; y++) {
      float depth = texture(shadow_map, ndc.xy + vec2(x, y) * texel_size).r;
      shadow += current_depth - shadow_bias > depth ? 1.0 : 0.0;
    }
  }

  return shadow / 9.0;
}

void main() {
  float diffuse_factor = 1.0 - shadow_factor();
  vec3 light = light_ambient * AmbientStrength + DiffuseLight * diffuse_factor;
  out_color = vec4(light, 1.0) * texture(block_texture, UV);
}
