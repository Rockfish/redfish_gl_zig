#version 330 core
in vec2 FragTextureCoord;

out vec4 FragColor;

uniform bool greyscale;

uniform sampler2D tex;

void main() {
  if (greyscale) {
    FragColor = vec4(vec3(texture(tex, FragTextureCoord).r), 1.0);
  } else {
    FragColor = texture(tex, FragTextureCoord);
  }
}

