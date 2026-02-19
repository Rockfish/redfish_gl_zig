#version 400 core

in vec2 fragTextureCoord;

out vec4 fragColor;

uniform sampler2D base_texture;
uniform sampler2D emission_texture;
uniform sampler2D bright_texture;

//uniform bool lagSystemOut;

float CalcBrightness(vec3 col) {
  return (col.x + col.y + col.z) / (3 );
}

vec4 ScaleColor(float scale, vec4 color) {
  return vec4(min(1.0, scale * color.r), min(1.0, scale * color.g), min(1.0, scale * color.b), color.a);
}

void main() {

  fragColor = vec4(texture(base_texture, fragTextureCoord).rgb + texture(emission_texture, fragTextureCoord).rgb * 2.9, 1.0);

  vec3 rawBright = texture(bright_texture, fragTextureCoord).rgb;

  if (CalcBrightness(rawBright) > 0.05) {
    float mult = 1.5;
    float additive = CalcBrightness(rawBright) > 0.3 ? 1.8 : 0.4;
    fragColor += vec4(mult * rawBright + vec3(2 * additive, 0.6 * additive, 0.6 * additive), 1.0);
  }
}

