#version 400 core

in vec2 FragTextureCoord;

out vec4 FragColor;

uniform sampler2D spritesheet;

uniform int numCols;
uniform float timePerSprite;
uniform float age;

void main() {
  // Doing this for every fragment is pretty wasteful...
  int col = int(age / timePerSprite);
  vec2 spriteTexCoord = vec2(FragTextureCoord.x / numCols + col * (1.0 / numCols), FragTextureCoord.y);
  // TODO interpolation
  FragColor = texture(spritesheet, spriteTexCoord);
}
