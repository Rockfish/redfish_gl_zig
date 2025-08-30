#version 400 core

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragLightSpacePosition;

struct DirectionLight {
  vec3 dir;
  vec3 color;
};

uniform DirectionLight directionLight;

uniform int hasColor;
uniform int hasTexture;

uniform vec4 diffuseColor;
uniform vec4 ambientColor;
uniform vec4 specularColor;
uniform vec4 emissiveColor;


uniform sampler2D textureDiffuse;
uniform sampler2D textureNormal;
//uniform sampler2D textureSpecular;

uniform float colorAlpha;
uniform bool useLight;
uniform vec3 ambient;

out vec4 fragFinalColor;

void main() {
  vec4 color = vec4(1.0, 0.0, 0.0, 1.0);

  if (hasTexture == 1) {
     color = texture(textureDiffuse, fragTexCoord);
  } else {
     if (hasColor == 1) {
        color = diffuseColor;
     }
  }

  if (useLight) {
    vec3 lightDir = normalize(-directionLight.dir);
    vec3 normal = vec3(texture(textureNormal, fragTexCoord));
    normal = normalize(normal * 2.0 - 1.0);
    float diff = max(dot(normal, lightDir), 0.0);
    vec3 amb = ambient * vec3(texture(textureDiffuse, fragTexCoord));
    color = vec4(directionLight.color, 1.0) * color * diff + vec4(amb, 1.0);
  }

  fragFinalColor = vec4(color.rgb, colorAlpha);
}

