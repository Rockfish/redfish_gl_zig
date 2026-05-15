#version 400 core

in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;

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
uniform bool useLight;
uniform vec3 ambient;

uniform int mesh_id;
uniform vec4 hitColor;
uniform float colorAlpha;

uniform int hasColor;
uniform int hasTexture;

uniform vec4 diffuseColor;
uniform vec4 ambientColor;
uniform vec4 specularColor;
uniform vec4 emissiveColor;

uniform sampler2D textureDiffuse;

out vec4 fragFinalColor;

void main()
{
    vec4 color = vec4(1.0, 0.0, 0.0, 1.0);

    if (hasTexture == 1) {
        color = texture(textureDiffuse, fragTexCoord);
    } else {
        if (hasColor == 1) {
           color = diffuseColor;
        } else {
           color = fragColor;
        }
    }

    if (useLight) {
        vec3 normal = normalize(fragNormal);

        // Direction light
        vec3 lightDir = normalize(-directionLight.dir);
        float diff = max(dot(normal, lightDir), 0.0);
        vec3 lighting = directionLight.color * diff;

        // Point lights (normal-only contribution, no world position available)
        for (int i = 0; i < numPointLights; i++) {
            vec3 ptDir = normalize(pointLights[i].worldPos);
            float ptDiff = max(dot(normal, ptDir), 0.0);
            lighting += pointLights[i].color * ptDiff;
        }

        color = vec4((ambient + lighting), 1.0) * color;
    }

    fragFinalColor = color;
}
