#version 330 core

in vec2 fragTexCoord;
in vec3 fragNormal;
in vec4 fragColor;

uniform int mesh_id;

uniform vec3 ambient_light;
uniform vec3 light_color;
uniform vec3 light_dir;
uniform vec4 hit_color;

uniform int hasColor;
uniform int hasTexture;

uniform vec4 diffuseColor;
uniform vec4 ambientColor;
uniform vec4 specularColor;
uniform vec4 emissiveColor;

uniform sampler2D textureDiffuse;


// Output fragment color
out vec4 finalColor;

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

    if (color.a < 0.1) {
        discard;
    }

    vec3 ambient = ambient_light;
    vec3 diffuse = max(dot(fragNormal, light_dir), 0.0) * light_color;

    finalColor = color;
    // finalColor = color * vec4((ambient), 1.0f);
    // finalColor = color * vec4((ambient + diffuse), 1.0f);
    // finalColor = texture(textureDiffuse, fragTexCoord);
    // finalColor = color + texture(textureDiffuse, fragTexCoord) + hit_color;
    // finalColor = vec4(0.8, 0.2, 0.2, 1.0);
    // finalColor = fragColor;
}
