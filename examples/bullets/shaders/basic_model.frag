#version 400 core

in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;

uniform int mesh_id;
uniform vec3 ambientLight;
uniform vec3 lightColor;
uniform vec3 lightDirection;
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
    }  else {
        if (hasColor == 1) {
           color = diffuseColor;
        } else {
           color = fragColor;
        }
    }

//    vec4 color = vec4(0.5, 0.5, 0.3, 0.2);
    fragFinalColor = color;

//    color = color + hitColor;
//    vec3 ambient = ambientLight;
//    vec3 diffuse = max(dot(fragNormal, lightDirection), 0.0) * lightColor;
    // fragFinalColor = color * vec4((ambient + diffuse), 1.0f);

//    fragFinalColor = vec4(color.rgb, colorAlpha);
    // fragFinalColor = color * vec4((ambient), 1.0f);
    // fragFinalColor = color * vec4((ambient + diffuse), 1.0f);
    // fragFinalColor = texture(textureDiffuse, fragTexCoord);
    // fragFinalColor = color + texture(textureDiffuse, fragTexCoord) + hitColor;
    // fragFinalColor = vec4(0.8, 0.2, 0.2, 1.0);
    // fragFinalColor = fragFinalColor;
}
