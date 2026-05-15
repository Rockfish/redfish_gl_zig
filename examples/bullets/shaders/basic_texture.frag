#version 400 core

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragLightSpacePosition;

struct DirectionLight {
  vec3 dir;
  vec3 color;
};

struct PointLight {
  vec3 worldPos;
  vec3 color;
  float constant;
  float linear;
  float quadratic;
};

const int MAX_POINT_LIGHTS = 4;

uniform DirectionLight directionLight;
uniform PointLight pointLights[MAX_POINT_LIGHTS];
uniform int numPointLights;

uniform int hasColor;
uniform int hasTexture;

uniform vec4 diffuseColor;
uniform vec4 ambientColor;
uniform vec4 specularColor;
uniform vec4 emissiveColor;


uniform sampler2D textureDiffuse;
uniform sampler2D textureNormal;
uniform sampler2D textureSpec;

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
    vec3 normal = vec3(texture(textureNormal, fragTexCoord));
    normal = normalize(normal * 2.0 - 1.0);

    // Direction light
    vec3 lightDir = normalize(-directionLight.dir);
    float diff = max(dot(normal, lightDir), 0.0);
    vec3 lighting = directionLight.color * diff;

    // Point lights
    for (int i = 0; i < numPointLights; i++) {
      float dist = length(pointLights[i].worldPos - fragPosition);
      float attenuation = 1.0 / (pointLights[i].constant
                                + pointLights[i].linear * dist
                                + pointLights[i].quadratic * dist * dist);
      vec3 ptDir = normalize(pointLights[i].worldPos - fragPosition);
      float ptDiff = max(dot(normal, ptDir), 0.0);
      lighting += pointLights[i].color * ptDiff * attenuation;
    }

    // Specular map modulates highlight intensity
    float spec = texture(textureSpec, fragTexCoord).r;
    lighting += lighting * spec * 0.3;

    vec3 amb = ambient * vec3(texture(textureDiffuse, fragTexCoord));
    color = vec4(lighting, 1.0) * color + vec4(amb, 1.0);
  }

  fragFinalColor = vec4(color.rgb, colorAlpha);
}
